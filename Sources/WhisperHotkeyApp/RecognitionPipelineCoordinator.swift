import Foundation
import WhisperHotkeyASR
import WhisperHotkeyCore
import WhisperHotkeySystem

/// The only events a recognition pipeline may hand to the application shell.
/// A pause event is always a complete sentence candidate; provisional words
/// never cross this boundary.
public enum RecognitionPipelineDeliveryKind: String, Sendable {
    case finalTranscript
    case pauseSentence
}

public struct RecognitionPipelineDelivery: Equatable, Sendable {
    public let kind: RecognitionPipelineDeliveryKind
    public let text: String
    public let sessionID: UUID
    public let generation: UInt64

    public init(
        kind: RecognitionPipelineDeliveryKind,
        text: String,
        sessionID: UUID,
        generation: UInt64
    ) {
        self.kind = kind
        self.text = text
        self.sessionID = sessionID
        self.generation = generation
    }
}

public enum RecognitionPipelineStage: String, Sendable {
    case primary
    case finalTail
    case verifier
    case formatter
}

public enum RecognitionPipelineError: Error, Equatable, Sendable {
    case cancelled
    case staleGeneration
    case deadlineExceeded(RecognitionPipelineStage)
    case noSpeechDetected
    case primaryFailed
}

/// A provider request is deliberately bounded and contains no transcript or
/// audio bytes.  Span repair reuses the canonical file and supplies only a
/// sample range; providers must honor `preserveAudio`.
public struct RecognitionPipelineDecodeRequest: Equatable, Sendable {
    public let sessionID: UUID
    public let generation: UInt64
    public let pass: RecognitionPassKind
    public let requestID: String
    public let prompt: String?
    public let sampleStart: Int64?
    public let sampleEnd: Int64?
    public let preserveAudio: Bool
    public let completeness: DecodeCompleteness

    public init(
        sessionID: UUID,
        generation: UInt64,
        pass: RecognitionPassKind,
        requestID: String = UUID().uuidString,
        prompt: String? = nil,
        sampleStart: Int64? = nil,
        sampleEnd: Int64? = nil,
        preserveAudio: Bool = true,
        completeness: DecodeCompleteness = .provisional
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.pass = pass
        self.requestID = requestID
        self.prompt = prompt
        self.sampleStart = sampleStart
        self.sampleEnd = sampleEnd
        self.preserveAudio = preserveAudio
        self.completeness = completeness
    }
}

/// The coordinator does not infer that a synthetic or merely fitted
/// calibration artifact is production evidence.  A caller must explicitly
/// mark a matching, promoted artifact before selective repair can run.
public struct RecognitionCalibrationEvidence: Sendable {
    public let artifactID: String
    public let calibrator: ConfidenceCalibrator
    public let threshold: ConfidenceThreshold
    public let isPromoted: Bool

    public init(
        artifactID: String,
        calibrator: ConfidenceCalibrator,
        threshold: ConfidenceThreshold,
        isPromoted: Bool = false
    ) {
        self.artifactID = artifactID
        self.calibrator = calibrator
        self.threshold = threshold
        self.isPromoted = isPromoted
    }
}

public enum RecognitionRepairAvailability: String, Sendable {
    case disabled
    case missingCalibrationEvidence
    case enabled
}

public struct RecognitionPipelineRepairPolicy: Sendable {
    public let calibration: RecognitionCalibrationEvidence?
    public let plannerConfiguration: UncertainSpanPlannerConfiguration
    public let verifierEnabled: Bool

    public init(
        calibration: RecognitionCalibrationEvidence? = nil,
        plannerConfiguration: UncertainSpanPlannerConfiguration =
            .uncalibratedExperimentDefaults,
        verifierEnabled: Bool = false
    ) {
        self.calibration = calibration
        self.plannerConfiguration = plannerConfiguration
        self.verifierEnabled = verifierEnabled
    }

    public static let disabled = Self()

    public var availability: RecognitionRepairAvailability {
        guard verifierEnabled else { return .disabled }
        guard let calibration else { return .missingCalibrationEvidence }
        guard calibration.isPromoted,
              !calibration.artifactID.isEmpty
        else {
            return .disabled
        }
        let source = calibration.threshold.source
        guard case let .calibrationArtifact(
            artifactID,
            calibratorVersion,
            key
        ) = source,
              artifactID == calibration.artifactID,
              calibratorVersion == calibration.calibrator.version,
              key == calibration.calibrator.key,
              calibration.threshold.isCalibrated,
              plannerConfiguration.threshold.source == source
        else {
            return .disabled
        }
        return .enabled
    }

    fileprivate var estimator: ConfidenceEstimator? {
        guard availability == .enabled, let calibration else { return nil }
        return ConfidenceEstimator(calibrator: calibration.calibrator)
    }
}

public struct RecognitionPipelineConfiguration: Sendable {
    public let activationMode: HotkeyActivationMode
    public let processingMode: ModelProcessingMode
    public let primaryDeadline: TimeInterval
    public let finalTailDeadline: TimeInterval
    public let verifierDeadline: TimeInterval
    public let formatterDeadline: TimeInterval
    public let maximumInFlightChunks: Int
    public let maximumVerifierConcurrency: Int
    public let repairPolicy: RecognitionPipelineRepairPolicy

    public init(
        activationMode: HotkeyActivationMode = .hold,
        processingMode: ModelProcessingMode = .afterRecording,
        primaryDeadline: TimeInterval = 120,
        finalTailDeadline: TimeInterval = 30,
        verifierDeadline: TimeInterval = 3.0,
        formatterDeadline: TimeInterval = 0.15,
        maximumInFlightChunks: Int = 2,
        maximumVerifierConcurrency: Int = 2,
        repairPolicy: RecognitionPipelineRepairPolicy = .disabled
    ) {
        self.activationMode = activationMode
        self.processingMode = processingMode
        self.primaryDeadline = Self.boundedDeadline(primaryDeadline, fallback: 120)
        self.finalTailDeadline = Self.boundedDeadline(finalTailDeadline, fallback: 30)
        self.verifierDeadline = Self.boundedDeadline(verifierDeadline, fallback: 3)
        self.formatterDeadline = Self.boundedDeadline(formatterDeadline, fallback: 0.15)
        self.maximumInFlightChunks = min(8, max(1, maximumInFlightChunks))
        self.maximumVerifierConcurrency = min(4, max(1, maximumVerifierConcurrency))
        self.repairPolicy = repairPolicy
    }

    private static func boundedDeadline(
        _ value: TimeInterval,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard value.isFinite, value > 0 else { return fallback }
        return min(120, max(0.001, value))
    }
}

/// Injected providers keep the coordinator deterministic and testable.  The
/// production factory below adapts these closures to WhisperRecognizer.
public struct RecognitionPipelineProviders: Sendable {
    public typealias Decode = @Sendable (
        WhisperAudioFile,
        RecognitionPipelineDecodeRequest
    ) async throws -> RecognitionResult
    public typealias Format = @Sendable (
        RecognitionResult
    ) async throws -> LexicallyInvariantFormattingResult
    public typealias Delivery = @Sendable (
        RecognitionPipelineDelivery
    ) async -> Void

    public let primary: Decode
    public let streaming: Decode?
    public let verifier: Decode?
    public let formatter: Format
    public let preparePrimary: @Sendable () async throws -> Void
    public let releaseModels: @Sendable () async -> Void
    public let cancelModels: @Sendable () async -> Void

    public init(
        primary: @escaping Decode,
        streaming: Decode? = nil,
        verifier: Decode? = nil,
        formatter: @escaping Format = { result in
            LexicallyInvariantFormatter().format(result)
        },
        preparePrimary: @escaping @Sendable () async throws -> Void = {},
        releaseModels: @escaping @Sendable () async -> Void = {},
        cancelModels: @escaping @Sendable () async -> Void = {}
    ) {
        self.primary = primary
        self.streaming = streaming
        self.verifier = verifier
        self.formatter = formatter
        self.preparePrimary = preparePrimary
        self.releaseModels = releaseModels
        self.cancelModels = cancelModels
    }

    /// The shipping recognizer owns its process/runtime leases.  Every decode
    /// uses the rich result API and preserves caller-owned audio.
    public static func whisper(
        recognizer: WhisperRecognizer
    ) -> Self {
        let decode: Decode = { audio, request in
            try await recognizer.transcribeResult(
                audio,
                prompt: request.prompt,
                pass: request.pass,
                strategy: .beam,
                beamSize: 5,
                protocolVersion: 2,
                requestID: request.requestID,
                sampleStart: request.sampleStart,
                sampleEnd: request.sampleEnd,
                emitMetadata: true,
                preserveAudio: request.preserveAudio,
                sessionID: request.sessionID,
                generation: request.generation,
                completeness: request.completeness
            )
        }
        let streaming: Decode = { audio, request in
            try await recognizer.transcribeChunkResult(
                audio,
                prompt: request.prompt,
                pass: request.pass,
                requestID: request.requestID,
                sampleStart: request.sampleStart,
                sampleEnd: request.sampleEnd,
                preserveAudio: request.preserveAudio,
                sessionID: request.sessionID,
                generation: request.generation,
                completeness: request.completeness
            )
        }
        return Self(
            primary: decode,
            streaming: streaming,
            // No promoted verifier model is shipped in Phase 1.  Callers may
            // inject a span-capable verifier only after calibration evidence
            // is promoted; never reuse a full-session primary implicitly.
            verifier: nil,
            preparePrimary: { try await recognizer.preload() },
            releaseModels: { await recognizer.finishContinuousSession() },
            cancelModels: { await recognizer.cancel() }
        )
    }
}

public enum RecognitionPipelineFinalizationSource: String, Sendable {
    case primary
    case finalTail
    case accumulated
    case fullSessionFallback
}

public struct RecognitionPipelineOutcome: Sendable {
    public let sessionID: UUID
    public let generation: UInt64
    public let text: String
    public let words: [RecognizedWord]
    public let source: RecognitionPipelineFinalizationSource
    public let usedVerifier: Bool
    public let formatterAccepted: Bool
    public let repairAvailability: RecognitionRepairAvailability
    public let finalTailAccepted: Bool
    public let fallbackUsed: Bool
    public let deliveryCount: Int

    public init(
        sessionID: UUID,
        generation: UInt64,
        text: String,
        words: [RecognizedWord],
        source: RecognitionPipelineFinalizationSource,
        usedVerifier: Bool,
        formatterAccepted: Bool,
        repairAvailability: RecognitionRepairAvailability,
        finalTailAccepted: Bool,
        fallbackUsed: Bool,
        deliveryCount: Int
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.text = text
        self.words = words
        self.source = source
        self.usedVerifier = usedVerifier
        self.formatterAccepted = formatterAccepted
        self.repairAvailability = repairAvailability
        self.finalTailAccepted = finalTailAccepted
        self.fallbackUsed = fallbackUsed
        self.deliveryCount = deliveryCount
    }
}

private enum PipelineTimeout: Error {
    case expired(RecognitionPipelineStage)
}

private func withPipelineTimeout<Value: Sendable>(
    _ seconds: TimeInterval,
    stage: RecognitionPipelineStage,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw PipelineTimeout.expired(stage)
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw PipelineTimeout.expired(stage)
        }
        return result
    }
}

/// Actor-owned staged recognition DAG.  It is the sole owner of canonical
/// words, generation acceptance, audio cleanup, enhancement fallback, and
/// delivery.  Providers never paste and no provider owns the session audio.
public actor RecognitionPipelineCoordinator {
    public typealias Delivery = RecognitionPipelineProviders.Delivery

    private let providers: RecognitionPipelineProviders
    private let delivery: Delivery
    private let configuration: RecognitionPipelineConfiguration

    private var sessionID: UUID?
    private var activeGeneration: UInt64?
    private var generationCounter: UInt64 = 0
    private var activeActivationMode: HotkeyActivationMode = .hold
    private var activeProcessingMode: ModelProcessingMode = .afterRecording
    private var active = false
    private var finalizing = false
    private var cancelled = false
    private var finalDelivered = false
    private var deliveryCount = 0
    private var deliveredCandidateIDs = Set<String>()
    private var deliveredWordIDs = Set<StableWordID>()
    private var deliveredCandidateLexicalKeys: [String] = []
    private var deliveredCandidateLexicalKeySet = Set<String>()
    private var accumulator = PredecodedTranscriptAccumulator()
    private var childTasks: [Int: Task<Void, Never>] = [:]
    private var nextChildID = 0
    private var pendingChunkCount = 0
    private var canonicalAudio: WhisperAudioFile?
    private var finalTailAudio: WhisperAudioFile?
    private var cleanedAudioIDs = Set<ObjectIdentifier>()
    // Retain cleaned objects for the active session so ObjectIdentifier reuse
    // cannot make a later distinct audio file look already cleaned.
    private var cleanedAudioObjects: [WhisperAudioFile] = []
    private var finishTask: Task<RecognitionPipelineOutcome, Error>?

    public init(
        providers: RecognitionPipelineProviders,
        configuration: RecognitionPipelineConfiguration =
            RecognitionPipelineConfiguration(),
        delivery: @escaping Delivery = { _ in }
    ) {
        self.providers = providers
        self.configuration = configuration
        self.delivery = delivery
    }

    public var currentGeneration: UInt64? { activeGeneration }
    public var currentSessionID: UUID? { sessionID }
    public var isActive: Bool { active }
    public var isFinishing: Bool { finalizing }
    public var repairAvailability: RecognitionRepairAvailability {
        configuration.repairPolicy.availability
    }
    public var deliveredEventCount: Int { deliveryCount }
    public var pendingChunkCountForTesting: Int { pendingChunkCount }

    /// Invalidates any prior generation before accepting a new session.  A
    /// model-ready/decode-while-speaking session prepares its primary lease;
    /// after-recording remains cold until finalization.
    public func beginSession(
        sessionID: UUID = UUID(),
        generation: UInt64? = nil,
        activationMode: HotkeyActivationMode? = nil,
        processingMode: ModelProcessingMode? = nil
    ) async {
        await invalidateCurrent()
        cleanedAudioIDs.removeAll(keepingCapacity: true)
        cleanedAudioObjects.removeAll(keepingCapacity: true)
        let nextGeneration: UInt64
        if let generation {
            nextGeneration = generation
            generationCounter = max(generationCounter, generation)
        } else {
            generationCounter &+= 1
            nextGeneration = generationCounter
        }
        self.sessionID = sessionID
        activeGeneration = nextGeneration
        active = true
        finalizing = false
        cancelled = false
        finalDelivered = false
        deliveryCount = 0
        deliveredCandidateIDs.removeAll(keepingCapacity: true)
        deliveredWordIDs.removeAll(keepingCapacity: true)
        deliveredCandidateLexicalKeys.removeAll(keepingCapacity: true)
        deliveredCandidateLexicalKeySet.removeAll(keepingCapacity: true)
        pendingChunkCount = 0

        let resolvedProcessing = processingMode ?? configuration.processingMode
        let resolvedActivation = activationMode ?? configuration.activationMode
        activeProcessingMode = resolvedProcessing
        activeActivationMode = resolvedActivation
        let accumulatorMode: BackgroundPredecodeMode
        if resolvedActivation == .pause {
            accumulatorMode = .pauseMode
        } else if resolvedProcessing == .decodeWhileSpeaking {
            accumulatorMode = .decodeWhileSpeaking
        } else {
            accumulatorMode = .deferred
        }
        accumulator = PredecodedTranscriptAccumulator(
            mode: accumulatorMode,
            sessionID: sessionID,
            generation: nextGeneration
        )

        guard resolvedProcessing != .afterRecording else { return }
        try? await withPipelineTimeout(
            30,
            stage: .primary,
            operation: providers.preparePrimary
        )
    }

    /// Accepts a rich timed result from a streaming window. It is reconciled
    /// exclusively by W10's accumulator. In Pause Mode, each accumulator
    /// approved whole sentence is delivered immediately; provisional tails
    /// remain inside the accumulator and never cross this boundary.
    @discardableResult
    public func appendStreamingResult(
        _ result: RecognitionResult
    ) async -> PredecodeSnapshot? {
        guard accepts(result), !finalizing else { return nil }
        let snapshot = accumulator.append(result)
        if activeActivationMode == .pause {
            let candidates = accumulator.takePauseModeSentenceCandidates()
            for candidate in candidates {
                _ = await deliverPauseCandidate(
                    candidate,
                    sessionID: result.sessionID,
                    generation: result.generation
                )
            }
        }
        return snapshot
    }

    /// Starts one bounded background decode and applies backpressure when the
    /// in-flight queue is full.  The supplied segment is deleted only after
    /// its provider has unwound, including cancellation.
    public func submitStreamingAudio(
        _ audio: WhisperAudioFile,
        prompt: String? = nil,
        pass: RecognitionPassKind = .provisional,
        sampleStart: Int64? = nil,
        sampleEnd: Int64? = nil,
        completeness: DecodeCompleteness = .provisional,
        expectedGeneration: UInt64? = nil
    ) {
        guard let sessionID,
              let generation = activeGeneration,
              active,
              !finalizing,
              !cancelled,
              expectedGeneration == nil || expectedGeneration == generation,
              audio.speechPresence != .absent,
              pendingChunkCount < configuration.maximumInFlightChunks
        else {
            if active,
               !finalizing,
               !cancelled,
               (expectedGeneration == nil || expectedGeneration == activeGeneration)
            {
                // Dropping a bounded chunk is safe only if finalization is
                // forced to use the canonical full-recording fallback.
                accumulator.markBackgroundFailure()
            }
            audio.delete()
            return
        }
        pendingChunkCount += 1
        let childID = nextChildID
        nextChildID &+= 1
        let request = RecognitionPipelineDecodeRequest(
            sessionID: sessionID,
            generation: generation,
            pass: pass,
            prompt: prompt,
            sampleStart: sampleStart,
            sampleEnd: sampleEnd,
            preserveAudio: true,
            completeness: completeness
        )
        let provider = providers.streaming ?? providers.primary
        let task = Task { [weak self] in
            defer { audio.delete() }
            var failed = false
            do {
                let result = try await withPipelineTimeout(
                    0.9,
                    stage: .finalTail,
                    operation: { try await provider(audio, request) }
                )
                _ = await self?.appendStreamingResult(result)
            } catch {
                failed = true
            }
            if failed {
                await self?.streamingChildFailed(childID)
            } else {
                await self?.streamingChildFinished(childID)
            }
        }
        childTasks[childID] = task
    }

    /// Finishes the staged DAG.  `finalTailAudio` is a bounded inference
    /// segment; the canonical file is retained for all primary/enhancement
    /// work and is deleted once, after every child has unwound.
    public func finish(
        audio: WhisperAudioFile,
        finalTailAudio: WhisperAudioFile? = nil,
        finalTailSampleStart: Int64? = nil,
        finalTailSampleEnd: Int64? = nil,
        prompt: String? = nil
    ) async throws -> RecognitionPipelineOutcome {
        guard active,
              let sessionID,
              let generation = activeGeneration,
              !cancelled
        else {
            cleanupRejectedFinishAudio(audio, finalTailAudio: finalTailAudio)
            throw RecognitionPipelineError.staleGeneration
        }
        guard finishTask == nil else {
            cleanupRejectedFinishAudio(audio, finalTailAudio: finalTailAudio)
            throw RecognitionPipelineError.staleGeneration
        }

        canonicalAudio = audio
        self.finalTailAudio = finalTailAudio
        let task = Task { [weak self] in
            guard let self else { throw RecognitionPipelineError.cancelled }
            return try await self.performFinish(
                audio: audio,
                finalTailAudio: finalTailAudio,
                finalTailSampleStart: finalTailSampleStart,
                finalTailSampleEnd: finalTailSampleEnd,
                prompt: prompt,
                sessionID: sessionID,
                generation: generation
            )
        }
        finishTask = task
        do {
            let outcome = try await task.value
            finishTask = nil
            return outcome
        } catch {
            finishTask = nil
            throw error
        }
    }

    /// Cancels all stages, invalidates the generation, waits for provider
    /// unwind, then releases model leases and session audio.
    public func cancel() async {
        guard active || finishTask != nil || canonicalAudio != nil else {
            return
        }
        cancelled = true
        active = false
        finalizing = true
        activeGeneration = (activeGeneration ?? 0) &+ 1
        accumulator.cancel()
        finishTask?.cancel()
        for task in childTasks.values { task.cancel() }
        if let finishTask {
            _ = try? await finishTask.value
        }
        await waitForChildren()
        await providers.cancelModels()
        await providers.releaseModels()
        cleanupSessionAudio()
        childTasks.removeAll(keepingCapacity: true)
        pendingChunkCount = 0
        finalizing = false
        sessionID = nil
    }

    private func performFinish(
        audio: WhisperAudioFile,
        finalTailAudio: WhisperAudioFile?,
        finalTailSampleStart: Int64?,
        finalTailSampleEnd: Int64?,
        prompt: String?,
        sessionID: UUID,
        generation: UInt64
    ) async throws -> RecognitionPipelineOutcome {
        finalizing = true
        do {
            try ensureCurrent(sessionID: sessionID, generation: generation)
            await waitForChildren()
            try ensureCurrent(sessionID: sessionID, generation: generation)

            var primary: RecognitionResult?
            var source: RecognitionPipelineFinalizationSource = .primary
            var finalTailAccepted = false
            var fallbackUsed = false

            let streamingSession = activeProcessingMode ==
                .decodeWhileSpeaking || activeActivationMode == .pause
            if streamingSession, let finalTailAudio {
                do {
                    let request = RecognitionPipelineDecodeRequest(
                        sessionID: sessionID,
                        generation: generation,
                        pass: .primaryFullSession,
                        prompt: prompt,
                        sampleStart: finalTailSampleStart,
                        sampleEnd: finalTailSampleEnd,
                        preserveAudio: true,
                        completeness: .finalSession
                    )
                    let finalTail = try await withPipelineTimeout(
                        configuration.finalTailDeadline,
                        stage: .finalTail,
                        operation: {
                            try await self.providers.primary(finalTailAudio, request)
                        }
                    )
                    try ensureResultIdentity(
                        finalTail,
                        sessionID: sessionID,
                        generation: generation
                    )
                    try ensureCurrent(sessionID: sessionID, generation: generation)
                    let finalization = accumulator.finalize(finalTail: finalTail)
                    finalTailAccepted = finalization.finalTailAccepted
                    if activeActivationMode == .pause {
                        // W10 emits a final sentence candidate during
                        // finalize(). It is still the canonical tail, so
                        // deliver it here before the remaining-tail filter
                        // runs; already delivered IDs/lexical keys are
                        // rejected by the same exactly-once gate.
                        let candidates = accumulator.takePauseModeSentenceCandidates()
                        for candidate in candidates {
                            _ = await deliverPauseCandidate(
                                candidate,
                                sessionID: sessionID,
                                generation: generation
                            )
                        }
                    }
                    if finalization.snapshot.finalized,
                       !finalization.snapshot.transcript.isEmpty
                    {
                        primary = Self.accumulatorResult(
                            finalization,
                            source: finalTail,
                            sessionID: sessionID,
                            generation: generation
                        )
                        source = .finalTail
                    }
                } catch is CancellationError {
                    throw RecognitionPipelineError.cancelled
                } catch let error as RecognitionPipelineError {
                    if error == .staleGeneration {
                        throw error
                    }
                    accumulator.markBackgroundFailure()
                } catch {
                    accumulator.markBackgroundFailure()
                }
            }

            if primary == nil {
                let request = RecognitionPipelineDecodeRequest(
                    sessionID: sessionID,
                    generation: generation,
                    pass: .primaryFullSession,
                    prompt: prompt,
                    preserveAudio: true,
                    completeness: .finalSession
                )
                do {
                    primary = try await withPipelineTimeout(
                        configuration.primaryDeadline,
                        stage: .primary,
                        operation: { try await self.providers.primary(audio, request) }
                    )
                    if let primary {
                        try ensureResultIdentity(
                            primary,
                            sessionID: sessionID,
                            generation: generation
                        )
                    }
                    source = streamingSession ? .fullSessionFallback : .primary
                    fallbackUsed = streamingSession
                    try ensureCurrent(sessionID: sessionID, generation: generation)
                } catch is CancellationError {
                    throw RecognitionPipelineError.cancelled
                } catch let error as RecognitionPipelineError {
                    if error == .staleGeneration {
                        throw error
                    }
                    let accumulated = accumulator.snapshotForFallback()
                    guard !accumulated.transcript.isEmpty else {
                        throw RecognitionPipelineError.primaryFailed
                    }
                    primary = Self.accumulatorResult(
                        accumulated,
                        source: nil,
                        sessionID: sessionID,
                        generation: generation
                    )
                    source = .accumulated
                    fallbackUsed = true
                } catch {
                    // A complete accumulated result is still a safe fallback
                    // only when a final tail was not available; it is never
                    // invented text.
                    let accumulated = accumulator.snapshotForFallback()
                    guard !accumulated.transcript.isEmpty else {
                        throw RecognitionPipelineError.primaryFailed
                    }
                    primary = Self.accumulatorResult(
                        accumulated,
                        source: nil,
                        sessionID: sessionID,
                        generation: generation
                    )
                    source = .accumulated
                    fallbackUsed = true
                }
            }

            guard let primary else { throw RecognitionPipelineError.primaryFailed }
            guard !primary.words.isEmpty
                || !primary.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw RecognitionPipelineError.noSpeechDetected
            }
            try ensureCurrent(sessionID: sessionID, generation: generation)
            let enhancement = try await enhance(
                primary,
                audio: audio,
                sessionID: sessionID,
                generation: generation
            )
            try ensureCurrent(sessionID: sessionID, generation: generation)

            let outcome = RecognitionPipelineOutcome(
                sessionID: sessionID,
                generation: generation,
                text: enhancement.text,
                words: enhancement.words,
                source: source,
                usedVerifier: enhancement.usedVerifier,
                formatterAccepted: enhancement.formatterAccepted,
                repairAvailability: configuration.repairPolicy.availability,
                finalTailAccepted: finalTailAccepted,
                fallbackUsed: fallbackUsed,
                deliveryCount: deliveryCount
            )
            try await deliverOutcome(
                outcome,
                formattedWords: enhancement.formattedWords
            )
            try ensureCurrent(sessionID: sessionID, generation: generation)
            await providers.releaseModels()
            active = false
            finalizing = false
            cleanupSessionAudio()
            self.sessionID = nil
            return RecognitionPipelineOutcome(
                sessionID: outcome.sessionID,
                generation: outcome.generation,
                text: outcome.text,
                words: outcome.words,
                source: outcome.source,
                usedVerifier: outcome.usedVerifier,
                formatterAccepted: outcome.formatterAccepted,
                repairAvailability: outcome.repairAvailability,
                finalTailAccepted: outcome.finalTailAccepted,
                fallbackUsed: outcome.fallbackUsed,
                deliveryCount: deliveryCount
            )
        } catch is CancellationError {
            await abortCurrentSession()
            throw RecognitionPipelineError.cancelled
        } catch let error as RecognitionPipelineError {
            await abortCurrentSession()
            throw error
        } catch {
            await abortCurrentSession()
            throw error
        }
    }

    private struct EnhancementResult: Sendable {
        let text: String
        let words: [RecognizedWord]
        let formattedWords: [FormattedLexicalWord]
        let usedVerifier: Bool
        let formatterAccepted: Bool
    }

    private func enhance(
        _ primary: RecognitionResult,
        audio: WhisperAudioFile,
        sessionID: UUID,
        generation: UInt64
    ) async throws -> EnhancementResult {
        let formattingTask = Task { [providers, configuration] in
            try await withPipelineTimeout(
                configuration.formatterDeadline,
                stage: .formatter,
                operation: { try await providers.formatter(primary) }
            )
        }
        let repairTask = Task { [weak self] in
            guard let self else {
                return (primary, false)
            }
            return await self.repair(
                primary,
                audio: audio,
                sessionID: sessionID,
                generation: generation
            )
        }

        return try await withTaskCancellationHandler(operation: {
            let repaired = await repairTask.value
            try ensureCurrent(sessionID: sessionID, generation: generation)

        let formatted: LexicallyInvariantFormattingResult?
        var formattingFailed = false
        do {
            formatted = try await formattingTask.value
        } catch {
            formatted = nil
            formattingFailed = true
        }
        let result = repaired.0
        let acceptedFormatting: LexicallyInvariantFormattingResult?
        if formattingFailed {
            // A formatter timeout/failure is a guarded primary fallback.  Do
            // not run a second formatter here: the canonical primary words
            // are the only safe output after an enhancement failure.
            acceptedFormatting = nil
        } else if let formatted {
            guard formatted.accepted else {
                acceptedFormatting = nil
                return EnhancementResult(
                    text: result.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    words: result.words,
                    formattedWords: [],
                    usedVerifier: repaired.1,
                    formatterAccepted: false
                )
            }
            let matchesCanonicalWords = formatted.words.map(\.id)
                == result.words.map(\.id)
                && LexicalInvariantGuard.areLexicallyInvariant(
                    originalWords: result.words,
                    formattedWords: formatted.words
                )
                && LexicalInvariantGuard.areLexicallyInvariant(
                    original: result.text,
                    formatted: formatted.formattedText
                )
            if matchesCanonicalWords {
                acceptedFormatting = formatted
            } else if result.words.isEmpty {
                acceptedFormatting = LexicalInvariantGuard.areLexicallyInvariant(
                    original: result.text,
                    formatted: formatted.formattedText
                ) ? formatted : nil
            } else {
                // A verifier may replace lexical content while a stale W09
                // result still preserves IDs. Re-run only the deterministic
                // W09 label layer for the repaired canonical word graph; it
                // cannot inherit labels by array position or stale text.
                let rerun = LexicallyInvariantFormatter().format(result)
                acceptedFormatting = rerun.accepted ? rerun : nil
            }
        } else if result.words.isEmpty {
            acceptedFormatting = nil
        } else {
            // A verifier may replace a word ID.  Re-run only the deterministic
            // W09 label layer for the new canonical word graph; it cannot
            // inherit labels by array position.
            let rerun = LexicallyInvariantFormatter().format(result)
            acceptedFormatting = rerun.accepted ? rerun : nil
        }
        let text = acceptedFormatting?.formattedText
            ?? result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return EnhancementResult(
                text: text,
                words: result.words,
                formattedWords: acceptedFormatting?.words ?? [],
                usedVerifier: repaired.1,
                formatterAccepted: acceptedFormatting != nil
            )
        }, onCancel: {
            formattingTask.cancel()
            repairTask.cancel()
        })
    }

    private func repair(
        _ primary: RecognitionResult,
        audio: WhisperAudioFile,
        sessionID: UUID,
        generation: UInt64
    ) async -> (RecognitionResult, Bool) {
        guard configuration.repairPolicy.availability == .enabled,
              let estimator = configuration.repairPolicy.estimator,
              let verifier = providers.verifier
        else {
            return (primary, false)
        }

        let calibrated = estimator.applyingCalibration(to: primary)
        let probabilities = Dictionary(
            uniqueKeysWithValues: calibrated.words.compactMap { word in
                word.calibratedErrorProbability.map { (word.id, $0) }
            }
        )
        let plan = UncertainSpanPlanner.plan(
            words: calibrated.words,
            wordErrorProbabilities: probabilities,
            sessionDurationSeconds: calibrated.timing.audioDurationSeconds
                ?? max(0.001, calibrated.words.last?.endSeconds ?? 0.001),
            configuration: configuration.repairPolicy.plannerConfiguration
        )
        guard !plan.spans.isEmpty else { return (calibrated, false) }

        let requests = await verifierResults(
            plan: plan,
            audio: audio,
            sessionID: sessionID,
            generation: generation,
            verifier: verifier
        )
        guard !requests.isEmpty else { return (calibrated, false) }

        var current = calibrated
        var changed = false
        for (span, candidate) in requests {
            guard current.sessionID == sessionID,
                  current.generation == generation
            else { return (primary, false) }
            let fusion = CandidateFusion.fuse(
                primary: current,
                candidates: [candidate],
                configuration: span.fusionConfiguration
            )
            if fusion.accepted || fusion.words != current.words {
                current = Self.resultReplacingWords(current, words: fusion.words)
                changed = changed || fusion.words != calibrated.words
            }
        }
        return (current, changed)
    }

    private func verifierResults(
        plan: UncertainSpanPlan,
        audio: WhisperAudioFile,
        sessionID: UUID,
        generation: UInt64,
        verifier: @escaping RecognitionPipelineProviders.Decode
    ) async -> [(UncertainAudioSpan, RecognitionResult)] {
        var values: [(UncertainAudioSpan, RecognitionResult)] = []
        let maxConcurrency = configuration.maximumVerifierConcurrency
        let verifierDeadline = configuration.verifierDeadline
        for batchStart in stride(from: 0, to: plan.spans.count, by: maxConcurrency) {
            let batch = Array(
                plan.spans.dropFirst(batchStart).prefix(maxConcurrency)
            )
            let batchValues = await withTaskGroup(
                of: (UncertainAudioSpan, RecognitionResult)?.self,
                returning: [(UncertainAudioSpan, RecognitionResult)].self
            ) { group in
                for span in batch {
                    group.addTask {
                        let request = RecognitionPipelineDecodeRequest(
                            sessionID: sessionID,
                            generation: generation,
                            pass: .secondaryVerifier,
                            prompt: span.contextText,
                            sampleStart: span.startSample,
                            sampleEnd: span.endSample,
                            preserveAudio: true,
                            completeness: .finalSession
                        )
                        do {
                            let result = try await withPipelineTimeout(
                                verifierDeadline,
                                stage: .verifier,
                                operation: { try await verifier(audio, request) }
                            )
                            guard result.sessionID == sessionID,
                                  result.generation == generation
                            else { return nil }
                            return (span, result)
                        } catch {
                            return nil
                        }
                    }
                }
                var output: [(UncertainAudioSpan, RecognitionResult)] = []
                for await value in group {
                    if let value { output.append(value) }
                }
                return output
            }
            values.append(contentsOf: batchValues)
        }
        return values.sorted { $0.0.id < $1.0.id }
    }

    private func deliverOutcome(
        _ outcome: RecognitionPipelineOutcome,
        formattedWords: [FormattedLexicalWord]
    ) async throws {
        guard activeActivationMode == .pause else {
            guard !finalDelivered else { return }
            try ensureCurrent(
                sessionID: outcome.sessionID,
                generation: outcome.generation
            )
            finalDelivered = true
            await deliver(
                RecognitionPipelineDelivery(
                    kind: .finalTranscript,
                    text: outcome.text,
                    sessionID: outcome.sessionID,
                    generation: outcome.generation
                )
            )
            return
        }

        let remainingText: String
        if !formattedWords.isEmpty {
            var skipped = 0
            remainingText = formattedWords.compactMap { word in
                if deliveredWordIDs.contains(word.id) {
                    return nil
                }
                if skipped < deliveredCandidateLexicalKeys.count,
                   Self.lexicalKey(word.lexicalText)
                    == deliveredCandidateLexicalKeys[skipped]
                {
                    skipped += 1
                    return nil
                }
                return word.renderedText
            }.joined(separator: " ")
        } else {
            var skipped = 0
            remainingText = outcome.words.compactMap { word in
                if deliveredWordIDs.contains(word.id) {
                    return nil
                }
                if skipped < deliveredCandidateLexicalKeys.count,
                   Self.lexicalKey(word.text)
                    == deliveredCandidateLexicalKeys[skipped]
                {
                    skipped += 1
                    return nil
                }
                return word.text
            }.joined(separator: " ")
        }
        let trimmed = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || deliveryCount == 0, !finalDelivered else {
            return
        }
        try ensureCurrent(
            sessionID: outcome.sessionID,
            generation: outcome.generation
        )
        finalDelivered = true
        await deliver(
            RecognitionPipelineDelivery(
                kind: .finalTranscript,
                text: trimmed.isEmpty ? outcome.text : trimmed,
                sessionID: outcome.sessionID,
                generation: outcome.generation
            )
        )
    }

    private func deliver(_ event: RecognitionPipelineDelivery) async {
        deliveryCount += 1
        await delivery(event)
    }

    /// Delivers one accumulator-approved sentence while the session is still
    /// listening. The checks happen immediately before the closure is called;
    /// AppDelegate performs the matching generation/phase guard on receipt.
    private func deliverPauseCandidate(
        _ candidate: PauseModeSentenceCandidate,
        sessionID: UUID,
        generation: UInt64
    ) async -> Bool {
        guard activeActivationMode == .pause,
              candidate.generation == generation,
              candidate.sessionID == nil || candidate.sessionID == self.sessionID,
              !candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              candidate.pasteReadiness == .sentenceCandidate
                  || candidate.pasteReadiness == .finalReady,
              !deliveredCandidateIDs.contains(candidate.id)
        else { return false }

        let lexicalWords = candidate.words.map { Self.lexicalKey($0.text) }
        let lexicalKey = lexicalWords.joined(separator: "\u{1F}")
        let effectiveLexicalKey = lexicalKey.isEmpty
            ? Self.lexicalKey(candidate.text)
            : lexicalKey
        guard !effectiveLexicalKey.isEmpty,
              !deliveredCandidateLexicalKeySet.contains(effectiveLexicalKey)
        else { return false }
        do {
            try ensureCurrent(sessionID: sessionID, generation: generation)
        } catch {
            return false
        }

        deliveredCandidateIDs.insert(candidate.id)
        deliveredCandidateLexicalKeySet.insert(effectiveLexicalKey)
        deliveredWordIDs.formUnion(candidate.words.map(\.id))
        deliveredCandidateLexicalKeys.append(contentsOf: lexicalWords)
        await deliver(
            RecognitionPipelineDelivery(
                kind: .pauseSentence,
                text: candidate.text,
                sessionID: sessionID,
                generation: generation
            )
        )
        return true
    }

    private func accepts(_ result: RecognitionResult) -> Bool {
        guard active,
              let sessionID,
              let generation = activeGeneration,
              result.sessionID == sessionID,
              result.generation == generation,
              !cancelled
        else { return false }
        return true
    }

    private func ensureCurrent(
        sessionID: UUID,
        generation: UInt64
    ) throws {
        guard active,
              !cancelled,
              self.sessionID == sessionID,
              activeGeneration == generation,
              !Task.isCancelled
        else { throw RecognitionPipelineError.staleGeneration }
    }

    private func ensureResultIdentity(
        _ result: RecognitionResult,
        sessionID: UUID,
        generation: UInt64
    ) throws {
        guard result.sessionID == sessionID,
              result.generation == generation
        else { throw RecognitionPipelineError.staleGeneration }
    }

    private func streamingChildFinished(_ childID: Int) {
        pendingChunkCount = max(0, pendingChunkCount - 1)
        childTasks.removeValue(forKey: childID)
    }

    private func streamingChildFailed(_ childID: Int) {
        accumulator.markBackgroundFailure()
        streamingChildFinished(childID)
    }

    private func waitForChildren() async {
        let tasks = Array(childTasks.values)
        for task in tasks { await task.value }
        childTasks.removeAll(keepingCapacity: true)
        pendingChunkCount = 0
    }

    private func invalidateCurrent() async {
        guard active || finishTask != nil || canonicalAudio != nil else { return }
        cancelled = true
        active = false
        finalizing = true
        activeGeneration = (activeGeneration ?? 0) &+ 1
        accumulator.cancel()
        finishTask?.cancel()
        for task in childTasks.values { task.cancel() }
        if let finishTask { _ = try? await finishTask.value }
        await waitForChildren()
        await providers.cancelModels()
        await providers.releaseModels()
        cleanupSessionAudio()
        sessionID = nil
        finalizing = false
        finishTask = nil
    }

    private func abortCurrentSession() async {
        active = false
        finalizing = true
        cancelled = true
        activeGeneration = (activeGeneration ?? 0) &+ 1
        for task in childTasks.values { task.cancel() }
        await waitForChildren()
        await providers.cancelModels()
        await providers.releaseModels()
        cleanupSessionAudio()
        sessionID = nil
        finishTask = nil
        finalizing = false
    }

    private func cleanupSessionAudio() {
        if let canonicalAudio {
            cleanup(canonicalAudio)
            self.canonicalAudio = nil
        }
        if let finalTailAudio {
            cleanup(finalTailAudio)
            self.finalTailAudio = nil
        }
    }

    private func cleanup(_ audio: WhisperAudioFile) {
        let id = ObjectIdentifier(audio)
        guard cleanedAudioIDs.insert(id).inserted else { return }
        cleanedAudioObjects.append(audio)
        audio.delete()
    }

    /// A rejected finish never becomes the coordinator's canonical ownership.
    /// Do not delete an already-owned canonical/tail object while another
    /// finish task is unwinding; the accepted invocation remains sole owner.
    private func cleanupRejectedFinishAudio(
        _ audio: WhisperAudioFile,
        finalTailAudio: WhisperAudioFile?
    ) {
        let ownedIDs = Set(
            [canonicalAudio, self.finalTailAudio].compactMap {
                $0.map(ObjectIdentifier.init)
            }
        )
        cleanupRejected(audio, ownedIDs: ownedIDs)
        if let finalTailAudio, finalTailAudio !== audio {
            cleanupRejected(finalTailAudio, ownedIDs: ownedIDs)
        }
    }

    private func cleanupRejected(
        _ audio: WhisperAudioFile,
        ownedIDs: Set<ObjectIdentifier>
    ) {
        let id = ObjectIdentifier(audio)
        guard !ownedIDs.contains(id), cleanedAudioIDs.insert(id).inserted else {
            return
        }
        cleanedAudioObjects.append(audio)
        audio.delete()
    }

    private static func resultReplacingWords(
        _ result: RecognitionResult,
        words: [RecognizedWord]
    ) -> RecognitionResult {
        RecognitionResult(
            sessionID: result.sessionID,
            generation: result.generation,
            engine: result.engine,
            model: result.model,
            pass: result.pass,
            text: words.map(\.text).joined(separator: " "),
            words: words,
            segments: result.segments,
            alternatives: result.alternatives,
            utteranceEvidence: result.utteranceEvidence,
            timing: result.timing,
            completeness: result.completeness,
            passMetadata: result.passMetadata
        )
    }

    private static func lexicalKey(_ text: String) -> String {
        text.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private static func accumulatorResult(
        _ finalization: PredecodeFinalization,
        source: RecognitionResult?,
        sessionID: UUID,
        generation: UInt64
    ) -> RecognitionResult {
        accumulatorResult(
            finalization.snapshot,
            source: source,
            sessionID: sessionID,
            generation: generation
        )
    }

    private static func accumulatorResult(
        _ snapshot: PredecodeSnapshot,
        source: RecognitionResult?,
        sessionID: UUID,
        generation: UInt64
    ) -> RecognitionResult {
        let words = snapshot.stablePrefix + snapshot.revisableTail
        let text = snapshot.transcript.isEmpty
            ? source?.text ?? words.map(\.text).joined(separator: " ")
            : snapshot.transcript
        return RecognitionResult(
            sessionID: sessionID,
            generation: generation,
            engine: source?.engine ?? .whisperTurbo,
            model: source?.model ?? .unknown,
            pass: source?.pass ?? .primaryFullSession,
            text: text,
            words: words,
            segments: source?.segments ?? [],
            alternatives: source?.alternatives ?? [],
            utteranceEvidence: source?.utteranceEvidence ?? .unavailable,
            timing: source?.timing ?? .unavailable,
            completeness: .finalSession,
            passMetadata: source?.passMetadata ?? RecognitionPassMetadata()
        )
    }
}

private extension PredecodedTranscriptAccumulator {
    func snapshotForFallback() -> PredecodeSnapshot {
        PredecodeSnapshot(
            stablePrefix: stablePrefix,
            revisableTail: revisableTail,
            transcript: transcript,
            sentenceCandidates: sentenceCandidates,
            boundaries: boundaries,
            generation: generation,
            mode: mode,
            accepted: true,
            ignored: false,
            fallbackRequired: fallbackRequired,
            cancelled: cancelled,
            finalized: finalized
        )
    }
}
