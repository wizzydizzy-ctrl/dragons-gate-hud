# Safe Map Cleanup Design

## Objective

Dragons Gate HUD will let users repair an incorrectly generated map by deleting one HUD-owned room, one HUD-owned special submap, or one HUD-owned mapper area. Cleanup must never delete or mutate personal or otherwise unowned Mudlet map content.

## User Commands

The first release exposes command aliases only:

- `dghud map delete room <room-id>`
- `dghud map clear submap <root-room-id>`
- `dghud map clear area <area-name-or-id>`
- `dghud map confirm <token>`
- `dghud map cancel`

A delete or clear command is read-only. It prints the operation, resolved area, exact sorted room IDs, room count, blockers, and an opaque one-use token. The token expires after 30 seconds. `confirm` executes only the matching pending plan. `cancel` invalidates it. Starting a new preview replaces the previous preview.

There is no force option. A future map context menu may invoke the same planner, but it will not have separate deletion behavior.

## Ownership Boundary

Persisted Mudlet metadata is the sole authority:

- A room is owned only when `dghud.owner == "DragonsGateHUD"` on that room.
- An area is owned only when `dghud.owner == "DragonsGateHUD"` on that area.
- Names, prefixes, room-number ranges, in-memory caches, and provisional state never establish ownership.

An individual HUD-owned room may be deleted from an unowned legacy area only if doing so cannot mutate unowned inbound sources. The containing area must remain.

Area or submap cleanup requires an owned area and independent ownership verification of every room currently in it. Missing metadata, mixed ownership, unsupported mapper APIs, and read failures are hard blockers.

## Scope Resolution

Room deletion resolves exactly one positive integer room ID.

Submap cleanup resolves the exact partition `special:<root-room-id>` and exact mapper area associated with `Dragons Gate - Submap <root-room-id>`. Every selected room must have that persisted partition and belong to the resolved owned area. Connectivity alone never defines submap membership.

Area cleanup resolves an exact area ID or unambiguous exact area name. It never uses partial-name matching. Every room returned by Mudlet for that area is re-read and verified.

All room lists are normalized, deduplicated, and sorted numerically so previews and execution are deterministic.

## Safety Checks

Planning and confirmation both reject the operation when:

- The current physical room is in the deletion set.
- A map walk is active, or an active route/destination intersects the set.
- Automapper movement or a special transition is pending.
- Any selected room is missing or unowned.
- Area ownership or membership is incomplete, mixed, or changed.
- An ordinary or special inbound exit originates in an unowned room.
- Required reads fail or the installed Mudlet mapper lacks required capabilities.

Mudlet's `deleteRoom` removes exits to and from the room. Therefore inbound-source inspection is mandatory to prevent deleting an exit from personal content. The HUD does not pre-remove exits because doing so creates additional partial-failure states.

## Immutable Preview and Confirmation

A pending plan records the operation, target, sorted room IDs, resolved area, ownership evidence, route/current-room state, creation time, and a random opaque token.

On confirmation, the HUD rebuilds the plan from current mapper state. Execution proceeds only if the rebuilt operation, target, area, room IDs, ownership, inbound-source safety, and movement state exactly match the preview. Expired, reused, cancelled, or stale tokens fail without mutation.

## Execution Order

The cleanup controller allows only one operation at a time.

1. Consume the confirmation token and lock cleanup re-entry.
2. Rebuild and compare the plan one final time.
3. Stop the walker and clear generated speed-walk state.
4. Cancel pending automapper movement and special transitions.
5. Delete validated rooms individually in ascending room-ID order.
6. For area/submap cleanup only, re-read the area after room deletion. Delete it only when it is empty and still HUD-owned.
7. Clear affected adapter caches and `managed_rooms` entries.
8. Refresh Mudlet's map and resynchronize from fresh GMCP room information.
9. Release the cleanup lock and report the result.

`deleteArea` is never used as the first deletion operation because it recursively removes rooms.

## Partial Failure

Deletion cannot be transactional through Mudlet. If a room deletion fails mid-batch, execution stops immediately. The result reports exact deleted IDs, the failed ID and error, and exact untouched IDs. The area is never deleted after a partial failure. The map refreshes and caches are reconciled with actual surviving content.

The consumed token cannot be retried; the user must generate a fresh preview.

## Components

- `map_adapter.lua`: guarded ownership reads, inbound-source inspection, exact scope resolution, individual deletion, empty-owned-area deletion, cache invalidation, and capability wrappers.
- New cleanup planner/controller module: immutable previews, token expiry, stale-plan comparison, single-operation lock, execution orchestration, and result reporting.
- `main.lua`: aliases, walker/automapper/special-transition safety boundary, status messages, and post-cleanup synchronization.
- `mudlet_adapter.lua`: secure token entropy where available, current-time source, mapper refresh, and exact Mudlet API wrappers.
- Tests: pure planner/controller tests, adapter ownership tests, runtime alias tests, and end-to-end acceptance preserving personal map content.

## Verification

Automated tests must demonstrate:

- Individual deletion accepts only a safe HUD-owned room.
- Unknown, personal, missing-owner, malformed, current, routed, or pending rooms are rejected.
- Ordinary and special inbound exits from unowned rooms block deletion and remain unchanged.
- HUD-owned rooms in an unowned legacy area never authorize area deletion.
- Mixed areas and mismatched submap partitions are rejected.
- Expired, reused, cancelled, and stale tokens cause zero mutation.
- Confirmation detects ownership, membership, route, and current-room changes.
- Mid-batch failure reports exact results and preserves the area.
- Successful cleanup clears stale routes/caches, refreshes the mapper, and allows later GMCP remapping.
- Personal rooms, areas, exits, special exits, names, coordinates, labels, and metadata remain byte-for-byte unchanged.

Live acceptance occurs only in the disposable `Dragons Gate HUD` profile. It will create a deliberately isolated HUD-owned test submap, preview cleanup, verify cancellation and expiry, execute cleanup after moving outside it, confirm personal content is unchanged, revisit a deleted canonical room, and verify it maps cleanly again.

## Release and Compatibility

The feature ships through the existing signed/checksummed GitHub release workflow and `dghud update`. It changes only the DragonsGateHUD package and its HUD-owned mapper objects. It must not modify user triggers, aliases, scripts, settings, chat logs, unrelated packages, or personal map content.
