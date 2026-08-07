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

        let primary = try await primaryProvider.primaryHypothesis(request: request)
        alternatives.append(primary)
        weightedCandidates.append(
            .init(hypothesis: primary, reliabilityWeight: 1.0)
        )

        if provisional.count > 0 {
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

        if let secondaryProvider {
            let alternate: RecognitionHypothesis?
            do {
                alternate = try await secondaryProvider.alternateHypothesis(
                    request: AlternateRecognitionRequest(
                        base: request,
                        pass: .secondaryVerifier
                    )
                )
            } catch {
                alternate = nil
            }
            if let alternate {
                alternatives.append(alternate)
                weightedCandidates.append(
                    .init(hypothesis: alternate, reliabilityWeight: 0.6)
                )
            }
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
                candidateCount: alternatives.count
            )
        )
    }
}
