import * as fs from "fs";
import { SpellEffect } from "./SpellData";
import { cfg } from "./config";

export enum SealType {
    SOR = "SOR",
    SOC = "SOC",
}

interface SealInfo {
    judgeDummyIndex: number,
    spells: number[]
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
