import { SpellEffect } from "./SpellData";

/**
 * Effect value helpers for the Forever (Mainline-style) SpellEffect schema.
 *
 * Classic Era stored EffectBasePoints + EffectDieSides (value = base + 1..dieSides).
 * Forever stores EffectBasePointsF (the mean value, a float) and Variance:
 *   low  = base * (1 - Variance / 2)
 *   high = base * (1 + Variance / 2)
 * Spell IDs stored inside effects (judgement dummies, Starfall triggers, ...) are
 * stored directly in EffectBasePointsF with Variance 0.
 */

const ROUNDING_WARN_EPSILON = 0.01;
/** Variance is stored as a rounded float, so low/high are rarely exact integers; only warn when the rounding is a near tie. */
const ROUNDING_TIE_EPSILON = 0.4;

function roundRolled(effect: SpellEffect, value: number, what: string)
{
    const rounded = Math.round(value);
    if (Math.abs(rounded - value) > ROUNDING_TIE_EPSILON)
    {
        console.warn(`Effect ${effect.ID} (spell ${effect.SpellID}, index ${effect.EffectIndex}): ${what} ${value} is a rounding tie, using ${rounded}`);
    }
    return rounded;
}

/**
 * Mean value of an effect (EffectBasePointsF). Use this for values that are not rolled,
 * i.e. aura amounts, percentages, spell IDs stored in effects, weapon percentages.
 */
export function getEffectBase(effect: SpellEffect)
{
    return effect.EffectBasePointsF;
}

/**
 * Low and high value of a rolled effect (damage/heal ranges).
 * Values are rounded to integers like the client rolls them.
 */
export function getEffectLowHigh(effect: SpellEffect): { low: number, high: number }
{
    const base = effect.EffectBasePointsF;
    const variance = effect.Variance;

    if (!variance) return { low: base, high: base };

    return {
        low: roundRolled(effect, base * (1 - variance / 2), "low value"),
        high: roundRolled(effect, base * (1 + variance / 2), "high value"),
    };
}

/**
 * Fill valueBase and valueRange of an EffectInfo-like object from an effect.
 */
export function fillBaseAndRange(target: { valueBase: number, valueRange: number }, effect: SpellEffect)
{
    const { low, high } = getEffectLowHigh(effect);
    target.valueBase = low;
    target.valueRange = high - low;
}

/**
 * Spell ID stored in an effect's base points (judgement dummies, Starfall, Living Bomb).
 */
export function getSpellIdFromEffect(effect: SpellEffect)
{
    const id = Math.round(effect.EffectBasePointsF);
    if (Math.abs(id - effect.EffectBasePointsF) > ROUNDING_WARN_EPSILON || id <= 0)
    {
        throw new Error(`Effect ${effect.ID} (spell ${effect.SpellID}) does not store a spell ID in its base points (${effect.EffectBasePointsF})!`);
    }
    return id;
}
