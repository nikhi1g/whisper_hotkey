import Foundation
import XCTest

final class CLIParsingTests: XCTestCase {
    func testHelpListsEverySupportedLiteralCommand() throws {
        let result = try runCLI(["--help"])

        XCTAssertEqual(result.status, 0)
        for command in [
            "start",
            "stop",
            "restart",
            "status",
            "cancel",
            "setup",
            "enable-login",
            "disable-login",
            "logs",
        ] {
            XCTAssertTrue(result.standardOutput.contains(command), "Missing \(command)")
        }
        XCTAssertTrue(result.standardError.isEmpty)
    }

    func testMissingAndExtraArgumentsAreUsageErrors() throws {
        let missing = try runCLI([])
        XCTAssertEqual(missing.status, 64)
        XCTAssertTrue(missing.standardError.contains("Missing command."))

        let unknown = try runCLI(["transcribe"])
        XCTAssertEqual(unknown.status, 64)
        XCTAssertTrue(unknown.standardError.contains("Unknown command: transcribe"))

        let extra = try runCLI(["status", "extra"])
        XCTAssertEqual(extra.status, 64)
        XCTAssertTrue(extra.standardError.contains("Unexpected arguments: extra"))
    }

    private func runCLI(_ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = try controllerExecutable()
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            standardOutput: String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            standardError: String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }

    private func controllerExecutable() throws -> URL {
        let roots = [
            Bundle(for: Self.self).bundleURL,
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
        ]

        for initialRoot in roots {
            var root = initialRoot
            for _ in 0..<8 {
                let candidate = root.appendingPathComponent("whisper_hotkey")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
                root.deleteLastPathComponent()
            }
        }
        throw XCTSkip("Build the whisper_hotkey target before running shell tests.")
    }

    private struct Result {
        let status: Int32
        let standardOutput: String
        let standardError: String
    }
}
