# Book/ Agent Instructions

## Product purpose and app relationship

Read [`purpose.md`](purpose.md) before changing either native application. It is
the product contract for how the two apps relate:

- macOS BookCLI is the authoritative, fully featured application and owns the
  catalog, shelves, files, downloads, Librarian, reader defaults, and management
  workflows.
- BookCLI Mobile is a reduced away-from-desk companion containing Library,
  Reader, and compact Settings only. Do not add Librarian, acquisition, shelf
  mutation, or a full-library mirror to iOS.
- Mobile follows the Mac's visual theme and reader defaults by default, with an
  explicit persistent device-local override. Preserve continuous vertical EPUB
  scrolling, chapter navigation, shelf browsing, progress sync, and on-demand
  bounded book caching.
- Enforce locality: offline Library views contain only fully downloaded books,
  which remain readable across cold launches. Never require a connection to
  display cached content, and never retain remote-only entries while offline.
- New mobile functionality should directly support selecting, reading, or
  synchronizing a few books. Keep the Mac implementation primary and the phone
  surface intentionally uncluttered.

## Structure
This repository contains the library plus its applications. Python sources live
under `src/bookcli/`, native apps under `apps/`, tests under `tests/`, maintenance
commands under `tools/`, and documentation under `docs/`. Physical book files
live under `library/shelves/`, mutable databases and caches under
`library/state/`, and generated catalog projections under `library/exports/`.
Stable catalog identities remain `shelf/filename`; they do not include the
physical `library/shelves/` prefix. Root control files are `AGENTS.md`,
`shelves.toml`, `pyproject.toml`, and `.gitignore`.
macOS system files (`.DS_Store`, `Icon`) are tolerated but not tracked.

### Shelves
Shelf descriptions, keyword rules, and tie-break priority live in `shelves.toml`;
`shelves.py` loads that config and exposes the existing `SHELVES`,
`SHELF_KEYWORDS`, and `SHELF_PRIORITY` constants for code compatibility.

- `library/shelves/csbooks/` — Computer science: programming, systems, algorithms, compilers, databases
- `aibooks/` — Artificial intelligence, machine learning, and AI-adjacent texts
- `reference/` — Textbooks, technical references, reading lists, and academic reference material
- `microbiology/` — Microbiology, virology, pathogens, and viral vectors
- `biology/` — Biology, genetics, evolution, ecology, and human origins
- `health-medicine/` — Health, medicine, aging, clinical decisions, sexuality, and drug development
- `physics/` — Physics, cosmology, complexity, and the nature of reality
- `psychology/` — Psychology, cognition, behavior, neuroscience, emotion, and social behavior
- `relationships/` — Dating, relationships, sexuality, mating strategy, and gender dynamics
- `communication/` — Communication, persuasion, negotiation, conversation, rhetoric, and speeches
- `strategy-power/` — Power, strategy, statecraft, conflict, dominance, and strategic influence
- `history-politics/` — History, politics, institutions, political thought, war history, and society
- `philosophy/` — Philosophy, ethics, social criticism, stoicism, existentialism, and metaphysics
- `spirituality/` — Spiritual practice, meditation, nonduality, religion, and direct realization
- `literature/` — Fiction, classic works, poetry
- `memoir/` — Memoirs and autobiographies
- `productivity/` — Productivity, focus, creativity, execution, process improvement, and skill work
- `habits/` — Habit formation, routines, behavior change, and small daily systems
- `performance/` — Performance, self-mastery, motivation, discipline, ambition, and life direction
- `mental-models/` — Mental models, decision-making, systems thinking, forecasting, and judgment
- `business/` — Business, entrepreneurship, company histories, management, and business memoirs
- `investing/` — Long-term investing, wealth, capital allocation, valuation, and money
- `trading/` — Markets, trading systems, technical analysis
- `privacy-security/` — Privacy, anonymity, operational security, and personal digital security
- `misc/` — Non-book files (images, etc.)

Note: the old broad shelves `science/` and `self-development/` were split into the
finer shelves above (2026-06-06). The former app-era shelves `business-finance/`,
`influence/`, `power/`, and `mindset/` were retired during the manual Codex pass
(2026-06-21). Don't recreate those retired shelves.

## Loose books in root
If any book file (epub, pdf) is found in the root, do NOT silently leave it there.
Ask the user: "Where should I shelve **<title>**? Suggested: `<best-guess shelf>/`"
Then move it and regenerate `library/exports/library.md`.

## Catalog (database is the source of truth)
- `library/state/library.sqlite3` — **the source of truth** for the book catalog (gitignored, not tracked). Built/maintained by `catalog_db.py`; reconciled with disk on every `scan_library()`.
- `library/exports/library.md` — **generated** human-readable projection (grouped by shelf, alphabetized). Do NOT hand-edit; it's overwritten by `library.export_catalog()`. Edits won't affect the catalog.
- `library/exports/catalog.jsonl` — **generated** lossless export, one record per book; used by `bookcli rebuild` to reconstruct the DB. Committed so the catalog is diffable in git.
- After catalog changes, exports regenerate automatically; `bookcli export` forces it, `bookcli rebuild` restores the DB from `library/exports/catalog.jsonl`.
- `wishlist.md` — a personal, hand-maintained file. The CLI does NOT read or write it.
- When answering what's owned, query the DB (`catalog_db.load_catalog()`) or read the generated `library/exports/library.md`.

## Searching and downloading books

Use the `bookcli` package for all search and download operations. No API key needed.

```bash
# Interactive live TUI (default): opens the Search view
PYTHONPATH=src python3 -m bookcli

# Same TUI, opens the Library view first
PYTHONPATH=src python3 -m bookcli --library

# Interactive: search, pick, download, shelve, update library.md + wishlist.md
PYTHONPATH=src python3 -m bookcli get "<title or author>"

# Search only (owned books are flagged ✓ with a ⌘-clickable path)
PYTHONPATH=src python3 -m bookcli search "<query>"

# Download by MD5
PYTHONPATH=src python3 -m bookcli download <md5>
```

`bookcli` and `bookcli --library` open the **same** unified TUI — press **Tab** to
switch between the Search view and the two-pane Library view (shelves | books)
within one session. `--library` only chooses which view opens first. The download
queue stays visible in both views, and books downloaded during the session appear
in the Library when you switch into it. Library keys: `←/→` shelf, `↑/↓` book,
`⏎` read/open, `/` filter, `:q`/`q` quit. `⏎` opens EPUB/PDF/DJVU books with the
local patched reader, preferring `BOOKCLI_READER`, then
`~/bin/bookokrat-bookcli`, then `/private/tmp/bookokrat-src/target/release/bookokrat`.
If that patched reader is unavailable or exits nonzero, bookcli falls back to
macOS `open`. Stock Homebrew `bookokrat` is intentionally not used automatically;
set `BOOKCLI_ALLOW_STOCK_BOOKOKRAT=1` only when you explicitly want stock
behavior. The `bookokrat-bookcli` local variant makes the reader's `← Books List`
item quit back to bookcli, matching `q`, while stock `bookokrat` keeps its own
internal book-list behavior. It also makes EPUB scroll as a continuous chapter
window: j/k, wheel, half-page, and page scrolling move through adjacent chapters
without the old boundary jump, while the active chapter is classified from the
visible rendered lines.

Search results that are already on a shelf are flagged green with `✓` and listed
below the table as ⌘-clickable `file://` links, so you can spot duplicates before
downloading. Ownership is detected by scanning the shelf files on disk.

New TUI/app downloads use the optional LLM librarian for auto-shelving.
`librarian.py` accepts provider-prefixed model IDs: `local:<served-name>` for
BookCLI's managed OpenAI-compatible MLX server, `mlx:<huggingface-repo>` for the
legacy direct MLX LM path, `cerebras:<model>` for Cerebras Cloud SDK, and
`ollama:<model>` or a plain model name for Ollama. The macOS app default is
`local:qwen3.5-9b-local` backed by
`mlx-community/Qwen3.5-9B-MLX-4bit`; the fast utility option is
`local:qwen3.5-0.8b-local` backed by
`mlx-community/Qwen3.5-0.8B-MLX-4bit`. The speed-first command option is
`local:qwen3-0.6b-local` backed by `mlx-community/Qwen3-0.6B-4bit`; it caps
responses at 512 tokens and uses Qwen3's native tool/reasoning parsers. The
managed lifecycle probes `/v1/models`,
reuses a compatible endpoint, serializes start races, never replaces an occupied
incompatible port, launches its own server tree in an isolated process group,
and stops only the complete tree BookCLI owns. The 9B model normally
uses port 8000, the 0.8B model port 8001, and the 0.6B model port 8002. Both chat and download classification
route through that shared endpoint, avoiding duplicate in-process weight loads.
Local OpenAI requests disable Qwen's hidden thinking through native chat-template
kwargs for low-latency UI responses while preserving structured tool calling.
For GUI launches, BookCLI prefers the MLX server runtime at
`~/Library/Application Support/BookCLI/mlx-runtime/`; this avoids macOS privacy
blocking a virtual environment inside an unrelated Desktop project. The model
weights remain in the single Hugging Face cache. If that managed runtime is not
installed, the existing `youtube-automations/.venv` executable remains the
compatibility fallback.
The picker also supports `cerebras:zai-glm-4.7`, `cerebras:gpt-oss-120b`, and
`cerebras:gemma-4-31b`. Cerebras requires
`cerebras-cloud-sdk`; the macOS app shows a Keychain-backed secure API-key field
when a `cerebras:` model is selected, and CLI use reads `CEREBRAS_API_KEY` or
`BOOKCLI_CEREBRAS_API_KEY`.
Never commit API keys. A manually selected backend is tried exactly as selected.
If it is missing, unavailable, or rejects its credential, the librarian reports a
model notice and falls back to the already-cached/running managed Qwen 3.5 9B;
automatic fallback never downloads weights. Classification uses deterministic
`suggest_shelf()` rules only when both model attempts fail. Ollama calls use
`BOOKCLI_OLLAMA_URL` (default `http://127.0.0.1:11434/api/chat`) and
`BOOKCLI_OLLAMA_MODEL` (default `gemma3:4b-it-qat`); if no Ollama API is already
listening, bookcli starts `ollama serve` on demand, waits briefly for readiness,
and stops only that owned child after the routed request completes. A manually
started Ollama server is reused and left running. The LLM
normally chooses the shelf; if it returns confidence below `0.35`, the book is
shelved to `misc/`. If the selected backend is unavailable or returns invalid
JSON/shelf data, the same selected-model → local-9B → deterministic chain is
used. The classifier
source/model/confidence/reason are persisted in the catalog DB and exported to
`catalog.jsonl`. For newly downloaded books, the classifier receives metadata plus
a compact parsed-text sample from the downloaded EPUB/PDF. MOBI/AZW3/FB2 downloads
are automatically converted to EPUB before shelving when Calibre's
`ebook-convert` is installed (`ebook-convert` on PATH or
`/Applications/calibre.app/Contents/MacOS/ebook-convert`); otherwise they are
shelved in their original format and opened through macOS `open`.

Local Library search uses two precomputed tiers: an in-memory posting/trigram
metadata index for immediate title/author/year/shelf/format matches, followed by
generation-guarded SQLite FTS5 results from `library/state/library.sqlite3`. The FTS
metadata table also indexes language, source ID, added date, and classifier
metadata; the body index stores at most 750k normalized characters per book,
sampled across long books. EPUB/PDF/DJVU/FB2 text is extracted directly and
MOBI/AZW3 uses Calibre when installed. Path/size/mtime/catalog/index-version
fingerprints make warming incremental; an index-version migration runs in the
background while existing postings remain searchable. Common-term and fuzzy
thresholds deliberately allow zero local matches, so unrelated queries can show
only online results.

The macOS app supports voice dictation in both the library search field and the
large Librarian composer. It records a private temporary 16 kHz
mono WAV, then runs local `whisper.cpp` with Metal acceleration (the audited defaults
are `/opt/homebrew/bin/whisper-cli` and
`~/.cache/whisper/ggml-small.en.bin`, with `ggml-base.en.bin` as a fallback). The
live preview starts only after the microphone is activated and uses the same local
model with a 750 ms sampling step, a rolling five-second context window, four
threads, a 48-token cap, and temperature fallback disabled. It stops on Stop,
Cancel, or app termination; BookCLI terminates the complete owned process group
with a bounded TERM-to-KILL fallback so no Whisper helper remains after quit. Final
transcription still prefers Metal and retries once on CPU only when Metal startup
fails. Override those paths with
`BOOKCLI_WHISPER_CLI` and `BOOKCLI_WHISPER_MODEL`. The raw transcript stays out
of the UI until `dictation_refinement.py` has offered it to the selected local
model for conservative, intent-aware cleanup. Cerebras and other remote
fallbacks are prohibited for dictation; uncached/unavailable/unsafe refinement
returns the Whisper wording. Stop transcribes into the editable composer without
sending; Send while listening transcribes and then submits exactly once; Escape
cancels the active generation and discards its audio/result. Audio is deleted
after completion, failure, or cancellation.

Librarian `open_book` actions default to BookCLI's in-app reader; Apple Books and
BookOKRat are used only when explicitly requested. In-app librarian opens create
new tabs in the current window rather than replacing the focused pane. Bulk shelf
requests use `open_shelf_books`, which creates all ordered tab shells in one pass
and warms only the final selected reader instead of eagerly mounting every book.

EPUB reader column width is stored as a pane-relative percentage from 20% to
100%, not as pixels. The reader measures the actual WebKit viewport after every
native, window, visual-viewport, or observed geometry change, then assigns the
column exactly `viewport width * selected percentage`; values below 100% stay
centered and 100% is deliberate edge-to-edge mode. App versions that stored
pixel widths migrate them against the former 1200-point reference width. Reader
cache version 6 generates intrinsically width-safe HTML with no fixed horizontal
body padding, while authored descendant minimum widths and unbreakable text are
constrained. Contents and inspector panes are accessories: each appears only if
its minimum width plus the divider can preserve a 280-point document, and both
yield when the physical pane itself is narrower. Native pre/post geometry hooks
and the continuously tracked stable-word anchor preserve the first visible
top-left word through live reflow; asynchronous native preparation reuses the
pre-resize marker instead of capturing a post-resize position. A low-cost
offset-change observer covers native/programmatic WebKit scrolling that emits no
DOM scroll event. The workspace title bar has its own geometry compression
boundary: excess minimum-width tabs scroll horizontally inside the available
strip and can never widen the reader or freeze its viewport at an old window
size.

### Module layout
`src/bookcli/cli.py` is the entry point (arg parsing plus the
`search`/`get`/`download` flows). Supporting modules live in the same package:
`net.py`, `library.py`, `shelves.py`, `librarian.py`,
`dictation_refinement.py`, `ui.py`, and `tui.py`.

If SSL fails, connect WARP first: `warp-cli connect`

### Manual fallback (if bookcli.py unavailable)

Use this sequence to produce a working direct download link. No API key required.

### Step 1 — Connect Cloudflare WARP
```
warp-cli connect
warp-cli status   # confirm: "Connected" + "Network: healthy"
```

### Step 2 — Search Anna's Archive (SSL bypass required)
The CLI at `/tmp/annas.py` fails on SSL without the bypass. Always run it like this:
```
python3 -c "
import ssl, sys
ssl._create_default_https_context = ssl._create_unverified_context
sys.argv = ['annas.py', 'search', '<title or author>', '-f', 'epub', '--limit', '10']
exec(open('/tmp/annas.py').read())
"
```
Pick the result with the cleanest author/title match. Note its **MD5 hash**.

### Step 3 — Build the libgen link
```
https://libgen.li/ads.php?md5=<MD5>
```
Example: `https://libgen.li/ads.php?md5=861e122a8b99c0b837851faeea2d4161`

Give this URL to the user. The page has a direct download button — no key needed.

### Step 4 — After user confirms download
1. Ask where to shelve it (suggest the best shelf).
2. Strip any metadata noise from the filename → `Title — Author (Year).epub`
3. Move it to the correct shelf.
4. Update `library.md` (add entry) and `wishlist.md` (mark as owned).
5. Commit.

### Notes
- WARP CLI: `/Applications/Cloudflare WARP.app`; disconnect when done with `warp-cli disconnect`
- Script source: `github.com/ratacat/annas-archive-ebooks`; script lives at `/tmp/annas.py`
- `ANNAS_ARCHIVE_KEY` env var needed only for CLI-based downloads (not required for the libgen link method)

## Retired mobile/iOS surface

The native `BookCLIiOS/` app, `bookcli serve`, `webserver.py`, the static `web/`
PWA, mobile sync/progress scripts, and `MOBILE_ACCESS.md` were removed on
2026-06-29 after a `bookcli-ios-server` launchd job was found keeping
`bookcli.py serve --host 0.0.0.0 --port 8000` externally reachable. Do not
recreate these paths or add a launchd job/server that binds the library on a LAN
or wildcard interface without an explicit new security review.

## Future Development

- **Librarian RAG + agent harness** (IMPLEMENTED 2026-07-18): the macOS Librarian
  uses SQLite catalog metadata and indexed book-text snippets through bounded
  tools for owned-title, author/topic, character, phrase, and per-book questions.
  The same tool loop can search/queue downloads, open/close books, cancel jobs,
  create/rename shelves, reshelve, request confirmed Trash deletion, refresh or
  navigate the app, and manage the selected local model. Slash commands and
  in-memory book mention completion feed exact mentioned-book context into chat.

- **Shelf management mode for the macOS app** (NOT YET): add a deliberate
  management surface for creating shelves, deleting empty shelves, merging one
  shelf into another, and bulk-moving selected books. Keep destructive actions
  out of the normal browsing path and require confirmation.

- **Command palette for the macOS app** (NOT YET): add a `Cmd+K` action palette
  for library search, download search, opening settings, moving/deleting books,
  renaming shelves, opening duplicates, and toggling reader controls.

- **bookokrat: comment/note timestamps in local time** (NOT YET — do not
  implement; needs the fork source): notes show the raw UTC instant instead of
  local time — e.g. a note made at 21:34 PDT on 2026-06-06 displays as
  `06-07-26 04:34`. Storage is correct (`comments/*.yaml` `updated_at` is proper
  UTC with `Z`, e.g. `2026-06-07T04:34:57Z`); only the *display* is wrong. Fix is
  a one-line change in the `bookokrat-bookcli` fork where the comment timestamp is
  formatted — convert UTC→local before formatting, e.g.
  `updated_at.with_timezone(&chrono::Local).format("%m-%d-%y %H:%M")`. Same fork
  we patched for continuous EPUB scrolling and the `← Books List` exit behavior;
  upstream is `github.com/bugzmanov/bookokrat` at tag `v0.3.12` (Homebrew formula:
  `https://github.com/bugzmanov/bookokrat/archive/refs/tags/v0.3.12.tar.gz`).
  The patched binary currently lives at `~/bin/bookokrat-bookcli`; the full
  rehydrated source tree is restored at `/private/tmp/bookokrat-src`, with build
  artifacts under `/private/tmp/bookokrat-src/target/release/`. If `/private/tmp`
  cleanup removes source files but `target/release/bookokrat.d` remains, that
  `.d` file lists the exact patched source file layout to rehydrate from upstream
  before re-applying local patches. No config/timezone option exists, so it must
  be a source patch + rebuild.

- **libgen download mirror visibility**: downloads use the `LIBGEN_MIRRORS` list
  in `net.py` (`libgen.li`, `libgen.is`, `libgen.rs`, `libgen.gs`) for
  `ads.php?md5=…` link resolution. The app download job records the actual
  resolved mirror host in `download_mirror`, and the Downloads UI shows it as the
  Mirror field so fallback behavior is visible to the user.

- **WARP CLI download retry fallback**: app downloads try the regular LibGen path
  first. Network/block-style failures (HTTP 403/429/503, SSL/timeout/Cloudflare/
  tiny HTML responses, unreachable mirrors) retry the same MD5 through WARP before
  candidate fallback. Direct downloads also have a conservative slow-path cutoff
  from the 2026-06-20 benchmark: regular mean `36.369s`, sample stdev `94.387s`,
  so direct transfers crossing `130.756s` are treated as anomalously slow and
  retried through WARP. The worker checks `warp-cli status`, connects only if WARP
  was not already connected, and disconnects only if that worker connected it. A
  cross-process lock under `library/state/warp-download.lock` serializes app-owned WARP
  retries so one download cannot disconnect another. Jobs persist `warp_state`,
  `warp_reason`, and `warp_started_by_app`; the Downloads UI shows a per-job WARP
  badge when fallback is connecting/active/used/failed.

- **Auto-download**: Full pipeline already proven via curl — search AA for MD5, parse libgen ads page for keyed `get.php` link, fetch epub. Next step: wrap into a single agent command `download "<title>"` that searches, downloads, cleans filename, shelves, and updates library.md + wishlist.md in one shot. Curl method (no key needed):
  ```bash
  KEY=$(curl -sk "https://libgen.li/ads.php?md5=<MD5>" | grep -o 'get.php?md5=[^"]*' | head -1)
  curl -skL "https://libgen.li/$KEY" -o "<output>.epub"
  ```
  Note: first MD5 result may return HTML (Cloudflare block) — retry with next MD5 if file size is <100K or `file` reports HTML.

## Git
- After every turn that changes any file in this folder, stage and commit the changes.
- Commit only tracked files (no epubs, pdfs, images — see .gitignore).
- Use a concise, specific commit message.

## macOS App Builds
- After any source change to `apps/macos/`, always run `python3 build_app.py` from
  `apps/macos/` so `apps/macos/dist/BookCLI.app` is rebuilt and reflects the
  current source before handing the work back to the user.
- Immediately replace the user-installed app with the rebuilt bundle:
  `rm -rf /Applications/BookCLI.app && cp -R apps/macos/dist/BookCLI.app /Applications/BookCLI.app`.
- For interaction fixes, add a native AppKit mouse-event regression that clicks
  the control center and visible hitbox edge, then run the full Swift test suite.
- After installing, quit every BookCLI instance, restart the Dock when its pinned
  tile is in scope, launch `/Applications/BookCLI.app`, verify the running process
  path, confirm the Dock URL is `file:///Applications/BookCLI.app/`, and compare
  SHA-256 hashes of the built and installed executables before handoff.
- Exception: prototype-only work under `apps/macos/WinkPrototype/` must rebuild
  only `Wink HUD Prototype.app`. Do not rebuild, install, or relaunch BookCLI.app
  for prototype experiments unless the user explicitly asks to integrate them.
- Production and prototype wink stacks are intentionally independent. The
  prototype owns `apps/macos/WinkPrototype/book_turner_worker.py` and
  `apps/macos/WinkPrototype/wink_detector.py`; production owns the corresponding
  files under `apps/macos/Resources/`. Prototype tuning must not modify the
  production worker or detector until integration is explicitly approved.

## Session History (backup reference)

Condensed log of major work sessions, for continuity across chats.

### bookcli.py — build & UI (master)
- Built `bookcli.py`: tokenless search/download CLI (search AA via HTML scrape → libgen
  `ads.php` keyed `get.php` link → stream epub). No API key. SSL bypass via
  `ssl._create_unverified_context`. WARP CLI fallback when SSL still fails.
- UI: colored dynamic-width box-drawing table (`shutil.get_terminal_size`), wraps long
  titles/authors across rows, streaming download progress bar, interactive default mode
  (type query → pick number → download → shelve → update library.md + wishlist.md).
- Installed as global `bookcli`: `chmod +x` + symlink `~/bin/bookcli`, `~/bin` on PATH.
- Search progress: deterministic bar filling 0→95% over 2.5s, snaps to 100% on completion.

### Performance branch (complexity) — implemented, NOT merged
On a `performance` branch, fixed 4 algorithmic issues in bookcli.py: `wrap()` O(w²)→O(w)
(list+join), `update_library()` O(n²)→O(n) (splitlines+insert), `suggest_shelf()` O(k×n)→O(n+k)
(tokenize to set for single-word keywords), `update_wishlist()` fast-path `"**BUY**" in line`
before `.lower()`. Then attempted network speedups that **failed and were reverted**:
parallel homepage mirror-probing picked `.li` (alive but returns 2-byte empty search →
"No results found"), and a persistent `http.client` keep-alive connection hung ("eons").
Reverted to `master`. Branch retained but superseded.

### search-latency branch (≥2x search speedup) — current work
Root cause of slowness diagnosed: every search did **two sequential round trips** — a
throwaway homepage liveness probe in `get_mirror()` (~1–2.2s) then a second request for the
actual search. **Fix: fold the liveness check into the search request itself.** `search_books()`
now tries mirrors in preference order (`.gl` first); the first returning *parseable results*
wins, alive-but-broken mirrors (`.li`) self-eliminate. Winner cached to `.mirror` (gitignored)
so repeat CLI runs skip rediscovery. Also: dropped `sort=year_desc` for relevance ordering,
precompiled parse regexes, added per-search elapsed-ms readout on the results line.

### Interactive TUI + background downloads + shelf split (main, 2026-06-06)
- Fixed `BOOK_DIR = Path(__file__).resolve().parent` so the `~/bin/bookcli` symlink
  dereferences to the real `~/Desktop/Book/` dir (was downloading/shelving into `~/bin/`).
- Rewrote `cmd_interactive()` as a raw-mode TUI (termios/tty/select): a full-screen redraw
  loop with `↑/↓` to highlight a result row, `enter` to download the highlighted row, type
  to search again, `:q` to quit. Non-tty stdin falls back to `_interactive_fallback()`.
- Downloads now run in **daemon threads** (`_bg_download`), so you can keep searching while
  one downloads. A **pinned status block** (`_pinned_lines()`) shows each download's progress
  bar / `shelving…` / `✓ → shelf/` / `✗ error`. Completed downloads auto-shelve to the
  `suggest_shelf()` shelf (no prompt) and update library.md + wishlist.md. `download_md5` and
  `fetch_stream` gained a `progress_cb` param; `print_table` split into `render_table()`.
- **Shelf reorg**: split the overloaded broad shelves — `science/` → physics/biology/
  psychology, `self-development/` → mindset/productivity (+ habits, kept empty for future),
  `investing/` → trading/business-finance. SHELVES + SHELF_KEYWORDS, library.md, and the
  shelf list above all updated.

### Unify: ownership + library browser + curses TUI (unify-tui-library, 2026-06-06)
- Split the monolithic `bookcli.py` into modules: `net.py`, `library.py`,
  `shelves.py`, `ui.py`, `tui.py` (entry stays `bookcli.py`; `~/bin/bookcli`
  symlink still works).
- **Ownership awareness**: `library.scan_library()` indexes shelf files; `find_owned()`
  fuzzy-matches search titles (token-subset match) so duplicates show `✓` + a
  ⌘-clickable OSC 8 `file://` path. Wired into `search`, `get`, and the TUI.
- **`--library` browser**: curses list of shelves/books, ↑/↓ navigate, ⏎ → macOS
  `open`, `/` filter, `:q` quit.
- **Curses rewrite** of the interactive loop (replaced the hand-rolled ANSI repaint):
  scrollable results in the managed screen (no scroll-ghosting), live download-queue
  footer that updates the instant a bg thread finishes, and the caret positioned
  exactly at the typed text. Non-tty stdin falls back to a line-based loop.

### Unified switchable TUI: Search ⇄ Library via Tab (unify-tui-library)
- Collapsed the two separate curses programs (`_interactive`, `_browse`) into one
  `_app` under a single `curses.wrapper`, holding a `State` with a `view` field.
  **Tab** toggles Search ⇄ Library; entering Library re-scans the index so
  session downloads appear. `bookcli` / `--library` just set the initial view.
- New **two-pane Library**: shelves+counts (left) | books with parsed
  Title/Author/Year (right). `library.OwnedBook` gained `title/author/year/ext`
  via `parse_meta()`, then enriched from the `library.md` catalog
  (`_load_catalog`/`_enrich`) so Title/Author land in the right columns even for
  messy filenames. New downloads work the same way: bookcli writes
  `Title — Author (Year)` filenames + a library.md entry, and the filename
  fallback splits only on ` — `/` -- ` (never a lone hyphen), so it never swaps.
  Download queue + message render in a shared footer for both views. Fixed: `_prompt_filter`/`_confirm_quit` now tolerate the global
  `timeout(120)` (raise curses.error on idle) instead of crashing.
- Library `⏎` now suspends curses and launches `bookokrat-bookcli` (preferred)
  or `bookokrat` for EPUB/PDF/DJVU terminal reading when available, falling back
  to macOS `open` for unsupported formats or missing reader. `bookokrat-bookcli`
  is a local v0.3.12 build with direct-file mode patched so selecting
  `← Books List` exits back to bookcli instead of opening Bookokrat's own
  directory-level list. The local build also patches EPUB scrolling into a
  continuous chapter window, so adjacent chapters are rendered in one scrollable
  stream and the active chapter is derived from visible rendered-line ownership.

**Latency baseline (measured via curl):** connection setup (DNS+TCP+TLS) is ~35–80ms —
negligible. The 1.5–3.4s per search is **entirely Anna's Archive server think-time** (TTFB
0.7–3.3s, highly variable per query) + ~0.6s to stream the 723KB result page. We are
server-bound, not client-bound — no meaningful client-side latency remains to optimize.
`.li` answers in ~80–155ms but with a 2-byte empty body (why it must be rejected, not raced).
