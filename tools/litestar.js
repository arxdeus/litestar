#!/usr/bin/env node
'use strict';
// Builds Litestar, the slim build of Polestar, as its own addon so it never
// clashes with Polestar installed beside it (or updated by WowUp/CurseForge):
//
//   node tools/litestar.js [--out dist/Litestar] [--zip]
//
// The source tree stays Polestar (forge, the guides' compiler and the tests
// keep working, and upstream guide updates merge). This copies every shipped
// addon folder from addon/ (plus Polestar_Codex and Polestar_QuestDB when
// present) to <out>/AddOns, renaming as it goes:
//   * folders and TOCs Polestar* -> Litestar*
//   * every identifier with Polestar in it: the global table (Polestar ->
//     Litestar), frame and button names (PolestarGuideFrame ->
//     LitestarGuideFrame), SavedVariables (PolestarDB -> LitestarDB), binding
//     names (POLESTAR_NEXT -> LITESTAR_NEXT), TOC metadata keys
//     (X-Polestar-Pack -> X-Litestar-Pack), media paths
//   * the slash commands: /litestar and /lite (no /pole, no /way, no /rl)
//   * the name players read: "Polestar" -> "Litestar" in titles, notes and
//     the interface strings (English and Russian)
//   * the wordmark texture, engraved "LITESTAR"
// A fresh SavedVariables name means Litestar starts with its own settings and
// progress: nothing is read from or written to Polestar's.

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'addon');

const args = process.argv.slice(2);
const outIdx = args.indexOf('--out');
const OUT = path.resolve(outIdx >= 0 ? args[outIdx + 1] : path.join(ROOT, 'dist', 'Litestar'));
const ADDONS_OUT = path.join(OUT, 'AddOns');

// The folders that ship: the core, our guides and their parts, the walking
// router and its maps, Russian, the item data, and the two data addons a
// player gets from a Polestar release (copied in from the client by hand).
function shipped() {
	const names = fs.readdirSync(SRC).filter((n) => n.startsWith('Polestar') && fs.existsSync(path.join(SRC, n, `${n}.toc`)));
	return names.sort();
}

// Text replacements, most specific first. Applied to .lua, .xml and .toc.
const TEXT_RULES = [
	// Slash commands: only /litestar and /lite; /way and /rl belong to TomTom
	// and the like, and a second guide addon must not take them.
	[/SLASH_POLESTAR1 = "\/polestar"/g, 'SLASH_LITESTAR1 = "/litestar"'],
	[/SLASH_POLESTAR2 = "\/pole"/g, 'SLASH_LITESTAR2 = "/lite"'],
	[/SLASH_POLESTAR_RL1 = "\/rl"/g, 'SLASH_LITESTAR_RL1 = "/litestar-reload"'],
	[/SLASH_POLESTARWAY1 = "\/way"/g, 'SLASH_LITESTARWAY1 = "/litestar-way"'],
	[/\/polestar\b/g, '/litestar'],
	[/\/pole\b/g, '/lite'],
	// Identifiers and names, every case.
	[/POLESTAR/g, 'LITESTAR'],
	[/Polestar/g, 'Litestar'],
	[/polestar_(upgrade|step_item|quest_needed|kept_item)/g, 'litestar_$1'],
];

// Lowercase "polestar" also names the house skin and the map medallion pack
// ("polestar" as a value); those stay, they are internal keys, not names.
function transformText(text) {
	let out = text;
	for (const [re, to] of TEXT_RULES) out = out.replace(re, to);
	return out;
}

function renameName(n) {
	return n.replace(/^Polestar/, 'Litestar');
}

function copyTree(from, to) {
	fs.mkdirSync(to, { recursive: true });
	for (const ent of fs.readdirSync(from, { withFileTypes: true })) {
		if (ent.name === '.DS_Store') continue;
		const src = path.join(from, ent.name);
		const dst = path.join(to, renameName(ent.name));
		if (ent.isDirectory()) {
			copyTree(src, dst);
		} else if (/\.(lua|xml|toc)$/i.test(ent.name)) {
			// latin1 maps every byte to one char and back: the walking maps' Lua
			// strings hold compressed binary data, which a UTF-8 round trip mangles
			// (DecompressString errors in game). Every rule matches ASCII only.
			fs.writeFileSync(dst, Buffer.from(transformText(fs.readFileSync(src, 'latin1')), 'latin1'));
		} else {
			fs.copyFileSync(src, dst);
		}
	}
}

// Litestar's own wordmark, engraved as Polestar's is (tools/media/ui.js).
function writeWordmarks(coreDir) {
	const { engrave } = require('./media/ui');
	const dir = path.join(coreDir, 'Media', 'UI');
	engrave({ capH: 22, bold: 0.8, tracking: 0.15, text: 'LITESTAR' }).write(path.join(dir, 'wordmark.tga'));
	engrave({ capH: 15, bold: 0.6, tracking: 0.16, text: 'LITESTAR' }).write(path.join(dir, 'wordmark-small.tga'));
}

// The core's TOC: Litestar's own title, notes and author, no update site.
function fixCoreToc(coreDir) {
	const toc = path.join(coreDir, 'Litestar.toc');
	let t = fs.readFileSync(toc, 'utf8');
	t = t.replace(/^## Notes: .*$/m, '## Notes: Slim leveling guides for World of Warcraft: Forever (a Polestar fork): guides, the arrow, class spell hints.')
		.replace(/^## Notes-ruRU: .*$/m, '## Notes-ruRU: Облегчённые гайды по прокачке для World of Warcraft: Forever (форк Polestar): гайды, стрелка, подсказки по спеллам.')
		.replace(/^## Author: .*$/m, '## Author: Litestar')
		.replace(/^## X-Website: .*\n/m, '')
		.replace(/^## OptionalDeps: .*$/m, '## OptionalDeps: TomTom, OpenMap');
	fs.writeFileSync(toc, t);
}

function main() {
	fs.rmSync(OUT, { recursive: true, force: true });
	fs.mkdirSync(ADDONS_OUT, { recursive: true });
	const names = shipped();
	for (const n of names) copyTree(path.join(SRC, n), path.join(ADDONS_OUT, renameName(n)));
	const core = path.join(ADDONS_OUT, 'Litestar');
	writeWordmarks(core);
	fixCoreToc(core);
	// Nothing named Polestar may be left in what the game loads (comments and
	// strings included), except the credit in the core's notes.
	const left = [];
	const walk = (d) => {
		for (const e of fs.readdirSync(d, { withFileTypes: true })) {
			const f = path.join(d, e.name);
			if (e.isDirectory()) walk(f);
			else if (/\.(lua|xml|toc)$/i.test(e.name)) {
				const lines = fs.readFileSync(f, 'latin1').split('\n');
				lines.forEach((l, i) => { if (/Polestar|POLESTAR/.test(l) && !/^## Notes(-ruRU)?: /.test(l)) left.push(`${path.relative(ADDONS_OUT, f)}:${i + 1}`); });
			}
		}
	};
	walk(ADDONS_OUT);
	if (left.length) throw new Error(`Polestar left in ${left.length} lines, first: ${left.slice(0, 5).join(', ')}`);
	console.log(`wrote ${path.relative(ROOT, ADDONS_OUT)}: ${names.map(renameName).join(', ')}`);
	if (args.includes('--zip')) {
		const version = (fs.readFileSync(path.join(core, 'Litestar.toc'), 'utf8').match(/^## Version: (\S+)/m) || [])[1] || 'dev';
		const zip = path.join(path.dirname(OUT), `Litestar-${version}.zip`);
		fs.rmSync(zip, { force: true });
		execFileSync('zip', ['-qrX', zip, ...names.map(renameName)], { cwd: ADDONS_OUT });
		console.log(`wrote ${path.relative(ROOT, zip)}`);
	}
}

main();
