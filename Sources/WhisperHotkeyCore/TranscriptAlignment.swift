import Foundation

public enum WordAlignmentError: Error, Equatable, Sendable {
    case problemTooLarge(cells: Int, maximum: Int)
}

public enum AlignmentOperation: Hashable, Sendable {
    case match(String)
    case substitute(reference: String, hypothesis: String)
    case delete(String)
    case insert(String)
}

public struct AlignmentResult: Hashable, Sendable {
    public let distance: Int
    public let operations: [AlignmentOperation]

    public init(distance: Int, operations: [AlignmentOperation]) {
        self.distance = distance
        self.operations = operations
    }
}

public enum WordAlignment: Equatable, Sendable {
    public static func distance(_ lhs: [String], _ rhs: [String]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        let short: [String]
        let long: [String]

        if lhs.count <= rhs.count {
            short = lhs
            long = rhs
        } else {
            short = rhs
            long = lhs
        }

        var previous = Array(0...short.count)
        var current = Array(repeating: 0, count: short.count + 1)

        for (i, longToken) in long.enumerated() {
            current[0] = i + 1
            for (j, shortToken) in short.enumerated() {
                let substitution = previous[j] + (longToken == shortToken ? 0 : 1)
                let insertion = current[j] + 1
                let deletion = previous[j + 1] + 1
                current[j + 1] = min(substitution, insertion, deletion)
            }
            swap(&previous, &current)
        }
        return previous[short.count]
    }

    public static func align(
        reference: [String],
        hypothesis: [String],
        maximumCells: Int = 1_000_000
    ) throws -> AlignmentResult {
        let rows = reference.count + 1
        let columns = hypothesis.count + 1
        let cells = rows * columns
        guard cells <= maximumCells else {
            throw WordAlignmentError.problemTooLarge(
                cells: cells,
                maximum: maximumCells
            )
        }

        var matrix = Array(
            repeating: Array(repeating: 0, count: columns),
            count: rows
        )

        for i in 0..<rows { matrix[i][0] = i }
        for j in 0..<columns { matrix[0][j] = j }

        if reference.count > 0 && hypothesis.count > 0 {
            for i in 1..<rows {
                for j in 1..<columns {
                    let substitution = matrix[i - 1][j - 1]
                        + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1)
                    matrix[i][j] = min(
                        substitution,
                        matrix[i - 1][j] + 1,
                        matrix[i][j - 1] + 1
                    )
                }
            }
        }

        var operations: [AlignmentOperation] = []
        var i = reference.count
        var j = hypothesis.count
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let equal = reference[i - 1] == hypothesis[j - 1]
                let diagonal = matrix[i - 1][j - 1] + (equal ? 0 : 1)
                if matrix[i][j] == diagonal {
                    operations.append(
                        equal
                            ? .match(reference[i - 1])
                            : .substitute(
                                reference: reference[i - 1],
                                hypothesis: hypothesis[j - 1]
                            )
                    )
                    i -= 1
                    j -= 1
                    continue
                }
            }
            if i > 0, matrix[i][j] == matrix[i - 1][j] + 1 {
                operations.append(.delete(reference[i - 1]))
                i -= 1
            } else if j > 0 {
                operations.append(.insert(hypothesis[j - 1]))
                j -= 1
            }
        }
        operations.reverse()

        return AlignmentResult(
            distance: matrix[reference.count][hypothesis.count],
            operations: operations
        )
    }
}

public enum TranscriptAlignment {
    public static func lexicalTokens(from text: String) -> [String] {
        var normalized: [String] = []
        var current = ""

        for scalar in text.lowercased().unicodeScalars {
            let character = Character(scalar)
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if character == "'" || character == "’" {
                current.append("'")
            } else if !current.isEmpty {
                normalized.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            normalized.append(current)
        }
        return normalized
    }
}
