---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "WARLOCK" then
    return;
end

--------------------------------------------------------------------------
-- Player auras
--------------------------------------------------------------------------

-- Soul Link (25228) and the Demonic Sacrifice effects come from the generated player aura data.

local scripting = _addon.scripting;
local EFFECT_TYPE = _addon.CONST.EFFECT_TYPE;
local ADDON_EFFECT_FLAGS = _addon.CONST.ADDON_EFFECT_FLAGS;
local ALL_SPELLS = { 4294967295, 4294967295, 4294967295, 4294967295 };
local FIRE, SHADOW = 4, 32;

---@param calcedEffect CalcedEffect
local function IsDamage(calcedEffect)
    return bit.band(calcedEffect.effectFlags, ADDON_EFFECT_FLAGS.HEAL + ADDON_EFFECT_FLAGS.ABSORB) == 0;
end

---A buff that has one spell for every rank of its talent, so the aura data only knows a single value: a damage
---bonus to a school whose percentage is the rank's own value, which the talent stores (modules/talentDummies.ts).
---Read when a spell is calculated, so it follows the talents. Without a stored value the aura data's value applies.
---@param auraId integer
---@param buffName string Name for the list of considered buffs.
---@param talentKey string Script value the talent stores.
---@param schoolMask integer
---@param fallback number
local function RankedSchoolDamage(auraId, buffName, talentKey, schoolMask, fallback)
    local key = "Warlock_Aura_" .. auraId;
    _addon.aurasPlayer[auraId] = {
        {
            type = EFFECT_TYPE.SCRIPT_SPELLMOD_DONE_PCT,
            affectSpell = ALL_SPELLS,
            scriptKey = key,
            value = fallback,
        }
    };
    scripting.RegisterScript(key, function(fallbackPct, calcedSpell, calcedEffect, _, spellInfo)
        if bit.band(spellInfo.schoolMask, schoolMask) == 0 or not IsDamage(calcedEffect) then
            return;
        end
        local pct = scripting.GetValue(talentKey);
        if pct <= 0 then
            pct = fallbackPct or 0;
        end
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + pct / 100);
        calcedSpell:AddToBuffList({buffName});
    end);
end

-- Master Demonologist: "Imp - Increases Fire damage done by $m1%. ... Succubus/Incubus - Increases Shadow damage
-- done by $m3%." 2% per rank; the aura spells carry the value of 5/5.
RankedSchoolDamage(23759, "Master Demonologist", "Warlock_Master_Demonologist", FIRE, 10);
RankedSchoolDamage(23761, "Master Demonologist", "Warlock_Master_Demonologist", SHADOW, 10);

-- Shadow and Flame: Conflagrate's buff "Shadow" and Shadowburn's buff "Flame", 4% per rank; the aura spells
-- carry 10%.
RankedSchoolDamage(1293816, "Shadow and Flame", "Warlock_Shadow_and_Flame", SHADOW, 10);
RankedSchoolDamage(426311, "Shadow and Flame", "Warlock_Shadow_and_Flame", FIRE, 10);

-- Soul Harvest: "allows $s2% of Mana regeneration to continue while casting", 50% per rank. The buff only
-- appears after a kill, long after the talents were read.
---@type AuraEffectBase
local soulHarvestRegen = {
    type = EFFECT_TYPE.FSR_SPIRIT_REGEN,
};
_addon.aurasPlayer[1242853] = {
    {
        type = EFFECT_TYPE.SCRIPT_AURASCRIPT,
        value = 100,
        scriptKey = "Warlock_Soul_Harvest_Buff",
    }
};
scripting.RegisterAuraScript("Warlock_Soul_Harvest_Buff", function(apply, auraId, fromPlayer, _, cacheValue, value)
    local name = "Soul Harvest";
    if apply then
        local pct = scripting.GetValue("Warlock_Soul_Harvest");
        if pct <= 0 then
            pct = value;
        end
        _addon:ApplyAuraEffect(name, soulHarvestRegen, pct, auraId, fromPlayer);
        return pct;
    else
        assert(cacheValue, "Soul Harvest aura removed while cacheValue is nil!");
        _addon:RemoveAuraEffect(name, soulHarvestRegen, cacheValue, auraId, fromPlayer);
    end
end);

-- Amplify Curse: "Increases the effect of your next Curse of Weakness or Bane of Agony by $s1%". The aura's own
-- modifier only names Curse of Weakness; Bane of Agony (class mask bit 1024) is added here.
_addon.aurasPlayer[18288] = {
    {
        type = EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
        affectSpell = { 1024, 0, 0, 0 },
        value = 50,
    }
};

--------------------------------------------------------------------------
-- Scripts
--------------------------------------------------------------------------

-- The talents below are generated with the percentage as the script's value (modules/talentDummies.ts). The
-- states of the target they depend on are assumed in Settings > Target Auras (modules/TargetAuras.ts).

-- The warlock's Immolate on the target: "an additional $m2% damage if the target is afflicted by Immolate"
-- (Incinerate, immolateDamagePct in its spell data).
scripting.RegisterScript("Warlock_Immolate_Target", function(_, calcedSpell, calcedEffect, _, spellInfo)
    if spellInfo.immolateDamagePct then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + spellInfo.immolateDamagePct / 100);
        calcedSpell:AddToBuffList({"Immolate"});
    end
end);

-- Improved Shadow Bolt's debuff: "increase Shadow damage taken by the target from your attacks by $m1%", the
-- value of the talent's rank. Nothing without the talent: the debuff only counts for the warlock who applied it.
scripting.RegisterScript("Warlock_Shadow_Vulnerability", function(_, calcedSpell, calcedEffect, _, spellInfo)
    local pct = scripting.GetValue("Warlock_Improved_Shadow_Bolt");
    if pct > 0 and bit.band(spellInfo.schoolMask, SHADOW) ~= 0 and IsDamage(calcedEffect) then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + pct / 100);
        calcedSpell:AddToBuffList({"Improved Shadow Bolt"});
    end
end);

-- Decimation: "When you cast Shadow Bolt or Searing Pain on an enemy below $m3% health, they deal $m4% increased
-- damage".
scripting.RegisterScript("Warlock_Decimation", function(pct, calcedSpell, calcedEffect)
    if pct and pct > 0 and scripting.GetValue("Warlock_Target_Low_Health") > 0 and IsDamage(calcedEffect) then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + pct / 100);
        calcedSpell:AddToBuffList({"Decimation"});
    end
end);

-- Soul Siphon: "Increases the damage done or health drained by your Drain Life, Drain Soul, and Wrack spells by
-- $s1% per each of your Corruption, Siphon Life, and Bane of Agony effects active on the target".
scripting.RegisterScript("Warlock_Soul_Siphon", function(pct, calcedSpell, calcedEffect)
    local effects = scripting.GetValue("Warlock_Dots_On_Target");
    if pct and pct > 0 and effects > 0 and IsDamage(calcedEffect) then
        calcedEffect.modBonus = calcedEffect.modBonus * (1 + pct * effects / 100);
        calcedSpell:AddToBuffList({"Soul Siphon"});
    end
end);
