import { SpellEffect, SpellData } from "./SpellData";
import { cfg } from "./config";
import { isJudgeDummy, SealType, getSeals } from "./paladinCrap";
import { getSpellIdFromEffect } from "./effectValues";
import { report, reportSection } from "./report";
import * as fs from "fs";

/**
 * Spells stored with their damage against a target that is not stunned, and the percentage a stunned or
 * incapacitated target adds (Judgement of Command). Filled by fixSpellEffects.
 */
export const stunnedDamagePct = new Map<number, number>();

// This isn't used anywhere, just put something there just in case
let effCustIndex = 999900;

function cloneEntry(entry: SpellEffect): SpellEffect
{
    const k: SpellEffect = { ...entry };
    k.ID = effCustIndex;
    effCustIndex++;
    return k;
}

/**
 * Effects of a spell, or undefined (reported) when the spell is not in the client data.
 */
function effectsOf(sd: SpellData, spellId: number, what: string)
{
    const effects = sd.getSpellEffects(spellId, true);
    if (!effects) report(`${what}: spell ${spellId} does not exist, fix skipped`);
    return effects;
}

function priestFix(sd: SpellData)
{
    console.log("Fixing priest coefs and effects");

    // Holy Nova spell -> its heal spell
    const HOLY_NOVA_TRIGGER: { [spellId: number]: number } = {
        15237: 23455,
        15430: 23458,
        15431: 23459,
        27799: 27803,
        27800: 27804,
        27801: 27805,
    }

    // map Touch of Weakness proc spells
    const TOW_MAP: { [spellId: number]: number } = {
        2652: 2943,
        19261: 19249,
        19262: 19251,
        19264: 19252,
        19265: 19253,
        19266: 19254,
    };

    // Shadowguard -> triggerID
    const SHADOWGUARD_TRIGGER_IDS: { [spellId: number]: number } = {
        18137: 28377,
        19308: 28378,
        19309: 28379,
        19310: 28380,
        19311: 28381,
        19312: 28382,
    };

    // Fix Holy Nova trigger
    for (const hnId in HOLY_NOVA_TRIGGER)
    {
        const effects = effectsOf(sd, parseInt(hnId), "Holy Nova");
        if (!effects) continue;
        if (!effectsOf(sd, HOLY_NOVA_TRIGGER[hnId], "Holy Nova heal")) continue;
        for (const effect of effects)
        {
            if (effect.EffectIndex === 0)
            {
                let clone = cloneEntry(effect);
                clone.EffectIndex = 1;
                clone.Effect = EFFECT_TYPE.SPELL_EFFECT_TRIGGER_SPELL;
                clone.EffectTriggerSpell = HOLY_NOVA_TRIGGER[effect.SpellID];
                effects.push(clone);
            }
        }
    }

    // Touch of Weakness does not have any usefull data about its proc by default, replace with proc entirely
    for (const towId in TOW_MAP)
    {
        const effects = effectsOf(sd, parseInt(towId), "Touch of Weakness");
        if (!effects) continue;
        effects[0].EffectTriggerSpell = TOW_MAP[towId];
    }

    // Prayer of Mending: make the jump effect a dummy aura the addon handles
    const pomSpells = sd.getSpellsByName("Prayer of Mending", true) ?? [];
    for (const pomId of pomSpells)
    {
        const effects = sd.getSpellEffects(pomId, true);
        if (!effects) continue;
        for (const effect of effects)
        {
            if (effect.EffectIndex === 0)
            {
                effect.Effect = EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA;
                effect.EffectAura = AURA_TYPE.SPELL_AURA_DUMMY;
            }
        }
    }

    // Shadowguard trigger fix
    for (const shieldSpellId in SHADOWGUARD_TRIGGER_IDS)
    {
        const effects = effectsOf(sd, parseInt(shieldSpellId), "Shadowguard");
        if (!effects) continue;
        for (const effect of effects)
        {
            if (effect.Effect === EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA && effect.EffectAura === AURA_TYPE.SPELL_AURA_PROC_TRIGGER_SPELL)
            {
                effect.EffectTriggerSpell = SHADOWGUARD_TRIGGER_IDS[shieldSpellId];
            }
        }
    }

    // Penance: every rank that is cast is a dummy whose tooltip names the damage and the heal of one volley
    // ("causing $402284s1 Holy damage to an enemy, or $402289s1 healing to an ally, instantly and every $402261t2
    // sec for $402261d"). Each of the two is fired by the periodic trigger aura of another spell with the same
    // name; the cast spell gets those two auras (heal first) and their duration.
    const penances = sd.getSpellsByName("Penance", true) ?? [];
    const penanceVolley = (tickSpellId: number) =>
    {
        for (const spellId of penances)
        {
            const effect = sd.getSpellEffects(spellId, true)?.find(e => e.EffectAura === AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL
                && e.EffectTriggerSpell === tickSpellId);
            if (effect) return { spellId, effect };
        }
        return undefined;
    };
    for (const penanceId of penances)
    {
        const spell = sd.getSpell(penanceId, true);
        const effects = sd.getSpellEffects(penanceId, true);
        if (!spell || !effects || effects.length !== 1 || effects[0].Effect !== EFFECT_TYPE.SPELL_EFFECT_DUMMY) continue;
        const match = spell.Description_lang.match(/\$(\d+)s1 Holy damage.*?\$(\d+)s1 healing/);
        if (!match) continue;

        const dmg = penanceVolley(parseInt(match[1]));
        const heal = penanceVolley(parseInt(match[2]));
        if (!dmg || !heal)
        {
            report(`${sd.getSpellNameWithRank(penanceId)} [${penanceId}]: couldn't find the ${heal ? "damage" : "heal"} trigger aura, not generated`);
            continue;
        }

        const eff = effects[0];
        Object.assign(eff, heal.effect);
        eff.SpellID = penanceId;
        eff.EffectIndex = 0;

        const dmgEffect = cloneEntry(dmg.effect);
        dmgEffect.SpellID = penanceId;
        dmgEffect.EffectIndex = 1;
        effects.push(dmgEffect);

        sd.getSpellMisc(penanceId).DurationIndex = sd.getSpellMisc(heal.spellId).DurationIndex;
    }

    // Contingency Plan: two dummy auras; what the ward does when it goes off is only named in the description
    // ("they will gain a shield absorbing $1277466s2 damage and begin healing for $1277460o2 Health over
    // $1277460d"). Shown as the periodic heal and the absorb of those two spells.
    for (const planId of sd.getSpellsByName("Contingency Plan", true) ?? [])
    {
        const spell = sd.getSpell(planId, true);
        const effects = sd.getSpellEffects(planId, true);
        if (!spell || !effects) continue;
        const match = spell.Description_lang.match(/absorbing \$(\d+)s\d damage and begin healing for \$(\d+)o\d/);
        if (!match) continue;
        const absorbId = parseInt(match[1]);
        const healId = parseInt(match[2]);
        const absorb = sd.getSpellEffects(absorbId, true)?.find(e => e.EffectAura === AURA_TYPE.SPELL_AURA_SCHOOL_ABSORB);
        const heal = sd.getSpellEffects(healId, true)?.find(e => e.EffectAura === AURA_TYPE.SPELL_AURA_PERIODIC_HEAL);
        const first = effects.find(e => e.EffectIndex === 0);
        const second = effects.find(e => e.EffectIndex === 1);
        if (!absorb || !heal || !first || !second)
        {
            report(`${sd.getSpellNameWithRank(planId)} [${planId}]: absorb ${absorbId} or heal ${healId} not found, not generated`);
            continue;
        }
        Object.assign(first, heal);
        first.SpellID = planId;
        first.EffectIndex = 0;
        Object.assign(second, absorb);
        second.SpellID = planId;
        second.EffectIndex = 1;
        sd.getSpellMisc(planId).DurationIndex = sd.getSpellMisc(healId).DurationIndex;
    }
}

function paladinFix(sd: SpellData)
{
    console.log("Fixing pala coefs and effects");

    // Holy Light / Flash of Light coefficients the client data does not have
    {
        const HL_GENERIC = [1026, 1042, 3472, 10328, 10329, 25292];
        const FOL_GENERIC = [19750, 19939, 19940, 19941, 19942, 19943];

        const fixCoefAndEffect = (spellId: number, coef: number) =>
        {
            const effects = effectsOf(sd, spellId, "Holy Light/Flash of Light coefficient");
            if (!effects) return;
            effects[0].EffectBonusCoefficient = coef;
            effects[0].Effect = EFFECT_TYPE.SPELL_EFFECT_HEAL;
        };
        // HL
        fixCoefAndEffect(635, 0.205);
        fixCoefAndEffect(639, 0.339);
        fixCoefAndEffect(647, 0.554);
        for (const spellId of HL_GENERIC)
        {
            fixCoefAndEffect(spellId, 2.5 / 3.5);
        }
        // FoL
        for (const spellId of FOL_GENERIC)
        {
            fixCoefAndEffect(spellId, 1.5 / 3.5);
        }
    }

    // Holy Shock: a dummy effect; the damage and heal spells are only named in the description
    // ("causing $25912s1 Holy damage to an enemy, or $25914s1 healing to an ally").
    const holyShocks = sd.getSpellsByName("Holy Shock", true) ?? [];
    for (const hsId of holyShocks)
    {
        const spell = sd.getSpell(hsId, true);
        const effects = sd.getSpellEffects(hsId, true);
        if (!spell || !effects) continue;
        if (effects[0].Effect !== EFFECT_TYPE.SPELL_EFFECT_DUMMY) continue;

        const match = spell.Description_lang.match(/\$(\d+)s1 Holy damage.*?\$(\d+)s1 healing/);
        if (!match)
        {
            report(`Holy Shock ${hsId}: could not find damage/heal spells in the description, skipped`);
            continue;
        }
        const dmgId = parseInt(match[1]);
        const healId = parseInt(match[2]);
        if (!effectsOf(sd, dmgId, `Holy Shock ${hsId} damage`) || !effectsOf(sd, healId, `Holy Shock ${hsId} heal`)) continue;

        for (const effect of effects)
        {
            if (effect.EffectIndex === 0)
            {
                effect.Effect = EFFECT_TYPE.SPELL_EFFECT_TRIGGER_SPELL;
                effect.EffectTriggerSpell = healId;

                const clone = cloneEntry(effect);
                clone.EffectIndex = 1;
                clone.EffectTriggerSpell = dmgId;
                effects.push(clone);

                const sc = sd.getSpellCategory(effect.SpellID);
                if (!sc) throw new Error("SpellCategory doesn't exist for Holy Shock " + hsId);
                sc.DefenseType = DEFENSE_TYPE.MAGIC;
            }
        }
    }

    // Light's Vigil: two dummy effects; the party heal the next Holy Shock sets off is only named in the description
    // ("heals the target and their party for $1311596s1"). Shown as the spell's heal, per target.
    for (const vigilId of sd.getSpellsByName("Light's Vigil", true) ?? [])
    {
        const spell = sd.getSpell(vigilId, true);
        const effects = sd.getSpellEffects(vigilId, true);
        if (!spell || !effects || effects[0].Effect !== EFFECT_TYPE.SPELL_EFFECT_DUMMY) continue;
        const match = spell.Description_lang.match(/party for \$(\d+)s1/);
        if (!match) continue;
        const healId = parseInt(match[1]);
        const heal = effectsOf(sd, healId, `Light's Vigil ${vigilId} heal`);
        if (!heal || heal[0].Effect !== EFFECT_TYPE.SPELL_EFFECT_HEAL)
        {
            report(`Light's Vigil ${vigilId}: spell ${healId} named in the description is no heal, skipped`);
            continue;
        }
        effects[0].Effect = EFFECT_TYPE.SPELL_EFFECT_TRIGGER_SPELL;
        effects[0].EffectTriggerSpell = healId;
    }

    // Judgement of Command: "instantly causing $/2;20467s1 Holy damage, $20467s1 if the target is stunned or
    // incapacitated." The judgement spell holds the full value; store the usual one (base, per level and spell
    // power alike) and how much a stunned target adds (stunnedDamagePct in the spell data, applied by the assumed
    // "stunned target" aura).
    for (const sealId of sd.getSpellsByName("Seal of Command", true) ?? [])
    {
        const match = sd.getSpell(sealId, true)?.Description_lang.match(/\$\/(\d+);(\d+)s1 Holy damage, \$(\d+)s1 if the target is stunned/);
        if (!match || match[2] !== match[3]) continue;
        const divisor = parseInt(match[1]);
        const judgementId = parseInt(match[2]);
        if (divisor <= 1 || stunnedDamagePct.has(judgementId)) continue;
        const damage = sd.getSpellEffects(judgementId, true)?.find(e => e.Effect === EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE);
        if (!damage) continue;
        damage.EffectBasePointsF /= divisor;
        damage.EffectRealPointsPerLevel /= divisor;
        damage.EffectBonusCoefficient /= divisor;
        damage.BonusCoefficientFromAP /= divisor;
        stunnedDamagePct.set(judgementId, (divisor - 1) * 100);
    }

    const spellIdsSoC = getSeals(SealType.SOC);
    for (const sealId of spellIdsSoC)
    {
        const effects = effectsOf(sd, sealId, "Seal of Command");
        if (!effects) continue;
        for (const eff of effects)
        {
            // replace SoC judgement dummy spell id, it's inside even another spell
            if (isJudgeDummy(eff) == SealType.SOC)
            {
                const jdEffects = effectsOf(sd, getSpellIdFromEffect(eff), "Seal of Command judgement dummy");
                if (!jdEffects) continue;
                for (const jeff of jdEffects)
                {
                    eff.EffectBasePointsF = jeff.EffectBasePointsF;
                    eff.Variance = 0;
                }
            }

            // replace SoC trigger with it's triggered effect
            if (eff.EffectIndex == 0)
            {
                const triggered = effectsOf(sd, eff.EffectTriggerSpell, "Seal of Command trigger");
                if (!triggered) continue;
                const triggeredEffect = triggered[0];
                eff.EffectBasePointsF = triggeredEffect.EffectBasePointsF;
                eff.Variance = triggeredEffect.Variance;
                eff.EffectBonusCoefficient = triggeredEffect.EffectBonusCoefficient;
                eff.EffectRealPointsPerLevel = triggeredEffect.EffectRealPointsPerLevel;
                eff.Effect = triggeredEffect.Effect;
            }
        }
    }

    const spellIdsAllSeals = getSeals();
    for (const sealId of spellIdsAllSeals)
    {
        if (!sd.spellExists(sealId))
        {
            report(`Seal ${sealId} (sealData.json) does not exist`);
            continue;
        }
        // Make seals melee
        const sc = sd.getSpellCategory(sealId);
        if (!sc)
        {
            report(`Seal ${sealId} has no SpellCategories entry`);
            continue;
        }
        sc.DefenseType = DEFENSE_TYPE.MELEE;
    }
}

function druidFixes(sd: SpellData)
{
    console.log("Fixing druid coefs and effects");

    const RIP = [1079, 9492, 9493, 9752, 9894, 9896];
    for (const ripId of RIP)
    {
        const effects = effectsOf(sd, ripId, "Rip");
        if (!effects) continue;
        effects[0].EffectMechanic = SpellMechanic.BLEED;
    }

    // Lacerate: a bleed (the effect does not carry the mechanic), "plus $s2% weapon damage per existing
    // application of Lacerate on the target" as a dummy effect. Make that a weapon damage effect for a target that
    // already has the full stack, which is what the bleed's "Sustained N Stacks" numbers assume as well.
    const lacerates = sd.getSpellsByName("Lacerate", true) ?? [];
    for (const spellId of lacerates)
    {
        if (sd.getSpellClassOption(spellId, true)?.SpellClassSet != 7) continue;
        const effects = sd.getSpellEffects(spellId, true);
        if (!effects) continue;
        const bleed = effects.find(e => e.EffectIndex === 0 && e.EffectAura === AURA_TYPE.SPELL_AURA_PERIODIC_DAMAGE);
        const perStack = effects.find(e => e.EffectIndex === 1 && e.Effect === EFFECT_TYPE.SPELL_EFFECT_DUMMY);
        const stacks = sd.getSpellAuraOptions(spellId)?.CumulativeAura ?? 0;
        if (!bleed) continue;
        bleed.EffectMechanic = SpellMechanic.BLEED;
        if (!perStack || stacks < 1)
        {
            report(`Lacerate ${spellId}: no weapon damage per application effect or no stack limit, bleed only`);
            continue;
        }
        perStack.Effect = EFFECT_TYPE.SPELL_EFFECT_WEAPON_PERCENT_DAMAGE;
        perStack.EffectBasePointsF = perStack.EffectBasePointsF * stacks;
        perStack.EffectBonusCoefficient = 0;
        // The addon expects the direct effect in slot 1.
        perStack.EffectIndex = 0;
        bleed.EffectIndex = 1;
        effects.sort((a, b) => a.EffectIndex - b.EffectIndex);
    }

    const mauls = sd.getSpellsByName("Maul", true) ?? [];
    const shreds = sd.getSpellsByName("Shred", true) ?? [];
    const mangleIncreasedSpells = [...mauls, ...shreds];
    for (const spellId of mangleIncreasedSpells)
    {
        if (sd.getSpellClassOption(spellId, true)?.SpellClassSet == 7)
        {
            const effects = sd.getSpellEffects(spellId, true);
            if (!effects) continue;
            for (const effect of effects)
            {
                if (effect.EffectIndex === 0)
                {
                    effect.EffectMechanic = SpellMechanic.BLEED;
                }
            }
        }
    }
}

function warlockFixes(sd: SpellData)
{
    console.log("Fixing warlock coefs and effects");

    // Ignore trigger effect for shard debuff
    const shadowBurns = sd.getSpellsByName("Shadowburn", true) ?? [];
    for (const spellId of shadowBurns)
    {
        const effects = sd.getSpellEffects(spellId, true);
        if (!effects) continue;
        for (const effect of effects)
        {
            if (effect.Effect === EFFECT_TYPE.SPELL_EFFECT_TRIGGER_SPELL) effect.Effect = 0;
        }
    }
}

function shamanFix(sd: SpellData)
{
    console.log("Fixing shaman coefs and effects");

    // Lightning Shield -> damage trigger
    const LIGHTNING_SHIELD_TRIGGERS: { [spellId: number]: number } = {
        324: 26364,
        325: 26365,
        905: 26366,
        945: 26367,
        8134: 26369,
        10431: 26370,
        10432: 26363,
    };

    for (const shieldSpellId in LIGHTNING_SHIELD_TRIGGERS)
    {
        const effects = effectsOf(sd, parseInt(shieldSpellId), "Lightning Shield");
        if (!effects) continue;
        if (!effectsOf(sd, LIGHTNING_SHIELD_TRIGGERS[shieldSpellId], "Lightning Shield trigger")) continue;
        for (const effect of effects)
        {
            if (effect.Effect === EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA && effect.EffectAura === AURA_TYPE.SPELL_AURA_PROC_TRIGGER_SPELL)
            {
                effect.EffectTriggerSpell = LIGHTNING_SHIELD_TRIGGERS[shieldSpellId];
            }
        }
    }

    const stormStrikes = sd.getSpellsByName("Stormstrike", true) ?? [];
    for (const stormStrikeId of stormStrikes)
    {
        const ao = sd.getSpellAuraOptions(stormStrikeId);
        if (ao) ao.ProcCharges = 0;
    }

    const searingTotems = sd.getSpellsByName("Searing Totem", true) ?? [];
    for (const totemSpellId of searingTotems)
    {
        const tts = sd.getTotemSpell(totemSpellId);
        if (tts)
        {
            const effects = effectsOf(sd, totemSpellId, "Searing Totem");
            if (!effects || !effectsOf(sd, tts, "Searing Totem spell")) continue;
            const effect = effects[0];
            effect.Effect = EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA;
            effect.EffectAura = AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL;
            effect.EffectAuraPeriod = 2200;
            effect.EffectTriggerSpell = tts;
        }
    }

    const magmaTotems = sd.getSpellsByName("Magma Totem", true) ?? [];
    for (const totemSpellId of magmaTotems)
    {
        const tts = sd.getTotemSpell(totemSpellId);
        if (tts)
        {
            const effects = effectsOf(sd, totemSpellId, "Magma Totem");
            const ttsEffects = effectsOf(sd, tts, "Magma Totem spell");
            if (!effects || !ttsEffects) continue;
            const effect = effects[0];
            const misc = sd.getSpellMisc(effect.SpellID);
            misc.DurationIndex = 18 // 20000

            const ttsEff = ttsEffects[0];
            effect.Effect = ttsEff.Effect;
            effect.EffectAura = ttsEff.EffectAura;
            effect.EffectAuraPeriod = ttsEff.EffectAuraPeriod;
            effect.EffectTriggerSpell = ttsEff.EffectTriggerSpell;
        }
    }

    const healingStreamTotems = sd.getSpellsByName("Healing Stream Totem", true) ?? [];
    for (const totemSpellId of healingStreamTotems)
    {
        const tts = sd.getTotemSpell(totemSpellId);
        if (tts)
        {
            const effects = effectsOf(sd, totemSpellId, "Healing Stream Totem");
            const ttsEffects = effectsOf(sd, tts, "Healing Stream Totem spell");
            if (!effects || !ttsEffects) continue;
            const effect = effects[0];
            const ttsEff = ttsEffects[0];
            effect.Effect = ttsEff.Effect;
            effect.EffectAura = ttsEff.EffectAura;
            effect.EffectAuraPeriod = ttsEff.EffectAuraPeriod;
            effect.EffectTriggerSpell = ttsEff.EffectTriggerSpell;
        }
    }
}

function coefFixes(sd: SpellData)
{
    interface CoefEntry { [effectIndex: number]: { ap?: number, sp?: number } }

    console.log("Fixing coefs");
    const data: {
        names: { [spellName: string]: CoefEntry },
        ids: { [spellId: number]: CoefEntry },
    } = JSON.parse(fs.readFileSync(cfg.dataDir + "missingCoef.json", "utf8"));

    for (const spellName in data.names)
    {
        const spells = sd.getSpellsByName(spellName, true);
        if (!spells)
        {
            report(`missingCoef.json: no spells named "${spellName}"`);
            continue;
        }
        for (const spellId of spells)
        {
            const effects = sd.getSpellEffects(spellId, true);
            if (!effects) continue;
            for (const effect of effects)
            {
                if (data.names[spellName][effect.EffectIndex])
                {
                    const thisData = data.names[spellName][effect.EffectIndex];
                    if (typeof thisData.ap !== "undefined") effect.BonusCoefficientFromAP = thisData.ap;
                    if (typeof thisData.sp !== "undefined") effect.EffectBonusCoefficient = thisData.sp;
                }
            }
        }
    }

    for (const spellId in data.ids)
    {
        const effects = effectsOf(sd, parseInt(spellId), "missingCoef.json");
        if (!effects) continue;
        for (const effect of effects)
        {
            if (data.ids[spellId][effect.EffectIndex])
            {
                const thisData = data.ids[spellId][effect.EffectIndex];
                if (typeof thisData.ap !== "undefined") effect.BonusCoefficientFromAP = thisData.ap;
                if (typeof thisData.sp !== "undefined") effect.EffectBonusCoefficient = thisData.sp;
            }
        }
    }
}

/**
 * Area spells that tick through an area trigger (Hurricane, Blizzard, Rain of Fire, the burn of Flamestrike). On
 * Forever the spell that is cast only creates an area trigger and carries a periodic dummy aura for its duration;
 * the damage of a tick is a separate spell that nothing but the tooltip names ("causing $1278759s1 Nature damage
 * to enemies every $t3 sec", "an additional ${$1279990m1*4} Fire damage over $d"). Give the cast spell the periodic
 * area damage it stands for: the damage spell's values, ticking at the dummy aura's period. A channelled spell has
 * a dummy as its first effect, which becomes the area damage; otherwise the periodic dummy aura itself does
 * (Flamestrike keeps its direct damage in front of it).
 */
function areaTriggerFix(sd: SpellData)
{
    const SPELL_EFFECT_CREATE_AREATRIGGER = 179;
    let channelled = 0;
    let other = 0;

    for (const spellId of sd.getAllSpellIds())
    {
        const effects = sd.getSpellEffects(spellId, true);
        const misc = sd.getSpellMisc(spellId, true);
        const spell = sd.getSpell(spellId, true);
        const name = sd.getSpellName(spellId, true);
        if (!effects || !misc || !spell || !name) continue;

        const periodic = effects.find(e => e.Effect === EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA
            && e.EffectAura === AURA_TYPE.PERIODIC_DUMMY && e.EffectAuraPeriod > 0);
        if (!periodic || !effects.some(e => e.Effect === SPELL_EFFECT_CREATE_AREATRIGGER)) continue;

        const isChannel = (misc.Attributes_1 & SPELL_ATTR1.SPELL_ATTR_EX_CHANNELED_ANY) !== 0;
        const target = isChannel
            ? effects.find(e => e.EffectIndex === 0 && e.Effect === EFFECT_TYPE.SPELL_EFFECT_DUMMY)
            : periodic;
        if (!target) continue;

        const match = spell.Description_lang.match(/\$(\d+)[sm]1/);
        if (!match) continue;
        const damageId = parseInt(match[1]);
        const damageEffects = sd.getSpellEffects(damageId, true)?.filter(e => e.Effect === EFFECT_TYPE.SPELL_EFFECT_SCHOOL_DAMAGE) ?? [];
        const damage = damageEffects.find(e => e.EffectIndex === 0);
        if (!damage || sd.getSpellName(damageId, true)?.Name_lang !== name.Name_lang) continue;
        // A tick with more damage effects is one value only when the tooltip adds them up for the same enemy.
        // Consecration: "doing ${$1280349m1*8} Holy damage over $d to enemies who enter the area. The first $s3
        // enemies who enter the area will take an additional ${$1280349m2*8} damage" - the spell is shown for one
        // of those first enemies, who takes both parts.
        const additional = damageEffects.filter(e => e !== damage);
        if (additional.length > 0)
        {
            const allNamed = additional.every(e => new RegExp(`additional \\$\\{\\$${damageId}m${e.EffectIndex + 1}\\b`).test(spell.Description_lang));
            if (!allNamed || damageEffects.some(e => e.Variance))
            {
                report(`${sd.getSpellNameWithRank(spellId)} [${spellId}]: tick spell ${damageId} has ${damageEffects.length} damage effects the tooltip does not add up, no periodic damage generated`);
                continue;
            }
            report(`${sd.getSpellNameWithRank(spellId)} [${spellId}]: tick is ${damageEffects.map(e => e.EffectBasePointsF).join(" + ")} (every enemy + additional for the first enemies), shown as one value`);
        }
        const sum = (get: (e: SpellEffect) => number) => damageEffects.reduce((total, e) => total + (get(e) || 0), 0);

        const period = periodic.EffectAuraPeriod;
        target.Effect = EFFECT_TYPE.SPELL_EFFECT_PERSISTENT_AREA_AURA;
        target.EffectAura = AURA_TYPE.SPELL_AURA_PERIODIC_DAMAGE;
        target.EffectAuraPeriod = period;
        target.EffectBasePointsF = sum(e => e.EffectBasePointsF);
        target.Variance = damage.Variance;
        target.EffectRealPointsPerLevel = sum(e => e.EffectRealPointsPerLevel);
        target.EffectBonusCoefficient = sum(e => e.EffectBonusCoefficient);
        target.BonusCoefficientFromAP = sum(e => e.BonusCoefficientFromAP);
        if (isChannel) channelled++; else other++;
    }

    console.log(`Area trigger spells: tick damage taken from the spell named in the tooltip for ${channelled} channelled and ${other} other spells`);
}

export function fixSpellEffects(sd: SpellData)
{
    reportSection("Spell data fixes");
    areaTriggerFix(sd);
    paladinFix(sd);
    priestFix(sd);
    druidFixes(sd);
    warlockFixes(sd);
    shamanFix(sd);
    coefFixes(sd);
}
