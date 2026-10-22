import { readDBCSVtoMap } from "../CSVReader";
import { cfg } from "../config";
import { SkillData } from "./SkillData";

/**
 * Forever talents live in the trait system (the Dragonflight talent tables):
 *
 *   SkillLineXTraitTree: class skill line -> TraitTree
 *   TraitNode (position in the tree) -> TraitNodeXTraitNodeEntry -> TraitNodeEntry (MaxRanks)
 *   TraitNodeEntry -> TraitDefinition (SpellID)
 *   TraitDefinitionEffectPoints -> Curve -> CurvePoint: value of a spell effect per rank
 *
 * A multi-rank talent is a single spell whose effects hold the max-rank values; the
 * curve maps rank -> value for the effects that change with rank.
 */

interface DBCTraitTree
{
    TitleText_lang: string,
    ID: number,
    TraitSystemID: number,
    Flags: number,
}

interface DBCTraitNode
{
    ID: number,
    TraitTreeID: number,
    PosX: number,
    PosY: number,
    Type: number,
    Flags: number,
    TraitSubTreeID: number,
}

interface DBCTraitNodeXTraitNodeEntry
{
    ID: number,
    TraitNodeID: number,
    TraitNodeEntryID: number,
    _Index: number,
}

interface DBCTraitNodeEntry
{
    ID: number,
    TraitDefinitionID: number,
    MaxRanks: number,
    NodeEntryType: number,
    TraitSubTreeID: number,
}

interface DBCTraitDefinition
{
    OverrideName_lang: string,
    OverrideSubtext_lang: string,
    OverrideDescription_lang: string,
    ID: number,
    SpellID: number,
    OverrideIcon: number,
    OverridesSpellID: number,
    VisibleSpellID: number,
}

interface DBCTraitDefinitionEffectPoints
{
    ID: number,
    TraitDefinitionID: number,
    EffectIndex: number,
    OperationType: number,
    CurveID: number,
}

interface DBCCurvePoint
{
    Pos_0: number,
    Pos_1: number,
    ID: number,
    CurveID: number,
    OrderIndex: number,
}

interface DBCSkillLineXTraitTree
{
    ID: number,
    SkillLineID: number,
    TraitTreeID: number,
    Variant: number,
}

/** TraitDefinitionEffectPoints.OperationType: the curve value replaces the effect value. */
const OPERATION_SET = 0;

export interface TraitTalent
{
    nodeId: number,
    posX: number,
    posY: number,
    entryId: number,
    maxRanks: number,
    definitionId: number,
    spellId: number,
    overridesSpellId: number,
    visibleSpellId: number,
    /** Effect index -> (rank -> effect value). Effects without an entry keep the spell's value at every rank. */
    rankValues: Map<number, Map<number, number>>,
}

export class TraitData
{
    private readonly trees: Map<number, DBCTraitTree>;
    private readonly nodes: Map<number, DBCTraitNode>;
    private readonly nodeEntries: Map<number, DBCTraitNodeEntry>;
    private readonly definitions: Map<number, DBCTraitDefinition>;
    private readonly nodeToEntryIds = new Map<number, number[]>();
    private readonly definitionEffectPoints = new Map<number, DBCTraitDefinitionEffectPoints[]>();
    private readonly curvePoints = new Map<number, Map<number, number>>();
    private readonly skillLineToTree = new Map<number, number>();
    private readonly skillData: SkillData;

    constructor(skillData: SkillData)
    {
        console.log("Loading trait (talent) data...");

        this.skillData = skillData;
        this.trees = readDBCSVtoMap<DBCTraitTree>(cfg.dataDir + "dbc/TraitTree.csv", "ID");
        this.nodes = readDBCSVtoMap<DBCTraitNode>(cfg.dataDir + "dbc/TraitNode.csv", "ID");
        this.nodeEntries = readDBCSVtoMap<DBCTraitNodeEntry>(cfg.dataDir + "dbc/TraitNodeEntry.csv", "ID");
        this.definitions = readDBCSVtoMap<DBCTraitDefinition>(cfg.dataDir + "dbc/TraitDefinition.csv", "ID");

        const nodeXEntries = Array.from(readDBCSVtoMap<DBCTraitNodeXTraitNodeEntry>(cfg.dataDir + "dbc/TraitNodeXTraitNodeEntry.csv", "ID").values());
        nodeXEntries.sort((a, b) => a._Index - b._Index);
        for (const nxe of nodeXEntries)
        {
            if (!this.nodeToEntryIds.has(nxe.TraitNodeID)) this.nodeToEntryIds.set(nxe.TraitNodeID, []);
            this.nodeToEntryIds.get(nxe.TraitNodeID)!.push(nxe.TraitNodeEntryID);
        }

        for (const ep of readDBCSVtoMap<DBCTraitDefinitionEffectPoints>(cfg.dataDir + "dbc/TraitDefinitionEffectPoints.csv", "ID").values())
        {
            if (!this.definitionEffectPoints.has(ep.TraitDefinitionID)) this.definitionEffectPoints.set(ep.TraitDefinitionID, []);
            this.definitionEffectPoints.get(ep.TraitDefinitionID)!.push(ep);
        }

        for (const cp of readDBCSVtoMap<DBCCurvePoint>(cfg.dataDir + "dbc/CurvePoint.csv", "ID").values())
        {
            if (!this.curvePoints.has(cp.CurveID)) this.curvePoints.set(cp.CurveID, new Map<number, number>());
            this.curvePoints.get(cp.CurveID)!.set(cp.Pos_0, cp.Pos_1);
        }

        for (const slxt of readDBCSVtoMap<DBCSkillLineXTraitTree>(cfg.dataDir + "dbc/SkillLineXTraitTree.csv", "ID").values())
        {
            this.skillLineToTree.set(slxt.SkillLineID, slxt.TraitTreeID);
        }

        console.log(`Trait data: ${this.trees.size} trees, ${this.nodes.size} nodes, ${this.definitions.size} definitions`);
    }

    /**
     * Trait tree of a class, found through its class skill lines.
     */
    getClassTreeId(pclass: PlayerClass)
    {
        const treeIds = new Set<number>();
        for (const lineId of this.skillData.getClassSkillLineIds(pclass))
        {
            const treeId = this.skillLineToTree.get(lineId);
            if (treeId) treeIds.add(treeId);
        }

        if (treeIds.size !== 1)
        {
            throw new Error(`Expected exactly one trait tree for ${pclass}, found ${Array.from(treeIds).join(", ") || "none"}`);
        }

        const treeId = treeIds.values().next().value as number;
        if (!this.trees.has(treeId)) throw new Error(`Trait tree ${treeId} of ${pclass} does not exist!`);
        return treeId;
    }

    /**
     * All talents (node entries) of a tree.
     */
    getTalents(treeId: number)
    {
        const talents: TraitTalent[] = [];

        for (const node of this.nodes.values())
        {
            if (node.TraitTreeID !== treeId) continue;

            for (const entryId of this.nodeToEntryIds.get(node.ID) ?? [])
            {
                const entry = this.nodeEntries.get(entryId);
                if (!entry) throw new Error(`TraitNodeEntry ${entryId} of node ${node.ID} does not exist!`);
                const def = this.definitions.get(entry.TraitDefinitionID);
                if (!def) throw new Error(`TraitDefinition ${entry.TraitDefinitionID} of entry ${entryId} does not exist!`);

                const rankValues = new Map<number, Map<number, number>>();
                for (const ep of this.definitionEffectPoints.get(def.ID) ?? [])
                {
                    if (ep.OperationType !== OPERATION_SET)
                    {
                        throw new Error(`Unhandled TraitDefinitionEffectPoints.OperationType ${ep.OperationType} on definition ${def.ID}`);
                    }
                    const points = this.curvePoints.get(ep.CurveID);
                    if (!points) throw new Error(`Curve ${ep.CurveID} of definition ${def.ID} has no points!`);
                    rankValues.set(ep.EffectIndex, points);
                }

                talents.push({
                    nodeId: node.ID,
                    posX: node.PosX,
                    posY: node.PosY,
                    entryId: entry.ID,
                    maxRanks: entry.MaxRanks,
                    definitionId: def.ID,
                    spellId: def.SpellID,
                    overridesSpellId: def.OverridesSpellID,
                    visibleSpellId: def.VisibleSpellID,
                    rankValues: rankValues,
                });
            }
        }

        return talents;
    }

    /**
     * Every spell ID referenced by the talents of a tree (talent spells, overridden and visible spells).
     */
    getTalentSpellIds(treeId: number)
    {
        const ids = new Set<number>();
        for (const talent of this.getTalents(treeId))
        {
            if (talent.spellId) ids.add(talent.spellId);
            if (talent.overridesSpellId) ids.add(talent.overridesSpellId);
            if (talent.visibleSpellId) ids.add(talent.visibleSpellId);
        }
        return ids;
    }

    /**
     * Value of an effect at a talent rank.
     * @param fallback Value if the effect does not change with rank.
     */
    static getRankValue(talent: TraitTalent, effectIndex: number, rank: number, fallback: number)
    {
        const points = talent.rankValues.get(effectIndex);
        if (!points) return fallback;
        const value = points.get(rank);
        if (typeof value === "undefined")
        {
            throw new Error(`Talent spell ${talent.spellId}: curve for effect ${effectIndex} has no value for rank ${rank}`);
        }
        return value;
    }
}
