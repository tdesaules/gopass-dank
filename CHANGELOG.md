# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-06-28

First stable release.

### Added

- **Native passphrase dialog** that fully bypasses `pinentry`. The passphrase is
  captured in a DMS-styled `FloatingWindow`, injected to `gopass` through the
  `GOPASS_AGE_PASSWORD` environment variable, and cached **in memory for the
  session** so it is only entered once.
- **Copy password / Copy username / Copy TOTP** actions in the launcher context
  menu (Tab).
- **Edit secret** action — a native editor window loads the full secret content
  and saves it back through the canonical `gopass show -f` → `gopass insert -f`
  round-trip.
- **Sync vault** action — runs `gopass sync` (git pull/push) then rebuilds the
  local path cache.
- Multi-word, case-insensitive search over the whole vault.
- Local cache of secret paths, persisted across plugin reloads for instant
  display.
- Settings: configurable trigger, gopass binary path, and max results.

### Changed

- The launcher is refreshed through `pluginService.requestLauncherUpdate()`,
  the channel DMS actually listens on (replacing the unwired custom signal).
- Cleaner launcher entries: name is the last path segment, comment is the
  parent path.
- Documentation and architecture notes rewritten for the stable release.

### Removed

- Dead `itemsChanged` signal (never listened to by DMS).
- Verbose `EDIT` debug logging.

## [0.x] - Initial development

Iterative development builds prior to the first stable release.

### Added

- Launcher search over a gopass vault via the `pass` trigger.
- Background secret listing (`gopass list --flat`) and manual vault refresh.
- Clipboard copy of a secret's password (`gopass show -c`).
- Basic settings panel.

### Changed

- Multiple refactors of the plugin lifecycle and the async refresh mechanism
  (auto-refresh, manual refresh, request-launcher-update wiring).

[1.0.0]: https://github.com/tdesaules/gopass-dank/releases/tag/v1.0.0
