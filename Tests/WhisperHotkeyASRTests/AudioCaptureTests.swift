@preconcurrency import AVFoundation
import Foundation
import XCTest
@testable import WhisperHotkeyASR

final class AudioCaptureTests: XCTestCase {
    func testFastPathActivatesCaptureBeforePreparingWriter() throws {
        var events: [String] = []

        let prepared = try activateWhisperCaptureFastPath(
            activateCapture: {
                events.append("capture")
            },
            prepareWriter: {
                events.append("writer")
                return 42
            },
            adoptWriter: { value in
                XCTAssertEqual(value, 42)
                events.append("adopt")
            }
        )

        XCTAssertEqual(prepared, 42)
        XCTAssertEqual(events, ["capture", "writer", "adopt"])
    }

    func testBufferedSinkRetainsFirstBufferAndWritesFIFOAfterAttach()
        throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-buffered-audio-test-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dictation.wav")
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let fileFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        var outputFile: AVAudioFile? = try AVAudioFile(
            forWriting: url,
            settings: fileFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let processingFormat = try XCTUnwrap(outputFile?.processingFormat)
        let converter = try XCTUnwrap(
            AVAudioConverter(from: format, to: processingFormat)
        )
        let timing = LockedAudioTiming()
        let writer = WhisperWAVWriter(
            file: try XCTUnwrap(outputFile),
            segmentFile: nil,
            segmentAudioFile: nil,
            converter: converter,
            outputFormat: processingFormat,
            onFirstSamplesCommitted: timing.recordCommitted
        )
        let sink = WhisperBufferedAudioSink(
            onFirstBuffer: timing.recordBuffer
        )
        let first = try makeConstantBuffer(format: format, value: 0.25)
        let second = try makeConstantBuffer(format: format, value: -0.25)

        // This is the startup race: Core Audio delivers speech before private
        // file/converter preparation has attached the writer.
        sink.consume(first)
        sink.attach(writer)
        sink.consume(second)
        XCTAssertNil(sink.finishAcceptingAndWait())
        XCTAssertNil(writer.finish())
        outputFile = nil

        let written = try AVAudioFile(forReading: url)
        let samples = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: written.processingFormat,
                frameCapacity: AVAudioFrameCount(written.length)
            )
        )
        try written.read(into: samples)
        let channel = try XCTUnwrap(samples.floatChannelData?[0])
        XCTAssertEqual(samples.frameLength, 640)
        XCTAssertGreaterThan(channel[0], 0.2)
        XCTAssertLessThan(channel[320], -0.2)

        let timestamps = timing.snapshot
        XCTAssertNotNil(timestamps.buffer)
        XCTAssertNotNil(timestamps.committed)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(timestamps.buffer),
            try XCTUnwrap(timestamps.committed)
        )
    }

    func testBufferedSinkOverflowFailsInsteadOfTruncatingSilently()
        throws
    {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let input = try makeConstantBuffer(format: format, value: 0.1)
        let sink = WhisperBufferedAudioSink(maximumQueuedBytes: 1)

        sink.consume(input)

        XCTAssertNotNil(sink.finishAcceptingAndWait())
    }

    func testEmptyCallbackDoesNotCountAsFirstMicrophoneBuffer() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let empty = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)
        )
        empty.frameLength = 0
        let timing = LockedAudioTiming()
        let sink = WhisperBufferedAudioSink(
            onFirstBuffer: timing.recordBuffer
        )

        sink.consume(empty)

        XCTAssertNil(timing.snapshot.buffer)
        XCTAssertNil(sink.finishAcceptingAndWait())
    }

    func testCaptureTimingUsesIntegerUptimeDeltas() {
        let timing = WhisperAudioCaptureTiming(
            requestedAtUptimeNanoseconds: 100,
            firstBufferAtUptimeNanoseconds: 145,
            firstCommittedSampleAtUptimeNanoseconds: 210
        )

        XCTAssertEqual(timing.requestToFirstBufferNanoseconds, 45)
        XCTAssertEqual(
            timing.requestToFirstCommittedSampleNanoseconds,
            110
        )
    }

    func testCompletionGraceAppliesOnlyToConfirmedRecentSpeech() {
        XCTAssertEqual(
            CompletionCaptureGracePolicy.delay(
                speechPresence: .present,
                trailingSilence: 0
            ),
            CompletionCaptureGracePolicy.graceDuration
        )
        XCTAssertEqual(
            CompletionCaptureGracePolicy.delay(
                speechPresence: .present,
                trailingSilence:
                    CompletionCaptureGracePolicy.recentSpeechWindow - 0.001
            ),
            CompletionCaptureGracePolicy.graceDuration
        )
        XCTAssertNil(
            CompletionCaptureGracePolicy.delay(
                speechPresence: .present,
                trailingSilence:
                    CompletionCaptureGracePolicy.recentSpeechWindow
            )
        )
        XCTAssertNil(
            CompletionCaptureGracePolicy.delay(
                speechPresence: .absent,
                trailingSilence: 0
            )
        )
        XCTAssertNil(
            CompletionCaptureGracePolicy.delay(
                speechPresence: .unknown,
                trailingSilence: 0
            )
        )
    }
    func testWriterConvertsToPrivate16KHzMonoPCM16WAV() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-audio-test-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dictation.wav")
        let segmentDirectory = directory.appendingPathComponent(
            "segment",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: segmentDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let segmentURL = segmentDirectory.appendingPathComponent(
            "dictation.wav"
        )

        let inputFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )
        let fileFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        var outputFile: AVAudioFile? = try AVAudioFile(
            forWriting: url,
            settings: fileFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let segmentFile = try AVAudioFile(
            forWriting: segmentURL,
            settings: fileFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let segmentAudioFile = WhisperAudioFile(
            url: segmentURL,
            directoryURL: segmentDirectory
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        let processingFormat = try XCTUnwrap(outputFile?.processingFormat)
        let converter = try XCTUnwrap(
            AVAudioConverter(from: inputFormat, to: processingFormat)
        )
        let writer = WhisperWAVWriter(
            file: try XCTUnwrap(outputFile),
            segmentFile: segmentFile,
            segmentAudioFile: segmentAudioFile,
            converter: converter,
            outputFormat: processingFormat
        )
        let input = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: 4_800
            )
        )
        input.frameLength = 4_800
        for channel in 0..<Int(inputFormat.channelCount) {
            let samples = try XCTUnwrap(input.floatChannelData?[channel])
            for index in 0..<Int(input.frameLength) {
                samples[index] = Float(
                    sin(
                        Double(index) * 2 * .pi * 440
                            / inputFormat.sampleRate
                    ) * 0.25
                )
            }
        }

        let sink = WhisperBufferedAudioSink()
        sink.attach(writer)
        let callback = AudioTapInvocation(
            block: makeWhisperAudioTapHandler(sink: sink),
            buffer: input
        )
        let callbackFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            callback.invoke()
            callbackFinished.signal()
        }
        XCTAssertEqual(
            callbackFinished.wait(timeout: .now() + 2),
            .success
        )
        _ = try sink.performWriterAction { _ in () }
        XCTAssertGreaterThan(writer.normalizedInputLevel, 0.3)
        XCTAssertLessThanOrEqual(writer.normalizedInputLevel, 1)

        for _ in 0..<9 {
            sink.consume(input)
        }
        _ = try sink.performWriterAction { _ in () }
        XCTAssertEqual(writer.speechPresence, .present)
        XCTAssertGreaterThan(writer.segmentDuration, 0.9)
        XCTAssertEqual(writer.segmentSpeechPresence, .present)
        let nextSegmentDirectory = directory.appendingPathComponent(
            "next-segment",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: nextSegmentDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let nextSegmentURL = nextSegmentDirectory.appendingPathComponent(
            "dictation.wav"
        )
        let nextSegmentFile = try AVAudioFile(
            forWriting: nextSegmentURL,
            settings: fileFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let nextSegmentAudio = WhisperAudioFile(
            url: nextSegmentURL,
            directoryURL: nextSegmentDirectory
        )
        let completedSegment = try sink.performWriterAction { writer in
            try writer.rotateSegment(
                to: nextSegmentFile,
                audioFile: nextSegmentAudio
            )
        }
        XCTAssertEqual(completedSegment.speechPresence, .present)
        XCTAssertEqual(writer.trailingSilenceDuration, 0)
        XCTAssertEqual(writer.segmentDuration, 0)

        for _ in 0..<5 {
            sink.consume(input)
        }
        XCTAssertNil(sink.finishAcceptingAndWait())
        XCTAssertGreaterThan(writer.segmentDuration, 0.4)
        let finishResult = writer.finishRetainingSegment()
        XCTAssertNil(finishResult.error)
        XCTAssertEqual(finishResult.segment?.speechPresence, .present)
        let completedSegmentFile = try AVAudioFile(
            forReading: completedSegment.url
        )
        XCTAssertEqual(
            completedSegmentFile.fileFormat.commonFormat,
            .pcmFormatInt16
        )
        completedSegment.delete()
        finishResult.segment?.delete()
        outputFile = nil

        let written = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(written.length, 0)
        XCTAssertEqual(written.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(written.fileFormat.channelCount, 1)
        XCTAssertEqual(
            written.fileFormat.commonFormat,
            .pcmFormatInt16
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testWriterReplacesAStaleConverterWithTheActualBufferFormat()
        throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-format-change-test-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dictation.wav")
        let staleFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )
        let actualFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 24_000,
                channels: 1,
                interleaved: false
            )
        )
        let fileFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        var outputFile: AVAudioFile? = try AVAudioFile(
            forWriting: url,
            settings: fileFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let processingFormat = try XCTUnwrap(outputFile?.processingFormat)
        let staleConverter = try XCTUnwrap(
            AVAudioConverter(from: staleFormat, to: processingFormat)
        )
        let writer = WhisperWAVWriter(
            file: try XCTUnwrap(outputFile),
            segmentFile: nil,
            segmentAudioFile: nil,
            converter: staleConverter,
            outputFormat: processingFormat
        )
        let input = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: actualFormat,
                frameCapacity: 2_400
            )
        )
        input.frameLength = 2_400
        let samples = try XCTUnwrap(input.floatChannelData?[0])
        for index in 0..<Int(input.frameLength) {
            samples[index] = 0.2
        }

        writer.consume(input)

        XCTAssertNil(writer.finish())
        outputFile = nil
        let written = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(written.length, 1_500)
        XCTAssertLessThan(written.length, 1_700)
    }

    func testAudioFileDeletesItsWholePrivateDirectoryIdempotently()
        throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-cleanup-test-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("dictation.wav")
        try Data([0]).write(to: url)
        let audio = WhisperAudioFile(
            url: url,
            directoryURL: directory
        )

        audio.delete()
        audio.delete()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.path)
        )
    }

    func testVoiceActivityRejectsSustainedSilence() {
        var detector = WhisperSpeechActivityDetector()
        for _ in 0..<100 {
            detector.observe(
                decibels: -70,
                frameCount: 320,
                sampleRate: 16_000
            )
        }
        XCTAssertEqual(detector.presence, .absent)
    }

    func testVoiceActivityAcceptsSustainedQuietSpeech() {
        var detector = WhisperSpeechActivityDetector()
        for _ in 0..<5 {
            detector.observe(
                decibels: -47,
                frameCount: 320,
                sampleRate: 16_000
            )
        }
        XCTAssertEqual(detector.presence, .present)
    }

    func testVoiceActivityRejectsBriefTransient() {
        var detector = WhisperSpeechActivityDetector()
        detector.observe(
            decibels: -20,
            frameCount: 640,
            sampleRate: 16_000
        )
        detector.observe(
            decibels: -70,
            frameCount: 320,
            sampleRate: 16_000
        )
        XCTAssertEqual(detector.presence, .absent)
    }

    func testTrailingSilenceStartsOnlyAfterConfirmedSpeechAndResets() {
        var detector = WhisperSpeechActivityDetector()
        for _ in 0..<20 {
            detector.observe(
                decibels: -70,
                frameCount: 320,
                sampleRate: 16_000
            )
        }
        XCTAssertEqual(detector.trailingSilenceDuration, 0)

        for _ in 0..<5 {
            detector.observe(
                decibels: -40,
                frameCount: 320,
                sampleRate: 16_000
            )
        }
        for _ in 0..<40 {
            detector.observe(
                decibels: -70,
                frameCount: 320,
                sampleRate: 16_000
            )
        }
        XCTAssertEqual(
            detector.trailingSilenceDuration,
            0.8,
            accuracy: 0.001
        )

        detector.observe(
            decibels: -40,
            frameCount: 320,
            sampleRate: 16_000
        )
        XCTAssertEqual(detector.trailingSilenceDuration, 0)
    }

    func testPauseBoundaryLearnsCadenceWithinStrictBounds() {
        var detector = WhisperSpeechActivityDetector()
        XCTAssertEqual(
            detector.pauseBoundarySilence,
            WhisperSpeechActivityDetector.defaultPauseBoundary
        )

        for _ in 0..<5 {
            detector.observe(
                decibels: -40,
                frameCount: 320,
                sampleRate: 16_000
            )
        }
        for _ in 0..<20 {
            detector.observe(
                decibels: -70,
                frameCount: 320,
                sampleRate: 16_000
            )
        }
        detector.observe(
            decibels: -40,
            frameCount: 320,
            sampleRate: 16_000
        )

        XCTAssertEqual(
            detector.pauseBoundarySilence,
            0.58,
            accuracy: 0.001
        )
        let next = detector.nextSegmentPreservingCadence()
        XCTAssertEqual(
            next.pauseBoundarySilence,
            detector.pauseBoundarySilence,
            accuracy: 0.001
        )
        XCTAssertEqual(next.trailingSilenceDuration, 0)
        XCTAssertEqual(next.presence, .absent)
    }

    private func makeConstantBuffer(
        format: AVAudioFormat,
        value: Float
    ) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)
        )
        buffer.frameLength = 320
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<320 {
            samples[index] = value
        }
        return buffer
    }
}

private final class LockedAudioTiming: @unchecked Sendable {
    private let lock = NSLock()
    private var firstBuffer: UInt64?
    private var firstCommitted: UInt64?

    var snapshot: (buffer: UInt64?, committed: UInt64?) {
        lock.lock()
        defer { lock.unlock() }
        return (firstBuffer, firstCommitted)
    }

    func recordBuffer(_ uptimeNanoseconds: UInt64) {
        lock.lock()
        if firstBuffer == nil {
            firstBuffer = uptimeNanoseconds
        }
        lock.unlock()
    }

    func recordCommitted(_ uptimeNanoseconds: UInt64) {
        lock.lock()
        if firstCommitted == nil {
            firstCommitted = uptimeNanoseconds
        }
        lock.unlock()
    }
}

private final class AudioTapInvocation: @unchecked Sendable {
    private let block: AVAudioNodeTapBlock
    private let buffer: AVAudioPCMBuffer

    init(block: @escaping AVAudioNodeTapBlock, buffer: AVAudioPCMBuffer) {
        self.block = block
        self.buffer = buffer
    }

    func invoke() {
        block(buffer, AVAudioTime())
    }
}
