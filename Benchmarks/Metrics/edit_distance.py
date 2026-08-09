#!/usr/bin/env python3
"""Deterministic Levenshtein alignment used by all benchmark metrics."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


@dataclass(frozen=True)
class EditCounts:
    substitutions: int
    deletions: int
    insertions: int

    @property
    def errors(self) -> int:
        return self.substitutions + self.deletions + self.insertions


@dataclass(frozen=True)
class AlignmentStep:
    operation: str
    reference: str | None
    hypothesis: str | None


def align(reference: Sequence[str], hypothesis: Sequence[str]) -> list[AlignmentStep]:
    """Return a deterministic minimum-cost alignment.

    Ties prefer a match, substitution, deletion, then insertion.  The order
    is part of the frozen scoring policy so confidence and formatting slices do
    not depend on dictionary or platform iteration order.
    """

    rows = len(reference)
    columns = len(hypothesis)
    costs = [[0] * (columns + 1) for _ in range(rows + 1)]
    operations: list[list[str | None]] = [[None] * (columns + 1) for _ in range(rows + 1)]

    for row in range(1, rows + 1):
        costs[row][0] = row
        operations[row][0] = "delete"
    for column in range(1, columns + 1):
        costs[0][column] = column
        operations[0][column] = "insert"

    for row in range(1, rows + 1):
        for column in range(1, columns + 1):
            if reference[row - 1] == hypothesis[column - 1]:
                costs[row][column] = costs[row - 1][column - 1]
                operations[row][column] = "equal"
                continue

            candidates = [
                (costs[row - 1][column - 1] + 1, 0, "substitute"),
                (costs[row - 1][column] + 1, 1, "delete"),
                (costs[row][column - 1] + 1, 2, "insert"),
            ]
            cost, _, operation = min(candidates)
            costs[row][column] = cost
            operations[row][column] = operation

    result: list[AlignmentStep] = []
    row, column = rows, columns
    while row or column:
        operation = operations[row][column]
        if operation == "equal":
            result.append(AlignmentStep("equal", reference[row - 1], hypothesis[column - 1]))
            row -= 1
            column -= 1
        elif operation == "substitute":
            result.append(AlignmentStep("substitute", reference[row - 1], hypothesis[column - 1]))
            row -= 1
            column -= 1
        elif operation == "delete":
            result.append(AlignmentStep("delete", reference[row - 1], None))
            row -= 1
        elif operation == "insert":
            result.append(AlignmentStep("insert", None, hypothesis[column - 1]))
            column -= 1
        else:  # pragma: no cover - defensive guard for an impossible matrix state.
            raise RuntimeError("incomplete benchmark alignment")
    result.reverse()
    return result


def edit_counts(reference: Sequence[str], hypothesis: Sequence[str]) -> EditCounts:
    counts = {"substitute": 0, "delete": 0, "insert": 0}
    for step in align(reference, hypothesis):
        if step.operation in counts:
            counts[step.operation] += 1
    return EditCounts(
        substitutions=counts["substitute"],
        deletions=counts["delete"],
        insertions=counts["insert"],
    )
