# Load Order Facts: Plugins.txt and Creations

Load Order Facts tests a common claim about Starfield: that Vortex mods load through the script extender, that Creations load when you load a save, and that the two have separate load orders. We checked it by reading the game's own code (Starfield.exe 1.16.244) and by watching Plugins.txt in the game step by step. The answer: there is one load order, and loading a save doesn't change it.

Open the site: https://taosecurity.github.io/starfield-load-order-facts/

For AI assistants: step-by-step instructions are in [AGENTS.md](AGENTS.md).

## Example

The two scripts in this repository repeat the in-game test on your own PC. Take a snapshot before starting the game, another after each step in the game, then compare them:

    > powershell -ExecutionPolicy Bypass -File .\PluginsTxtSnapshot.ps1 00-start -AddMarker
    > powershell -ExecutionPolicy Bypass -File .\PluginsTxtSnapshot.ps1 01-menu
    > powershell -ExecutionPolicy Bypass -File .\PluginsTxtSnapshot.ps1 03-continue
    > python compare_snapshots.py
    ===== 00-start -> 01-menu
    Plugins.txt: rewritten (lines added or removed)
        -# PluginsTxtSnapshot marker - safe to delete
    ContentCatalog.txt: not changed
    ===== 01-menu -> 03-continue
    Plugins.txt: not rewritten
    ContentCatalog.txt: changed
        TM_28973af6-8caf-4a46-b0d7-a638dd412fc2: Timestamp changed
        TM_2a9007f0-fac9-4f18-bdfd-f3d9576353cc: Timestamp changed
        (one line for each installed Creation)

In our test, the game rewrote Plugins.txt when it started (the marker line vanished), and loading a save with Continue left it alone.

What's new: see the top of the [live page](https://taosecurity.github.io/starfield-load-order-facts/).

## What the page shows

- A TL;DR at the top, then a verdict for each part of the claim, with the evidence.
- Part 1, the game's code: where Starfield.exe reads Plugins.txt, the one function that rewrites it, and the two places that call that function (the Creations sync and the Creations menu).
- Part 2, the in-game test: seven snapshots of the load-order files, a marker line that shows when the game rewrites Plugins.txt, and a control step that proves the test catches a rewrite.
- The limits of the test, and what it means for your mod setup.
- Diagrams of what happens to Plugins.txt from launch to loading a save.

## Install the scripts

`PluginsTxtSnapshot.ps1` needs only Windows PowerShell, which is part of Windows. `compare_snapshots.py` needs Python 3.9 or later and nothing else.

1. Install Python 3.11 or newer from [python.org](https://www.python.org/downloads/). On the first screen of the installer, tick **Add python.exe to PATH**. To check it, open a new Command Prompt and type `python --version`.
2. Download `PluginsTxtSnapshot.ps1` and `compare_snapshots.py` from this repository into one folder.
3. Open the folder in File Explorer, click the address bar, type `powershell` and press Enter. A PowerShell window opens in that folder, ready for the commands in the Example.

Close Vortex before the test, and MO2 too unless you start the game from MO2 (see below), so only the game can change the files, and run the snapshot script from the Windows account you play on. Snapshots go to `PluginsTxtTest` on your Desktop unless you add `-OutDir <folder>`. Pass the same folder to `compare_snapshots.py` if you change it. Afterward, Vortex users deploy again to put back Vortex's order.

MO2 never deploys. If you start the game from Steam with MO2 closed, keep the default folders: the game then reads `%LOCALAPPDATA%\Starfield\Plugins.txt`, and MO2's own copy in its profile isn't touched. To watch the copy MO2 gives the game instead, start the game from MO2 and add `-PluginsDir "<MO2 folder>\profiles\<profile>"` to each snapshot command. We haven't tested whether the game's rewrites reach that file.

With `-AddMarker`, the marker line then goes into the profile's `plugins.txt`, so afterward, with MO2 closed, delete that line or copy `Plugins.txt.backup` back over the profile's file. The script still reads `ContentCatalog.txt` from `%LOCALAPPDATA%\Starfield` (change it with `-CatalogDir`), because MO2 (2.5.2 and the 2.5.3 betas) keeps no copy of it in the profile. A new test in a folder that already holds one moves the earlier test into a dated `earlier-test-...` folder.

## Words used here

- **Plugin:** a mod's data file (`.esm`, `.esp` or `.esl`).
- **Plugins.txt:** the file that lists the plugins the game loads, in order. Lines starting with `*` are active. It lives in `%LOCALAPPDATA%\Starfield`.
- **Creation:** a mod installed through the game's own Creations menu. Its plugin goes in the Data folder like any other.
- **ContentCatalog.txt:** a file next to Plugins.txt that records which Creations are installed. It doesn't hold the order.
- **SFSE:** the Starfield Script Extender, which loads DLL plugins into the game.

## The log

Add `-Verbose` to a snapshot command to print, and log to `snapshot.log` in the output folder, every file it read or couldn't find. `python compare_snapshots.py --verbose` writes `compare.log` in the same folder.

## Notes

- The page names functions, addresses and strings in Starfield.exe 1.16.244 and describes what the code does. It holds no game code or game files.
- The scripts only read, except that `-AddMarker` backs up Plugins.txt and then adds one comment line to it. The game ignores that line and drops it the next time it rewrites the file.
- The code check used [Ghidra](https://github.com/NationalSecurityAgency/ghidra), the [Bethesda Ghidra Scripts](https://github.com/1001Bits/BethesdaGhidraScripts) by 1001Bits, and [GhidraSQL](https://github.com/0xeb/ghidrasql) by Elias Bachaalany.

Found a mistake? Open an issue: https://github.com/taosecurity/starfield-load-order-facts/issues

## Credits and License

Richard Bejtlich of [Richard Presents Starfield Essentials](https://www.youtube.com/@RichardBejtlich) made this page. I am the developer, and Claude is the programmer. More Starfield tools and references are on the [Richard Presents Development Hub](https://taosecurity.github.io/).

This is an unofficial page, not made or endorsed by Bethesda. Starfield is a trademark of ZeniMax Media.

The page is a single self-contained `index.html` with no external dependencies. Its code and both scripts are MIT licensed; see [LICENSE](LICENSE).
