#!/usr/bin/env python3
"""Frozen English benchmark normalization.

This module is deliberately dependency-free and is part of the benchmark
contract.  Keep ``NORMALIZATION_VERSION`` and this implementation unchanged
for a frozen comparison.  A caller that needs a new policy must publish a new
version instead of changing this one after looking at test outcomes.
"""

from __future__ import annotations

import hashlib
import re
import unicodedata
from pathlib import Path


NORMALIZATION_VERSION = "whisper-hotkey-wer-normalization-v1"

# Unicode letters and numbers, with apostrophes retained inside contractions.
WORD_RE = re.compile(r"[^\W_]+(?:['’][^\W_]+)?", re.UNICODE)
DISPLAY_RE = re.compile(
    r"[^\W_]+(?:['’][^\W_]+)?|[^\s\w]",
    re.UNICODE,
)
PUNCTUATION = frozenset(".,?!:;")
BOUNDARY_MARKS = frozenset(".?!")


def canonical_text(text: str) -> str:
    """Apply the frozen Unicode and apostrophe policy."""

    if not isinstance(text, str):
        raise TypeError("benchmark text must be a string")
    return unicodedata.normalize("NFKC", text).replace("’", "'")


def normalize_word(word: str) -> str:
    """Return one case-insensitive lexical token."""

    value = canonical_text(word).casefold()
    return value.strip("'")


def normalize_text(text: str) -> list[str]:
    """Return punctuation-independent lexical tokens.

    Punctuation is removed, casing is folded, and written versus spoken
    numbers are intentionally *not* rewritten.  This prevents the normalizer
    from giving one recognizer a model-specific number advantage.
    """

    return [normalize_word(token) for token in WORD_RE.findall(canonical_text(text))]


def display_units(text: str) -> list[str]:
    """Return case- and formatting-sensitive words/punctuation units."""

    return DISPLAY_RE.findall(canonical_text(text))


def display_words(text: str) -> list[str]:
    """Return display words while preserving case but ignoring punctuation."""

    return [
        token
        for token in DISPLAY_RE.findall(canonical_text(text))
        if any(char.isalnum() for char in token)
    ]


def normalized_characters(text: str) -> list[str]:
    """Return normalized characters with single spaces between lexical words."""

    return list(" ".join(normalize_text(text)))


def punctuation_by_word(text: str) -> list[tuple[int, str]]:
    """Return ``(zero-based word index, mark)`` punctuation events."""

    events: list[tuple[int, str]] = []
    word_index = -1
    for token in DISPLAY_RE.findall(canonical_text(text)):
        if token in PUNCTUATION:
            if word_index >= 0:
                events.append((word_index, token))
        else:
            word_index += 1
    return events


def boundary_positions(text: str) -> list[int]:
    """Return lexical word positions followed by sentence-boundary marks."""

    return [index for index, mark in punctuation_by_word(text) if mark in BOUNDARY_MARKS]


def capitalization_labels(text: str) -> list[bool]:
    """Return whether each display word starts with an uppercase letter."""

    labels: list[bool] = []
    for token in display_words(text):
        first = next((char for char in token if char.isalpha()), "")
        labels.append(bool(first) and first.isupper())
    return labels


def normalization_sha256() -> str:
    """Hash this frozen implementation for inclusion in every report."""

    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
