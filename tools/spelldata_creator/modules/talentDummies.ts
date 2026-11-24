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

const ALL_SPELLS = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF];

function addPaladinTalents(list: TalentDummyList, spellData: SpellData)
{
    // "After getting a critical effect from your Flash of Light, Holy Light, Light's Vigil, or Holy Shock heal spell
    //  you have a $m1% chance to gain Mana equal to $m3% of the base cost of the spell."
    // The addon models this as the expected refund in percent of the base cost.
    list["Illumination"] = [{
        type: ADDON_EFFECT_TYPE.ILLUMINATION,
        valueForRank: v => v[0] * v[2] / 100,
    }];

    // "Increases the critical strike healing bonus of your Holy spells by $s1%." A critical heal's bonus is 50% of
    // the heal; the addon effect adds to the critical multiplier of heals (all of a paladin's are Holy), so half
    // the percentage: 1.5 + 0.25 = 1.75 with all five ranks.
    list["Holy Power"] = [{
        type: ADDON_EFFECT_TYPE.GLOBAL_MOD_CRITICAL_HEALING,
        valueForRank: v => v[0] / 2,
    }];

    // "Gives your Holy spells $m1% increased damage against the first $20924s3 enemies that enter your
    // Consecration." A script on every spell (data/forever/classes/paladin.lua): Consecration always, other Holy
    // damage while the target is assumed to be one of those enemies (modules/TargetAuras.ts).
    list["Consecrated Ground"] = [{
        type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_DONE_PCT,
        affectSpell: ALL_SPELLS,
        scriptKey: "Paladin_Consecrated_Ground",
        valueForRank: v => v[0],
    }];

    // "Increases the critical strike chance of your Holy Shock spell by $s1% when cast on allies not affected by
    // your Oath of Light." A script on the heal Holy Shock triggers: the class mask bits only those spells have.
    const set = SpellClassSetId.PALADIN;
    const healMask = [0, 0, 0, 0];
    const otherMask = [0, 0, 0, 0];
    for (const spellId of spellData.getSpellsByName("Holy Shock", true) ?? [])
    {
        const options = spellData.getSpellClassOption(spellId, true);
        if (!options || options.SpellClassSet !== set) continue;
        const isHeal = spellData.getSpellEffects(spellId, true)?.some(e => e.EffectIndex === 0 && e.Effect === EFFECT_TYPE.SPELL_EFFECT_HEAL);
        const mask = isHeal ? healMask : otherMask;
        mask[0] |= options.SpellClassMask_0;
        mask[1] |= options.SpellClassMask_1;
        mask[2] |= options.SpellClassMask_2;
        mask[3] |= options.SpellClassMask_3;
    }
    const healOnly = healMask.map((bits, i) => (bits & ~otherMask[i]) >>> 0);
    if (healOnly.some(bits => bits !== 0))
    {
        list["Boundless Light"] = [{
            type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_CRIT_CHANCE,
            affectSpell: healOnly,
            scriptKey: "Paladin_Boundless_Light",
            valueForRank: v => v[0],
        }];
    }
}

/**
 * Class mask bits of the spells of a class set with one of the given names (all ranks).
 */
function classMaskOf(spellData: SpellData, set: number, names: string[], filter?: (spellId: number) => boolean)
{
    const mask = [0, 0, 0, 0];
    for (const name of names)
    {
        for (const spellId of spellData.getSpellsByName(name, true) ?? [])
        {
            const options = spellData.getSpellClassOption(spellId, true);
            if (!options || options.SpellClassSet !== set) continue;
            if (filter && !filter(spellId)) continue;
            mask[0] |= options.SpellClassMask_0;
            mask[1] |= options.SpellClassMask_1;
            mask[2] |= options.SpellClassMask_2;
            mask[3] |= options.SpellClassMask_3;
        }
    }
    return mask.map(bits => bits >>> 0);
}

/**
 * The scripts are in data/forever/classes/priest.lua; the target states they depend on are assumed in the
 * settings (modules/TargetAuras.ts).
 */
function addPriestTalents(list: TalentDummyList, spellData: SpellData)
{
    const set = SpellClassSetId.PRIEST;
    const firstEffectIs = (type: number) => (spellId: number) =>
        spellData.getSpellEffects(spellId, true)?.some(e => e.EffectIndex === 0 && e.Effect === type) ?? false;
    const isHeal = firstEffectIs(EFFECT_TYPE.SPELL_EFFECT_HEAL);
    const isDamage = firstEffectIs(EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE);
    const any = (mask: number[]) => mask.some(bits => bits !== 0);

    // "Your non-periodic critical heals create a protective shield on the target, absorbing $s1% of the amount
    // healed." Extra value on a critical heal, like Ignite on damage, for the spells Spiritual Healing lists as
    // heals (its first effect; periodic heals do not crit). The cap ($s2 per level) is not modelled.
    const spiritualHealing = (spellData.getSpellsByName("Spiritual Healing", true) ?? [])
        .map(id => spellData.getSpellEffects(id, true)?.find(e => e.EffectIndex === 0 && e.EffectAura === AURA_TYPE.SPELL_AURA_ADD_PCT_MODIFIER))
        .find(e => e && (e.EffectSpellClassMask_0 || e.EffectSpellClassMask_1));
    if (spiritualHealing)
    {
        list["Divine Aegis"] = [{
            type: ADDON_EFFECT_TYPE.SPELLMOD_EXTRA_ON_CRIT,
            affectSpell: [spiritualHealing.EffectSpellClassMask_0, spiritualHealing.EffectSpellClassMask_1,
                spiritualHealing.EffectSpellClassMask_2, spiritualHealing.EffectSpellClassMask_3],
            valueForRank: v => v[0],
        }];
    }

    // "Your heals from Flash Heal, Lesser Heal, Heal, Greater Heal, and Penance gain $m1% increased critical strike
    // chance when cast on targets with Weakened Soul". A script on those heals (for Penance the heal of a volley).
    const hopeMask = classMaskOf(spellData, set, ["Flash Heal", "Lesser Heal", "Heal", "Greater Heal", "Penance"], isHeal);
    if (any(hopeMask))
    {
        list["Renewed Hope"] = [{
            type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_CRIT_CHANCE,
            affectSpell: hopeMask,
            scriptKey: "Priest_Renewed_Hope",
            valueForRank: v => v[0],
        }];
    }

    // "Your Smite and Penance spells deal $m1% increased damage to targets afflicted with your Holy Fire or Shadow
    // Word: Pain." A script on Smite and the damage of a Penance volley.
    const lightMask = classMaskOf(spellData, set, ["Smite", "Penance"], isDamage);
    if (any(lightMask))
    {
        list["Power in Light"] = [{
            type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_DONE_PCT,
            affectSpell: lightMask,
            scriptKey: "Priest_Power_in_Light",
            valueForRank: v => v[0],
        }];
    }

    // "Increases Shadow Word: Death's critical strike chance on targets at or below $s2% health by $s1%."
    const deathMask = classMaskOf(spellData, set, ["Shadow Word: Death"], isDamage);
    if (any(deathMask))
    {
        list["Early Demise"] = [{
            type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_CRIT_CHANCE,
            affectSpell: deathMask,
            scriptKey: "Priest_Early_Demise",
            valueForRank: v => v[0],
        }];
    }

    // "Each instance of damage of Mind Flay deals $s1% more damage than its previous instance of damage." The
    // script turns that into the average over the channel's ticks.
    const flayMask = classMaskOf(spellData, set, ["Mind Flay"],
        id => spellData.getSpellEffects(id, true)?.some(e => e.EffectAura === AURA_TYPE.SPELL_AURA_PERIODIC_DAMAGE) ?? false);
    if (any(flayMask))
    {
        list["Improved Mind Flay"] = [{
            type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_DONE_PCT,
            affectSpell: flayMask,
            scriptKey: "Priest_Improved_Mind_Flay",
            valueForRank: v => v[0],
        }];
    }
}

/**
 * The scripts are in data/forever/classes/warlock.lua; the target states are assumed in the settings
 * (modules/TargetAuras.ts).
 */
function addWarlockTalents(list: TalentDummyList, spellData: SpellData)
{
    const set = SpellClassSetId.WARLOCK;
    const any = (mask: number[]) => mask.some(bits => bits !== 0);
    const isPeriodicDamage = (spellId: number) => spellData.getSpellEffects(spellId, true)?.some(e =>
        e.EffectAura === AURA_TYPE.SPELL_AURA_PERIODIC_DAMAGE || e.EffectAura === AURA_TYPE.SPELL_AURA_PERIODIC_LEECH) ?? false;

    // "When you cast Shadow Bolt or Searing Pain on an enemy below $m3% health, they deal $m4% increased damage".
    // The fourth effect is a damage modifier on the two spells; converted as is it would always apply. A script
    // applies it while the target is assumed to be below that health. (The Soul Fire parts change its cooldown,
    // cast time and shard cost, nothing the addon calculates.)
    const decimation = (spellData.getSpellsByName("Decimation", true) ?? [])
        .map(id => spellData.getSpellEffects(id, true)?.find(e => e.EffectIndex === 3 && e.EffectAura === AURA_TYPE.SPELL_AURA_ADD_PCT_MODIFIER))
        .find(e => e && e.EffectSpellClassMask_0);
    if (decimation)
    {
        list["Decimation"] = [{
            type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_DONE_PCT,
            affectSpell: [decimation.EffectSpellClassMask_0, decimation.EffectSpellClassMask_1,
                decimation.EffectSpellClassMask_2, decimation.EffectSpellClassMask_3],
            scriptKey: "Warlock_Decimation",
            valueForRank: v => v[3],
        }];
    }

    // "Increases the damage done or health drained by your Drain Life, Drain Soul, and Wrack spells by $s1% per
    // each of your Corruption, Siphon Life, and Bane of Agony effects active on the target". A script on the
    // three spells; the number of effects is assumed in the settings.
    const siphonMask = classMaskOf(spellData, set, ["Drain Life", "Drain Soul", "Wrack"], isPeriodicDamage);
    if (any(siphonMask))
    {
        list["Soul Siphon"] = [{
            type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_DONE_PCT,
            affectSpell: siphonMask,
            scriptKey: "Warlock_Soul_Siphon",
            valueForRank: v => v[0],
        }];
    }

    // "Increases the amount of Mana awarded by your Life Tap spell by $s1%."
    const lifeTapMask = classMaskOf(spellData, set, ["Life Tap"]);
    if (any(lifeTapMask))
    {
        list["Improved Life Tap"] = [{
            type: ADDON_EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
            affectSpell: lifeTapMask,
            valueForRank: v => v[0],
        }];
    }

    // Talents whose buff or debuff has one spell for every rank: the aura data only has a single value, so the
    // rank's own value is stored and the aura's script uses it.
    // "Your Shadow Bolt critical strikes increase Shadow damage taken by the target from your attacks by $m1%"
    list["Improved Shadow Bolt"] = [{ type: ADDON_EFFECT_TYPE.SCRIPT_SET_VALUE, scriptKey: "Warlock_Improved_Shadow_Bolt", valueForRank: v => v[0] }];
    // "Imp - Increases Fire damage done by $m1%. ... Succubus/Incubus - Increases Shadow damage done by $m3%."
    list["Master Demonologist"] = [{ type: ADDON_EFFECT_TYPE.SCRIPT_SET_VALUE, scriptKey: "Warlock_Master_Demonologist", valueForRank: v => v[0] }];
    // "Conflagrate increases all Shadow damage you deal by $m3% ..., Shadowburn increases all Fire damage you deal by $m4%"
    list["Shadow and Flame"] = [{ type: ADDON_EFFECT_TYPE.SCRIPT_SET_VALUE, scriptKey: "Warlock_Shadow_and_Flame", valueForRank: v => v[2] }];
    // "... and allows $m2% of normal Mana regeneration to continue while casting."
    list["Soul Harvest"] = [{ type: ADDON_EFFECT_TYPE.SCRIPT_SET_VALUE, scriptKey: "Warlock_Soul_Harvest", valueForRank: v => v[1] }];
}

function addShamanTalents(list: TalentDummyList, spellData: SpellData)
{
    // "Gives you a $h% chance to enter a Clearcasting state after casting any Fire, Frost, or Nature damage spell"
    // $h is the proc chance of the aura.
    list["Elemental Focus"] = [{
        type: ADDON_EFFECT_TYPE.CLEARCAST_CHANCE_DMG,
        valueForRank: (_v, _rank, spellId) => spellData.getSpellAuraOptions(spellId)?.ProcChance ?? 10,
    }];

    // "Gives your Lightning Bolt and Chain Lightning spells a $m1% chance to cast a second, similar spell on the
    // same target at no additional cost that causes half damage". The addon adds the expected extra damage
    // (core/effectHandlers.lua). The two spells are the ones Call of Thunder names.
    const callOfThunder = (spellData.getSpellsByName("Call of Thunder", true) ?? [])
        .map(id => spellData.getSpellEffects(id, true)?.find(e => e.EffectAura === AURA_TYPE.SPELL_AURA_ADD_FLAT_MODIFIER))
        .find(e => e && e.EffectSpellClassMask_0);
    if (callOfThunder)
    {
        list["Lightning Overload"] = [{
            type: ADDON_EFFECT_TYPE.SHAMAN_LIGHTNING_OVERLOAD,
            affectSpell: [callOfThunder.EffectSpellClassMask_0, callOfThunder.EffectSpellClassMask_1,
                callOfThunder.EffectSpellClassMask_2, callOfThunder.EffectSpellClassMask_3],
            valueForRank: v => v[0],
        }];
    }
}

export function getTalentDummies(spellData: SpellData, classSpellSets: ClassSpellSets)
{
    const list: TalentDummyList = {};

    addMageTalents(list, spellData, classSpellSets);
    addPaladinTalents(list, spellData);
    addPriestTalents(list, spellData);
    addWarlockTalents(list, spellData);
    addShamanTalents(list, spellData);

    return list;
}
