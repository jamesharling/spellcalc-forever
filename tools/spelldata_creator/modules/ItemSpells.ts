import { readDBCSVtoMap } from "../CSVReader";
import { cfg } from "../config";
import { createFileHead, getItemDbData } from "../itemFunctions";
import { report } from "../report";
import { SpellData, SpellEffect } from "../SpellData";

/**
 * Use effects of items that heal or deal damage: potions, healthstones, bandages, explosives and trinkets
 * such as Blessed Prayer Beads. Their spells get the same rank info as class spells, so tooltips and action bar
 * values work for the item, and an item -> use spell map tells the addon which spell an item action casts.
 *
 * Only the first heal or damage effect of a use spell is kept (a sapper charge also hurts its user, a
 * potion may also restore mana); anything the spell does besides that is left out.
 */

interface ItemEffectRow
{
    ID: number,
    LegacySlotIndex: number,
    TriggerType: number,
    Charges: number,
    CoolDownMSec: number,
    CategoryCoolDownMSec: number,
    SpellCategoryID: number,
    SpellID: number,
    ChrSpecializationID: number,
    PlayerConditionID: number
}

interface ItemXItemEffectRow
{
    ID: number,
    ItemEffectID: number,
    ItemID: number
}

/** ItemEffect.TriggerType of a "Use:" effect. */
const TRIGGER_ON_USE = 0;

/** Effects worth showing a value for. */
const VALUE_EFFECTS = new Set<number>([
    EFFECT_TYPE.SPELL_EFFECT_HEAL,
    EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE,
    EFFECT_TYPE.SPELL_EFFECT_HEALTH_LEECH,
]);
const VALUE_AURAS = new Set<number>([
    AURA_TYPE.SPELL_AURA_PERIODIC_HEAL,
    AURA_TYPE.SPELL_AURA_PERIODIC_DAMAGE,
    AURA_TYPE.SPELL_AURA_PERIODIC_LEECH,
    AURA_TYPE.SPELL_AURA_SCHOOL_ABSORB,
]);

/** Item classes whose use effects are not for the calculator. */
const SKIP_ITEM_CLASSES = new Set<number>([ItemClass.ITEM_CLASS_QUEST, ItemClass.ITEM_CLASS_KEY]);

/** Items that exist in the tables but not in the game: test, deprecated and placeholder entries. */
const NOT_IN_GAME = /\b(test|deprecated|dnt|debug|placeholder|unused|do not use)\b|\(test\)|\[ph\]|^monster\b/i;

function isValueEffect(effect: SpellEffect)
{
    if (VALUE_EFFECTS.has(effect.Effect)) return true;
    return effect.Effect === EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA && VALUE_AURAS.has(effect.EffectAura);
}

export class ItemSpells
{
    private readonly spellData: SpellData;
    private readonly buildRankInfo: (spellId: number, effects: SpellEffect[]) => RankInfo;
    private readonly rankInfoToLua: (spellId: string | number, rankInfo: RankInfo) => string;

    /**
     * @param buildRankInfo The generator's rank info builder (throws when a spell is not handled).
     * @param rankInfoToLua The generator's rank info serializer (tab indented, one `[id] = {...},` block).
     */
    constructor(spellData: SpellData, buildRankInfo: (spellId: number, effects: SpellEffect[]) => RankInfo,
        rankInfoToLua: (spellId: string | number, rankInfo: RankInfo) => string)
    {
        this.spellData = spellData;
        this.buildRankInfo = buildRankInfo;
        this.rankInfoToLua = rankInfoToLua;
    }

    /** Item ID -> spell ID of its first "Use:" effect, for items that exist on Forever. */
    private getItemUseSpells()
    {
        const dbData = getItemDbData();
        const itemEffects = readDBCSVtoMap<ItemEffectRow>(cfg.dataDir + "dbc/ItemEffect.csv", "ID");
        const links = readDBCSVtoMap<ItemXItemEffectRow>(cfg.dataDir + "dbc/ItemXItemEffect.csv", "ID");
        const itemUseSpell = new Map<number, number>();
        let notInGame = 0;

        for (const link of links.values())
        {
            const item = dbData[link.ItemID];
            if (!item || SKIP_ITEM_CLASSES.has(item.class)) continue;
            const itemEffect = itemEffects.get(link.ItemEffectID);
            if (!itemEffect || itemEffect.TriggerType !== TRIGGER_ON_USE || !itemEffect.SpellID) continue;
            if (itemUseSpell.has(link.ItemID)) continue;
            if (NOT_IN_GAME.test(item.name))
            {
                notInGame++;
                continue;
            }
            itemUseSpell.set(link.ItemID, itemEffect.SpellID);
        }

        if (notInGame > 0) report(`${notInGame} use items skipped by name (test, deprecated or placeholder items)`);
        return itemUseSpell;
    }

    /** Rank info for a use spell, or undefined if it has nothing to show or is not handled. */
    private buildItemSpell(spellId: number, itemNames: string[]): RankInfo | undefined
    {
        const effects = this.spellData.getSpellEffects(spellId, true);
        const valueEffect = effects?.find(isValueEffect);
        if (!valueEffect) return undefined;

        try
        {
            const rankInfo = this.buildRankInfo(spellId, [valueEffect]);
            // Item spells are often filed under no defense type; treat them as spells so spell crit and hit apply.
            if (rankInfo.defenseType === DEFENSE_TYPE.NONE) rankInfo.defenseType = DEFENSE_TYPE.MAGIC;
            return rankInfo;
        }
        catch (error)
        {
            const msg = error instanceof Error ? error.message : String(error);
            report(`Item use spell ${this.spellData.getSpellNameWithRank(spellId)} [${spellId}] (${itemNames.join(", ")}) skipped: ${msg}`);
            return undefined;
        }
    }

    getLua()
    {
        console.log("Creating Lua for item use spells...");
        const dbData = getItemDbData();
        const itemUseSpell = this.getItemUseSpells();

        // Spell -> items using it (healthstones of one rank share a spell).
        const spellItems = new Map<number, number[]>();
        for (const [itemId, spellId] of itemUseSpell)
        {
            if (!spellItems.has(spellId)) spellItems.set(spellId, []);
            spellItems.get(spellId)!.push(itemId);
        }

        const spells = new Map<number, RankInfo>();
        for (const [spellId, itemIds] of spellItems)
        {
            const names = itemIds.map(id => dbData[id].name);
            const rankInfo = this.buildItemSpell(spellId, names);
            if (rankInfo) spells.set(spellId, rankInfo);
        }

        const spellIds = [...spells.keys()].sort((a, b) => a - b);
        const itemIds = [...itemUseSpell.keys()].filter(id => spells.has(itemUseSpell.get(id)!)).sort((a, b) => a - b);
        console.log(`${spellIds.length} item use spells for ${itemIds.length} items`);

        const clean = (s: string) => String(s).replace(/[\r\n]+/g, " ");

        let str = createFileHead();
        str += "-- Use effects of items that heal or deal damage: potions, healthstones, bandages, explosives and trinkets\n";
        str += "-- such as Blessed Prayer Beads. Only the first heal or damage effect of each use spell is kept. Loaded after the\n";
        str += "-- class spell data; classes the addon does not support get none (see events.lua).\n";
        str += "local _, playerClass = UnitClass(\"player\");\n";
        str += "if _addon.CONST.UNSUPPORTED_CLASSES[playerClass] then\n";
        str += "    return;\n";
        str += "end\n\n";

        str += "---@type SpellInfoTable\n";
        str += "local itemSpells = {\n";
        for (const spellId of spellIds)
        {
            const rankInfo = spells.get(spellId)!;
            const names = spellItems.get(spellId)!.map(id => clean(dbData[id].name));
            rankInfo.spellnamecomment = `${clean(this.spellData.getSpellNameWithRank(spellId))} (${names.slice(0, 4).join(", ")}${names.length > 4 ? ", ..." : ""})`;
            str += this.rankInfoToLua(spellId, rankInfo);
        }
        str += "};\n";
        str += "for spellId, info in pairs(itemSpells) do\n";
        str += "    if not _addon.spellInfo[spellId] then\n";
        str += "        _addon.spellInfo[spellId] = info;\n";
        str += "    end\n";
        str += "end\n\n";

        str += "---Item ID -> spell ID of its use effect.\n";
        str += "---@type table<integer, integer>\n";
        str += "_addon.itemUseSpells = {\n";
        for (const itemId of itemIds)
        {
            str += `\t[${itemId}] = ${itemUseSpell.get(itemId)}, -- ${clean(dbData[itemId].name)}\n`;
        }
        str += "};\n";

        return str.replace(/\t/gm, "    ");
    }
}
