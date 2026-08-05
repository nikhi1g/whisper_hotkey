// swift-tools-version: 6.0

import PackageDescription

let whisperPrefix = Context.environment["WHISPER_CPP_PREFIX"]
    ?? "/opt/homebrew/opt/whisper-cpp"
let ggmlPrefix = Context.environment["GGML_PREFIX"]
    ?? "/opt/homebrew/opt/ggml"

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
        .executable(
            name: "WhisperHotkeyLoginLauncher",
            targets: ["WhisperHotkeyLoginLauncher"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            revision: "8fcbfed028415b0b90f0f10ee7b0303c53b600a0"
        ),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.5"
        ),
    ],
    targets: [
        .target(name: "WhisperHotkeyCore"),
        .target(
            name: "WhisperHotkeyASR",
            dependencies: [
                "WhisperHotkeyCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
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
            name: "WhisperHotkeyLoginLauncher",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/WhisperHotkeyLoginLauncher/Info.plist",
                ]),
            ]
        ),
        .executableTarget(
            name: "WhisperModelHelper",
            path: "Sources/WhisperModelHelper",
            cxxSettings: [
                .unsafeFlags([
                    "-I\(whisperPrefix)/include",
                    "-I\(ggmlPrefix)/include",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(whisperPrefix)/lib",
                    "-L\(ggmlPrefix)/lib",
                    "-lwhisper",
                    "-lggml",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "\(whisperPrefix)/lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "\(ggmlPrefix)/lib",
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
