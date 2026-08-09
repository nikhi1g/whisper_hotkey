import Darwin
import Foundation
import XCTest
@testable import WhisperHotkeyASR
import WhisperHotkeyCore

final class RecognitionTests: XCTestCase {
    func testHelperArgumentsUseAccuracyFirstDefaults() {
        let options = WhisperRecognitionOptions()
        let arguments = WhisperHelperInvocation.arguments(
            modelURL: URL(fileURLWithPath: "/private/model.bin"),
            options: options
        )

        XCTAssertEqual(
            arguments.value(after: "--threads"),
            String(WhisperRuntimeDiscovery.recommendedThreadCount())
        )
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

    func testAdaptiveStrategyIsPassedOnlyToTheOwnedHelper() {
        var options = WhisperRecognitionOptions()
        options.strategy = .adaptive

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
            "adaptive"
        )
        XCTAssertEqual(commandLineArguments.value(after: "-bs"), "5")
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
        XCTAssertEqual(
            metal.value(after: "-t"),
            String(WhisperRuntimeDiscovery.recommendedThreadCount())
        )
        XCTAssertEqual(metal.value(after: "-bs"), "5")
        XCTAssertTrue(metal.contains("-fa"))
        XCTAssertTrue(metal.contains("-sns"))
        XCTAssertTrue(metal.contains("-nt"))
        XCTAssertTrue(metal.contains("-np"))
        XCTAssertEqual(metal.suffix(2), ["-l", "en"])
    }

    func testAccuracyCapableCommandFallbackOmitsOnlyNoTimestampFlag() {
        let options = WhisperRecognitionOptions()
        let arguments = WhisperCommandLineInvocation.arguments(
            modelURL: URL(fileURLWithPath: "/private/model.bin"),
            audioURL: URL(fileURLWithPath: "/private/audio.wav"),
            options: options,
            accuracyCapable: true
        )

        XCTAssertFalse(arguments.contains("-nt"))
        XCTAssertTrue(arguments.contains("-np"))
        XCTAssertTrue(arguments.contains("-sns"))
        XCTAssertTrue(arguments.contains("-fa"))
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

    func testHelperProtocolParsesAdaptiveMetadataFromResultEvent() throws {
        let event =
            #"{"event":"result","text":"hello","protocolVersion":2,"requestID":"adaptive-1","engine":"whisperTurbo","pass":"primaryFullSession","window":{"startSample":0,"endSample":10,"sampleRate":16000},"averageLogProbability":-0.20,"noSpeechProbability":0.02,"weakTokenFraction":0.015,"repetitionDetected":false,"metadata":{"adaptiveFallback":true,"requestedStrategy":"adaptive","weakTokenFraction":0.03}}"#
        let parsed = try WhisperHelperProtocol.parse(event)
        guard case .resultRich(let hypothesis) = parsed else {
            XCTFail("Expected resultRich")
            return
        }

        XCTAssertTrue(hypothesis.adaptiveFallback)
        XCTAssertEqual(hypothesis.metadata["adaptiveFallback"], "true")
        XCTAssertEqual(hypothesis.metadata["requestedStrategy"], "adaptive")
        XCTAssertEqual(hypothesis.averageLogProbability, -0.20)
        XCTAssertEqual(hypothesis.noSpeechProbability, 0.02)
        XCTAssertEqual(hypothesis.weakTokenFraction, 0.015)
        XCTAssertEqual(hypothesis.repetitionDetected, false)

        let fallbackEvent =
            #"{"event":"result","text":"hello","protocolVersion":2,"requestID":"adaptive-2","engine":"whisperTurbo","pass":"primaryFullSession","window":{"startSample":0,"endSample":10,"sampleRate":16000},"averageLogProbability":-0.2,"maximumNoSpeechProbability":0.22,"repetitionDetected":false,"adaptiveFallback":false,"requestedStrategy":"beam","metadata":{"weakTokenFraction":0.04,"ignored":true}}"#
        let fallbackParsed = try WhisperHelperProtocol.parse(fallbackEvent)
        guard case .resultRich(let fallbackHypothesis) = fallbackParsed else {
            XCTFail("Expected resultRich")
            return
        }

        XCTAssertFalse(fallbackHypothesis.adaptiveFallback)
        XCTAssertEqual(
            fallbackHypothesis.metadata["requestedStrategy"],
            "beam"
        )
        XCTAssertEqual(fallbackHypothesis.noSpeechProbability, 0.22)
        XCTAssertEqual(fallbackHypothesis.weakTokenFraction, 0.04)
    }

    func testHelperProtocolRetainsFlatSnakeCaseTimingAndEvidence() throws {
        let event = #"{"event":"result","protocol_version":1,"request_id":"decode-1","engine":"whisperTurbo","model_id":"turbo-q5","pass":"primaryFullSession","text":"hello","window":{"start_sample":0,"end_sample":6400,"sample_rate":16000},"words":[{"text":"hello","start_seconds":0,"end_seconds":0.4,"posterior":0.8,"token_ids":[42],"token_log_probabilities":[-0.2]}],"segments":[{"text":"hello","start_seconds":0,"end_seconds":0.4,"words":[{"text":"hello","start_seconds":0,"end_seconds":0.4,"posterior":0.8}]}]}"#
        let parsed = try WhisperHelperProtocol.parse(event)
        guard case .resultRich(let hypothesis) = parsed else {
            XCTFail("Expected resultRich")
            return
        }

        XCTAssertEqual(hypothesis.metadata["requestID"], "decode-1")
        XCTAssertEqual(hypothesis.modelID, "turbo-q5")
        XCTAssertEqual(hypothesis.words.first?.startSeconds, 0)
        XCTAssertEqual(hypothesis.words.first?.endSeconds, 0.4)
        XCTAssertEqual(hypothesis.words.first?.confidence, 0.8)
        XCTAssertEqual(hypothesis.segments.first?.words.count, 1)
    }

    func testHelperProtocolParsesNestedV2EvidenceWithoutInventingAlternatives()
        throws
    {
        let line = #"{"protocol_version":2,"event":"result","request_id":"11111111-2222-3333-4444-555555555555","result":{"session_id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","generation":7,"engine":"whisperTurbo","model":{"identifier":"turbo-q5","compute_units":"metal"},"pass":"primaryFullSession","text":"hello world","words":[{"id":{"session_id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","provider_decode_id":"decode-1","word_index":0},"text":"hello","start_seconds":0,"end_seconds":0.4,"raw_evidence":{"token_ids":[42],"token_log_probabilities":[-0.2],"posterior":0.8,"availability":7}}],"segments":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","text":"hello world","start_seconds":0,"end_seconds":0.8,"word_ids":[]}],"alternatives":[],"utterance_evidence":{"average_log_probability":-0.2,"no_speech_probability":0.01,"maximum_no_speech_probability":0.01,"weak_token_fraction":0.02,"repetition_detected":false},"timing":{"audio_duration_seconds":0.8,"decode_duration_seconds":0.02},"completeness":"finalSession","pass_metadata":{"strategy":"beam","beam_size":5,"used_prompt":true,"prompt_character_count":12,"protocol_version":2,"request_id":"11111111-2222-3333-4444-555555555555","adaptive_fallback":false}}}"#

        let parsed = try WhisperHelperProtocol.parse(line)
        guard case .resultCanonical(let result) = parsed else {
            XCTFail("Expected canonical v2 result")
            return
        }

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.words.count, 1)
        XCTAssertEqual(result.words[0].rawEvidence.tokenIDs, [42])
        XCTAssertEqual(result.words[0].rawEvidence.tokenLogProbabilities, [-0.2])
        XCTAssertEqual(result.words[0].rawEvidence.posterior, 0.8)
        XCTAssertEqual(result.passMetadata.strategy, "beam")
        XCTAssertEqual(result.passMetadata.beamSize, 5)
        XCTAssertTrue(result.passMetadata.usedPrompt)
        XCTAssertEqual(result.passMetadata.promptCharacterCount, 12)
        XCTAssertTrue(result.alternatives.isEmpty)
    }

    func testHelperProtocolRejectsOversizedLineBeforeDecoding() {
        let line = "{\"event\":\"result\",\"text\":\""
            + String(repeating: "x", count: 1_048_577)
            + "\"}"
        XCTAssertThrowsError(try WhisperHelperProtocol.parse(line))
    }

    func testTranscribeCommandIsOneJSONLineWithPrivatePath() throws {
        let data = try WhisperHelperProtocol.transcribeCommand(
            audioURL: URL(
                fileURLWithPath: #"/private/a folder/"quoted".wav"#
            ),
            prompt: "Codex continues this sentence,"
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
        XCTAssertEqual(
            object["prompt"],
            "Codex continues this sentence,"
        )
    }

    func testDiscoveryUsesSelectedEnglishModelAndExecutableHelper()
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
            model: .baseEnglish,
            engine: .whisperCppMetal,
            environment: [
                WhisperRuntimeDiscovery.helperEnvironmentKey: helper.path
            ],
            homeDirectory: home
        )

        XCTAssertEqual(configuration.modelURL, model)
        XCTAssertEqual(configuration.helperExecutableURL, helper)
        XCTAssertEqual(
            WhisperRuntimeDiscovery.modelURL(
                model: .baseEnglish,
                homeDirectory: home
            ),
            model
        )
    }

    func testDiscoveryResolvesLargerModelSelection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let model = WhisperRuntimeDiscovery.modelURL(
            model: .largeV3TurboQ5,
            homeDirectory: root
        )
        try FileManager.default.createDirectory(
            at: model.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0]).write(to: model)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = try WhisperRuntimeDiscovery.discover(
            model: .largeV3TurboQ5,
            engine: .whisperCppMetal,
            environment: [:],
            homeDirectory: root
        )
        XCTAssertEqual(configuration.modelURL, model)
    }

    func testDiscoveryUsesVerifiedModelBundledWithApplication() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleRoot = root.appendingPathComponent(
            "ReleaseFixture.bundle",
            isDirectory: true
        )
        let resources = bundleRoot.appendingPathComponent(
            "Contents/Resources",
            isDirectory: true
        )
        let model = resources.appendingPathComponent(
            "Models/ggml-base.en.bin"
        )
        try FileManager.default.createDirectory(
            at: model.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "local.whisperhotkey.test-fixture",
            "CFBundleName": "ReleaseFixture",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1",
        ]
        try (info as NSDictionary).write(
            to: bundleRoot.appendingPathComponent("Contents/Info.plist")
        )
        try Data([0]).write(to: model)
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = try XCTUnwrap(Bundle(url: bundleRoot))
        let configuration = try WhisperRuntimeDiscovery.discover(
            model: .baseEnglish,
            engine: .whisperCppMetal,
            environment: [:],
            bundle: bundle,
            homeDirectory: root.appendingPathComponent("empty-home")
        )

        XCTAssertEqual(configuration.modelURL, model.standardizedFileURL)
        XCTAssertEqual(
            WhisperRuntimeDiscovery.bundledModelURL(
                model: .baseEnglish,
                bundle: bundle
            ),
            model.standardizedFileURL
        )
    }

    /// The Core ML encoder and WhisperKit engines were retired in 3.5.7; what
    /// survives is Metal's requirement that the model path be a real file.
    /// A directory there used to satisfy the existence check.
    func testDiscoveryRejectsADirectoryWhereTheModelFileBelongs() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let modelURL = WhisperHotkeyPaths.modelURL(
            for: .baseEnglish,
            homeDirectory: home
        )
        try FileManager.default.createDirectory(
            at: modelURL,
            withIntermediateDirectories: true
        )
        XCTAssertThrowsError(
            try WhisperRuntimeDiscovery.discover(
                model: .baseEnglish,
                engine: .whisperCppMetal,
                environment: [:],
                homeDirectory: home
            )
        )
    }

    func testThreadBudgetUsesHalfTheMachineUpToEight() {
        XCTAssertEqual(
            WhisperRuntimeDiscovery.recommendedThreadCount(
                activeProcessorCount: 16
            ),
            8
        )
        XCTAssertEqual(
            WhisperRuntimeDiscovery.recommendedThreadCount(
                activeProcessorCount: 10
            ),
            5
        )
        XCTAssertEqual(
            WhisperRuntimeDiscovery.recommendedThreadCount(
                activeProcessorCount: 8
            ),
            4
        )
        XCTAssertEqual(
            WhisperRuntimeDiscovery.recommendedThreadCount(
                activeProcessorCount: 2
            ),
            2
        )
    }

    func testDiscoveryReportsExactMissingModelPath() {
        let home = URL(fileURLWithPath: "/private/missing-home")
        XCTAssertThrowsError(
            try WhisperRuntimeDiscovery.discover(
                model: .baseEnglish,
                engine: .whisperCppMetal,
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

    func testKnownSilenceSkipsHelperAndCommandLineInference() async throws {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            printf A >> "${0}.attempts"
            printf '%s\\n' '{"event":"ready"}'
            while IFS= read -r command; do
                printf '%s\\n' '{"event":"result","text":"hallucination"}'
            done
            """,
            commandLineScript: """
            #!/bin/sh
            printf A >> "${0}.attempts"
            printf '%s\\n' 'hallucination'
            """
        )
        defer { fixture.delete() }
        let audio = try fixture.makeAudio(speechPresence: .absent)
        let audioDirectory = audio.url.deletingLastPathComponent()
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration,
            options: WhisperRecognitionOptions()
        )

        do {
            _ = try await recognizer.transcribe(audio)
            XCTFail("Known silence should not be decoded")
        } catch let error as WhisperASRError {
            XCTAssertEqual(error, .noSpeech)
        }

        XCTAssertEqual(try fixture.helperAttemptCount(), 0)
        XCTAssertEqual(try fixture.commandLineAttemptCount(), 0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: audioDirectory.path)
        )
        let readiness = await recognizer.readiness
        XCTAssertEqual(readiness, .idle)
    }

    func testContinuousSessionReusesOneHelperForOrderedChunks() async throws {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            printf A >> "${0}.attempts"
            printf '%s\\n' '{"event":"ready"}'
            count=0
            while IFS= read -r command; do
                printf '%s\\n' "$command" >> "${0}.commands"
                count=$((count + 1))
                printf '{"event":"result","text":"chunk %s"}\\n' "$count"
            done
            """
        )
        defer { fixture.delete() }
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration
        )

        let first = try await recognizer.transcribeChunk(
            fixture.makeAudio()
        )
        let second = try await recognizer.transcribeChunk(
            fixture.makeAudio(),
            prompt: "The first phrase continues,"
        )
        await recognizer.finishContinuousSession()

        XCTAssertEqual(first, "chunk 1")
        XCTAssertEqual(second, "chunk 2")
        XCTAssertEqual(try fixture.helperAttemptCount(), 1)
        XCTAssertTrue(
            try fixture.helperCommands().contains(
                #""prompt":"The first phrase continues,""#
            )
        )
        let readiness = await recognizer.readiness
        XCTAssertEqual(readiness, .idle)
    }

    func testOrdinaryDictationSendsVocabularyPromptOverHelperStdin()
        async throws
    {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            printf '%s\\n' '{"event":"ready"}'
            IFS= read -r command
            printf '%s\\n' "$command" >> "${0}.commands"
            printf '%s\\n' '{"event":"result","text":"Codex"}'
            """
        )
        defer { fixture.delete() }
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration
        )

        let transcript = try await recognizer.transcribe(
            fixture.makeAudio(),
            prompt: "Codex, Claude Code"
        )

        XCTAssertEqual(transcript, "Codex")
        XCTAssertTrue(
            try fixture.helperCommands().contains(
                #""prompt":"Codex, Claude Code""#
            )
        )
    }

    func testKeepModelReadyReusesHelperAcrossOrdinaryDictations()
        async throws
    {
        let fixture = try RecognitionFixture(
            helperScript: """
            #!/bin/sh
            printf A >> "${0}.attempts"
            printf '%s\\n' '{"event":"ready"}'
            count=0
            while IFS= read -r command; do
                count=$((count + 1))
                printf '{"event":"result","text":"warm %s"}\\n' "$count"
            done
            """
        )
        defer { fixture.delete() }
        let recognizer = WhisperRecognizer(
            configuration: fixture.configuration
        )

        try await recognizer.setKeepsModelReady(true)
        let first = try await recognizer.transcribe(fixture.makeAudio())
        let second = try await recognizer.transcribe(fixture.makeAudio())

        XCTAssertEqual(first, "warm 1")
        XCTAssertEqual(second, "warm 2")
        XCTAssertEqual(try fixture.helperAttemptCount(), 1)
        let warmReadiness = await recognizer.readiness
        XCTAssertEqual(warmReadiness, .ready)

        try await recognizer.setKeepsModelReady(false)
        let coldReadiness = await recognizer.readiness
        XCTAssertEqual(coldReadiness, .idle)
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

    func makeAudio(
        speechPresence: WhisperSpeechPresence = .unknown
    ) throws -> WhisperAudioFile {
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
        return WhisperAudioFile(
            url: url,
            directoryURL: directory,
            speechPresence: speechPresence
        )
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

    func helperCommands() throws -> String {
        guard let helperURL = configuration.helperExecutableURL else {
            return ""
        }
        let commands = URL(fileURLWithPath: helperURL.path + ".commands")
        guard FileManager.default.fileExists(atPath: commands.path) else {
            return ""
        }
        return try String(contentsOf: commands, encoding: .utf8)
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
