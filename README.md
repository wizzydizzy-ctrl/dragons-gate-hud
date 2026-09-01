# Dragons Gate GMCP HUD

An original bronze-and-jade Mudlet 5 HUD for Dragons Gate. It displays confirmed `Char.Status`, `Char.Vitals`, and `Room` GMCP values, including `weapon_readied` and `shield_readied`.

## Local build and install

```bash
python3 scripts/build.py --owner wizzydizzy-ctrl --repository dragons-gate-hud
```

In the Dragons Gate Mudlet profile command line, replace the path and run:

```lua
lua installPackage("/absolute/path/to/dragons-gate-hud/dist/DragonsGateHUD.mpackage")
```

After the first GitHub release, install directly with:

```lua
lua installPackage("https://github.com/wizzydizzy-ctrl/dragons-gate-hud/releases/download/v0.1.0/DragonsGateHUD.mpackage")
```

This executes code from that release inside the current Mudlet profile. Use only your own repository URL.

## Publishing

Create an empty GitHub repository, set your owner in `src/defaults.lua`, commit this project, and push a semantic version tag such as `v0.1.0`. GitHub Actions tests and attaches `DragonsGateHUD.mpackage` and `manifest.json` to the release.

The HUD owns only the package named `DragonsGateHUD`, runtime IDs it creates, and files under the profile's `DragonsGateHUD` data directory. It does not alter unrelated profile triggers, aliases, scripts, timers, keys, packages, modules, maps, or settings.

## Persistent top chatbox

The always-visible top-center chatbox records approved communication formats without gagging, replacing, or otherwise changing normal game output. Its built-in filters are `ALL`, `ROOM`, `OWN`, `WHISPER`, `ESP`, `DRAGON`, `CONTACT`, and `STAFF`; `PRIVATE` shows `WHISPER`, `ESP`, `DRAGON`, and `CONTACT` together. Each entry retains its exact category even when a combined filter is used.

The default chat settings are:

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

User overrides merge into these defaults, including nested `chat` overrides, without discarding unknown personal settings. For example, from the Mudlet command line, set an override and reload:

```lua
DGHUD.user_settings.chat = DGHUD.user_settings.chat or {}
DGHUD.user_settings.chat.height_percent = 0.25
DGHUD.user_settings.chat.timestamps = false
DGHUD.reload()
```

Setting `chat.enabled = false` disables the HUD-owned chat capture runtime. `visible_limit` bounds only memory: the disk log is never pruned by the HUD. Adjacent duplicate entries with matching category, speaker, target, and message are accepted only once within `dedupe_seconds`; later or non-adjacent repeats remain in the log.

### Custom capture triggers

Personal triggers remain yours. The HUD never creates, edits, or deletes them. A personal trigger can add a filterable custom category through the stable API:

```lua
DGHUD.chat.capture("QUEST", line)
```

Or send a message directly when the trigger already extracts the text:

```lua
DGHUD.chat.capture("EVENTS", "The invasion has started.")
```

Valid new categories automatically become available as filters. Calls made while the HUD is replacing itself during reload/update fail safely and do not send game commands or modify unrelated runtime.

### Storage, privacy, and diagnostics

Captured entries are append-only JSON Lines stored permanently under the active Mudlet profile data directory:

```text
<Mudlet home>/DragonsGateHUD/chat/<safe-character-name>/YYYY-MM-DD.jsonl
```

The HUD reads at most the newest 1,000 valid entries into memory, but leaves older dated logs intact. Reloading, updating, rolling back, or uninstalling the HUD does not delete these files. Delete the relevant files yourself if you want to remove retained history.

Private communications such as whispers, ESP, Dragon, and Contact traffic are saved locally in these plain JSONL files. Anyone with access to your Mudlet profile, computer account, backups, or copied profile data may be able to read them. The HUD does not transmit chat logs, but you should treat the directory as sensitive local data.

Run `dghud chatstatus` to print the active filter, the current visible-entry count, the sanitized current-character storage key, and the most recent storage error (`none` when no storage error has occurred in the running chat session).

## Embedded automapper

The native Mudlet map is embedded in the lower-left HUD immediately above the compass. While the mapper is enabled, each valid `gmcp.Room.Info.num` becomes the canonical Dragons Gate room ID. Walking through the twelve standard directions (`n`, `ne`, `e`, `se`, `s`, `sw`, `w`, `nw`, `up`, `down`, `in`, and `out`) discovers rooms, creates advertised exit stubs, and confirms links only after the destination room arrives through GMCP. Teleports do not invent links.

The default mapper settings are:

```lua
mapper = {
  enabled = true,
  walk_timeout = 12,
  minimum_height = 90,
  schema = 1,
}
```

Nested user overrides and unknown future settings are preserved during merge and migration. Set `DGHUD.user_settings.mapper.enabled = false` and run `DGHUD.reload()` to disable discovery and walking. `walk_timeout` controls how many seconds a sent movement command waits for its expected room update. `minimum_height` sets the visible mapper floor when the window can accommodate it; wide layouts retain a 140-pixel responsive floor, while medium layouts default to 90 pixels. If the configured floor cannot fit without overlapping essential HUD content, the mapper hides cleanly.

Click a known destination in the embedded map or use:

```text
walkto 176
walkstop
mapcenter
dghud mapstatus
```

Walking sends exactly one standard movement command at a time and waits for the expected GMCP room number. After arrival, nonzero GMCP roundtime pauses the route until a later Vitals update reports zero. The per-step movement timeout is canceled while paused because no command is in flight; a fresh timeout starts only when the next direction is sent. Wrong directions, unexpected rooms, manual movement, disconnection, timeout, and shutdown stop the route. Automatic special-exit traversal is intentionally excluded from this release; portal, door, gate, arch, and other nonstandard transitions must be used manually.

The HUD tags only its own rooms and areas with `dghud.owner=DragonsGateHUD`. It refuses to rewrite an existing unowned room or area and never deletes personal map data. Discovered native Mudlet map records remain when the HUD reloads, updates, or is uninstalled. `dghud mapstatus` reports only whether mapping is enabled, the current room, the number of rooms managed during the HUD session, an active walking destination, the latest mapper status, and the latest actual mapper error. Routine stops such as `walkstop`, manual movement, route replacement, and shutdown update the status but do not overwrite the last error. It does not dump room names, routes, personal map records, or unrelated data.

Updating with `dghud update` replaces only the `DragonsGateHUD` package code. It preserves native map records, chat logs, user settings, and unrelated Mudlet scripts, aliases, triggers, packages, and map content.
