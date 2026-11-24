---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "MAGE" then
    return;
end

--------------------------------------------------------------------------
-- Player auras
--------------------------------------------------------------------------

-- Mage Armor: "allows 50% of your mana regeneration to continue while casting" on every rank in Forever's data
-- (30% in Classic).
local MageArmorEffect = {
    {
        type = _addon.CONST.EFFECT_TYPE.FSR_SPIRIT_REGEN,
        value = 50,
    }
};
_addon.aurasPlayer[6117] = MageArmorEffect;
_addon.aurasPlayer[22782] = MageArmorEffect;
_addon.aurasPlayer[22783] = MageArmorEffect;

--------------------------------------------------------------------------
-- Scripts
--------------------------------------------------------------------------

local ADDON_EFFECT_FLAGS = _addon.CONST.ADDON_EFFECT_FLAGS;
local FIRE = 4;

-- Fire Power: "Increases the damage done by your Fire spells by 3% per your Fire effects on the target, up to a
-- maximum increase of 12%." The talent stores the percentage (Mage_Fire_Power); the number of Fire effects is
-- assumed in the settings (Target Auras > Your Fire effects on the target) and arrives as the script's value.
_addon.scripting.RegisterScript("Mage_Fire_Effects", function(effects, calcedSpell, calcedEffect, _, spellInfo)
    local perEffect = _addon.scripting.GetValue("Mage_Fire_Power");
    if perEffect > 0 and effects and effects > 0 and bit.band(spellInfo.schoolMask, FIRE) ~= 0
        and bit.band(calcedEffect.effectFlags, ADDON_EFFECT_FLAGS.HEAL + ADDON_EFFECT_FLAGS.ABSORB) == 0 then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + perEffect * effects / 100);
        calcedSpell:AddToBuffList({"Fire Power"});
    end
end);

-- Both scripts run for every spell while the assumed "Frozen target" aura (Settings > Target Auras) is selected.

-- A spell's own bonus against frozen targets: Ice Lance "deals 300% increased damage to Frozen targets".
_addon.scripting.RegisterScript("Mage_Frozen_Damage", function(_, calcedSpell, calcedEffect, _, spellInfo)
    if spellInfo.frozenDamagePct then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + spellInfo.frozenDamagePct / 100);
        calcedSpell:AddToBuffList({"Frozen"});
    end
end);

-- Shatter: critical strike chance against frozen targets. The talent stores its value (Mage_Shatter).
_addon.scripting.RegisterScript("Mage_Frozen_Crit", function(_, calcedSpell)
    local shatter = _addon.scripting.GetValue("Mage_Shatter");
    if shatter > 0 and calcedSpell.critChance > 0 then
        calcedSpell.critChance = calcedSpell.critChance + shatter;
        calcedSpell:AddToBuffList({"Shatter"});
    end
end);
