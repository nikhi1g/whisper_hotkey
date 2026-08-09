import Foundation
import FluidAudio
import WhisperHotkeyCore

/// Wraps FluidAudio's Parakeet models behind the same load/transcribe/release
/// shape the other engines use.
///
/// Parakeet is a FastConformer transducer, not an autoregressive decoder, so
/// three things differ from the whisper engines and are handled here rather
/// than leaking into `WhisperRecognition`:
///
/// - There is no beam search, so `DecodingProfile` has nothing to select.
/// - There is no prompt, so the internal dictionary and the Pause Mode context
///   tail cannot bias the decode; both are dropped before the call.
/// - Models are fetched and cached by FluidAudio under Application Support
///   rather than `~/.cache/whisper`, so there is no bundled file to discover.
actor ParakeetRuntime {
    private let variant: ParakeetVariant
    private var models: AsrModels?
    private var manager: AsrManager?
    /// Unified is a different FluidAudio manager with its own decoder, so it
    /// is held separately rather than bent into the TDT one.
    private var unifiedManager: UnifiedAsrManager?
    private let audioConverter = AudioConverter()
    private var decoderLayers = 2

    init(variant: ParakeetVariant) {
        self.variant = variant
    }

    private var modelVersion: AsrModelVersion {
        ParakeetModelInstaller.version(for: variant)
    }

    var isLoaded: Bool {
        manager != nil || unifiedManager != nil
    }

    /// Loads an already-installed checkpoint.
    ///
    /// This never downloads. A dictation that had to fetch several hundred
    /// megabytes first showed a Transcribing badge for the whole transfer, with
    /// no progress and no timeout, which is indistinguishable from a hang. The
    /// fetch is an explicit, cancellable step at selection time instead; see
    /// `ParakeetModelInstaller`.
    func load() async throws {
        if variant == .unified {
            try await loadUnified()
            return
        }
        guard manager == nil else { return }
        let directory = ParakeetModelInstaller.cacheDirectory(for: variant)
        guard ParakeetModelInstaller.isInstalled(variant) else {
            throw WhisperASRError.modelMissing(directory.path)
        }
        do {
            let loaded = try await AsrModels.load(
                from: directory,
                version: modelVersion
            )
            try Task.checkCancellation()
            let runtime = AsrManager(config: .default)
            try await runtime.loadModels(loaded)
            models = loaded
            manager = runtime
            decoderLayers = await runtime.decoderLayerCount
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed(
                "Parakeet model load failed"
            )
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await transcribeResult(audioURL: audioURL).renderedText
    }

    /// Returns FluidAudio's provider-neutral rich result without discarding
    /// evidence that is not representable by the legacy String API.
    ///
    /// The TDT managers expose token timings and per-token confidence through
    /// `ASRResult`. Unified's pinned offline manager exposes only its final
    /// String, so the adapter deliberately returns no words, segments, or
    /// confidence for that variant rather than deriving unsupported evidence.
    func transcribeResult(
        audioURL: URL,
        sessionID: UUID = UUID(),
        generation: UInt64 = 0,
        pass: RecognitionPassKind = .primaryFullSession,
        providerDecodeID: String = UUID().uuidString,
        completeness: DecodeCompleteness = .finalSession
    ) async throws -> RecognitionResult {
        try await load()
        if variant == .unified {
            guard let unifiedManager else {
                throw WhisperASRError.helperFailed("Parakeet is not loaded")
            }
            do {
                let samples = try audioConverter.resampleAudioFile(audioURL)
                // A fresh decoder state per utterance keeps one dictation from
                // carrying transducer state into the next.
                try await unifiedManager.reset()
                let start = Date()
                let text = try await unifiedManager.transcribe(samples)
                try Task.checkCancellation()
                return ParakeetRecognitionAdapter.textOnlyResult(
                    text: text,
                    variant: variant,
                    sessionID: sessionID,
                    generation: generation,
                    pass: pass,
                    providerDecodeID: providerDecodeID,
                    completeness: completeness,
                    audioDurationSeconds: Double(samples.count) / 16_000,
                    decodeDurationSeconds: Date().timeIntervalSince(start)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw WhisperASRError.helperFailed(
                    "Parakeet transcription failed"
                )
            }
        }
        guard let manager else {
            throw WhisperASRError.helperFailed("Parakeet is not loaded")
        }
        do {
            // A fresh decoder state per utterance keeps one dictation from
            // carrying transducer state into the next.
            var state = try TdtDecoderState(decoderLayers: decoderLayers)
            let result = try await manager.transcribe(
                audioURL,
                decoderState: &state
            )
            try Task.checkCancellation()
            return ParakeetRecognitionAdapter.result(
                from: result,
                variant: variant,
                sessionID: sessionID,
                generation: generation,
                pass: pass,
                providerDecodeID: providerDecodeID,
                completeness: completeness
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed(
                "Parakeet transcription failed"
            )
        }
    }

    func release() async {
        if let manager {
            await manager.cleanup()
        }
        if let unifiedManager {
            await unifiedManager.cleanup()
        }
        manager = nil
        unifiedManager = nil
        models = nil
    }

    /// Loads the already-installed Unified checkpoint. Like the TDT path this
    /// never downloads; the install is an explicit step at selection time.
    private func loadUnified() async throws {
        guard unifiedManager == nil else { return }
        let directory = ParakeetModelInstaller.cacheDirectory(for: variant)
        guard ParakeetModelInstaller.isInstalled(variant) else {
            throw WhisperASRError.modelMissing(directory.path)
        }
        do {
            let runtime = UnifiedAsrManager()
            try await runtime.loadModels(from: directory)
            try Task.checkCancellation()
            unifiedManager = runtime
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WhisperASRError.helperFailed("Parakeet model load failed")
        }
    }
}

/// Converts the exact FluidAudio 0.15.5 result shapes into the provider-neutral
/// contract. This adapter intentionally retains only evidence that FluidAudio
/// actually exposes; it never treats a missing confidence/timing as a value.
enum ParakeetRecognitionAdapter {
    private struct IndexedToken {
        let sourceIndex: Int
        let timing: TokenTiming
    }

    private struct WordGroup {
        var tokens: [IndexedToken]
        var text: String
    }

    static func result(
        from result: ASRResult,
        variant: ParakeetVariant,
        sessionID: UUID,
        generation: UInt64,
        pass: RecognitionPassKind,
        providerDecodeID: String,
        completeness: DecodeCompleteness = .finalSession
    ) -> RecognitionResult {
        let groups = wordGroups(from: result.tokenTimings ?? [])
        let words = groups.enumerated().map { index, group in
            let tokenIDs = group.tokens.map { $0.timing.tokenId }
            let confidences = group.tokens.map { $0.timing.confidence }
            let posterior: Double?
            if confidences.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                posterior = confidences.isEmpty
                    ? nil
                    : Double(confidences.reduce(0, +)) / Double(confidences.count)
            } else {
                posterior = nil
            }
            // FluidAudio documents TokenTiming.confidence as a decoder
            // softmax probability. Preserve that raw score in the contract's
            // log-probability slot without calibrating it; zero and invalid
            // values remain unavailable rather than becoming -infinity.
            let tokenLogProbabilities: [Double]
            if confidences.allSatisfy({
                $0.isFinite && $0 > 0 && $0 <= 1
            }) {
                tokenLogProbabilities = confidences.map {
                    log(Double($0))
                }
            } else {
                tokenLogProbabilities = []
            }

            let first = group.tokens.first!.timing
            let last = group.tokens.last!.timing
            var availability: WordEvidenceAvailability = [.tokenIDs, .timing]
            if tokenLogProbabilities.count == tokenIDs.count {
                availability.insert(.tokenLogProbabilities)
            }
            if posterior != nil {
                availability.insert(.posterior)
            }
            return RecognizedWord(
                id: StableWordID(
                    sessionID: sessionID,
                    providerDecodeID: providerDecodeID,
                    wordIndex: index
                ),
                text: group.text,
                startSeconds: first.startTime,
                endSeconds: last.endTime,
                tokenRange: group.tokens.first!.sourceIndex
                    ..< (group.tokens.last!.sourceIndex + 1),
                rawEvidence: WordEvidence(
                    tokenIDs: tokenIDs,
                    tokenLogProbabilities: tokenLogProbabilities,
                    posterior: posterior,
                    availability: availability
                ),
                provenance: .primary(
                    providerDecodeID: providerDecodeID,
                    wordIndex: index
                )
            )
        }

        let utteranceEvidence = UtteranceEvidence(
            // FluidAudio calls this aggregate token confidence. It is kept as
            // raw sequence score evidence and is not presented as calibrated
            // correctness probability.
            sequenceScore: validProbability(result.confidence)
        )
        let timing = RecognitionTiming(
            audioDurationSeconds: validNonNegative(result.duration),
            decodeDurationSeconds: validNonNegative(result.processingTime),
            firstWordStartSeconds: words.first?.startSeconds,
            lastWordEndSeconds: words.last?.endSeconds
        )
        let segments = makeDecodeWindowSegment(
            text: result.text,
            words: words,
            tokenTimings: result.tokenTimings ?? [],
            evidence: utteranceEvidence,
            variant: variant
        )

        return RecognitionResult(
            sessionID: sessionID,
            generation: generation,
            engine: variant.candidateEngineID,
            model: modelIdentity(for: variant),
            pass: pass,
            text: result.text,
            words: words,
            segments: segments,
            utteranceEvidence: utteranceEvidence,
            timing: timing,
            completeness: completeness,
            passMetadata: passMetadata(
                for: variant,
                providerDecodeID: providerDecodeID
            )
        )
    }

    static func textOnlyResult(
        text: String,
        variant: ParakeetVariant,
        sessionID: UUID,
        generation: UInt64,
        pass: RecognitionPassKind,
        providerDecodeID: String,
        completeness: DecodeCompleteness = .finalSession,
        audioDurationSeconds: Double?,
        decodeDurationSeconds: Double?
    ) -> RecognitionResult {
        RecognitionResult(
            sessionID: sessionID,
            generation: generation,
            engine: variant.candidateEngineID,
            model: modelIdentity(for: variant),
            pass: pass,
            text: text,
            // UnifiedAsrManager.transcribe([Float]) is String-only in the
            // pinned FluidAudio release. Empty collections are intentional:
            // no word/timing/confidence evidence is claimed.
            words: [],
            segments: [],
            utteranceEvidence: .unavailable,
            timing: RecognitionTiming(
                audioDurationSeconds: validNonNegative(audioDurationSeconds),
                decodeDurationSeconds: validNonNegative(decodeDurationSeconds)
            ),
            completeness: completeness,
            passMetadata: passMetadata(
                for: variant,
                providerDecodeID: providerDecodeID
            )
        )
    }

    private static func wordGroups(from tokenTimings: [TokenTiming]) -> [WordGroup] {
        var groups: [WordGroup] = []
        var currentTokens: [IndexedToken] = []
        var currentText = ""

        func flush() {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !currentTokens.isEmpty else {
                currentTokens.removeAll(keepingCapacity: true)
                currentText = ""
                return
            }
            groups.append(WordGroup(tokens: currentTokens, text: text))
            currentTokens.removeAll(keepingCapacity: true)
            currentText = ""
        }

        for (sourceIndex, timing) in tokenTimings.enumerated() {
            guard validTiming(timing),
                  !timing.token.isEmpty,
                  timing.token != "<blank>",
                  timing.token != "<pad>"
            else {
                continue
            }

            let startsNewWord = currentTokens.isEmpty || isWordBoundary(timing.token)
            if startsNewWord && !currentTokens.isEmpty {
                flush()
            }
            currentTokens.append(
                IndexedToken(sourceIndex: sourceIndex, timing: timing)
            )
            currentText += stripWordBoundaryPrefix(timing.token)
        }
        flush()
        return groups
    }

    private static func makeDecodeWindowSegment(
        text: String,
        words: [RecognizedWord],
        tokenTimings: [TokenTiming],
        evidence: UtteranceEvidence,
        variant: ParakeetVariant
    ) -> [RecognizedSegment] {
        guard let first = words.first, let last = words.last else { return [] }
        let tokenRange = tokenTimings.indices.first.flatMap { firstIndex in
            tokenTimings.indices.last.map { firstIndex ..< ($0 + 1) }
        }
        return [
            RecognizedSegment(
                text: text,
                startSeconds: first.startSeconds ?? 0,
                endSeconds: last.endSeconds ?? (first.startSeconds ?? 0),
                wordIDs: words.map(\.id),
                tokenRange: tokenRange,
                evidence: evidence,
                provenance: RecognitionProvenance(
                    sourceWordIDs: words.map(\.id),
                    reason: "FluidAudio 0.15.5 \(variant.rawValue) token-timing decode window; explicit segment and chunk/seam provenance unavailable"
                )
            ),
        ]
    }

    private static func modelIdentity(for variant: ParakeetVariant) -> ModelIdentity {
        let revision: String
        switch variant {
        case .fast:
            revision = "tdtCtc110m"
        case .accurate:
            revision = "v2"
        case .unified:
            revision = "offline-15s"
        }
        return ModelIdentity(
            identifier: variant.cacheFolderName,
            version: "0.15.5",
            revision: revision,
            quantization: "int8",
            computeUnits: "cpuAndNeuralEngine"
        )
    }

    private static func passMetadata(
        for variant: ParakeetVariant,
        providerDecodeID: String
    ) -> RecognitionPassMetadata {
        let strategy: String
        switch variant {
        case .unified:
            strategy = "offline-unified-15s"
        case .fast, .accurate:
            strategy = "offline-tdt"
        }
        return RecognitionPassMetadata(
            strategy: strategy,
            protocolVersion: RecognitionProtocolV2Envelope.version,
            requestID: providerDecodeID,
            adaptiveFallback: false
        )
    }

    private static func isWordBoundary(_ token: String) -> Bool {
        token.hasPrefix("▁") || token.hasPrefix(" ")
    }

    private static func stripWordBoundaryPrefix(_ token: String) -> String {
        isWordBoundary(token) ? String(token.dropFirst()) : token
    }

    private static func validTiming(_ timing: TokenTiming) -> Bool {
        timing.startTime.isFinite
            && timing.endTime.isFinite
            && timing.startTime >= 0
            && timing.endTime >= timing.startTime
    }

    private static func validNonNegative(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }

    private static func validNonNegative(_ value: TimeInterval?) -> Double? {
        value.flatMap(validNonNegative)
    }

    private static func validProbability(_ value: Float) -> Double? {
        value.isFinite && (0...1).contains(value) ? Double(value) : nil
    }
}
