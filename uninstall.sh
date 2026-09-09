#!/usr/bin/env bash
# Remove omarchy-classic-desktop and restore the OCD desktop from the
# install-time snapshot (stock OCD dock + ocd.lua, pre-overlay Hyprland files
# with overlay hunks stripped). Does not uninstall OCD itself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/backup.sh
source "$ROOT/lib/backup.sh"

usage() {
  cat <<EOF
Usage: ./uninstall.sh [--dry-run] [--keep-backup]

Restore OCD as it was before this overlay:
  - stock OCD dock + hypr/ocd.lua (from the snapshot, fetched at install)
  - hyprland.lua / bindings.lua / input.lua from the pre-install snapshot,
    with overlay hunks stripped
  - overlay taskbar + desktop-menu plugins, classic.lua, and overlay helpers removed
  - OCD dock feature re-enabled

Pins in ~/.config/omarchy/ocd/dock-pins.json are left alone.

  --dry-run       Print every mutation, change nothing
  --keep-backup   Do not delete ~/.local/state/ocd-classic/backup/
EOF
}

KEEP_BACKUP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --keep-backup) KEEP_BACKUP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log "unknown flag: $1"; exit 2 ;;
  esac
done

if ! backup_exists; then
  log "no install snapshot at $BACKUP_META"
  log "will still strip overlay hunks and try to fetch stock OCD files"
  if ! dry; then
    mkdir -p "$BACKUP_STOCK"
    fetch_stock_ocd || log "warning: stock OCD fetch failed; dock/ocd.lua may stay as they are"
  fi
fi

remove_added_files
restore_user_hypr
restore_ocd_owned
reenable_ocd_dock

if dry; then
  log "[dry-run] hyprctl reload"
else
  Hyprland --verify-config >/dev/null 2>&1 || log "warning: Hyprland --verify-config failed"
  hyprctl reload >/dev/null 2>&1 || log "warning: hyprctl reload failed"
  if command -v hyprpm >/dev/null 2>&1; then
    hyprpm reload >/dev/null 2>&1 || true
  fi
  rm -f "$REF_FILE"
  if [[ "$KEEP_BACKUP" -eq 0 ]]; then
    rm -rf "$BACKUP_DIR"
    log "removed install snapshot $BACKUP_DIR"
  else
    log "kept install snapshot $BACKUP_DIR"
  fi
fi

log "omarchy-classic-desktop removed. OCD dock and titlebars should be back."
