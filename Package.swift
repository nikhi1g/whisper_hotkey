// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "whisper_hotkey",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperHotkeyCore", targets: ["WhisperHotkeyCore"]),
        .library(name: "WhisperHotkeyASR", targets: ["WhisperHotkeyASR"]),
        .library(name: "WhisperHotkeySystem", targets: ["WhisperHotkeySystem"]),
        .library(name: "WhisperHotkeyShell", targets: ["WhisperHotkeyShell"]),
        .executable(name: "WhisperHotkeyApp", targets: ["WhisperHotkeyApp"]),
        .executable(name: "whisper_hotkey", targets: ["whisper_hotkey"]),
        .executable(name: "WhisperModelHelper", targets: ["WhisperModelHelper"]),
    ],
    targets: [
        .target(name: "WhisperHotkeyCore"),
        .target(
            name: "WhisperHotkeyASR",
            dependencies: ["WhisperHotkeyCore"]
        ),
        .target(
            name: "WhisperHotkeySystem",
            dependencies: ["WhisperHotkeyCore"]
        ),
        .target(
            name: "WhisperHotkeyShell",
            dependencies: ["WhisperHotkeyCore", "WhisperHotkeySystem"]
        ),
        .executableTarget(
            name: "WhisperHotkeyApp",
            dependencies: [
                "WhisperHotkeyCore",
                "WhisperHotkeyASR",
                "WhisperHotkeySystem",
                "WhisperHotkeyShell",
            ]
        ),
        .executableTarget(
            name: "whisper_hotkey",
            dependencies: ["WhisperHotkeyCore"]
        ),
        .executableTarget(
            name: "WhisperModelHelper",
            path: "Sources/WhisperModelHelper",
            cxxSettings: [
                .unsafeFlags(["-I/opt/homebrew/opt/whisper-cpp/include"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L/opt/homebrew/opt/whisper-cpp/lib",
                    "-lwhisper",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/opt/homebrew/opt/whisper-cpp/lib",
                ]),
            ]
        ),
        .testTarget(
            name: "WhisperHotkeyCoreTests",
            dependencies: ["WhisperHotkeyCore"]
        ),
        .testTarget(
            name: "WhisperHotkeyASRTests",
            dependencies: ["WhisperHotkeyASR", "WhisperHotkeyCore"]
        ),
        .testTarget(
            name: "WhisperHotkeySystemTests",
            dependencies: ["WhisperHotkeySystem", "WhisperHotkeyCore"]
        ),
        .testTarget(
            name: "WhisperHotkeyShellTests",
            dependencies: ["WhisperHotkeyShell", "WhisperHotkeyCore"]
        ),
    ]
)
