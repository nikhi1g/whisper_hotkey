import Foundation

public enum WhisperASRError: LocalizedError, Equatable, Sendable {
    case microphoneUnavailable
    case captureFailed(String)
    case noActiveRecording
    case modelMissing(String)
    case helperUnavailable
    case commandLineUnavailable
    case helperProtocolFailure
    case helperFailed(String)
    case recognitionTimedOut
    case commandLineFailed(Int32)
    case noSpeech
    case parakeetInstallFailed(String)

    public var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            "The current microphone did not provide a usable audio format."
        case .captureFailed(let detail):
            "Could not capture dictation audio: \(detail)"
        case .noActiveRecording:
            "There is no active dictation recording."
        case .modelMissing(let path):
            "The installed Base English Whisper model was not found at \(path)."
        case .helperUnavailable:
            "The local Whisper model helper is unavailable."
        case .commandLineUnavailable:
            "The local whisper-cli fallback is unavailable."
        case .helperProtocolFailure:
            "The local Whisper helper returned an invalid response."
        case .helperFailed(let reason):
            "The local Whisper helper failed: \(reason)"
        case .recognitionTimedOut:
            "Local Whisper transcription timed out."
        case .commandLineFailed(let status):
            "Local whisper-cli failed with status \(status)."
        case .noSpeech:
            "No speech was detected."
        case .parakeetInstallFailed(let reason):
            "Parakeet download failed: \(reason)"
        }
    }
}
