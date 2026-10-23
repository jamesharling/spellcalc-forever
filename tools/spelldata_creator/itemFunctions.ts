import { existsSync, readFileSync } from "fs";
import { readDBCSV } from "./CSVReader";
import { cfg, getBuildInfo } from "./config";
import type { HotfixItems } from "./HotfixSnapshot";
import { report } from "./report";
import { SpellData } from "./SpellData";

/**
 * An item known to the generator. Item.csv has every item; the detail row (ItemSparse: name, allowed
 * classes, set) is missing for items Forever removed and for items it added or reworked through server
 * hotfixes, because hotfix-only rows aren't in the exported tables. data/forever/hotfixItems.json
 * (HotfixSnapshot) tells the two apart and has the names of the hotfix-only items.
 */
export interface DbRow
{
    entry: number,
    name: string,
    /** Undefined when the item has no detail row. */
    AllowableClass: number | undefined,
    class: number,
    subclass: number,
    hasDetails: boolean,
}

interface DBCItemSparse
{
    ID: number,
    AllowableRace: number,
    Display_lang: string,
    Flags_0: number,
    Flags_1: number,
    Flags_2: number,
    Flags_3: number,
    ItemSet: number,
    AllowableClass: number,
    InventoryType: number
}

interface DBCItem
{
    ID: number,
    ClassID: number,
    SubclassID: number,
    InventoryType: number
}

const classMask = {
    warrior: 1,
    paladin: 1 << 1,
    hunter: 1 << 2,
    rogue: 1 << 3,
    priest: 1 << 4,
    deathknight: 1 << 5,
    shaman: 1 << 6,
    mage: 1 << 7,
    warlock: 1 << 8,
    druid: 1 << 10
};

const allClasses = function ()
{
    let ac = 0;
    for (const className in classMask) ac |= classMask[className as keyof typeof classMask];
    return ac;
}();

const LE_ITEM_CLASS_ARMOR = 4;
const LE_ITEM_ARMOR_LIBRAM = 7;
const LE_ITEM_ARMOR_IDOL = 8;
const LE_ITEM_ARMOR_TOTEM = 9;

interface ItemDBdata
{
    [itemId: string]: DbRow
}
let dbDataCache: ItemDBdata;

function getHotfixItems(): HotfixItems
{
    const file = cfg.dataDir + "hotfixItems.json";
    if (!existsSync(file))
    {
        report("No hotfixItems.json (npm run update-hotfixes-forever): items added through hotfixes are left out");
        return { build: "none", region: 0, items: {}, deleted: [] };
    }
    const hotfixes: HotfixItems = JSON.parse(readFileSync(file, "utf8"));
    if (hotfixes.build !== getBuildInfo().version)
    {
        report(`hotfixItems.json is from build ${hotfixes.build}, the tables from ${getBuildInfo().version}: update it from a current client`);
    }
    return hotfixes;
}

/**
 * Get item DB data: every item with an exported or a hotfix detail row, minus items a hotfix deleted.
 */
export function getItemDbData()
{
    if (dbDataCache) return dbDataCache;

    const sparse = readDBCSV<DBCItemSparse>(cfg.dataDir + "dbc/ItemSparse.csv", "ID");
    const item = readDBCSV<DBCItem>(cfg.dataDir + "dbc/Item.csv", "ID");
    const hotfixes = getHotfixItems();
    const deleted = new Set(hotfixes.deleted);

    dbDataCache = {};

    let hotfixOnly = 0;
    let removed = 0;
    for (const id in item)
    {
        const details = sparse[id];
        const hotfixName = hotfixes.items[id];
        if (deleted.has(Number(id)) || (!details && hotfixName === undefined))
        {
            removed++;
            continue;
        }
        if (!details) hotfixOnly++;

        dbDataCache[id] = {
            entry: item[id].ID,
            class: item[id].ClassID,
            subclass: item[id].SubclassID,
            AllowableClass: details ? details.AllowableClass : undefined,
            name: hotfixName ?? String(details.Display_lang),
            hasDetails: !!details,
        }
    }

    console.log(`Item DB: ${Object.keys(dbDataCache).length} items (${hotfixOnly} from hotfixes), ${removed} removed items skipped`);

    return dbDataCache;
}

/** SpellClassOptions.SpellClassSet -> class key used for the generated files */
const CLASS_BY_SPELL_SET: { [set: number]: keyof typeof classMask } = {
    3: "mage", 4: "warrior", 5: "warlock", 6: "priest", 7: "druid", 8: "rogue", 9: "hunter", 10: "paladin", 11: "shaman",
};

/**
 * The class whose spells a group of spells modifies, if they all agree. Used for items without a detail row
 * (no allowed classes): their set bonus or equip effect spells usually only modify one class's spells.
 * Only effects with a spell class mask count; the class set of a spell that modifies no spells means nothing
 * (some Forever set procs carry another class's set).
 */
export function classFromSpells(spellData: SpellData, spellIds: number[]): keyof typeof classMask | undefined
{
    const classes = new Set<keyof typeof classMask>();
    for (const spellId of spellIds)
    {
        const cls = CLASS_BY_SPELL_SET[spellData.getSpellClassOption(spellId, true)?.SpellClassSet ?? 0];
        const modifiesSpells = spellData.getSpellEffects(spellId, true)?.some(eff => eff.EffectSpellClassMask_0
            || eff.EffectSpellClassMask_1 || eff.EffectSpellClassMask_2 || eff.EffectSpellClassMask_3);
        if (cls && modifiesSpells) classes.add(cls);
    }
    return classes.size === 1 ? classes.values().next().value : undefined;
}

/**
 * Order item data by classes that can use it. 
 * @param itemMap Item data mapped by itemId
 * @param classHints Class for items without a detail row (no AllowableClass); others go to GENERAL.
 * @returns Object containing maps of the same type for each class
 */
export async function orderItemsByClass<T>(itemMap: Map<number, T>, classHints?: Map<number, keyof typeof classMask | undefined>)
{
    const dbData = getItemDbData();

    const ordered = {
        warrior: new Map<number, T>(),
        paladin: new Map<number, T>(),
        hunter: new Map<number, T>(),
        rogue: new Map<number, T>(),
        priest: new Map<number, T>(),
        shaman: new Map<number, T>(),
        mage: new Map<number, T>(),
        warlock: new Map<number, T>(),
        druid: new Map<number, T>(),
        deathknight: new Map<number, T>(),
        GENERAL: new Map<number, T>(),
    };

    for (const [itemId, effects] of itemMap)
    {
        const dbentry = dbData[itemId];

        if (!dbentry)
        {
            report(`Item ${itemId} doesn't exist in the item table, skipped`);
            continue;
        }

        if (dbentry.AllowableClass === undefined
            && !(dbentry.class === LE_ITEM_CLASS_ARMOR && [LE_ITEM_ARMOR_IDOL, LE_ITEM_ARMOR_LIBRAM, LE_ITEM_ARMOR_TOTEM].includes(dbentry.subclass)))
        {
            const hint = classHints?.get(itemId);
            if (hint) ordered[hint].set(itemId, effects);
            else ordered.GENERAL.set(itemId, effects);
            continue;
        }

        if (dbentry.class === LE_ITEM_CLASS_ARMOR && dbentry.subclass == LE_ITEM_ARMOR_IDOL)
        {
            ordered.druid.set(itemId, effects);
        }
        else if (dbentry.class === LE_ITEM_CLASS_ARMOR && dbentry.subclass == LE_ITEM_ARMOR_LIBRAM)
        {
            ordered.paladin.set(itemId, effects);
        }
        else if (dbentry.class === LE_ITEM_CLASS_ARMOR && dbentry.subclass == LE_ITEM_ARMOR_TOTEM)
        {
            ordered.shaman.set(itemId, effects);
        }
        else if (itemId === 20006)
        {
            ordered.priest.set(itemId, effects);
        }
        else if (dbentry.AllowableClass === undefined || (dbentry.AllowableClass & allClasses) === allClasses)
        {
            ordered.GENERAL.set(itemId, effects);
        }
        else
        {
            for (const className in classMask)
            {
                if ((dbentry.AllowableClass ?? 0) & classMask[className as keyof typeof classMask])
                {
                    ordered[className as keyof typeof classMask].set(itemId, effects);
                }
            }
        }
    }

    return ordered;
}

/**
 * Return string of format
 * {
 *     type = type,
 *     [affectMask = affectMask,]
 *     [affectSpell = affectSpell,]
 *     [value = value]
 * },\n
 * @param indent 
 * @param eff 
 */
export function createEffectLua(indent: string, eff: AddonEffectData, additionalMembers?: { [key: string]: any })
{
    let lua = `${indent}{\n`;
    lua += `${indent}    type = ${eff.type},\n`;
    if (eff.affectMask) lua += `${indent}    affectMask = ${eff.affectMask},\n`;
    if (eff.affectSpell) lua += `${indent}    affectSpell = {${eff.affectSpell.join(", ")}},\n`;
    if (typeof eff.value !== "undefined") lua += `${indent}    value = ${eff.value},\n`;
    if (typeof eff.scriptKey !== "undefined") lua += `${indent}    scriptKey = "${eff.scriptKey}",\n`;
    if (eff.hasStacks) lua += `${indent}    hasStacks = true,\n`;
    if (eff.affectMechanic) lua += `${indent}    affectMechanic = ${eff.affectMechanic},\n`;
    if (eff.neededWeaponMask) lua += `${indent}    neededWeaponMask = ${eff.neededWeaponMask},\n`;
    if (eff.auraCategory) lua += `${indent}    auraCategory = ${eff.auraCategory},\n`;
    if (additionalMembers)
    {
        for (const k in additionalMembers)
        {
            lua += `${indent}    ${k} = ${additionalMembers[k]},\n`;
        }
    }
    lua += `${indent}},\n`;
    return lua;
}

/**
 * Create a head for a data file.
 * @param classNameRestriction
 * @returns 
 */
export function createFileHead(classNameRestriction?: string)
{
    const build = getBuildInfo();
    const head = `-- GENERATED by tools/spelldata_creator from World of Warcraft: Forever client build ${build.version} - DO NOT EDIT!\n`;

    if (classNameRestriction)
    {
        return head + `
---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "${classNameRestriction.toUpperCase()}" then
    return;
end

`;
    }

    return head + `
---@class AddonEnv
local _addon = select(2, ...);

`;
}