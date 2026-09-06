#!/usr/bin/env bash
# Actions for the classic desktop right-click menu.
set -euo pipefail

desktop_dir() {
  local dir=""
  if command -v xdg-user-dir >/dev/null 2>&1; then
    dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
  fi
  if [[ -z "$dir" || "$dir" == "$HOME" || "$dir" == "$HOME/" ]]; then
    dir="$HOME/Desktop"
  fi
  mkdir -p "$dir"
  printf '%s' "$dir"
}

new_folder() {
  local dir name n
  dir="$(desktop_dir)"
  name="New folder"
  n=1
  while [[ -e "$dir/$name" ]]; do
    n=$((n + 1))
    name="New folder ($n)"
  done
  mkdir "$dir/$name"
  open_in_files "$dir"
}

open_in_files() {
  local target="${1:-}"
  [[ -n "$target" ]] || return 0
  if command -v uwsm-app >/dev/null 2>&1; then
    setsid uwsm-app -- xdg-open "$target" >/dev/null 2>&1 &
    return 0
  fi
  xdg-open "$target" >/dev/null 2>&1 &
}

open_files() {
  open_in_files "$(desktop_dir)"
}

open_terminal() {
  local dir
  dir="$(desktop_dir)"
  if command -v xdg-terminal-exec >/dev/null 2>&1; then
    setsid uwsm-app -- xdg-terminal-exec --dir="$dir" >/dev/null 2>&1 &
    return 0
  fi
  if command -v foot >/dev/null 2>&1; then
    setsid uwsm-app -- foot --working-directory="$dir" >/dev/null 2>&1 &
    return 0
  fi
  omarchy launch terminal >/dev/null 2>&1 &
}

wallpaper_file() {
  local picked theme dest_dir dest base name ext n resolved
  picked="$(omarchy file select --title "Choose wallpaper" --extensions "png jpg jpeg webp bmp gif" || true)"
  picked="${picked%%$'\n'*}"
  [[ -n "$picked" && -f "$picked" ]] || return 0

  resolved="$(realpath "$picked")"
  theme="$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"
  dest_dir="$HOME/.config/omarchy/backgrounds/${theme:-custom}"
  mkdir -p "$dest_dir"

  # Already a theme or user background: just apply it.
  case "$resolved" in
    "$dest_dir"/*|"$HOME/.local/state/omarchy/current/theme/backgrounds"/*)
      omarchy theme bg set "$resolved"
      return 0
      ;;
  esac

  base="$(basename "$resolved")"
  dest="$dest_dir/$base"
  if [[ -e "$dest" ]]; then
    name="${base%.*}"
    ext="${base##*.}"
    if [[ "$name" == "$base" ]]; then
      ext=""
    fi
    n=1
    while true; do
      if [[ -n "$ext" ]]; then
        dest="$dest_dir/${name} ($n).$ext"
      else
        dest="$dest_dir/${name} ($n)"
      fi
      [[ -e "$dest" ]] || break
      n=$((n + 1))
    done
  fi
  cp -a "$resolved" "$dest"
  omarchy theme bg set "$dest"
}

case "${1:-}" in
  new-folder)
    new_folder
    ;;
  wallpaper)
    background="$(omarchy-theme-bg-switcher)"
    [[ -n "${background:-}" ]] && omarchy-theme-bg-set "$background"
    ;;
  wallpaper-file)
    wallpaper_file
    ;;
  wallpaper-next)
    omarchy theme bg next
    ;;
  theme)
    theme="$(omarchy-theme-switcher)"
    [[ -n "${theme:-}" ]] && omarchy-theme-set "$theme" >/dev/null 2>&1 &
    ;;
  display)
    omarchy-launch-config-editor "$HOME/.config/hypr/monitors.lua"
    ;;
  files)
    open_files
    ;;
  terminal)
    open_terminal
    ;;
  *)
    echo "usage: desktop.sh new-folder|wallpaper|wallpaper-file|wallpaper-next|theme|display|files|terminal" >&2
    exit 2
    ;;
esac
