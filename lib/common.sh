#!/usr/bin/env bash
# Shared paths and helpers for install.sh / uninstall.sh.

PLUGIN_ID="io.github.jstuglik.taskbar"
OCD_DOCK_ID="io.github.fevangelou.ocd.dock"
MARKER="ocd-classic"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

HYPR_DIR="${HYPR_CONFIG_DIR:-$HOME/.config/hypr}"
HYPR_MAIN="$HYPR_DIR/hyprland.lua"
HYPR_OCD="$HYPR_DIR/ocd.lua"
HYPR_CLASSIC="$HYPR_DIR/classic.lua"
HYPR_BINDINGS="$HYPR_DIR/bindings.lua"
HYPR_INPUT="$HYPR_DIR/input.lua"

PLUGIN_DST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ocd-classic"
REF_FILE="$STATE_DIR/installed-ref"
OCD_DOCK_DIR="${OCD_DOCK_DIR:-$HOME/.config/omarchy/plugins/$OCD_DOCK_ID}"

DRY_RUN="${DRY_RUN:-0}"

log() { printf '%s\n' "$*" >&2; }

dry() { [[ "$DRY_RUN" == "1" ]]; }

run() {
  local desc="$1"; shift
  if dry; then
    log "[dry-run] $desc"
    return 0
  fi
  log "[run] $desc"
  "$@"
}

marker_present() {
  local file="$1" tag="$2"
  [[ -f "$file" ]] && grep -qF ">>> ${tag} >>>" "$file"
}

marker_append() {
  local file="$1" tag="$2" body="$3" prefix="${4:---}"
  if marker_present "$file" "$tag"; then
    log "marker '$tag' already in $file"
    return 0
  fi
  if dry; then
    log "[dry-run] append marker '$tag' to $file"
    return 0
  fi
  [[ -f "$file" ]] || : >"$file"
  {
    printf '\n%s >>> %s >>>\n' "$prefix" "$tag"
    printf '%s\n' "$body"
    printf '%s <<< %s <<<\n' "$prefix" "$tag"
  } >>"$file"
  log "appended marker '$tag' to $file"
}

marker_remove() {
  local file="$1" tag="$2"
  [[ -f "$file" ]] || return 0
  marker_present "$file" "$tag" || return 0
  if dry; then
    log "[dry-run] remove marker '$tag' from $file"
    return 0
  fi
  local tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v start=">>> ${tag} >>>" -v end="<<< ${tag} <<<" '
    index($0, start) { skip=1; if (buffered_blank) { buffered_blank=0 }; next }
    index($0, end) { skip=0; next }
    skip { next }
    /^$/ { buffered_blank=1; next }
    buffered_blank { print ""; buffered_blank=0 }
    { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  log "removed marker '$tag' from $file"
}
