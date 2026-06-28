# AGENTS.md

Conventions for working on this repository.

## Versioning (semver)

Always bump `plugin.json` "version" on any code change, following semver:

- **PATCH** (`x.y.z` -> `x.y.z+1`): bug fixes, no behavior change.
- **MINOR** (`x.y.z` -> `x.y+1.0`): new features, backward compatible.
- **MAJOR** (`x.y.z` -> `x+1.0.0`): breaking changes.

Current series is `1.x.y` (stable). Released versions are documented in `CHANGELOG.md`.

## Development

```sh
# Reload the plugin at runtime (no full DMS restart)
dms ipc call plugins reload gopassDank

# List plugins / check status
dms ipc call plugins list

# Live logs (to spot QML load errors)
journalctl --user -u dms.service -f
```

## Plugin structure (DankMaterialShell launcher plugin)

Proven working structure (validated against DankVault + dms-pass + DMS source):

- Root element: `QtObject` (NOT `Item`) — launcher plugins render no UI; `Item` produces a "graphical object not placed in scene" warning.
- Declare `property string pluginId: "gopassDank"` and `property var pluginService: null`.
- Notify the launcher of async updates with `pluginService.requestLauncherUpdate(pluginId)`. DMS's `Controller.qml` listens to this signal (verified against the DMS source). A custom `itemsChanged` signal is **not** wired by DMS — do not rely on it.
- Although launcher plugins are headless, they can spawn `FloatingWindow`s on demand via a `property Component dlg: Component { FloatingWindow { ... } }` + `dlg.createObject(root)`. This is how the passphrase and edit dialogs are rendered (proven working). Keyboard focus is acquired with `Qt.callLater(() => field.forceActiveFocus())`.
- `QtObject` has NO default `children` property, so child objects must be declared as properties: `property Component foo: Component { ... }` then `foo.createObject(root)`. Direct `Component { id: foo }` only works under `Item`.
- Do NOT load sibling QML files with `Qt.createComponent(Qt.resolvedUrl("..."))` — on this host `/home` is a symlink to `var/home` and Qt emits "File name case mismatch". Inline components in a `property Component` instead.
- Pass environment variables to a `Process` with the `environment: ({ "KEY": value })` syntax (object map). Inject the age passphrase as `GOPASS_AGE_PASSWORD` to fully bypass `pinentry`.
- Run commands via `Process` from `Quickshell.Io` (with `SplitParser`/`StdioCollector`).
- No QML linter in this environment; verify via `dms ipc call plugins reload gopassDank` and `journalctl --user -u dms.service`.

## Known DMS bug: savePluginState

`PluginService._flushStateToDisk` calls `fv.loaded.connect(...)` where `FileView.loaded` is a bool property (not the signal), causing `Property 'connect' of object false is not a function` on first run / after reload. This is a DMS-side bug, non-fatal: the in-memory cache still works, only state persistence across reloads is affected. Cannot be fixed from the plugin side.
