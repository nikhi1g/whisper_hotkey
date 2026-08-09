# Reusable diagrams

## User-to-product learning loop

```mermaid
flowchart LR
    A["Choose one high-frequency user job"] --> B["Recruit a small representative cohort"]
    B --> C["Observe install and supplied tasks"]
    C --> D["Collect de-identified outcomes, not dictation content"]
    D --> E["Reproduce and rank one problem"]
    E --> F["Make one bounded product change"]
    F --> G["Repeat the same task on the same cohort"]
    G --> H{"Metric and retention improve?"}
    H -->|Yes| I["Publish evidence and expand carefully"]
    H -->|No| J["Revisit the problem or segment"]
    I --> A
    J --> A
```

## Privacy boundary

```mermaid
flowchart LR
    K["Physical hotkey edge"] --> C["Private microphone capture"]
    C --> Q["Bounded ordered PCM queue"]
    Q --> L["Local conversion and temporary audio"]
    L --> M["Selected local Parakeet or Whisper model"]
    M --> T["Release-time target field"]
    L --> X["Delete on completion, cancel, failure, or exit"]

    U["Explicit manual or opt-in launch update check"] -. "release metadata only" .-> GH["GitHub Releases"]

    subgraph MAC["User's Mac"]
        K
        C
        Q
        L
        M
        T
        X
        U
    end
```

The dotted update path is separate from dictation. Verify exact behavior for
the release before publishing this diagram.

## Activation funnel

```mermaid
flowchart TD
    V["Relevant visitor"] --> D["Chooses the ZIP"]
    D --> G["Passes Gatekeeper / Open Anyway"]
    G --> P["Understands and grants 3 permissions"]
    P --> F["Completes first supplied dictation"]
    F --> W["Uses it in 3 real work sessions"]
    W --> R["Returns in week 4"]

    G -. "largest current trust risk" .-> N["Future Developer ID + notarization decision"]
```

## Evidence before claims

```mermaid
flowchart LR
    A["Architecture"] --> B["Deterministic lab test"]
    B --> C["Representative cohort"]
    C --> D["Paired competitor comparison"]
    D --> E["Qualified public claim"]

    A -.-> A1["Designed to capture first"]
    B -.-> B1["Measured on named hardware"]
    C -.-> C1["Observed across N users and trials"]
    D -.-> D1["Difference plus confidence interval"]
```

## Positioning map

| | Focused dictation | Broad workspace/agent suite |
| --- | --- | --- |
| **Local and verifiable by default** | Target: `whisper_hotkey`; literal, ephemeral, measured | Pindrop, MacParakeet, OpenWhispr local modes |
| **Cloud or hybrid** | Aqua, Wispr Flow, parts of Superwhisper/Spokenly | Meeting, note, and agent platforms |

The map is a strategic simplification, not a claim that competitors fit only
one cell.
