# Agent notes — omarchy-classic-desktop

This file is for anyone (human or agent) changing this repo. Read it before editing.

## What this is

A **versioned overlay** on [OCD](https://github.com/fevangelou/ocd) v1.2+ for Omarchy 4.x. It is **not** a single Omarchy marketplace plugin.

Omarchy's `omarchy plugin add` only clones QML. It cannot declare prerequisites, install Hyprland Lua, or drop binaries. This repo's `install.sh` does that.

**Prerequisite:** OCD must already be installed (`ocd status` shows v1.2 or newer).

**Source of truth:** GitHub — https://github.com/jakubstuglik/omarchy-classic-desktop  
Cursor Origin is an optional mirror only. Origin cannot host public repos yet.

## Layout

```
plugin/taskbar/     Quickshell service id: io.github.jstuglik.taskbar (hover miniatures when an icon has 2+ windows)
bin/ocd-window      maximize / raise / minimize / fit helpers
hypr/classic.lua    float, stack, one-shot open fit, titlebar double-click maximize
install.sh          apply overlay; snapshot OCD files first
uninstall.sh        restore OCD from that snapshot
lib/backup.sh       snapshot / fetch stock OCD / strip overlay hunks
```

Live copies after install:

- `~/.config/omarchy/plugins/io.github.jstuglik.taskbar/`
- `~/.config/hypr/classic.lua` (hooked from `hyprland.lua` via `>>> ocd-classic >>>`)
- `~/.local/bin/ocd-window`, `ocd-raise-window`
- snapshot: `~/.local/state/ocd-classic/backup/` (`pre/` + `stock/`)

## Do not

- Edit OCD's own plugin in place (`io.github.fevangelou.ocd.dock`). `ocd update` will overwrite it. This overlay **disables** that dock and ships a new id.
- Put machine pins in git. `~/.config/omarchy/ocd/dock-pins.json` and `appid-overrides.json` stay per-machine.
- Refresh the first-install snapshot on every `./install.sh`. That snapshot is how uninstall gets back to OCD. Use `--rebackup` only on purpose.
- Ship this as `omarchy plugin add` unless you split out **only** the QML taskbar and document OCD as a manual prerequisite.
- Edit `/usr/share/omarchy/` (package-owned).

## Workflow

1. Change files **in this repo**, or copy working live plugin files back here before committing.
2. `omarchy plugin validate plugin/taskbar`
3. `./install.sh --dry-run` then `./install.sh` on a test machine.
4. Bump version (see below), conventional commit, tag, push.

Uninstall restore: `./uninstall.sh --dry-run` then `./uninstall.sh`. That restores stock OCD dock + `ocd.lua`, strips overlay hunks from Hyprland files, removes helpers, re-enables OCD dock. Pins are left alone.

## Versioning

Keep these in lockstep for every release:

| File | What |
|---|---|
| `VERSION` | `X.Y.Z` |
| `plugin/taskbar/manifest.json` `version` | same |
| `CHANGELOG.md` | human notes |
| git tag `vX.Y.Z` | annotated tag, pushed |

While the major version is 0:

- `feat` → bump **minor** (`0.1.1` → `0.2.0`)
- `fix` / `docs` that ship with code fixes → bump **patch** (`0.1.1` → `0.1.2`)
- breaking overlay/install contract → bump **minor** and say so in the commit body (`BREAKING CHANGE:`)

`docs`-only or `chore`-only commits do not need a version bump.

## Conventional commits

Every commit message uses [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(optional-scope): <imperative summary>

optional body
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`.

Scopes (use when it helps): `taskbar`, `hypr`, `install`, `uninstall`.

Examples:

```
feat(taskbar): group windows by app identity

fix(hypr): keep maximized windows in the work area

docs: document uninstall snapshot paths

chore: ignore backup files
```

Rules:

- Subject in imperative, lowercase after the colon, no trailing period.
- One logical change per commit.
- Do not rewrite already-pushed `main` history.

## License

GPL-3.0. Taskbar QML is derived from OCD (© 2026 Fotis Evangelou). Keep that attribution in file headers.
