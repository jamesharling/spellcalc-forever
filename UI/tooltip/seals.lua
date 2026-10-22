---@class AddonEnv
local _addon = select(2, ...);
local L = _addon:GetLocalization();
local SCT = _addon.SCTooltip;
local GetSpellInfo = _addon.api.GetSpellInfo;

---@param calcedSpell CalcedSpell
---@param effectNum number
local function SoR(calcedSpell, effectNum)
    local calcedEffect = calcedSpell.effects[effectNum];

    if SpellCalc_settings.ttHit then
        SCT:SingleLine(L["Damage"], ("%.1f"):format(calcedEffect.avg));
    end

    SCT:AppendCoefData(calcedSpell, calcedEffect, nil, 0);

    if SpellCalc_settings.ttResist and calcedSpell.avgResist > 0 then
        local effRes = math.max(0, calcedSpell.resistance - calcedSpell.resistancePen) + calcedSpell.resistanceFromLevel;
        local strUsed = calcedSpell.resistanceFromLevel > 0 and L["%.1f%% (Res: %d (%d from level))"] or L["%.1f%% (Res: %d)"];
        SCT:SingleLine(L["Avg. resisted"], strUsed:format(calcedSpell.avgResist * 100, effRes, calcedSpell.resistanceFromLevel));
    end
end

---@param calcedSpell CalcedSpell
---@param effectNum number
local function SoC(calcedSpell, effectNum)
    local calcedEffect = calcedSpell.effects[effectNum];

    if SpellCalc_settings.ttHit then
        SCT:AppendMinMaxAvgLine(L["Damage"], calcedEffect.min, calcedEffect.max, calcedEffect.avg);
    end

    if SpellCalc_settings.ttCrit then
        SCT:AppendMinMaxAvgLine(L["Critical"], calcedEffect.minCrit, calcedEffect.maxCrit, calcedEffect.avgCrit, nil,
            nil, SCT:CritStr(calcedSpell.critChance));
    end

    if SpellCalc_settings.ttResist and calcedSpell.avgResist > 0 then
        local effRes = math.max(0, calcedSpell.resistance - calcedSpell.resistancePen) + calcedSpell.resistanceFromLevel;
        local strUsed = calcedSpell.resistanceFromLevel > 0 and L["%.1f%% (Res: %d (%d from level))"] or L["%.1f%% (Res: %d)"];
        SCT:SingleLine(L["Avg. resisted"], strUsed:format(calcedSpell.avgResist * 100, effRes, calcedSpell.resistanceFromLevel));
    end
end

SCT:AddDummyHandler(GetSpellInfo(20375), SoC);
SCT:AddDummyHandler(GetSpellInfo(21084), SoR);
