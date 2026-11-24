import * as fs from "fs";
import { createEffectLua, createFileHead } from "../itemFunctions";
import { SpellData, SpellEffect } from "../SpellData";
import { TargetAuraHandlers } from "./TargetAuraHandlers";
import { report, reportSection } from "../report";
import { cfg } from "../config";
import { getEffectBase } from "../effectValues";

/**
 * Target auras the player can choose to assume (Settings > Target Auras).
 *
 * Forever makes aura data secret in combat, and debuffs on a target almost only exist in combat, so the
 * addon no longer scans the target's auras. Instead it offers a curated list of class debuffs and
 * helpful target buffs (data/forever/targetAuras.json) and applies the ones the player picks. The
 * generator resolves each entry to the highest rank in the client data and converts its effects.
 */

const DO_AURAS: { [index: number]: true | undefined } = {
    [AURA_TYPE.SPELL_AURA_MOD_DAMAGE_TAKEN]: true, // = spell power? (misc_0 = school mask)
    [AURA_TYPE.MOD_HEALING_TAKEN]: true, // = heal power?
    [AURA_TYPE.SPELL_AURA_MOD_RESISTANCE]: true,
    [AURA_TYPE.MOD_DAMAGE_PERCENT_TAKEN]: true,
    [AURA_TYPE.MOD_RESISTANCE_PCT]: true,
    [AURA_TYPE.MOD_HEALING_TAKEN_PCT]: true,
    [AURA_TYPE.MOD_MECHANIC_DAMAGE_TAKEN_PERCENT]: true,
    [AURA_TYPE.MOD_SCHOOL_MASK_DAMAGE_FROM_CASTER]: true,
    [AURA_TYPE.MOD_SPELL_DAMAGE_FROM_CASTER]: true,
    [AURA_TYPE.MOD_TARGET_ARMOR_FOREVER]: true,
}

/** Aura types that only increase damage done by the aura's caster. */
const FROM_CASTER_AURAS = new Set<number>([
    AURA_TYPE.MOD_SCHOOL_MASK_DAMAGE_FROM_CASTER,
    AURA_TYPE.MOD_SPELL_DAMAGE_FROM_CASTER,
]);

const AURA_EFFECTS = [
    EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA,
    EFFECT_TYPE.SPELL_EFFECT_PERSISTENT_AREA_AURA,
    EFFECT_TYPE.SPELL_EFFECT_APPLY_AREA_AURA_PARTY,
];

/** class token -> SpellClassOptions.SpellClassSet */
const CLASS_SET: { [cls: string]: number } = {
    MAGE: 3, WARRIOR: 4, WARLOCK: 5, PRIEST: 6, DRUID: 7, ROGUE: 8, HUNTER: 9, PALADIN: 10, SHAMAN: 11,
};

interface CuratedAura
{
    class: string,
    name: string,
    id?: number,
    note?: string,
    /** Name of the option instead of the spell's name (the aura stands for a state, e.g. a frozen target). */
    label?: string,
    /** Highest count to offer when the spell itself is not a stacking aura. */
    maxStacks?: number,
}

interface AssumableAura
{
    spellId: number,
    cls: string,
    maxStacks: number,
    fromCaster: boolean,
    effects: AddonEffectData[],
    label?: string,
}

const ALL_SPELLS = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF];

export class TargetAuras
{
    private readonly spellData: SpellData;
    private readonly handlers: TargetAuraHandlers["handlers"];

    constructor(spellData: SpellData)
    {
        this.spellData = spellData;
        this.handlers = new TargetAuraHandlers(spellData).handlers;
    }

    /**
     * Addon effects of a spell's target aura effects.
     */
    private processEffects(spellId: number): { effects: AddonEffectData[], fromCaster: boolean }
    {
        const aedarr: AddonEffectData[] = [];
        let fromCaster = false;
        const name = this.spellData.getSpellNameWithRank(spellId);

        for (const spellEffect of this.spellData.getSpellEffects(spellId, true) ?? [] as SpellEffect[])
        {
            if (AURA_EFFECTS.indexOf(spellEffect.Effect) === -1) continue;
            if (!DO_AURAS[spellEffect.EffectAura]) continue;

            try
            {
                const aed = this.handlers[spellEffect.EffectAura](spellEffect);
                if (aed)
                {
                    aedarr.push(aed);
                    if (FROM_CASTER_AURAS.has(spellEffect.EffectAura)) fromCaster = true;
                }
            }
            catch (error)
            {
                report(`${name} [${spellId}] effect ${spellEffect.EffectIndex} skipped: ${error}`);
            }
        }

        return { effects: aedarr, fromCaster };
    }

    /**
     * Highest-level spell of a class with the given name.
     */
    private findHighestRank(cls: string, name: string)
    {
        const set = CLASS_SET[cls];
        let best: number | undefined;
        let bestLevel = -1;
        for (const spellId of this.spellData.getSpellsByName(name, true) ?? [])
        {
            if (!this.spellData.spellExists(spellId)) continue;
            if (this.spellData.getSpellClassOption(spellId, true)?.SpellClassSet !== set) continue;
            const level = this.spellData.getSpellLevel(spellId, true)?.SpellLevel ?? 0;
            if (level > bestLevel || (level === bestLevel && best !== undefined && spellId > best))
            {
                best = spellId;
                bestLevel = level;
            }
        }
        return best;
    }

    /**
     * Effects the handlers cannot read from the aura: dummy effects, and states a debuff stands for.
     */
    private getExtraEffects(entry: CuratedAura, spellId: number): AddonEffectData[]
    {
        const effects = this.spellData.getSpellEffects(spellId);

        // "Taking $s1% increased damage and $s2% increased spell power coefficient from the caster's next Cone of
        // Cold spell." The talent: "it gains an additional $s3% of your spell damage" per application. The second
        // effect is a dummy; the first one names Cone of Cold.
        if (entry.class === "MAGE" && entry.name === "Winter's Chill")
        {
            const damage = effects.find(e => e.EffectAura === AURA_TYPE.MOD_SPELL_DAMAGE_FROM_CASTER);
            const coef = effects.find(e => e.EffectIndex === 1 && e.EffectAura === AURA_TYPE.SPELL_AURA_DUMMY);
            if (!damage || !coef || getEffectBase(coef) <= 0)
            {
                report(`${entry.class} ${entry.name} [${spellId}]: no spell power coefficient effect found, only the damage taken part is applied`);
                return [];
            }
            return [{
                type: ADDON_EFFECT_TYPE.SPELLMOD_FLAT_SPELL_SCALE,
                affectSpell: [damage.EffectSpellClassMask_0, damage.EffectSpellClassMask_1, damage.EffectSpellClassMask_2, damage.EffectSpellClassMask_3],
                value: getEffectBase(coef),
                hasStacks: this.spellData.getSpellAuraOptions(spellId)!.CumulativeAura > 1,
            }];
        }

        // A frozen target, offered under Frost Nova. Both effects are scripts in data/forever/classes/mage.lua that
        // run for every spell: Mage_Frozen_Damage applies a spell's own bonus against frozen targets (Ice Lance,
        // frozenDamagePct in its spell data), Mage_Frozen_Crit adds the critical strike chance of Shatter (the
        // talent stores its value).
        if (entry.class === "MAGE" && entry.name === "Frost Nova")
        {
            return [
                { type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_DONE_PCT, affectSpell: ALL_SPELLS, scriptKey: "Mage_Frozen_Damage", value: 0 },
                { type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_CRIT_CHANCE, affectSpell: ALL_SPELLS, scriptKey: "Mage_Frozen_Crit", value: 0 },
            ];
        }

        // The player's own Fire effects on the target, offered under the Fire Power talent, which adds Fire damage
        // for each of them. The effect's value is the number of effects (1 per application); the Mage_Fire_Effects
        // script multiplies it with the percentage the talent stores.
        if (entry.class === "MAGE" && entry.name === "Fire Power")
        {
            return [{ type: ADDON_EFFECT_TYPE.SCRIPT_SPELLMOD_DONE_PCT, affectSpell: ALL_SPELLS, scriptKey: "Mage_Fire_Effects", value: 1, hasStacks: true }];
        }

        return [];
    }

    private getAssumableAuras()
    {
        const curated: CuratedAura[] = JSON.parse(fs.readFileSync(cfg.dataDir + "targetAuras.json", "utf8")).auras;
        const auras: AssumableAura[] = [];

        for (const entry of curated)
        {
            const spellId = entry.id ?? this.findHighestRank(entry.class, entry.name);
            if (!spellId || !this.spellData.spellExists(spellId))
            {
                report(`${entry.class} ${entry.name}${entry.id ? ` [${entry.id}]` : ""}: not found in the client data, skipped`);
                continue;
            }

            let { effects, fromCaster } = this.processEffects(spellId);
            const extra = this.getExtraEffects(entry, spellId);
            if (extra.length > 0)
            {
                // Hand-written effects change the player's own spells only.
                effects = effects.concat(extra);
                fromCaster = true;
            }
            if (effects.length === 0)
            {
                report(`${entry.class} ${this.spellData.getSpellNameWithRank(spellId)} [${spellId}]: no effects the addon models, skipped`);
                continue;
            }

            const cumulative = this.spellData.getSpellAuraOptions(spellId)?.CumulativeAura ?? 0;
            auras.push({ spellId, cls: entry.class, maxStacks: entry.maxStacks ?? (cumulative > 1 ? cumulative : 1), fromCaster, effects, label: entry.label });
        }

        return auras;
    }

    getAuraLua()
    {
        console.log("Creating Lua for assumable target auras...");
        reportSection("Assumable target auras");

        const auras = this.getAssumableAuras();

        let luaStr = createFileHead();
        luaStr += `-- Target auras the player can assume in the settings (the addon doesn't scan the target: aura data is
-- secret in combat on Forever). Curated in tools/spelldata_creator/data/forever/targetAuras.json.

---@type table<integer, UnitAuraEffect[]>
_addon.aurasTarget = {\n`;

        for (const aura of auras)
        {
            luaStr += `    [${aura.spellId}] = { -- ${this.spellData.getSpellNameWithRank(aura.spellId)}\n`;
            for (const effect of aura.effects)
            {
                luaStr += createEffectLua("        ", effect);
            }
            luaStr += `    },\n`;
        }

        luaStr += `}\n\n---@type AssumableTargetAura[]\n_addon.assumableTargetAuras = {\n`;
        for (const aura of auras)
        {
            luaStr += `    { spellId = ${aura.spellId}, class = "${aura.cls}", maxStacks = ${aura.maxStacks}${aura.fromCaster ? ", fromCaster = true" : ""}${aura.label ? `, label = ${JSON.stringify(aura.label)}` : ""} }, -- ${this.spellData.getSpellNameWithRank(aura.spellId)}\n`;
            report(`${aura.cls}: ${this.spellData.getSpellNameWithRank(aura.spellId)} [${aura.spellId}]${aura.label ? ` as "${aura.label}"` : ""}${aura.maxStacks > 1 ? `, up to ${aura.maxStacks} stacks` : ""}${aura.fromCaster ? ", caster's own damage only" : ""}`);
        }
        luaStr += `}\n`;

        console.log(`${auras.length} assumable target auras`);
        return luaStr;
    }
}
