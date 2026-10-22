import { readDBCSVtoMap } from "../CSVReader";
import { cfg } from "../config";
import { getClassMaskFromName } from "../helper";

/**
 * Class spell books from SkillLine / SkillLineAbility / SkillRaceClassInfo.
 *
 * Forever keeps the Classic Era structure of three class skill lines per class
 * (e.g. mage: Arcane 237, Fire 8, Frost 6). SkillRaceClassInfo tells which class a
 * skill line belongs to.
 */

interface DBCSkillLine
{
    DisplayName_lang: string,
    ID: number,
    CategoryID: number,
    ParentSkillLineID: number,
}

interface DBCSkillLineAbility
{
    ID: number,
    SkillLine: number,
    Spell: number,
    MinSkillLineRank: number,
    ClassMask: number,
    SupercedesSpell: number,
    AcquireMethod: number,
    Flags: number,
}

interface DBCSkillRaceClassInfo
{
    ID: number,
    SkillID: number,
    ClassMask: number,
    Flags: number,
    Availability: number,
    MinLevel: number,
}

/** SkillLine.CategoryID of class skill lines. */
const SKILL_CATEGORY_CLASS = 7;

/**
 * SkillLineAbility.AcquireMethod values seen in the Forever data. 3 marks spells that are in
 * the table but cannot be learned (Season of Discovery rune abilities, removed spells).
 */
const ACQUIRE_METHOD_UNAVAILABLE = 3;

export class SkillData
{
    private readonly skillLines: Map<number, DBCSkillLine>;
    private readonly skillLineAbilities: Map<number, DBCSkillLineAbility>;
    private readonly skillRaceClassInfo: Map<number, DBCSkillRaceClassInfo>;

    constructor()
    {
        this.skillLines = readDBCSVtoMap<DBCSkillLine>(cfg.dataDir + "dbc/SkillLine.csv", "ID");
        this.skillLineAbilities = readDBCSVtoMap<DBCSkillLineAbility>(cfg.dataDir + "dbc/SkillLineAbility.csv", "ID");
        this.skillRaceClassInfo = readDBCSVtoMap<DBCSkillRaceClassInfo>(cfg.dataDir + "dbc/SkillRaceClassInfo.csv", "ID");
    }

    /**
     * IDs of the class skill lines of a class (pet skill lines excluded).
     */
    getClassSkillLineIds(pclass: PlayerClass)
    {
        const classMask = getClassMaskFromName(pclass);
        const ids: number[] = [];

        for (const srci of this.skillRaceClassInfo.values())
        {
            if (srci.ClassMask !== classMask) continue;
            const line = this.skillLines.get(srci.SkillID);
            if (!line || line.CategoryID !== SKILL_CATEGORY_CLASS) continue;
            if (line.DisplayName_lang.startsWith("Pet")) continue;
            if (ids.indexOf(line.ID) === -1) ids.push(line.ID);
        }

        return ids;
    }

    getSkillLineName(skillLineId: number)
    {
        return this.skillLines.get(skillLineId)?.DisplayName_lang ?? ("skill line " + skillLineId);
    }

    /**
     * Learnable spells of a class' skill lines.
     * @returns Map spell ID -> skill line name (for reporting)
     */
    getClassSpells(pclass: PlayerClass)
    {
        const lineIds = this.getClassSkillLineIds(pclass);
        const spells = new Map<number, string>();

        for (const sla of this.skillLineAbilities.values())
        {
            if (lineIds.indexOf(sla.SkillLine) === -1) continue;
            if (sla.AcquireMethod === ACQUIRE_METHOD_UNAVAILABLE) continue;
            if (!spells.has(sla.Spell)) spells.set(sla.Spell, this.getSkillLineName(sla.SkillLine));
        }

        return spells;
    }
}
