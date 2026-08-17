import Foundation

public enum DictationEvent: Equatable, Sendable {
    case hotkeyPressed(at: TimeInterval)
    case captureStarted
    case hotkeyReleased(at: TimeInterval)
    case maximumDurationReached
    case cancel
    case transcriptReady
    case processingRequested
    case reviewAccepted
    case reviewCancelled
    case deliveryFinished
    case chunkedSessionFinished
    case failed(String)
    case cancellationPresentationFinished
    case errorPresentationFinished
}

public enum DictationEffect: Equatable, Sendable {
    case beginSession
    case finalizeRecording
    case cancelSession
    case deliverTranscript
    case requestProcessing
    case showReview(PostProcessPreview)
    case showBadge(BadgePresentation)
}

public struct DictationStateMachine: Equatable, Sendable {
    public private(set) var phase: DictationPhase = .idle
    public private(set) var pressedAt: TimeInterval?
    public private(set) var lastError: String?
    public let minimumHoldDuration: TimeInterval

    public init(minimumHoldDuration: TimeInterval = 0.250) {
        self.minimumHoldDuration = minimumHoldDuration
    }

    @discardableResult
    public mutating func handle(_ event: DictationEvent) -> [DictationEffect] {
        switch event {
        case .hotkeyPressed(let timestamp):
            guard !phase.isBusy else {
                return [.showBadge(.busy)]
            }
            guard phase != .failed else {
                return [.showBadge(.busy)]
            }
            pressedAt = timestamp
            lastError = nil
            phase = .preparing
            return [.beginSession, .showBadge(.listening)]

        case .captureStarted:
            guard phase == .preparing else { return [] }
            phase = .listening
            return []

        case .hotkeyReleased(let timestamp):
            guard phase == .preparing || phase == .listening,
                  let pressedAt else {
                return []
            }
            self.pressedAt = nil
            guard timestamp - pressedAt >= minimumHoldDuration else {
                phase = .idle
                return [.cancelSession, .showBadge(.hidden)]
            }
            phase = .transcribing
            return [.finalizeRecording, .showBadge(.transcribing)]

        case .maximumDurationReached:
            guard phase == .preparing || phase == .listening else { return [] }
            pressedAt = nil
            phase = .transcribing
            return [.finalizeRecording, .showBadge(.transcribing)]

        case .cancel:
            guard phase.isBusy else { return [] }
            pressedAt = nil
            phase = .cancelled
            return [.cancelSession, .showBadge(.hidden)]

        case .transcriptReady:
            guard phase == .transcribing else { return [] }
            phase = .inserting
            return [.deliverTranscript]

        case .processingRequested:
            guard phase == .transcribing else { return [] }
            phase = .reviewing
            return [.requestProcessing]

        case .reviewAccepted:
            guard phase == .reviewing else { return [] }
            phase = .inserting
            return [.deliverTranscript]

        case .reviewCancelled:
            guard phase == .reviewing else { return [] }
            phase = .cancelled
            return [.cancelSession, .showBadge(.hidden)]

        case .deliveryFinished:
            guard phase == .inserting else { return [] }
            phase = .idle
            return [.showBadge(.hidden)]

        case .chunkedSessionFinished:
            guard phase == .transcribing else { return [] }
            phase = .idle
            return [.showBadge(.hidden)]

        case .failed(let message):
            guard phase.isBusy else { return [] }
            pressedAt = nil
            lastError = message
            phase = .failed
            return [.cancelSession, .showBadge(.error(message))]

        case .cancellationPresentationFinished:
            guard phase == .cancelled else { return [] }
            phase = .idle
            return [.showBadge(.hidden)]

        case .errorPresentationFinished:
            guard phase == .failed else { return [] }
            phase = .idle
            return [.showBadge(.hidden)]
        }
    }
}
