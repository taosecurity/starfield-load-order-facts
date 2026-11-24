# AGENTS.md: Load Order Facts

Instructions for AI assistants working with this repository.

1. **What it is:** a static web page (`index.html`, published with GitHub Pages at https://taosecurity.github.io/starfield-load-order-facts/) and two small scripts, `PluginsTxtSnapshot.ps1` and `compare_snapshots.py`.
   - The page shows, from Starfield.exe 1.16.244's code and an in-game test, that Starfield has one load order: the game reads Plugins.txt itself at startup, Creations sit in the same Plugins.txt, and loading a save doesn't change it. The game rewrites Plugins.txt at every launch and after an in-game Creations reorder.
   - Use the page to answer questions about when Starfield reads or rewrites Plugins.txt.
   - Use the scripts to repeat the test on a user's own PC, for example after a game update.
2. **Prerequisites:** Windows with Windows PowerShell 5.1 or later (built in) for `PluginsTxtSnapshot.ps1`. Python 3.9 or later (standard library only) for `compare_snapshots.py`. Starfield installed and started at least once, so `%LOCALAPPDATA%\Starfield\Plugins.txt` exists.
3. **Install:** none. Get a copy with `git clone https://github.com/taosecurity/starfield-load-order-facts.git`.
4. **Prove it works:** from the repo folder, run the line below. It prints the script's usage and exits with code 0.
   ```
   python compare_snapshots.py --help
   ```
5. **Common tasks:**
   - Before starting the game, take the first snapshot and add the marker line:
     ```
     powershell -ExecutionPolicy Bypass -File .\PluginsTxtSnapshot.ps1 00-start -AddMarker
     ```
   - After each step in the game, take a snapshot named for that step: `powershell -ExecutionPolicy Bypass -File .\PluginsTxtSnapshot.ps1 01-menu`. The page lists the seven steps we used.
   - Compare all steps: `python compare_snapshots.py`. It prints, for each pair of steps, whether Plugins.txt was rewritten and which lines changed, and which ContentCatalog.txt entries changed.
   - Troubleshoot: add `-Verbose` to a snapshot command, or `--verbose` to the compare command.
6. **Inputs:** a step name (letters, digits, dots, dashes and underscores, with at least one letter or digit; start it with a number, because steps are compared in the order of that number), and optionally `-OutDir <folder>` for the snapshot script or a folder argument for the compare script. Both default to `PluginsTxtTest` on the user's Desktop (the real one, even when OneDrive has moved it). The compare script counts only folders that hold `info.txt` as steps.
7. **Outputs:** one folder per step holding copies of `Plugins.txt`, `ContentCatalog.txt` and `StarfieldCustom.ini` plus `info.txt` (each file's modified time, size and SHA256, and whether the marker line is present). With `-AddMarker`, `Plugins.txt.backup` in the output folder: the Plugins.txt the user had when the test started. Logs: `snapshot.log` (with `-Verbose`) and `compare.log` (with `--verbose`) in the output folder. When the folder passed to the compare script doesn't exist, `compare.log` goes to the current folder, and the script prints the log's path either way. A new test in a folder that already holds one moves the earlier backup and step folders to `earlier-test-<date and time>`.
8. **Exit codes:**
   - `PluginsTxtSnapshot.ps1`: 0 when the snapshot was taken (files that are missing or couldn't be read are listed in `info.txt`); 1 when the output folder can't be created, or `-AddMarker` finds no Plugins.txt or can't back it up or mark it; 2 for a bad step name. Failures are written to `snapshot.log` too when `-Verbose` is on. If the marker is still in Plugins.txt, `-AddMarker` doesn't add a second marker, and keeps the backup (or, if the folder has none, saves the file without the marker line as the backup). Otherwise it starts a new test: an older backup is renamed `Plugins.txt.backup-<date and time of the new test>` and a fresh one is made. Step names may not be `snapshot.log`, `compare.log` or start with `Plugins.txt.backup`.
   - `compare_snapshots.py`: 0 when it compared; 1 when the folder is missing or holds fewer than two steps (also logged with `--verbose`); 2 for wrong arguments.
9. **Limits:**
   - The scripts never touch the game folder, saves or mod files, and never upload anything. The only change they make is `-AddMarker`, which backs up Plugins.txt and then adds one comment line to it. The page fetches nothing.
   - Close Vortex during a test, and MO2 too unless the game is started from MO2. MO2 never deploys; it normally gives the game its own copy of Plugins.txt through its virtual file system when the game is started from MO2. With the game started from Steam and MO2 closed, keep the default folders. To watch MO2's copy, start the game from MO2 and pass the profile folder: `-PluginsDir "<MO2 folder>\profiles\<profile>"` (and `-IniDir` the same folder if the profile has its own INI files). Whether the game's rewrites reach that file is untested. `ContentCatalog.txt` is read from `%LOCALAPPDATA%\Starfield` (`-CatalogDir` changes it), because MO2 keeps no copy of it in the profile.
   - The findings are for Steam Starfield 1.16.244. Function addresses on the page change with each game version.
   - After a test, tell a Vortex user to deploy again to put back Vortex's order. An MO2 user who kept the default folders needs to do nothing, because MO2 never deploys and keeps its own copy in the profile. An MO2 user who ran `-AddMarker` with `-PluginsDir` pointing at the profile should, with MO2 closed, delete the marker line from the profile's `plugins.txt` or copy `Plugins.txt.backup` back over it.
10. **Corrections:** open an issue at https://github.com/taosecurity/starfield-load-order-facts/issues.
