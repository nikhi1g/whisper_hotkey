import Foundation
@preconcurrency import WhisperKit
import WhisperHotkeyCore

public enum WhisperReadiness: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed
}

public struct WhisperRuntimeConfiguration: Equatable, Sendable {
    public let helperExecutableURL: URL?
    public let commandLineExecutableURL: URL?
    public let modelURL: URL
    public let engine: RecognitionEngine

    public init(
        helperExecutableURL: URL?,
        commandLineExecutableURL: URL?,
        modelURL: URL,
        engine: RecognitionEngine = .whisperCppMetal
    ) {
        self.helperExecutableURL = helperExecutableURL
        self.commandLineExecutableURL = commandLineExecutableURL
        self.modelURL = modelURL
        self.engine = engine
    }
}

public enum WhisperRuntimeDiscovery {
    public static let helperEnvironmentKey = "WHISPER_HOTKEY_HELPER"

    public static func recommendedThreadCount(
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Int {
        let available = max(1, activeProcessorCount)
        let half = max(1, available / 2)
        return min(available, min(8, max(4, half)))
    }

    public static func helperCandidates(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> [URL] {
        var candidates: [URL] = []
        if let override = environment[helperEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let auxiliary = bundle.url(
            forAuxiliaryExecutable: "WhisperModelHelper"
        ) {
            candidates.append(auxiliary)
        }
        if let executable = bundle.executableURL {
            candidates.append(
                executable.deletingLastPathComponent()
                    .appendingPathComponent("WhisperModelHelper")
            )
        }
        return orderedUnique(candidates)
    }

    public static func modelURL(
        model: DictationModel = DictationModel.selected(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        WhisperHotkeyPaths.modelURL(
            for: model,
            homeDirectory: homeDirectory
        )
    }

    public static func discover(
        model: DictationModel = DictationModel.selected(),
        engine: RecognitionEngine = RecognitionEngine.selected(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> WhisperRuntimeConfiguration {
        let modelURL: URL
        switch engine {
        case .whisperCppMetal:
            modelURL = Self.modelURL(
                model: model,
                homeDirectory: homeDirectory
            )
        case .whisperCppCoreML:
            guard environment["WHISPER_HOTKEY_COREML"] == "1"
                || bundle.url(
                    forResource: "CoreMLEnabled",
                    withExtension: nil
                ) != nil
            else {
                throw WhisperASRError.helperUnavailable
            }
            modelURL = WhisperHotkeyPaths.coreMLModelURL(
                for: model,
                homeDirectory: homeDirectory
            )
        case .whisperKitCoreML:
            modelURL = WhisperHotkeyPaths.whisperKitModelURL(
                for: model,
                homeDirectory: homeDirectory
            )
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: modelURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue == (engine == .whisperKitCoreML) else {
            throw WhisperASRError.modelMissing(modelURL.path)
        }
        if engine == .whisperCppCoreML {
            let encoderURL = WhisperHotkeyPaths.coreMLEncoderURL(
                for: model,
                homeDirectory: homeDirectory
            )
            guard fileManager.fileExists(
                atPath: encoderURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw WhisperASRError.modelMissing(encoderURL.path)
            }
        }
        if engine == .whisperKitCoreML {
            let requiredNames = [
                "AudioEncoder.mlmodelc",
                "MelSpectrogram.mlmodelc",
                "TextDecoder.mlmodelc",
                "tokenizer.json",
                "tokenizer_config.json",
            ]
            guard requiredNames.allSatisfy({
                fileManager.fileExists(
                    atPath: modelURL.appendingPathComponent($0).path
                )
            }) else {
                throw WhisperASRError.modelMissing(modelURL.path)
            }
        }

        let helper = helperCandidates(
            environment: environment,
            bundle: bundle
        ).first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
        let commandLine = URL(
            fileURLWithPath: WhisperHotkeyPaths.whisperCLIPath
        ).standardizedFileURL
        return WhisperRuntimeConfiguration(
            helperExecutableURL: helper,
            commandLineExecutableURL: fileManager.isExecutableFile(
                atPath: commandLine.path
            ) ? commandLine : nil,
            modelURL: modelURL,
            engine: engine
        )
    }

    private static func orderedUnique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap {
            let standardized = $0.standardizedFileURL
            return seen.insert(standardized.path).inserted
                ? standardized
                : nil
        }
    }
}

enum WhisperDecodingStrategy: String, Equatable, Sendable {
    case beam
    case greedy
}

struct WhisperRecognitionOptions: Equatable, Sendable {
    var strategy: WhisperDecodingStrategy = .beam
    var beamSize = 5
    var threadCount = WhisperRuntimeDiscovery.recommendedThreadCount()
    var preloadTimeout: TimeInterval = 30
    var transcriptionTimeout: TimeInterval = 120

}

enum WhisperHelperInvocation {
    static func arguments(
        modelURL: URL,
        options: WhisperRecognitionOptions,
        requireCoreML: Bool = false
    ) -> [String] {
        var arguments = [
            "--model", modelURL.path,
            "--threads", String(options.threadCount),
            "--strategy", options.strategy.rawValue,
            "--beam-size", String(options.beamSize),
        ]
        if requireCoreML {
            arguments.append("--require-coreml")
        }
        return arguments
    }
}

enum WhisperCommandLineInvocation {
    static func arguments(
        modelURL: URL,
        audioURL: URL,
        options: WhisperRecognitionOptions,
        disableGPU: Bool = false
    ) -> [String] {
        var arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-t", String(options.threadCount),
            "-bs", options.strategy == .beam
                ? String(options.beamSize)
                : "1",
            "-nt",
            "-np",
            "-sns",
            "-fa",
            "-l", "en",
        ]
        if disableGPU {
            arguments.append("-ng")
        }
        return arguments
    }
}

enum WhisperHelperEvent: Equatable, Sendable {
    case ready
    case result(String)
    case error(code: String, message: String)
}

enum WhisperHelperProtocol {
    private struct EventEnvelope: Decodable {
        let event: String
        let text: String?
        let code: String?
        let message: String?
    }

    private struct CommandEnvelope: Encodable {
        let command = "transcribe"
        let audioPath: String
        let prompt: String?
    }

    static func parse(_ line: String) throws -> WhisperHelperEvent {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(
                  EventEnvelope.self,
                  from: data
              ) else {
            throw WhisperASRError.helperProtocolFailure
        }
        switch envelope.event {
        case "ready":
            return .ready
        case "result":
            guard let text = envelope.text else {
                throw WhisperASRError.helperProtocolFailure
            }
            return .result(text)
        case "error":
            guard let code = envelope.code else {
                throw WhisperASRError.helperProtocolFailure
            }
            return .error(
                code: code,
                message: envelope.message ?? "unknown error"
            )
        default:
            throw WhisperASRError.helperProtocolFailure
        }
    }

    static func transcribeCommand(
        audioURL: URL,
        prompt: String? = nil
    ) throws -> Data {
        var data = try JSONEncoder().encode(
            CommandEnvelope(audioPath: audioURL.path, prompt: prompt)
        )
        data.append(0x0A)
        return data
    }
}

public actor WhisperRecognizer {
    public private(set) var readiness: WhisperReadiness = .idle

    private let suppliedConfiguration: WhisperRuntimeConfiguration?
    private let options: WhisperRecognitionOptions
    private let processController = OwnedProcessController()
    private var activeLease: OwnedProcessController.Lease?
    private var activeConfiguration: WhisperRuntimeConfiguration?
    private var preloadTask: Task<WhisperHelperSession, Error>?
    private var helperSession: WhisperHelperSession?
    private var whisperKitRuntime: WhisperKit?
    private var cachedHelperFailure: CachedHelperFailure?
    private var generation = UUID()
    private var keepsModelReady = false
    private var isShutDown = false

    public init(configuration: WhisperRuntimeConfiguration? = nil) {
        suppliedConfiguration = configuration
        options = WhisperRecognitionOptions()
    }

    init(
        configuration: WhisperRuntimeConfiguration?,
        options: WhisperRecognitionOptions
    ) {
        suppliedConfiguration = configuration
        self.options = options
    }

    deinit {
        if let activeLease {
            processController.finish(activeLease, wait: true)
        }
    }

    public func preload() async throws {
        let configuration = try resolvedConfiguration()
        if configuration.engine == .whisperKitCoreML {
            _ = try await preparedWhisperKit(configuration: configuration)
        } else {
            _ = try ensureLease()
            _ = try await preparedHelper()
        }
    }

    /// Enables or disables an idle resident helper. Enabling immediately
    /// preloads the selected model. Disabling waits for the owned helper and
    /// every descendant to exit before returning.
    public func setKeepsModelReady(_ enabled: Bool) async throws {
        guard !isShutDown else {
            throw CancellationError()
        }
        keepsModelReady = enabled
        if enabled {
            do {
                try await preload()
            } catch {
                await resetRuntime()
                throw error
            }
        } else {
            await resetRuntime()
        }
    }

    /// Drops the current configuration after a model preference change and
    /// preloads the replacement only when warm readiness remains enabled.
    public func reloadSelectedModel() async throws {
        guard !isShutDown else {
            throw CancellationError()
        }
        await resetRuntime()
        if keepsModelReady {
            do {
                try await preload()
            } catch {
                await resetRuntime()
                throw error
            }
        }
    }

    public func transcribe(_ audio: WhisperAudioFile) async throws -> String {
        try await transcribe(audio, keepHelperLoaded: false)
    }

    /// Transcribes one ordered chunk while retaining the model process for the
    /// next chunk in the same active pause-mode session.
    public func transcribeChunk(
        _ audio: WhisperAudioFile,
        prompt: String? = nil
    ) async throws -> String {
        try await transcribe(
            audio,
            keepHelperLoaded: true,
            prompt: prompt
        )
    }

    public func finishContinuousSession() async {
        if let whisperKitRuntime {
            if !keepsModelReady {
                await whisperKitRuntime.unloadModels()
                self.whisperKitRuntime = nil
                activeConfiguration = nil
                readiness = .idle
            }
            return
        }
        guard let activeLease else {
            return
        }
        if !keepsModelReady {
            finishDictation(activeLease)
        }
    }

    private func transcribe(
        _ audio: WhisperAudioFile,
        keepHelperLoaded: Bool,
        prompt: String? = nil
    ) async throws -> String {
        defer { audio.delete() }
        let configuration = try resolvedConfiguration()
        if configuration.engine == .whisperKitCoreML {
            return try await transcribeWithWhisperKit(
                audio,
                configuration: configuration,
                keepLoaded: keepHelperLoaded || keepsModelReady,
                prompt: prompt
            )
        }
        let lease = try ensureLease()
        defer {
            if !keepHelperLoaded && !keepsModelReady {
                finishDictation(lease)
            }
        }
        guard audio.speechPresence != .absent else {
            throw WhisperASRError.noSpeech
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            do {
                let helper = try await preparedHelper()
                let transcript = try await helper.transcribe(
                    audioURL: audio.url,
                    prompt: prompt,
                    timeout: options.transcriptionTimeout
                )
                return try cleanedTranscript(transcript)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as WhisperASRError where error == .noSpeech {
                throw error
            } catch {
                guard !processController.isCancelled(lease),
                      !Task.isCancelled else {
                    throw CancellationError()
                }
                helperSession?.terminate(wait: true)
                helperSession = nil
                preloadTask = nil
                readiness = .failed
                cachedHelperFailure = nil
                let configuration = try resolvedConfiguration()
                if configuration.engine == .whisperCppCoreML {
                    throw WhisperASRError.helperFailed(
                        "Core ML helper failed"
                    )
                }
                let transcript = try await Self.runCommandLineFallback(
                    configuration: configuration,
                    audioURL: audio.url,
                    options: options,
                    processController: processController,
                    lease: lease
                )
                if keepHelperLoaded {
                    readiness = .idle
                }
                if keepsModelReady {
                    cachedHelperFailure = nil
                    readiness = .idle
                }
                return try cleanedTranscript(transcript)
            }
        } onCancel: {
            self.processController.cancel(lease, wait: false)
        }
    }

    public func cancel() async {
        let shouldRestoreReadiness = keepsModelReady && !isShutDown
        await resetRuntime()
        if shouldRestoreReadiness {
            try? await preload()
        }
    }

    public func shutdown() async {
        isShutDown = true
        keepsModelReady = false
        await resetRuntime()
    }

    private func preparedHelper() async throws -> WhisperHelperSession {
        let lease = try ensureLease()
        if let cachedHelperFailure,
           cachedHelperFailure.lease == lease {
            throw cachedHelperFailure.error
        }
        if let helperSession, readiness == .ready {
            return helperSession
        }

        let task: Task<WhisperHelperSession, Error>
        let taskGeneration: UUID
        if let preloadTask {
            task = preloadTask
            taskGeneration = generation
        } else {
            let configuration: WhisperRuntimeConfiguration
            do {
                configuration = try resolvedConfiguration()
            } catch let error as WhisperASRError {
                cacheHelperFailure(error, lease: lease)
                throw error
            }
            guard let helperURL = configuration.helperExecutableURL else {
                let error = WhisperASRError.helperUnavailable
                cacheHelperFailure(error, lease: lease)
                readiness = .failed
                throw error
            }
            readiness = .loading
            let newGeneration = UUID()
            generation = newGeneration
            taskGeneration = newGeneration
            let options = options
            let processController = processController
            task = Task.detached(priority: .userInitiated) {
                try await WhisperHelperSession.start(
                    executableURL: helperURL,
                    modelURL: configuration.modelURL,
                    options: options,
                    requireCoreML:
                        configuration.engine == .whisperCppCoreML,
                    processController: processController,
                    lease: lease
                )
            }
            preloadTask = task
        }

        do {
            let session = try await task.value
            guard generation == taskGeneration,
                  let lease = activeLease,
                  !processController.isCancelled(lease) else {
                session.terminate(wait: false)
                throw CancellationError()
            }
            helperSession = session
            cachedHelperFailure = nil
            readiness = .ready
            return session
        } catch {
            if generation == taskGeneration {
                preloadTask = nil
                helperSession = nil
                if let error = error as? WhisperASRError {
                    cacheHelperFailure(error, lease: lease)
                }
                readiness = .failed
            }
            throw error
        }
    }

    private func preparedWhisperKit(
        configuration: WhisperRuntimeConfiguration
    ) async throws -> WhisperKit {
        if let whisperKitRuntime, readiness == .ready {
            return whisperKitRuntime
        }
        readiness = .loading
        do {
            let config = WhisperKitConfig(
                modelFolder: configuration.modelURL.path,
                tokenizerFolder: configuration.modelURL,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            let runtime = try await WhisperKit(config)
            try Task.checkCancellation()
            whisperKitRuntime = runtime
            readiness = .ready
            return runtime
        } catch is CancellationError {
            readiness = .idle
            throw CancellationError()
        } catch {
            readiness = .failed
            throw WhisperASRError.helperFailed("WhisperKit model load failed")
        }
    }

    private func transcribeWithWhisperKit(
        _ audio: WhisperAudioFile,
        configuration: WhisperRuntimeConfiguration,
        keepLoaded: Bool,
        prompt: String?
    ) async throws -> String {
        guard audio.speechPresence != .absent else {
            throw WhisperASRError.noSpeech
        }
        let runtime = try await preparedWhisperKit(
            configuration: configuration
        )
        var promptTokens: [Int]?
        if let prompt, !prompt.isEmpty {
            promptTokens = runtime.tokenizer?.encode(text: prompt)
        }
        let options = DecodingOptions(
            language: "en",
            temperature: 0,
            temperatureFallbackCount: 2,
            topK: 5,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            promptTokens: promptTokens,
            concurrentWorkerCount: 4,
            chunkingStrategy: .vad
        )
        do {
            let results = try await runtime.transcribe(
                audioPath: audio.url.path,
                decodeOptions: options
            )
            try Task.checkCancellation()
            let transcript = results.map(\.text).joined(separator: " ")
            let cleaned = try cleanedTranscript(transcript)
            if !keepLoaded {
                await runtime.unloadModels()
                whisperKitRuntime = nil
                activeConfiguration = nil
                readiness = .idle
            }
            return cleaned
        } catch is CancellationError {
            if !keepLoaded {
                await releaseWhisperKit(runtime)
            }
            throw CancellationError()
        } catch let error as WhisperASRError {
            if !keepLoaded {
                await releaseWhisperKit(runtime)
            }
            throw error
        } catch {
            if !keepLoaded {
                await releaseWhisperKit(runtime)
            }
            readiness = .failed
            throw WhisperASRError.helperFailed("WhisperKit transcription failed")
        }
    }

    private func releaseWhisperKit(_ runtime: WhisperKit) async {
        await runtime.unloadModels()
        if whisperKitRuntime === runtime {
            whisperKitRuntime = nil
            activeConfiguration = nil
            readiness = .idle
        }
    }

    private func resolvedConfiguration() throws -> WhisperRuntimeConfiguration {
        if let activeConfiguration {
            return activeConfiguration
        }
        let configuration = try suppliedConfiguration
            ?? WhisperRuntimeDiscovery.discover()
        activeConfiguration = configuration
        return configuration
    }

    private func ensureLease() throws -> OwnedProcessController.Lease {
        guard !isShutDown else {
            throw CancellationError()
        }
        if let activeLease {
            return activeLease
        }
        let lease = processController.beginDictation()
        activeLease = lease
        cachedHelperFailure = nil
        return lease
    }

    private func cacheHelperFailure(
        _ error: WhisperASRError,
        lease: OwnedProcessController.Lease
    ) {
        guard activeLease == lease, !isShutDown else { return }
        cachedHelperFailure = CachedHelperFailure(
            lease: lease,
            error: error
        )
    }

    private func finishDictation(_ lease: OwnedProcessController.Lease) {
        guard activeLease == lease else { return }
        generation = UUID()
        helperSession?.terminate(wait: false)
        processController.finish(lease, wait: false)
        activeLease = nil
        helperSession = nil
        preloadTask = nil
        cachedHelperFailure = nil
        activeConfiguration = nil
        readiness = .idle
    }

    private func resetRuntime() async {
        generation = UUID()
        let pendingPreload = preloadTask
        let activeSession = helperSession
        let lease = activeLease
        pendingPreload?.cancel()
        if let lease {
            processController.finish(lease, wait: true)
        }
        activeSession?.terminate(wait: true)
        if let whisperKitRuntime {
            await whisperKitRuntime.unloadModels()
        }
        if let pendingPreload,
           let lateSession = try? await pendingPreload.value {
            lateSession.terminate(wait: true)
        }
        activeLease = nil
        preloadTask = nil
        helperSession = nil
        whisperKitRuntime = nil
        cachedHelperFailure = nil
        activeConfiguration = nil
        readiness = .idle
    }

    private func cleanedTranscript(_ raw: String) throws -> String {
        let transcript = WhisperTranscriptSanitizer.clean(raw)
        guard !transcript.isEmpty else {
            throw WhisperASRError.noSpeech
        }
        return transcript
    }

    private static func runCommandLineFallback(
        configuration: WhisperRuntimeConfiguration,
        audioURL: URL,
        options: WhisperRecognitionOptions,
        processController: OwnedProcessController,
        lease: OwnedProcessController.Lease
    ) async throws -> String {
        guard let executableURL = configuration.commandLineExecutableURL else {
            throw WhisperASRError.commandLineUnavailable
        }
        do {
            return try await WhisperCommandLineProcess.run(
                executableURL: executableURL,
                arguments: WhisperCommandLineInvocation.arguments(
                    modelURL: configuration.modelURL,
                    audioURL: audioURL,
                    options: options
                ),
                timeout: options.transcriptionTimeout,
                processController: processController,
                lease: lease
            )
        } catch let error as WhisperCommandLineProcess.Failure
            where error.shouldRetryWithoutGPU {
            do {
                return try await WhisperCommandLineProcess.run(
                    executableURL: executableURL,
                    arguments: WhisperCommandLineInvocation.arguments(
                        modelURL: configuration.modelURL,
                        audioURL: audioURL,
                        options: options,
                        disableGPU: true
                    ),
                    timeout: options.transcriptionTimeout,
                    processController: processController,
                    lease: lease
                )
            } catch let cpuError as WhisperCommandLineProcess.Failure {
                throw WhisperASRError.commandLineFailed(cpuError.status)
            }
        } catch let error as WhisperCommandLineProcess.Failure {
            throw WhisperASRError.commandLineFailed(error.status)
        }
    }
}

private struct CachedHelperFailure: Sendable {
    let lease: OwnedProcessController.Lease
    let error: WhisperASRError
}

private final class WhisperHelperSession: @unchecked Sendable {
    private let process: Process
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let lines: JSONLineBuffer
    private let processController: OwnedProcessController
    private let lease: OwnedProcessController.Lease
    private let closeLock = NSLock()
    private var closed = false

    private init(
        process: Process,
        inputHandle: FileHandle,
        outputHandle: FileHandle,
        lines: JSONLineBuffer,
        processController: OwnedProcessController,
        lease: OwnedProcessController.Lease
    ) {
        self.process = process
        self.inputHandle = inputHandle
        self.outputHandle = outputHandle
        self.lines = lines
        self.processController = processController
        self.lease = lease
    }

    deinit {
        terminate(wait: false)
    }

    static func start(
        executableURL: URL,
        modelURL: URL,
        options: WhisperRecognitionOptions,
        requireCoreML: Bool,
        processController: OwnedProcessController,
        lease: OwnedProcessController.Lease
    ) async throws -> WhisperHelperSession {
        try Task.checkCancellation()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let lines = JSONLineBuffer()
        let outputHandle = outputPipe.fileHandleForReading

        process.executableURL = executableURL
        process.arguments = WhisperHelperInvocation.arguments(
            modelURL: modelURL,
            options: options,
            requireCoreML: requireCoreML
        )
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment
        outputHandle.readabilityHandler = { handle in
            lines.consume(handle.availableData)
        }
        guard processController.install(process, lease: lease) else {
            outputHandle.readabilityHandler = nil
            throw CancellationError()
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            processController.clear(process, lease: lease)
            throw WhisperASRError.helperFailed("could not start")
        }
        if processController.isCancelled(lease) || Task.isCancelled {
            OwnedProcessTermination.terminate(process, wait: false)
            throw CancellationError()
        }

        let session = WhisperHelperSession(
            process: process,
            inputHandle: inputPipe.fileHandleForWriting,
            outputHandle: outputHandle,
            lines: lines,
            processController: processController,
            lease: lease
        )
        do {
            let event = try await session.nextEvent(
                timeout: options.preloadTimeout
            )
            guard event == .ready else {
                throw session.error(for: event)
            }
            return session
        } catch {
            session.terminate(wait: true)
            throw error
        }
    }

    func transcribe(
        audioURL: URL,
        prompt: String?,
        timeout: TimeInterval
    ) async throws -> String {
        do {
            try inputHandle.write(
                contentsOf: WhisperHelperProtocol.transcribeCommand(
                    audioURL: audioURL,
                    prompt: prompt
                )
            )
        } catch {
            terminate(wait: false)
            throw WhisperASRError.helperFailed("command channel closed")
        }

        let event = try await nextEvent(timeout: timeout)
        switch event {
        case .result(let text):
            return text
        case .error:
            throw error(for: event)
        case .ready:
            throw WhisperASRError.helperProtocolFailure
        }
    }

    func terminate(wait: Bool) {
        let shouldClose = closeLock.withLock {
            guard !closed else { return false }
            closed = true
            return true
        }
        guard shouldClose else { return }
        outputHandle.readabilityHandler = nil
        try? inputHandle.close()
        if process.isRunning {
            OwnedProcessTermination.terminate(process, wait: wait)
        }
        processController.clear(process, lease: lease)
    }

    private func nextEvent(timeout: TimeInterval) async throws
        -> WhisperHelperEvent {
        let deadline = Date().addingTimeInterval(timeout)
        var processExitObserved: Date?
        while Date() < deadline {
            if processController.isCancelled(lease) || Task.isCancelled {
                processController.cancel(lease, wait: false)
                throw CancellationError()
            }
            if let line = lines.pop() {
                return try WhisperHelperProtocol.parse(line)
            }
            if !process.isRunning {
                let observed = processExitObserved ?? Date()
                processExitObserved = observed
                if lines.isFinished
                    || Date().timeIntervalSince(observed) >= 0.1 {
                    throw WhisperASRError.helperFailed("process exited")
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        if process.isRunning {
            OwnedProcessTermination.terminate(process, wait: false)
        }
        throw WhisperASRError.recognitionTimedOut
    }

    private func error(for event: WhisperHelperEvent) -> WhisperASRError {
        guard case .error(let code, _) = event else {
            return .helperProtocolFailure
        }
        if code == "no_speech" {
            return .noSpeech
        }
        switch code {
        case "model_load_failed":
            return .helperFailed("model preload failed")
        case "audio_unavailable", "audio_read_failed":
            return .helperFailed("recorded audio was unavailable")
        case "insecure_audio":
            return .helperFailed("recorded audio failed privacy validation")
        case "invalid_audio", "unsupported_audio":
            return .helperFailed("recorded audio format was invalid")
        default:
            return .helperFailed("local inference failed")
        }
    }
}

enum WhisperCommandLineProcess {
    struct Failure: Error, Equatable, Sendable {
        let status: Int32
        let diagnostic: String
        let terminationReason: Process.TerminationReason

        init(
            status: Int32,
            diagnostic: String,
            terminationReason: Process.TerminationReason = .exit
        ) {
            self.status = status
            self.diagnostic = diagnostic
            self.terminationReason = terminationReason
        }

        var shouldRetryWithoutGPU: Bool {
            terminationReason == .uncaughtSignal || isMetalSpecific
        }

        var isMetalSpecific: Bool {
            diagnostic.components(separatedBy: .newlines).contains { line in
                let lowercased = line.lowercased()
                guard !lowercased.contains("load_backend: loaded") else {
                    return false
                }
                let identifiesGPU = lowercased.contains("metal")
                    || lowercased.contains("ggml-metal")
                    || lowercased.contains("gpu")
                    || lowercased.contains("mtlcommand")
                let identifiesFailure = lowercased.contains("fail")
                    || lowercased.contains("error")
                    || lowercased.contains("unavailable")
                    || lowercased.contains("unsupported")
                return identifiesGPU && identifiesFailure
            }
        }
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        processController: OwnedProcessController,
        lease: OwnedProcessController.Lease
    ) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputBuffer = LockedDataBuffer()
        let errorBuffer = LockedDataBuffer()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }
        guard processController.install(process, lease: lease) else {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw CancellationError()
        }
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            processController.clear(process, lease: lease)
        }

        do {
            try process.run()
        } catch {
            throw WhisperASRError.commandLineFailed(-1)
        }
        if processController.isCancelled(lease) || Task.isCancelled {
            OwnedProcessTermination.terminate(process, wait: false)
            throw CancellationError()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if processController.isCancelled(lease) || Task.isCancelled {
                processController.cancel(lease, wait: true)
                throw CancellationError()
            }
            guard Date() < deadline else {
                OwnedProcessTermination.terminate(process, wait: true)
                throw WhisperASRError.recognitionTimedOut
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        if let tail = try? outputPipe.fileHandleForReading.readToEnd(),
           !tail.isEmpty {
            outputBuffer.append(tail)
        }
        if let tail = try? errorPipe.fileHandleForReading.readToEnd(),
           !tail.isEmpty {
            errorBuffer.append(tail)
        }

        let output = String(
            decoding: outputBuffer.snapshot(),
            as: UTF8.self
        )
        guard process.terminationReason == .exit,
              process.terminationStatus == 0 else {
            throw Failure(
                status: process.terminationStatus,
                diagnostic: String(
                    decoding: errorBuffer.snapshot(),
                    as: UTF8.self
                ),
                terminationReason: process.terminationReason
            )
        }
        return output
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
