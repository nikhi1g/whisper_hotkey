@preconcurrency import AVFoundation
import Foundation

public enum WhisperSpeechPresence: Equatable, Sendable {
    case unknown
    case absent
    case present
}

public enum CompletionCaptureGracePolicy {
    public static let recentSpeechWindow: TimeInterval = 0.18
    public static let graceDuration: TimeInterval = 0.24

    public static func delay(
        speechPresence: WhisperSpeechPresence,
        trailingSilence: TimeInterval
    ) -> TimeInterval? {
        guard speechPresence == .present,
              trailingSilence >= 0,
              trailingSilence < recentSpeechWindow
        else {
            return nil
        }
        return graceDuration
    }
}

public final class WhisperAudioFile: @unchecked Sendable {
    public let url: URL

    private let directoryURL: URL
    private let storage: WhisperAudioLease.Storage
    private let resourceID: WhisperAudioLease.Storage.ResourceID
    private let holder: WhisperAudioLease.Holder
    private let sessionOwned: Bool
    private let sessionOwner: WhisperAudioLease?
    private let maximumSpanDuration: TimeInterval
    private let lock = NSLock()
    private var deleted = false
    private var recordedSpeechPresence: WhisperSpeechPresence

    init(
        url: URL,
        directoryURL: URL,
        fileManager: FileManager = .default,
        speechPresence: WhisperSpeechPresence = .unknown
    ) {
        let storage = WhisperAudioLease.Storage(
            rootURL: directoryURL,
            fileManager: fileManager,
            initiallyFinished: false
        )
        guard let resourceID = storage.register(
            directoryURL: directoryURL,
            canonical: true
        ) else {
            preconditionFailure("A standalone audio file must be borrowable.")
        }
        guard let holder = storage.acquire(resourceID) else {
            preconditionFailure("A standalone audio file must be borrowable.")
        }
        self.url = url
        self.directoryURL = directoryURL
        self.storage = storage
        self.resourceID = resourceID
        self.holder = holder
        sessionOwned = false
        sessionOwner = nil
        maximumSpanDuration = WhisperAudioLease.defaultMaximumSpanDuration
        recordedSpeechPresence = speechPresence
    }

    convenience init(
        url: URL,
        directoryURL: URL,
        storage: WhisperAudioLease.Storage,
        resourceID: WhisperAudioLease.Storage.ResourceID,
        speechPresence: WhisperSpeechPresence,
        maximumSpanDuration: TimeInterval = WhisperAudioLease
            .defaultMaximumSpanDuration,
        sessionOwner: WhisperAudioLease? = nil
    ) {
        guard let holder = storage.acquire(resourceID) else {
            preconditionFailure("A session audio file must be borrowable.")
        }
        self.init(
            url: url,
            directoryURL: directoryURL,
            storage: storage,
            resourceID: resourceID,
            speechPresence: speechPresence,
            maximumSpanDuration: maximumSpanDuration,
            holder: holder,
            sessionOwner: sessionOwner
        )
    }

    init(
        url: URL,
        directoryURL: URL,
        storage: WhisperAudioLease.Storage,
        resourceID: WhisperAudioLease.Storage.ResourceID,
        speechPresence: WhisperSpeechPresence,
        maximumSpanDuration: TimeInterval,
        holder: WhisperAudioLease.Holder,
        sessionOwner: WhisperAudioLease?
    ) {
        self.url = url
        self.directoryURL = directoryURL
        self.storage = storage
        self.resourceID = resourceID
        self.holder = holder
        sessionOwned = true
        self.sessionOwner = sessionOwner
        self.maximumSpanDuration = maximumSpanDuration
        recordedSpeechPresence = speechPresence
    }

    deinit {
        delete()
    }

    public func delete() {
        let shouldFinishSession = lock.withLock {
            guard !deleted else { return false }
            deleted = true
            return !sessionOwned || sessionOwner != nil
        }
        guard shouldFinishSession else {
            holder.release()
            return
        }
        if let sessionOwner {
            sessionOwner.finish()
        } else {
            storage.finish()
        }
        holder.release()
    }


    /// Borrows this file for one asynchronous child task. The recognizer
    /// releases this holder after cancellation, failure, or completion.
    func acquireLeaseHolder() -> WhisperAudioLease.Holder? {
        storage.acquire(resourceID)
    }

    /// Marks an inference segment as no longer writable. Its directory is
    /// removed after the last holder releases, without waiting for the
    /// canonical recording's session to finish.
    func retire() {
        storage.retire(resourceID)
    }

    /// Returns an immutable bounded view without copying or materializing WAV.
    public func makeSpan(
        startSample: Int64,
        endSample: Int64,
        sampleRate: Int
    ) throws -> WhisperAudioSpan {
        guard !storage.isFinished else {
            throw WhisperAudioLeaseError.leaseFinished
        }
        guard sampleRate > 0,
              startSample >= 0,
              endSample > startSample,
              endSample >= 0
        else {
            throw WhisperAudioLeaseError.invalidSpanBounds
        }
        let sampleCount = endSample - startSample
        guard Double(sampleCount)
            <= maximumSpanDuration * Double(sampleRate)
        else {
            throw WhisperAudioLeaseError.spanTooLong
        }
        guard let holder = storage.acquire(resourceID) else {
            throw WhisperAudioLeaseError.leaseFinished
        }
        return WhisperAudioSpan(
            url: url,
            startSample: startSample,
            endSample: endSample,
            sampleRate: sampleRate,
            holder: holder
        )
    }

    public var speechPresence: WhisperSpeechPresence {
        lock.withLock { recordedSpeechPresence }
    }

    func setSpeechPresence(_ presence: WhisperSpeechPresence) {
        lock.withLock {
            recordedSpeechPresence = presence
        }
    }
}

public struct WhisperAudioCaptureToken: Hashable, Sendable {
    fileprivate let rawValue: UInt64
}

public struct WhisperAudioCaptureTiming: Equatable, Sendable {
    public let requestedAtUptimeNanoseconds: UInt64
    public let firstBufferAtUptimeNanoseconds: UInt64?
    public let firstCommittedSampleAtUptimeNanoseconds: UInt64?

    public var requestToFirstBufferNanoseconds: UInt64? {
        guard let firstBufferAtUptimeNanoseconds,
              firstBufferAtUptimeNanoseconds
                >= requestedAtUptimeNanoseconds
        else {
            return nil
        }
        return firstBufferAtUptimeNanoseconds
            - requestedAtUptimeNanoseconds
    }

    public var requestToFirstCommittedSampleNanoseconds: UInt64? {
        guard let firstCommittedSampleAtUptimeNanoseconds,
              firstCommittedSampleAtUptimeNanoseconds
                >= requestedAtUptimeNanoseconds
        else {
            return nil
        }
        return firstCommittedSampleAtUptimeNanoseconds
            - requestedAtUptimeNanoseconds
    }
}

@MainActor
public final class WhisperAudioRecorder {
    private nonisolated let backend: WhisperAudioRecorderBackend

    public init(
        audioEngine: AVAudioEngine = AVAudioEngine(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        backend = WhisperAudioRecorderBackend(
            audioEngine: audioEngine,
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory
        )
    }

    public var isRecording: Bool {
        backend.isRecording
    }

    /// A normalized 0...1 microphone level for lightweight presentation.
    /// Reading this value does not touch AVAudioEngine and is useful only while
    /// recording.
    public var normalizedInputLevel: Float {
        backend.normalizedInputLevel
    }

    /// Silence following confirmed speech in the current recording. This is
    /// updated by the existing audio callback and adds no timer or audio pass.
    public var trailingSilenceDuration: TimeInterval {
        backend.trailingSilenceDuration
    }

    /// Duration and speech state for the current inference segment. Both are
    /// maintained by the existing audio callback and read only while capture
    /// is active.
    public var currentSegmentDuration: TimeInterval {
        backend.currentSegmentDuration
    }

    public var currentSegmentSpeechPresence: WhisperSpeechPresence {
        backend.currentSegmentSpeechPresence
    }

    /// A bounded post-roll used only when confirmed speech reaches the
    /// completion gesture. Silence and already-paused speech stop immediately.
    public var completionCaptureGrace: TimeInterval? {
        CompletionCaptureGracePolicy.delay(
            speechPresence: currentSegmentSpeechPresence,
            trailingSilence: trailingSilenceDuration
        )
    }

    /// The current cadence-aware pause boundary. It is learned only from the
    /// existing audio callback and remains bounded for predictable latency.
    public var pauseBoundarySilence: TimeInterval {
        backend.pauseBoundarySilence
    }

    deinit {
        backend.shutdown()
    }

    /// Enqueues provisional microphone activation and returns immediately.
    /// This method is safe to call from a global event callback: all engine,
    /// storage, and conversion work runs on recorder-owned queues.
    public nonisolated func primeCapture(
        pauseSegmentation: Bool = false,
        requestedAtUptimeNanoseconds: UInt64 = DispatchTime.now()
            .uptimeNanoseconds
    ) -> WhisperAudioCaptureToken {
        backend.prime(
            pauseSegmentation: pauseSegmentation,
            requestedAtUptimeNanoseconds: requestedAtUptimeNanoseconds
        )
    }

    /// Returns content-free monotonic timing for startup diagnostics. Values
    /// remain optional until the corresponding callback/write has occurred.
    public nonisolated func captureTiming(
        for token: WhisperAudioCaptureToken
    ) -> WhisperAudioCaptureTiming? {
        backend.captureTiming(for: token)
    }

    /// Accepts one matching provisional capture without restarting its engine
    /// or losing buffers collected before private WAV preparation completed.
    @discardableResult
    public func adoptPrimedCapture(
        _ token: WhisperAudioCaptureToken
    ) throws -> URL {
        try backend.adopt(token)
    }

    /// Enqueues cancellation for only the matching, still-provisional session.
    /// An already-adopted or newer recording cannot be cancelled by a stale
    /// hotkey rejection.
    public nonisolated func cancelPrimedCapture(
        _ token: WhisperAudioCaptureToken
    ) {
        backend.cancelPrimed(token)
    }

    @discardableResult
    public func start(pauseSegmentation: Bool = false) throws -> URL {
        let token = primeCapture(pauseSegmentation: pauseSegmentation)
        return try adoptPrimedCapture(token)
    }

    public func stop() throws -> WhisperAudioFile {
        try backend.stop()
    }

    /// Rotates only the inference segment while the uninterrupted private
    /// session recording and microphone engine continue running.
    public func rotatePauseSegment() throws -> WhisperAudioFile {
        try backend.rotatePauseSegment()
    }

    /// Stops one continuous Pause Mode recording and returns both the complete
    /// private session audio and its untranscribed final segment.
    public func stopPauseSession() throws -> (
        recording: WhisperAudioFile,
        finalSegment: WhisperAudioFile
    ) {
        try backend.stopPauseSession()
    }

    public func cancel() {
        backend.cancel()
    }
}

private final class WhisperAudioRecorderBackend: @unchecked Sendable {
    private enum Phase {
        case provisional
        case adopted
    }

    private let engineBox: WhisperAudioEngineBox
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let controlQueue = DispatchQueue(
        label: "whisper_hotkey.audio.capture-control",
        qos: .userInteractive
    )
    private let tokenLock = NSLock()
    private let timingLock = NSLock()
    private var nextToken: UInt64 = 0
    private var timingTrackers: [
        WhisperAudioCaptureToken: WhisperAudioCaptureTimingTracker
    ] = [:]
    private var timingTokenOrder: [WhisperAudioCaptureToken] = []
    private var activeToken: WhisperAudioCaptureToken?
    private var phase: Phase?
    private var pauseSegmentation = false
    private var startupError: WhisperASRError?
    private var rejectedTokens: [WhisperAudioCaptureToken: WhisperASRError] = [:]
    private var rejectedTokenOrder: [WhisperAudioCaptureToken] = []
    private var writer: WhisperWAVWriter?
    private var sink: WhisperBufferedAudioSink?
    private var audioFile: WhisperAudioFile?
    private var audioLease: WhisperAudioLease?
    private var inputTapInstalled = false

    init(
        audioEngine: AVAudioEngine,
        fileManager: FileManager,
        temporaryDirectory: URL
    ) {
        engineBox = WhisperAudioEngineBox(audioEngine)
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    var isRecording: Bool {
        controlQueue.sync {
            audioFile != nil && engineBox.engine.isRunning
        }
    }

    var normalizedInputLevel: Float {
        controlQueue.sync { writer?.normalizedInputLevel ?? 0 }
    }

    var trailingSilenceDuration: TimeInterval {
        controlQueue.sync { writer?.trailingSilenceDuration ?? 0 }
    }

    var currentSegmentDuration: TimeInterval {
        controlQueue.sync { writer?.segmentDuration ?? 0 }
    }

    var currentSegmentSpeechPresence: WhisperSpeechPresence {
        controlQueue.sync { writer?.segmentSpeechPresence ?? .unknown }
    }

    var pauseBoundarySilence: TimeInterval {
        controlQueue.sync {
            writer?.pauseBoundarySilence
                ?? WhisperSpeechActivityDetector.defaultPauseBoundary
        }
    }

    func prime(
        pauseSegmentation: Bool,
        requestedAtUptimeNanoseconds: UInt64
    ) -> WhisperAudioCaptureToken {
        let token = tokenLock.withLock {
            nextToken &+= 1
            return WhisperAudioCaptureToken(rawValue: nextToken)
        }
        controlQueue.async { [self] in
            let timing = WhisperAudioCaptureTimingTracker(
                requestedAtUptimeNanoseconds: requestedAtUptimeNanoseconds
            )
            rememberTiming(timing, for: token)
            beginProvisionalCapture(
                token: token,
                pauseSegmentation: pauseSegmentation,
                timing: timing
            )
        }
        return token
    }

    private func rememberTiming(
        _ timing: WhisperAudioCaptureTimingTracker,
        for token: WhisperAudioCaptureToken
    ) {
        timingLock.withLock {
            timingTrackers[token] = timing
            timingTokenOrder.append(token)
            if timingTokenOrder.count > 16 {
                let expired = timingTokenOrder.removeFirst()
                timingTrackers.removeValue(forKey: expired)
            }
        }
    }

    func captureTiming(
        for token: WhisperAudioCaptureToken
    ) -> WhisperAudioCaptureTiming? {
        timingLock.withLock { timingTrackers[token] }?.snapshot
    }

    func adopt(_ token: WhisperAudioCaptureToken) throws -> URL {
        try controlQueue.sync {
            if let error = rejectedTokens.removeValue(forKey: token) {
                throw error
            }
            guard activeToken == token, phase == .provisional else {
                throw WhisperASRError.noActiveRecording
            }
            if let startupError {
                cleanupCapture()
                throw startupError
            }
            guard let audioFile else {
                cleanupCapture()
                throw WhisperASRError.captureFailed(
                    "Audio capture did not finish preparing."
                )
            }
            phase = .adopted
            return audioFile.url
        }
    }

    func cancelPrimed(_ token: WhisperAudioCaptureToken) {
        controlQueue.async { [self] in
            rejectedTokens.removeValue(forKey: token)
            guard activeToken == token, phase == .provisional else {
                return
            }
            cleanupCapture()
        }
    }

    func stop() throws -> WhisperAudioFile {
        try controlQueue.sync {
            guard phase == .adopted, let audioFile, let writer else {
                throw WhisperASRError.noActiveRecording
            }
            let lease = audioLease
            stopEngineAndTap()
            let queueError = sink?.finishAcceptingAndWait()
            let speechPresence = writer.speechPresence
            let writeError = writer.finish()
            sink = nil
            self.writer = nil
            self.audioFile = nil
            activeToken = nil
            phase = nil
            startupError = nil

            if queueError != nil || writeError != nil {
                audioFile.delete()
                lease?.finish()
                audioLease = nil
                throw WhisperASRError.captureFailed(
                    "Writing microphone audio failed."
                )
            }
            audioFile.setSpeechPresence(speechPresence)
            audioLease = nil
            return audioFile
        }
    }

    func rotatePauseSegment() throws -> WhisperAudioFile {
        try controlQueue.sync {
            guard phase == .adopted,
                  pauseSegmentation,
                  let writer,
                  let sink,
                  audioFile != nil,
                  engineBox.engine.isRunning
            else {
                throw WhisperASRError.noActiveRecording
            }
            let nextAudio = try makePrivateAudioFile()
            do {
                let nextFile = try makeOutputFile(
                    for: nextAudio,
                    settings: writer.outputFileSettings
                )
                return try sink.performWriterAction { writer in
                    try writer.rotateSegment(
                        to: nextFile,
                        audioFile: nextAudio
                    )
                }
            } catch {
                nextAudio.delete()
                if let error = error as? WhisperASRError {
                    throw error
                }
                throw WhisperASRError.captureFailed(
                    "Could not rotate the pause transcription segment."
                )
            }
        }
    }

    func stopPauseSession() throws -> (
        recording: WhisperAudioFile,
        finalSegment: WhisperAudioFile
    ) {
        try controlQueue.sync {
            guard phase == .adopted,
                  pauseSegmentation,
                  let audioFile,
                  let writer
            else {
                throw WhisperASRError.noActiveRecording
            }
            let lease = audioLease
            stopEngineAndTap()
            let queueError = sink?.finishAcceptingAndWait()
            let speechPresence = writer.speechPresence
            let result = writer.finishRetainingSegment()
            sink = nil
            self.writer = nil
            self.audioFile = nil
            activeToken = nil
            phase = nil
            startupError = nil

            guard queueError == nil,
                  result.error == nil,
                  let finalSegment = result.segment
            else {
                audioFile.delete()
                result.segment?.delete()
                lease?.finish()
                audioLease = nil
                throw WhisperASRError.captureFailed(
                    "Writing microphone audio failed."
                )
            }
            audioFile.setSpeechPresence(speechPresence)
            audioLease = nil
            return (audioFile, finalSegment)
        }
    }

    func cancel() {
        controlQueue.sync {
            cleanupCapture()
            rejectedTokens.removeAll(keepingCapacity: false)
            rejectedTokenOrder.removeAll(keepingCapacity: false)
        }
    }

    func shutdown() {
        cancel()
    }

    private func beginProvisionalCapture(
        token: WhisperAudioCaptureToken,
        pauseSegmentation: Bool,
        timing: WhisperAudioCaptureTimingTracker
    ) {
        guard activeToken == nil else {
            rememberRejectedToken(
                token,
                error: WhisperASRError.captureFailed(
                    "Another audio capture is already active."
                )
            )
            return
        }
        activeToken = token
        phase = .provisional
        self.pauseSegmentation = pauseSegmentation
        startupError = nil

        do {
            try prepareCapture(
                pauseSegmentation: pauseSegmentation,
                timing: timing
            )
        } catch {
            stopEngineAndTap()
            sink?.cancelAndWait()
            sink = nil
            writer?.finish()
            writer = nil
            audioFile?.delete()
            audioFile = nil
            audioLease?.finish()
            audioLease = nil
            startupError = (error as? WhisperASRError)
                ?? WhisperASRError.captureFailed(
                    "Audio engine setup failed."
                )
        }
    }

    private func prepareCapture(
        pauseSegmentation: Bool,
        timing: WhisperAudioCaptureTimingTracker
    ) throws {
        let inputNode = engineBox.engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw WhisperASRError.microphoneUnavailable
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperASRError.captureFailed(
                "Could not create the 16 kHz mono format."
            )
        }

        let sink = WhisperBufferedAudioSink(
            onFirstBuffer: timing.markFirstBuffer
        )
        self.sink = sink
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: inputFormat,
            block: makeWhisperAudioTapHandler(sink: sink)
        )
        inputTapInstalled = true

        let prepared = try activateWhisperCaptureFastPath(
            activateCapture: {
                engineBox.engine.prepare()
                try engineBox.engine.start()
            },
            prepareWriter: {
                try makePreparedWriter(
                    inputFormat: inputFormat,
                    outputFormat: outputFormat,
                    pauseSegmentation: pauseSegmentation,
                    timing: timing
                )
            },
            adoptWriter: { prepared in
                sink.attach(prepared.writer)
            }
        )
        writer = prepared.writer
        audioFile = prepared.audioFile
    }

    private func makePreparedWriter(
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        pauseSegmentation: Bool,
        timing: WhisperAudioCaptureTimingTracker
    ) throws -> WhisperPreparedAudioWriter {
        let audioFile = try makePrivateAudioFile()
        var segmentAudioFile: WhisperAudioFile?
        do {
            let outputFile = try makeOutputFile(
                for: audioFile,
                settings: outputFormat.settings
            )
            let segmentFile: AVAudioFile?
            if pauseSegmentation {
                let newSegmentAudioFile = try makePrivateAudioFile()
                segmentAudioFile = newSegmentAudioFile
                segmentFile = try makeOutputFile(
                    for: newSegmentAudioFile,
                    settings: outputFile.fileFormat.settings
                )
            } else {
                segmentFile = nil
            }
            guard let converter = AVAudioConverter(
                from: inputFormat,
                to: outputFile.processingFormat
            ) else {
                throw WhisperASRError.captureFailed(
                    "Could not prepare microphone conversion."
                )
            }
            let writer = WhisperWAVWriter(
                file: outputFile,
                segmentFile: segmentFile,
                segmentAudioFile: segmentAudioFile,
                converter: converter,
                outputFormat: outputFile.processingFormat,
                onFirstSamplesCommitted: timing.markFirstCommittedSample
            )
            segmentAudioFile = nil
            return WhisperPreparedAudioWriter(
                writer: writer,
                audioFile: audioFile
            )
        } catch {
            audioFile.delete()
            segmentAudioFile?.delete()
            throw error
        }
    }

    private func makePrivateAudioFile() throws -> WhisperAudioFile {
        if let audioLease {
            do {
                return try audioLease.makeChildFile()
            } catch {
                throw WhisperASRError.captureFailed(
                    "Could not create private temporary storage."
                )
            }
        }

        do {
            let lease = try WhisperAudioLease.create(
                in: temporaryDirectory,
                fileManager: fileManager
            )
            audioLease = lease
            return lease.makeCanonicalFile()
        } catch {
            throw WhisperASRError.captureFailed(
                "Could not create private temporary storage."
            )
        }
    }

    private func makeOutputFile(
        for audioFile: WhisperAudioFile,
        settings: [String: Any]
    ) throws -> AVAudioFile {
        let file = try AVAudioFile(
            forWriting: audioFile.url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: audioFile.url.path
        )
        return file
    }

    private func removeInputTap() {
        guard inputTapInstalled else { return }
        engineBox.engine.inputNode.removeTap(onBus: 0)
        inputTapInstalled = false
    }

    private func stopEngineAndTap() {
        engineBox.engine.stop()
        removeInputTap()
    }

    private func cleanupCapture() {
        let lease = audioLease
        stopEngineAndTap()
        sink?.cancelAndWait()
        sink = nil
        writer?.finish()
        writer = nil
        audioFile?.delete()
        audioFile = nil
        lease?.finish()
        audioLease = nil
        activeToken = nil
        phase = nil
        pauseSegmentation = false
        startupError = nil
    }

    private func rememberRejectedToken(
        _ token: WhisperAudioCaptureToken,
        error: WhisperASRError
    ) {
        rejectedTokens[token] = error
        rejectedTokenOrder.append(token)
        if rejectedTokenOrder.count > 16 {
            let expired = rejectedTokenOrder.removeFirst()
            rejectedTokens.removeValue(forKey: expired)
        }
    }
}

private struct WhisperPreparedAudioWriter {
    let writer: WhisperWAVWriter
    let audioFile: WhisperAudioFile
}

@discardableResult
func activateWhisperCaptureFastPath<Prepared>(
    activateCapture: () throws -> Void,
    prepareWriter: () throws -> Prepared,
    adoptWriter: (Prepared) -> Void
) throws -> Prepared {
    try activateCapture()
    let prepared = try prepareWriter()
    adoptWriter(prepared)
    return prepared
}

private final class WhisperAudioCaptureTimingTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let requestedAtUptimeNanoseconds: UInt64
    private var firstBufferAtUptimeNanoseconds: UInt64?
    private var firstCommittedSampleAtUptimeNanoseconds: UInt64?

    init(requestedAtUptimeNanoseconds: UInt64) {
        self.requestedAtUptimeNanoseconds = requestedAtUptimeNanoseconds
    }

    var snapshot: WhisperAudioCaptureTiming {
        lock.withLock {
            WhisperAudioCaptureTiming(
                requestedAtUptimeNanoseconds:
                    requestedAtUptimeNanoseconds,
                firstBufferAtUptimeNanoseconds:
                    firstBufferAtUptimeNanoseconds,
                firstCommittedSampleAtUptimeNanoseconds:
                    firstCommittedSampleAtUptimeNanoseconds
            )
        }
    }

    func markFirstBuffer(_ uptimeNanoseconds: UInt64) {
        lock.withLock {
            if firstBufferAtUptimeNanoseconds == nil {
                firstBufferAtUptimeNanoseconds = uptimeNanoseconds
            }
        }
    }

    func markFirstCommittedSample(_ uptimeNanoseconds: UInt64) {
        lock.withLock {
            if firstCommittedSampleAtUptimeNanoseconds == nil {
                firstCommittedSampleAtUptimeNanoseconds = uptimeNanoseconds
            }
        }
    }
}

/// Owns the real-time boundary between Core Audio and conversion/file I/O.
/// The tap only snapshots and enqueues PCM. One serial writer queue performs
/// conversion, VAD, metering, and WAV writes in strict arrival order.
final class WhisperBufferedAudioSink: @unchecked Sendable {
    static let maximumQueuedBytes = 32 * 1_024 * 1_024

    private enum Work {
        case audio(WhisperQueuedPCMBuffer)
        case action(WhisperAudioWriterAction)

        var byteCount: Int {
            switch self {
            case let .audio(buffer):
                buffer.byteCount
            case .action:
                0
            }
        }
    }

    private let condition = NSCondition()
    private let writerQueue = DispatchQueue(
        label: "whisper_hotkey.audio.wav-writer",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )
    private let onFirstBuffer: @Sendable (UInt64) -> Void
    private let maximumQueuedBytes: Int
    private var writer: WhisperWAVWriter?
    private var work: [Work] = []
    private var nextWorkIndex = 0
    private var queuedBytes = 0
    private var callbackCount = 0
    private var accepting = true
    private var drainScheduled = false
    private var markedFirstBuffer = false
    private var firstError: Error?

    init(
        maximumQueuedBytes: Int = WhisperBufferedAudioSink.maximumQueuedBytes,
        onFirstBuffer: @escaping @Sendable (UInt64) -> Void = { _ in }
    ) {
        self.maximumQueuedBytes = max(0, maximumQueuedBytes)
        self.onFirstBuffer = onFirstBuffer
    }

    func consume(_ input: AVAudioPCMBuffer) {
        condition.lock()
        guard accepting else {
            condition.unlock()
            return
        }
        callbackCount += 1
        let shouldMarkFirstBuffer = !markedFirstBuffer
        markedFirstBuffer = true
        condition.unlock()

        if shouldMarkFirstBuffer {
            onFirstBuffer(DispatchTime.now().uptimeNanoseconds)
        }
        let copied = WhisperQueuedPCMBuffer(copying: input)

        condition.lock()
        defer {
            callbackCount -= 1
            if callbackCount == 0 {
                condition.broadcast()
            }
            condition.unlock()
        }
        guard firstError == nil else {
            return
        }
        guard let copied else {
            failQueueLocked(
                "Could not retain a microphone input buffer."
            )
            return
        }
        guard copied.byteCount <= maximumQueuedBytes - queuedBytes else {
            failQueueLocked(
                "The microphone writer queue could not keep up."
            )
            return
        }
        work.append(.audio(copied))
        queuedBytes += copied.byteCount
        if scheduleDrainIfNeededLocked() {
            scheduleDrain()
        }
    }

    func attach(_ writer: WhisperWAVWriter) {
        condition.lock()
        self.writer = writer
        let shouldSchedule = scheduleDrainIfNeededLocked()
        condition.unlock()
        if shouldSchedule {
            scheduleDrain()
        }
    }

    func performWriterAction<T>(
        _ body: @escaping (WhisperWAVWriter) throws -> T
    ) throws -> T {
        let completion = WhisperAudioWriterActionCompletion<T>()
        let action = WhisperAudioWriterAction { writer in
            do {
                completion.complete(.success(try body(writer)))
            } catch {
                completion.complete(.failure(error))
            }
        }

        condition.lock()
        guard firstError == nil, accepting, writer != nil else {
            let error = firstError ?? WhisperASRError.captureFailed(
                "The microphone writer is unavailable."
            )
            condition.unlock()
            throw error
        }
        work.append(.action(action))
        let shouldSchedule = scheduleDrainIfNeededLocked()
        condition.unlock()
        if shouldSchedule {
            scheduleDrain()
        }
        return try completion.wait()
    }

    /// Stops accepting tap callbacks and waits for every callback that already
    /// crossed the boundary plus every earlier FIFO item to reach the WAV.
    func finishAcceptingAndWait() -> Error? {
        let completion = WhisperAudioWriterActionCompletion<Void>()
        let action = WhisperAudioWriterAction { _ in
            completion.complete(.success(()))
        }

        condition.lock()
        accepting = false
        while callbackCount > 0 {
            condition.wait()
        }
        if writer != nil {
            work.append(.action(action))
        } else {
            completion.complete(.success(()))
        }
        let shouldSchedule = scheduleDrainIfNeededLocked()
        condition.unlock()
        if shouldSchedule {
            scheduleDrain()
        }
        _ = try? completion.wait()

        condition.lock()
        let error = firstError
        condition.unlock()
        return error
    }

    func cancelAndWait() {
        condition.lock()
        accepting = false
        while callbackCount > 0 {
            condition.wait()
        }
        let shouldSchedule = scheduleDrainIfNeededLocked()
        condition.unlock()
        if shouldSchedule {
            scheduleDrain()
        }

        writerQueue.sync {}

        condition.lock()
        work.removeAll(keepingCapacity: false)
        nextWorkIndex = 0
        queuedBytes = 0
        writer = nil
        drainScheduled = false
        condition.unlock()
    }

    private func failQueueLocked(_ message: String) {
        if firstError == nil {
            firstError = WhisperASRError.captureFailed(message)
        }
        // Once the FIFO loses continuity, further input cannot repair the WAV.
        // Stop accepting instead of silently producing a truncated recording.
        accepting = false
    }

    private func scheduleDrainIfNeededLocked() -> Bool {
        guard writer != nil,
              !drainScheduled,
              nextWorkIndex < work.count
        else {
            return false
        }
        drainScheduled = true
        return true
    }

    private func scheduleDrain() {
        writerQueue.async { [self] in
            drain()
        }
    }

    private func drain() {
        while true {
            condition.lock()
            guard let writer, nextWorkIndex < work.count else {
                if nextWorkIndex >= work.count {
                    work.removeAll(keepingCapacity: true)
                    nextWorkIndex = 0
                }
                drainScheduled = false
                condition.unlock()
                return
            }
            let item = work[nextWorkIndex]
            nextWorkIndex += 1
            condition.unlock()

            switch item {
            case let .audio(buffer):
                writer.consume(buffer.buffer)
            case let .action(action):
                action.execute(with: writer)
            }

            condition.lock()
            queuedBytes -= item.byteCount
            if nextWorkIndex == work.count {
                work.removeAll(keepingCapacity: true)
                nextWorkIndex = 0
            } else if nextWorkIndex >= 256,
                      nextWorkIndex * 2 >= work.count
            {
                work.removeFirst(nextWorkIndex)
                nextWorkIndex = 0
            }
            condition.unlock()
        }
    }
}

private final class WhisperQueuedPCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let byteCount: Int

    init?(copying source: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ) else {
            return nil
        }
        copy.frameLength = source.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: source.audioBufferList)
        )
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(
            copy.mutableAudioBufferList
        )
        guard sourceBuffers.count == destinationBuffers.count else {
            return nil
        }

        var byteCount = 0
        for index in 0..<sourceBuffers.count {
            let sourceBuffer = sourceBuffers[index]
            var destinationBuffer = destinationBuffers[index]
            let bytes = Int(sourceBuffer.mDataByteSize)
            guard bytes <= Int(destinationBuffer.mDataByteSize),
                  let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffer.mData
            else {
                return nil
            }
            destinationData.copyMemory(from: sourceData, byteCount: bytes)
            destinationBuffer.mDataByteSize = UInt32(bytes)
            destinationBuffers[index] = destinationBuffer
            byteCount += bytes
        }
        self.buffer = copy
        self.byteCount = byteCount
    }
}

private final class WhisperAudioWriterAction: @unchecked Sendable {
    private let body: (WhisperWAVWriter) -> Void

    init(_ body: @escaping (WhisperWAVWriter) -> Void) {
        self.body = body
    }

    func execute(with writer: WhisperWAVWriter) {
        body(writer)
    }
}

private final class WhisperAudioWriterActionCompletion<Value>:
    @unchecked Sendable
{
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func complete(_ result: Result<Value, Error>) {
        lock.withLock {
            self.result = result
        }
        semaphore.signal()
    }

    func wait() throws -> Value {
        semaphore.wait()
        return try lock.withLock {
            try result!.get()
        }
    }
}

/// AVAudioEngine invokes tap blocks on a real-time audio queue. Constructing
/// this block inside the recorder's MainActor-isolated `start()` method causes
/// Swift 6 to retain MainActor isolation and trap when Core Audio calls it.
/// The sink is lock-protected, so the callback is intentionally constructed at
/// this nonisolated boundary. Conversion and file I/O never run on this queue.
nonisolated func makeWhisperAudioTapHandler(
    sink: WhisperBufferedAudioSink
) -> AVAudioNodeTapBlock {
    { buffer, _ in
        sink.consume(buffer)
    }
}

final class WhisperWAVWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var segmentFile: AVAudioFile?
    private var segmentAudioFile: WhisperAudioFile?
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let fileSettings: [String: Any]
    private var firstError: Error?
    private var latestNormalizedInputLevel: Float = 0
    private var segmentFrameCount: Int64 = 0
    private var sessionSpeechDetector = WhisperSpeechActivityDetector()
    private var segmentSpeechDetector = WhisperSpeechActivityDetector()
    private let onFirstSamplesCommitted: @Sendable (UInt64) -> Void
    private var committedSamples = false

    init(
        file: AVAudioFile,
        segmentFile: AVAudioFile?,
        segmentAudioFile: WhisperAudioFile?,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        onFirstSamplesCommitted: @escaping @Sendable (UInt64) -> Void = {
            _ in
        }
    ) {
        self.file = file
        self.segmentFile = segmentFile
        self.segmentAudioFile = segmentAudioFile
        self.converter = converter
        self.outputFormat = outputFormat
        self.onFirstSamplesCommitted = onFirstSamplesCommitted
        fileSettings = file.fileFormat.settings
    }

    var outputFileSettings: [String: Any] {
        fileSettings
    }

    var normalizedInputLevel: Float {
        lock.withLock { latestNormalizedInputLevel }
    }

    var speechPresence: WhisperSpeechPresence {
        lock.withLock { sessionSpeechDetector.presence }
    }

    var trailingSilenceDuration: TimeInterval {
        lock.withLock { segmentSpeechDetector.trailingSilenceDuration }
    }

    var segmentDuration: TimeInterval {
        lock.withLock {
            TimeInterval(segmentFrameCount) / outputFormat.sampleRate
        }
    }

    var segmentSpeechPresence: WhisperSpeechPresence {
        lock.withLock { segmentSpeechDetector.presence }
    }

    var pauseBoundarySilence: TimeInterval {
        lock.withLock { segmentSpeechDetector.pauseBoundarySilence }
    }

    func consume(_ input: AVAudioPCMBuffer) {
        lock.withLock {
            guard firstError == nil, let file, let converter else {
                return
            }
            let ratio = outputFormat.sampleRate / input.format.sampleRate
            let capacity = AVAudioFrameCount(
                ceil(Double(input.frameLength) * ratio)
            ) + 1
            guard let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else {
                firstError = WhisperASRError.captureFailed(
                    "Could not allocate an audio conversion buffer."
                )
                return
            }

            let provider = WhisperConverterInput(input)
            var conversionError: NSError?
            let status = converter.convert(
                to: output,
                error: &conversionError
            ) { _, inputStatus in
                if provider.supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                provider.supplied = true
                inputStatus.pointee = .haveData
                return provider.buffer
            }

            if let conversionError {
                firstError = conversionError
            } else if status == .error {
                firstError = WhisperASRError.captureFailed(
                    "Audio conversion failed."
                )
            } else if output.frameLength > 0 {
                do {
                    let measurement = Self.levelMeasurement(output)
                    latestNormalizedInputLevel = measurement.normalizedLevel
                    sessionSpeechDetector.observe(
                        decibels: measurement.decibels,
                        frameCount: Int(output.frameLength),
                        sampleRate: output.format.sampleRate
                    )
                    segmentSpeechDetector.observe(
                        decibels: measurement.decibels,
                        frameCount: Int(output.frameLength),
                        sampleRate: output.format.sampleRate
                    )
                    try file.write(from: output)
                    if !committedSamples {
                        committedSamples = true
                        onFirstSamplesCommitted(
                            DispatchTime.now().uptimeNanoseconds
                        )
                    }
                    try segmentFile?.write(from: output)
                    if segmentFile != nil {
                        segmentFrameCount += Int64(output.frameLength)
                    }
                } catch {
                    firstError = error
                }
            }
        }
    }

    @discardableResult
    func finish() -> Error? {
        let result = finish(retainSegment: false)
        return result.error
    }

    func finishRetainingSegment() -> (
        error: Error?,
        segment: WhisperAudioFile?
    ) {
        finish(retainSegment: true)
    }

    func rotateSegment(
        to nextFile: AVAudioFile,
        audioFile nextAudioFile: WhisperAudioFile
    ) throws -> WhisperAudioFile {
        try lock.withLock {
            if firstError != nil {
                throw WhisperASRError.captureFailed(
                    "Writing microphone audio failed."
                )
            }
            guard let completedAudioFile = segmentAudioFile else {
                throw WhisperASRError.noActiveRecording
            }
            segmentFile = nil
            completedAudioFile.retire()
            completedAudioFile.setSpeechPresence(
                segmentSpeechDetector.presence
            )
            segmentFile = nextFile
            segmentAudioFile = nextAudioFile
            segmentFrameCount = 0
            segmentSpeechDetector =
                segmentSpeechDetector.nextSegmentPreservingCadence()
            return completedAudioFile
        }
    }

    private func finish(retainSegment: Bool) -> (
        error: Error?,
        segment: WhisperAudioFile?
    ) {
        lock.withLock {
            file = nil
            segmentFile = nil
            segmentFrameCount = 0
            let finalSegment = segmentAudioFile
            segmentAudioFile = nil
            finalSegment?.setSpeechPresence(
                segmentSpeechDetector.presence
            )
            finalSegment?.retire()
            if !retainSegment {
                finalSegment?.delete()
            }
            return (
                firstError,
                retainSegment ? finalSegment : nil
            )
        }
    }

    private static func levelMeasurement(
        _ buffer: AVAudioPCMBuffer
    ) -> WhisperAudioLevelMeasurement {
        guard buffer.frameLength > 0,
              let samples = buffer.floatChannelData?[0]
        else {
            return WhisperAudioLevelMeasurement(
                normalizedLevel: 0,
                decibels: -120
            )
        }

        // The converted buffer is only about 20 ms of mono audio. Sampling
        // every fourth frame keeps this callback's meter work negligible.
        let count = Int(buffer.frameLength)
        var sum: Double = 0
        var sampleCount = 0
        var index = 0
        while index < count {
            let sample = Double(samples[index])
            sum += sample * sample
            sampleCount += 1
            index += 4
        }
        guard sampleCount > 0, sum > 0 else {
            return WhisperAudioLevelMeasurement(
                normalizedLevel: 0,
                decibels: -120
            )
        }

        let rms = sqrt(sum / Double(sampleCount))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return WhisperAudioLevelMeasurement(
            normalizedLevel: Float(
                min(1, max(0, (decibels + 55) / 47))
            ),
            decibels: decibels
        )
    }
}

private struct WhisperAudioLevelMeasurement {
    let normalizedLevel: Float
    let decibels: Double
}

struct WhisperSpeechActivityDetector: Equatable {
    static let minimumSpeechDecibels = -48.0
    static let minimumSpeechDuration = 0.10
    static let defaultPauseBoundary = 0.45
    static let minimumPauseBoundary = 0.30
    static let maximumPauseBoundary = 0.75
    static let pauseMargin = 0.18

    private var currentSpeechDuration = 0.0
    private var longestSpeechDuration = 0.0
    private(set) var trailingSilenceDuration = 0.0
    private var typicalPauseDuration: TimeInterval?
    private var observedAudio = false

    mutating func observe(
        decibels: Double,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard frameCount > 0, sampleRate > 0 else {
            return
        }
        observedAudio = true
        let duration = Double(frameCount) / sampleRate
        if decibels >= Self.minimumSpeechDecibels {
            learnFromCompletedPause()
            currentSpeechDuration += duration
            longestSpeechDuration = max(
                longestSpeechDuration,
                currentSpeechDuration
            )
            trailingSilenceDuration = 0
        } else {
            currentSpeechDuration = 0
            if longestSpeechDuration >= Self.minimumSpeechDuration {
                trailingSilenceDuration += duration
            }
        }
    }

    var pauseBoundarySilence: TimeInterval {
        guard let typicalPauseDuration else {
            return Self.defaultPauseBoundary
        }
        return min(
            Self.maximumPauseBoundary,
            max(
                Self.minimumPauseBoundary,
                typicalPauseDuration + Self.pauseMargin
            )
        )
    }

    var presence: WhisperSpeechPresence {
        guard observedAudio else {
            return .absent
        }
        return longestSpeechDuration >= Self.minimumSpeechDuration
            ? .present
            : .absent
    }

    func nextSegmentPreservingCadence() -> Self {
        var next = Self()
        next.typicalPauseDuration = typicalPauseDuration
        return next
    }

    private mutating func learnFromCompletedPause() {
        guard trailingSilenceDuration >= 0.12 else {
            trailingSilenceDuration = 0
            return
        }
        if let typicalPauseDuration {
            self.typicalPauseDuration =
                typicalPauseDuration * 0.75
                + trailingSilenceDuration * 0.25
        } else {
            typicalPauseDuration = trailingSilenceDuration
        }
        trailingSilenceDuration = 0
    }
}

private final class WhisperAudioEngineBox: @unchecked Sendable {
    let engine: AVAudioEngine

    init(_ engine: AVAudioEngine) {
        self.engine = engine
    }

    func stop(removeInputTap: Bool) {
        engine.stop()
        if removeInputTap {
            engine.inputNode.removeTap(onBus: 0)
        }
    }
}

private final class WhisperConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var supplied = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
