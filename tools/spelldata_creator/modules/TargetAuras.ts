import * as fs from "fs";
import { createEffectLua, createFileHead } from "../itemFunctions";
import { SpellData, SpellEffect } from "../SpellData";
import { TargetAuraHandlers } from "./TargetAuraHandlers";
import { report, reportSection } from "../report";
import { cfg } from "../config";

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
}

interface AssumableAura
{
    spellId: number,
    cls: string,
    maxStacks: number,
    fromCaster: boolean,
    effects: AddonEffectData[],
}

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

            const { effects, fromCaster } = this.processEffects(spellId);
            if (effects.length === 0)
            {
                report(`${entry.class} ${this.spellData.getSpellNameWithRank(spellId)} [${spellId}]: no effects the addon models, skipped`);
                continue;
            }

            const cumulative = this.spellData.getSpellAuraOptions(spellId)?.CumulativeAura ?? 0;
            auras.push({ spellId, cls: entry.class, maxStacks: cumulative > 1 ? cumulative : 1, fromCaster, effects });
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
            luaStr += `    { spellId = ${aura.spellId}, class = "${aura.cls}", maxStacks = ${aura.maxStacks}${aura.fromCaster ? ", fromCaster = true" : ""} }, -- ${this.spellData.getSpellNameWithRank(aura.spellId)}\n`;
            report(`${aura.cls}: ${this.spellData.getSpellNameWithRank(aura.spellId)} [${aura.spellId}]${aura.maxStacks > 1 ? `, up to ${aura.maxStacks} stacks` : ""}${aura.fromCaster ? ", caster's own damage only" : ""}`);
        }
        luaStr += `}\n`;

        console.log(`${auras.length} assumable target auras`);
        return luaStr;
    }
}
