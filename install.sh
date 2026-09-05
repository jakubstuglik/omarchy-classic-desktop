#!/usr/bin/env bash
# Install omarchy-classic-desktop over an existing OCD v1.2+ setup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/backup.sh
source "$ROOT/lib/backup.sh"

usage() {
  cat <<EOF
Usage: ./install.sh [--dry-run] [--keep-ocd-dock] [--rebackup]

Install the classic taskbar, window helpers, and floating/stacking Hyprland
behavior. Requires Omarchy 4.x and OCD v1.2 or newer.

First install snapshots the current OCD/Hyprland files under
~/.local/state/ocd-classic/backup/ so ./uninstall.sh can put OCD back.

  --dry-run         Print every mutation, change nothing
  --keep-ocd-dock   Leave OCD's text-tab dock enabled (two bars will show)
  --rebackup        Replace the existing uninstall snapshot (rarely needed)
EOF
}

KEEP_OCD_DOCK=0
REBACKUP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --keep-ocd-dock) KEEP_OCD_DOCK=1; shift ;;
    --rebackup) REBACKUP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log "unknown flag: $1"; usage; exit 2 ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing required command: $1"
    exit 1
  }
}

preflight() {
  need_cmd jq
  need_cmd python3
  need_cmd hyprctl
  need_cmd omarchy
  need_cmd curl

  local ver
  ver="$(omarchy version 2>/dev/null | head -1 || true)"
  case "$ver" in
    4.*) log "Omarchy $ver" ;;
    *)
      log "This overlay targets Omarchy 4.x. Detected: ${ver:-unknown}"
      exit 1
      ;;
  esac

  if ! command -v ocd >/dev/null 2>&1 && [[ ! -x "$HOME/.local/share/ocd/bin/ocd" ]]; then
    log "OCD is not installed. Install it first:"
    log "  curl -fsSL https://raw.githubusercontent.com/fevangelou/ocd/main/boot.sh | bash"
    exit 1
  fi

  local tag=""
  if [[ -f "$HOME/.local/share/ocd/.installed-ref" ]]; then
    tag="$(grep '^tag=' "$HOME/.local/share/ocd/.installed-ref" | head -1 | cut -d= -f2-)"
  fi
  if [[ -n "$tag" ]]; then
    log "OCD $tag"
    case "$tag" in
      v1.2|v1.[2-9]*|v[2-9]*) ;;
      *)
        log "Need OCD v1.2 or newer (found $tag)."
        exit 1
        ;;
    esac
  else
    log "warning: OCD installed-ref missing; assuming a recent install"
  fi
}

strip_legacy_inline_classic() {
  # This machine previously kept the floating/stacking code inline in
  # hyprland.lua (after the ocd marker). Move that to classic.lua.
  [[ -f "$HYPR_MAIN" ]] || return 0
  if marker_present "$HYPR_MAIN" "$MARKER"; then
    return 0
  fi
  if ! grep -qF 'Classic desktop: every window floats' "$HYPR_MAIN"; then
    return 0
  fi
  if dry; then
    log "[dry-run] strip inline classic-desktop block from $HYPR_MAIN"
    return 0
  fi
  local tmp
  tmp="$(mktemp "${HYPR_MAIN}.XXXXXX")"
  awk '
    index($0, "Classic desktop: every window floats") { skip=1; next }
    skip { next }
    { print }
  ' "$HYPR_MAIN" >"$tmp"
  mv "$tmp" "$HYPR_MAIN"
  log "moved inline classic-desktop block out of $HYPR_MAIN"
}

patch_ocd_lua() {
  [[ -f "$HYPR_OCD" ]] || {
    log "warning: $HYPR_OCD missing; skip hyprbars patches"
    return 0
  }
  if dry; then
    log "[dry-run] patch $HYPR_OCD (bar_part_of_window, maximize helper)"
    return 0
  fi
  python3 - "$HYPR_OCD" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
changed = False
if "bar_part_of_window" not in text:
    needle = "        bar_button_padding = 6,"
    insert = (
        "        bar_button_padding = 6,\n"
        "        -- Outside the client surface so apps that paint their own CSD\n"
        "        -- (JetBrains) cannot cover the titlebar.\n"
        "        bar_part_of_window = false,"
    )
    if needle in text:
        text = text.replace(needle, insert, 1)
        changed = True
old = "[[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })']]"
new = 'os.getenv("HOME") .. "/.local/bin/ocd-window maximize"'
if old in text:
    text = text.replace(old, new, 1)
    changed = True
if changed:
    path.write_text(text)
    print("patched", path)
else:
    print("ocd.lua already patched or pattern not found")
PY
}

install_files() {
  if dry; then
    log "[dry-run] install plugin $PLUGIN_ID"
    log "[dry-run] install helpers to $BIN_DIR"
    log "[dry-run] install $HYPR_CLASSIC"
    return 0
  fi
  mkdir -p "$PLUGIN_DST" "$BIN_DIR" "$STATE_DIR" "$HYPR_DIR"
  rm -rf "$PLUGIN_DST"
  cp -a "$ROOT/plugin/taskbar/." "$PLUGIN_DST/"
  chmod +x "$PLUGIN_DST/clients.sh"
  install -m 0755 "$ROOT/bin/ocd-window" "$BIN_DIR/ocd-window"
  install -m 0755 "$ROOT/bin/ocd-raise-window" "$BIN_DIR/ocd-raise-window"
  install -m 0644 "$ROOT/hypr/classic.lua" "$HYPR_CLASSIC"
  printf 'version=%s\nplugin=%s\n' "$VERSION" "$PLUGIN_ID" >"$REF_FILE"
  log "installed plugin, helpers, and classic.lua"
}

enable_plugin() {
  if dry; then
    log "[dry-run] enable $PLUGIN_ID, disable $OCD_DOCK_ID"
    return 0
  fi
  if [[ "$KEEP_OCD_DOCK" -eq 0 ]] && command -v ocd >/dev/null 2>&1; then
    ocd disable dock || true
    ocd apply || true
  fi
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins || true
    omarchy-shell shell setPluginEnabled "$PLUGIN_ID" true || true
    if [[ "$KEEP_OCD_DOCK" -eq 0 ]]; then
      omarchy-shell shell setPluginEnabled "$OCD_DOCK_ID" false || true
    fi
    omarchy-shell shell reloadConfig || true
  fi
}

reload_hypr() {
  if dry; then
    log "[dry-run] hyprctl reload"
    return 0
  fi
  Hyprland --verify-config >/dev/null 2>&1 || log "warning: Hyprland --verify-config failed"
  hyprctl reload >/dev/null 2>&1 || log "warning: hyprctl reload failed"
}

preflight
take_snapshot "$REBACKUP"
install_files
strip_legacy_inline_classic
marker_append "$HYPR_MAIN" "$MARKER" 'require("classic")'
marker_append "$HYPR_BINDINGS" "$MARKER" $'-- Tiling is disabled. These defaults would put windows back in the layout.\nhl.unbind("SUPER + T") -- was: toggle window floating/tiling\nhl.unbind("SUPER + J") -- was: toggle window split\nhl.unbind("SUPER + P") -- was: pseudo window\nhl.unbind("SUPER + L") -- was: toggle workspace layout (dwindle/scrolling)\nhl.unbind("SUPER + CTRL + F") -- was: tiled full screen'
marker_append "$HYPR_INPUT" "$MARKER" $'-- Click-to-focus like Windows. Hovering a window no longer steals focus.\nhl.config({\n  input = {\n    follow_mouse = 0,\n    touchpad = {\n      clickfinger_behavior = false,\n    },\n  },\n})'
patch_ocd_lua
enable_plugin
reload_hypr

log "omarchy-classic-desktop $VERSION installed."
log "Pin apps from the taskbar right-click menu. Pins stay on this machine."
log "Snapshot for uninstall: $BACKUP_DIR"
log "To return to OCD: $ROOT/uninstall.sh"
