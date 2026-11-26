// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Fails when C++ reads a `Module` member that client/web/emscripten-module.d.ts
// does not declare.
//
// The engine reaches the page through `Module["luantiLauncher"]`,
// `Module.luantiPerf` and friends inside EM_JS / EM_ASM / MAIN_THREAD_EM_ASM
// bodies. tsc cannot see those, so without this check the .d.ts contract can
// drift from the C++ side with no failure. With it, adding a `Module.luanti*`
// read to C++ forces the matching declaration into the same change, where
// review sees it in the diff of emscripten-module.d.ts.
//
// Run by `npm run typecheck`. Plain Node, no dependencies:
//   node util/wasm/check_module_contract.mjs

import {readdirSync, readFileSync} from "node:fs";
import {dirname, join, relative} from "node:path";
import {fileURLToPath} from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const declarationFile = join(root, "client/web/emscripten-module.d.ts");
const cppRoots = ["src", "irr/src"];
const cppExtensions = /\.(?:cpp|h|hpp|mm)$/;

/** Members of `interface LuantiModule { ... }` (one tab deep). */
function declaredMembers(text) {
	const lines = text.split("\n");
	const start = lines.findIndex((line) => line.startsWith("interface LuantiModule"));
	if (start < 0)
		throw new Error("interface LuantiModule not found in " + declarationFile);
	const members = new Set();
	for (let i = start + 1; i < lines.length && lines[i] !== "}"; i++) {
		const match = /^\t([A-Za-z_$][\w$]*)\??\s*[:(<]/.exec(lines[i]);
		if (match)
			members.add(match[1]);
	}
	return members;
}

/** Every .cpp/.h file under `dir`, skipping nothing: EM_JS can live anywhere. */
function* sourceFiles(dir) {
	for (const entry of readdirSync(dir, {withFileTypes: true})) {
		const path = join(dir, entry.name);
		if (entry.isDirectory())
			yield* sourceFiles(path);
		else if (cppExtensions.test(entry.name))
			yield path;
	}
}

const declared = declaredMembers(readFileSync(declarationFile, "utf8"));
// `Module.name` and `Module["name"]` / `Module['name']`; the leading \b keeps
// `ModuleInfo` and friends out.
const access = /\bModule(?:\.([A-Za-z_$][\w$]*)|\s*\[\s*["']([^"']+)["']\s*\])/g;

const missing = [];
let references = 0;
for (const dir of cppRoots) {
	for (const file of sourceFiles(join(root, dir))) {
		const text = readFileSync(file, "utf8");
		if (!text.includes("Module"))
			continue;
		text.split("\n").forEach((line, index) => {
			for (const match of line.matchAll(access)) {
				references++;
				const name = match[1] || match[2];
				if (!declared.has(name))
					missing.push(`${relative(root, file)}:${index + 1}: Module.${name}`);
			}
		});
	}
}

if (missing.length) {
	console.error("C++ reads Module members that client/web/emscripten-module.d.ts does not declare:\n");
	for (const line of missing)
		console.error("  " + line);
	console.error("\nDeclare each one on `interface LuantiModule` in the same change as the C++ call and the");
	console.error("JavaScript that implements it.");
	process.exit(1);
}
console.log(`Module contract: ${references} C++ references, all declared (${declared.size} members).`);
