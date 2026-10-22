import { writeFileSync, mkdirSync } from "fs";
import https from "https"
import path from "path";

/**
 * DB2 tables the generator reads. Exported as CSV from wago.tools for the
 * World of Warcraft: Forever client (wago.tools product "wowf").
 */
const dataTables = [
    // Items
    "Item",
    "ItemEffect",
    "ItemXItemEffect",
    "ItemSet",
    "ItemSetSpell",
    "ItemSparse",
    // Spells
    "Spell",
    "SpellAuraOptions",
    "SpellCategories",
    "SpellClassOptions",
    "SpellCooldowns",
    "SpellDescriptionVariables",
    "SpellDuration",
    "SpellEffect",
    "SpellEquippedItems",
    "SpellLevels",
    "SpellMisc",
    "SpellName",
    "SpellPower",
    "SpellXDescriptionVariables",
    // Class spell books
    "SkillLine",
    "SkillLineAbility",
    "SkillRaceClassInfo",
    // Talents (trait system)
    "SkillLineXTraitTree",
    "TraitTree",
    "TraitNode",
    "TraitNodeXTraitNodeEntry",
    "TraitNodeEntry",
    "TraitDefinition",
    "TraitDefinitionEffectPoints",
    "Curve",
    "CurvePoint",
];

const WAGO_PRODUCT = "wowf";
const DATA_DIR = "data/forever/dbc/";

function downloadFile(url: string): Promise<string>
{
    return new Promise((resolve, reject) =>
    {
        const request = https.get(url, { headers: { "User-Agent": "SpellCalc_Forever spelldata_creator" } }, response =>
        {
            if (response.statusCode !== 200)
            {
                reject(new Error(`Req failed '${url}' (${response.statusCode})`));
                response.resume();
                return;
            }

            let data = "";
            response.setEncoding("utf-8");
            response.on("data", (chunk) => { data += chunk; });
            response.on("end", () => resolve(data));
        });

        request.on("error", err => reject(err));
    });
}

interface WagoBuild
{
    product: string,
    version: string,
    created_at: string,
}

/**
 * Get the newest build wago.tools knows for the product.
 */
async function getLatestBuild(): Promise<WagoBuild | undefined>
{
    try
    {
        const json = JSON.parse(await downloadFile("https://wago.tools/api/builds"));
        const builds: WagoBuild[] | undefined = json[WAGO_PRODUCT];
        if (!builds || builds.length === 0) return;
        return builds[0];
    }
    catch (error)
    {
        console.error("Could not read build list from wago.tools: " + error);
        return;
    }
}

async function updateDataFiles(requestedBuild: string | undefined)
{
    mkdirSync(DATA_DIR, { recursive: true });

    let build = requestedBuild;
    let createdAt: string | undefined;

    if (!build)
    {
        const latest = await getLatestBuild();
        if (latest)
        {
            build = latest.version;
            createdAt = latest.created_at;
        }
    }

    const query = build ? `build=${build}` : `branch=${WAGO_PRODUCT}`;
    console.log(`Downloading ${WAGO_PRODUCT} tables (${query})`);

    for (const tableName of dataTables)
    {
        const url = `https://wago.tools/db2/${tableName}/csv?${query}`;
        let data: string;

        console.log("Starting download for: " + tableName);

        try
        {
            data = await downloadFile(url);
        }
        catch (error)
        {
            console.error(error);
            return;
        }

        if (!data.startsWith("ID,") && data.indexOf(",ID,") === -1 && !data.startsWith("Name_lang,") && !data.startsWith("TitleText_lang,") && !data.startsWith("OverrideName_lang,") && !data.startsWith("DisplayName_lang,") && !data.startsWith("Pos_0,") && !data.startsWith("AbilityVerb_lang,"))
        {
            console.error(`Download for ${tableName} does not look like a CSV table, aborting!`);
            return;
        }

        const dest = path.join(DATA_DIR, tableName + ".csv");
        writeFileSync(dest, data);
        console.log("Wrote file: " + dest);
    }

    const buildInfo = {
        product: WAGO_PRODUCT,
        version: build ?? "unknown",
        created_at: createdAt,
        downloaded: new Date().toISOString(),
    };
    writeFileSync(path.join(DATA_DIR, "build.json"), JSON.stringify(buildInfo, null, 4));
    console.log("Wrote build.json: " + buildInfo.version);
}

// Usage: node build/DataUpdater.js [build]
// Without a build the newest build wago.tools lists for the Forever product is used.
updateDataFiles(process.argv[2]);
