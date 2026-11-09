#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT="$(realpath -e -- "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(dirname -- "$SCRIPT")"
LAUNCHER="$PROJECT_DIR/livesplit-proton-launcher.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/livesplit-proton"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
CONFIG="$CONFIG_DIR/config"
DESKTOP="$APP_DIR/livesplit-proton.desktop"
usage(){ printf 'Usage: %s --livesplit /path/to/LiveSplit.exe\n' "$(basename "$0")"; }
LIVE=""
while (($#)); do
 case "$1" in
  --livesplit) (($# >= 2)) || { usage >&2; exit 2; }; LIVE="$2"; shift 2 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
 esac
done
[[ -n "$LIVE" && -f "$LIVE" ]] || { printf 'Provide a valid LiveSplit.exe path.\n' >&2; exit 1; }
LIVE="$(realpath -e -- "$LIVE")"
quote_exec(){ local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }
mkdir -p "$CONFIG_DIR" "$APP_DIR"
chmod 700 "$CONFIG_DIR"
printf '%s\n' "$LIVE" > "$CONFIG.tmp"
chmod 600 "$CONFIG.tmp"
mv -f "$CONFIG.tmp" "$CONFIG"
printf '[Desktop Entry]\nName=LiveSplit (Proton)\nComment=Launch LiveSplit inside a running Proton or Wine game\nExec=%s\nTerminal=true\nType=Application\nCategories=Game;\n' "$(quote_exec "$LAUNCHER")" > "$DESKTOP"
chmod 644 "$DESKTOP"
if command -v desktop-file-validate >/dev/null 2>&1; then desktop-file-validate "$DESKTOP"; fi
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true; fi
printf 'Desktop shortcut created: %s\nLiveSplit configured: %s\n' "$DESKTOP" "$LIVE"
printf 'This helper does not install LiveSplit or any component.\n'
