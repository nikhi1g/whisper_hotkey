import Foundation
import XCTest
@testable import WhisperHotkeyASR

/// Regression coverage for the internal-dictionary prompt echo bug.
///
/// whisper's decoder treats `initial_prompt` as if it were prior transcript
/// text. When a clip has no real speech for a vocabulary-biasing prompt (the
/// Internal Dictionary, rendered as a comma-separated list by
/// `InternalDictionary.makePrompt`) to legitimately bias, the decoder can
/// instead "continue" that prompt, confidently emitting dictionary entries
/// verbatim into the transcript even though nothing was said.
///
/// The fix (`Sources/WhisperModelHelper/main.cpp`, `signal_rms` /
/// `kMinimumPromptSignalRms`) suppresses the prompt for a decode whenever the
/// clip's RMS level is below a floor that genuine dictated speech clears by
/// roughly an order of magnitude. These tests drive the real, compiled
/// helper binary end to end (not a stub), matching how
/// `Tests/WhisperHotkeyShellTests/CLIParsingTests.swift` exercises the real
/// `whisper_hotkey` controller.
final class DictionaryPromptEchoTests: XCTestCase {
    private let dictionaryEntries = ["Claude Code", "SAM", "C.md", "Codex.md"]

    func testNearSilentAudioNeverEchoesDictionaryVocabulary() throws {
        let helper = try locateHelperExecutable()
        let model = try locateEchoProneModel()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Four seconds of quiet background noise: no speech at all, at a
        // level well below normal dictation volume but still non-zero (so
        // the helper's own no_speech guard doesn't short-circuit decoding).
        let quietAudio = try writeWAV(
            samples: quietNoiseSamples(seconds: 4, amplitude: 800, seed: 800),
            to: root.appendingPathComponent("quiet.wav")
        )

        let text = try runHelper(
            helper: helper,
            model: model,
            audioURL: quietAudio,
            prompt: dictionaryEntries.joined(separator: ", ")
        )

        for entry in dictionaryEntries {
            XCTAssertNil(
                text.range(of: entry, options: .caseInsensitive),
                "Near-silent audio must never echo dictionary entry " +
                    "\"\(entry)\" into the transcript; got \"\(text)\""
            )
        }
    }

    func testGenuineSpeechContainingADictionaryWordStillTranscribesIt()
        throws {
        let helper = try locateHelperExecutable()
        let model = try locateDefaultModel()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let audio = try synthesizeSpeech(
            "Codex",
            to: root.appendingPathComponent("codex.wav")
        )

        let text = try runHelper(
            helper: helper,
            model: model,
            audioURL: audio,
            prompt: dictionaryEntries.joined(separator: ", ")
        )

        XCTAssertNotNil(
            text.range(of: "codex", options: .caseInsensitive),
            "Genuinely dictated speech containing a dictionary word must " +
                "still be recognized as that word; got \"\(text)\""
        )
    }

    // MARK: - Executable and model discovery

    private func locateHelperExecutable() throws -> URL {
        let roots = [
            Bundle(for: Self.self).bundleURL,
            URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent(),
        ]
        for initialRoot in roots {
            var root = initialRoot
            for _ in 0..<8 {
                let candidate = root
                    .appendingPathComponent("WhisperModelHelper")
                if FileManager.default.isExecutableFile(
                    atPath: candidate.path
                ) {
                    return candidate
                }
                root.deleteLastPathComponent()
            }
        }
        throw XCTSkip(
            "Build the WhisperModelHelper target before running this test."
        )
    }

    private func locateDefaultModel() throws -> URL {
        try locateCachedModel(named: "ggml-base.en.bin")
    }

    /// The dictionary-echo hallucination reproduces confidently on a larger
    /// model (verified against ggml-large-v3-turbo-q5_0.bin); the smaller
    /// default base.en model falls back to generic filler instead of
    /// literal dictionary text on the same inputs. Prefer the model this
    /// bug was actually confirmed against so the negative assertion is
    /// meaningful rather than vacuously true.
    private func locateEchoProneModel() throws -> URL {
        if let url = try? locateCachedModel(
            named: "ggml-large-v3-turbo-q5_0.bin"
        ) {
            return url
        }
        throw XCTSkip(
            "No cached ggml-large-v3-turbo-q5_0.bin; this is the model " +
                "the dictionary-echo hallucination was confirmed against. " +
                "Download it to ~/.cache/whisper to run this test."
        )
    }

    private func locateCachedModel(named name: String) throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let model = home.appendingPathComponent(".cache/whisper/\(name)")
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw XCTSkip(
                "No cached whisper model at \(model.path); download one " +
                    "before running this test."
            )
        }
        return model
    }

    // MARK: - Fixtures

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "whisper_hotkey-echo-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private func quietNoiseSamples(
        seconds: Double,
        amplitude: Int16,
        seed: UInt64
    ) -> [Int16] {
        var generator = SplitMixGenerator(seed: seed)
        let count = Int(16_000 * seconds)
        return (0..<count).map { _ in
            Int16.random(in: -amplitude...amplitude, using: &generator)
        }
    }

    private func writeWAV(samples: [Int16], to url: URL) throws -> URL {
        var data = Data()
        let byteRate: UInt32 = 16_000 * 2
        let dataSize = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndian: UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt32(16_000))
        data.append(littleEndian: byteRate)
        data.append(littleEndian: UInt16(2))
        data.append(littleEndian: UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndian: dataSize)
        for sample in samples {
            data.append(littleEndian: UInt16(bitPattern: sample))
        }
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return url
    }

    private func synthesizeSpeech(_ text: String, to url: URL) throws -> URL {
        let aiff = url.deletingPathExtension()
            .appendingPathExtension("aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", aiff.path, text]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else {
            throw XCTSkip("`say` was unavailable to synthesize test speech.")
        }

        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        convert.arguments = [
            "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
            aiff.path, url.path,
        ]
        try convert.run()
        convert.waitUntilExit()
        guard convert.terminationStatus == 0 else {
            throw XCTSkip(
                "`afconvert` was unavailable to prepare test audio."
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return url
    }

    // MARK: - Helper process

    private func runHelper(
        helper: URL,
        model: URL,
        audioURL: URL,
        prompt: String
    ) throws -> String {
        let process = Process()
        process.executableURL = helper
        process.arguments = [
            "--model", model.path,
            "--threads", "4",
            "--strategy", "greedy",
        ]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + 60,
            execute: watchdog
        )
        defer { watchdog.cancel() }

        stdin.fileHandleForWriting.write(
            try WhisperHelperProtocol.transcribeCommand(
                audioURL: audioURL,
                prompt: prompt
            )
        )

        var resultText: String?
        var buffer = Data()
        while resultText == nil {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(
                    in: buffer.startIndex..<newlineIndex
                )
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                guard let line = String(data: lineData, encoding: .utf8),
                      let event = try? WhisperHelperProtocol.parse(line)
                else {
                    continue
                }
                switch event {
                case .ready:
                    continue
                case .result(let text):
                    resultText = text
                case .resultRich(let hypothesis):
                    resultText = hypothesis.text
                case .error(let code, let message):
                    XCTFail("helper reported error \(code): \(message)")
                    resultText = ""
                }
            }
        }

        stdin.fileHandleForWriting.closeFile()
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        return try XCTUnwrap(
            resultText,
            "Helper produced no result before closing its output."
        )
    }
}

/// Minimal deterministic xorshift64 generator so noise fixtures are
/// reproducible across runs without depending on true randomness.
private struct SplitMixGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
        if state == 0 {
            state = 0x9E37_79B9_7F4A_7C15
        }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }

    mutating func append(littleEndian value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }
}
