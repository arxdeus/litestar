#!/usr/bin/env node
'use strict';
// Litestar's one command (tools/litestar/):
//
//   node tools/litestar.js build [--zip] [--out <dir>]   build dist/Litestar from addon/
//   node tools/litestar.js check [--quick] [--dir <dir>]  load and walk the build under the game stub
//   node tools/litestar.js install [--to <AddOns>]        copy the build into the game
//   node tools/litestar.js sync [<tag>] [--data-only] [--no-install]
//                                                         merge a Polestar release and take its data
//   node tools/litestar.js i18n sync | check | todo       the Russian interface strings
//
// Bare `node tools/litestar.js --zip` (the old form) builds.

const [cmd, ...rest] = process.argv.slice(2);

function run() {
	switch (cmd) {
		case 'build': return require('./litestar/build').build(rest);
		case 'check': return require('./litestar/check').main(rest);
		case 'install': return require('./litestar/install').main(rest);
		case 'sync': return require('./litestar/sync').main(rest);
		case 'i18n': return require('./litestar/i18n').main(rest);
		case undefined: case '--zip': case '--out':
			return require('./litestar/build').build(process.argv.slice(2));
		case 'help': case '--help': case '-h':
			console.log(require('node:fs').readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).slice(0, 10).map((l) => l.slice(3)).join('\n'));
			return;
		default:
			throw new Error(`unknown command ${cmd}: build, check, install, sync, i18n (help)`);
	}
}

try {
	run();
} catch (e) {
	console.error(`litestar: ${e.message}`);
	process.exitCode = 1;
}
