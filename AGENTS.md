# Litestar: for coding agents

Litestar is a slim build of Polestar (https://github.com/fitzforge/polestar),
a leveling guide addon for WoW: Forever. Read README.md first.

- `addon/Polestar*` is Polestar's tree, trimmed. Keep it Polestar-named:
  `tools/litestar/build.js` renames everything to Litestar when it builds.
  `node tools/litestar.js sync` takes only the content of Polestar releases;
  `sync <tag> --engine` merges Polestar's code, only when a release's guides
  need a newer engine (a new pack format).
- Code changes go in `addon/Polestar/`. The data folders (`Polestar_Guides*`,
  `Polestar_Nav*`, `Polestar_ItemDB`, and the Codex/QuestDB, which git
  ignores) come from Polestar's release zip: never edit them, a sync replaces
  them.
- Interface strings: `L["..."]` in code, then `node tools/litestar.js i18n sync`
  and translate the new keys in `addon/Polestar_ruRU/Interface.lua`.
- Only the game's own UI: Blizzard templates, MenuUtil, StaticPopup, the
  Settings panel. No custom skins or windows.
- Nothing that taints the game's secure UI: frames under a game frame through
  `ns.CreateFrameUnder`, no `ShowUIPanel`/`HideUIPanel` on our frames, no menu
  titles or dividers in combat (`W.MenuTitle`, `W.MenuDivider`).
- Check before committing: `node tools/litestar.js build && node tools/litestar.js check`.
- `tools/litestar/sync.js` KEEP lists what the repository holds; a file
  outside it is removed on the next sync.
