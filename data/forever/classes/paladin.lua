---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "PALADIN" then
    return;
end

--------------------------------------------------------------------------
-- Player auras
--------------------------------------------------------------------------

-- Divine Favor
_addon.aurasPlayer[20216] = {
    {
        type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
        affectSpell = { 2147483648 + 1073741824 + 2097152 },
        value = 100,
    }
};

--------------------------------------------------------------------------
-- Scripts
--------------------------------------------------------------------------

local scripting = _addon.scripting;
local ADDON_EFFECT_FLAGS = _addon.CONST.ADDON_EFFECT_FLAGS;
local HOLY = 2;

---@param spellInfo SpellInfo
---@param calcedEffect CalcedEffect
local function IsHolyDamage(spellInfo, calcedEffect)
    return bit.band(spellInfo.schoolMask, HOLY) ~= 0
        and bit.band(calcedEffect.effectFlags, ADDON_EFFECT_FLAGS.HEAL + ADDON_EFFECT_FLAGS.ABSORB) == 0;
end

-- Consecrated Ground: "Gives your Holy spells $m1% increased damage against the first $20924s3 enemies that enter
-- your Consecration." The talent effect (generated, on every spell) carries the percentage. Consecration itself is
-- shown for one of those enemies (its tick includes the part only they take), so it always gets the bonus; other
-- Holy damage gets it when the "first enemies in your Consecration" target aura is assumed in the settings
-- (modules/TargetAuras.ts sets Paladin_In_Consecration).
local CONSECRATION = _addon.api.GetSpellInfo(20924);

scripting.RegisterScript("Paladin_Consecrated_Ground", function(pct, calcedSpell, calcedEffect, _, spellInfo, _, spellName)
    if not pct or pct <= 0 or not IsHolyDamage(spellInfo, calcedEffect) then
        return;
    end
    if spellName == CONSECRATION or scripting.GetValue("Paladin_In_Consecration") > 0 then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + pct / 100);
        calcedSpell:AddToBuffList({"Consecrated Ground"});
    end
end);

-- A stunned or incapacitated target, assumed in the settings (offered under Hammer of Justice). Judgement of
-- Command is stored with the half damage it deals otherwise; stunnedDamagePct is what such a target adds.
scripting.RegisterScript("Paladin_Stunned_Damage", function(_, calcedSpell, calcedEffect, _, spellInfo)
    if spellInfo.stunnedDamagePct then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + spellInfo.stunnedDamagePct / 100);
        calcedSpell:AddToBuffList({"Stunned"});
    end
end);

-- Oath of Light on the heal target, assumed in the settings: "increasing the healing of your Holy Light on them by
-- up to $s1, your Flash of Light by up to $s2, and your Holy Shock by up to $s3". The three values grow with the
-- paladin's level (400 / 115 / 230 at level 60); each script's value is the amount per level. Added to the heal's
-- base value, so talents that increase the heal apply to it.
---@param perLevel number|nil
---@param calcedSpell CalcedSpell
---@param calcedEffect CalcedEffect
local function OathOfLightHeal(perLevel, calcedSpell, calcedEffect)
    if perLevel and perLevel > 0 and bit.band(calcedEffect.effectFlags, ADDON_EFFECT_FLAGS.HEAL) ~= 0 then
        calcedEffect.flatMod = calcedEffect.flatMod + perLevel * UnitLevel("player");
        calcedSpell:AddToBuffList({"Oath of Light"});
    end
end

scripting.RegisterScript("Paladin_Oath_Holy_Light", OathOfLightHeal);
scripting.RegisterScript("Paladin_Oath_Flash_of_Light", OathOfLightHeal);
scripting.RegisterScript("Paladin_Oath_Holy_Shock", OathOfLightHeal);

-- Boundless Light: "Increases the critical strike chance of your Holy Shock spell by $s1% when cast on allies not
-- affected by your Oath of Light." Applies unless Oath of Light is assumed on the target.
scripting.RegisterScript("Paladin_Boundless_Light", function(crit, calcedSpell)
    if crit and crit > 0 and calcedSpell.critChance > 0 and scripting.GetValue("Paladin_Oath_of_Light") <= 0 then
        calcedSpell.critChance = calcedSpell.critChance + crit;
        calcedSpell:AddToBuffList({"Boundless Light"});
    end
end);
