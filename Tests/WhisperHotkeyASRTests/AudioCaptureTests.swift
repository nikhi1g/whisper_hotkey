@preconcurrency import AVFoundation
import Foundation
import XCTest
@testable import WhisperHotkeyASR

final class AudioCaptureTests: XCTestCase {
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

        for _ in 0..<10 {
            writer.consume(input)
        }
        XCTAssertNil(writer.finish())
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
}
