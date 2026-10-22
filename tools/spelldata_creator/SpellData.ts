import * as fs from "fs";
import { fixSpellEffects } from "./spellDataFixes";
import { isSeal } from "./paladinCrap";
import { readDBCSV } from "./CSVReader";
import { cfg } from "./config";

const AUTO_ATTACK_ID = 6603;

export interface SpellLevel
{
    ID: number,
    DifficultyID: number,
    BaseLevel: number,
    MaxLevel: number,
    SpellLevel: number,
    MaxPassiveAuraLevel: number,
    SpellID: number
}

/**
 * SpellEffect row (Forever / Mainline schema).
 * Values: EffectBasePointsF is the mean value, Variance the spread (see effectValues.ts).
 */
export interface SpellEffect
{
    ID: number,
    DifficultyID: number,
    EffectIndex: number,
    Effect: number,
    EffectAmplitude: number,
    EffectAttributes: number,
    EffectAura: number,
    EffectAuraPeriod: number,
    EffectBasePointsF: number,
    EffectBonusCoefficient: number,
    EffectChainAmplitude: number,
    EffectChainTargets: number,
    EffectItemType: number,
    EffectMechanic: number,
    EffectPointsPerResource: number,
    EffectPos_facing: number,
    EffectRealPointsPerLevel: number,
    EffectTriggerSpell: number,
    BonusCoefficientFromAP: number,
    PvpMultiplier: number,
    Coefficient: number,
    Variance: number,
    ResourceCoefficient: number,
    GroupSizeBasePointsCoefficient: number,
    ScalingClass: number,
    EffectMiscValue_0: number,
    EffectMiscValue_1: number,
    EffectRadiusIndex_0: number,
    EffectRadiusIndex_1: number,
    EffectSpellClassMask_0: number,
    EffectSpellClassMask_1: number,
    EffectSpellClassMask_2: number,
    EffectSpellClassMask_3: number,
    ImplicitTarget_0: number,
    ImplicitTarget_1: number,
    SpellID: number
}

export interface SpellClassOptions
{
    ID: number,
    SpellID: number,
    ModalNextSpell: number,
    SpellClassSet: number,
    SpellClassMask_0: number,
    SpellClassMask_1: number,
    SpellClassMask_2: number,
    SpellClassMask_3: number,
}

export interface SpellMisc
{
    ID: number,
    DifficultyID: number,
    CastingTimeIndex: number,
    DurationIndex: number,
    RangeIndex: number,
    SchoolMask: SCHOOL_MASK,
    Speed: number,
    LaunchDelay: number,
    MinDuration: number,
    SpellIconFileDataID: number,
    ActiveIconFileDataID: number,
    Attributes_0: number,
    Attributes_1: number,
    Attributes_2: number,
    Attributes_3: number,
    Attributes_4: number,
    Attributes_5: number,
    Attributes_6: number,
    Attributes_7: number,
    Attributes_8: number,
    Attributes_9: number,
    Attributes_10: number,
    Attributes_11: number,
    Attributes_12: number,
    Attributes_13: number,
    Attributes_14: number,
    Attributes_15: number,
    Attributes_16: number,
    SpellID: number
}

export interface SpellCategory
{
    DefenseType: DEFENSE_TYPE,
    DifficultyID: number,
    Mechanic: number,
}

export interface SpellName
{
    ID: number
    Name_lang: string
}

export interface Spell
{
    ID: number,
    NameSubtext_lang: string,
    Description_lang: string,
    AuraDescription_lang: string
}

export interface SpellDuration
{
    ID: number,
    Duration: number,
    MaxDuration: number,
    DurationPerResource: number
}

export interface SpellCooldown
{
    DifficultyID: number,
    CategoryRecoveryTime: number,
    RecoveryTime: number,
    StartRecoveryTime: number,
    SpellID: number
}

export interface SpellPower
{
    ID: number,
    OrderIndex: number,
    ManaCost: number,
    ManaCostPerLevel: number,
    ManaPerSecond: number,
    PowerCostPct: number,
    PowerCostMaxPct: number,
    PowerPctPerSecond: number,
    PowerType: number,
    OptionalCost: number,
    SpellID: number
}

export interface SpellEquippedItems
{
    ID: number,
    SpellID: number,
    EquippedItemClass: ItemClass,
    EquippedItemInvTypes: number,
    EquippedItemSubclass: number
}

export interface SpellAuraOptions
{
    ID: number,
    DifficultyID: number,
    CumulativeAura: number,
    ProcCategoryRecovery: number,
    ProcChance: number,
    ProcCharges: number,
    SpellProcsPerMinuteID: number,
    ProcTypeMask_0: number,
    ProcTypeMask_1: number,
    SpellID: number,
}

export class SpellData
{
    readonly spellEffectsBySpellId = new Map<number, SpellEffect[]>();
    private readonly spellsByName: { [spellName: string]: number[] } = {};
    private readonly spellLevels: { [index: number]: SpellLevel };
    private readonly spellMiscs: { [index: number]: SpellMisc };
    private readonly spellNames: { [index: number]: SpellName };
    private readonly spell: { [index: number]: Spell };
    private readonly spellDuration: { [index: number]: SpellDuration };
    private readonly totemSpells: { [index: number]: number };
    readonly spellCategories: { [index: number]: SpellCategory };
    private readonly spellCooldowns: { [index: number]: SpellCooldown };
    private readonly spellPowerCost: { [index: number]: SpellPower };
    private readonly spellPowerCostBySpell = new Map<number, SpellPower[]>();
    readonly spellClassOptions: { [index: number]: SpellClassOptions };
    private readonly spellClassOptionsBySpell = new Map<number, SpellClassOptions>();
    private readonly spellEquippedItems: { [index: number]: SpellEquippedItems };
    private readonly spellAuraOptions: { [index: number]: SpellAuraOptions };

    constructor()
    {
        console.log("Creating SpellData");

        const baseDir = cfg.dataDir;

        this.spellNames = readDBCSV<SpellName>(baseDir + "dbc/SpellName.csv", "ID");
        // The CSV reader turns numeric looking fields into numbers; names must stay strings.
        for (const id in this.spellNames) this.spellNames[id].Name_lang = String(this.spellNames[id].Name_lang);
        this.spell = readDBCSV<Spell>(baseDir + "dbc/Spell.csv", "ID");
        this.spellDuration = readDBCSV<SpellDuration>(baseDir + "dbc/SpellDuration.csv", "ID");
        this.spellCategories = readDBCSV<SpellCategory>(baseDir + "dbc/SpellCategories.csv", "SpellID", [{ key: "DifficultyID", is: 0 }]);
        this.spellCooldowns = readDBCSV<SpellCooldown>(baseDir + "dbc/SpellCooldowns.csv", "SpellID", [{ key: "DifficultyID", is: 0 }]);
        this.spellPowerCost = readDBCSV<SpellPower>(baseDir + "dbc/SpellPower.csv", "ID");
        this.spellClassOptions = readDBCSV<SpellClassOptions>(baseDir + "dbc/SpellClassOptions.csv", "SpellID");
        this.spellEquippedItems = readDBCSV<SpellEquippedItems>(baseDir + "dbc/SpellEquippedItems.csv", "SpellID");
        this.spellAuraOptions = readDBCSV<SpellAuraOptions>(baseDir + "dbc/SpellAuraOptions.csv", "SpellID", [{ key: "DifficultyID", is: 0 }]);
        this.totemSpells = JSON.parse(fs.readFileSync(baseDir + "totemSpells.json", "utf8"));
        this.spellMiscs = readDBCSV<SpellMisc>(baseDir + "dbc/SpellMisc.csv", "SpellID", [{ key: "DifficultyID", is: 0 }]);
        this.spellLevels = readDBCSV<SpellLevel>(baseDir + "dbc/SpellLevels.csv", "SpellID", [{ key: "DifficultyID", is: 0 }]);

        for (const costId in this.spellPowerCost)
        {
            const cost = this.spellPowerCost[costId];
            if (!this.spellPowerCostBySpell.has(cost.SpellID)) this.spellPowerCostBySpell.set(cost.SpellID, []);
            this.spellPowerCostBySpell.get(cost.SpellID)!.push(cost);
        }

        for (const scoId in this.spellClassOptions)
        {
            const sco = this.spellClassOptions[scoId];
            this.spellClassOptionsBySpell.set(sco.SpellID, sco);
        }

        {
            // Only the base difficulty; dungeon/raid difficulties duplicate effects of creature spells.
            const spellEffects = readDBCSV<SpellEffect>(baseDir + "dbc/SpellEffect.csv", "ID", [{ key: "DifficultyID", is: 0 }]);
            for (let effectId in spellEffects)
            {
                const spellId = spellEffects[effectId].SpellID;
                if (!this.spellEffectsBySpellId.has(spellId)) this.spellEffectsBySpellId.set(spellId, []);
                this.spellEffectsBySpellId.get(spellId)!.push(spellEffects[effectId]);
            }
        }

        for (const [spellId, effects] of this.spellEffectsBySpellId)
        {
            // Build name list
            const nameEntry = this.getSpellName(spellId, true);
            if (nameEntry)
            {
                const name = nameEntry.Name_lang;
                if (!this.spellsByName[name]) this.spellsByName[name] = [];
                this.spellsByName[name].push(spellId);
            }

            // make sure direct dmg is always the 1st effect on spells that also have a duration effect
            if (isSeal(spellId)) continue;

            for (const effect1 of effects)
            {
                if (effect1.EffectIndex != 1 || effect1.Effect != EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE) continue;

                for (const effect2 of effects)
                {
                    if (effect2.EffectIndex != 0 || effect2.Effect != EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA) continue;
                    // Put the direct damage effect first (the addon expects it in slot 1)
                    effect1.EffectIndex = 0;
                    effect2.EffectIndex = 1;
                    break;
                }
            }
        }

        for (const effects of this.spellEffectsBySpellId.values())
        {
            effects.sort((a, b) => a.EffectIndex - b.EffectIndex);
        }

        fixSpellEffects(this);

        console.log("SpellData created!");
    }

    /**
     * Does the spell exist in the client data (name and misc entry)?
     * The Forever tables still reference many removed Classic Era spells (ranks, old talents).
     */
    spellExists(spellId: number)
    {
        return !!this.spellNames[spellId] && !!this.spellMiscs[spellId];
    }

    getSpellsByName(spellName: string): number[]
    getSpellsByName(spellName: string, noerr: true): number[] | undefined
    getSpellsByName(spellName: string, noerr = false)
    {
        if (!this.spellsByName[spellName])
        {
            if (noerr) return;
            throw new Error("No spells with name " + spellName + " exist!");
        }
        return this.spellsByName[spellName];
    }

    getSpellEffects(spellId: number): SpellEffect[]
    getSpellEffects(spellId: number, noerr: true): SpellEffect[] | undefined
    getSpellEffects(spellId: number, noerr = false)
    {
        const effects = this.spellEffectsBySpellId.get(spellId);
        if (!effects)
        {
            if (noerr) return;
            throw new Error("Spell effect(s) not found for " + spellId);
        }
        return effects;
    }

    getSpellLevel(spellId: number): SpellLevel
    getSpellLevel(spellId: number, noerr: true): SpellLevel | undefined
    getSpellLevel(spellId: number, noerr = false)
    {
        if (this.spellLevels[spellId]) return this.spellLevels[spellId];

        if (spellId == AUTO_ATTACK_ID
            || spellId == 23590)
        {
            return SpellData.emptySpellLevel(spellId);
        }

        if (noerr) return;
        throw new Error("Spelllevel not found for " + spellId);
    }

    static emptySpellLevel(spellId: number): SpellLevel
    {
        return {
            ID: 0,
            DifficultyID: 0,
            BaseLevel: 0,
            MaxLevel: 0,
            SpellLevel: 0,
            MaxPassiveAuraLevel: 0,
            SpellID: spellId
        }
    }

    getSpellMisc(spellId: number): SpellMisc
    getSpellMisc(spellId: number, noErr: true): SpellMisc | undefined
    getSpellMisc(spellId: number, noErr = false)
    {
        if (this.spellMiscs[spellId]) return this.spellMiscs[spellId];
        if (noErr) return;
        throw new Error("Spellmisc not found for " + spellId);
    }

    getSpellName(spellId: number): SpellName
    getSpellName(spellId: number, noerr: true): SpellName | undefined
    getSpellName(spellId: number, noErr = false)
    {
        if (this.spellNames[spellId]) return this.spellNames[spellId];
        if (noErr) return;
        throw new Error("Spellname not found for " + spellId);
    }

    /**
     * Spell name with rank subtext, for comments: "Fireball (Rank 2)".
     */
    getSpellNameWithRank(spellId: number)
    {
        const name = this.getSpellName(spellId, true)?.Name_lang ?? ("spell " + spellId);
        const subtext = this.spell[spellId]?.NameSubtext_lang;
        return name + ((subtext && subtext.length) ? ` (${subtext})` : "");
    }

    getSpell(spellId: number): Spell
    getSpell(spellId: number, noerr: true): Spell | undefined
    getSpell(spellId: number, noErr = false)
    {
        if (this.spell[spellId]) return this.spell[spellId];
        if (noErr) return;
        throw new Error("Spellspell not found for " + spellId);
    }

    getSpellDuration(durationId: number)
    {
        if (this.spellDuration[durationId])
        {
            return this.spellDuration[durationId];
        }
        throw new Error("Spellduration not found " + durationId);
    }

    getTotemSpell(totemId: number): number | undefined
    {
        return this.totemSpells[totemId];
    }

    getSpellCategory(spellId: number)
    {
        if (this.spellCategories[spellId]) return this.spellCategories[spellId];

        if (spellId == AUTO_ATTACK_ID)
        {
            let sc: SpellCategory = {
                DefenseType: DEFENSE_TYPE.MELEE,
                DifficultyID: 0,
                Mechanic: 0,
            }
            return sc;
        }

        if (spellId == 23590 || spellId == 20168 || this.getSpellName(spellId, true)?.Name_lang == "Healing Stream Totem")
        {
            let sc: SpellCategory = {
                DefenseType: DEFENSE_TYPE.NONE,
                DifficultyID: 0,
                Mechanic: 0,
            }
            return sc;
        }

        return;
    }

    getSpellCooldown(spellId: number)
    {
        if (this.spellCooldowns[spellId]) return this.spellCooldowns[spellId];

        let sc: SpellCooldown = {
            DifficultyID: 0,
            CategoryRecoveryTime: 0,
            StartRecoveryTime: 1500,
            RecoveryTime: 0,
            SpellID: AUTO_ATTACK_ID
        }
        return sc;
    }

    getSpellPowerCosts(spellId: number): SpellPower[]
    {
        return this.spellPowerCostBySpell.get(spellId) ?? [];
    }

    getSpellClassOption(spellId: number): SpellClassOptions
    getSpellClassOption(spellId: number, noerr: true): SpellClassOptions | undefined
    getSpellClassOption(spellId: number, noerr = false)
    {
        const sco = this.spellClassOptionsBySpell.get(spellId);
        if (sco) return sco;
        if (noerr) return;
        throw new Error("No spell class options for spell " + spellId);
    }

    getSpellClassOptions()
    {
        return this.spellClassOptions;
    }

    getSpellEquipeedItems(spellId: number): SpellEquippedItems | undefined
    {
        return this.spellEquippedItems[spellId];
    }

    getSpellAuraOptions(spellId: number): SpellAuraOptions | undefined
    {
        return this.spellAuraOptions[spellId];
    }
}
