import { existsSync, readFileSync, statSync, writeFileSync } from "fs";
import path from "path";
import { readDBCSV } from "./CSVReader";
import { cfg, getBuildInfo } from "./config";

/**
 * Snapshots the item rows the Forever client received as server hotfixes into data/forever/hotfixItems.json.
 *
 * wago.tools exports the DB2 tables as shipped in the client build, without hotfixes. Forever adds and reworks
 * a lot of items through hotfixes (the tier 0 sets among them), so for those items Item.csv has a row but
 * ItemSparse.csv (name, allowed classes) doesn't. Items Forever removed look the same in the export. The client's
 * hotfix cache tells the two apart: it holds every hotfix row the server pushed, with its state.
 *
 * Log in to the Forever client once (so the cache is current), then run
 *   npm run update-hotfixes-forever -- [client folder or path to DBCache.bin]
 * The snapshot is committed, so generating data doesn't need the client.
 */

const DEFAULT_CLIENT_DIR = "C:/Program Files (x86)/World of Warcraft/_forever_";
const CACHE_PATH = "Cache/ADB/enUS/DBCache.bin";
const OUTPUT_FILE = "hotfixItems.json";

/** DB2 table hash of ItemSparse. */
const TABLE_ITEMSPARSE = 0x919BE54E;

/** Hotfix record states in DBCache.bin. */
const enum RecordState
{
    VALID = 1,
    DELETED = 2,
    INVALID = 3,
    NOT_PUBLIC = 4,
}

interface HotfixRecord
{
    table: number,
    recordId: number,
    state: RecordState,
    data: Buffer,
}

export interface HotfixItems
{
    /** Client build the cache was written by. */
    build: string,
    region: number,
    /** Items with a valid hotfix detail row: item ID -> name. */
    items: { [itemId: string]: string },
    /** Items whose detail row a hotfix deleted. */
    deleted: number[],
}

/**
 * Read DBCache.bin (version 9). Later records of the same table and record ID replace earlier ones.
 */
function readHotfixCache(file: string)
{
    const buf = readFileSync(file);
    if (buf.toString("latin1", 0, 4) !== "XFTH") throw new Error(`${file} is not a hotfix cache`);
    const version = buf.readInt32LE(4);
    if (version !== 9) throw new Error(`Hotfix cache version ${version} is not supported (expected 9)`);
    const build = buf.readUInt32LE(8);

    const records = new Map<string, HotfixRecord>();
    let region = 0;
    let off = 12 + 32; // header + verification hash
    while (off + 32 <= buf.length)
    {
        if (buf.toString("latin1", off, off + 4) !== "XFTH") throw new Error(`Bad record magic at offset ${off}`);
        region = buf.readInt32LE(off + 4);
        // off + 8: push ID, off + 12: unique ID
        const table = buf.readUInt32LE(off + 16);
        const recordId = buf.readUInt32LE(off + 20);
        const size = buf.readInt32LE(off + 24);
        const state = buf[off + 28] as RecordState;
        const data = buf.subarray(off + 32, off + 32 + size);
        records.set(table + ":" + recordId, { table, recordId, state, data });
        off += 32 + size;
    }

    return { build, region, records: [...records.values()] };
}

/**
 * Read the null-terminated string with the given index from the start of a hotfix row.
 * Hotfix rows store strings inline; ItemSparse's string columns come first.
 */
function readLeadingString(data: Buffer, index: number)
{
    let start = 0;
    for (let i = 0; i < index; i++)
    {
        start = data.indexOf(0, start) + 1;
        if (start === 0) return undefined;
    }
    const end = data.indexOf(0, start);
    if (end === -1) return undefined;
    return data.toString("utf8", start, end);
}

function main()
{
    let cacheFile = process.argv[2] ?? process.env.WOWF_CLIENT_DIR ?? DEFAULT_CLIENT_DIR;
    if (existsSync(cacheFile) && statSync(cacheFile).isDirectory()) cacheFile = path.join(cacheFile, CACHE_PATH);
    if (!existsSync(cacheFile))
    {
        console.error(`No hotfix cache at ${cacheFile}. Pass the Forever client folder or the path to DBCache.bin.`);
        process.exit(1);
    }

    const tableVersion = getBuildInfo().version;
    const cache = readHotfixCache(cacheFile);
    const build = tableVersion.endsWith("." + cache.build) ? tableVersion : String(cache.build);
    if (build !== tableVersion)
    {
        console.warn(`Warning: the cache is from client build ${cache.build}, the tables in ${cfg.dataDir}dbc from ${tableVersion}.`);
    }

    // The name's position among ItemSparse's leading string columns, from the export of the same build.
    const sparseCsv = readFileSync(cfg.dataDir + "dbc/ItemSparse.csv", "utf8");
    const columns = sparseCsv.slice(0, sparseCsv.indexOf("\n")).trim().split(",").slice(1); // ID isn't part of the row data
    const nameIndex = columns.indexOf("Display_lang");
    if (nameIndex === -1 || !columns.slice(0, nameIndex + 1).every(c => c.endsWith("_lang")))
    {
        throw new Error("ItemSparse.csv doesn't start with its string columns, the row layout changed");
    }

    const snapshot: HotfixItems = { build, region: cache.region, items: {}, deleted: [] };
    for (const rec of cache.records)
    {
        if (rec.table !== TABLE_ITEMSPARSE) continue;
        if (rec.state === RecordState.DELETED)
        {
            snapshot.deleted.push(rec.recordId);
        }
        else if (rec.state === RecordState.VALID)
        {
            const name = readLeadingString(rec.data, nameIndex);
            if (name === undefined) throw new Error(`Hotfix row of item ${rec.recordId} has no name`);
            snapshot.items[rec.recordId] = name;
        }
    }
    snapshot.deleted.sort((a, b) => a - b);

    // Items that have both an exported and a hotfix row check the name offset.
    const sparse = readDBCSV<{ ID: number, Display_lang: string }>(cfg.dataDir + "dbc/ItemSparse.csv", "ID");
    let compared = 0;
    for (const id in snapshot.items)
    {
        if (!sparse[id]) continue;
        compared++;
        if (String(sparse[id].Display_lang) !== snapshot.items[id])
        {
            console.warn(`Item ${id}: hotfix name '${snapshot.items[id]}', exported name '${sparse[id].Display_lang}'`);
        }
    }

    const outFile = cfg.dataDir + OUTPUT_FILE;
    writeFileSync(outFile, JSON.stringify(snapshot, null, 4) + "\n");
    const hotfixOnly = Object.keys(snapshot.items).filter(id => !sparse[id]).length;
    console.log(`${outFile}: ${Object.keys(snapshot.items).length} hotfixed items (${hotfixOnly} not in the export, `
        + `${compared} checked against it), ${snapshot.deleted.length} deleted, build ${build}`);
}

main();
