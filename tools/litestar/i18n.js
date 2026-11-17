'use strict';
// The Russian interface file, addon/Polestar_ruRU/Interface.lua, kept in step
// with the code (what `forge i18n sync ruRU` and `forge i18n check` did, in
// Node so Litestar needs no Rust):
//
//   node tools/litestar.js i18n sync     adds the keys the code gained (commented
//                                        out: shown in English until translated),
//                                        moves translations of keys it lost to the
//                                        retired block at the end
//   node tools/litestar.js i18n check    lists the keys left to translate; exit 1
//                                        when some are
//   node tools/litestar.js i18n todo     prints them, one per line
//
// The keys: every literal L["..."] / ns.LC(...) in addon/Polestar and the keys
// code looks up from data (tools/lib/i18n/keys.js).

const fs = require('node:fs');
const path = require('node:path');
const { extractKeys } = require('../lib/i18n/keys');
const { updateLocaleText, parseLocaleText } = require('../lib/i18n/files');

const ROOT = path.join(__dirname, '..', '..');
const CORE = path.join(ROOT, 'addon', 'Polestar');
const FILE = path.join(ROOT, 'addon', 'Polestar_ruRU', 'Interface.lua');

// { key: value } of every translated line in another copy of the file (the
// release's, during a sync): fills the keys this one has left to translate.
function translationsIn(text) {
	const out = {};
	try {
		const doc = parseLocaleText(text, 'release');
		for (const g of doc.groups) for (const l of g.lines) if (l.kind === 'entry' && l.value) out[l.key] = l.value;
	} catch (e) {
		// Not in the layout: nothing to take.
	}
	return out;
}

function sync({ quiet = false, fill = {} } = {}) {
	const keys = extractKeys(CORE);
	const text = fs.readFileSync(FILE, 'utf8');
	const r = updateLocaleText({ text, file: path.relative(ROOT, FILE), keys, fill });
	if (r.text !== text) fs.writeFileSync(FILE, r.text);
	if (!quiet) console.log(`ruRU: ${r.added.length} keys added, ${r.retired.length} retired, ${r.dropped.length} dropped`);
	return r;
}

function todo() {
	const doc = parseLocaleText(fs.readFileSync(FILE, 'utf8'), FILE);
	const out = [];
	for (const g of doc.groups) for (const l of g.lines) if (l.kind === 'todo') out.push(l.key);
	return out;
}

function check() {
	const keys = extractKeys(CORE);
	const doc = parseLocaleText(fs.readFileSync(FILE, 'utf8'), FILE);
	const have = new Set();
	let done = 0;
	for (const g of doc.groups) for (const l of g.lines) {
		if (l.kind === 'entry') { have.add(l.key); done++; }
		if (l.kind === 'todo') have.add(l.key);
	}
	const missing = [...keys.keys()].filter((k) => !have.has(k));
	const left = todo();
	console.log(`ruRU: ${done}/${keys.size} translated, ${left.length} to translate, ${missing.length} not in the file (run i18n sync)`);
	return left.length === 0 && missing.length === 0;
}

function main(args) {
	const cmd = args[0] || 'check';
	if (cmd === 'sync') sync();
	else if (cmd === 'todo') for (const k of todo()) console.log(k);
	else if (cmd === 'check') process.exitCode = check() ? 0 : 1;
	else throw new Error(`i18n: unknown command ${cmd} (sync, check, todo)`);
}

module.exports = { sync, check, todo, main, translationsIn, FILE };
