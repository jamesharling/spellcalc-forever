import { SpellData, SpellEffect } from "./SpellData";
import * as fs from "fs";
import { isJudgeDummy, isSeal } from "./paladinCrap";
import { cfg } from "./config";
import { getSpellIdFromEffect } from "./effectValues";
import { SkillData } from "./modules/SkillData";
import { TraitData } from "./modules/TraitData";
import { report, reportSection } from "./report";
import { isPlayerClass } from "./helper";

const DO_EFFECTS = [
    EFFECT_TYPE.SPELL_EFFECT_HEAL,
    EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA,
    EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE,
    EFFECT_TYPE.SPELL_EFFECT_HEALTH_LEECH,
    EFFECT_TYPE.SPELL_EFFECT_PERSISTENT_AREA_AURA,
    EFFECT_TYPE.SPELL_EFFECT_SUMMON_TOTEM_SLOT_CLASSIC,
    EFFECT_TYPE.SPELL_EFFECT_WEAPON_PERCENT_DAMAGE,
    EFFECT_TYPE.SPELL_EFFECT_ATTACK,
    EFFECT_TYPE.SPELL_EFFECT_WEAPON_DAMAGE,
    EFFECT_TYPE.SPELL_EFFECT_APPLY_AREA_AURA_PARTY,
    EFFECT_TYPE.SPELL_EFFECT_TRIGGER_SPELL,
    EFFECT_TYPE.SPELL_EFFECT_DUMMY,
    EFFECT_TYPE.SPELL_EFFECT_ENERGIZE_PCT,
    EFFECT_TYPE.SPELL_EFFECT_HEALTH_FUNNEL,
    EFFECT_TYPE.SPELL_EFFECT_NORMALIZED_WEAPON_DMG,
];

const DO_AURAS = [
    AURA_TYPE.SPELL_AURA_PERIODIC_HEAL,
    AURA_TYPE.SPELL_AURA_SCHOOL_ABSORB,
    AURA_TYPE.SPELL_AURA_PERIODIC_DAMAGE,
    AURA_TYPE.SPELL_AURA_PROC_TRIGGER_SPELL,
    AURA_TYPE.SPELL_AURA_PERIODIC_LEECH,
    AURA_TYPE.SPELL_AURA_MANA_SHIELD,
    AURA_TYPE.SPELL_AURA_DAMAGE_SHIELD,
    AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL,
    AURA_TYPE.SPELL_AURA_DUMMY,
    AURA_TYPE.SPELL_AURA_PROC_TRIGGER_DAMAGE,
    AURA_TYPE.SPELL_AURA_OBS_MOD_MANA,
    AURA_TYPE.SPELL_AURA_PERIODIC_ENERGIZE,
    AURA_TYPE.MOD_POWER_REGEN_PERCENT,
    AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL_WITH_VALUE
];

/** Spells whose proc trigger aura is not interesting for the calculator. */
const TRIGGER_SPELL_IGNORE: { [spellName: string]: boolean } = {
    "Feedback": true,
    "Frost Armor": true,
    "Ice Armor": true,
    "Drain Soul": true,
    "Nature's Grasp": true,
    "Seal of Justice": true,
    "Seal of Light": true, // no scaling, no need to handle
    "Seal of Wisdom": true,
    "Barkskin": true,
}

/** Periodic trigger auras to ignore (by spell ID). */
const PTSA_IGNORES = [
    552, 1515, 2893, 1949, 11683, 11684
];

export class ClassSpellLists
{
    private readonly spellData: SpellData;
    private readonly skillData: SkillData;
    private readonly traitData: TraitData;
    private readonly validClassSpells: { [className: string]: Map<number, SpellEffect[]> } = {};
    private readonly judgementRemap: Map<number, number> = new Map<number, number>();

    constructor(spellData: SpellData, skillData: SkillData, traitData: TraitData, classesToDo: string[])
    {
        this.spellData = spellData;
        this.skillData = skillData;
        this.traitData = traitData;

        console.log("Loading class spell lists...");

        for (const className of classesToDo)
        {
            const list = this.createValidSpellList(className);
            this.validClassSpells[className] = list;
        }

        console.log("Done!");
    }

    private addTriggeredSpellIfValid(spellId: number, binaryCache: Map<number, SpellEffect>, list: Map<number, SpellEffect[]>)
    {
        const tspell = this.spellData.getSpellEffects(spellId);
        for (const se of tspell)
        {
            if (se.Effect == EFFECT_TYPE.SPELL_EFFECT_TRIGGER_SPELL) throw new Error("Triggered spell triggers spell!");
            if ((se.Effect == EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA
                || se.Effect == EFFECT_TYPE.SPELL_EFFECT_APPLY_AREA_AURA_PARTY
                || se.Effect == EFFECT_TYPE.SPELL_EFFECT_PERSISTENT_AREA_AURA)
                && (se.EffectAura == AURA_TYPE.SPELL_AURA_PROC_TRIGGER_SPELL
                    || se.EffectAura == AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL
                    || se.EffectAura == AURA_TYPE.SPELL_AURA_ADD_TARGET_TRIGGER)) throw new Error("Triggered spell triggers spell!");
        }
        const validEffects = this.getValidEffectsForSpell(spellId, binaryCache, list);
        if (!validEffects) return false;
        list.set(spellId, validEffects);
        return true;
    }

    private getValidEffectsForSpell(spellId: number, binaryCache: Map<number, SpellEffect>, list: Map<number, SpellEffect[]>)
    {
        const validEffects: SpellEffect[] = [];
        let spellEffects = this.spellData.getSpellEffects(spellId);
        const spellName = this.spellData.getSpellName(spellId).Name_lang;

        for (let i = 0; i < spellEffects.length; i++)
        {
            let effect = spellEffects[i];

            if (DO_EFFECTS.indexOf(effect.Effect) == -1) continue;

            if (effect.Effect == EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA
                || effect.Effect == EFFECT_TYPE.SPELL_EFFECT_PERSISTENT_AREA_AURA
                || effect.Effect == EFFECT_TYPE.SPELL_EFFECT_APPLY_AREA_AURA_PARTY
                || effect.Effect == EFFECT_TYPE.SPELL_EFFECT_HEALTH_FUNNEL)
            {
                if (DO_AURAS.indexOf(effect.EffectAura) == -1)
                {
                    if (effect.EffectMechanic != 0 && effect.EffectIndex != 0)
                    {
                        binaryCache.set(effect.SpellID, effect);
                    }
                    continue;
                };

                if (effect.EffectAura == AURA_TYPE.SPELL_AURA_PROC_TRIGGER_SPELL)
                {
                    if (TRIGGER_SPELL_IGNORE[spellName]) continue;
                    if (!this.addTriggeredSpellIfValid(effect.EffectTriggerSpell, binaryCache, list)) throw new Error("Triggered spell has no valid effects!");
                }

                if (effect.EffectAura == AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL || effect.EffectAura == AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL_WITH_VALUE)
                {
                    if (PTSA_IGNORES.indexOf(effect.SpellID) != -1 || effect.EffectTriggerSpell == 0) continue;
                    const tspell = this.spellData.getSpellEffects(effect.EffectTriggerSpell);
                    let found = false;
                    for (let i = 0; i < tspell.length; i++)
                    {
                        if (tspell[i].Effect == EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE || tspell[i].Effect == EFFECT_TYPE.SPELL_EFFECT_HEAL)
                        {
                            found = true;
                            break;
                        } else if (tspell[i].Effect == EFFECT_TYPE.SPELL_EFFECT_DUMMY)
                        {
                            found = true;
                            break;
                        }
                    }
                    if (!found) throw new Error("PTSA effect has no handled trigger spell effect! " + effect.SpellID);
                    if (!this.addTriggeredSpellIfValid(effect.EffectTriggerSpell, binaryCache, list)) throw new Error("Triggered spell has no valid effects!");
                }

                if (effect.EffectAura == AURA_TYPE.SPELL_AURA_DUMMY)
                {
                    // pala seals
                    if (isJudgeDummy(effect) !== false)
                    {
                        const jspell = this.spellData.getSpellEffects(getSpellIdFromEffect(effect));
                        if (jspell[0].Effect != EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE
                            && jspell[0].Effect != EFFECT_TYPE.SPELL_EFFECT_WEAPON_DAMAGE) continue;
                        if (!list.has(jspell[0].SpellID)) list.set(jspell[0].SpellID, jspell);
                        this.judgementRemap.set(effect.SpellID, jspell[0].SpellID)
                        // don't use this effect
                        continue;
                    }
                    // only add dummy auras we want
                    if (
                        !(effect.EffectIndex == 0 && isSeal(effect.SpellID)) // SoR or SoC attack effect
                        && spellName != "Prayer of Mending"
                        && spellName != "Earth Shield"
                        && !(spellName == "Sacred Shield" && effect.EffectIndex == 0)
                    ) continue;
                }
            }

            if (effect.Effect == EFFECT_TYPE.SPELL_EFFECT_SUMMON_TOTEM_SLOT_CLASSIC)
            {
                if (!this.spellData.getTotemSpell(effect.SpellID)) continue;
            }

            if (effect.Effect == EFFECT_TYPE.SPELL_EFFECT_TRIGGER_SPELL)
            {
                switch (effect.SpellID)
                {
                    case 19752: // Lazy fix for Divine Intervention "for now"
                    case 24858: // Moonkin Form aura trigger
                    case 16979: // Feral Charge
                    case 49376: // Charge Cat
                        continue;
                }

                switch (spellName)
                {
                    case "Arcane Blast":
                        continue;
                }

                const tspell = this.spellData.getSpellEffects(effect.EffectTriggerSpell);
                let found = false;
                for (let i = 0; i < tspell.length; i++)
                {
                    if (tspell[i].Effect == EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE || tspell[i].Effect == EFFECT_TYPE.SPELL_EFFECT_HEAL || tspell[i].Effect == EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA
                        || tspell[i].Effect == EFFECT_TYPE.SPELL_EFFECT_WEAPON_DAMAGE)
                    {
                        found = true;
                        break;
                    } else if (tspell[i].Effect == EFFECT_TYPE.SPELL_EFFECT_DUMMY)
                    {
                        found = true;
                        break;
                    }
                }
                if (!found) throw new Error("SPELL_EFFECT_TRIGGER_SPELL has no handled triggered spell effect! " + effect.SpellID);
                if (!this.addTriggeredSpellIfValid(effect.EffectTriggerSpell, binaryCache, list)) throw new Error("Triggered spell has no valid effects!");
            }

            if (effect.Effect == EFFECT_TYPE.SPELL_EFFECT_DUMMY)
            {
                switch (spellName)
                {
                    case "Starfall":
                    case "Conflagrate":
                        break;
                    default:
                        continue;
                }
            }

            validEffects.push(effect);
        }

        if (validEffects.length === 0) return;
        return validEffects;
    }

    /**
     * Spells to consider for a class: the learnable spells of its skill lines, the spells
     * of its talent tree, and the hand-maintained extras in class_spells/<class>.json.
     * @returns Map spell ID -> source (for reporting)
     */
    private collectClassSpellIds(pclass: string)
    {
        const spells = new Map<number, string>();
        let passives = 0;

        const addSpell = (spellId: number, source: string, skipPassive: boolean) =>
        {
            if (!this.spellData.spellExists(spellId)) return false;
            if (skipPassive && (this.spellData.getSpellMisc(spellId).Attributes_0 & SPELL_ATTR0.SPELL_ATTR_PASSIVE) !== 0)
            {
                // Passive spells (talents, weapon/armor skills) are no castable spells; passive auras
                // with calculator effects are collected by PlayerAuras instead.
                passives++;
                return true;
            }
            if (!spells.has(spellId)) spells.set(spellId, source);
            return true;
        };

        if (isPlayerClass(pclass))
        {
            const lineIds = this.skillData.getClassSkillLineIds(pclass);
            report(`${pclass}: skill lines ${lineIds.map(id => `${id} (${this.skillData.getSkillLineName(id)})`).join(", ")}`);

            let missing = 0;
            for (const [spellId, lineName] of this.skillData.getClassSpells(pclass))
            {
                if (!addSpell(spellId, lineName, true)) missing++;
            }
            report(`${pclass}: ${spells.size} skill line spells, ${passives} passives ignored, ${missing} skill line entries point to removed spells`);

            const before = spells.size;
            const treeId = this.traitData.getClassTreeId(pclass);
            for (const spellId of this.traitData.getTalentSpellIds(treeId))
            {
                addSpell(spellId, "trait tree " + treeId, true);
            }
            report(`${pclass}: ${spells.size - before} additional spells from trait tree ${treeId}`);
        }

        const extrasFile = cfg.dataDir + "class_spells/" + pclass + ".json";
        if (fs.existsSync(extrasFile))
        {
            const extras: { [name: string]: number | string } = JSON.parse(fs.readFileSync(extrasFile, "utf8"));
            for (const name in extras)
            {
                if (name.startsWith("_")) continue;
                const spellId = extras[name];
                if (typeof spellId !== "number") continue;
                if (!addSpell(spellId, "class_spells/" + pclass + ".json", false))
                {
                    report(`${pclass}: extra spell "${name}" (${spellId}) does not exist in the client data`);
                }
            }
        }

        return spells;
    }

    /**
     * Get list of valid/handled spells for a class
     * @param pclass
     */
    private createValidSpellList(pclass: string)
    {
        console.log("Building list of spells for class " + pclass);
        reportSection(`Spell list: ${pclass}`);

        const list: Map<number, SpellEffect[]> = new Map<number, SpellEffect[]>();
        const binaryCache: Map<number, SpellEffect> = new Map<number, SpellEffect>();
        const spells = this.collectClassSpellIds(pclass);

        for (const [spellId, source] of spells)
        {
            try
            {
                const validEffs = this.getValidEffectsForSpell(spellId, binaryCache, list);
                if (validEffs) list.set(spellId, validEffs);
            }
            catch (error)
            {
                const msg = error instanceof Error ? error.message : String(error);
                report(`${this.spellData.getSpellNameWithRank(spellId)} [${spellId}, ${source}] skipped: ${msg}`);
            }
        }

        for (const [spellId, effect] of binaryCache)
        {
            const listEntry = list.get(spellId);
            if (listEntry) listEntry.push(effect);
        }

        console.log(`${pclass}: ${list.size} spells with handled effects out of ${spells.size} candidates`);

        return list;
    }

    /**
     * Get list of spells to handle for a class.
     * @param className
     */
    getListForClass(className: string)
    {
        if (!this.validClassSpells[className]) throw "Invalid class!";
        return this.validClassSpells[className];
    }

    getJudgementRemap()
    {
        return this.judgementRemap;
    }

    /**
     * Check if a spell is handled currently.
     * @param spellId
     */
    isHandledSpell(spellId: number)
    {
        for (const className in this.validClassSpells)
        {
            if (this.validClassSpells[className].has(spellId)) return true;
        }

        return false;
    }
}
