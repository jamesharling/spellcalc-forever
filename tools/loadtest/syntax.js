// Syntax check of every addon Lua file (libraries included, generator tools excluded).
//
// luaparse's Lua 5.1 mode wrongly rejects `break;` (valid in 5.1 and used by the addon), so files
// are parsed as Lua 5.2 and the one 5.2 feature WoW's Lua 5.1 lacks, goto/labels, is rejected
// separately.
//
// It also flags `Unsecret(f(...))` in the addon's own files: with a call as the only argument, the
// call's second return value becomes Unsecret's fallback, which is just as secret as the first
// (Unsecret(UnitCreatureType("target")) crashed on the live client).
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

const CALL_TYPES = new Set(["CallExpression", "StringCallExpression", "TableCallExpression"]);

/** Unsecret calls whose only argument is a call; returns their line numbers. (luaparse doesn't record
 * parentheses, so `Unsecret((f()))` is flagged too: take the value into a local instead.) */
function multiValueUnsecret(ast) {
    const lines = [];
    (function visit(node) {
        if (Array.isArray(node)) { node.forEach(visit); return; }
        if (!node || typeof node !== "object") return;
        if (node.type === "CallExpression") {
            const callee = node.base;
            const name = callee.type === "Identifier" ? callee.name : callee.type === "MemberExpression" ? callee.identifier.name : "";
            const args = node.arguments;
            if (name === "Unsecret" && args.length === 1 && CALL_TYPES.has(args[0].type)) {
                lines.push(node.loc.start.line);
            }
        }
        for (const key in node) if (key !== "loc") visit(node[key]);
    })(ast);
    return lines;
}

let bad = 0;
for (const f of files) {
    const rel = path.relative(REPO, f);
    const src = fs.readFileSync(f, "utf8").replace(/^﻿/, "");
    if (/\bgoto\b|::[A-Za-z_]+::/.test(src.replace(/--.*$/gm, ""))) {
        bad++;
        console.log(`GOTO (not Lua 5.1) ${rel}`);
    }
    try {
        const ast = luaparse.parse(src, { luaVersion: "5.2", comments: false, locations: true });
        if (!rel.startsWith("libs" + path.sep)) {
            for (const line of multiValueUnsecret(ast)) {
                bad++;
                console.log(`UNSECRET ${rel}:${line}: only argument is a call, its second return value becomes the fallback; use a local`);
            }
        }
    } catch (e) {
        bad++;
        console.log(`SYNTAX ${rel}: ${e.message}`);
    }
}
console.log(`${files.length} Lua files parsed, ${bad} with errors`);
process.exit(bad ? 1 : 0);
