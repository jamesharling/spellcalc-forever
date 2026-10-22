---@class AddonEnv
local _addon = select(2, ...);
local L = _addon:GetLocalization();
local SCT = _addon.SCTooltip;
local GetSpellInfo = _addon.api.GetSpellInfo;

---Prayer of Mending
---@param calcedSpell CalcedSpell
---@param effectNum integer
local function PoM(calcedSpell, effectNum)
    local calcedEffect = calcedSpell.effects[effectNum];

    if SpellCalc_settings.ttHit then
        SCT:SingleLine(L.HEAL, ("%dx %d | %d total"):format(calcedSpell.charges, SCT:Round(calcedEffect.avg), SCT:Round(calcedEffect.avg * calcedSpell.charges)));
    end

    if SpellCalc_settings.ttCrit and calcedSpell.critChance > 0 then
        SCT:AppendMinMaxAvgLine(L["Critical"], calcedEffect.minCrit, calcedEffect.maxCrit, calcedEffect.avgCrit, nil, nil, SCT:CritStr(calcedSpell.critChance));
    end

    SCT:AppendCoefData(calcedSpell, calcedEffect);

    if SpellCalc_settings.ttPerSecond then
        SCT:SingleLine(L["HPSC"], ("%.1f"):format(calcedEffect.perSec));
    end

    SCT:AppendEfficiency(calcedSpell, effectNum, true, false);
end

SCT:AddDummyHandler(GetSpellInfo(401859), PoM); -- Prayer of Mending

---Display extended information if T5 2PC is used.
---@param calcedSpell CalcedSpell
---@param effectNum integer
---@param spellId integer
local function GreaterHeal(calcedSpell, effectNum, spellId)
    SCT:ShowEffectTooltip(calcedSpell, 1, true, spellId);

    if _addon:IsBooleanFlagActive(_addon.CONST.BOOLEAN_FLAGS.PRIEST_T5_2PC) then
        local calcedEffect = calcedSpell.effects[1];
        assert(calcedEffect, "Priest T5 bonus set but triggered effect missing!");

        local origPerResource = calcedEffect.perResource;
        local origCastsToOom = calcedSpell.castingData.castsToOom;
        local origTimeToOom = calcedSpell.castingData.timeToOom;
        local origDoneToOom = calcedEffect.doneToOom;

        calcedSpell.effectiveCost = calcedSpell.effectiveCost - 100;
        calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;
        calcedSpell.castingData.castsToOom = _addon:GetEffectiveManaPool() / calcedSpell.effectiveCost;
        if SpellCalc_settings.useRealToOom then
            calcedSpell.castingData.castsToOom = math.floor(calcedSpell.castingData.castsToOom);
        end
        local _, _, _, castTime = GetSpellInfo(2060);
        castTime = (castTime or 0) / 1000;
        calcedSpell.castingData.timeToOom = calcedSpell.castingData.castsToOom * castTime;
        calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;

        SCT:HeaderLine(L["If healed to full:"]);
        SCT:AppendEfficiency(calcedSpell, 1, true, true);

        calcedSpell.effectiveCost = calcedSpell.effectiveCost + 100;
        calcedEffect.perResource = origPerResource;
        calcedSpell.castingData.castsToOom = origCastsToOom;
        calcedSpell.castingData.timeToOom = origTimeToOom;
        calcedEffect.doneToOom = origDoneToOom;
    end
end

SCT:AddDummyHandler(GetSpellInfo(2060), GreaterHeal);
