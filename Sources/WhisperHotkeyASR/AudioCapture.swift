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
    private let maximumSpanDuration: TimeInterval
    private let lock = NSLock()
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
            .defaultMaximumSpanDuration
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
            holder: holder
        )
    }

    init(
        url: URL,
        directoryURL: URL,
        storage: WhisperAudioLease.Storage,
        resourceID: WhisperAudioLease.Storage.ResourceID,
        speechPresence: WhisperSpeechPresence,
        maximumSpanDuration: TimeInterval,
        holder: WhisperAudioLease.Holder
    ) {
        self.url = url
        self.directoryURL = directoryURL
        self.storage = storage
        self.resourceID = resourceID
        self.holder = holder
        sessionOwned = true
        self.maximumSpanDuration = maximumSpanDuration
        recordedSpeechPresence = speechPresence
    }

    deinit {
        delete()
    }

    public func delete() {
        holder.release()
        if !sessionOwned {
            storage.finish()
        }
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

@MainActor
public final class WhisperAudioRecorder {
    private let engineBox: WhisperAudioEngineBox
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private var writer: WhisperWAVWriter?
    private var audioFile: WhisperAudioFile?
    private var audioLease: WhisperAudioLease?
    private var inputTapInstalled = false

    public init(
        audioEngine: AVAudioEngine = AVAudioEngine(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        engineBox = WhisperAudioEngineBox(audioEngine)
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    public var isRecording: Bool {
        audioFile != nil && engineBox.engine.isRunning
    }

    /// A normalized 0...1 microphone level for lightweight presentation.
    /// Reading this value does not touch AVAudioEngine and is useful only while
    /// recording.
    public var normalizedInputLevel: Float {
        writer?.normalizedInputLevel ?? 0
    }

    /// Silence following confirmed speech in the current recording. This is
    /// updated by the existing audio callback and adds no timer or audio pass.
    public var trailingSilenceDuration: TimeInterval {
        writer?.trailingSilenceDuration ?? 0
    }

    /// Duration and speech state for the current inference segment. Both are
    /// maintained by the existing audio callback and read only while capture
    /// is active.
    public var currentSegmentDuration: TimeInterval {
        writer?.segmentDuration ?? 0
    }

    public var currentSegmentSpeechPresence: WhisperSpeechPresence {
        writer?.segmentSpeechPresence ?? .unknown
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
        writer?.pauseBoundarySilence
            ?? WhisperSpeechActivityDetector.defaultPauseBoundary
    }

    deinit {
        let lease = audioLease
        engineBox.stop(removeInputTap: inputTapInstalled)
        writer?.finish()
        audioFile?.delete()
        lease?.finish()
    }

    @discardableResult
    public func start(pauseSegmentation: Bool = false) throws -> URL {
        cancel()
        let audioFile = try makePrivateAudioFile()
        var segmentAudioFile: WhisperAudioFile?

        do {
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
            let outputFile = try AVAudioFile(
                forWriting: audioFile.url,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: audioFile.url.path
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
                outputFormat: outputFile.processingFormat
            )
            let tapHandler = makeWhisperAudioTapHandler(writer: writer)
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: inputFormat,
                block: tapHandler
            )
            inputTapInstalled = true
            self.writer = writer
            self.audioFile = audioFile
            segmentAudioFile = nil
            engineBox.engine.prepare()
            try engineBox.engine.start()
            return audioFile.url
        } catch {
            let lease = audioLease
            engineBox.engine.stop()
            removeInputTap()
            writer?.finish()
            writer = nil
            self.audioFile = nil
            audioFile.delete()
            segmentAudioFile?.delete()
            lease?.finish()
            audioLease = nil
            if let error = error as? WhisperASRError {
                throw error
            }
            throw WhisperASRError.captureFailed(
                "Audio engine setup failed."
            )
        }
    }

    public func stop() throws -> WhisperAudioFile {
        guard let audioFile else {
            throw WhisperASRError.noActiveRecording
        }
        let lease = audioLease
        engineBox.engine.stop()
        removeInputTap()
        let speechPresence = writer?.speechPresence ?? .unknown
        let writeError = writer?.finish()
        writer = nil
        self.audioFile = nil

        if writeError != nil {
            audioFile.delete()
            lease?.finish()
            audioLease = nil
            throw WhisperASRError.captureFailed(
                "Writing microphone audio failed."
            )
        }
        audioFile.setSpeechPresence(speechPresence)
        lease?.finish()
        audioLease = nil
        return audioFile
    }

    /// Rotates only the inference segment while the uninterrupted private
    /// session recording and microphone engine continue running.
    public func rotatePauseSegment() throws -> WhisperAudioFile {
        guard let writer, audioFile != nil, engineBox.engine.isRunning else {
            throw WhisperASRError.noActiveRecording
        }
        let nextAudio = try makePrivateAudioFile()
        do {
            let nextFile = try makeOutputFile(
                for: nextAudio,
                settings: writer.outputFileSettings
            )
            return try writer.rotateSegment(
                to: nextFile,
                audioFile: nextAudio
            )
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

    /// Stops one continuous Pause Mode recording and returns both the complete
    /// private session audio and its untranscribed final segment.
    public func stopPauseSession() throws -> (
        recording: WhisperAudioFile,
        finalSegment: WhisperAudioFile
    ) {
        guard let audioFile, let writer else {
            throw WhisperASRError.noActiveRecording
        }
        let lease = audioLease
        engineBox.engine.stop()
        removeInputTap()
        let speechPresence = writer.speechPresence
        let result = writer.finishRetainingSegment()
        self.writer = nil
        self.audioFile = nil

        guard result.error == nil, let finalSegment = result.segment else {
            audioFile.delete()
            result.segment?.delete()
            lease?.finish()
            audioLease = nil
            throw WhisperASRError.captureFailed(
                "Writing microphone audio failed."
            )
        }
        audioFile.setSpeechPresence(speechPresence)
        lease?.finish()
        audioLease = nil
        return (audioFile, finalSegment)
    }

    public func cancel() {
        let lease = audioLease
        engineBox.engine.stop()
        removeInputTap()
        writer?.finish()
        writer = nil
        audioFile?.delete()
        audioFile = nil
        lease?.finish()
        audioLease = nil
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
}

/// AVAudioEngine invokes tap blocks on a real-time audio queue. Constructing
/// this block inside the recorder's MainActor-isolated `start()` method causes
/// Swift 6 to retain MainActor isolation and trap when Core Audio calls it.
/// The writer is lock-protected, so the callback is intentionally constructed
/// at this nonisolated boundary.
nonisolated func makeWhisperAudioTapHandler(
    writer: WhisperWAVWriter
) -> AVAudioNodeTapBlock {
    { buffer, _ in
        writer.consume(buffer)
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

    init(
        file: AVAudioFile,
        segmentFile: AVAudioFile?,
        segmentAudioFile: WhisperAudioFile?,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        self.file = file
        self.segmentFile = segmentFile
        self.segmentAudioFile = segmentAudioFile
        self.converter = converter
        self.outputFormat = outputFormat
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
