import { SpellData, SpellEffect } from "../SpellData";
import { getEffectBase } from "../effectValues";

function getBaseValue(effect: SpellEffect)
{
    // Mean value; effects with a Variance (rolled values) use the middle like the old DieSides/2 handling did.
    let value = Math.round(getEffectBase(effect));

    if (effect.EffectPointsPerResource != 0)
    {
        value += effect.EffectPointsPerResource * 5;
    }

    return value;
}

export class TargetAuraHandlers
{
    private readonly spellData: SpellData;
    readonly handlers: { [index: number]: (effect: SpellEffect) => AddonEffectData | void } = {};

    constructor(spellData: SpellData)
    {
        this.spellData = spellData;

        this.handlers[AURA_TYPE.MOD_HEALING_TAKEN_PCT] = effect => 
        {
            const value = getBaseValue(effect);
            const aed: AddonEffectData = {
                type: ADDON_EFFECT_TYPE.TARGET_HEALING_RECIEVED,
                value: value,
                hasStacks: this.hasAuraCumStacks(effect.SpellID),
                auraCategory: (value > 0) ? ADDON_AURA_CATEGORY.HEALING_RECIEVED_POSITIVE : ADDON_AURA_CATEGORY.HEALING_RECIEVED_NEGATIVE,
            };
            return aed;
        }

        this.handlers[AURA_TYPE.MOD_MECHANIC_DAMAGE_TAKEN_PERCENT] = effect => 
        {
            if (effect.EffectMiscValue_0 == 0) throw new Error("MOD_MECHANIC_DAMAGE_TAKEN_PERCENT: EffectMiscValue_0 is 0!");
            return {
                type: ADDON_EFFECT_TYPE.TARGET_MECHANICMOD_DMG_TAKEN_PCT,
                affectMechanic: effect.EffectMiscValue_0,
                value: getBaseValue(effect),
                auraCategory: (effect.EffectMiscValue_0 == SpellMechanic.BLEED) ? ADDON_AURA_CATEGORY.BLEED_DAMAGE : undefined,
                hasStacks: this.hasAuraCumStacks(effect.SpellID)
            };
        }

        this.handlers[AURA_TYPE.MOD_DAMAGE_PERCENT_TAKEN] = effect => 
        {
            if (effect.EffectMiscValue_0 == 0)
            {
                if (effect.SpellID == 28348) return;
                throw new Error("MOD_DAMAGE_PERCENT_TAKEN: EffectMiscValue_0 is 0!");
            }

            const value = getBaseValue(effect);
            if (value == 0) return;

            return {
                type: ADDON_EFFECT_TYPE.TARGET_SCHOOLMOD_DMG_TAKEN_PCT,
                affectMask: effect.EffectMiscValue_0,
                value: value,
                hasStacks: this.hasAuraCumStacks(effect.SpellID)
            };
        }

        this.handlers[AURA_TYPE.SPELL_AURA_MOD_RESISTANCE] = effect => 
        {
            if (effect.EffectMiscValue_0 == 0) throw new Error("SPELL_AURA_MOD_RESISTANCE: EffectMiscValue_0 is 0!");

            const value = getBaseValue(effect);
            if (value == 0) return;

            return {
                type: ADDON_EFFECT_TYPE.SCHOOLMOD_RESISTANCE_PENETRATION,
                affectMask: effect.EffectMiscValue_0,
                value: -value,
                hasStacks: this.hasAuraCumStacks(effect.SpellID),
            };
        }

        this.handlers[AURA_TYPE.MOD_RESISTANCE_PCT] = effect => 
        {
            if (effect.EffectMiscValue_0 == 0) throw new Error("MOD_RESISTANCE_PCT: EffectMiscValue_0 is 0!");
            return {
                type: ADDON_EFFECT_TYPE.TARGET_SCHOOLMOD_RESISTANCE_PCT,
                affectMask: effect.EffectMiscValue_0,
                value: getBaseValue(effect),
                hasStacks: this.hasAuraCumStacks(effect.SpellID)
            };
        }

        this.handlers[AURA_TYPE.SPELL_AURA_MOD_DAMAGE_TAKEN] = effect => 
        {
            if (effect.EffectMiscValue_0 == 0)
            {
                if (effect.SpellID == 398117) return;
                if (effect.SpellID == 428491) return;
                throw new Error("SPELL_AURA_MOD_DAMAGE_TAKEN: EffectMiscValue_0 is 0!");
            }

            const value = getBaseValue(effect);
            if (value == 0) return;

            return {
                type: ADDON_EFFECT_TYPE.TARGET_SCHOOLMOD_SPELLPOWER,
                affectMask: effect.EffectMiscValue_0,
                value: value,
                hasStacks: this.hasAuraCumStacks(effect.SpellID)
            };
        }

        // Forever (Mainline) "from caster" debuffs only increase the damage of the aura's caster.
        this.handlers[AURA_TYPE.MOD_SCHOOL_MASK_DAMAGE_FROM_CASTER] = effect =>
        {
            if (effect.EffectMiscValue_0 == 0) throw new Error("MOD_SCHOOL_MASK_DAMAGE_FROM_CASTER: EffectMiscValue_0 is 0!");
            const value = getBaseValue(effect);
            if (value == 0) return;
            return {
                type: ADDON_EFFECT_TYPE.TARGET_SCHOOLMOD_DMG_TAKEN_PCT,
                affectMask: effect.EffectMiscValue_0,
                value: value,
                hasStacks: this.hasAuraCumStacks(effect.SpellID)
            };
        }

        this.handlers[AURA_TYPE.MOD_SPELL_DAMAGE_FROM_CASTER] = effect =>
        {
            const mask = [effect.EffectSpellClassMask_0, effect.EffectSpellClassMask_1, effect.EffectSpellClassMask_2, effect.EffectSpellClassMask_3];
            if (mask.every(m => m === 0)) throw new Error("MOD_SPELL_DAMAGE_FROM_CASTER without a spell class mask");
            const value = getBaseValue(effect);
            if (value == 0) return;
            return {
                type: ADDON_EFFECT_TYPE.TARGET_SPELLMOD_DMG_TAKEN_FROM_CASTER,
                affectSpell: mask,
                value: value,
                hasStacks: this.hasAuraCumStacks(effect.SpellID)
            };
        }

        this.handlers[AURA_TYPE.MOD_TARGET_ARMOR_FOREVER] = effect =>
        {
            if (effect.EffectMiscValue_0 == 0) throw new Error("MOD_TARGET_ARMOR_FOREVER: EffectMiscValue_0 is 0!");
            const value = getBaseValue(effect);
            if (value == 0) return;
            return {
                type: ADDON_EFFECT_TYPE.SCHOOLMOD_RESISTANCE_PENETRATION,
                affectMask: effect.EffectMiscValue_0,
                value: -value,
                hasStacks: this.hasAuraCumStacks(effect.SpellID),
            };
        }

        this.handlers[AURA_TYPE.MOD_HEALING_TAKEN] = effect => 
        {
            const value = getBaseValue(effect);
            if (value == 0) return;

            return {
                type: ADDON_EFFECT_TYPE.TARGET_HEALPOWER,
                value: value,
                hasStacks: this.hasAuraCumStacks(effect.SpellID)
            };
        }
    }

    /**
     * Check if spell aura is cumulatively stacking.
     * @param spellId 
     * @returns 
     */
    hasAuraCumStacks(spellId: number)
    {
        const cumAura = this.spellData.getSpellAuraOptions(spellId)?.CumulativeAura;
        return typeof cumAura !== "undefined" && cumAura > 1;
    }
}
