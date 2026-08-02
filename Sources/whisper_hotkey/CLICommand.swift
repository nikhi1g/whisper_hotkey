import Foundation
import WhisperHotkeyCore

enum CLICommand: Equatable {
    case start
    case restart
    case verifySetup
    case control(ControlCommand)
    case logs
    case help
}

enum CLIParseError: Error, Equatable {
    case missingCommand
    case unknownCommand(String)
    case unexpectedArguments([String])
}

enum CLICommandParser {
    static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let first = arguments.first else {
            throw CLIParseError.missingCommand
        }
        guard arguments.count == 1 else {
            throw CLIParseError.unexpectedArguments(Array(arguments.dropFirst()))
        }

        switch first {
        case "start":
            return .start
        case "restart":
            return .restart
        case "verify-setup":
            return .verifySetup
        case "logs":
            return .logs
        case "help", "-h", "--help":
            return .help
        default:
            if let command = ControlCommand(rawValue: first) {
                return .control(command)
            }
            throw CLIParseError.unknownCommand(first)
        }
    }
}
