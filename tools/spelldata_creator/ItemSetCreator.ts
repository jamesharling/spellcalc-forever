import { ClassSpellLists } from "./ClassSpellLists";
import { ClassSpellSets } from "./ClassSpellSets";
import { cfg } from "./config";
import { readDBCSVtoMap } from "./CSVReader";
import { AuraHandlers, USELESS_AURAS } from "./ItemAuraHandlers";
import { classFromSpells, createEffectLua, createFileHead, getItemDbData, orderItemsByClass } from "./itemFunctions";
import { SpellData } from "./SpellData";
import { report } from "./report";

const AURA_TYPES_TO_IGNORE: { [index: number]: true | undefined } = {

}
Object.assign(AURA_TYPES_TO_IGNORE, USELESS_AURAS);

interface ItemSet
{
    ID: number,
    Name_lang: string,
    SetFlags: number,
    RequiredSkill: number,
    RequiredSkillRank: number,
    ItemID_0: number,
    ItemID_1: number,
    ItemID_2: number,
    ItemID_3: number,
    ItemID_4: number,
    ItemID_5: number,
    ItemID_6: number,
    ItemID_7: number,
    ItemID_8: number,
    ItemID_9: number,
    ItemID_10: number,
    ItemID_11: number,
    ItemID_12: number,
    ItemID_13: number,
    ItemID_14: number,
    ItemID_15: number,
    ItemID_16: number
}

interface ItemSetSpell
{
    ID: number,
    ChrSpecID: number,
    SpellID: number,
    Threshold: number,
    ItemSetID: number
}

interface ItemSparse
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

interface ItemSetAddonData
{
    ID: number,
    name: string,
    items: number[],
    /** Bonus spells of the set, to infer the class when no item has a detail row. */
    spellIds: number[],
    effects: {
        need: number,
        effect: AddonEffectData
    }[]
}

export class ItemSetCreator
{
    private readonly spellData: SpellData;
    private readonly auraHandlers: AuraHandlers;

    private readonly itemsparse = new Map<number, ItemSparse>();
    private readonly setIdToSparse = new Map<number, ItemSparse[]>();

    constructor(spellData: SpellData, classSpellLists: ClassSpellLists, classSpellSets: ClassSpellSets)
    {
        this.spellData = spellData;
        this.auraHandlers = new AuraHandlers(spellData, classSpellLists, classSpellSets);

        this.itemsparse = readDBCSVtoMap<ItemSparse>(cfg.dataDir + "dbc/ItemSparse.csv", "ID");

        for (const sparse of this.itemsparse.values())
        {
            if (!sparse.ItemSet) continue;
            if (!this.setIdToSparse.has(sparse.ItemSet))
                this.setIdToSparse.set(sparse.ItemSet, []);
            const setMap = this.setIdToSparse.get(sparse.ItemSet)!;
            setMap.push(sparse);
        }
    }

    /**
     * Process spell and return addon effect data if spell has a valid effect.
     * @param spellId 
     */
    private processSpell(spellId: number): AddonEffectData[]
    {
        const spellEffects = this.spellData.getSpellEffects(spellId, true);
        const aedarr: AddonEffectData[] = [];

        if (!spellEffects)
        {
            report(`Item set bonus spell ${spellId} has no effects, skipped`);
            return aedarr;
        }

        for (let spellEffect of spellEffects)
        {
            if (spellId === 24746 || spellId === 67191 || spellId === 70847 || spellId === 70844
                || spellId === 70656) continue;
            if (spellEffect.Effect !== EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA)
            {
                report(`Item set bonus spell ${spellId} effect ${spellEffect.EffectIndex} doesn't apply an aura (effect ${spellEffect.Effect}), skipped`);
                continue;
            }
            if (AURA_TYPES_TO_IGNORE[spellEffect.EffectAura]) continue;
            if (!this.auraHandlers.handlers[spellEffect.EffectAura])
            {
                report(`Item set bonus spell ${spellId} effect ${spellEffect.EffectIndex}: aura type ${spellEffect.EffectAura} is not handled, skipped`);
                continue;
            }
            try
            {
                const aed = this.auraHandlers.handlers[spellEffect.EffectAura](spellEffect);
                if (aed) aedarr.push(aed);
            }
            catch (error)
            {
                report(`Item set bonus spell ${spellId} effect ${spellEffect.EffectIndex}: ${error}`);
            }
        }

        return aedarr;
    }

    /**
     * Get real set items from item if item is "placeholder" for set items, e.e. for 10 and 25 versions.
     * @param itemId 
     * @returns 
     */
    private getSetItemsForItem(itemId: number)
    {
        const sparse = this.itemsparse.get(itemId);
        if (!sparse) return;
        const setId = sparse.ItemSet;
        const setItemList = this.setIdToSparse.get(setId);
        if (!setItemList) return;
        const invType = sparse.InventoryType;
        const items: number[] = [];

        for (const setItem of setItemList)
        {
            if (setItem.InventoryType === invType)
                items.push(setItem.ID);
        }

        if (items.length == 0) return;
        return items;
    }

    /**
     * Process data for item set.
     * @param setDataEntry 
     * @param spellsbyItemSet 
     * @returns Itemset data if set has valid spell effects on any bonus.
     */
    private getAddonDataForSet(setDataEntry: ItemSet, spellsbyItemSet: Map<number, ItemSetSpell[]>)
    {
        const setSpells = spellsbyItemSet.get(setDataEntry.ID);
        const setAddonData: ItemSetAddonData = {
            ID: setDataEntry.ID,
            name: setDataEntry.Name_lang,
            items: [],
            spellIds: (setSpells ?? []).map(entry => entry.SpellID),
            effects: []
        }

        if (!setSpells)
        {
            console.log(setDataEntry.ID + ": " + setDataEntry.Name_lang + " has no spells assinged, SKIPPING!");
            return;
        }

        for (let i = 0; i <= 16; i++)
        {
            const itemId = setDataEntry[("ItemID_" + i) as keyof ItemSet] as number;
            if (itemId != 0)
            {
                const realItems = this.getSetItemsForItem(itemId);
                if (realItems)
                {
                    setAddonData.items.push(...realItems);
                }
                else
                {
                    setAddonData.items.push(itemId);
                }
            }
        }

        for (let setSpellEntry of setSpells)
        {
            const aedarr = this.processSpell(setSpellEntry.SpellID);
            for (let aed of aedarr)
            {
                setAddonData.effects.push({
                    need: setSpellEntry.Threshold,
                    effect: aed
                });
            }
        }

        if (setAddonData.effects.length === 0)
        {
            console.log(setDataEntry.ID + ": " + setDataEntry.Name_lang + " has no valid spells, SKIPPING!");
            return;
        }

        if (setAddonData.items.length === 0)
        {
            console.log("Item set " + setAddonData.name + " has no items!");
            return;
        }

        return setAddonData;
    }

    /**
     * Get item set spells mapped by item set ID.
     */
    private getSpellsByItemSet()
    {
        console.log("Mapping set spells...");
        const itemSetSpellData = readDBCSVtoMap<ItemSetSpell>(cfg.dataDir + "dbc/ItemSetSpell.csv", "ID");
        const spellsbyItemSet = new Map<number, ItemSetSpell[]>();

        for (let spellEntry of itemSetSpellData.values())
        {
            if (!spellsbyItemSet.has(spellEntry.ItemSetID)) spellsbyItemSet.set(spellEntry.ItemSetID, []);
            spellsbyItemSet.get(spellEntry.ItemSetID)!.push(spellEntry);
        }

        for (let setSpells of spellsbyItemSet.values())
        {
            setSpells.sort((a, b) =>
            {
                return a.Threshold - b.Threshold;
            });
        }

        console.log("Mapped " + spellsbyItemSet.size + " set spells!");
        return spellsbyItemSet;
    }

    /**
     * Get processed data of all valid item sets.
     */
    private getProcessedSetData()
    {
        const spellsbyItemSet = this.getSpellsByItemSet();
        const itemSetData = readDBCSVtoMap<ItemSet>(cfg.dataDir + "dbc/ItemSet.csv", "ID");
        const setAddonExportData = new Map<number, ItemSetAddonData>();

        console.log("Creating data for sets...");
        for (const setDataEntry of itemSetData.values())
        {
            const addonSetData = this.getAddonDataForSet(setDataEntry, spellsbyItemSet);
            if (addonSetData) 
            {
                console.log(setDataEntry.ID + ": " + setDataEntry.Name_lang + " added!");
                setAddonExportData.set(setDataEntry.ID, addonSetData);
            }
        }

        console.log("Created " + setAddonExportData.size + " set data entries!");
        return setAddonExportData;
    }

    /**
     * Get Lua code for item set data file.
     */
    async getItemSetLua()
    {
        console.log("Creating Lua for  item set data...");
        const processedData = this.getProcessedSetData();

        // Represent each set by one of its items (the class ordering looks it up in the item DB). Prefer an
        // item with a detail row; sets made of hotfix-only items get their class from the bonus spells.
        const dbData = getItemDbData();
        const itemToSetId = new Map<number, ItemSetAddonData>();
        const classHints = new Map<number, ReturnType<typeof classFromSpells>>();
        for (const setData of processedData.values())
        {
            const representative = setData.items.find(itemId => dbData[itemId]?.hasDetails)
                ?? setData.items.find(itemId => !!dbData[itemId]);
            if (typeof representative === "undefined")
            {
                report(`Item set ${setData.ID} (${setData.name}): none of its items exist in Forever (no exported or hotfix detail row), skipped`);
                continue;
            }
            if (!dbData[representative].hasDetails)
            {
                const cls = classFromSpells(this.spellData, setData.spellIds);
                classHints.set(representative, cls);
                report(`Item set ${setData.ID} (${setData.name}): no item has a detail row (hotfix-only items), ${cls ? "class " + cls + " inferred from its bonus spells" : "placed in the class-neutral file"}`);
            }
            itemToSetId.set(representative, setData);
        }
        const ordered = await orderItemsByClass(itemToSetId, classHints);

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

        luaStrings.GENERAL = createFileHead();
        luaStrings.GENERAL += "---@type ItemSetDataTable\n";
        luaStrings.GENERAL += "_addon.itemSetData = {\n";

        for (const setData of ordered.GENERAL.values())
        {
            luaStrings.GENERAL += `    [${setData.ID}] = {\n`;
            luaStrings.GENERAL += `        name = "${setData.name}",\n`;
            luaStrings.GENERAL += `        effects = {\n`;
            for (let i = 0; i < setData.effects.length; i++)
            {
                luaStrings.GENERAL += createEffectLua("            ", setData.effects[i].effect, { need: setData.effects[i].need });
            }
            luaStrings.GENERAL += `        }\n`;
            luaStrings.GENERAL += `    },\n`;
        }

        luaStrings.GENERAL += `}\n\n---@type SetItemDataTable\n_addon.setItemData = {\n`;

        for (const setData of ordered.GENERAL.values())
        {
            for (const itemId of setData.items)
            {
                luaStrings.GENERAL += `    [${itemId}] = ${setData.ID},\n`
            }
        }

        luaStrings.GENERAL += "}";

        for (const className in ordered)
        {
            if (className == "GENERAL") continue;

            luaStrings[className as keyof typeof ordered] = createFileHead(className);

            for (const setData of ordered[className as keyof typeof ordered].values())
            {
                let entrystr = `_addon.itemSetData[${setData.ID}] = {\n`;
                entrystr += `    name = "${setData.name}",\n`;
                entrystr += `    effects = {\n`;
                for (let i = 0; i < setData.effects.length; i++)
                {
                    entrystr += createEffectLua("        ", setData.effects[i].effect, { need: setData.effects[i].need });
                }
                entrystr += `    }\n`;
                entrystr += `}\n`;
                for (const itemId of setData.items)
                {
                    const sparse = this.itemsparse.get(itemId);
                    if (sparse)
                    {
                        entrystr += `_addon.setItemData[${itemId}] = ${setData.ID}; -- ${sparse.Display_lang}\n`
                    }
                    else
                    {
                        entrystr += `_addon.setItemData[${itemId}] = ${setData.ID};\n`
                    }
                }
                entrystr += "\n";

                luaStrings[className as keyof typeof ordered] += entrystr;
            }
        }

        console.log("Lua item set data created!");
        return luaStrings;
    }
}

