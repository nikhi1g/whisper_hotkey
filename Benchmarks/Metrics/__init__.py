"""Privacy-preserving, deterministic benchmark scoring helpers.

The package accepts transcript text only as an ephemeral scoring input.  Its
reporting functions return utterance identifiers and numeric measurements, not
audio or transcript text.
"""

from .normalization import NORMALIZATION_VERSION, normalization_sha256
from .scoring import score_rows

__all__ = [
    "NORMALIZATION_VERSION",
    "normalization_sha256",
    "score_rows",
]
