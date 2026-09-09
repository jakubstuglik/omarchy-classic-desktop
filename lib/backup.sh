#!/usr/bin/env bash
# Snapshot / restore helpers. Sourced by install.sh and uninstall.sh.

BACKUP_DIR="$STATE_DIR/backup"
BACKUP_META="$BACKUP_DIR/meta.json"
BACKUP_PRE="$BACKUP_DIR/pre"
BACKUP_STOCK="$BACKUP_DIR/stock"
OCD_DOCK_DIR="$HOME/.config/omarchy/plugins/$OCD_DOCK_ID"
OCD_FEATURES="$HOME/.config/omarchy/ocd/features.json"
OCD_REF="$HOME/.local/share/ocd/.installed-ref"

backup_exists() { [[ -f "$BACKUP_META" ]]; }

ocd_tag() {
  local tag=""
  if [[ -f "$OCD_REF" ]]; then
    tag="$(grep '^tag=' "$OCD_REF" | head -1 | cut -d= -f2-)"
  fi
  printf '%s' "${tag:-v1.2}"
}

copy_if() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  if [[ -d "$src" ]]; then
    rm -rf "$dest"
    cp -a "$src" "$dest"
  else
    cp -a "$src" "$dest"
  fi
}

json_bool() {
  [[ "$1" == "1" || "$1" == "true" ]] && echo true || echo false
}

# First install only. Re-running install.sh must not replace the original
# snapshot with overlay files, or uninstall could no longer reach OCD.
take_snapshot() {
  local force="${1:-0}"
  if backup_exists && [[ "$force" != "1" ]]; then
    log "keeping existing backup at $BACKUP_DIR"
    return 0
  fi
  if dry; then
    log "[dry-run] snapshot current OCD/Hyprland files to $BACKUP_DIR"
    return 0
  fi
  rm -rf "$BACKUP_DIR"
  mkdir -p "$BACKUP_PRE" "$BACKUP_STOCK"

  copy_if "$HYPR_MAIN" "$BACKUP_PRE/hyprland.lua"
  copy_if "$HYPR_OCD" "$BACKUP_PRE/ocd.lua"
  copy_if "$HYPR_BINDINGS" "$BACKUP_PRE/bindings.lua"
  copy_if "$HYPR_INPUT" "$BACKUP_PRE/input.lua"
  copy_if "$HYPR_CLASSIC" "$BACKUP_PRE/classic.lua"
  copy_if "$OCD_DOCK_DIR" "$BACKUP_PRE/dock"
  copy_if "$BIN_DIR/ocd-window" "$BACKUP_PRE/bin/ocd-window"
  copy_if "$BIN_DIR/ocd-raise-window" "$BACKUP_PRE/bin/ocd-raise-window"
  copy_if "$BIN_DIR/ocd-hyprbars-ensure" "$BACKUP_PRE/bin/ocd-hyprbars-ensure"
  copy_if "$BIN_DIR/ocd-hyprbars-rebuild" "$BACKUP_PRE/bin/ocd-hyprbars-rebuild"
  copy_if "$OCD_FEATURES" "$BACKUP_PRE/features.json"

  local dock_feature="true"
  if [[ -f "$OCD_FEATURES" ]]; then
    dock_feature="$(jq -r '.features.dock // true' "$OCD_FEATURES" 2>/dev/null || echo true)"
  fi
  local had_window=0 had_raise=0 had_classic=0
  [[ -e "$BIN_DIR/ocd-window" ]] && had_window=1
  [[ -e "$BIN_DIR/ocd-raise-window" ]] && had_raise=1
  [[ -e "$HYPR_CLASSIC" ]] && had_classic=1

  cat >"$BACKUP_META" <<EOF
{
  "created": "$(date -Iseconds)",
  "overlayVersion": "$VERSION",
  "ocdTag": "$(ocd_tag)",
  "hadOcdWindow": $(json_bool "$had_window"),
  "hadOcdRaiseWindow": $(json_bool "$had_raise"),
  "hadClassicLua": $(json_bool "$had_classic"),
  "dockFeature": $dock_feature
}
EOF
  log "snapshotted pre-install files to $BACKUP_DIR"
  fetch_stock_ocd || log "warning: could not fetch stock OCD files; uninstall will restore the pre-install snapshot instead"
}

fetch_stock_ocd() {
  local tag base dest
  tag="$(ocd_tag)"
  base="https://raw.githubusercontent.com/fevangelou/ocd/${tag}"
  dest="$BACKUP_STOCK"
  if dry; then
    log "[dry-run] fetch stock OCD $tag dock + ocd.lua"
    return 0
  fi
  mkdir -p "$dest/dock"
  local f
  for f in hypr/ocd.lua \
           plugin/dock/Dock.qml \
           plugin/dock/DockItem.qml \
           plugin/dock/AppMatcher.js \
           plugin/dock/manifest.json; do
    if ! curl -fsSL "$base/$f" -o "$dest/tmp"; then
      rm -f "$dest/tmp"
      return 1
    fi
    case "$f" in
      hypr/ocd.lua) mv "$dest/tmp" "$dest/ocd.lua" ;;
      plugin/dock/*) mv "$dest/tmp" "$dest/dock/${f##*/}" ;;
    esac
  done
  log "fetched stock OCD $tag files for uninstall restore"
}

restore_file() {
  local src="$1" dest="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    log "restored $dest"
  fi
}

restore_dir() {
  local src="$1" dest="$2"
  if [[ -d "$src" ]]; then
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    log "restored $dest"
  fi
}

# Drop overlay hunks that may already have been in the pre-install snapshot
# (this machine edited OCD in place before the installer existed).
strip_overlay_hunks() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if dry; then
    log "[dry-run] strip overlay hunks from $file"
    return 0
  fi
  python3 - "$file" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
orig = text

# Marked installer blocks.
text = re.sub(
    r"\n?-- >>> ocd-classic >>>\n.*?-- <<< ocd-classic <<<\n?",
    "\n",
    text,
    flags=re.S,
)

# Inline classic-desktop block previously kept at the end of hyprland.lua.
idx = text.find("-- Classic desktop: every window floats")
if idx != -1:
    text = text[:idx].rstrip() + "\n"

text = re.sub(r'\nrequire\("classic"\)\n', "\n", text)

# Tiling unbinds the overlay adds.
text = re.sub(
    r"\n-- Tiling is disabled\. These defaults would put windows back in the layout\.\n"
    r"(hl\.unbind\(\"SUPER \+ [^\"]+\"\)[^\n]*\n)+",
    "\n",
    text,
)

# Click-to-focus block (with or without the extra touchpad comments).
text = re.sub(
    r"\n-- Click-to-focus like Windows\.[^\n]*\n"
    r"hl\.config\(\{.*?\n\}\)\n",
    "\n",
    text,
    flags=re.S,
)

text = re.sub(r"\n{3,}", "\n\n", text)
if text != orig:
    path.write_text(text)
    print("stripped overlay hunks in", path)
PY
}

remove_added_files() {
  if dry; then
    log "[dry-run] remove overlay plugins, helpers, classic.lua"
    return 0
  fi
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell setPluginEnabled "$PLUGIN_ID" false || true
    omarchy-shell shell setPluginEnabled "$DESKTOP_PLUGIN_ID" false || true
  fi
  rm -rf "$PLUGIN_DST" "$DESKTOP_PLUGIN_DST"
  rm -f "$HYPR_CLASSIC"
  # OCD does not ship these helpers. Always remove the overlay copies.
  rm -f "$BIN_DIR/ocd-window" "$BIN_DIR/ocd-raise-window" "$BIN_DIR/ocd-hyprbars-ensure" "$BIN_DIR/ocd-hyprbars-rebuild"
  log "removed overlay plugins, helpers, and classic.lua"
}

restore_ocd_owned() {
  if dry; then
    log "[dry-run] restore stock OCD dock + ocd.lua"
    return 0
  fi
  if [[ -f "$BACKUP_STOCK/ocd.lua" ]]; then
    restore_file "$BACKUP_STOCK/ocd.lua" "$HYPR_OCD"
  elif [[ -f "$BACKUP_PRE/ocd.lua" ]]; then
    restore_file "$BACKUP_PRE/ocd.lua" "$HYPR_OCD"
  else
    fetch_stock_ocd || true
    [[ -f "$BACKUP_STOCK/ocd.lua" ]] && restore_file "$BACKUP_STOCK/ocd.lua" "$HYPR_OCD"
  fi

  if [[ -d "$BACKUP_STOCK/dock" && -f "$BACKUP_STOCK/dock/Dock.qml" ]]; then
    restore_dir "$BACKUP_STOCK/dock" "$OCD_DOCK_DIR"
  elif [[ -d "$BACKUP_PRE/dock" ]]; then
    restore_dir "$BACKUP_PRE/dock" "$OCD_DOCK_DIR"
  fi
}

restore_user_hypr() {
  if dry; then
    log "[dry-run] restore hyprland/bindings/input then strip overlay hunks"
    return 0
  fi
  restore_file "$BACKUP_PRE/hyprland.lua" "$HYPR_MAIN"
  restore_file "$BACKUP_PRE/bindings.lua" "$HYPR_BINDINGS"
  restore_file "$BACKUP_PRE/input.lua" "$HYPR_INPUT"
  strip_overlay_hunks "$HYPR_MAIN"
  strip_overlay_hunks "$HYPR_BINDINGS"
  strip_overlay_hunks "$HYPR_INPUT"
  marker_remove "$HYPR_MAIN" "$MARKER"
  marker_remove "$HYPR_BINDINGS" "$MARKER"
  marker_remove "$HYPR_INPUT" "$MARKER"
}

reenable_ocd_dock() {
  local want="true"
  if [[ -f "$BACKUP_META" ]]; then
    want="$(jq -r '.dockFeature // true' "$BACKUP_META" 2>/dev/null || echo true)"
  fi
  if dry; then
    log "[dry-run] set OCD dock feature=$want and enable $OCD_DOCK_ID"
    return 0
  fi
  if command -v ocd >/dev/null 2>&1; then
    if [[ "$want" == "false" ]]; then
      ocd disable dock || true
    else
      ocd enable dock || true
    fi
    ocd apply || true
  fi
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins || true
    if [[ "$want" != "false" ]]; then
      omarchy-shell shell setPluginEnabled "$OCD_DOCK_ID" true || true
    fi
    omarchy-shell shell reloadConfig || true
  fi
}
