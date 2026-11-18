'use strict';
// Brings Litestar's guides up to a Polestar release: the content only, never
// Polestar's code. Litestar's engine (addon/Polestar) stays as it is.
//
//   node tools/litestar.js sync [<tag>] [--no-install] [--force]
//   node tools/litestar.js sync <tag> --engine     (rare: also merge Polestar's code)
//
// <tag>: a Polestar release tag (v0.4.0.2); none: the latest release on GitHub.
//
//   1. the release zip from GitHub, its SHA256SUMS checked
//   2. compatibility: every guide pack's format (X-Polestar-Format) must be one
//      Litestar's engine reads (Guides.FORMATS in addon/Polestar/Core/
//      Guides.lua), and the data addons' versions must be the release's; a
//      newer format stops the sync with nothing changed (the guides would be
//      refused in game): that release needs the engine (--engine) first
//   3. the content replaced by the release's: the guides (Polestar_Guides*),
//      the Codex, the quest and item data, the walking maps (Polestar_Nav*),
//      the Russian guide texts and names (Polestar_ruRU's Texts.lua and
//      Names.lua; its Interface.lua, the interface strings, is Litestar's)
//   4. a check that the guides load and walk under the game stub for both
//      factions and both languages (tools/litestar/check.js); on a problem
//      nothing is committed or installed and the content is put back
//   5. commit, and unless --no-install, install into the game
//
// --engine: before the content, merge the release's code into the current
// branch (git merge of the tag); Litestar's cuts are kept without asking, what
// both changed stops the sync with the list. For a release whose guides need
// a newer engine. --force: take a newer format anyway (for testing).

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync, spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..', '..');
const REPO = 'fitzforge/polestar';
const REMOTE = 'polestar';

// The addon folders Litestar ships, by source: code from the merge, data from
// the release zip (the zip's copy wins: it is what that release's code reads).
const CODE = ['Polestar'];
const DATA = [
	'Polestar_Guides', 'Polestar_Guides_Alliance', 'Polestar_Guides_Horde',
	'Polestar_Guides_Dwarf', 'Polestar_Guides_Gnome', 'Polestar_Guides_Human', 'Polestar_Guides_NightElf',
	'Polestar_Guides_Orc', 'Polestar_Guides_Scourge', 'Polestar_Guides_Skyborne', 'Polestar_Guides_Tauren', 'Polestar_Guides_Troll',
	'Polestar_Codex', 'Polestar_QuestDB', 'Polestar_ItemDB',
	'Polestar_Nav', 'Polestar_Nav_EK', 'Polestar_Nav_Kalimdor',
];
// The language folder: its guide texts and names come from the zip, its
// interface strings (Interface.lua) are Litestar's own.
const LANGUAGE = 'Polestar_ruRU';
const OWN_IN_LANGUAGE = ['Interface.lua'];

// What the repository keeps (everything else an upstream merge brings in is
// removed again: the toolchain, the site, the docs, the other languages and
// the cut features live in Polestar). Paths are prefixes.
const KEEP = [
	'addon/Polestar/', 'addon/Polestar_Looks/', 'addon/Polestar_ruRU/',
	...DATA.filter((d) => !['Polestar_Codex', 'Polestar_QuestDB'].includes(d)).map((d) => `addon/${d}/`),
	'tools/litestar.js', 'tools/litestar/',
	'data/codex/attunements.json', // the attunement notes' keys (tools/lib/i18n/keys.js)
	'tools/lib/lua.js', 'tools/lib/i18n/keys.js', 'tools/lib/i18n/files.js', 'tools/lib/i18n/locales.js',
	'tests/helpers/lua.js',
	'tests/lua/wow_stub.lua', 'tests/lua/stub_world.lua', 'tests/lua/stub_settings.lua', 'tests/lua/stub_encoding.lua',
	'.gitignore', '.gitattributes', '.editorconfig', 'LICENSE', 'LICENSE-EXCEPTION.md', 'THIRD_PARTY.md',
	'README.md', 'AGENTS.md', 'SYNC.md', 'package.json',
];
// Inside the kept core, files of features Litestar cut (a merge may bring
// them back as new files): removed again after the merge.
const CUT = [
	'addon/Polestar/Rares/', 'addon/Polestar/Talents/', 'addon/Polestar/Locales/',
];

// Litestar's own files: in a conflict, Litestar's side wins without asking.
// The Russian interface file keeps Litestar's lines; the release's
// translations fill the keys still left to translate (step 4).
const OURS = ['README.md', 'AGENTS.md', 'SYNC.md', '.gitignore', '.gitattributes', 'package.json', 'addon/Polestar_ruRU/Interface.lua'];
let upstreamRu = null;

function kept(file) {
	if (CUT.some((p) => file.startsWith(p))) return false;
	return KEEP.some((p) => (p.endsWith('/') ? file.startsWith(p) : file === p));
}

function git(args, opts = {}) {
	const out = execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: opts.stdio || ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 });
	return (out || '').trim();
}

function gitOk(args) {
	return spawnSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
}

function step(n, text) {
	console.log(`\n[${n}] ${text}`);
}

function latestTag() {
	const r = spawnSync('gh', ['release', 'view', '-R', REPO, '--json', 'tagName', '-q', '.tagName'], { encoding: 'utf8' });
	if (r.status === 0 && r.stdout.trim()) return r.stdout.trim();
	const res = spawnSync('curl', ['-fsSL', `https://api.github.com/repos/${REPO}/releases/latest`], { encoding: 'utf8' });
	if (res.status !== 0) throw new Error('could not ask GitHub for the latest Polestar release: name the tag (sync v0.4.0.1)');
	return JSON.parse(res.stdout).tag_name;
}

function fetchTag(tag) {
	if (gitOk(['remote', 'get-url', REMOTE]).status !== 0) git(['remote', 'add', REMOTE, `https://github.com/${REPO}.git`]);
	git(['fetch', '--no-tags', REMOTE, `refs/tags/${tag}:refs/tags/${tag}`], { stdio: ['ignore', 'inherit', 'inherit'] });
}

// Already merged: the tag's commit is in the current branch.
function merged(tag) {
	return gitOk(['merge-base', '--is-ancestor', `${tag}^{commit}`, 'HEAD']).status === 0;
}

// Merge `tag`; resolve what Litestar decides without asking (its cuts), leave
// the rest. -> list of files left in conflict.
function mergeCode(tag) {
	if (git(['status', '--porcelain', '--untracked-files=no'])) throw new Error('the working tree has changes: commit or stash them first');
	const r = gitOk(['merge', '--no-ff', '--no-commit', '-m', `Litestar: sync with Polestar ${tag}`, tag]);
	if (r.status !== 0 && !/CONFLICT|Automatic merge failed/.test(r.stdout + r.stderr)) throw new Error(`git merge failed:\n${r.stderr}`);
	// Unmerged paths: (stage info) decide those outside what Litestar keeps.
	const unmerged = [...new Set(git(['diff', '--name-only', '--diff-filter=U']).split('\n').filter(Boolean))];
	for (const f of unmerged) {
		if (OURS.includes(f)) {
			if (f === 'addon/Polestar_ruRU/Interface.lua') upstreamRu = gitOk(['show', `${tag}:${f}`]).stdout || null;
			gitOk(['checkout', '--ours', '--', f]);
			gitOk(['add', '--', f]);
			continue;
		}
		if (!kept(f)) {
			gitOk(['rm', '-q', '--cached', '--', f]);
			fs.rmSync(path.join(ROOT, f), { force: true });
			continue;
		}
		// Deleted in Litestar, changed upstream: Litestar's delete stands.
		const ours = gitOk(['cat-file', '-e', `HEAD:${f}`]).status === 0;
		if (!ours) {
			gitOk(['rm', '-q', '--cached', '--', f]);
			fs.rmSync(path.join(ROOT, f), { force: true });
		}
	}
	// Everything the merge added outside what Litestar keeps goes again.
	const all = git(['ls-files']).split('\n').filter(Boolean);
	const drop = all.filter((f) => !kept(f));
	for (let i = 0; i < drop.length; i += 500) gitOk(['rm', '-q', '-r', '--cached', '--ignore-unmatch', '--', ...drop.slice(i, i + 500)]);
	for (const f of drop) fs.rmSync(path.join(ROOT, f), { force: true });
	return [...new Set(git(['diff', '--name-only', '--diff-filter=U']).split('\n').filter(Boolean))];
}

// The release zip is kept in dist/cache/<tag>: a slow or broken connection
// resumes where it stopped (curl -C -, with retries), and a zip already
// downloaded and checked is not downloaded again.
const CACHE = path.join(ROOT, 'dist', 'cache');

function sha256(file) {
	return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function fetchFile(url, file, tries = 30) {
	for (let i = 1; i <= tries; i++) {
		const c = spawnSync('curl', ['-fsSL', '-C', '-', '--retry', '5', '--retry-all-errors', '--speed-time', '60', '--speed-limit', '1000', '-o', file, url], { stdio: ['ignore', 'ignore', 'inherit'] });
		if (c.status === 0) return;
		// 33: the server can't resume (or the file is already whole): start over once.
		if (c.status === 33 && fs.existsSync(file)) fs.rmSync(file);
		const have = fs.existsSync(file) ? fs.statSync(file).size : 0;
		console.log(`    ${path.basename(file)}: connection lost at ${(have / 1048576).toFixed(1)} MB, resuming (${i}/${tries})`);
	}
	throw new Error(`could not download ${url}`);
}

function download(tag, dir) {
	const version = tag.replace(/^v/, '');
	const zip = `Polestar-${version}.zip`;
	const cache = path.join(CACHE, tag);
	fs.mkdirSync(cache, { recursive: true });
	const base = `https://github.com/${REPO}/releases/download/${tag}`;
	const sumsFile = path.join(cache, 'SHA256SUMS');
	if (!fs.existsSync(sumsFile)) fetchFile(`${base}/SHA256SUMS`, sumsFile);
	const sums = fs.readFileSync(sumsFile, 'utf8');
	const want = (sums.split('\n').find((l) => l.endsWith(`  ${zip}`)) || '').split(/\s+/)[0];
	if (!want) throw new Error(`SHA256SUMS of ${tag} has no ${zip}`);
	const zipFile = path.join(cache, zip);
	if (!fs.existsSync(zipFile) || sha256(zipFile) !== want) {
		fetchFile(`${base}/${zip}`, zipFile);
		const got = sha256(zipFile);
		if (got !== want) {
			fs.rmSync(zipFile);
			throw new Error(`${zip}: checksum ${got} does not match SHA256SUMS (${want}); removed, run sync again`);
		}
	}
	execFileSync('unzip', ['-q', '-o', zipFile], { cwd: dir });
	return dir;
}

function tocVersion(dir) {
	const toc = path.join(dir, `${path.basename(dir)}.toc`);
	if (!fs.existsSync(toc)) return null;
	const m = fs.readFileSync(toc, 'utf8').match(/^## Version: (\S+)/m);
	return m ? m[1] : null;
}

function replaceData(unpacked) {
	const changed = [];
	for (const name of DATA) {
		const from = path.join(unpacked, name);
		if (!fs.existsSync(from)) throw new Error(`the release has no ${name}`);
		const to = path.join(ROOT, 'addon', name);
		fs.rmSync(to, { recursive: true, force: true });
		fs.cpSync(from, to, { recursive: true });
		changed.push(name);
	}
	const lang = path.join(ROOT, 'addon', LANGUAGE);
	const keep = {};
	for (const f of OWN_IN_LANGUAGE) keep[f] = fs.readFileSync(path.join(lang, f));
	fs.rmSync(lang, { recursive: true, force: true });
	fs.cpSync(path.join(unpacked, LANGUAGE), lang, { recursive: true });
	for (const [f, buf] of Object.entries(keep)) fs.writeFileSync(path.join(lang, f), buf);
	return changed;
}

// The core's version says which release it is: the TOCs of the data match it,
// so Data.lua's "mixed install" check stays quiet.
function setCoreVersion(version) {
	for (const toc of [path.join(ROOT, 'addon', 'Polestar', 'Polestar.toc'), path.join(ROOT, 'addon', LANGUAGE, `${LANGUAGE}.toc`)]) {
		const t = fs.readFileSync(toc, 'utf8');
		fs.writeFileSync(toc, t.replace(/^## Version: .*$/m, `## Version: ${version}`));
	}
	const pkg = path.join(ROOT, 'package.json');
	const p = JSON.parse(fs.readFileSync(pkg, 'utf8'));
	p.version = version;
	fs.writeFileSync(pkg, `${JSON.stringify(p, null, 2)}\n`);
}

// The pack formats Litestar's engine reads: Guides.FORMATS in Core/Guides.lua.
function engineFormats() {
	const src = fs.readFileSync(path.join(ROOT, 'addon', 'Polestar', 'Core', 'Guides.lua'), 'utf8');
	const m = src.match(/^Guides\.FORMATS = \{([^}]*)\}/m);
	if (!m) throw new Error('Core/Guides.lua: no Guides.FORMATS line');
	return new Set([...m[1].matchAll(/\[(\d+)\]\s*=\s*true/g)].map((x) => Number(x[1])));
}

// Every pack in the release that Litestar ships: its format, and whether the engine reads it.
function compatibility(unpacked) {
	const formats = engineFormats();
	const problems = [];
	for (const name of [...DATA, LANGUAGE]) {
		const toc = path.join(unpacked, name, `${name}.toc`);
		if (!fs.existsSync(toc)) { problems.push(`${name}: not in the release`); continue; }
		const t = fs.readFileSync(toc, 'utf8');
		const f = t.match(/^## X-Polestar-Format: (\d+)/m);
		if (f && !formats.has(Number(f[1]))) problems.push(`${name}: pack format ${f[1]}, the engine reads ${[...formats].sort((a, b) => a - b).join(', ')}`);
	}
	return problems;
}

function main(args) {
	const flags = new Set(args.filter((a) => a.startsWith('--')));
	const tag = args.find((a) => !a.startsWith('--')) || latestTag();
	const version = tag.replace(/^v/, '');
	console.log(`Litestar sync with Polestar ${tag}`);

	if (flags.has('--engine')) {
		step(1, `fetching ${tag}`);
		fetchTag(tag);
		if (merged(tag)) {
			console.log('    already merged');
		} else {
			step(2, `merging ${tag}`);
			const left = mergeCode(tag);
			if (left.length) {
				console.log(`\n    ${left.length} file(s) changed by both Litestar and Polestar; resolve them, then:`);
				console.log('      git add <files> && git commit --no-edit');
				console.log(`      node tools/litestar.js sync ${tag}`);
				for (const f of left) console.log(`      ${f}`);
				console.log('    or cancel the merge: git merge --abort');
				process.exitCode = 2;
				return false;
			}
			git(['commit', '-q', '--no-edit']);
			console.log(`    merged: ${git(['log', '--oneline', '-1'])}`);
		}
	}

	if (git(['status', '--porcelain', '--untracked-files=no', '--', 'addon'])) throw new Error('addon/ has uncommitted changes: commit or stash them first');
	step(1, `the ${tag} release`);
	const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'litestar-sync-'));
	try {
		const unpacked = download(tag, tmp);
		const got = tocVersion(path.join(unpacked, 'Polestar_Guides'));
		if (got !== version) throw new Error(`the release zip's guides say ${got}, not ${version}`);
		step(2, 'compatibility');
		const problems = compatibility(unpacked);
		if (problems.length && !flags.has('--force')) {
			for (const p of problems) console.log(`    ${p}`);
			console.log(`\n    Polestar ${version}'s guides need a newer engine than Litestar's: nothing changed.`);
			console.log(`    Update the engine first: node tools/litestar.js sync ${tag} --engine`);
			process.exitCode = 3;
			return false;
		}
		console.log('    every pack in a format the engine reads');
		step(3, 'content');
		replaceData(unpacked);
		setCoreVersion(version);
		console.log(`    ${DATA.length} content folders and ${LANGUAGE}'s guide texts replaced (${version})`);
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}

	// New interface strings come only with the engine's code (--engine).
	step(4, 'Russian interface strings');
	const i18n = require('./i18n');
	if (!upstreamRu && flags.has('--engine')) upstreamRu = gitOk(['show', `${tag}:addon/Polestar_ruRU/Interface.lua`]).stdout || null;
	const r = i18n.sync({ quiet: true, fill: upstreamRu ? i18n.translationsIn(upstreamRu) : {} });
	const left = i18n.todo();
	console.log(`    ${r.added.length} new (${r.filled.length} translated from the release), ${r.retired.length} retired; ${left.length} left to translate${left.length ? ' (node tools/litestar.js i18n todo)' : ''}`);

	step(5, 'build and check');
	require('./build').build(['--zip']);
	const ok = require('./check').main([]);
	if (!ok) {
		console.log('\n    the check found problems: the content is put back, nothing installed or committed');
		git(['checkout', '--', 'addon', 'package.json']);
		git(['clean', '-fdq', '--', 'addon']);
		process.exitCode = 1;
		return false;
	}
	const changes = git(['status', '--porcelain']);
	if (changes) {
		git(['add', '-A', 'addon', 'package.json']);
		git(['commit', '-q', '-m', `Litestar: guides of Polestar ${tag}`]);
		console.log(`    committed: ${git(['log', '--oneline', '-1'])}`);
	}
	if (!flags.has('--no-install')) require('./install').main([]);
	return true;
}

module.exports = { main, kept, compatibility, engineFormats, KEEP, CUT, DATA };
