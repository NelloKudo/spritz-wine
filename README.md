# Spritz-Wine

A custom Wine build aimed at making certain games work without Proton,
while staying up to date with the latest Wine-Staging.

## Download

- [AUR](https://aur.archlinux.org/packages/spritz-wine-bin)
- [Releases](https://github.com/NelloKudo/spritz-wine/releases)

Spritz-Wine builds are also available in all [an-anime-team](https://github.com/an-anime-team)'s game launchers.

## Features:

- Rebased on the **latest Wine-Staging**
- Game compatibility fixes from various Proton forks
- Supports both **Fsync** and **NTsync** in the same build, with NTsync used by default if available
- Many of Wine-TkG's fixes
- Fixes for running games without Proton (e.g. games that depend on `steam.exe`)

## Usage

Extract the release tarball anywhere, then either:

- Point your launcher (Lutris, Bottles, ...) at the extracted folder as a custom Wine runner
- Run it directly:

```bash
WINEPREFIX=~/game1 /path/to/spritz-wine/bin/wine game.exe
```

## Useful environmental variables

- Sync methods:
  - `WINENTSYNC=0`: disable NTsyc and fall back to fsync
  - `WINEFSYNC=0`: disable fsync and fall back to server sync

- Spritz patches:
  - `WINE_ENABLE_TIMEOUT_FIX=1`: experimental timeout fix, for when GI / ZZZ won't launch
  - `WINE_ENABLE_STEAM_STUB=1`: launch the executable through the bundled `steam.exe` launcher
  - `WINE_DISABLE_DISCONNECT=1`: disable the disconnect workaround where it's enabled by default

- Proton-like patches:
  - `PROTON_ENABLE_HIDRAW=1`: enables hidraw, fixes missing PlayStation button glyphs in some games
  - `PROTON_PREFER_SDL=1`: prefer SDL over hidraw (default)
  - `PROTON_DISABLE_HIDRAW=1`: disable hidraw (default)
  

## Builds description

Spritz builds are built in a Docker container based on Proton's SDK, with a few changes you can see in the Dockerfile. The `wine-builder` container is hosted [here](https://hub.docker.com/r/nellokudo/wine-builder), built from its apposite [GitHub repository](https://github.com/NelloKudo/winebuilder-image).

Many thanks to spectator's work in the [main repository](https://github.com/NelloKudo/WineBuilder) for the polished building process.
