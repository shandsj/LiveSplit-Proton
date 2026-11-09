#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/livesplit-proton/config"
LIVESPLIT_EXE="${LIVESPLIT_EXE:-}"

fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  printf 'Usage: %s [--livesplit /path/to/LiveSplit.exe]\n' "$(basename "$0")"
  printf 'Path priority: argument, LIVESPLIT_EXE, config file, beside launcher, ~/Games/LiveSplit*\n'
}
while (($#)); do
  case "$1" in
    --livesplit) (($# >= 2)) || fail '--livesplit requires a path'; LIVESPLIT_EXE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
if [[ -z "$LIVESPLIT_EXE" && -f "$CONFIG_FILE" ]]; then IFS= read -r LIVESPLIT_EXE < "$CONFIG_FILE" || true; fi
if [[ -z "$LIVESPLIT_EXE" && -f "$SCRIPT_DIR/LiveSplit.exe" ]]; then LIVESPLIT_EXE="$SCRIPT_DIR/LiveSplit.exe"; fi
if [[ -z "$LIVESPLIT_EXE" ]]; then
  for candidate in "$HOME"/Games/LiveSplit*/LiveSplit.exe; do
    if [[ -f "$candidate" ]]; then LIVESPLIT_EXE="$candidate"; break; fi
  done
fi
if [[ -z "$LIVESPLIT_EXE" && -t 0 ]]; then read -r -e -p 'Full path to LiveSplit.exe: ' LIVESPLIT_EXE || true; fi
[[ -n "$LIVESPLIT_EXE" && -f "$LIVESPLIT_EXE" ]] || fail 'LiveSplit.exe not found. Use --livesplit /path/to/LiveSplit.exe.'
command -v nsenter >/dev/null || fail 'nsenter is missing (util-linux).'
command -v sudo >/dev/null || fail 'sudo is missing.'
command -v realpath >/dev/null || fail 'realpath is missing.'
LIVESPLIT_EXE="$(realpath -e -- "$LIVESPLIT_EXE")"
LIVESPLIT_DIR="$(dirname -- "$LIVESPLIT_EXE")"

CANDIDATES=()
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  row="${row#"${row%%[![:space:]]*}"}"
  pid="${row%%[[:space:]]*}"
  cmd="${row#"$pid"}"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/environ" ]] || continue
  lower="${cmd,,}"
  [[ "$lower" == *'.exe'* && "$lower" != *'livesplit.exe'* ]] || continue
  [[ "$lower" =~ (steam\.exe|steamwebhelper\.exe|explorer\.exe|services\.exe|winedevice\.exe|plugplay\.exe|rpcss\.exe|svchost\.exe|start\.exe|conhost\.exe|cmd\.exe|taskhostw?\.exe) ]] && continue
  tr '\0' '\n' < "/proc/$pid/environ" | grep -Eq '^(WINEPREFIX|STEAM_COMPAT_DATA_PATH)=' || continue
  CANDIDATES+=("$pid"$'\t'"$cmd")
done < <(ps -eo pid=,args=)
(("${#CANDIDATES[@]}" > 0)) || fail 'No Proton/Wine game process found. Start the game through Steam first.'
printf 'Choose the running Proton/Wine game process:\n\n'
for i in "${!CANDIDATES[@]}"; do printf '  %d) %s\n' "$((i+1))" "${CANDIDATES[$i]#*$'\t'}"; done
read -r -p 'Game number: ' choice || fail 'No selection.'
[[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#CANDIDATES[@]})) || fail 'Invalid selection.'
selected="${CANDIDATES[$((choice-1))]}"
GAME_PID="${selected%%$'\t'*}"
GAME_CMD="${selected#*$'\t'}"
read_env() { tr '\0' '\n' < "/proc/$GAME_PID/environ" | sed -n "s/^$1=//p" | head -n 1; }
WINELOADER="$(read_env WINELOADER)"
PROTON_PATH="$(read_env PROTON_PATH)"
WINEPREFIX="$(read_env WINEPREFIX)"
STEAM_COMPAT_DATA_PATH="$(read_env STEAM_COMPAT_DATA_PATH)"
if [[ -z "$WINELOADER" && -n "$PROTON_PATH" && -x "$PROTON_PATH/files/bin/wine64" ]]; then WINELOADER="$PROTON_PATH/files/bin/wine64"; fi
if [[ -z "$WINEPREFIX" && -n "$STEAM_COMPAT_DATA_PATH" ]]; then WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"; fi
[[ -n "$WINEPREFIX" ]] || fail 'Could not read WINEPREFIX or STEAM_COMPAT_DATA_PATH.'
[[ -n "$WINELOADER" && -x "$WINELOADER" ]] || fail 'Could not locate the game Wine loader.'
printf '\nSelected: %s (PID %s)\nPrefix: %s\n' "$GAME_CMD" "$GAME_PID" "$WINEPREFIX"
printf 'Starting LiveSplit in the selected game namespaces. sudo may ask for your password.\n'
sudo nsenter --target "$GAME_PID" --mount --pid --env --setgid follow --setuid follow --wd="$LIVESPLIT_DIR" -- \
  /usr/bin/env -u WINESERVERSOCKET -u LD_PRELOAD "$WINELOADER" "$LIVESPLIT_EXE"
