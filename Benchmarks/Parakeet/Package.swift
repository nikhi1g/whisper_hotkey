// swift-tools-version: 6.0
import PackageDescription

// Kept separate from the app package so the benchmark never links into a
// shipped bundle. FluidAudio is pinned to the same version the app uses.
let package = Package(
    name: "parakeet-benchmark",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.5"
        ),
    ],
    targets: [
        .executableTarget(
            name: "parakeet-benchmark",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ]
)
