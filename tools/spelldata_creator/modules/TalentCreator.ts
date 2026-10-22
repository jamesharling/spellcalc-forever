import { AuraHandlers, USELESS_AURAS } from "../ItemAuraHandlers";
import { SpellData, SpellEffect } from "../SpellData";
import { createEffectLua, createFileHead } from "../itemFunctions";
import { ClassSpellSets } from "../ClassSpellSets";
import { getTalentDummies, TalentDummyDef } from "./talentDummies";
import { TraitData, TraitTalent } from "./TraitData";
import { report, reportSection } from "../report";
import { getEffectBase } from "../effectValues";

interface TalentDef
{
    name: string,
    /** Spell ID of the talent (TraitDefinition.SpellID); the addon keys talents by it (see system/talents.lua). */
    spellId: number,
    maxRanks: number,
    nodeId: number,
    posX: number,
    posY: number,
    effects: AddonTalentData[]
}

const AURA_TYPES_TO_IGNORE: { [index: number]: true | undefined } = {};
Object.assign(AURA_TYPES_TO_IGNORE, USELESS_AURAS);

const AURA_EFFECTS = [
    EFFECT_TYPE.SPELL_EFFECT_APPLY_AURA,
    EFFECT_TYPE.SPELL_EFFECT_APPLY_AREA_AURA_PARTY,
    EFFECT_TYPE.SPELL_EFFECT_PERSISTENT_AREA_AURA,
];

/** Nodes further apart than this on the X axis belong to different columns groups (the three old talent trees). */
const COLUMN_GROUP_WIDTH = 4000;

function roundValue(v: number)
{
    return Math.round(v * 10000) / 10000;
}

export class TalentsCreator
{
    private readonly spellData: SpellData;
    private readonly auraHandlers: AuraHandlers;
    private readonly traitData: TraitData;
    private readonly dummyTalents: { [talentName: string]: TalentDummyDef[] };

    constructor(spellData: SpellData, auraHandlers: AuraHandlers, classSpellSets: ClassSpellSets, traitData: TraitData)
    {
        this.spellData = spellData;
        this.auraHandlers = auraHandlers;
        this.traitData = traitData;
        this.dummyTalents = getTalentDummies(spellData, classSpellSets);
    }

    /**
     * Copy of the talent spell's effects with the values of the given rank.
     */
    private getEffectsForRank(talent: TraitTalent, rank: number): SpellEffect[]
    {
        const effects = this.spellData.getSpellEffects(talent.spellId);
        return effects.map(effect =>
        {
            const value = TraitData.getRankValue(talent, effect.EffectIndex, rank, getEffectBase(effect));
            if (value === getEffectBase(effect)) return effect;
            const clone: SpellEffect = { ...effect, EffectBasePointsF: value, Variance: 0 };
            return clone;
        });
    }

    /**
     * Convert the aura effects of one rank to addon effects.
     * @returns one entry per effect index (undefined where the effect is not used)
     */
    private convertEffects(talentName: string, effects: SpellEffect[]): (AddonEffectData | undefined)[]
    {
        const result: (AddonEffectData | undefined)[] = [];

        for (const eff of effects)
        {
            let converted: AddonEffectData | undefined;

            if (AURA_EFFECTS.indexOf(eff.Effect) !== -1 && !AURA_TYPES_TO_IGNORE[eff.EffectAura])
            {
                const handler = this.auraHandlers.handlers[eff.EffectAura];
                if (!handler)
                {
                    report(`${talentName} (${eff.SpellID}) effect ${eff.EffectIndex}: aura type ${eff.EffectAura} is not handled, effect skipped`);
                }
                else
                {
                    try
                    {
                        converted = handler(eff) || undefined;
                    }
                    catch (error)
                    {
                        report(`${talentName} (${eff.SpellID}) effect ${eff.EffectIndex} skipped: ${error}`);
                    }
                }
            }

            result[eff.EffectIndex] = converted;
        }

        return result;
    }

    /**
     * Collapse per-rank values to perPoint when they grow linearly, otherwise keep the list.
     */
    private static applyRankValues(effect: AddonTalentData, values: number[])
    {
        effect.value = undefined;

        const rounded = values.map(roundValue);
        const perPoint = rounded[0];
        const linear = rounded.every((v, i) => Math.abs(v - perPoint * (i + 1)) < 0.0001);

        if (linear)
            effect.perPoint = perPoint;
        else
            effect.values = rounded;
    }

    /**
     * Build effect list for talent from its spell effects and rank curves.
     */
    private getTalentEffects(talentName: string, talent: TraitTalent): AddonTalentData[]
    {
        const perRank: (AddonEffectData | undefined)[][] = [];

        for (let rank = 1; rank <= talent.maxRanks; rank++)
        {
            perRank.push(this.convertEffects(talentName, this.getEffectsForRank(talent, rank)));
        }

        const talentEffects: AddonTalentData[] = [];
        const effectCount = perRank[0].length;

        for (let effIndex = 0; effIndex < effectCount; effIndex++)
        {
            const first = perRank[0][effIndex];
            if (!first) continue;

            const values: number[] = [];
            let usable = true;

            for (let rank = 0; rank < perRank.length; rank++)
            {
                const rankEffect = perRank[rank][effIndex];
                if (!rankEffect || rankEffect.type !== first.type)
                {
                    report(`${talentName} (${talent.spellId}) effect ${effIndex}: rank ${rank + 1} converts differently than rank 1, effect skipped`);
                    usable = false;
                    break;
                }
                values.push(rankEffect.value ?? 0);
            }

            if (!usable) continue;
            if (values.every(v => v === 0)) continue;

            if (talent.maxRanks > 1 && !talent.rankValues.has(effIndex))
            {
                report(`${talentName} (${talent.spellId}) effect ${effIndex}: no rank curve, value ${values[0]} is used for all ${talent.maxRanks} ranks (check the tooltip)`);
            }

            const talentEffect: AddonTalentData = first;
            TalentsCreator.applyRankValues(talentEffect, values);
            talentEffects.push(talentEffect);
        }

        return talentEffects;
    }

    /**
     * Build effect list for a talent with a hand-written definition.
     */
    private getDummyTalentEffects(talent: TraitTalent, dummies: TalentDummyDef[]): AddonTalentData[]
    {
        const result: AddonTalentData[] = [];

        for (const dummy of dummies)
        {
            const values: number[] = [];
            for (let rank = 1; rank <= talent.maxRanks; rank++)
            {
                const effectValues = this.getEffectsForRank(talent, rank).map(getEffectBase);
                values.push(dummy.valueForRank(effectValues, rank, talent.spellId));
            }

            const effect: AddonTalentData = {
                type: dummy.type,
                affectSpell: dummy.affectSpell,
                affectMask: dummy.affectMask,
            };
            TalentsCreator.applyRankValues(effect, values);
            result.push(effect);
        }

        return result;
    }

    /**
     * Talents that require an equipped weapon type (weapon specializations, Wand Specialization) only
     * modify damage done with that weapon. Physical damage bonuses get the weapon requirement so the
     * addon applies them only while such a weapon is equipped; bonuses to magic schools would apply to
     * every spell instead of the weapon's own damage (wand shots), so they are dropped.
     */
    private applyWeaponRequirement(talentName: string, spellId: number, effects: AddonTalentData[]): AddonTalentData[]
    {
        const equipped = this.spellData.getSpellEquipeedItems(spellId);
        if (!equipped || equipped.EquippedItemClass !== ItemClass.ITEM_CLASS_WEAPON || !equipped.EquippedItemSubclass) return effects;

        const kept: AddonTalentData[] = [];
        for (const eff of effects)
        {
            const physicalOnly = eff.affectMask === SCHOOL_MASK.PHYSICAL && !eff.affectSpell;
            if (physicalOnly)
            {
                eff.neededWeaponMask = equipped.EquippedItemSubclass;
                kept.push(eff);
            }
            else
            {
                report(`${talentName} (${spellId}) requires weapon subclass mask ${equipped.EquippedItemSubclass}; its ${eff.type.replace("_addon.CONST.EFFECT_TYPE.", "")} effect only applies to that weapon's damage and is dropped`);
            }
        }
        return kept;
    }

    /**
     * Build talent list for player class.
     */
    private getTalentList(pclass: PlayerClass)
    {
        const treeId = this.traitData.getClassTreeId(pclass);
        const traitTalents = this.traitData.getTalents(treeId);
        const list: TalentDef[] = [];
        const seenSpells = new Set<number>();

        console.log(`${pclass}: trait tree ${treeId} with ${traitTalents.length} node entries`);

        for (const talent of traitTalents)
        {
            if (!talent.spellId)
            {
                report(`node ${talent.nodeId}: entry ${talent.entryId} has no spell, skipped`);
                continue;
            }

            if (seenSpells.has(talent.spellId))
            {
                report(`node ${talent.nodeId}: spell ${talent.spellId} already handled by another node, skipped`);
                continue;
            }
            seenSpells.add(talent.spellId);

            if (!this.spellData.spellExists(talent.spellId))
            {
                report(`node ${talent.nodeId}: spell ${talent.spellId} does not exist in the client data, skipped`);
                continue;
            }

            const talentName = this.spellData.getSpellName(talent.spellId).Name_lang;

            // Active abilities granted by talents (Arcane Power, Inner Focus, ...) are handled as regular
            // spells and, when they buff the player, through auras.lua while the buff is up.
            if (this.spellData.getSpellPowerCosts(talent.spellId).length !== 0) continue;
            if ((this.spellData.getSpellMisc(talent.spellId).Attributes_0 & SPELL_ATTR0.SPELL_ATTR_PASSIVE) === 0)
            {
                report(`${talentName} (${talent.spellId}) is an active ability, not applied as a permanent talent effect`);
                continue;
            }

            if (!this.spellData.getSpellEffects(talent.spellId, true)) continue;

            let talentEffects: AddonTalentData[];
            try
            {
                if (this.dummyTalents[talentName])
                {
                    talentEffects = this.getDummyTalentEffects(talent, this.dummyTalents[talentName]);
                    report(`${talentName} (${talent.spellId}) uses a hand-written definition: ${talentEffects.map(e => `${e.type.replace("_addon.CONST.EFFECT_TYPE.", "")}=${e.values ? "{" + e.values.join(",") + "}" : e.perPoint + "/pt"}`).join(", ")}`);
                }
                else
                {
                    talentEffects = this.getTalentEffects(talentName, talent);
                }
            }
            catch (error)
            {
                report(`${talentName} (${talent.spellId}) skipped: ${error}`);
                continue;
            }

            talentEffects = this.applyWeaponRequirement(talentName, talent.spellId, talentEffects);
            if (talentEffects.length === 0) continue;

            list.push({
                name: talentName,
                spellId: talent.spellId,
                maxRanks: talent.maxRanks,
                nodeId: talent.nodeId,
                posX: talent.posX,
                posY: talent.posY,
                effects: talentEffects
            });
        }

        list.sort((a, b) =>
        {
            const ga = Math.floor(a.posX / COLUMN_GROUP_WIDTH);
            const gb = Math.floor(b.posX / COLUMN_GROUP_WIDTH);
            if (ga !== gb) return ga - gb;
            if (a.posY !== b.posY) return a.posY - b.posY;
            return a.posX - b.posX;
        });

        return list;
    }

    buildTalentLua(pclass: PlayerClass)
    {
        console.log("Building talents for " + pclass);
        reportSection(`Talents: ${pclass}`);

        const list = this.getTalentList(pclass);

        let lua = createFileHead(pclass);
        lua += `-- Talents are keyed by their spell ID (C_Traits definition spell). Multi-rank talents are one spell;
-- perPoint/values give the effect value per rank (from the client's rank curves).

---@type TalentDataRawEntry[]
_addon.talentDataRaw = {`;

        let lastGroup = -1;
        for (const talent of list)
        {
            const group = Math.floor(talent.posX / COLUMN_GROUP_WIDTH);
            if (group !== lastGroup)
            {
                lua += `
    -----------------------------
    -- Column group ${group + 1}
    -----------------------------`;
                lastGroup = group;
            }

            lua += `
    { -- ${talent.name} (node ${talent.nodeId}, ${talent.maxRanks} rank${talent.maxRanks > 1 ? "s" : ""})
        name = ${JSON.stringify(talent.name)},
        spellId = ${talent.spellId},
        maxRanks = ${talent.maxRanks},
        effects = {\n`;
            for (const eff of talent.effects)
            {
                const valKey = eff.values ? "values" : "perPoint";
                const value = eff.values ? `{${eff.values.join(", ")}}` : eff.perPoint;
                lua += createEffectLua("            ", eff, { [valKey]: value });
            }
            lua += `        }
    },`;
        }

        lua += "\n}\n";

        console.log(`${pclass}: ${list.length} talents with addon effects`);

        return lua;
    }
}
