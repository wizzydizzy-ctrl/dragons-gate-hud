# Dragons Gate Top Chatbox Design

## Goal

Add an always-visible, persistent chatbox to the center column of DragonsGateHUD before implementing the embedded automapper. The chatbox captures approved Dragons Gate communication formats without suppressing normal console output and exposes a stable API that personal Mudlet triggers can use for future capture rules.

## Placement and Responsive Layout

The chatbox sits at the top center directly above the main game console. Its left edge and width exactly match the main console between the 17 percent HUD rails. Side HUD content continues beside the chatbox and is not pushed downward.

The target height is 240 pixels. Height is computed as a configurable percentage of the usable window height and clamped to readable minimum and maximum values. The default percentage is chosen to produce approximately 240 pixels at the current reference resolution. Wide, medium, short-height, compact, full-screen, and restored-window layouts must preserve a readable chatbox and main console without overlap, clipping, disappearing panels, or exposed black gaps.

The existing single `top` layout value is split conceptually into header height and console top. The HUD header remains at the top; the chatbox occupies the center column below it; the main console border begins below the chatbox. Side cards continue to use the header boundary rather than the lower console boundary.

The chatbox is always visible. It has no collapse control.

## Built-in Capture Categories

The built-in categories are:

- `ALL`: every captured entry;
- `ROOM`: room speech using says, asks, exclaims, shouts, and yells, with optional targets and languages;
- `OWN`: the active character's room speech and `You say ...` output;
- `WHISPER`: incoming and outgoing whisper formats;
- `ESP`: `<speaker> (ESP): "<message>"`;
- `DRAGON`: mental-link messages;
- `CONTACT`: thoughts echoing through the area;
- `STAFF`: Elder and Guide channel formats.

The visible filters may combine related categories for space, but every stored entry retains its exact category. `PRIVATE` is a display filter that includes WHISPER, ESP, DRAGON, and CONTACT.

Parsing uses anchored, format-specific rules based on supplied live/archive examples. A generic occurrence of `says`, `asks`, `exclaims`, or `whispers` is insufficient. Lines such as NPC narration or `The teller whispers to you...` are not captured unless they match an approved communication format.

The parser operates on plain text after ANSI removal while preserving the original readable message text for display and storage.

## Deduplication

Identical adjacent entries from the same category are deduplicated. Deduplication compares normalized category, speaker, target, and message text within a short configurable time window. Non-adjacent repeats and identical messages from different speakers are retained.

## Entry Model

Each captured entry contains:

- schema version;
- local timestamp in ISO 8601 form;
- active character name;
- category;
- speaker when available;
- target when available;
- language when available;
- message text;
- original normalized line;
- source, either `builtin` or `custom`.

Missing metadata fields are omitted rather than written as invented values.

## Extension API

The package exposes a stable public function:

```lua
DGHUD.chat.capture(category, text[, metadata])
```

`category` is normalized to a safe uppercase identifier. `text` is the message or full line to display and store. Optional metadata may provide speaker, target, language, timestamp, or original line. Custom captures are marked with source `custom`.

A personal trigger may call:

```lua
DGHUD.chat.capture("QUEST", line)
```

or:

```lua
DGHUD.chat.capture("EVENTS", "The invasion has started.")
```

Unknown valid categories automatically become available as filters. Invalid categories or empty text return a clear error without throwing inside the user's trigger.

The extension function remains stable across package updates. The HUD never edits or deletes personal triggers that call it. During package shutdown or a brief update replacement window, the function must fail safely rather than sending data or changing unrelated state.

## User Interface

The chatbox uses an owned Geyser container with:

- a compact tab/filter row;
- a scrollable or mini-console message body;
- readable responsive typography;
- channel-specific but theme-compatible colors;
- timestamps that can be displayed without dominating message text;
- an active-filter indicator;
- automatic scrolling only when the user is already at the bottom.

Default visible filters are ALL, ROOM, PRIVATE, ESP, DRAGON, CONTACT, and STAFF. OWN and WHISPER remain independently stored and can be included through ALL, ROOM, and PRIVATE. Custom category tabs appear in deterministic insertion order and must not overflow the panel; overflow categories use a compact selector or horizontal scroll behavior.

The first release is read-only. It captures and displays communication but does not send replies or messages.

## Persistence

Captured history is retained indefinitely unless the user explicitly deletes it outside the first release. Files live under the active profile data directory:

```text
DragonsGateHUD/chat/<safe-character-name>/YYYY-MM-DD.jsonl
```

Storage is append-only JSON Lines. Each line contains one versioned entry. Character and filename components are sanitized to prevent path traversal or invalid filenames. Unknown characters use an `unknown` directory until identity becomes available.

The visible model retains at most the newest 1,000 entries. On startup, only enough recent files are read to reconstruct that bounded view. Older logs remain untouched on disk. A malformed JSON line is skipped and reported once without preventing later valid entries from loading.

HUD update, reload, rollback, and uninstall do not delete logs. Chat logging failures do not interrupt game output or other HUD components.

## Runtime Flow

One owned line trigger forwards each incoming line to the chat parser. Recognized entries pass through deduplication, persistence, the bounded in-memory model, and the current visible filter. Custom API captures enter after parsing and use the same validation, deduplication, persistence, and rendering path.

Identity changes rotate storage to the corresponding character directory without losing already captured entries. Disconnect closes any open file handle and shutdown removes only owned triggers, handlers, timers, and Geyser objects.

## Isolation

Chat parsing, entry management, persistence, and rendering are separate modules with explicit interfaces. The subsystem owns only its runtime objects, files below `DragonsGateHUD/chat`, and the public `DGHUD.chat` table. It does not alter unrelated scripts, triggers, aliases, timers, packages, maps, modules, logs, or profile preferences.

The automapper implementation remains paused until this chatbox passes live acceptance and is published through the existing updater.

## Settings

Default settings include:

```lua
chat = {
  enabled = true,
  height_percent = 0.21,
  target_height = 240,
  min_height = 160,
  max_height = 320,
  visible_limit = 1000,
  dedupe_seconds = 3,
  timestamps = true,
}
```

Responsive computation uses the percentage and clamps, with the target height serving as the reference/default intent. User overrides merge through the existing settings mechanism.

## Testing and Acceptance

Pure Lua tests cover every supplied message format, optional targets and languages, rejection of misleading NPC/system narration, ANSI removal, metadata extraction, custom category validation, adjacent deduplication, bounded history, safe character paths, JSONL encoding, malformed-line recovery, and permanent append behavior.

Runtime tests verify one owned line trigger, API availability, update/reload idempotence, file-handle cleanup, and preservation of unrelated Mudlet content. Layout tests cover reference 240-pixel sizing, percentage scaling, min/max clamps, exact center-column alignment, and non-overlap at wide, medium, compact, full-screen, restored, and short-height resolutions.

Live acceptance in the disposable `Dragons Gate HUD` profile must demonstrate:

1. supplied ROOM, OWN, WHISPER, ESP, DRAGON, CONTACT, and STAFF examples enter the correct filters;
2. misleading NPC narration is not captured;
3. adjacent duplicate ESP entries appear once;
4. normal game output remains in the main console;
5. a personal trigger calling `DGHUD.chat.capture("QUEST", line)` creates and populates a custom category;
6. captured entries persist across reload, reconnect, update, and Mudlet restart;
7. resizing preserves the always-visible top-center chatbox and usable console;
8. unrelated personal triggers, aliases, scripts, packages, map data, and settings remain unchanged.

## Delivery Sequence

Implementation proceeds through pure parser and entry model, append-only storage, chat controller and extension API, responsive top-center UI, then live acceptance and updater release. The embedded automapper plan resumes only after the chatbox release is stable.
