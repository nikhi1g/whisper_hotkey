import Foundation
import FluidAudio

// Usage: parabench <v2|v3|tdtCtc110m> <wav-list-file>
// Emits one JSON object per line: {"id":..., "text":..., "seconds":...}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: parabench <v2|v3|tdtCtc110m> <wav-list>\n".data(using: .utf8)!)
    exit(2)
}

let versionName = arguments[1]
let version: AsrModelVersion
switch versionName {
case "v2": version = .v2
case "v3": version = .v3
case "tdtCtc110m": version = .tdtCtc110m
default:
    FileHandle.standardError.write("unknown version \(versionName)\n".data(using: .utf8)!)
    exit(2)
}

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
