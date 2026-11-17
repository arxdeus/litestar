'use strict';
// Brings Litestar up to a Polestar release: its guides, its data and the fixes
// to the code Litestar keeps.
//
//   node tools/litestar.js sync [<tag>] [--data-only] [--no-install]
//
// <tag>: a Polestar release tag (v0.4.0.1); none: the latest release on
// GitHub. Steps, each stopping with what to do when it can't go on:
//
//   1. fetch the tag from the `polestar` remote (added on first run:
//      https://github.com/fitzforge/polestar)
//   2. merge it into the current branch (the code). Litestar's cuts are kept
//      without asking: a file Litestar deleted that the release changed stays
//      deleted, a folder the release adds under a cut feature stays out
//      (KEEP below says what Litestar ships). What is left in conflict (a
//      line both changed) stops the sync: fix those files, `git commit`,
//      then run sync again with --data-only.
//   3. the release zip from GitHub (its SHA256SUMS checked): every data folder
//      Litestar ships (DATA below) replaced by the release's, so the guides,
//      the Codex, the quest and item data and the walking maps are exactly
//      the ones that release's core reads
//   4. the Russian interface file synced with the code (new strings listed:
//      they show in English until translated)
//   5. build, check (tools/litestar/check.js) and, unless --no-install,
//      install into the game's AddOns folder (tools/litestar/install.js)
//
// --data-only skips 1-2: only the data of <tag> (for a merge already done).

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
	'addon/Polestar/', 'addon/Polestar_ruRU/',
	...DATA.filter((d) => !['Polestar_Codex', 'Polestar_QuestDB'].includes(d)).map((d) => `addon/${d}/`),
	'tools/litestar.js', 'tools/litestar/',
	'data/codex/attunements.json', // the attunement notes' keys (tools/lib/i18n/keys.js)
	'tools/lib/lua.js', 'tools/lib/i18n/keys.js', 'tools/lib/i18n/files.js', 'tools/lib/i18n/locales.js',
	'tests/helpers/lua.js',
	'tests/lua/wow_stub.lua', 'tests/lua/stub_world.lua', 'tests/lua/stub_settings.lua', 'tests/lua/stub_encoding.lua',
	'.gitignore', '.gitattributes', '.editorconfig', 'LICENSE', 'LICENSE-EXCEPTION.md', 'THIRD_PARTY.md',
	'README.md', 'AGENTS.md', 'package.json',
];
// Inside the kept core, files of features Litestar cut (a merge may bring
// them back as new files): removed again after the merge.
const CUT = [
	'addon/Polestar/Rares/', 'addon/Polestar/Talents/', 'addon/Polestar/Locales/',
];

function kept(file) {
	if (CUT.some((p) => file.startsWith(p))) return false;
	return KEEP.some((p) => (p.endsWith('/') ? file.startsWith(p) : file === p));
}

function git(args, opts = {}) {
	return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: opts.stdio || ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 }).trim();
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

function download(tag, dir) {
	const version = tag.replace(/^v/, '');
	const zip = `Polestar-${version}.zip`;
	const r = spawnSync('gh', ['release', 'download', tag, '-R', REPO, '-p', zip, '-p', 'SHA256SUMS', '-D', dir, '--clobber'], { encoding: 'utf8' });
	if (r.status !== 0) {
		for (const f of [zip, 'SHA256SUMS']) {
			const c = spawnSync('curl', ['-fsSL', '-o', path.join(dir, f), `https://github.com/${REPO}/releases/download/${tag}/${f}`]);
			if (c.status !== 0) throw new Error(`could not download ${f} of Polestar ${tag}`);
		}
	}
	const sums = fs.readFileSync(path.join(dir, 'SHA256SUMS'), 'utf8');
	const want = (sums.split('\n').find((l) => l.endsWith(`  ${zip}`)) || '').split(/\s+/)[0];
	const got = crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, zip))).digest('hex');
	if (!want || want !== got) throw new Error(`${zip}: checksum ${got} does not match SHA256SUMS (${want || 'missing'})`);
	execFileSync('unzip', ['-q', '-o', zip], { cwd: dir });
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

function main(args) {
	const flags = new Set(args.filter((a) => a.startsWith('--')));
	const tag = args.find((a) => !a.startsWith('--')) || latestTag();
	const version = tag.replace(/^v/, '');
	console.log(`Litestar sync with Polestar ${tag}`);

	if (!flags.has('--data-only')) {
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
				console.log(`      node tools/litestar.js sync ${tag} --data-only`);
				for (const f of left) console.log(`      ${f}`);
				process.exitCode = 2;
				return false;
			}
			git(['commit', '-q', '--no-edit']);
			console.log(`    merged: ${git(['log', '--oneline', '-1'])}`);
		}
	}

	step(3, `data from the ${tag} release`);
	const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'litestar-sync-'));
	try {
		const unpacked = download(tag, tmp);
		const got = tocVersion(path.join(unpacked, 'Polestar_Guides'));
		if (got !== version) throw new Error(`the release zip's guides say ${got}, not ${version}`);
		replaceData(unpacked);
		setCoreVersion(version);
		console.log(`    ${DATA.length} data folders and ${LANGUAGE}'s texts replaced (${version})`);
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}

	step(4, 'Russian interface strings');
	const i18n = require('./i18n');
	const r = i18n.sync({ quiet: true });
	const left = i18n.todo();
	console.log(`    ${r.added.length} new, ${r.retired.length} retired; ${left.length} left to translate${left.length ? ' (node tools/litestar.js i18n todo)' : ''}`);

	step(5, 'build and check');
	require('./build').build(['--zip']);
	const ok = require('./check').main([]);
	if (!ok) {
		console.log('\n    the check found problems: nothing installed, nothing committed');
		process.exitCode = 1;
		return false;
	}
	const changes = git(['status', '--porcelain']);
	if (changes) {
		git(['add', '-A', 'addon', 'package.json']);
		git(['commit', '-q', '-m', `Litestar: data of Polestar ${tag}`]);
		console.log(`    committed: ${git(['log', '--oneline', '-1'])}`);
	}
	if (!flags.has('--no-install')) require('./install').main([]);
	return true;
}

module.exports = { main, kept, KEEP, CUT, DATA };
