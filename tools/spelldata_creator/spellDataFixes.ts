import { SpellEffect, SpellData } from "./SpellData";
import { cfg } from "./config";
import { isJudgeDummy, SealType, getSeals } from "./paladinCrap";
import { getSpellIdFromEffect } from "./effectValues";
import { report, reportSection } from "./report";
import * as fs from "fs";

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

    // Penance channel -> periodic trigger spells
    const PENANCE_TRIGGERS: { [spellId: number]: { dmg: number, heal: number } } = {
        402174: { dmg: 402261, heal: 402277 },
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

    // Penance
    for (const penanceId in PENANCE_TRIGGERS)
    {
        const effects = effectsOf(sd, parseInt(penanceId), "Penance");
        if (!effects) continue;
        const heal = effectsOf(sd, PENANCE_TRIGGERS[penanceId].heal, "Penance heal");
        const dmg = effectsOf(sd, PENANCE_TRIGGERS[penanceId].dmg, "Penance damage");
        if (!heal || !dmg) continue;

        for (const eff of effects)
        {
            if (eff.EffectIndex === 0)
            {
                // Heal effect
                let done = false;
                for (const heff of heal)
                {
                    if (heff.EffectAura == AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL)
                    {
                        const origId = eff.SpellID;
                        Object.assign(eff, heff);
                        eff.SpellID = origId;
                        eff.EffectIndex = 0;
                        done = true;
                        break;
                    }
                }
                if (!done)
                {
                    report(`Penance ${eff.SpellID}: couldn't find the heal trigger effect`);
                    break;
                }

                // damage
                done = false;
                for (const deff of dmg)
                {
                    if (deff.EffectAura == AURA_TYPE.SPELL_AURA_PERIODIC_TRIGGER_SPELL)
                    {
                        deff.EffectIndex = 1;
                        deff.SpellID = eff.SpellID;
                        effects.push(deff);
                        done = true;
                        break;
                    }
                }
                if (!done)
                {
                    report(`Penance ${eff.SpellID}: couldn't find the damage trigger effect`);
                    break;
                }

                sd.getSpellMisc(eff.SpellID).DurationIndex = 39;
            }
        }
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

export function fixSpellEffects(sd: SpellData)
{
    reportSection("Spell data fixes");
    paladinFix(sd);
    priestFix(sd);
    druidFixes(sd);
    warlockFixes(sd);
    shamanFix(sd);
    coefFixes(sd);
}
