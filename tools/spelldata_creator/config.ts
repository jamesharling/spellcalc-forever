import * as fs from "fs";
import path from "path";

interface IConfig
{
    /** Directory with the DB2 CSV exports (dbc/) and the hand-maintained JSON files. */
    dataDir: string,
    /** Addon data directory the Lua files are written to. */
    outputDir: string,
    /** Text report of everything the generator skipped or guessed, for review. */
    reportFile: string,
}

const cfg: IConfig = {
    dataDir: "data/forever/",
    outputDir: __dirname + "/../../../data/forever/",
    reportFile: "data/forever/generation_report.txt",
}

interface BuildInfo
{
    product: string,
    version: string,
    created_at?: string,
}

let buildInfoCache: BuildInfo | undefined;

/**
 * Build the DB2 tables in dataDir/dbc were exported from (written by DataUpdater).
 */
function getBuildInfo(): BuildInfo
{
    if (buildInfoCache) return buildInfoCache;

    const file = path.join(cfg.dataDir, "dbc", "build.json");
    if (fs.existsSync(file))
    {
        buildInfoCache = JSON.parse(fs.readFileSync(file, "utf8"));
    }
    else
    {
        buildInfoCache = { product: "wowf", version: "unknown" };
    }
    return buildInfoCache!;
}

export { cfg, getBuildInfo }
