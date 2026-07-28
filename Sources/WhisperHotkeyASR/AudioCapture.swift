@preconcurrency import AVFoundation
import Foundation

public final class WhisperAudioFile: @unchecked Sendable {
    public let url: URL

    private let directoryURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var deleted = false

    init(url: URL, directoryURL: URL, fileManager: FileManager = .default) {
        self.url = url
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    deinit {
        delete()
    }

    public func delete() {
        let shouldDelete = lock.withLock {
            guard !deleted else { return false }
            deleted = true
            return true
        }
        if shouldDelete {
            try? fileManager.removeItem(at: directoryURL)
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

    deinit {
        engineBox.stop(removeInputTap: inputTapInstalled)
        writer?.finish()
        audioFile?.delete()
    }

    @discardableResult
    public func start() throws -> URL {
        cancel()
        let audioFile = try makePrivateAudioFile()

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
            engineBox.engine.prepare()
            try engineBox.engine.start()
            return audioFile.url
        } catch {
            engineBox.engine.stop()
            removeInputTap()
            writer?.finish()
            writer = nil
            self.audioFile = nil
            audioFile.delete()
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
        engineBox.engine.stop()
        removeInputTap()
        let writeError = writer?.finish()
        writer = nil
        self.audioFile = nil

        if writeError != nil {
            audioFile.delete()
            throw WhisperASRError.captureFailed(
                "Writing microphone audio failed."
            )
        }
        return audioFile
    }

    public func cancel() {
        engineBox.engine.stop()
        removeInputTap()
        writer?.finish()
        writer = nil
        audioFile?.delete()
        audioFile = nil
    }

    private func makePrivateAudioFile() throws -> WhisperAudioFile {
        let directory = temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-\(UUID().uuidString)",
                isDirectory: true
            )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            let url = directory.appendingPathComponent("dictation.wav")
            return WhisperAudioFile(
                url: url,
                directoryURL: directory,
                fileManager: fileManager
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            throw WhisperASRError.captureFailed(
                "Could not create private temporary storage."
            )
        }
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
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private var firstError: Error?
    private var latestNormalizedInputLevel: Float = 0

    init(
        file: AVAudioFile,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        self.file = file
        self.converter = converter
        self.outputFormat = outputFormat
    }

    var normalizedInputLevel: Float {
        lock.withLock { latestNormalizedInputLevel }
    }

    func consume(_ input: AVAudioPCMBuffer) {
        lock.withLock {
            guard firstError == nil, let file, let converter else { return }
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
                    latestNormalizedInputLevel = Self.normalizedLevel(output)
                    try file.write(from: output)
                } catch {
                    firstError = error
                }
            }
        }
    }

    @discardableResult
    func finish() -> Error? {
        lock.withLock {
            file = nil
            converter = nil
            latestNormalizedInputLevel = 0
            return firstError
        }
    }

    private static func normalizedLevel(
        _ buffer: AVAudioPCMBuffer
    ) -> Float {
        guard buffer.frameLength > 0,
              let samples = buffer.floatChannelData?[0]
        else {
            return 0
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
            return 0
        }

        let rms = sqrt(sum / Double(sampleCount))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return Float(min(1, max(0, (decibels + 55) / 47)))
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
