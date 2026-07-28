import Darwin
import Foundation
import XCTest
import WhisperHotkeyCore
@testable import WhisperHotkeyShell

final class ControlTransportTests: XCTestCase {
    func testJSONLineRoundTripUsesPrivateSocketAndCleansUp() throws {
        let directory = temporaryDirectory()
        let socketURL = directory.appendingPathComponent("control.sock")
        let expectedStatus = RuntimeStatus(
            running: true,
            phase: .listening,
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true,
            loginItemEnabled: true,
            helperAvailable: true,
            modelAvailable: true,
            clipboardLeaseActive: false
        )
        let server = ControlServer(socketURL: socketURL) { request in
            XCTAssertEqual(request.command, .status)
            return ControlResponse(ok: true, message: "Running.", status: expectedStatus)
        }

        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try server.start()
        let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        let response = try ControlClient(socketURL: socketURL).send(.status)
        XCTAssertEqual(response, ControlResponse(ok: true, message: "Running.", status: expectedStatus))

        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
        XCTAssertFalse(server.isRunning)
    }

    func testSecondServerDoesNotReplaceActiveSocket() throws {
        let directory = temporaryDirectory()
        let socketURL = directory.appendingPathComponent("control.sock")
        let first = ControlServer(socketURL: socketURL) { _ in
            ControlResponse(ok: true, message: "first")
        }
        let second = ControlServer(socketURL: socketURL) { _ in
            ControlResponse(ok: true, message: "second")
        }

        defer {
            second.stop()
            first.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try first.start()
        XCTAssertThrowsError(try second.start()) { error in
            guard case ControlTransportError.alreadyRunning = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try ControlClient(socketURL: socketURL).send(.cancel).message, "first")
    }

    func testStartRemovesAStaleSocketNode() throws {
        let directory = temporaryDirectory()
        let socketURL = directory.appendingPathComponent("control.sock")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try createStaleSocket(at: socketURL)
        let server = ControlServer(socketURL: socketURL) { request in
            ControlResponse(ok: request.command == .status, message: "fresh")
        }

        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try server.start()
        XCTAssertEqual(try ControlClient(socketURL: socketURL).send(.status).message, "fresh")
    }

    private func temporaryDirectory() -> URL {
        URL(
            fileURLWithPath: "/private/tmp/wh-shell-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
    }

    private func createStaleSocket(at url: URL) throws {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(.ENOTSOCK)
        }
        defer {
            Darwin.close(descriptor)
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(url.path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: bytes)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
