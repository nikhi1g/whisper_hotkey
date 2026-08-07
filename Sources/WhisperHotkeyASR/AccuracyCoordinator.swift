import Foundation
import WhisperHotkeyCore

public struct AccuracyDecision: Equatable, Sendable {
    public let selected: RecognitionHypothesis
    public let alternatives: [RecognitionHypothesis]
    public let trace: TranscriptDecisionTrace

    public init(
        selected: RecognitionHypothesis,
        alternatives: [RecognitionHypothesis],
        trace: TranscriptDecisionTrace
    ) {
        self.selected = selected
        self.alternatives = alternatives
        self.trace = trace
    }
}

public actor AccuracyCoordinator {
    private let primaryProvider: any RecognitionCandidateProvider
    private let secondaryProvider: (any RecognitionCandidateProvider)?
    private let policy: AccuracyPolicy

    public init(
        primaryProvider: any RecognitionCandidateProvider,
        secondaryProvider: (any RecognitionCandidateProvider)? = nil,
        policy: AccuracyPolicy = .defaultPolicy
    ) {
        self.primaryProvider = primaryProvider
        self.secondaryProvider = secondaryProvider
        self.policy = policy
    }

    public func finalize(
        request: RecognitionRequest,
        provisional: [RecognitionHypothesis] = []
    ) async throws -> AccuracyDecision {
        var weightedCandidates: [WeightedCandidate] = []
        var alternatives: [RecognitionHypothesis] = []
        var rejectionReasons: [String] = []

        let primary = try await primaryProvider.primaryHypothesis(request: request)
        alternatives.append(primary)
        weightedCandidates.append(
            .init(hypothesis: primary, reliabilityWeight: 1.0)
        )

        if !provisional.isEmpty {
            alternatives.append(contentsOf: provisional)
            let provisionalWeight = max(
                0.1,
                Double(policy.maximumCandidates) > 0
                    ? 1.0 / Double(policy.maximumCandidates + 1)
                    : 0.5
            )
            for candidate in provisional {
                weightedCandidates.append(
                    .init(
                        hypothesis: candidate,
                        reliabilityWeight: provisionalWeight
                    )
                )
            }
        }

        let uncertainty = UncertaintyDetector.assess(
            hypothesis: primary,
            policy: policy
        )
        if uncertainty.isUncertain {
            rejectionReasons.append(contentsOf: uncertainty.reasons)
        }

        let shouldRetrySecondary = request.strategy == .adaptive
            && uncertainty.isUncertain
            && !primary.adaptiveFallback
            && secondaryProvider != nil

        if shouldRetrySecondary,
           let secondaryProvider {
            let beamRequest = RecognitionRequest(
                requestID: request.requestID,
                audioURL: request.audioURL,
                prompt: request.prompt,
                window: request.window,
                strategy: .beam,
                beamSize: request.beamSize,
                emitTokenData: request.emitTokenData,
                emitTimestamps: request.emitTimestamps,
                protocolVersion: request.protocolVersion
            )
            do {
                let alternate = try await secondaryProvider.alternateHypothesis(
                    request: AlternateRecognitionRequest(
                        base: beamRequest,
                        pass: .secondaryVerifier
                    )
                )
                alternatives.append(alternate)
                weightedCandidates.append(
                    .init(
                        hypothesis: alternate,
                        reliabilityWeight: 0.8
                    )
                )
            } catch {
                rejectionReasons.append(
                    "secondary retry failed: \(String(describing: error))"
                )
            }
        }

        let maximumCandidates = max(policy.maximumCandidates, 1)
        if alternatives.count > maximumCandidates {
            alternatives = Array(alternatives.suffix(maximumCandidates))
            weightedCandidates = Array(weightedCandidates.suffix(maximumCandidates))
        }

        guard let chosen = CandidateSelector.weightedMedoid(weightedCandidates)
        else {
            throw WhisperASRError.noSpeech
        }

        return AccuracyDecision(
            selected: chosen.hypothesis,
            alternatives: alternatives,
            trace: TranscriptDecisionTrace(
                selectedHypothesisID: chosen.hypothesis.id,
                candidateCount: alternatives.count,
                rejectionReasons: rejectionReasons
            )
        )
    }
}
