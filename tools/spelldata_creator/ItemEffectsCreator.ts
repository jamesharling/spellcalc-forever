import { ClassSpellLists } from "./ClassSpellLists";
import { ClassSpellSets } from "./ClassSpellSets";
import { cfg } from "./config";
import { readDBCSVtoMap } from "./CSVReader";
import { AuraHandlers, USELESS_AURAS } from "./ItemAuraHandlers";
import { createEffectLua, createFileHead, getItemDbData, orderItemsByClass } from "./itemFunctions";
import { SpellData } from "./SpellData";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { report } from "./report";

const AURA_TYPES_TO_IGNORE: { [index: number]: true | undefined } = {
    [AURA_TYPE.SPELL_AURA_PERIODIC_DAMAGE_PERCENT]: true,
    [AURA_TYPE.SPELL_AURA_PERIODIC_DAMAGE]: true,
    [AURA_TYPE.SPELL_AURA_PROC_TRIGGER_DAMAGE]: true,
    [AURA_TYPE.SPELL_AURA_DAMAGE_SHIELD]: true,
    [AURA_TYPE.SPELL_AURA_MOD_RANGED_AMMO_HASTE]: true,
    [AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL]: true,
    [AURA_TYPE.SPELL_AURA_PERIODIC_HEAL]: true,
    [AURA_TYPE.SPELL_AURA_PROC_TRIGGER_SPELL]: true,
    [AURA_TYPE.SPELL_AURA_SCHOOL_ABSORB]: true,
    [AURA_TYPE.OVERRIDE_ACTIONBAR_SPELLS]: true,
    [AURA_TYPE.PERIODIC_DUMMY]: true,
    [AURA_TYPE.MOD_ENVIRONMENTAL_DAMAGE_TAKEN]: true,
}
Object.assign(AURA_TYPES_TO_IGNORE, USELESS_AURAS);

interface ItemEffect
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

/** Links item effects to items; replaces ItemEffect.ParentItemID of the Classic Era schema. */
interface ItemXItemEffect
{
    ID: number,
    ItemEffectID: number,
    ItemID: number
}

interface DbRow
{
    entry: number,
    name: string,
    AllowableClass: number,
    class: number,
    subclass: number
}

export class ItemEffectsCreator
{
    private readonly spellData: SpellData;
    private readonly auraHandlers: AuraHandlers;

    constructor(spellData: SpellData, classSpellLists: ClassSpellLists, classSpellSets: ClassSpellSets)
    {
        this.spellData = spellData;
        this.auraHandlers = new AuraHandlers(spellData, classSpellLists, classSpellSets);
    }

    /**
     * Process spell and return addon effect data if spell has a valid effect.
     * @param spellId 
     */
    private processSpell(spellId: number): AddonEffectData[]
    {
        const spellEffects = this.spellData.getSpellEffects(spellId, true);
        const aedarr: AddonEffectData[] = [];

        if (!spellEffects) return aedarr;

        for (let spellEffect of spellEffects)
        {
            if (spellId === 24746 || spellId === 7363 || spellId === 17816 || spellId === 24748
                || spellId === 24782 || (spellId === 24392 && spellEffect.EffectIndex === 1)
                || spellId === 28143 || spellId === 28144 || spellId === 28145 || spellId === 28142
                || spellId === 28282 || spellId === 24346 || spellId === 50009 || spellId === 48777 || spellId === 62106) continue;
            if (spellEffect.Effect !== EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA)
            {
                switch(spellId)
                {
                    case 4977: // Random questitem
                    case 60837:
                    case 54809:
                    case 62107:
                    case 17232: // Broken SoD item https://www.wowhead.com/classic/item=211940/ecksavs-tribal-guardian
                        continue;
                    default:
                        report(`Item effect spell ${spellId} effect ${spellEffect.EffectIndex} doesn't apply an aura (effect ${spellEffect.Effect}), skipped`);
                        continue;
                }
            }
            if (AURA_TYPES_TO_IGNORE[spellEffect.EffectAura]) continue;
            if (!this.auraHandlers.handlers[spellEffect.EffectAura])
            {
                report(`Item effect spell ${spellId} effect ${spellEffect.EffectIndex}: aura type ${spellEffect.EffectAura} is not handled, skipped`);
                continue;
            }
            try
            {
                const aed = this.auraHandlers.handlers[spellEffect.EffectAura](spellEffect);
                if (aed) aedarr.push(aed);
            }
            catch (error)
            {
                report(`Item effect spell ${spellId} effect ${spellEffect.EffectIndex}: ${error}`);
            }
        }

        return aedarr;
    }

    private getItemEffectData(dbData: { [itemId: number]: DbRow })
    {
        const cacheFile = "cache/itemEffDoneCache_forever.json";
        const itemEffects = readDBCSVtoMap<ItemEffect>(cfg.dataDir + "dbc/ItemEffect.csv", "ID");
        const itemXEffects = readDBCSVtoMap<ItemXItemEffect>(cfg.dataDir + "dbc/ItemXItemEffect.csv", "ID");
        const filteredItems = new Map<number, AddonEffectData[]>();
        let doneEffectIds: { [id: number]: true | AddonEffectData[] };
        let counter = 0;

        // Item effect ID -> item IDs (an effect can be shared by several items)
        const effectToItems = new Map<number, number[]>();
        for (const link of itemXEffects.values())
        {
            if (!effectToItems.has(link.ItemEffectID)) effectToItems.set(link.ItemEffectID, []);
            effectToItems.get(link.ItemEffectID)!.push(link.ItemID);
        }

        try
        {
            if (existsSync(cacheFile))
            {
                console.log("Load item effect cache...");
                doneEffectIds = JSON.parse(readFileSync(cacheFile, "utf-8"));
            }
            else
            {
                doneEffectIds = {};
            }
        }
        catch (error)
        {
            console.log(error);
            process.exit(1);
        }

        console.log("Building item effect data...");

        const logEvery = 500;

        for (const ie of itemEffects.values())
        {
            const fromCache = doneEffectIds[ie.ID];
            const itemIds = (effectToItems.get(ie.ID) ?? []).filter(itemId => !!dbData[itemId]);
            let effects: AddonEffectData[];
            counter++;

            if (counter % logEvery === 0) console.log(`${counter}/${itemEffects.size}`);

            if (!fromCache)
            {
                doneEffectIds[ie.ID] = true;
                if (ie.TriggerType !== 1) continue; // 1 == on equip auras, we can ignore the rest
                // Items not in the DB shouldn't matter
                if (itemIds.length === 0) continue;
                effects = this.processSpell(ie.SpellID);
                if (effects.length === 0) continue;
                doneEffectIds[ie.ID] = effects;
            }
            else
            {
                if (fromCache === true) continue;
                effects = fromCache;
            }

            for (const itemId of itemIds)
            {
                if (!filteredItems.has(itemId)) filteredItems.set(itemId, []);
                const flistentry = filteredItems.get(itemId)!;
                for (const eff of effects)
                {
                    flistentry.push(eff);
                }
            }
        }

        try
        {
            mkdirSync("cache", { recursive: true });
            writeFileSync(cacheFile, JSON.stringify(doneEffectIds, null, 4));
        }
        catch (error)
        {
            console.log("Could not write item effect cache: " + error);
        }

        return filteredItems;
    }

    async getItemEffectLua()
    {
        console.log("Creating Lua for  item effect data...");

        const dbData = getItemDbData();
        const itemEffectData = this.getItemEffectData(dbData);

        const luaStrings = {
            warrior: "",
            paladin: "",
            hunter: "",
            rogue: "",
            priest: "",
            shaman: "",
            mage: "",
            warlock: "",
            druid: "",
            deathknight: "",
            GENERAL: ""
        };

        const ordered = await orderItemsByClass(itemEffectData);

        luaStrings.GENERAL = createFileHead();
        luaStrings.GENERAL += "---@type ItemEffects\n"
        luaStrings.GENERAL += "_addon.itemEffects = {\n";

        for (const [itemId, effects] of ordered.GENERAL)
        {
            luaStrings.GENERAL += `    [${itemId}] = { -- ${dbData[itemId].name}\n`;
            for (let i = 0; i < effects.length; i++)
            {
                luaStrings.GENERAL += createEffectLua("        ", effects[i]);
            }
            luaStrings.GENERAL += `    },\n`;
        }

        luaStrings.GENERAL += `}\n`;

        for (const className in ordered)
        {
            if (className != "GENERAL") luaStrings[className as keyof typeof ordered] = createFileHead(className);
        }

        for (const className in ordered)
        {
            if (className == "GENERAL") continue;

            for (const [itemId, effects] of ordered[className as keyof typeof ordered])
            {
                let entrystr = `_addon.itemEffects[${itemId}] = { -- ${dbData[itemId].name}\n`;
                for (let i = 0; i < effects.length; i++)
                {
                    entrystr += createEffectLua("    ", effects[i]);
                }
                entrystr += `}\n\n`;
                luaStrings[className as keyof typeof ordered] += entrystr;
            }
        }

        console.log("Lua item effect data created!");
        return luaStrings;
    }
}

