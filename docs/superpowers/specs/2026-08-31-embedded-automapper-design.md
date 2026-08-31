# Dragons Gate Embedded Automapper Design

## Goal

Add an isolated Dragons Gate automapper to the existing HUD. It must discover rooms from GMCP while the player explores, persist the resulting graph in Mudlet's native map database, render an interactive nearby-room map inside the HUD, and support safe room-number walking.

## Scope

The first mapper release supports standard directional exits: north, northeast, east, southeast, south, southwest, west, northwest, up, down, in, and out. It creates rooms and exit stubs, connects confirmed movement, centers the embedded map on the current room, handles clickable destinations, and provides `walkto <room number>`, `walkstop`, and `mapcenter`.

Automatic special-exit traversal is excluded initially. Doors, gates, portals, arches, teleports, and other non-directional transitions may be observed and recorded, but they must not be used for automatic walking until their commands and arrival behavior are confirmed.

## HUD Placement and Responsive Behavior

The mapper is a native `Geyser.Mapper` embedded in a dedicated HUD container. It sits immediately above the compass direction pad in the lower-left navigation stack. Vitals, Status, and Location remain above the mapper; the compass and GO PORTAL/DOOR/GATE/ARCH buttons remain below it.

At wide and medium sizes, the map receives the flexible vertical space between Location and the compass. It has a minimum usable height and scales with the rail. At shorter heights, low-priority detail is reduced before the mapper is hidden. At compact widths, the existing side rails collapse and the first release may hide the embedded map rather than obscure the main console. No resize path may expose unstyled black gaps.

The current room is centered and highlighted. The map defaults to a nearby-room view with native zoom and pan rather than scaling the entire known world into the panel.

## Room Identity and Ownership

Dragons Gate `gmcp.Room.Info.num` is the canonical game room identifier and is used as the Mudlet room ID when available. The mapper stores ownership and schema metadata using Mudlet map or room user data. It mutates only rooms tagged as managed by DragonsGateHUD.

Existing unowned Mudlet rooms are never deleted or silently rewritten. If a canonical game room ID collides with an unowned room, the mapper records the conflict, leaves that room untouched, and does not create unsafe links until the conflict is resolved.

HUD updates and package removal preserve discovered map data. Map deletion requires a separate explicit purge operation.

## Room Discovery

On each `gmcp.Room.Info` event, the mapper normalizes the room number, name, area identifier, environment, flags, and exits. Unknown managed rooms are created and assigned to a managed area derived from the GMCP area identifier. Each advertised but unexplored standard direction receives an exit stub.

The mapper records the last outgoing standard movement command and its origin room. When a different GMCP room number arrives, it connects the origin to the destination in that direction. A reverse exit is added only when the destination advertises the opposite direction or the reverse movement is later observed.

Room changes without a pending standard direction are treated as non-directional transitions. The current room is updated, but no directional edge is invented.

## Coordinates and Conflicts

New directional rooms receive coordinates relative to the origin using standard direction vectors. Up and down change the Z coordinate. Before placement, the mapper checks for an occupied coordinate in the managed area. A conflict is resolved deterministically by shifting the new branch to the nearest free coordinate while preserving the confirmed graph edge. The mapper must never stack distinct managed rooms invisibly at the same coordinate.

## Pathfinding and Walking

Mudlet's native graph and path calculation provide the route. Clicked room destinations and `walkto <room number>` enter the same controlled walker.

The walker sends one step at a time. It waits for a GMCP room update matching the expected next room before sending another step. Roundtime delays pause progression without discarding the route. Standard movement aliases may be used in generated routes; special exits remain locked or excluded in the first release.

Walking stops immediately on:

- `walkstop` or package shutdown;
- disconnection;
- `gmcp.Room.WrongDir`;
- an unexpected destination room;
- a movement timeout;
- a conflicting manual movement command;
- a route containing an unsupported special exit.

Stopping leaves the map and discovered rooms intact and reports a concise reason in the HUD or console.

## Isolation

Mapper code is split into normalization, graph planning, Mudlet map adapter, walker, and embedded view responsibilities. All runtime triggers, handlers, aliases, timers, and Geyser objects are owned and removed by DragonsGateHUD. The module does not inspect, modify, or delete unrelated user scripts, triggers, aliases, timers, packages, modules, or unowned map rooms.

## Persistence and Updates

The native Mudlet map database stores rooms and links. Versioned ownership metadata supports future migrations. Package updates may add or repair managed metadata but do not purge mapped rooms. A failed update or health check rolls back HUD code without replacing the user's map database.

## Testing and Acceptance

Pure Lua tests cover room normalization, directional vectors, stubs, confirmed and unconfirmed reverse links, coordinate collision handling, ownership conflicts, route progression, cancellation, wrong-direction handling, unexpected destinations, and timeouts.

Runtime tests verify handler and timer ownership, reload idempotence, and shutdown cleanup. Layout tests cover wide, medium, short-height, compact, full-screen, and restored-window states, with the map directly above the compass.

Live acceptance in the disposable `Dragons Gate HUD` profile must demonstrate:

1. walking through previously unknown rooms creates distinct clickable nodes;
2. returning through a confirmed reverse exit links correctly without duplication;
3. teleporting does not create a false directional exit;
4. resizing preserves a usable map and does not expose black gaps;
5. clicking a known room walks one confirmed step at a time;
6. `walkto <room number>` uses the same walker;
7. `walkstop`, WrongDir, an unexpected room, and disconnection stop safely;
8. updating the HUD preserves unrelated Mudlet content and mapped rooms.

## Delivery Sequence

Implementation proceeds in bounded increments: mapper model and ownership adapter; automatic standard-direction discovery; embedded responsive map; controlled room-number walker and click integration; live acceptance and updater release. Special exits and room-name search are later increments after the standard mapper is stable.
