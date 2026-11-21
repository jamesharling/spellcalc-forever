import * as fs from "fs";
import { SpellEffect } from "./SpellData";
import { cfg } from "./config";

export enum SealType {
    SOR = "SOR",
    SOC = "SOC",
    SOF = "SOF",
}

interface SealInfo {
    judgeDummyIndex: number,
    spells: number[],
    /** Seal spell ID -> the proc spell that deals its damage, where the seal's data doesn't link it. */
    procs?: { [sealId: string]: number | string },
}

interface SealData {
    seals: {
        [k in SealType]: SealInfo
    }
}

const SEALDATA: SealData = JSON.parse(fs.readFileSync(cfg.dataDir + "sealData.json", "utf8"));

/**
 * Is spell a seal
 * @param id
 * @param specific Filter for specific seal
 */
export function isSeal(id: number, specific?: SealType) {
    for (const sealType in SEALDATA.seals)
    {
        if (specific && specific != sealType) continue;
        if (SEALDATA.seals[sealType as SealType].spells.indexOf(id) != -1) return <SealType>sealType;
    }
    return false;
}

/**
 * The proc spell listed for a seal in sealData.json, if any.
 * @param id Seal spell ID
 */
export function getListedSealProc(id: number): number | undefined
{
    for (const sealType in SEALDATA.seals)
    {
        const proc = SEALDATA.seals[sealType as SealType].procs?.[id];
        if (typeof proc === "number") return proc;
    }
    return undefined;
}

/**
 * Get array of seal spells for seal type or all seals.
 * @param type
 * @returns
 */
export function getSeals(type?: SealType)
{
    if (type)
    {
        if (!SEALDATA.seals[type]) throw new Error("No seals for this type!");
        return SEALDATA.seals[type].spells;
    }

    const seals: number[] = [];
    for (const sealType in SEALDATA.seals)
    {
        const thisSeals = SEALDATA.seals[sealType as SealType].spells;
        seals.push(...thisSeals);
    }
    return seals;
}

/**
 * Is effect a judgement dummy
 * @param eff
 * @param seal
 */
export function isJudgeDummy(eff: SpellEffect, seal?: SealType) {
    for (const sealType in SEALDATA.seals)
    {
        if (seal && seal != sealType) continue;
        if (isSeal(eff.SpellID, <SealType>sealType) && eff.EffectIndex == SEALDATA.seals[sealType as SealType].judgeDummyIndex)
        {
            return <SealType>sealType;
        }
    }

    return false;
}
