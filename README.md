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
