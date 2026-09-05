# omarchy-classic-desktop

Windows-style taskbar and floating-window behavior for [Omarchy](https://omarchy.org) 4.x, layered on [OCD](https://github.com/fevangelou/ocd) v1.2+.

This is **not** a drop-in `omarchy plugin add` package by itself. Omarchy shell plugins cannot install Hyprland Lua or helper binaries, and they have no prerequisites field. This repo is a versioned overlay: a Quickshell taskbar plugin plus an installer that wires the rest.

## Prerequisites

1. Omarchy 4.x
2. [OCD](https://github.com/fevangelou/ocd) **v1.2 or newer** (titlebars, Exposé, settings, `ocd` CLI, hyprbars)

```sh
curl -fsSL https://raw.githubusercontent.com/fevangelou/ocd/main/boot.sh | bash
ocd status
```

## Install

```sh
git clone https://github.com/jakubstuglik/omarchy-classic-desktop.git ~/Projects/omarchy-classic-desktop
cd ~/Projects/omarchy-classic-desktop
./install.sh --dry-run
./install.sh
```

The installer:

- copies the taskbar plugin as `io.github.jstuglik.taskbar`
- disables OCD’s own dock so `ocd update` does not overwrite this taskbar
- installs `~/.local/bin/ocd-window` and `ocd-raise-window`
- installs `~/.config/hypr/classic.lua` and hooks it from `hyprland.lua`
- unbinds tiling keys and sets click-to-focus
- patches OCD’s maximize button to use the work-area helper

Pins stay in `~/.config/omarchy/ocd/dock-pins.json` on each machine. They are not part of this repo.

## Uninstall

```sh
./uninstall.sh
```

OCD itself is left installed.

## Develop / version

| File | What to bump |
|---|---|
| `VERSION` | overlay release |
| `plugin/taskbar/manifest.json` `version` | same number |
| `CHANGELOG.md` | human notes |
| git tag `v0.1.0` | installable snapshot |

`omarchy plugin validate plugin/taskbar` checks the Quickshell half. Lua and helpers only apply through `./install.sh`.

After editing the live plugin on a machine, copy the working files back here, bump the version, commit, and tag.

## GitHub vs Cursor Origin

These are **different git hosts**.

| | GitHub | Cursor Origin |
|---|---|---|
| What it is | Public/private git forge | Cursor’s own git host (paid plans, early beta) |
| Public repos | Yes | **Not yet** (Internal/Private only) |
| `omarchy plugin add` / clone on another PC | Works with a public HTTPS URL | Other machines cannot pull a private Origin repo without Cursor auth |
| This overlay’s installer | `git clone` then `./install.sh` | Same, if you can clone |

**Use GitHub as the source of truth for this project.** That is how you install it on another Omarchy machine and how you could later list the taskbar QML on [plugins.omarchy.org](https://plugins.omarchy.org).

Cursor Origin is optional: create the GitHub repo, then **Sync from GitHub** in Origin so Cursor agents can browse it. Pushes on a synced repo still go to GitHub. Do not make Origin the only remote — you cannot currently publish it.

GitHub remote: https://github.com/jakubstuglik/omarchy-classic-desktop

In Cursor: Codebase → Sync from GitHub → pick this repo.

If you want Origin as a second remote later:

```sh
git remote add cursor https://origin.cursor.com/<your-codebase>/omarchy-classic-desktop.git
```

## Layout

```
plugin/taskbar/     Quickshell service (icons, pins, context menu)
bin/ocd-window      maximize/raise/minimize/fit helpers
hypr/classic.lua    float, stack, clamp
install.sh          apply on a machine that already has OCD
```

## License

GPL-3.0. The taskbar QML is derived from OCD (© 2026 Fotis Evangelou).
