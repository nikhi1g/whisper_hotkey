import Foundation
import FluidAudio

// Usage:
//   parakeet-benchmark <v2|v3|tdtCtc110m> <wav-list-file>
//     Transcribes each WAV and emits one JSON object per line:
//     {"id":..., "text":..., "seconds":...}
//   parakeet-benchmark download <v2|v3|tdtCtc110m> [more...]
//     Downloads the named checkpoints into FluidAudio's cache and exits.
//     The release build bundles the checkpoints into the app, so a clean
//     machine has to populate that cache before build_app.py can copy them.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

func parseVersion(_ name: String) -> AsrModelVersion {
    switch name {
    case "v2": return .v2
    case "v3": return .v3
    case "tdtCtc110m": return .tdtCtc110m
    default: fail("unknown version \(name)")
    }
}

let arguments = CommandLine.arguments

if arguments.count >= 2, arguments[1] == "download" {
    let names = Array(arguments.dropFirst(2))
    guard !names.isEmpty else {
        fail("usage: parakeet-benchmark download <v2|v3|tdtCtc110m> [more...]")
    }
    for name in names {
        let version = parseVersion(name)
        // A no-op when the checkpoint is already complete, so this is safe to
        // run unconditionally in CI and locally.
        let directory = try await AsrModels.download(version: version)
        FileHandle.standardError.write(
            "ready \(name) at \(directory.path)\n".data(using: .utf8)!
        )
    }
    exit(0)
}

// Parakeet Unified: one checkpoint serving offline and streaming. Benchmarked
// through the same WAV list and JSON output as every other engine here.
if arguments.count == 3, arguments[1] == "unified" {
    let listURL = URL(fileURLWithPath: arguments[2])
    let paths = try String(contentsOf: listURL, encoding: .utf8)
        .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    let manager = UnifiedAsrManager()
    let converter = AudioConverter()
    let loadStart = Date()
    // Downloads on first use, then loads from the same cache.
    try await manager.loadModels()
    FileHandle.standardError.write(
        "loaded unified in \(String(format: "%.1f", Date().timeIntervalSince(loadStart)))s\n"
            .data(using: .utf8)!
    )
    if let first = paths.first {
        for _ in 0..<2 {
            _ = try? await manager.transcribe(
                try converter.resampleAudioFile(URL(fileURLWithPath: first))
            )
        }
        FileHandle.standardError.write("warmed up\n".data(using: .utf8)!)
    }
    struct UnifiedRow: Encodable {
        let id: String
        let text: String
        let seconds: Double
    }
    let encoder = JSONEncoder()
    for path in paths {
        let url = URL(fileURLWithPath: path)
        let samples = try converter.resampleAudioFile(url)
        try await manager.reset()
        let started = Date()
        let text = try await manager.transcribe(samples)
        let row = UnifiedRow(
            id: url.deletingPathExtension().lastPathComponent,
            text: text,
            seconds: Date().timeIntervalSince(started)
        )
        FileHandle.standardOutput.write(try encoder.encode(row))
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
    await manager.cleanup()
    exit(0)
}

// Cohere Transcribe: a different engine entirely, benchmarked through the same
// WAV list and JSON output so its WER and latency are directly comparable.
if arguments.count >= 2, arguments[1] == "cohere-download" {
    let directory = MLModelConfigurationUtils.defaultModelsDirectory(
        for: Repo.cohereTranscribeCoreml
    )
    FileHandle.standardError.write(
        "downloading to \(directory.path)\n".data(using: .utf8)!
    )
    try await ModelHub.download(.cohereTranscribeCoreml, to: directory)
    FileHandle.standardError.write("ready\n".data(using: .utf8)!)
    exit(0)
}

if arguments.count == 3, arguments[1] == "cohere" {
    let listURL = URL(fileURLWithPath: arguments[2])
    let paths = try String(contentsOf: listURL, encoding: .utf8)
        .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    let directory = MLModelConfigurationUtils.defaultModelsDirectory(
        for: Repo.cohereTranscribeCoreml
    )
    let loadStart = Date()
    let models = try await CoherePipeline.loadModels(
        encoderDir: directory,
        decoderDir: directory,
        vocabDir: directory
    )
    let pipeline = CoherePipeline()
    let converter = AudioConverter()
    FileHandle.standardError.write(
        "loaded cohere in \(String(format: "%.1f", Date().timeIntervalSince(loadStart)))s\n"
            .data(using: .utf8)!
    )
    // Warm up on the first file so compilation is not charged to timing.
    if let first = paths.first {
        _ = try? await pipeline.transcribeLong(
            audio: try converter.resampleAudioFile(URL(fileURLWithPath: first)),
            models: models
        )
    }
    struct CohereRow: Encodable {
        let id: String
        let text: String
        let seconds: Double
    }
    let encoder = JSONEncoder()
    for path in paths {
        let url = URL(fileURLWithPath: path)
        let samples = try converter.resampleAudioFile(url)
        let started = Date()
        let result = try await pipeline.transcribeLong(audio: samples, models: models)
        let row = CohereRow(
            id: url.deletingPathExtension().lastPathComponent,
            text: result.text,
            seconds: Date().timeIntervalSince(started)
        )
        FileHandle.standardOutput.write(try encoder.encode(row))
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
    exit(0)
}

guard arguments.count == 3 else {
    fail("usage: parakeet-benchmark <v2|v3|tdtCtc110m> <wav-list>")
}

let versionName = arguments[1]
let version = parseVersion(versionName)

let listURL = URL(fileURLWithPath: arguments[2])
let paths = try String(contentsOf: listURL, encoding: .utf8)
    .split(separator: "\n")
    .map(String.init)
    .filter { !$0.isEmpty }

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

struct Row: Encodable {
    let id: String
    let text: String
    let seconds: Double
}

// Declared at file scope so its locals are nonisolated; top-level code in
// main.swift is @MainActor, which cannot pass `inout` state to an actor.
func run(version: AsrModelVersion, versionName: String, paths: [String]) async throws {
let loadStart = Date()
let models = try await AsrModels.downloadAndLoad(version: version)
let manager = AsrManager(config: .default)
try await manager.loadModels(models)
log("loaded \(versionName) in \(String(format: "%.2f", Date().timeIntervalSince(loadStart)))s")

let layers = await manager.decoderLayerCount
var decoderState = try TdtDecoderState(decoderLayers: layers)

// Warm-up: the first passes pay ANE compilation and cache costs that a running
// app pays once at launch, not once per dictation.
if let first = paths.first {
    for _ in 0..<2 {
        decoderState = try TdtDecoderState(decoderLayers: layers)
        _ = try await manager.transcribe(URL(fileURLWithPath: first), decoderState: &decoderState)
    }
    log("warmed up")
}

let encoder = JSONEncoder()

for path in paths {
    let url = URL(fileURLWithPath: path)
    decoderState = try TdtDecoderState(decoderLayers: layers)
    let started = Date()
    let result = try await manager.transcribe(url, decoderState: &decoderState)
    let elapsed = Date().timeIntervalSince(started)
    let row = Row(
        id: url.deletingPathExtension().lastPathComponent,
        text: result.text,
        seconds: elapsed
    )
    FileHandle.standardOutput.write(try encoder.encode(row))
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

await manager.cleanup()
}

try await run(version: version, versionName: versionName, paths: paths)
