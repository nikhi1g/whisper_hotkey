import Foundation

public struct TokenOverlapResult: Equatable, Sendable {
    public let merged: [String]
    public let overlapCount: Int

    public init(merged: [String], overlapCount: Int) {
        self.merged = merged
        self.overlapCount = overlapCount
    }
}

public enum TokenOverlap {
    public static func merge(
        left: [String],
        right: [String],
        maximumOverlap: Int = 32
    ) -> TokenOverlapResult {
        precondition(maximumOverlap >= 0)
        let limit = min(maximumOverlap, left.count, right.count)
        var overlap = 0
        if limit > 0 {
            for count in stride(from: limit, through: 1, by: -1) {
                if left.suffix(count).elementsEqual(right.prefix(count)) {
                    overlap = count
                    break
                }
            }
        }
        return TokenOverlapResult(
            merged: left + right.dropFirst(overlap),
            overlapCount: overlap
        )
    }
}
