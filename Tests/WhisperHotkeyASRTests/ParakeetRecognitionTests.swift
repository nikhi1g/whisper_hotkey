import Foundation
import XCTest
@testable import WhisperHotkeyASR
import WhisperHotkeyCore
import FluidAudio

final class ParakeetRecognitionTests: XCTestCase {
    func testPinnedFluidAudioTDTResultPreservesWordsTimingEvidenceAndProvenance() {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let decodeID = "tdt-decode-1"
        let fluidResult = ASRResult(
            text: "Hello world!",
            confidence: 0.87,
            duration: 1.2,
            processingTime: 0.04,
            tokenTimings: [
                TokenTiming(
                    token: "▁Hello",
                    tokenId: 11,
                    startTime: 0.10,
                    endTime: 0.34,
                    confidence: 0.91
                ),
                TokenTiming(
                    token: "▁world",
                    tokenId: 12,
                    startTime: 0.40,
                    endTime: 0.72,
                    confidence: 0.83
                ),
                TokenTiming(
                    token: "!",
                    tokenId: 13,
                    startTime: 0.72,
                    endTime: 0.78,
                    confidence: 0.79
                ),
            ]
        )

        for variant in [ParakeetVariant.fast, .accurate] {
            let result = ParakeetRecognitionAdapter.result(
                from: fluidResult,
                variant: variant,
                sessionID: sessionID,
                generation: 9,
                pass: .primaryFullSession,
                providerDecodeID: decodeID
            )

            XCTAssertEqual(result.renderedText, fluidResult.text)
            XCTAssertEqual(result.generation, 9)
            XCTAssertEqual(result.words.map(\.text), ["Hello", "world!"])
            XCTAssertEqual(result.words.map(\.id.providerDecodeID), [decodeID, decodeID])
            XCTAssertEqual(result.words.map(\.id.wordIndex), [0, 1])
            XCTAssertEqual(result.words[0].startSeconds, 0.10)
            XCTAssertEqual(result.words[1].endSeconds, 0.78)
            XCTAssertEqual(result.words[0].rawEvidence.tokenIDs, [11])
            XCTAssertEqual(result.words[1].rawEvidence.tokenIDs, [12, 13])
            XCTAssertEqual(
                result.words[1].rawEvidence.tokenLogProbabilities.count,
                2
            )
            XCTAssertEqual(
                result.words[1].rawEvidence.tokenLogProbabilities[0],
                log(0.83),
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                result.words[1].rawEvidence.tokenLogProbabilities[1],
                log(0.79),
                accuracy: 0.000_001
            )
            XCTAssertTrue(
                result.words[1].rawEvidence.availability.contains(
                    .tokenLogProbabilities
                )
            )
            XCTAssertEqual(
                result.words[1].rawEvidence.posterior ?? -1,
                (0.83 + 0.79) / 2,
                accuracy: 0.000_001
            )
            XCTAssertTrue(
                result.words[1].rawEvidence.availability.contains(.posterior)
            )
            XCTAssertTrue(
                result.words[1].rawEvidence.availability.contains(.timing)
            )
            XCTAssertEqual(
                result.utteranceEvidence.sequenceScore ?? -1,
                0.87,
                accuracy: 0.000_001
            )
            XCTAssertEqual(result.timing.audioDurationSeconds, 1.2)
            XCTAssertEqual(result.timing.decodeDurationSeconds, 0.04)
            XCTAssertEqual(result.segments.count, 1)
            XCTAssertEqual(result.segments[0].wordIDs, result.words.map(\.id))
            XCTAssertEqual(
                result.words[0].provenance,
                .primary(providerDecodeID: decodeID, wordIndex: 0)
            )
            XCTAssertTrue(
                result.segments[0].provenance.reason?.contains("FluidAudio 0.15.5") == true
            )
            XCTAssertEqual(result.model.identifier, variant.cacheFolderName)
            XCTAssertEqual(result.model.version, "0.15.5")
            XCTAssertEqual(result.model.computeUnits, "cpuAndNeuralEngine")
            XCTAssertEqual(result.passMetadata.requestID, decodeID)
        }
    }

    func testMissingFluidAudioTokenConfidenceRemainsUnavailable() {
        let fluidResult = ASRResult(
            text: "unknown",
            confidence: 0.6,
            duration: 0.5,
            processingTime: 0.02,
            tokenTimings: [
                TokenTiming(
                    token: "▁unknown",
                    tokenId: 21,
                    startTime: 0.05,
                    endTime: 0.31,
                    confidence: .nan
                ),
            ]
        )

        let result = ParakeetRecognitionAdapter.result(
            from: fluidResult,
            variant: .accurate,
            sessionID: UUID(),
            generation: 0,
            pass: .primaryFullSession,
            providerDecodeID: "missing-confidence"
        )

        XCTAssertEqual(result.words.count, 1)
        XCTAssertNil(result.words[0].rawEvidence.posterior)
        XCTAssertFalse(
            result.words[0].rawEvidence.availability.contains(.posterior)
        )
        XCTAssertTrue(
            result.words[0].rawEvidence.tokenLogProbabilities.isEmpty
        )
        XCTAssertFalse(
            result.words[0].rawEvidence.availability.contains(
                .tokenLogProbabilities
            )
        )
        XCTAssertEqual(result.words[0].rawEvidence.tokenIDs, [21])
        XCTAssertNil(result.words[0].calibratedErrorProbability)
    }

    func testUnifiedStringOnlyAPIDoesNotInventWordSegmentsOrConfidence() {
        let result = ParakeetRecognitionAdapter.textOnlyResult(
            text: "Unified transcript",
            variant: .unified,
            sessionID: UUID(),
            generation: 4,
            pass: .primaryFullSession,
            providerDecodeID: "unified-decode-1",
            completeness: .finalSession,
            audioDurationSeconds: 1.75,
            decodeDurationSeconds: 0.03
        )

        XCTAssertEqual(result.engine, .parakeetUnifiedCoreML)
        XCTAssertEqual(result.model.identifier, "parakeet-unified-en-0.6b")
        XCTAssertEqual(result.model.revision, "offline-15s")
        XCTAssertEqual(result.text, "Unified transcript")
        XCTAssertTrue(result.words.isEmpty)
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertEqual(result.utteranceEvidence, .unavailable)
        XCTAssertEqual(result.timing.audioDurationSeconds, 1.75)
        XCTAssertEqual(result.passMetadata.strategy, "offline-unified-15s")
    }

    func testTokenBoundaryAndBlankHandlingKeepsWordsAndRangesOrdered() {
        let fluidResult = ASRResult(
            text: "Hello, world",
            confidence: 0.8,
            duration: 1,
            processingTime: 0.01,
            tokenTimings: [
                TokenTiming(
                    token: " Hello",
                    tokenId: 1,
                    startTime: 0.1,
                    endTime: 0.2,
                    confidence: 0.9
                ),
                TokenTiming(
                    token: ",",
                    tokenId: 2,
                    startTime: 0.2,
                    endTime: 0.23,
                    confidence: 0.8
                ),
                TokenTiming(
                    token: "<blank>",
                    tokenId: 3,
                    startTime: 0.23,
                    endTime: 0.24,
                    confidence: 0
                ),
                TokenTiming(
                    token: "▁world",
                    tokenId: 4,
                    startTime: 0.4,
                    endTime: 0.6,
                    confidence: 0.7
                ),
            ]
        )

        let result = ParakeetRecognitionAdapter.result(
            from: fluidResult,
            variant: .fast,
            sessionID: UUID(),
            generation: 0,
            pass: .primaryFullSession,
            providerDecodeID: "boundary-decode"
        )

        XCTAssertEqual(result.words.map(\.text), ["Hello,", "world"])
        XCTAssertEqual(result.words.map(\.tokenRange), [0..<2, 3..<4])
        XCTAssertEqual(result.segments.first?.tokenRange, 0..<4)
        XCTAssertEqual(result.words.map(\.startSeconds), [0.1, 0.4])
        XCTAssertEqual(result.words.map(\.endSeconds), [0.23, 0.6])
    }

    func testDiscoveryNeedsNoLocalFilesAndCarriesTheVariant() throws {
        // Parakeet checkpoints are fetched by FluidAudio on first use, so
        // discovery must succeed against an empty home directory. Every other
        // engine throws here.
        let home = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let configuration = try WhisperRuntimeDiscovery.discover(
            model: .largeV3TurboQ5,
            engine: .parakeetCoreML,
            parakeetVariant: .accurate,
            environment: [:],
            homeDirectory: home
        )
        XCTAssertEqual(configuration.engine, .parakeetCoreML)
        XCTAssertEqual(configuration.parakeetVariant, .accurate)
        XCTAssertNil(configuration.helperExecutableURL)
        XCTAssertNil(configuration.commandLineExecutableURL)

        XCTAssertThrowsError(
            try WhisperRuntimeDiscovery.discover(
                model: .largeV3TurboQ5,
                engine: .whisperCppMetal,
                environment: [:],
                homeDirectory: home
            )
        )
    }

    func testParakeetIgnoresTheWhisperModelSelection() throws {
        // Parakeet keeps its own selection, so the whisper model in play must
        // not influence which checkpoint runs.
        let home = URL(fileURLWithPath: "/private/home", isDirectory: true)
        for model in DictationModel.allCases {
            let configuration = try WhisperRuntimeDiscovery.discover(
                model: model,
                engine: .parakeetCoreML,
                parakeetVariant: .fast,
                environment: [:],
                homeDirectory: home
            )
            XCTAssertEqual(configuration.parakeetVariant, .fast)
            XCTAssertEqual(
                configuration.modelURL,
                WhisperHotkeyPaths.parakeetModelURL(
                    for: .fast,
                    homeDirectory: home
                )
            )
        }
    }

    func testEngineTraitsMatchTheParakeetPipeline() {
        // Parakeet is a transducer: no beam search, no helper subprocess, and
        // no prompt to bias the decode with.
        XCTAssertFalse(RecognitionEngine.parakeetCoreML.usesWhisperDecoding)
        XCTAssertFalse(RecognitionEngine.parakeetCoreML.usesLocalHelper)
        XCTAssertFalse(
            RecognitionEngine.parakeetCoreML.supportsPromptConditioning
        )
        XCTAssertTrue(RecognitionEngine.whisperCppMetal.usesWhisperDecoding)
        XCTAssertTrue(RecognitionEngine.whisperCppMetal.usesLocalHelper)
    }

    func testInstallerReportsAMissingCheckpointRatherThanFetchingIt() async {
        // A dictation must never trigger a several-hundred-megabyte download.
        // The recognizer reports the missing path so the badge can show a real
        // error instead of stalling behind a Transcribing badge.
        let runtime = ParakeetRuntime(variant: .accurate)
        guard !ParakeetModelInstaller.isInstalled(.accurate) else {
            // Installed on this machine, so assert the inverse: loading must
            // not have to reach the network to succeed.
            XCTAssertTrue(
                ParakeetModelInstaller.cacheDirectory(for: .accurate)
                    .path.contains("FluidAudio")
            )
            return
        }
        do {
            _ = try await runtime.transcribe(
                audioURL: URL(fileURLWithPath: "/dev/null")
            )
            XCTFail("a missing checkpoint should not transcribe")
        } catch let error as WhisperASRError {
            guard case .modelMissing = error else {
                return XCTFail("expected modelMissing, got \(error)")
            }
        } catch {
            XCTFail("expected modelMissing, got \(error)")
        }
    }

    /// Unified became a bundled checkpoint in 3.7.0 and is now the default, so
    /// a first dictation must not depend on a download. It still needs its own
    /// directory: it is a different manager with a different decoder.
    func testUnifiedIsBundledAndHasItsOwnDirectory() {
        XCTAssertTrue(ParakeetVariant.unified.shipsInsideTheApp)
        XCTAssertNotEqual(
            ParakeetModelInstaller.cacheDirectory(for: .unified),
            ParakeetModelInstaller.cacheDirectory(for: .accurate)
        )
    }

    func testCacheDirectoriesDifferPerVariant() {
        XCTAssertNotEqual(
            ParakeetModelInstaller.cacheDirectory(for: .fast),
            ParakeetModelInstaller.cacheDirectory(for: .accurate)
        )
    }

    /// Proves the checkpoints bundled into the app are loadable, without any
    /// FluidAudio cache present. Gated on an installed app because the test
    /// bundle is not the app bundle.
    func testBundledCheckpointsLoadFromTheApplicationBundle() async throws {
        let appPath = ProcessInfo.processInfo
            .environment["WHISPER_HOTKEY_APP_BUNDLE"]
            ?? "/Applications/whisper_hotkey.app"
        guard let bundle = Bundle(url: URL(fileURLWithPath: appPath)) else {
            throw XCTSkip("no app bundle at \(appPath)")
        }
        // Unified is downloaded on demand rather than bundled, so it is not
        // expected inside the application.
        for variant in ParakeetVariant.allCases where variant.shipsInsideTheApp {
            let directory = ParakeetModelInstaller.bundledDirectory(
                for: variant,
                bundle: bundle
            )
            XCTAssertNotNil(
                directory,
                "\(variant) is not bundled or its files are incomplete"
            )
            XCTAssertTrue(
                ParakeetModelInstaller.isInstalled(variant, bundle: bundle),
                "\(variant) should report installed from the bundle alone"
            )
        }
    }

    /// End-to-end Unified recognition through the recognizer, not the
    /// benchmark harness. Skipped unless the checkpoint is installed, because
    /// it is a 594 MB on-demand download.
    func testUnifiedTranscribesThroughTheRecognizer() async throws {
        guard ParakeetModelInstaller.isInstalled(.unified) else {
            throw XCTSkip("Unified checkpoint not installed")
        }
        guard let fixture = ProcessInfo.processInfo
            .environment["WHISPER_HOTKEY_PARAKEET_FIXTURE"] else {
            throw XCTSkip("set WHISPER_HOTKEY_PARAKEET_FIXTURE to run")
        }
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let audioURL = directory.appendingPathComponent("fixture.wav")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: fixture),
            to: audioURL
        )
        let audio = WhisperAudioFile(
            url: audioURL,
            directoryURL: directory,
            speechPresence: .present
        )
        let configuration = try WhisperRuntimeDiscovery.discover(
            model: .baseEnglish,
            engine: .parakeetCoreML,
            parakeetVariant: .unified,
            environment: [:]
        )
        let recognizer = WhisperRecognizer(configuration: configuration)
        let transcript = try await recognizer.transcribe(audio)
        XCTAssertFalse(transcript.isEmpty)
    }

    /// End-to-end recognition against a real checkpoint. Skipped unless
    /// `WHISPER_HOTKEY_PARAKEET_FIXTURE` points at a 16 kHz mono PCM16 WAV,
    /// because it downloads ~220 MB on a cold cache.
    func testTranscribesAFixtureThroughTheRecognizer() async throws {
        guard let fixture = ProcessInfo.processInfo
            .environment["WHISPER_HOTKEY_PARAKEET_FIXTURE"] else {
            throw XCTSkip("set WHISPER_HOTKEY_PARAKEET_FIXTURE to run")
        }
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let audioURL = directory.appendingPathComponent("fixture.wav")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: fixture),
            to: audioURL
        )
        let audio = WhisperAudioFile(
            url: audioURL,
            directoryURL: directory,
            speechPresence: .present
        )
        let configuration = try WhisperRuntimeDiscovery.discover(
            model: .baseEnglish,
            engine: .parakeetCoreML,
            environment: [:]
        )
        let recognizer = WhisperRecognizer(configuration: configuration)
        let transcript = try await recognizer.transcribe(audio)
        XCTAssertFalse(transcript.isEmpty)
    }
}
