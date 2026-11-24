---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "PRIEST" then
    return;
end

--------------------------------------------------------------------------
-- Player auras
--------------------------------------------------------------------------

-- Spirit Tap: "Spirit increased by $s1% and allows $s2% of Mana regeneration while casting." The Spirit is in
-- the stats the client reports; the regeneration while casting is not.
_addon.aurasPlayer[15271] = {
    {
        type = _addon.CONST.EFFECT_TYPE.FSR_SPIRIT_REGEN,
        value = 50,
    }
};

--------------------------------------------------------------------------
-- Scripts
--------------------------------------------------------------------------

-- (Season of Discovery rune scripts were removed for the Forever port.)

local scripting = _addon.scripting;
local ADDON_EFFECT_FLAGS = _addon.CONST.ADDON_EFFECT_FLAGS;

-- The talents below are generated with the percentage as the script's value (modules/talentDummies.ts). The
-- states of the target they depend on are assumed in Settings > Target Auras and arrive as set values
-- (modules/TargetAuras.ts).

-- Renewed Hope: "Your heals from Flash Heal, Lesser Heal, Heal, Greater Heal, and Penance gain $m1% increased
-- critical strike chance when cast on targets with Weakened Soul".
scripting.RegisterScript("Priest_Renewed_Hope", function(crit, calcedSpell)
    if crit and crit > 0 and calcedSpell.critChance > 0 and scripting.GetValue("Priest_Weakened_Soul") > 0
        and bit.band(calcedSpell.effects[1].effectFlags, ADDON_EFFECT_FLAGS.HEAL) ~= 0 then
        calcedSpell.critChance = calcedSpell.critChance + crit;
        calcedSpell:AddToBuffList({"Renewed Hope"});
    end
end);

-- Power in Light: "Your Smite and Penance spells deal $m1% increased damage to targets afflicted with your Holy
-- Fire or Shadow Word: Pain."
scripting.RegisterScript("Priest_Power_in_Light", function(pct, calcedSpell, calcedEffect)
    if pct and pct > 0 and scripting.GetValue("Priest_Dot_On_Target") > 0
        and bit.band(calcedEffect.effectFlags, ADDON_EFFECT_FLAGS.HEAL + ADDON_EFFECT_FLAGS.ABSORB) == 0 then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + pct / 100);
        calcedSpell:AddToBuffList({"Power in Light"});
    end
end);

-- Early Demise: "Increases Shadow Word: Death's critical strike chance on targets at or below $s2% health by $s1%."
scripting.RegisterScript("Priest_Early_Demise", function(crit, calcedSpell)
    if crit and crit > 0 and calcedSpell.critChance > 0 and scripting.GetValue("Priest_Target_Low_Health") > 0 then
        calcedSpell.critChance = calcedSpell.critChance + crit;
        calcedSpell:AddToBuffList({"Early Demise"});
    end
end);

-- Improved Mind Flay: "Each instance of damage of Mind Flay deals $s1% more damage than its previous instance of
-- damage." The tick the addon shows becomes the average of the channel's ticks, so the total is right.
scripting.RegisterScript("Priest_Improved_Mind_Flay", function(pct, calcedSpell, calcedEffect, _, spellInfo)
    local ticks = calcedEffect.ticks;
    if not pct or pct <= 0 or not ticks then
        return;
    end
    if spellInfo.extraTickAtApplication then
        ticks = ticks + 1;
    end
    if ticks > 1 then
        local sum, tick = 0, 1;
        for _ = 1, ticks do
            sum = sum + tick;
            tick = tick * (1 + pct / 100);
        end
        calcedEffect.modBonus = calcedEffect.modBonus * sum / ticks;
        calcedSpell:AddToBuffList({"Improved Mind Flay"});
    end
end);
