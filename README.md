# Spritz-Wine

`Spritz-Wine` is a custom Wine build aimed at making playing certain
games easier, without missing any of Wine's latest additions.

## Download

- [AUR](https://aur.archlinux.org/packages/spritz-wine-bin)
- [Releases](https://github.com/NelloKudo/spritz-wine/releases)

Spritz-Wine builds are also available in all [an-anime-team](https://github.com/an-anime-team)'s game launchers.

## Features:

- Rebased to **latest wine-staging**
- Includes fixes for games compatibility from [dwproton](https://dawn.wine/dawn-winery/dwproton)
- Bundles both **fsync/NTsync** in the same build, with NTsync used by default if available
- Includes many of Wine-TkG's fixes
- Imported a few patches from Proton, mostly aiming controllers
- Includes some QoL fixes for dropping inputs, random crashes and alt-tabbing

## Useful environmental variables

- Sync methods:
  - `WINENTSYNC=0`: disables NTsync, fallbacks to fsync
  - `WINEFSYNC=0`: disables fsync, fallbacks to server sync

- Spritz patches:
  - `WINE_ENABLE_TIMEOUT_FIX=1`: enables experimental timeout fix when needed (GI/ZZZ not launching)
  - `WINE_ENABLE_STEAM_STUB=1`: launches the executable using the `steam.exe` stub in the builds
  - `WINE_USE_WINEDMO=1`: enables the winedmo renderer backend
  - `WINE_DISABLE_DISCONNECT=1`: disables the disconnecting trick when enabled by default
  - `WINE_ENABLE_DISCONNECT=1`: enables the disconnecting trick

- Proton imported patches:
  - `PROTON_PREFER_SDL=1`: uses SDL instead of hidraw, disabling it (already default)
  - `PROTON_DISABLE_HIDRAW=1`: disables hidraw (already default)
  - `PROTON_ENABLE_HIDRAW=1`: enables hidraw, fixes PlayStation glyphs not showing in some games

## Builds description

Spritz builds are built in a Docker container based on Proton's SDK, with a few changes you can see in the Dockerfile. The `wine-builder` container is hosted [here](https://hub.docker.com/r/nellokudo/wine-builder), built from its apposite [GitHub repository](https://github.com/NelloKudo/winebuilder-image).

Many thanks to spectator's work in the main repository for the polished building process.
