import { readDBCSV, readDBCSVtoMap } from "../../CSVReader";
import { SpellData } from "../../SpellData";
import { cfg } from "../../config";
import { report, reportSection } from "../../report";
import { ScalingFormulaParsed } from "./parser";
import { ClassSpellLists } from "../../ClassSpellLists";

interface SpellXDescriptionVariables
{
    ID: number,
    SpellID: number,
    SpellDescriptionVariablesID: number
}

interface SpellDescriptionVariables
{
    ID: number,
    Variables: string,
}

/** Variables that describe level based scaling of a spell's values (Season of Discovery style). */
const SCALING_LABELS = ["damagepower", "power", "base", "healpower"];

const LUA_IDENTIFIER = /^[A-Za-z_][A-Za-z0-9_]*$/;

/**
 * Spells whose values scale with the player level through description variables
 * ("$<power>" etc. in the description).
 *
 * Forever attaches description variable sets to many Classic Era spells only to show
 * talent multipliers in the tooltip (e.g. "$<frostdamage>" on Frostbolt), so a spell is
 * only treated as scaling when its description actually references a scaling variable.
 */
export class SpellLevelScaling
{
    private readonly spellData: SpellData;
    /** Map<set id, Map<name, formula>> */
    private readonly descriptionVariables = new Map<number, Map<string, ScalingFormulaParsed>>();
    /** Variable sets the parser could not handle (not needed unless a spell uses them). */
    private readonly unparsableSets = new Map<number, string>();
    /** SpellId -> variable set Id */
    private readonly spellMappings = new Map<number, { variablesId: number, variablesKey: string }>();

    /**
     * @param classSpellLists Only spells in these lists are mentioned in the report.
     */
    constructor(spellData: SpellData, classSpellLists: ClassSpellLists)
    {
        this.spellData = spellData;
        reportSection("Spell level scaling");

        const spellDescVars = readDBCSV<SpellDescriptionVariables>(cfg.dataDir + "dbc/SpellDescriptionVariables.csv", "ID");
        for (const id in spellDescVars)
        {
            const setId = parseInt(id);
            try
            {
                const varSplit = spellDescVars[id].Variables.trim().split("\n");
                const variables = new Map<string, ScalingFormulaParsed>();

                for (const varEntry of varSplit)
                {
                    if (varEntry.trim().length === 0) continue;
                    const parsed = ScalingFormulaParsed.fromString(varEntry);
                    if (!LUA_IDENTIFIER.test(parsed.label)) throw new Error(`label "${parsed.label}" is not a valid Lua identifier`);
                    variables.set(parsed.label, parsed);
                }

                this.descriptionVariables.set(setId, variables);
            }
            catch (error)
            {
                const msg = error instanceof Error ? error.message : String(error);
                this.unparsableSets.set(setId, msg);
            }
        }

        const spellXDescVars = readDBCSVtoMap<SpellXDescriptionVariables>(cfg.dataDir + "dbc/SpellXDescriptionVariables.csv", "ID");
        for (const entry of spellXDescVars.values())
        {
            const variablesId = entry.SpellDescriptionVariablesID;
            const spellId = entry.SpellID;

            if (!this.spellData.spellExists(spellId)) continue;

            const keyForSpell = this.spellResolveVariableName(variablesId, spellId);
            if (!keyForSpell) continue;

            if (this.unparsableSets.has(variablesId))
            {
                report(`${this.spellData.getSpellNameWithRank(spellId)} [${spellId}] uses variable set ${variablesId} which could not be parsed: ${this.unparsableSets.get(variablesId)}`);
                continue;
            }

            this.spellMappings.set(spellId, { variablesId: variablesId, variablesKey: keyForSpell });
            if (classSpellLists.isHandledSpell(spellId))
            {
                report(`${this.spellData.getSpellNameWithRank(spellId)} [${spellId}] scales with level: set ${variablesId} variable "${keyForSpell}"`);
            }
        }

        console.log(`Spell level scaling: ${this.spellMappings.size} spells use scaling variables`);
    }

    /**
     * Scaling variable a spell uses in its description, if any.
     */
    private spellResolveVariableName(variablesId: number, spellId: number)
    {
        const effects = this.spellData.getSpellEffects(spellId, true);
        if (!effects) return;

        const spell = this.spellData.getSpell(spellId, true);
        if (!spell) return;
        const description = spell.Description_lang + " " + spell.AuraDescription_lang;

        const variables = this.descriptionVariables.get(variablesId);
        const isReferenced = (label: string) =>
        {
            if (variables && !variables.has(label)) return false;
            return description.indexOf("$<" + label + ">") !== -1;
        };

        const isHeal = effects[0].Effect == EFFECT_TYPE.SPELL_EFFECT_HEAL || effects[0].EffectAura == AURA_TYPE.SPELL_AURA_PERIODIC_HEAL;
        if (isHeal && isReferenced("healpower")) return "healpower";

        for (const label of SCALING_LABELS)
        {
            if (isReferenced(label)) return label;
        }

        return;
    }

    /**
     * Get key for variable function if spell uses special scaling.
     * @param spellId
     * @returns
     */
    getVariableKeyForSpell(spellId: number)
    {
        const mapping = this.spellMappings.get(spellId);
        if (!mapping) return;
        return { id: mapping.variablesId, label: mapping.variablesKey }
    }

    /**
     * Variable set IDs used by at least one spell.
     */
    private getUsedSetIds()
    {
        const ids = new Set<number>();
        for (const mapping of this.spellMappings.values()) ids.add(mapping.variablesId);
        return Array.from(ids).sort((a, b) => a - b);
    }

    /**
     * Get Lua table of the variable sets.
     * @param varName For the table variable.
     * @param ids Optionally get specific sets; default are the sets used by spells.
     * @returns
     */
    getVarSetsLua(varName: string, ids?: number[])
    {
        let lua = `---@type table<number, table<string, fun(playerLevel:number):number>>
${varName} = {\n`;

        ids = ids ?? this.getUsedSetIds();

        for (const setId of ids)
        {
            const vars = this.descriptionVariables.get(setId);
            if (!vars) throw new Error("Invalid or unparsable variable set id " + setId);

            lua += `    [${setId}] = {\n`;

            for (const [label, sform] of vars)
            {
                lua += `        ${label} = ${sform.asLuaFunctionString()},\n`;
            }

            lua += `    },\n`;
        }

        lua += "}\n";
        return lua;
    }
}
