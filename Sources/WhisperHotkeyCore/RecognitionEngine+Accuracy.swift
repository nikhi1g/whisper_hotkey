import Foundation

public extension RecognitionEngine {
    var primaryCandidateEngineID: RecognitionEngineID {
        switch self {
        case .whisperCppMetal:
            .whisperTurbo
        case .parakeetCoreML:
            .parakeetTDTCoreML
        }
    }
}

public extension ParakeetVariant {
    var candidateEngineID: RecognitionEngineID {
        switch self {
        case .unified:
            .parakeetUnifiedCoreML
        default:
            .parakeetTDTCoreML
        }
    }
}
