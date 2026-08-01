@preconcurrency import AVFoundation
import Foundation
import XCTest
@testable import WhisperHotkeyASR

final class AudioCaptureTests: XCTestCase {
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

        let callback = AudioTapInvocation(
            block: makeWhisperAudioTapHandler(writer: writer),
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
        XCTAssertGreaterThan(writer.normalizedInputLevel, 0.3)
        XCTAssertLessThanOrEqual(writer.normalizedInputLevel, 1)

        for _ in 0..<9 {
            writer.consume(input)
        }
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
        let completedSegment = try writer.rotateSegment(
            to: nextSegmentFile,
            audioFile: nextSegmentAudio
        )
        XCTAssertEqual(completedSegment.speechPresence, .present)
        XCTAssertEqual(writer.trailingSilenceDuration, 0)
        XCTAssertEqual(writer.segmentDuration, 0)

        for _ in 0..<5 {
            writer.consume(input)
        }
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
