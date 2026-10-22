// Headless load and smoke test for SpellCalc_Forever.
//
// Loads the addon exactly in TOC order (including the library XML includes) into a Lua VM
// (fengari, Lua 5.3 with Lua 5.1 shims) on top of a stubbed World of Warcraft API
// (wow_env.lua), once per supported class. Then driver.lua fires the login events and
// calculates every spell in the generated data, without and with all talents, and runs the
// spell tooltip hook for each of them.
//
// This catches load errors, missing data references, NaN/inf results and Lua errors in the
// calculation and tooltip code. It cannot tell whether numbers match the live game.
//
// Usage: node run.js [--classes MAGE,PRIEST] [--verbose]

const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const ADDON = "SpellCalc_Forever";
const REPO = path.resolve(__dirname, "..", "..");
const TOC = path.join(REPO, ADDON + ".toc");
const DBC = path.join(REPO, "tools", "spelldata_creator", "data", "forever", "dbc");
const SUPPORTED = ["DRUID", "MAGE", "PALADIN", "PRIEST", "SHAMAN", "WARLOCK"];

const args = process.argv.slice(2);
const verbose = args.includes("--verbose");
const classArgIdx = args.indexOf("--classes");
const classes = classArgIdx !== -1 ? args[classArgIdx + 1].toUpperCase().split(",") : SUPPORTED;

/** Minimal CSV parser (quoted fields, embedded newlines). Calls onRow(fields) for each row. */
function parseCsv(text, onRow) {
    let field = "", row = [], inQuotes = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (inQuotes) {
            if (c === '"') {
                if (text[i + 1] === '"') { field += '"'; i++; } else inQuotes = false;
            } else field += c;
        } else if (c === '"') inQuotes = true;
        else if (c === ",") { row.push(field); field = ""; }
        else if (c === "\n") { row.push(field); onRow(row); row = []; field = ""; }
        else if (c !== "\r") field += c;
    }
    if (field.length || row.length) { row.push(field); onRow(row); }
}

/** Spell names and rank subtexts: from the client CSVs if downloaded, else from data file comments. */
function loadSpellNames() {
    const names = new Map(), subtexts = new Map();
    const nameCsv = path.join(DBC, "SpellName.csv"), spellCsv = path.join(DBC, "Spell.csv");
    if (fs.existsSync(nameCsv) && fs.existsSync(spellCsv)) {
        let header = true;
        parseCsv(fs.readFileSync(nameCsv, "utf8"), r => { if (header) { header = false; return; } names.set(+r[0], r[1]); });
        header = true;
        parseCsv(fs.readFileSync(spellCsv, "utf8"), r => { if (header) { header = false; return; } if (r[1]) subtexts.set(+r[0], r[1]); });
        return { names, subtexts, source: "client CSVs" };
    }
    const dataDir = path.join(REPO, "data", "forever");
    const files = [];
    (function walk(d) { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (p.endsWith(".lua")) files.push(p); } })(dataDir);
    const re = /^\s*\[(\d+)\] = \{ -- (.+?)(?: \(([^)]*Rank[^)]*)\))?\s*$/;
    for (const f of files) {
        for (const line of fs.readFileSync(f, "utf8").split("\n")) {
            const m = line.match(re);
            if (m && !names.has(+m[1])) { names.set(+m[1], m[2]); if (m[3]) subtexts.set(+m[1], m[3]); }
        }
    }
    return { names, subtexts, source: "data file comments" };
}

/** Files in TOC order, with XML includes expanded. */
function tocFiles() {
    const out = [];
    const addXml = (xmlPath) => {
        const xml = fs.readFileSync(xmlPath, "utf8").replace(/<!--[\s\S]*?-->/g, "");
        const re = /<(Script|Include)\s+file\s*=\s*"([^"]+)"/g;
        let m;
        while ((m = re.exec(xml))) {
            const p = path.join(path.dirname(xmlPath), m[2].replace(/\\/g, "/"));
            if (m[1] === "Include") addXml(p); else out.push(p);
        }
    };
    for (const raw of fs.readFileSync(TOC, "utf8").split(/\r?\n/)) {
        const line = raw.trim();
        if (!line || line.startsWith("#")) continue;
        const p = path.join(REPO, line.replace(/\\/g, "/"));
        if (!fs.existsSync(p)) { out.push({ missing: line }); continue; }
        if (p.toLowerCase().endsWith(".xml")) addXml(p); else out.push(p);
    }
    return out;
}

function pushTraceback(L) {
    lua.lua_getglobal(L, to_luastring("debug"));
    lua.lua_getfield(L, -1, to_luastring("traceback"));
    lua.lua_remove(L, -2);
    return lua.lua_gettop(L);
}

/** Load and run a chunk; for addon files pass (addonName, addonTable) like the client. */
function runChunk(L, src, chunkName, addonArgs) {
    const msgh = pushTraceback(L);
    const buf = to_luastring(src.replace(/^﻿/, ""));
    let status = lauxlib.luaL_loadbuffer(L, buf, buf.length, to_luastring("@" + chunkName));
    if (status !== lua.LUA_OK) {
        const err = lua.lua_tojsstring(L, -1);
        lua.lua_settop(L, msgh - 1);
        return err;
    }
    let nargs = 0;
    if (addonArgs) {
        lua.lua_pushstring(L, to_luastring(ADDON));
        lua.lua_getglobal(L, to_luastring("__ADDON_TABLE"));
        nargs = 2;
    }
    status = lua.lua_pcall(L, nargs, 1, msgh);
    let result = null;
    if (status !== lua.LUA_OK) result = { error: lua.lua_tojsstring(L, -1) };
    else if (lua.lua_type(L, -1) === lua.LUA_TSTRING) result = { value: lua.lua_tojsstring(L, -1) };
    lua.lua_settop(L, msgh - 1);
    return result && result.error ? result.error : result;
}

/** Read a global Lua table as [key, value] string pairs (values may contain newlines). */
function getStringList(L, globalName) {
    const src = `local t = ${globalName}; local o = {}; for k, v in pairs(t) do o[#o + 1] = tostring(k) .. "\\31" .. tostring(v) end; table.sort(o); return table.concat(o, "\\30")`;
    const r = runChunk(L, src, "query", false);
    if (typeof r === "string") throw new Error(r);
    return r && r.value ? r.value.split("\x1e").filter(Boolean).map(l => l.split("\x1f")) : [];
}

const names = loadSpellNames();
const files = tocFiles();
const envSrc = fs.readFileSync(path.join(__dirname, "wow_env.lua"), "utf8");
const driverSrc = fs.readFileSync(path.join(__dirname, "driver.lua"), "utf8");
const IGNORED_MISSING = new Set(["Bartender4", "Dominos", "ElvUI", "SpellCalc_settings"]);

console.log(`SpellCalc_Forever load test: ${files.length} files from the TOC, spell names from ${names.source}`);
let failures = 0;
const missingGlobals = new Map(), missingMembers = new Map(), unknownMethods = new Map();

for (const cls of classes) {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);

    lua.lua_pushstring(L, to_luastring(cls)); lua.lua_setglobal(L, to_luastring("__CLASS"));
    lua.lua_pushstring(L, to_luastring(ADDON)); lua.lua_setglobal(L, to_luastring("__ADDON_NAME"));
    for (const [g, map] of [["__SPELL_NAMES", names.names], ["__SPELL_SUBTEXT", names.subtexts]]) {
        lua.lua_createtable(L, 0, map.size);
        for (const [id, text] of map) { lua.lua_pushinteger(L, id); lua.lua_pushstring(L, to_luastring(text)); lua.lua_rawset(L, -3); }
        lua.lua_setglobal(L, to_luastring(g));
    }

    let err = runChunk(L, envSrc, "wow_env.lua", false);
    if (typeof err === "string") { console.log(`${cls}: environment failed: ${err}`); failures++; continue; }
    lua.lua_createtable(L, 0, 0); lua.lua_setglobal(L, to_luastring("__ADDON_TABLE"));

    const loadErrors = [];
    for (const f of files) {
        if (f.missing) { loadErrors.push(`TOC entry not found: ${f.missing}`); continue; }
        const rel = path.relative(REPO, f).replace(/\\/g, "/");
        const r = runChunk(L, fs.readFileSync(f, "utf8"), rel, true);
        if (typeof r === "string") loadErrors.push(r);
    }

    const result = runChunk(L, driverSrc, "driver.lua", false);
    const lines = [];
    if (typeof result === "string") { lines.push("DRIVER ERROR " + result); }
    else if (result && result.value) lines.push(...result.value.split("\n"));

    const runtimeErrors = getStringList(L, "__ERRORS").map(([, v]) => v);
    const prints = getStringList(L, "__PRINTS").map(([, v]) => v);
    const errorPrints = prints.filter(p => p.includes("|cFFFF3333"));
    for (const [k, v] of getStringList(L, "__MISSING_GLOBALS")) if (!IGNORED_MISSING.has(k)) missingGlobals.set(k, (missingGlobals.get(k) || 0) + +v);
    for (const [k, v] of getStringList(L, "__MISSING_MEMBERS")) missingMembers.set(k, (missingMembers.get(k) || 0) + +v);
    for (const [k, v] of getStringList(L, "__UNKNOWN_METHODS")) unknownMethods.set(k, (unknownMethods.get(k) || 0) + +v);

    const bad = lines.filter(l => l.startsWith("FAIL"));
    const ok = loadErrors.length === 0 && runtimeErrors.length === 0 && errorPrints.length === 0 && bad.length === 0 && !lines.some(l => l.startsWith("DRIVER ERROR"));
    if (!ok) failures++;

    console.log(`\n=== ${cls}: ${ok ? "OK" : "PROBLEMS"}`);
    for (const e of loadErrors) console.log("  LOAD ERROR " + e.split("\n").slice(0, verbose ? 20 : 4).join("\n    "));
    const uniqueRuntime = new Map();
    for (const e of runtimeErrors) { const key = e.split("\n")[0]; uniqueRuntime.set(key, { count: (uniqueRuntime.get(key)?.count || 0) + 1, full: e }); }
    for (const [key, v] of uniqueRuntime) console.log(`  RUNTIME ERROR (${v.count}x) ` + (verbose ? v.full : key));
    for (const p of errorPrints.slice(0, 10)) console.log("  ADDON ERROR PRINT " + p.replace(/\|c[0-9A-Fa-f]{8}|\|r/g, ""));
    for (const l of lines) if (verbose || !l.startsWith("DETAIL")) console.log("  " + l);
}

const report = (title, map) => {
    if (map.size === 0) return;
    console.log(`\n${title}:`);
    console.log("  " + [...map.keys()].sort().join(", "));
};
report("Globals read by the addon that the stub environment does not define (real client may have them)", missingGlobals);
report("Namespace members read that the stubs do not define", missingMembers);
if (verbose) report("Widget methods without a stub (treated as no-ops)", unknownMethods);

console.log(`\n${failures === 0 ? "All classes passed." : failures + " class(es) with problems."}`);
process.exit(failures === 0 ? 0 : 1);
