# Litestar

A slim build of [Polestar](https://github.com/fitzforge/polestar), the leveling
guide addon for World of Warcraft: Forever. Litestar keeps the guides, the
arrow and the class spell hints, and draws everything with the game's own
interface: its windows, menus, dialogs and Settings panel. English and Russian.

It installs beside Polestar and never touches it: its own folders (`Litestar*`),
its own saved settings (`LitestarDB`, `LitestarCharDB`) and its own commands
(`/litestar`, `/lite`).

## What it has

- Polestar's guides (leveling, class, professions, reputation, collectibles),
  community guide packs and import strings
- the arrow and the walking routes
- the guide window, with a transparent mode
- the guides window (the guides button in the guide window's header): guides,
  community guides, and the quests the route never hands in
- class spell hints on level-up, gear upgrade arrows in the bags (Baganator
  too)
- settings in Esc > Options > AddOns > Litestar

Cut from Polestar: the other languages, Polestar's own skins and windows,
automation, party sync, rares, talents, the recorder and bug report, map
overlays, the integrations, the target-name button.

## Commands

Needs Node 24 and a Lua 5.1 (`luajit` or `lua5.1`) for the checks.

```sh
node tools/litestar.js sync              # merge the latest Polestar release, take its data, build, check, install
node tools/litestar.js sync v0.4.0.1     # a given release
node tools/litestar.js build --zip       # dist/Litestar/AddOns and dist/Litestar-<version>.zip
node tools/litestar.js check             # load and walk every guide under the game stub
node tools/litestar.js install           # copy the build into the game's AddOns folder
node tools/litestar.js i18n sync|check|todo   # the Russian interface strings
```

### How sync works

The source tree stays Polestar's (`addon/Polestar*`), so a Polestar release
merges into it. `sync`:

1. fetches the release tag from https://github.com/fitzforge/polestar
2. merges it; Litestar's cuts stay cut without asking. A line both sides
   changed stops the sync with the list of files: fix them, `git commit`, then
   `node tools/litestar.js sync <tag> --data-only`.
3. replaces the data (guides, Codex, quest and item data, walking maps, the
   Russian guide texts and names) with the release zip's, checksum checked
4. adds the new interface strings to `addon/Polestar_ruRU/Interface.lua`
   (shown in English until translated: `i18n todo` lists them)
5. builds, checks, commits and installs

Restart the game after an install: `/reload` does not load new files.

## Licence

GPL-3.0, as Polestar ([LICENSE](LICENSE), [LICENSE-EXCEPTION.md](LICENSE-EXCEPTION.md),
[THIRD_PARTY.md](THIRD_PARTY.md)). The guides, data and most of the code are
Polestar's and its contributors'.
