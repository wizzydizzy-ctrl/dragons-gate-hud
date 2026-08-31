# Hybrid Character Data and Inventory HUD Design

## Purpose

Extend Dragons Gate HUD so it can display useful character, combat, equipment, and inventory information that Dragons Gate Classic does not currently expose through GMCP. The HUD will continue to use GMCP internally, but all visible wording will describe game information rather than its transport.

The implementation must remain isolated to the `DragonsGateHUD` package. Installing, updating, reloading, or removing the HUD must not alter unrelated Mudlet scripts, triggers, aliases, timers, variables, or packages.

## Observed game interfaces

The current GMCP tree supplies:

- Character name, surname, race, class, and alignment
- HP, fatigue, carry weight and capacity, PSI, web, gold, and silver
- Weapon and shield readiness booleans, position, and roundtime
- Room name, number, area, environment, flags, exits, players, and wrong direction

It does not currently supply the detailed inventory, attribute rankings, physical description, exact readied item names, armor percentage, OR, DR, movement rate, damage bonus, combat stance, area-position prose, or novice protection.

Live Dragons Gate Classic output established these command formats:

- `inventory`: begins with `Items carried:`, lists one item per indented line with a bracketed weight, and ends with `Your inventory totals ... lbs.`
- `stat`: reports body armor, OR, DR, movement rate, damage bonus, stance, area-position prose, novice protection, and a list below `::: Equipment Readied :::`
- `info`: reports physical description, HP/fatigue/carry, the eleven attribute headings and values, and valid extended `INFO` subjects

The command is `stat`, singular. `stats` and `statistics` are not supported.

## Architecture

### Source-neutral state

`state.lua` will produce one view model without exposing whether a field came from GMCP or command output. It will merge two inputs:

1. Structured GMCP data
2. A command snapshot maintained by the collector

For fields available from both sources, valid GMCP values win. Parsed output fills fields that GMCP omits. A later GMCP addition can therefore replace a parser-backed field without changing the view.

The merged state will add:

- `character.physical`: build, age, sex, life stage, height, and weight
- `character.religion` and `character.deity`, initially absent unless a future source supplies them
- `attributes`: STR, INT, WIS, DEX, AGI, CON, CHA, WIL, VOI, PER, and APP
- `combat`: body armor, OR, DR, movement current/maximum, damage bonus, stance, area position, and novice protection
- `equipment.items`: exact readied-item descriptions
- `inventory.items`: ordered item descriptions and numeric weights
- `inventory.total_weight`

Missing parsed values remain absent rather than becoming misleading zeroes. Existing GMCP-backed numeric fields retain their current normalization and safe defaults.

### Command parser

A new pure Lua parser module will parse complete line arrays and return partial snapshots. It will contain independent functions for inventory, stat, and info output. Parsing will be case-tolerant where the server wording is semantically stable, trim terminal whitespace, and ignore ANSI formatting before matching.

The parser will not infer equipment slots from item names. Exact readied items will be displayed in server order because races and equipment types can vary. Inventory entries with duplicate names remain separate entries.

Malformed or incomplete output will not replace the last complete snapshot for that command. Empty inventories are valid when the server emits an explicit empty result or a zero total.

### Collector and lifecycle

A new collector component will own all temporary triggers and timers used for command capture. The Mudlet adapter will expose package-scoped operations for creating and removing line triggers, scheduling and cancelling timers, and sending game commands.

The collector will recognize entry into play from the server's `Welcome to Dragon's Gate, <name>!` line. It will then run this sequence once for that play session:

1. `inventory`
2. `stat`
3. `info`

Commands will be sent sequentially, advancing only when the prior command reaches its recognized terminator. This prevents interleaved output and avoids arbitrary rapid-fire timing. No periodic polling will be added.

The same capture triggers remain available for user-entered `inventory`, `stat`, and `info`, so normal manual commands refresh the HUD. The collector identifies response boundaries from server output rather than intercepting or replacing the user's commands.

The one-time login refresh resets on disconnect and begins again after the next character-entry welcome line. Account-menu activity does not trigger collection. If a response times out, the collector abandons only that response, retains the previous valid snapshot, and continues to the next startup command. Timeout messages are diagnostic-only and do not interrupt play.

Every collector-owned trigger, event handler, and timer is recorded and removed by HUD shutdown. Reload and update remain idempotent and cannot leave duplicate collectors behind.

### Refresh flow

When GMCP changes, the existing refresh path normalizes GMCP plus the latest command snapshot. When a parser completes a valid command response, the collector stores that partial snapshot and requests the same refresh path. The view receives one immutable merged state shape in both cases.

No parser or collector code will directly modify Geyser widgets.

## HUD design

### Visible terminology

`GMCP` will be removed from user-visible labels. The header status becomes `● LIVE`. Internal module names, event names, tests, and protocol handling may still use the correct technical term.

### Top-left Identity

The existing separate Identity card remains at the top-left and displays:

- Name
- Race and class
- Alignment
- A concise physical line containing age, sex, and height when available
- Religion or deity only when a source provides a non-empty value

Detailed prose such as body-build wording will be omitted from the always-visible card if it causes wrapping; it remains available to the Character Details section.

### Lower-left Vitals and Location

Vitals, Status, Location, and Exits remain anchored near the input line. Existing gauges and room data remain GMCP-backed internally. Combat stance may appear in Status when available.

### Right rail

The right rail is divided into three independently sized cards:

1. Equipment: exact readied item names from `stat`; readiness booleans remain the fallback before the first successful capture
2. Wealth: gold and silver
3. Inventory: ordered carried-item list, per-item weight, and total weight

Equipment and Wealth remain visible above Inventory. The Inventory card uses the remaining right-rail height. It shows as many complete rows as fit, then displays a final `+N more` row when necessary. It will not split or partially clip an item row. This deterministic truncation is preferred over adding an embedded scrollbar that could interfere with Mudlet's main console scrolling. A later explicit inventory window can add full scrolling without changing the state model.

### Combat and Character Details

A compact details card will show the highest-value parsed information:

- Body armor, OR, and DR
- Movement rate, damage bonus, and stance
- Novice protection status
- Eleven attributes in a compact grid
- Physical build, age, sex, height, and weight when space permits

On wide layouts this card occupies available left-side space between Identity and the lower-left Vitals stack. On medium layouts it uses a shorter summary: armor, OR/DR, stance, and a compact attribute line. Compact mode adds only armor, stance, and inventory count to the existing summary strip; it does not create side rails.

All new card heights, row heights, padding, and truncation capacity derive from responsive layout metrics. No new fixed text heights will be introduced.

## Error handling and compatibility

- Unknown or changed server wording leaves the last valid snapshot intact.
- Parser failures are contained with protected calls and cannot break GMCP refreshes.
- Before initial command capture, the HUD renders existing GMCP data and explicit unavailable placeholders only where useful.
- A disconnected or account-menu profile does not send character commands.
- Multiple welcome lines in one play session do not repeat the startup sequence.
- Re-entering after disconnect or returning from the account menu starts one fresh sequence.
- Existing settings remain compatible; no mandatory user configuration is introduced.
- The updater continues to replace only the `DragonsGateHUD` package.

## Testing strategy

Implementation will follow test-driven development with these layers:

1. Parser tests using captured Classic output for normal inventory, duplicate items, empty inventory, incomplete output, stat values, readied equipment, info description, and all eleven attributes
2. State tests proving GMCP precedence, parser fallback, absent-value handling, and preservation of existing normalized fields
3. Collector tests proving character-entry detection, one sequence per play session, sequential command advancement, manual-command refresh, timeout behavior, disconnect reset, and complete lifecycle cleanup
4. Layout and view tests proving responsive card metrics, inventory row capacity, deterministic `+N more` truncation, separate Identity/Equipment/Wealth/Inventory content, compact fallback, and absence of visible `GMCP` text
5. Runtime tests proving update/reload idempotence and no leaked triggers or timers
6. Package build verification and live Mudlet acceptance at wide, medium, and compact widths

Live acceptance will confirm that entering a character runs exactly three startup commands, the captured values match the game output, manual `inventory`, `stat`, and `info` refresh the HUD, no text is clipped, and unrelated Mudlet content remains untouched.

## Delivery

The feature will ship as the next semantic patch release through the existing GitHub release workflow. GitHub Actions must finish building the release assets before `dghud update` is run in the testing profile. The installed version, health check, live layout, and clean repository state will be verified before completion is reported.
