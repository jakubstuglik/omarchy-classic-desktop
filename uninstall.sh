#!/usr/bin/env bash
# Remove omarchy-classic-desktop. Does not uninstall OCD itself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: ./uninstall.sh [--dry-run]"
      exit 0
      ;;
    *) log "unknown flag: $1"; exit 2 ;;
  esac
done

if dry; then
  log "[dry-run] disable and remove $PLUGIN_ID"
else
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell setPluginEnabled "$PLUGIN_ID" false || true
  fi
  if [[ -d "$PLUGIN_DST" ]]; then
    stamp="$(date +%s)"
    mv "$PLUGIN_DST" "${PLUGIN_DST}.bak.${stamp}"
    log "backed up plugin to ${PLUGIN_DST}.bak.${stamp}"
  fi
  rm -f "$BIN_DIR/ocd-window" "$BIN_DIR/ocd-raise-window" "$HYPR_CLASSIC"
  rm -f "$REF_FILE"
fi

marker_remove "$HYPR_MAIN" "$MARKER"
marker_remove "$HYPR_BINDINGS" "$MARKER"
marker_remove "$HYPR_INPUT" "$MARKER"

if dry; then
  log "[dry-run] leave ocd.lua maximize/titlebar patches in place"
  log "[dry-run] hyprctl reload"
else
  log "left $HYPR_OCD patches in place (OCD still owns that file)."
  log "Re-run 'ocd apply' if you want stock OCD maximize/titlebar behavior."
  hyprctl reload >/dev/null 2>&1 || true
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins || true
    omarchy-shell shell reloadConfig || true
  fi
fi

log "omarchy-classic-desktop removed. OCD itself is unchanged."
