'use strict';
// Copies the built Litestar (dist/Litestar/AddOns) into the game's AddOns
// folder, one Litestar* folder at a time (nothing else there is touched;
// Polestar's folders stay as WowUp or CurseForge keep them).
//
//   node tools/litestar.js install [--to <AddOns folder>]
//
// The folder: --to, else $LITESTAR_ADDONS, else the first of the usual places
// that exists (macOS and Windows installs of WoW: Forever).

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const FROM = path.join(ROOT, 'dist', 'Litestar', 'AddOns');
const PLACES = [
	'/Applications/World of Warcraft/_forever_/Interface/AddOns',
	'C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns',
	'C:/Program Files/World of Warcraft/_forever_/Interface/AddOns',
];

function target(args) {
	const at = args.indexOf('--to');
	if (at >= 0) return path.resolve(args[at + 1]);
	if (process.env.LITESTAR_ADDONS) return path.resolve(process.env.LITESTAR_ADDONS);
	const found = PLACES.find((p) => fs.existsSync(p));
	if (!found) throw new Error('the game\'s AddOns folder was not found: pass --to <folder> or set LITESTAR_ADDONS');
	return found;
}

function main(args = []) {
	if (!fs.existsSync(path.join(FROM, 'Litestar'))) throw new Error('nothing built: run node tools/litestar.js build first');
	const to = target(args);
	const names = fs.readdirSync(FROM).filter((n) => n.startsWith('Litestar'));
	for (const n of names) {
		fs.rmSync(path.join(to, n), { recursive: true, force: true });
		fs.cpSync(path.join(FROM, n), path.join(to, n), { recursive: true });
	}
	// A Litestar part the build no longer makes goes too.
	for (const n of fs.readdirSync(to)) {
		if (n.startsWith('Litestar') && !names.includes(n)) fs.rmSync(path.join(to, n), { recursive: true, force: true });
	}
	console.log(`installed ${names.length} folders into ${to}; restart the game (a /reload does not load new files)`);
}

module.exports = { main };
