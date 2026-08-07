import Foundation

public enum StablePrefix {
    public static func commonPrefix(_ hypotheses: [[String]]) -> [String] {
        guard let first = hypotheses.first, !hypotheses.isEmpty else {
            return []
        }
        let limit = hypotheses.dropFirst().reduce(first.count) {
            min($0, $1.count)
        }
        var count = 0
        while count < limit {
            let candidate = first[count]
            if hypotheses.dropFirst().contains(where: { $0[count] != candidate }) {
                break
            }
            count += 1
        }
        return Array(first.prefix(count))
    }

    public static func resolve(
        observations: [String],
        preserveTrailingToken: Bool = true
    ) -> (stable: [String], unresolved: [String]) {
        let observationsTokens = observations.map { text in
            TranscriptAlignment.lexicalTokens(from: text)
        }
        guard let latest = observationsTokens.last else {
            return ([], [])
        }
        var stable = commonPrefix(observationsTokens)
        if preserveTrailingToken,
           !stable.isEmpty,
           stable.count == latest.count {
            _ = stable.popLast()
        }
        return (stable, Array(latest.dropFirst(stable.count)))
    }
}
