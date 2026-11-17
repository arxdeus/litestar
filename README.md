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
node tools/litestar.js sync              # the latest Polestar release's guides: check, commit, install
node tools/litestar.js sync v0.4.0.2     # a given release
node tools/litestar.js build --zip       # dist/Litestar/AddOns and dist/Litestar-<version>.zip
node tools/litestar.js check             # load and walk every guide under the game stub
node tools/litestar.js install           # copy the build into the game's AddOns folder
node tools/litestar.js i18n sync|check|todo   # the Russian interface strings
```

### How sync works

`sync` takes **only the content** of a Polestar release, never its code:
the guides, the Codex, the quest and item data, the walking maps and the
Russian guide texts and names, from the release zip (checksum checked).
Litestar's engine and interface stay as they are.

1. downloads the release zip from https://github.com/fitzforge/polestar
2. checks every guide pack's format against what Litestar's engine reads
   (`Guides.FORMATS`). A release that needs a newer engine stops with
   nothing changed.
3. replaces the content folders
4. loads and walks every leveling guide for both factions in English and
   Russian; on a problem the content is put back
5. commits and installs

When Polestar changes its guide format (rare: 0.4.0 did), the engine must
be brought up once: `node tools/litestar.js sync <tag> --engine` merges that
release's code, keeps Litestar's cuts and stops on the lines both sides
changed (fix them, `git commit`, then `sync <tag>`).

Restart the game after an install: `/reload` does not load new files.

## Licence

GPL-3.0, as Polestar ([LICENSE](LICENSE), [LICENSE-EXCEPTION.md](LICENSE-EXCEPTION.md),
[THIRD_PARTY.md](THIRD_PARTY.md)). The guides, data and most of the code are
Polestar's and its contributors'.
