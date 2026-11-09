#!/usr/bin/env bash
set -Eeuo pipefail

# Resolve paths relative to this script so it also works from a desktop shortcut.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/livesplit-proton/config"
LIVESPLIT_EXE="${LIVESPLIT_EXE:-}"

# Print a consistent error and stop before attempting a partial launch.
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  printf 'Usage: %s [--livesplit /path/to/LiveSplit.exe]\n' "$(basename "$0")"
  printf 'Path priority: argument, LIVESPLIT_EXE, config file, beside launcher, ~/Games/LiveSplit*\n'
}

# An explicit command-line path wins over environment and saved configuration.
while (($#)); do
  case "$1" in
    --livesplit)
      (($# >= 2)) || fail '--livesplit requires a path'
      LIVESPLIT_EXE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

# Find LiveSplit without requiring users to edit this script.
if [[ -z "$LIVESPLIT_EXE" && -f "$CONFIG_FILE" ]]; then
  IFS= read -r LIVESPLIT_EXE < "$CONFIG_FILE" || true
fi

if [[ -z "$LIVESPLIT_EXE" && -f "$SCRIPT_DIR/LiveSplit.exe" ]]; then
  LIVESPLIT_EXE="$SCRIPT_DIR/LiveSplit.exe"
fi

if [[ -z "$LIVESPLIT_EXE" ]]; then
  for candidate in "$HOME"/Games/LiveSplit*/LiveSplit.exe; do
    if [[ -f "$candidate" ]]; then
      LIVESPLIT_EXE="$candidate"
      break
    fi
  done
fi

# Interactive fallback is useful when the script is run from a terminal.
if [[ -z "$LIVESPLIT_EXE" && -t 0 ]]; then
  read -r -e -p 'Full path to LiveSplit.exe: ' LIVESPLIT_EXE || true
fi

[[ -n "$LIVESPLIT_EXE" && -f "$LIVESPLIT_EXE" ]] || fail 'LiveSplit.exe not found. Use --livesplit /path/to/LiveSplit.exe.'

# nsenter and sudo are needed to start LiveSplit in the game's namespaces.
command -v nsenter >/dev/null || fail 'nsenter is missing (util-linux).'
command -v sudo >/dev/null || fail 'sudo is missing.'
command -v realpath >/dev/null || fail 'realpath is missing.'

LIVESPLIT_EXE="$(realpath -e -- "$LIVESPLIT_EXE")"
LIVESPLIT_DIR="$(dirname -- "$LIVESPLIT_EXE")"

# Build a list of Wine/Proton processes that look like actual game processes.
# Steam helpers and common Wine services are excluded to avoid selecting them.
CANDIDATES=()
while IFS= read -r row; do
  [[ -n "$row" ]] || continue

  row="${row#"${row%%[![:space:]]*}"}"
  pid="${row%%[[:space:]]*}"
  cmd="${row#"$pid"}"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"

  # A readable /proc/<pid>/environ is also how we verify the process is ours to inspect.
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/environ" ]] || continue

  lower="${cmd,,}"
  [[ "$lower" == *'.exe'* && "$lower" != *'livesplit.exe'* ]] || continue
  [[ "$lower" =~ (steam\.exe|steamwebhelper\.exe|explorer\.exe|services\.exe|winedevice\.exe|plugplay\.exe|rpcss\.exe|svchost\.exe|start\.exe|conhost\.exe|cmd\.exe|taskhostw?\.exe) ]] && continue

  # Steam's compatibility environment variables distinguish game processes
  # from unrelated Windows applications running under Wine.
  tr '\0' '\n' < "/proc/$pid/environ" | grep -Eq '^(WINEPREFIX|STEAM_COMPAT_DATA_PATH)=' || continue
  CANDIDATES+=("$pid"$'\t'"$cmd")
done < <(ps -eo pid=,args=)

(("${#CANDIDATES[@]}" > 0)) || fail 'No Proton/Wine game process found. Start the game through Steam first.'

printf 'Choose the running Proton/Wine game process:\n\n'
for i in "${!CANDIDATES[@]}"; do
  printf '  %d) %s\n' "$((i+1))" "${CANDIDATES[$i]#*$'\t'}"
done

read -r -p 'Game number: ' choice || fail 'No selection.'
[[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#CANDIDATES[@]})) || fail 'Invalid selection.'

selected="${CANDIDATES[$((choice-1))]}"
GAME_PID="${selected%%$'\t'*}"
GAME_CMD="${selected#*$'\t'}"

# Read the selected process's environment. Proton supplies these values when
# Steam starts the game, so we reuse its exact loader and compatibility prefix.
read_env() {
  tr '\0' '\n' < "/proc/$GAME_PID/environ" | sed -n "s/^$1=//p" | head -n 1
}

WINELOADER="$(read_env WINELOADER)"
PROTON_PATH="$(read_env PROTON_PATH)"
WINEPREFIX="$(read_env WINEPREFIX)"
STEAM_COMPAT_DATA_PATH="$(read_env STEAM_COMPAT_DATA_PATH)"

# Some Proton versions expose PROTON_PATH but not WINELOADER directly.
if [[ -z "$WINELOADER" && -n "$PROTON_PATH" && -x "$PROTON_PATH/files/bin/wine64" ]]; then
  WINELOADER="$PROTON_PATH/files/bin/wine64"
fi

# Steam's compatdata directory contains the Wine prefix in its pfx subdirectory.
if [[ -z "$WINEPREFIX" && -n "$STEAM_COMPAT_DATA_PATH" ]]; then
  WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
fi

[[ -n "$WINEPREFIX" ]] || fail 'Could not read WINEPREFIX or STEAM_COMPAT_DATA_PATH.'
[[ -n "$WINELOADER" && -x "$WINELOADER" ]] || fail 'Could not locate the game Wine loader.'

printf '\nSelected: %s (PID %s)\nPrefix: %s\n' "$GAME_CMD" "$GAME_PID" "$WINEPREFIX"
printf 'Starting LiveSplit in the selected game namespaces. sudo may ask for your password.\n'

# Join the game's mount, PID, and environment namespaces so LiveSplit uses the
# same Proton/Wine server and filesystem view as the game. Keep the caller's
# user and group identity inside those namespaces.
#
# WINESERVERSOCKET can point at an invalid inherited socket, and LD_PRELOAD may
# contain a host-side library that cannot be loaded by the Windows process.
sudo nsenter --target "$GAME_PID" --mount --pid --env --setgid follow --setuid follow --wd="$LIVESPLIT_DIR" -- \
  /usr/bin/env -u WINESERVERSOCKET -u LD_PRELOAD "$WINELOADER" "$LIVESPLIT_EXE"
