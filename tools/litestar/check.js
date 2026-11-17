'use strict';
// The Litestar checks: the built addons (dist/Litestar/AddOns, or --dir) loaded
// the way the client loads them, under the game stub in tests/lua/, for a
// character of each faction, in English and in Russian. For each it reads:
//
//   * every Lua error while loading, logging in and walking the guides
//   * every guide pack the core refused, and every guide it dropped
//   * every leveling guide this character can follow, loaded and walked step
//     by step (Engine.Goto on each), with any error
//   * the guides window, the guide window's menu and the Settings panel opened
//
//   node tools/litestar.js check [--dir <AddOns folder>] [--quick]
//
// --quick walks only the first guide of each character. Exit 1 on any finding.

const fs = require('node:fs');
const path = require('node:path');
const { runAddon } = require('../../tests/helpers/lua');

const ROOT = path.join(__dirname, '..', '..');

const CHARACTERS = [
	{ race: 'Human', faction: 'Alliance', part: 'Human', class: 'WARRIOR', locale: 'enUS' },
	{ race: 'Orc', faction: 'Horde', part: 'Orc', class: 'HUNTER', locale: 'ruRU' },
	{ race: 'NightElf', faction: 'Alliance', part: 'NightElf', class: 'DRUID', locale: 'ruRU' },
	{ race: 'Scourge', faction: 'Horde', part: 'Scourge', class: 'MAGE', locale: 'enUS' },
];

function one(dir, c, quick) {
	const name = (n) => ({ name: n, dir: path.join(dir, n) });
	const parts = ['Litestar', 'Litestar_Guides', `Litestar_Guides_${c.faction}`, `Litestar_Guides_${c.part}`];
	for (const extra of ['Litestar_Codex', 'Litestar_QuestDB', 'Litestar_ItemDB']) if (fs.existsSync(path.join(dir, extra))) parts.push(extra);
	if (c.locale === 'ruRU') parts.splice(1, 0, 'Litestar_ruRU');
	const program = {
		stubs: ['stub_world.lua', 'stub_settings.lua', 'stub_encoding.lua'],
		addons: parts.map(name),
		before: `${c.locale === 'ruRU' ? 'function GetLocale() return "ruRU" end' : ''}
			local w = stub.world; w.race, w.raceName, w.class, w.className, w.faction = "${c.race}", "${c.race}", "${c.class}", "${c.class}", "${c.faction}"; w.level = 1`,
		script: `
			local found = {}
			local function note(s) found[#found + 1] = s end
			local function try(what, f) local ok, e = pcall(f) if not ok then note(what .. ": " .. tostring(e):sub(1, 300)) end end
			local P = Litestar
			if not P then emit({ found = { "Litestar did not load" } }) return end
			try("login", function() stub.login(); stub.fire("QUEST_LOG_UPDATE"); stub.advance(2) end)
			local G, E = P.Guides, P.Engine
			for _, r in ipairs(G.Packs()) do
				if r.status ~= "on" and r.status ~= "off" then note("pack " .. tostring(r.id) .. ": " .. tostring(r.status) .. " " .. tostring(r.reason)) end
				for _, p in ipairs(r.problems or {}) do note("pack " .. tostring(r.id) .. ": " .. tostring(p.message):sub(1, 200)) end
			end
			local player = P.Compat.GetPlayerInfo()
			local walked, steps = 0, 0
			for _, g in ipairs(G.List()) do
				if (g.category or "Leveling") == "Leveling" and G.GuideMatches(g, player) and not (${quick ? 'true' : 'false'} and walked > 0) then
					walked = walked + 1
					try("load " .. g.id, function()
						E.SetGuide(g.id)
						stub.advance(0.1)
						local full = G.Get(g.id)
						for i = 1, #full.steps do
							local ok, e = pcall(E.Goto, i)
							if not ok then note(g.id .. " step " .. i .. ": " .. tostring(e):sub(1, 200)) break end
							steps = steps + 1
						end
					end)
				end
			end
			try("guides window", function()
				P.UI.ShowGuides("guides"); P.UI.ShowGuides("packs"); P.UI.ShowGuides("quests"); P.UI.GuidesWindow:Hide()
			end)
			try("window menu", function() P.UI.GuideFrame.menuButton:Click() end)
			try("settings", function() Settings.OpenToCategory(stub.settings.categories[1].id) end)
			emit({ found = found, guides = #G.List(), walked = walked, steps = steps })
		`,
	};
	try {
		const [r] = runAddon(program).emitted;
		return r || { found: ['no result'] };
	} catch (e) {
		return { found: [String(e.stderr || e.message).split('\n').slice(0, 4).join(' ')] };
	}
}

function main(args) {
	const at = args.indexOf('--dir');
	const dir = path.resolve(at >= 0 ? args[at + 1] : path.join(ROOT, 'dist', 'Litestar', 'AddOns'));
	if (!fs.existsSync(path.join(dir, 'Litestar', 'Litestar.toc'))) throw new Error(`no Litestar build in ${dir}: run node tools/litestar.js build first`);
	const quick = args.includes('--quick');
	let bad = 0;
	for (const c of CHARACTERS) {
		const r = one(dir, c, quick);
		const label = `${c.race} ${c.class.toLowerCase()} (${c.locale})`;
		if (r.found.length) {
			bad += r.found.length;
			console.log(`FAIL ${label}: ${r.found.length} problem(s)`);
			for (const f of r.found.slice(0, 12)) console.log(`     ${f}`);
		} else {
			console.log(`ok   ${label}: ${r.guides} guides, ${r.walked} walked, ${r.steps} steps`);
		}
	}
	process.exitCode = bad ? 1 : 0;
	return bad === 0;
}

module.exports = { main };
