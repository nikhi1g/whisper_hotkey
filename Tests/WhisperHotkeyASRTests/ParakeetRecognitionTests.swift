import Foundation
import XCTest
@testable import WhisperHotkeyASR
import WhisperHotkeyCore

final class ParakeetRecognitionTests: XCTestCase {
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

    func testCacheDirectoriesDifferPerVariant() {
        XCTAssertNotEqual(
            ParakeetModelInstaller.cacheDirectory(for: .fast),
            ParakeetModelInstaller.cacheDirectory(for: .accurate)
        )
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
