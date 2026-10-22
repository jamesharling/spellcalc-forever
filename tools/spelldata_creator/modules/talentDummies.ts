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
    // Ignite: extra damage on crit for all fire spells
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
                    affectedSpellSets[set] += parseInt(bit);
                    continue;
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
