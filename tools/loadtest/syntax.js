// Syntax check of every addon Lua file (libraries included, generator tools excluded).
//
// luaparse's Lua 5.1 mode wrongly rejects `break;` (valid in 5.1 and used by the addon), so files
// are parsed as Lua 5.2 and the one 5.2 feature WoW's Lua 5.1 lacks, goto/labels, is rejected
// separately.
//
// Usage: node syntax.js

const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const REPO = path.resolve(__dirname, "..", "..");
const files = [];
(function walk(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        if (e.name === ".git" || e.name === "node_modules" || e.name === "tools") continue;
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p);
        else if (e.name.endsWith(".lua")) files.push(p);
    }
})(REPO);

let bad = 0;
for (const f of files) {
    const rel = path.relative(REPO, f);
    const src = fs.readFileSync(f, "utf8").replace(/^﻿/, "");
    if (/\bgoto\b|::[A-Za-z_]+::/.test(src.replace(/--.*$/gm, ""))) {
        bad++;
        console.log(`GOTO (not Lua 5.1) ${rel}`);
    }
    try {
        luaparse.parse(src, { luaVersion: "5.2", comments: false, locations: false });
    } catch (e) {
        bad++;
        console.log(`SYNTAX ${rel}: ${e.message}`);
    }
}
console.log(`${files.length} Lua files parsed, ${bad} with errors`);
process.exit(bad ? 1 : 0);
