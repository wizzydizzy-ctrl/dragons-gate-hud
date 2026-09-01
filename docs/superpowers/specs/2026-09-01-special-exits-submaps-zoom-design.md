# Dragons Gate HUD Special Exits, Sub-Maps, and Zoom Design

## Objective

Extend the embedded automapper so every observed non-directional room transition becomes a persistent Mudlet special exit. A newly discovered destination reached this way starts a separate HUD-owned sub-map, including transitions through doors, gates, portals, arches, and future commands such as `climb rope`. GMCP room numbers remain the canonical global room identity. Add reliable embedded controls that change the visible size of map rooms.

## Canonical Room Identity

`gmcp.Room.Info.num` is the only room identity. One numeric room ID may exist only once in Mudlet's map.

- The first successful discovery creates that numeric room and assigns its map area and coordinates.
- Later visits reuse the existing room, its area, and its coordinates.
- Re-entry automatically centers the embedded map on that room, switching the displayed map area when necessary.
- Multiple entrances may point to the same destination room without creating duplicate rooms or sub-maps.
- A preexisting room with the same ID that is not owned by `DragonsGateHUD` remains protected. The HUD neither adopts, moves, nor rewrites it.

The command used to move identifies an edge between rooms; it never identifies the destination room.

## Transition Classification

Standard directions remain `n`, `ne`, `e`, `se`, `s`, `sw`, `w`, `nw`, `up`, `down`, `in`, and `out`, including their accepted long aliases. They retain the current coordinate-based mapping behavior.

Any other eligible outbound game command starts a short-lived special-transition candidate containing:

- origin GMCP room ID;
- exact normalized command sent to the game;
- start time and owned timeout token.

The candidate is confirmed only when a later `gmcp.Room.Info` update reports a different valid room ID before the timeout. Same-room GMCP refreshes do not confirm or cancel it. A later outbound command replaces or cancels the candidate, ensuring that the final command associated with the room change is used.

Candidates are canceled on timeout, standard movement, wrong direction, disconnect, shutdown, mapper disablement, or an invalid/ownership-conflicting destination. HUD aliases, mapper commands, chat commands, character-data refresh commands, and other explicit non-travel control commands are excluded. The exclusion policy is conservative and test-covered. Unrecognized commands remain eligible so future game traversal syntax works without package changes.

The default confirmation window is three seconds and is configurable under the existing nested mapper settings. Timer creation or cancellation failures are contained and reported without inventing an exit.

## Sub-Map Assignment

Every confirmed non-directional transition to a previously unseen room creates a new HUD-owned sub-map, even if Dragons Gate reports the same GMCP area number. Doors are treated the same as gates, portals, arches, and arbitrary confirmed special transitions.

The sub-map's persistent key is derived from the canonical destination room ID, not the origin command. This provides stable behavior:

- entering destination room `1234` for the first time creates the sub-map rooted at `1234`;
- entering room `1234` later through another door reuses that room and sub-map;
- directional exploration from room `1234` remains in that sub-map while the game-reported area remains unchanged;
- a standard directional transition that changes the game-reported GMCP area starts or enters the corresponding normal HUD-owned area;
- a later special transition to another unseen room starts another sub-map.

Rooms store their effective HUD map partition and original game area as room user data. Existing owned rooms retain their current assignment during migration. The mapper must never relocate an already mapped room merely because it is reached through a new connection.

Sub-map areas use collision-resistant names containing the destination room ID and are tagged with the existing owner, mapper schema, and ready/provisional transaction metadata. Partial area or room creation follows the current exact-object rollback rules.

## Special Exit Persistence and Reverse Links

After destination room creation or lookup succeeds, the adapter calls Mudlet's `addSpecialExit(originID, destinationID, command)` for a one-way connection. The edge is written only when both rooms are HUD-owned. Repeated observation of the same edge is idempotent.

No reverse connection is inferred. A reverse edge is created only after an actual journey from the destination back to the origin confirms the exact return command. The return command may differ from the forward command.

If a command reaches an already known destination, the mapper adds only the missing observed edge and centers the known room. It does not alter either room's map area or coordinates.

## Walking Across Special Exits

Confirmed special exits participate in `walkto` and map-click routes. The walker continues sending exactly one command at a time and waiting for the expected GMCP room ID.

Before sending a non-direction route step, the HUD validates that the exact command is a stored special exit from the expected owned origin to the expected owned destination. Arbitrary strings returned by pathfinding are rejected. Roundtime pausing, movement timeout, unexpected-room handling, manual-movement cancellation, disconnect handling, and generated-command isolation continue to apply.

## Embedded Zoom Controls

The mapper frame gains three HUD-owned controls:

- `+` makes room squares larger;
- `−` makes room squares smaller;
- a center control recenters the current room without changing zoom.

The implementation uses Mudlet's `getMapZoom(areaID)` and `setMapZoom(value, areaID)` APIs. Mudlet's numeric convention is inverted from the visual wording: decreasing the value makes rooms larger, while increasing it shows more of the area. The HUD hides this detail from users.

Zoom is adjusted in predictable increments, clamped to Mudlet's minimum of `3.0` and a conservative maximum, and stored by Mudlet per area. Switching among normal areas and sub-maps restores each area's saved zoom. Zoom controls never modify room coordinates, map ownership, or the main HUD layout.

When the API is unavailable or returns an error, the controls leave the current zoom unchanged and report a bounded mapper error. They do not fall back to synthetic scaling that could desynchronize the native map.

## Ownership and Update Isolation

The feature extends the existing ownership boundary:

- mutate only rooms and areas tagged `dghud.owner=DragonsGateHUD`;
- create only HUD-owned special exits whose origin and destination are HUD-owned;
- do not delete personal rooms, areas, exits, map labels, or map settings;
- do not edit personal triggers, aliases, scripts, timers, keys, packages, or modules;
- preserve rooms, sub-maps, special exits, zoom values, settings, and chat logs across `dghud update`, reload, and uninstall.

Package replacement remains limited to the `DragonsGateHUD` package and its exact owned runtime IDs.

## Diagnostics

`dghud mapstatus` remains bounded and may add:

- whether a special-transition candidate is pending, without printing its command;
- current effective map partition;
- current area zoom;
- latest special-exit or zoom error.

Routine candidate expiration and replacement are statuses, not persistent errors. Diagnostics must not dump personal map contents or unrelated commands.

## Testing and Acceptance

Automated tests will cover:

- GMCP room ID reuse without duplicate room creation;
- separate sub-map creation for doors and all other confirmed non-direction transitions;
- directional continuation within a sub-map;
- normal GMCP area changes during directional movement;
- multiple entrances to one canonical destination;
- observed-only reverse links with different commands;
- candidate replacement, expiry, same-room refresh, cancellation, exclusions, and timer failures;
- ownership conflicts and transactional rollback;
- persistence/reload behavior through Mudlet user data;
- safe special-exit validation during `walkto` and map clicks;
- zoom direction, increments, bounds, per-area persistence, reset/recenter, and API failures;
- responsive mapper controls without overlap at wide, medium, short, and compact layouts;
- preservation of all unrelated Mudlet content during reload, update, and shutdown.

Live acceptance in the disposable `Dragons Gate HUD` profile will verify:

1. enter a door/gate and observe a new sub-map centered on the canonical destination room;
2. walk directionally inside it and see rooms remain in that sub-map;
3. return through the transition and confirm the reverse link appears only then;
4. revisit both rooms and confirm the mapper switches to the previously saved room and area;
5. use `+` and `−` and confirm room squares visibly change size;
6. resize the Mudlet window and confirm controls remain usable without obscuring the map;
7. run `walkto` across the confirmed special exit and verify exact expected-room checks;
8. confirm personal Mudlet content and unowned map data remain untouched.
