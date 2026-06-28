# Gopass-Dank

A [DankMaterialShell](https://danklinux.com) **launcher** plugin that lets you search,
copy and edit secrets stored in a [gopass](https://github.com/gopasspw/gopass) vault
(`age` backend) straight from the launcher bar — without ever spawning
`pinentry-qt`.

## Features

- **`pass` trigger** in the launcher to activate the plugin
- **Live, multi-word search** through the whole vault (case-insensitive)
- **Local cache** of secret paths for instant display, refreshed in the background
- **Copy actions** (Enter or Tab menu):
  - Password (`gopass show -c`)
  - Username / any body field (`gopass show -c <secret> <field>`)
  - TOTP code (`gopass totp -c`)
- **Edit secret** — a native editor window loads the full content and saves it back
  (`gopass show -f` → `gopass insert -f`)
- **Sync vault** — `gopass sync` (git pull/push) then rebuild the cache
- **Native passphrase dialog** that fully bypasses `pinentry`: the passphrase is
  captured in a DMS-styled window, injected to gopass via `GOPASS_AGE_PASSWORD`,
  and cached **in memory for the session** so you only enter it once

## Requirements

- [DankMaterialShell](https://danklinux.com) >= 1.4.0
- [gopass](https://github.com/gopasspw/gopass) >= 1.16, initialized and configured
  with the **`age`** backend (`gopass init --crypto age`)
- The vault must be unlocked/initialized (`gopass init`)

> The passphrase dialog relies on gopass's `GOPASS_AGE_PASSWORD` environment
> variable, which is specific to the age backend. The GPG backend is not supported.

## Installation

### From GitHub

```sh
mkdir -p ~/.config/DankMaterialShell/plugins
git clone https://github.com/tdesaules/gopass-dank.git ~/.config/DankMaterialShell/plugins/gopass-dank
dms restart
```

### Activation

1. Open **Settings → Plugins**
2. Click **Scan for Plugins**
3. Enable **Gopass-Dank**
4. Restart the shell: `dms restart`

## Usage

1. Open the launcher (Ctrl+Space or the launcher button)
2. Type `pass` — the plugin lists the vault's secrets
3. Refine with keywords: `pass github token`

### Selecting a secret

- **Enter** — copy the password to the clipboard
- **Tab** — open the context menu:
  | Action | Description |
  |--------|-------------|
  | **Copy password** | `gopass show -c` |
  | **Copy username** | Copies the `username` body field |
  | **Copy TOTP** | `gopass totp -c` (requires a `totp:` entry, see below) |
  | **Edit secret** | Opens a native editor window |
  | **Sync vault** | `gopass sync` then reloads the cache |

### Display format

The visible name is the last path segment; the comment is the parent path.

Example for `websites/github.com/tdesaules`:
- **Name**: `tdesaules`
- **Comment**: `websites / github.com`

### Passphrase

The first time you copy or edit a secret in a session, a native passphrase window
appears. The passphrase is then cached in memory until DMS restarts, so subsequent
copies happen instantly with no prompt. `pinentry` is never invoked.

If you enter a wrong passphrase, the dialog shows an error and lets you retry.

### TOTP

Add a `totp` key to a secret's body to enable TOTP codes:

```sh
gopass edit github/me
```
```
<password>
totp: JBSWY3DPEHPK3PXP
```

Then **Copy TOTP** generates `gopass totp -c`. The value can be a bare base32
secret or a full `otpauth://` URI.

### Editing a secret

**Edit secret** loads the full content (line 1 = password, rest = body) into an
editor window. Edit, then **Save** (button or `Ctrl+Enter`) or **Cancel**
(button or `Esc`). Saving commits and pushes to the git remote if `core.autopush`
is enabled.

## Configuration

Available in **Settings → Plugins → Gopass-Dank**:

| Setting | Description | Default |
|---------|-------------|---------|
| Trigger | Keyword that activates the plugin in the launcher | `pass` |
| Gopass Binary | Path to the `gopass` executable | `gopass` |
| Max Results | Maximum number of secrets displayed | `50` |

> After changing the trigger, reload the plugin: `dms ipc call plugins reload gopassDank`

## Architecture

```
gopass-dank/
├── plugin.json          # Plugin manifest
├── GopassLauncher.qml   # Launcher component (search, copy, edit, dialogs)
├── GopassSettings.qml   # Settings UI
├── README.md
├── CHANGELOG.md
└── LICENSE
```

### How it works

1. On load and on **Sync vault**, the plugin runs `gopass list --flat`. This lists
   secret **paths only** — no decryption, no passphrase needed. Paths are cached
   in memory and persisted via `pluginService.savePluginState` for instant display.
2. `getItems(query)` filters the cache synchronously (multi-word, case-insensitive).
3. **Copy / edit** actions need decryption, so they inject the cached passphrase
   into a short-lived `gopass` child process via `GOPASS_AGE_PASSWORD`, completely
   bypassing `pinentry`.
4. The passphrase dialog and the edit dialog are native DMS `FloatingWindow`s
   spawned by the plugin (`DankTextField` with `echoMode: Password`).

### Security model

- The secret-path cache contains **only paths** (already stored in cleartext on
  disk by gopass) — no secret material.
- The passphrase lives **only in memory** (a QML property), for the duration of
  the session. It is **never written to disk** and **never logged**.
- It is passed to `gopass` exclusively through the `GOPASS_AGE_PASSWORD`
  environment variable of a transient child process. This is comparable to
  pinentry's trust model; the exposure window is the gopass process lifetime
  (a few hundred milliseconds).
- Secret editing round-trips through `gopass show -f` → `gopass insert -f`, the
  canonical gopass read/write path, so the AKV format (line 1 = password, rest =
  body) is preserved.

## Development

```sh
# Clone the DMS source for IDE support
git clone https://github.com/AvengeMedia/DankMaterialShell.git ~/repos/DankMaterialShell

# Symlink the plugin into your plugins dir (so reloads pick up edits directly)
ln -sf "$PWD" ~/.config/DankMaterialShell/plugins/gopass-dank

# Reload the plugin after changes
dms ipc call plugins reload gopassDank

# Status
dms ipc call plugins list

# Live logs
journalctl --user -u dms.service -f
```

### Notes

- The launcher refreshes on async updates through
  `pluginService.requestLauncherUpdate(pluginId)` — the channel DMS actually
  listens on. A custom `itemsChanged` signal is **not** wired by DMS.
- A launcher plugin is headless (`QtObject`), but it can spawn `FloatingWindow`s
  on demand. This is how the passphrase and edit dialogs are rendered.

## License

MIT
