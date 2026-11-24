import { ClassSpellSets } from "../ClassSpellSets";
import { SpellData } from "../SpellData";

/**
 * Talents whose spell data cannot be turned into addon effects automatically.
 * Keyed by talent name. The value per rank is computed from the talent spell's
 * effect values at that rank (TraitDefinitionEffectPoints curves applied), so
 * rebalancing in the client data is picked up; only the meaning of the effects
 * is hand-written here. The generation report lists the resulting values.
 */
export interface TalentDummyDef
{
    type: ADDON_EFFECT_TYPE,
    affectSpell?: number[],
    affectMask?: number,
    /** For SCRIPT_ effect types: the script or script value the effect belongs to. */
    scriptKey?: string,
    /**
     * Value of the addon effect at a talent rank.
     * @param effectValues The talent spell's effect values at that rank, indexed by effect index.
     * @param rank 1-based rank
     * @param spellId Talent spell ID
     */
    valueForRank: (effectValues: number[], rank: number, spellId: number) => number,
}

type TalentDummyList = { [talentName: string]: TalentDummyDef[] }

function addMageTalents(list: TalentDummyList, spellData: SpellData, classSpellSets: ClassSpellSets)
{
    // Ignite: extra damage on crit for all fire spells. Each class mask bit is set once if any
    // fire spell uses it (upstream added the bit once per spell, producing values above 32 bits).
    const affectedSpellSets = [0, 0, 0, 0];
    const mageSet = classSpellSets.getClassSets(SpellClassSetId.MAGE);
    for (let set = 0; set < 4; set++)
    {
        const page = mageSet[set];
        for (let bit in page)
        {
            for (let spellId in page[bit])
            {
                const misc = spellData.getSpellMisc(parseInt(spellId), true);
                if (misc && (misc.SchoolMask & SCHOOL_MASK.FIRE) !== 0)
                {
                    affectedSpellSets[set] = (affectedSpellSets[set] | parseInt(bit)) >>> 0;
                    break;
                }
            }
        }
    }
    // "burn for an additional $m1% of your spell's damage"
    list["Ignite"] = [{
        type: ADDON_EFFECT_TYPE.SPELLMOD_EXTRA_ON_CRIT,
        affectSpell: affectedSpellSets,
        valueForRank: v => v[0],
    }];

    // "Gives you a $m1% chance of entering a Clearcasting state after any damage spell hits a target"
    list["Arcane Concentration"] = [{
        type: ADDON_EFFECT_TYPE.CLEARCAST_CHANCE_DMG,
        valueForRank: v => v[0],
    }];

    // "Your Fire and Frost critical strikes will refund $s1% of their base mana cost"
    list["Master of Elements"] = [{
        type: ADDON_EFFECT_TYPE.ILLUMINATION,
        valueForRank: v => v[0],
    }];

    // "... and increases the amount absorbed by your Ice Barrier and Frost Ward by $s3%." The third effect names
    // the two spells. Their tooltips apply it to the base value and to the spell power part alike:
    // ${$s1+($SPFR*0.1)*($11189s3/100+1)}, where $s1 already includes the talent. The other two effects (armor
    // of the Armor spells, Frost Ward's chance to negate) are nothing the addon calculates.
    const frostWarding = spellData.getSpellsByName("Frost Warding", true)
        ?.map(id => spellData.getSpellEffects(id, true)?.find(e => e.EffectIndex === 2 && e.EffectAura === AURA_TYPE.SPELL_AURA_ADD_PCT_MODIFIER))
        .find(e => e && (e.EffectSpellClassMask_0 || e.EffectSpellClassMask_1));
    if (frostWarding)
    {
        const absorbs = [frostWarding.EffectSpellClassMask_0, frostWarding.EffectSpellClassMask_1, frostWarding.EffectSpellClassMask_2, frostWarding.EffectSpellClassMask_3];
        list["Frost Warding"] = [
            { type: ADDON_EFFECT_TYPE.SPELLMOD_PCT_EFFECT, affectSpell: absorbs, valueForRank: v => v[2] },
            { type: ADDON_EFFECT_TYPE.SPELLMOD_PCT_SPELL_SCALE, affectSpell: absorbs, valueForRank: v => v[2] },
        ];
    }

    // "Decreases the Mana lost per point of damage taken when your Mana Shield spell is active by $m1%"; the
    // Mana Shield handler reads the value. The Mage Armor part changes nothing the addon calculates.
    list["Arcane Shielding"] = [{
        type: ADDON_EFFECT_TYPE.SCRIPT_SET_VALUE,
        scriptKey: "Mage_Arcane_Shielding",
        valueForRank: v => Math.abs(v[0]),
    }];

    // "Increases the damage done by your Fire spells by $s1% per your Fire effects on the target, up to a maximum
    // increase of ${$s1*4}%." Stored as a value; the number of effects is assumed in the settings (the "Fire Power"
    // target aura in modules/TargetAuras.ts) and its script multiplies the two.
    list["Fire Power"] = [{
        type: ADDON_EFFECT_TYPE.SCRIPT_SET_VALUE,
        scriptKey: "Mage_Fire_Power",
        valueForRank: v => v[0],
    }];

    // "Increases the critical strike chance of all your spells against Frozen targets by $m1%." Stored as a
    // value; the assumed "frozen target" aura (modules/TargetAuras.ts) adds it to the crit chance.
    list["Shatter"] = [{
        type: ADDON_EFFECT_TYPE.SCRIPT_SET_VALUE,
        scriptKey: "Mage_Shatter",
        valueForRank: v => v[0],
    }];
}

function addPaladinTalents(list: TalentDummyList)
{
    // "After getting a critical effect from your Flash of Light, Holy Light, Light's Vigil, or Holy Shock heal spell
    //  you have a $m1% chance to gain Mana equal to $m3% of the base cost of the spell."
    // The addon models this as the expected refund in percent of the base cost.
    list["Illumination"] = [{
        type: ADDON_EFFECT_TYPE.ILLUMINATION,
        valueForRank: v => v[0] * v[2] / 100,
    }];
}

function addShamanTalents(list: TalentDummyList, spellData: SpellData)
{
    // "Gives you a $h% chance to enter a Clearcasting state after casting any Fire, Frost, or Nature damage spell"
    // $h is the proc chance of the aura.
    list["Elemental Focus"] = [{
        type: ADDON_EFFECT_TYPE.CLEARCAST_CHANCE_DMG,
        valueForRank: (_v, _rank, spellId) => spellData.getSpellAuraOptions(spellId)?.ProcChance ?? 10,
    }];
}

export function getTalentDummies(spellData: SpellData, classSpellSets: ClassSpellSets)
{
    const list: TalentDummyList = {};

    addMageTalents(list, spellData, classSpellSets);
    addPaladinTalents(list);
    addShamanTalents(list, spellData);

    return list;
}
