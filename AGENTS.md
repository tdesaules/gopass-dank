# AGENTS.md

Conventions for working on this repository.

## Versioning (semver)

Always bump `plugin.json` "version" on any code change, following semver:

- **PATCH** (`0.x.y` -> `0.x.y+1`): bug fixes, no behavior change.
- **MINOR** (`0.x.y` -> `0.x+1.0`): new features or behavior changes (in 0.x, MINOR acts as the "breaking/major" bump).
- **MAJOR** (`0.x.y` -> `1.0.0`): reserved for the first stable release.

Current series is `0.x.y`: bump MINOR for new features / behavior changes, PATCH for fixes.

## Development

```sh
# Reload the plugin at runtime (no full DMS restart)
dms ipc call plugins reload gopassDank

# List plugins / check status
dms ipc call plugins list

# Live logs (to spot QML load errors)
journalctl --user -u dankmaterialshell -f
```

## Plugin structure (DankMaterialShell launcher plugin)

Proven working structure (validated against DankVault + dms-pass + DMS source):

- Root element: `QtObject` (NOT `Item`) — launcher plugins render no UI; `Item` produces a "graphical object not placed in scene" warning.
- Declare `property string pluginId: "gopassDank"` and `property var pluginService: null`.
- Notify the launcher of async updates with `root.itemsChanged()` (the `signal itemsChanged`). DMS's `Controller.qml` also listens to `pluginService.requestLauncherUpdate(pluginId)`; both work.
- `QtObject` has NO default `children` property, so child objects must be declared as properties: `property Component foo: Component { ... }` then `foo.createObject(root)`. Direct `Component { id: foo }` only works under `Item`.
- Run commands via `Process` from `Quickshell.Io` (with `SplitParser`/`StdioCollector`).
- No QML linter in this environment; verify via `dms ipc call plugins reload gopassDank` and `journalctl --user -u dms.service`.

## Known DMS bug: savePluginState

`PluginService._flushStateToDisk` calls `fv.loaded.connect(...)` where `FileView.loaded` is a bool property (not the signal), causing `Property 'connect' of object false is not a function` on first run / after reload. This is a DMS-side bug, non-fatal: the in-memory cache still works, only state persistence across reloads is affected. Cannot be fixed from the plugin side.
