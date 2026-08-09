# Formatting benchmark

`check_lexical_invariance.py` is a model-free safety benchmark for formatter
candidates.  Feed it JSONL rows containing an utterance identifier plus
`before` and `after` strings:

```sh
python3 Benchmarks/Formatting/check_lexical_invariance.py candidates.jsonl
```

The output contains only aggregate case counts and the lexical mutation count.
The promotion gate is `lexical_mutations == 0`; punctuation and capitalization
quality must be measured separately against a licensed, frozen punctuation
corpus.  No external punctuation model is wired into the application until a
benchmark demonstrates a bounded gain without lexical mutations.
