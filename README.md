# LiveSplit-Proton

Launch the Windows version of [LiveSplit](https://github.com/LiveSplit/LiveSplit) inside an already-running Steam Proton or Wine game's process namespaces.

The launcher is deliberately independent of any LiveSplit component. It does not install LiveSplit, install components, or bundle game-specific files. Use it with an existing LiveSplit installation and whichever components you already use.

## Why this exists

Starting LiveSplit separately, even with the same Wine prefix, can put it in a different Wine server or Proton container. Components that inspect the game's process may then be unable to read the game. LiveSplit-Proton enters the selected game's mount and PID namespaces and starts LiveSplit with that game's Wine loader.

This is a launch workaround, not a native Linux or Wayland port of LiveSplit.

## Requirements

- A game already running through Steam Proton or a compatible Wine setup
- An existing Windows LiveSplit installation (`LiveSplit.exe`)
- Bash, `ps`, `realpath`, `grep`, `head`, `sed`, and `tr`
- `nsenter` from `util-linux`
- `sudo`

The launcher has been tested on Bazzite 44 with Steam and GE-Proton 9-27. Other distributions, Proton versions, Wine builds, and desktop environments may behave differently.

## Quick start

Make the launcher executable, then start your game from Steam and run:

```bash
chmod +x livesplit-proton-launcher.sh
./livesplit-proton-launcher.sh --livesplit "$HOME/Games/LiveSplit_1.8.37/LiveSplit.exe"
```

The launcher lists detected Proton/Wine Windows processes. Select the actual game executable, not Steam, a game launcher, an updater, or another helper. `sudo` will ask for permission to enter the selected process's namespaces.

You can also set `LIVESPLIT_EXE` in the environment, save the absolute path as the first line of `~/.config/livesplit-proton/config`, or place `LiveSplit.exe` beside the launcher. When no path is configured, the launcher also checks common `~/Games/LiveSplit*` locations.

## Optional application-menu shortcut

The optional helper creates a desktop entry and stores the LiveSplit path in the user's configuration directory. It does not copy or install LiveSplit, install components, or require administrator privileges.

```bash
chmod +x setup-desktop-entry.sh
./setup-desktop-entry.sh --livesplit "$HOME/Games/LiveSplit_1.8.37/LiveSplit.exe"
```

After that, start the game in Steam and choose **LiveSplit (Proton)** from the application menu. To change the LiveSplit installation later, run the setup helper again with the new path. The desktop entry points to the launcher in its current folder, so keep the project folder in place or rerun the helper after moving it.

If you prefer not to use a desktop shortcut, the launcher can be run directly at any time.

## Permissions and security

The launcher reads local process command lines and environment variables from `/proc` to find Wine/Proton game processes and their Wine loader/prefix. It does not upload this information or send game data to a remote service.

It invokes `sudo nsenter` to enter the selected process's mount and PID namespaces. `--setuid follow` and `--setgid follow` make the launched process follow the target process's user and group rather than running LiveSplit as root. Review the script before running it, especially on systems with a different security or namespace configuration.

## Troubleshooting

### No game processes are listed

Start the game through Steam first and wait until the actual game executable is running. The current scanner looks for Windows `.exe` command lines whose process environment contains `WINEPREFIX` or `STEAM_COMPAT_DATA_PATH`.

### Several processes are listed

Choose the actual game executable. Avoid Steam helpers, game launchers, crash handlers, and updaters. Close unrelated Proton games and retry if the list is confusing.

### The Wine loader cannot be found

The launcher reads `WINELOADER` from the selected process, or falls back to `PROTON_PATH/files/bin/wine64`. Some custom Wine setups do not expose these variables or paths in the expected form.

### LiveSplit opens but a component cannot attach to the game

Confirm that LiveSplit was started through this launcher after the game was already running. Starting LiveSplit with a separate Wine/Proton invocation may create a second Wine server. This launcher does not add game support to components; game-specific memory support remains the responsibility of each component.

## Releasing

The next version is stored in `release-version.txt` as `MAJOR.MINOR.PATCH` (for example, `0.1.0`, without the leading `v`). Committing a change to that file on `main` starts the release workflow.

The workflow validates the selected source commit, creates an annotated `vX.Y.Z` tag when needed, packages the launcher files, and creates or updates the matching GitHub Release. When a tag already exists, its tagged commit is validated and reused. An existing release keeps its notes and prerelease setting while the ZIP asset is added or replaced.

Always increment the version for new code. Published tags are not moved to different commits.

## License

This launcher is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE).

## Scope

- The launcher handles process discovery, selection, and namespace entry.
- It does not bundle or install LiveSplit.
- It does not bundle or install components.
- It does not make every game supported by every LiveSplit component.
- Successful startup does not replace testing with the target game and component.
