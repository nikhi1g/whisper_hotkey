import Darwin
import Foundation
import XCTest
@testable import WhisperHotkeyASR

final class RecognitionTests: XCTestCase {
    func testHelperArgumentsUseAccuracyFirstDefaults() {
        let options = WhisperRecognitionOptions()
        let arguments = WhisperHelperInvocation.arguments(
            modelURL: URL(fileURLWithPath: "/private/model.bin"),
            options: options
        )

        XCTAssertEqual(arguments.value(after: "--threads"), "4")
        XCTAssertEqual(arguments.value(after: "--strategy"), "beam")
        XCTAssertEqual(arguments.value(after: "--beam-size"), "5")
        XCTAssertEqual(
            arguments.value(after: "--model"),
            "/private/model.bin"
        )
    }

    func testGreedyStrategyIsInternallySelectable() {
        var options = WhisperRecognitionOptions()
        options.strategy = .greedy
        let helperArguments = WhisperHelperInvocation.arguments(
            modelURL: URL(fileURLWithPath: "/private/model.bin"),
            options: options
        )
        let commandLineArguments = WhisperCommandLineInvocation.arguments(
            modelURL: URL(fileURLWithPath: "/private/model.bin"),
            audioURL: URL(fileURLWithPath: "/private/audio.wav"),
            options: options
        )

        XCTAssertEqual(
            helperArguments.value(after: "--strategy"),
            "greedy"
        )
        XCTAssertEqual(commandLineArguments.value(after: "-bs"), "1")
    }

    func testCommandLineFallbackUsesMetalThenCPUOnlyWhenRequested() {
        let options = WhisperRecognitionOptions()
        let model = URL(fileURLWithPath: "/private/model.bin")
        let audio = URL(fileURLWithPath: "/private/audio.wav")
        let metal = WhisperCommandLineInvocation.arguments(
            modelURL: model,
            audioURL: audio,
            options: options
        )
        let cpu = WhisperCommandLineInvocation.arguments(
            modelURL: model,
            audioURL: audio,
            options: options,
            disableGPU: true
        )

        XCTAssertFalse(metal.contains("-ng"))
        XCTAssertTrue(cpu.contains("-ng"))
        XCTAssertEqual(metal.value(after: "-t"), "4")
        XCTAssertEqual(metal.value(after: "-bs"), "5")
        XCTAssertTrue(metal.contains("-fa"))
        XCTAssertTrue(metal.contains("-sns"))
        XCTAssertTrue(metal.contains("-nt"))
        XCTAssertTrue(metal.contains("-np"))
        XCTAssertEqual(metal.suffix(2), ["-l", "en"])
    }

    func testMetalClassifierIgnoresRoutineBackendLoadingForOtherErrors() {
        let ordinaryFailure = WhisperCommandLineProcess.Failure(
            status: 1,
            diagnostic: """
            load_backend: loaded MTL backend
            error: failed to open audio file
            """
        )
        XCTAssertFalse(ordinaryFailure.isMetalSpecific)
        XCTAssertFalse(ordinaryFailure.shouldRetryWithoutGPU)

        XCTAssertTrue(
            WhisperCommandLineProcess.Failure(
                status: 1,
                diagnostic: "ggml_metal_init: error: Metal device failed"
            ).shouldRetryWithoutGPU
        )
        XCTAssertFalse(
            WhisperCommandLineProcess.Failure(
                status: SIGKILL,
                diagnostic: "load_backend: loaded MTL backend"
            ).shouldRetryWithoutGPU
        )
        XCTAssertTrue(
            WhisperCommandLineProcess.Failure(
                status: SIGKILL,
                diagnostic: "load_backend: loaded MTL backend",
                terminationReason: .uncaughtSignal
            ).shouldRetryWithoutGPU
        )
    }

    func testHelperProtocolParsesReadyResultAndError() throws {
        XCTAssertEqual(
            try WhisperHelperProtocol.parse(#"{"event":"ready"}"#),
            .ready
        )
        XCTAssertEqual(
            try WhisperHelperProtocol.parse(
                #"{"event":"result","text":"Hello \"world\"."}"#
            ),
            .result(#"Hello "world"."#)
        )
        XCTAssertEqual(
            try WhisperHelperProtocol.parse(
                #"{"event":"error","code":"no_speech","message":"quiet"}"#
            ),
            .error(code: "no_speech", message: "quiet")
        )
        XCTAssertThrowsError(
            try WhisperHelperProtocol.parse(
                #"{"event":"unknown","text":"private words"}"#
            )
        )
    }

    func testTranscribeCommandIsOneJSONLineWithPrivatePath() throws {
        let data = try WhisperHelperProtocol.transcribeCommand(
            audioURL: URL(
                fileURLWithPath: #"/private/a folder/"quoted".wav"#
            )
        )
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(data.filter { $0 == 0x0A }.count, 1)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: data.dropLast()
            ) as? [String: String]
        )
        XCTAssertEqual(object["command"], "transcribe")
        XCTAssertEqual(
            object["audioPath"],
            #"/private/a folder/"quoted".wav"#
        )
    }

    func testDiscoveryUsesOnlyBaseEnglishModelAndExecutableHelper()
        throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-discovery-\(UUID().uuidString)",
                isDirectory: true
            )
        let home = root.appendingPathComponent("home", isDirectory: true)
        let model = home.appendingPathComponent(
            ".cache/whisper/ggml-base.en.bin"
        )
        let helper = root.appendingPathComponent("WhisperModelHelper")
        try FileManager.default.createDirectory(
            at: model.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0]).write(to: model)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: helper.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = try WhisperRuntimeDiscovery.discover(
            environment: [
                WhisperRuntimeDiscovery.helperEnvironmentKey: helper.path
            ],
            homeDirectory: home
        )

        XCTAssertEqual(configuration.modelURL, model)
        XCTAssertEqual(configuration.helperExecutableURL, helper)
        XCTAssertEqual(
            WhisperRuntimeDiscovery.modelURL(homeDirectory: home),
            model
        )
    }

    func testDiscoveryReportsExactMissingModelPath() {
        let home = URL(fileURLWithPath: "/private/missing-home")
        XCTAssertThrowsError(
            try WhisperRuntimeDiscovery.discover(
                environment: [:],
                homeDirectory: home
            )
        ) { error in
            XCTAssertEqual(
                error as? WhisperASRError,
                .modelMissing(
                    "/private/missing-home/.cache/whisper/ggml-base.en.bin"
                )
            )
        }
    }

    func testSanitizerRemovesTransportAndNonSpeechNoiseOnly() {
        let raw = """
        \u{001B}[32m[00:00:00.000 --> 00:00:01.000]  Find deep learning.\u{001B}[0m
        [BLANK_AUDIO]
        <|endoftext|> by Ian Goodfellow
        """

        XCTAssertEqual(
            WhisperTranscriptSanitizer.clean(raw),
            "Find deep learning. by Ian Goodfellow"
        )
        XCTAssertEqual(
            WhisperTranscriptSanitizer.clean("[silence]\n (music) "),
            ""
        )
        XCTAssertEqual(
            WhisperTranscriptSanitizer.clean(
                "Don't rewrite e-mail or iPhone 15."
            ),
            "Don't rewrite e-mail or iPhone 15."
        )
    }

    func testOwnedProcessTerminationKillsStubbornProcessGroup() throws {
        let process = Process()
        let pidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-process-\(UUID().uuidString).pid"
            )
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "trap '' TERM; sleep 30 & echo $! > '\(pidURL.path)'; wait",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            try? FileManager.default.removeItem(at: pidURL)
            if process.isRunning {
                OwnedProcessTermination.terminate(
                    process,
                    wait: true,
                    grace: 0.05
                )
            }
        }

        let pidDeadline = Date().addingTimeInterval(1)
        while !FileManager.default.fileExists(atPath: pidURL.path),
              Date() < pidDeadline {
            usleep(10_000)
        }
        let childPID = try XCTUnwrap(
            Int32(
                String(contentsOf: pidURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        XCTAssertEqual(
            getpgid(process.processIdentifier),
            process.processIdentifier
        )
        XCTAssertEqual(
            getpgid(childPID),
            process.processIdentifier
        )

        OwnedProcessTermination.terminate(
            process,
            wait: true,
            grace: 0.05
        )

        XCTAssertFalse(process.isRunning)
        let deadline = Date().addingTimeInterval(0.5)
        while Darwin.kill(childPID, 0) == 0, Date() < deadline {
            usleep(10_000)
        }
        XCTAssertEqual(
            Darwin.kill(childPID, 0),
            -1,
            "The helper descendant must not survive its process group."
        )
    }

    func testImmediateNewDictationWaitsForCancelledGroupAndRejectsStaleLease()
        throws {
        let controller = OwnedProcessController()
        let firstLease = controller.beginDictation()
        let first = Process()
        first.executableURL = URL(fileURLWithPath: "/bin/sh")
        first.arguments = [
            "-c",
            "trap '' TERM; sleep 30 & wait",
        ]
        first.standardOutput = FileHandle.nullDevice
        first.standardError = FileHandle.nullDevice
        XCTAssertTrue(controller.install(first, lease: firstLease))
        try first.run()

        controller.cancel(firstLease, wait: false)
        let secondLease = controller.beginDictation()

        XCTAssertFalse(first.isRunning)
        XCTAssertFalse(
            controller.install(Process(), lease: firstLease),
            "A cancelled generation must never overwrite the new owner."
        )

        let second = Process()
        second.executableURL = URL(fileURLWithPath: "/bin/sleep")
        second.arguments = ["30"]
        second.standardOutput = FileHandle.nullDevice
        second.standardError = FileHandle.nullDevice
        XCTAssertTrue(controller.install(second, lease: secondLease))
        try second.run()
        controller.finish(secondLease, wait: true)
        XCTAssertFalse(second.isRunning)
    }

    func testHelperStartupFailureFallsBackToCommandLineAndDeletesAudio()
        async throws {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            printf '%s\\n' '{"event":"error","code":"model_load_failed","message":"load failed"}'
            exit 70
            """
        )
        defer { fixture.delete() }
        let audio = try fixture.makeAudio()
        let audioDirectory = audio.url.deletingLastPathComponent()
        var options = WhisperRecognitionOptions()
        options.preloadTimeout = 0.2
        options.transcriptionTimeout = 1
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration,
            options: options
        )

        let transcript = try await recognizer.transcribe(audio)

        XCTAssertEqual(transcript, "fallback words")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: audioDirectory.path)
        )
        let readiness = await recognizer.readiness
        XCTAssertEqual(readiness, .idle)
    }

    func testHelperReadinessTimeoutStillFallsBackWhenNotCancelled()
        async throws {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            sleep 30
            """
        )
        defer { fixture.delete() }
        let audio = try fixture.makeAudio()
        var options = WhisperRecognitionOptions()
        options.preloadTimeout = 0.05
        options.transcriptionTimeout = 1
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration,
            options: options
        )

        let transcript = try await recognizer.transcribe(audio)

        XCTAssertEqual(transcript, "fallback words")
    }

    func testSignalTerminatedMetalAttemptRetriesOnceWithoutGPU()
        async throws {
        let fixture = try RecognitionFixture(
            helperScript: "#!/bin/sh\nexit 70\n",
            commandLineScript: """
            #!/bin/sh
            printf A >> "${0}.attempts"
            for argument in "$@"; do
                if [ "$argument" = "-ng" ]; then
                    printf '%s\\n' 'cpu fallback words'
                    exit 0
                fi
            done
            kill -KILL "$$"
            """
        )
        defer { fixture.delete() }
        let configuration = WhisperRuntimeConfiguration(
            helperExecutableURL: nil,
            commandLineExecutableURL:
                fixture.configuration.commandLineExecutableURL,
            modelURL: fixture.configuration.modelURL
        )
        let recognizer = WhisperRecognizer(configuration: configuration)
        let audio = try fixture.makeAudio()
        let audioDirectory = audio.url.deletingLastPathComponent()

        let transcript = try await recognizer.transcribe(audio)

        XCTAssertEqual(transcript, "cpu fallback words")
        XCTAssertEqual(try fixture.commandLineAttemptCount(), 2)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: audioDirectory.path)
        )
    }

    func testOrdinaryNonMetalExitDoesNotRetryWithoutGPU()
        async throws {
        let fixture = try RecognitionFixture(
            helperScript: "#!/bin/sh\nexit 70\n",
            commandLineScript: """
            #!/bin/sh
            printf A >> "${0}.attempts"
            for argument in "$@"; do
                if [ "$argument" = "-ng" ]; then
                    printf '%s\\n' 'unexpected retry'
                    exit 0
                fi
            done
            printf '%s\\n' 'failed to open audio file' >&2
            exit 17
            """
        )
        defer { fixture.delete() }
        let configuration = WhisperRuntimeConfiguration(
            helperExecutableURL: nil,
            commandLineExecutableURL:
                fixture.configuration.commandLineExecutableURL,
            modelURL: fixture.configuration.modelURL
        )
        let recognizer = WhisperRecognizer(configuration: configuration)
        let audio = try fixture.makeAudio()
        let audioDirectory = audio.url.deletingLastPathComponent()

        do {
            _ = try await recognizer.transcribe(audio)
            XCTFail("Expected the ordinary CLI failure.")
        } catch {
            XCTAssertEqual(
                error as? WhisperASRError,
                .commandLineFailed(17)
            )
        }

        XCTAssertEqual(try fixture.commandLineAttemptCount(), 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: audioDirectory.path)
        )
    }

    func testFailedPreloadIsCachedForActiveLeaseBeforeFallback()
        async throws {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            printf A >> "${0}.attempts"
            printf '%s\\n' '{"event":"error","code":"model_load_failed","message":"load failed"}'
            """
        )
        defer { fixture.delete() }
        var options = WhisperRecognitionOptions()
        options.preloadTimeout = 1
        options.transcriptionTimeout = 1
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration,
            options: options
        )

        do {
            try await recognizer.preload()
            XCTFail("Expected the helper preload failure.")
        } catch {
            XCTAssertEqual(
                error as? WhisperASRError,
                .helperFailed("model preload failed")
            )
        }

        let transcript = try await recognizer.transcribe(
            fixture.makeAudio()
        )
        XCTAssertEqual(transcript, "fallback words")
        XCTAssertEqual(try fixture.helperAttemptCount(), 1)

        do {
            try await recognizer.preload()
            XCTFail("A new lease should make one fresh helper attempt.")
        } catch {
            XCTAssertEqual(
                error as? WhisperASRError,
                .helperFailed("model preload failed")
            )
        }
        XCTAssertEqual(try fixture.helperAttemptCount(), 2)
        await recognizer.cancel()
    }

    func testFailureDeletesAudioWithoutPublishingHelperDiagnostic()
        async throws {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            printf '%s\\n' '{"event":"error","code":"inference_failed","message":"secret words at /private/dictation.wav"}'
            exit 70
            """
        )
        defer { fixture.delete() }
        let privateConfiguration = WhisperRuntimeConfiguration(
            helperExecutableURL:
                fixture.configuration.helperExecutableURL,
            commandLineExecutableURL: nil,
            modelURL: fixture.configuration.modelURL
        )
        let audio = try fixture.makeAudio()
        let audioDirectory = audio.url.deletingLastPathComponent()
        let recognizer = WhisperRecognizer(
            configuration: privateConfiguration
        )

        do {
            _ = try await recognizer.transcribe(audio)
            XCTFail("Expected local fallback availability failure.")
        } catch {
            XCTAssertEqual(
                error as? WhisperASRError,
                .commandLineUnavailable
            )
            XCTAssertFalse(
                error.localizedDescription.contains("secret words")
            )
            XCTAssertFalse(
                error.localizedDescription.contains("dictation.wav")
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: audioDirectory.path)
        )
    }

    func testShutdownWaitsForPreloadedHelperProcessGroup() async throws {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            trap '' TERM
            sleep 30 &
            echo $! > "$2.pid"
            printf '%s\\n' '{"event":"ready"}'
            wait
            """
        )
        defer { fixture.delete() }
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration
        )
        try await recognizer.preload()
        let childPIDURL = URL(
            fileURLWithPath: fixture.configuration.modelURL.path + ".pid"
        )
        let childPID = try XCTUnwrap(
            Int32(
                String(contentsOf: childPIDURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )

        await recognizer.shutdown()

        let readiness = await recognizer.readiness
        XCTAssertEqual(readiness, .idle)
        XCTAssertEqual(
            Darwin.kill(childPID, 0),
            -1,
            "Shutdown must not return while a helper descendant survives."
        )
    }

    func testShutdownTerminalStateRejectsLateWorkAndDeletesAudio()
        async throws {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            printf launched > "${0}.attempts"
            printf '%s\\n' '{"event":"ready"}'
            sleep 30
            """
        )
        defer { fixture.delete() }
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration
        )
        await recognizer.shutdown()
        await recognizer.cancel()

        do {
            try await recognizer.preload()
            XCTFail("Preload must remain rejected after shutdown.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error).")
        }

        let audio = try fixture.makeAudio()
        let audioDirectory = audio.url.deletingLastPathComponent()
        do {
            _ = try await recognizer.transcribe(audio)
            XCTFail("Transcription must remain rejected after shutdown.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error).")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: audioDirectory.path),
            "Rejected transcription must still remove its private audio."
        )
        XCTAssertEqual(
            try fixture.helperAttemptCount(),
            0
        )
        let readiness = await recognizer.readiness
        XCTAssertEqual(readiness, .idle)
    }
}

private extension Array where Element == String {
    func value(after flag: String) -> String? {
        guard let index = firstIndex(of: flag),
              indices.contains(index + 1) else {
            return nil
        }
        return self[index + 1]
    }
}

private final class RecognitionFixture {
    let root: URL
    let configuration: WhisperRuntimeConfiguration

    init(
        helperScript: String,
        commandLineScript: String = """
        #!/bin/sh
        printf '%s\\n' 'fallback words'
        """
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-recognition-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let helper = root.appendingPathComponent("WhisperModelHelper")
        let commandLine = root.appendingPathComponent("whisper-cli")
        let model = root.appendingPathComponent("ggml-base.en.bin")
        try Data(helperScript.utf8).write(to: helper)
        try Data(commandLineScript.utf8).write(to: commandLine)
        try Data([0]).write(to: model)
        for executable in [helper, commandLine] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: executable.path
            )
        }
        configuration = WhisperRuntimeConfiguration(
            helperExecutableURL: helper,
            commandLineExecutableURL: commandLine,
            modelURL: model
        )
    }

    func makeAudio() throws -> WhisperAudioFile {
        let directory = root.appendingPathComponent(
            "audio-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("dictation.wav")
        try Data([0]).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return WhisperAudioFile(url: url, directoryURL: directory)
    }

    func delete() {
        try? FileManager.default.removeItem(at: root)
    }

    func helperAttemptCount() throws -> Int {
        try attemptCount(
            executableURL: configuration.helperExecutableURL
        )
    }

    func commandLineAttemptCount() throws -> Int {
        try attemptCount(
            executableURL: configuration.commandLineExecutableURL
        )
    }

    private func attemptCount(executableURL: URL?) throws -> Int {
        guard let executableURL else { return 0 }
        let attempts = URL(
            fileURLWithPath: executableURL.path + ".attempts"
        )
        guard FileManager.default.fileExists(atPath: attempts.path) else {
            return 0
        }
        return try Data(contentsOf: attempts).count
    }
}
