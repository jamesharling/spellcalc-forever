---@class AddonEnv
local _addon = select(2, ...);
local GetSpellInfo = _addon.api.GetSpellInfo;
local effHandler = _addon.effectHandler;
local stats = _addon.stats;
local EFFECT_TYPES = _addon.CONST.SPELL_EFFECT_TYPES;
local AURA_TYPES = _addon.CONST.SPELL_AURA_TYPES;

---The part of an effect's base value that comes from the player's level (up to the spell's max level).
---@param spellInfo SpellInfo
---@param effectData SpellEffectData
---@return number
local function LevelBonus(spellInfo, effectData)
    if not effectData.valuePerLevel or effectData.valuePerLevel <= 0 then
        return 0;
    end
    local refLevel = UnitLevel("player");
    if spellInfo.maxLevel and spellInfo.maxLevel > 0 and spellInfo.maxLevel < refLevel then
        refLevel = spellInfo.maxLevel;
    end
    return (refLevel - spellInfo.spellLevel) * effectData.valuePerLevel;
end

---Fill effect base values.
---Fills min, max, avg and avgCombined.
---@param calcedSpell CalcedSpell
---@param calcedEffect CalcedEffect
---@param spellId integer
---@param spellInfo SpellInfo
---@param spellName string
---@param effectData SpellEffectData
---@param flat number Flat value added before modifier.
---@param mod number|nil Modifier for base values.
---@param add number|nil Additional value to add after modifier.
local function FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, flat, mod, add)
    mod = mod or 1;
    add = add or 0;

    local baseLow = effectData.valueBase + flat + LevelBonus(spellInfo, effectData);

    if spellInfo.useScalingFormula then
        local min, max = _addon.ApplyScalingFormula(spellInfo.useScalingFormula, baseLow, baseLow + effectData.valueRange);
        calcedEffect.min = min * mod + add;
        calcedEffect.max = max * mod + add;
    else
        calcedEffect.min = baseLow * mod + add;
        calcedEffect.max = (baseLow + effectData.valueRange) * mod + add;
    end

    calcedEffect.avg = (calcedEffect.min + calcedEffect.max) * 0.5;
    calcedEffect.avgCombined = calcedEffect.avg;

    _addon.scripting.DoSpell(_addon.CONST.EFFECT_TYPE.SCRIPT_SPELLMOD_EFFECT_BASEVALUES, calcedSpell, calcedEffect, spellId, spellInfo, spellName);
end

---Fill crit values and avgCombined. Also handle on crit effects.
---@param calcedSpell CalcedSpell
---@param calcedEffect CalcedEffect
---@param spellId integer
local function FillCritValues(calcedSpell, calcedEffect, spellId)
    calcedEffect.minCrit = calcedEffect.min * calcedSpell.critMult;
    calcedEffect.maxCrit = calcedEffect.max * calcedSpell.critMult;
    calcedEffect.avgCrit = calcedEffect.avg * calcedSpell.critMult;
    calcedEffect.avgCombined = calcedEffect.avg + (calcedEffect.avgCrit - calcedEffect.avg) * calcedSpell.critChance/100;

    if stats.spellModExtraOnCrit[spellId] and stats.spellModExtraOnCrit[spellId].val ~= 0 then
        calcedEffect.critExtraAvg = calcedEffect.avgCrit * stats.spellModExtraOnCrit[spellId].val / 100;
        calcedEffect.avgCombined = calcedEffect.avgCombined + calcedEffect.critExtraAvg * calcedSpell.critChance/100;
        calcedSpell:AddToBuffList(stats.spellModExtraOnCrit[spellId].buffs);
    else
        calcedEffect.critExtraAvg = nil;
    end
end

---Apply mitigation, i.e. hit chance, resistance/armor.
---Fills avgAfterMitigation.
---@param spellName string
---@param calcedSpell CalcedSpell
---@param calcedEffect CalcedEffect
---@param mustBeMelee boolean|nil
---@param isBleed boolean|nil
---@param totalOverride number|nil Use this instead of avgCombined to calculate avgAfterMitigation.
local function Mitigate(spellName, calcedSpell, calcedEffect, mustBeMelee, isBleed, totalOverride)
    local mmit = calcedSpell.meleeMitigation;
    local usedHit;
    local combined = totalOverride and totalOverride or calcedEffect.avgCombined;

    if mmit or mustBeMelee then
        assert(mmit, "meleeMitigation table missing for melee spell "..spellName);
        usedHit = math.max(calcedSpell.hitChance - mmit.dodge - mmit.parry, 0) / 100;
    else
        if bit.band(calcedEffect.effectFlags, _addon.CONST.ADDON_EFFECT_FLAGS.CHANNEL) > 0 then
            -- This is the relative damage done per default timeframe, i.e. cast or channel time, with failed GCDs.
            -- duration / (duration + wasted GCD time)
            usedHit = calcedSpell.effCastTime / ((100 / calcedSpell.hitChance - 1) * calcedSpell.gcd + calcedSpell.effCastTime);
        else
            usedHit = calcedSpell.hitChance / 100;
        end
    end

    calcedEffect.avgAfterMitigation = combined * usedHit;

    if calcedSpell.hitChanceBinaryLoss == nil and not isBleed then
        calcedEffect.avgAfterMitigation = calcedEffect.avgAfterMitigation * (1 - calcedSpell.avgResist);
    end
end

---Get normalized weapon damage based on equipped weapon and given AP value.
---@param slot string mainhand, offhand or ranged
---@param ap number The attack power used.
---@param weaponCoef number
---@return number low
---@return number high
local function GetNormalizedWeaponDamage(slot, ap, weaponCoef)
    local CONST = _addon.CONST;
    local low = stats.weaponBaseDamage[slot].min;
    local high = stats.weaponBaseDamage[slot].max;
    local weaponBit = _addon:GetWeaponTypeMask(slot);
    local dpsFromAP = ap / 14;
    local dmgFromAP;

    if weaponBit then
        if bit.band(weaponBit, CONST.WEAPON_TYPES_MASK.DAGGER) > 0 then
            dmgFromAP = 1.7 * dpsFromAP;
        elseif bit.band(weaponBit, CONST.WEAPON_TYPES_MASK.ONE_HAND) > 0 then
            dmgFromAP = 2.4 * dpsFromAP;
        elseif bit.band(weaponBit, CONST.WEAPON_TYPES_MASK.TWO_HAND) > 0 then
            dmgFromAP = 3.3 * dpsFromAP;
        elseif bit.band(weaponBit, CONST.WEAPON_TYPES_MASK.RANGED) > 0 then
            dmgFromAP = 2.8 * dpsFromAP;
        end
    end

    if not dmgFromAP then
        dmgFromAP = 2 * dpsFromAP; -- Unarmed fallback.
    end

    low = (low + dmgFromAP) * weaponCoef;
    high = (high + dmgFromAP) * weaponCoef;

    return low, high;
end

local HealEffect;

----------------------------------------------------------------------------------------------------------------------------------------
-- Templates
----------------------------------------------------------------------------------------------------------------------------------------

---@alias EffectHandler fun(auraType: SpellAuraType|nil, calcedSpell: CalcedSpell, effNum: integer, spellInfo: SpellInfo, spellName: string, spellId: integer):nil

--- BASE TEMPLATE
---@class sdgsdgdsfhsfdh
---@param auraType SpellAuraType|nil
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function EFFECT_TEMPLATE(auraType, calcedSpell, effNum, spellInfo, spellName, spellId)
    -- Example function definition
end

---@alias AuraEffectHandler fun(calcedSpell: CalcedSpell, effNum: integer, spellInfo: SpellInfo, spellName: string, spellId: integer):nil

--- BASE AURA TEMPLATE
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function AURA_TEMPLATE(calcedSpell, effNum, spellInfo, spellName, spellId)
    -- Example function definition
end

----------------------------------------------------------------------------------------------------------------------------------------
-- Dummy Aura Handler
----------------------------------------------------------------------------------------------------------------------------------------

---@type table<string, AuraEffectHandler>
local dummyAuraHandlers = {};

---Multipliers from spell modifiers on the proc spell that deals a seal's damage. Improved Seals, for one,
---modifies the Seal of Righteousness and Seal of Fury procs, not the seal auras the addon calculates.
---@param calcedSpell CalcedSpell
---@param procId integer|nil
---@return number baseMult For the base value only
---@return number damageMult For the base value and the spell power bonus
local function SealProcMods(calcedSpell, procId)
    local baseMult, damageMult = 1, 1;
    if procId then
        local effectMod = stats.spellModPctEffect[procId];
        if effectMod and effectMod.val ~= 0 then
            baseMult = math.max(0, 1 + effectMod.val / 100);
            calcedSpell:AddToBuffList(effectMod.buffs);
        end
        local damageMod = stats.spellModPctDamageHealing[procId];
        if damageMod and damageMod.val ~= 0 then
            damageMult = math.max(0, 1 + damageMod.val / 100);
            calcedSpell:AddToBuffList(damageMod.buffs);
        end
    end
    return baseMult, damageMult;
end

---A seal's damage per melee swing: one value, no range.
---@param calcedEffect CalcedEffect
---@param damage number
local function SetPerSwingDamage(calcedEffect, damage)
    calcedEffect.min = damage;
    calcedEffect.max = damage;
    calcedEffect.avg = damage;
    calcedEffect.avgCombined = damage;
end

-- Seal of Righteousness per swing. Forever's tooltip gives "(s/87 + 0.0765 * SP) to (s/25 + 0.12 * SP)", times
-- Improved Seals (SpellDescriptionVariables 1023: $1h = 0.0765 * holy SP, $2h = 0.12 * holy SP), where s is the
-- rank's base points. The base part is the Classic Era formula (WoWSims): s / 100 * weapon speed * 0.85 with a
-- one-hander, * 1.2 with a two-hander, using the weapon's own speed (haste doesn't change it); s/87 is a 1.35 speed
-- one-hander, s/25 a 3.33 two-hander. The spell power part depends only on the weapon type.
local SOR_ONE_HAND = { speedMult = 0.85, spCoef = 0.0765 };
local SOR_TWO_HAND = { speedMult = 1.2, spCoef = 0.12 };

---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
local function SealOfRighteousness(calcedSpell, effNum, spellInfo, spellName)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];
    local hand = _addon:IsTwoHandEquipped() and SOR_TWO_HAND or SOR_ONE_HAND;
    local baseMult, damageMult = SealProcMods(calcedSpell, effectData.procSpell);

    local points = effectData.valueBase + LevelBonus(spellInfo, effectData);
    local base = points / 100 * hand.speedMult * stats.baseAttackSpeed.mainhand;

    calcedEffect.effectiveSpCoef = hand.spCoef * calcedEffect.modBonus * damageMult;
    calcedEffect.effectiveApCoef = 0;
    calcedEffect.effectivePower = calcedEffect.spellPower * calcedEffect.effectiveSpCoef;

    SetPerSwingDamage(calcedEffect,
        (base + calcedEffect.flatMod) * calcedEffect.modBase * baseMult * damageMult + calcedEffect.effectivePower);
end

-- Seal of Fury per swing: the same Holy damage on every swing whatever the weapon, the proc spell's base value
-- plus 10% of spell power (the generator puts the proc's values on the seal).
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
local function SealOfFury(calcedSpell, effNum, spellInfo, spellName)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];
    local baseMult, damageMult = SealProcMods(calcedSpell, effectData.procSpell);

    calcedEffect.effectiveSpCoef = calcedEffect.effectiveSpCoef * damageMult;
    calcedEffect.effectivePower = calcedEffect.effectivePower * damageMult;

    local base = effectData.valueBase + LevelBonus(spellInfo, effectData);
    SetPerSwingDamage(calcedEffect,
        (base + calcedEffect.flatMod) * calcedEffect.modBase * baseMult * damageMult + calcedEffect.effectivePower);
end

---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
local function SealOfCommand(calcedSpell, effNum, spellInfo, spellName)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    -- 70% of a normal weapon hit, plus the proc's spell power bonus (29%, in effectivePower)
    local weaponCoef = effectData.weaponCoef * calcedEffect.modBase;
    calcedEffect.min = weaponCoef * stats.attackDmg.mainhand.min + calcedEffect.effectivePower;
    calcedEffect.max = weaponCoef * stats.attackDmg.mainhand.max + calcedEffect.effectivePower;
    calcedEffect.avg = 0.5 * (calcedEffect.min + calcedEffect.max);
    calcedEffect.minCrit = calcedEffect.min * calcedSpell.critMult;
    calcedEffect.maxCrit = calcedEffect.max * calcedSpell.critMult;
    calcedEffect.avgCrit = (calcedEffect.minCrit + calcedEffect.maxCrit) / 2;
end

---Dummy handler for Prayer of Mending
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function PrayerOfMending(calcedSpell, effNum, spellInfo, spellName, spellId)
    -- Do normal heal effect
    HealEffect(nil, calcedSpell, effNum, spellInfo, spellName, spellId);
    -- Multiply by charge count
    local calcedEffect = calcedSpell.effects[effNum];
    calcedEffect.avgAfterMitigation = calcedEffect.avgAfterMitigation * calcedSpell.charges;
    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;
end

---Register a dummy aura handler by spell ID. Spells missing on this client are skipped.
---@param spellId integer
---@param handler function
local function RegisterDummyAuraHandler(spellId, handler)
    local name = GetSpellInfo(spellId);
    if name then
        dummyAuraHandlers[name] = handler;
    end
end

RegisterDummyAuraHandler(20154, SealOfRighteousness);
RegisterDummyAuraHandler(20375, SealOfCommand);
RegisterDummyAuraHandler(1311649, SealOfFury);
RegisterDummyAuraHandler(401859, PrayerOfMending);
-- Innervate and Evocation are mana regen percent auras on Forever (PowerRegenPercent below), Seal of
-- Wisdom isn't calculated, and Earth Shield, Starfall, Thunderstorm, the Wrath Conflagrate and Seal of
-- Vengeance/Corruption don't exist on Forever, so they have no dummy handlers.


----------------------------------------------------------------------------------------------------------------------------------------
-- Aura Handler
----------------------------------------------------------------------------------------------------------------------------------------

---@type table<SpellAuraType, AuraEffectHandler>
local auraHandler = {};

--- Handler for periodic damage auras.
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function PeriodicDamage(calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, calcedEffect.flatMod, calcedEffect.modBase, calcedEffect.effectivePower);

    if stats.spellModAllowDotCrit[spellId] and stats.spellModAllowDotCrit[spellId].val > 0 then
        FillCritValues(calcedSpell, calcedEffect, spellId);
    else
        calcedEffect.minCrit = 0;
        calcedEffect.avgCombined = calcedEffect.avg;
    end

    if spellInfo.extraTickAtApplication then
        calcedEffect.ticks = calcedEffect.ticks + 1;
    end

    local total = calcedEffect.avgCombined * calcedEffect.ticks;

    if stats.spellModExtraOnHit[spellId] and stats.spellModExtraOnHit[spellId].val ~= 0 then
        if not calcedEffect.hitExtra then calcedEffect.hitExtra = {} end
        calcedEffect.hitExtra.avgHit = calcedEffect.min * calcedEffect.ticks * stats.spellModExtraOnHit[spellId].val / 100;
        calcedEffect.hitExtra.avgCrit = calcedEffect.hitExtra.avgHit * 1.5;
        calcedEffect.hitExtra.avg = calcedEffect.hitExtra.avgHit + (calcedEffect.hitExtra.avgCrit - calcedEffect.hitExtra.avgHit) * calcedSpell.critChance/100;
        calcedSpell:AddToBuffList(stats.spellModExtraOnHit[spellId].buffs);
        total = total + calcedEffect.hitExtra.avg;
    else
        calcedEffect.hitExtra = nil;
    end

    Mitigate(spellName, calcedSpell, calcedEffect, false, effectData.mechanic == _addon.CONST.SPELL_MECHANIC.BLEED, total);

    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.perSecDurOrCD = total / calcedSpell.duration;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;
end

---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function PeriodicHeal(calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, calcedEffect.flatMod, calcedEffect.modBase, calcedEffect.effectivePower);

    if spellInfo.extraTickAtApplication then
        calcedEffect.ticks = calcedEffect.ticks + 1;
    end

    calcedEffect.avgAfterMitigation = calcedEffect.avgCombined * calcedEffect.ticks;

    if stats.spellModExtraOnHit[spellId] and stats.spellModExtraOnHit[spellId].val ~= 0 then
        local onHit = calcedEffect.min * calcedEffect.ticks * stats.spellModExtraOnHit[spellId].val / 100;
        local onHitCrit = onHit * calcedSpell.critMult;
        local onHitAvg = onHit + (onHitCrit - onHit) * calcedSpell.critChance/100;
        calcedSpell:AddToBuffList(stats.spellModExtraOnHit[spellId].buffs);
        calcedEffect.avgAfterMitigation = calcedEffect.avgAfterMitigation + onHitAvg;
    end

    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.perSecDurOrCD = calcedEffect.avgAfterMitigation / calcedSpell.duration;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;
end

--- Handler for damage shield like effects
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function DamageShield(calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, calcedEffect.flatMod, calcedEffect.modBase, calcedEffect.effectivePower);

    local total = (calcedSpell.charges and calcedSpell.charges > 0) and calcedSpell.charges * calcedEffect.avgCombined or calcedEffect.avgCombined;

    Mitigate(spellName, calcedSpell, calcedEffect, false, false, total);

    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;
end

--- Handler for absorbs
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function AbsorbAura(calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, calcedEffect.flatMod, calcedEffect.modBase, calcedEffect.effectivePower);

    if stats.spellModExtraOnHit[spellId] and stats.spellModExtraOnHit[spellId].val ~= 0 then
        if not calcedEffect.hitExtra then calcedEffect.hitExtra = {} end
        calcedEffect.hitExtra.avgHit = calcedEffect.min * stats.spellModExtraOnHit[spellId].val / 100;
        calcedEffect.hitExtra.avg = calcedEffect.hitExtra.avgHit;
        calcedSpell:AddToBuffList(stats.spellModExtraOnHit[spellId].buffs);
        calcedEffect.avgCombined = calcedEffect.avgCombined + calcedEffect.hitExtra.avg;
    else
        calcedEffect.hitExtra = nil;
    end

    calcedEffect.avgAfterMitigation = calcedEffect.avgCombined;

    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;
end

--- Handler for Mana Shield
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function ManaShield(calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, calcedEffect.flatMod, calcedEffect.modBase, calcedEffect.effectivePower);

    calcedEffect.avgAfterMitigation = calcedEffect.avgCombined;

    -- Mana drained per point of damage absorbed ("Drains $e mana per damage absorbed"), less Arcane Shielding.
    local drain = effectData.manaPerDamage or 2;
    local reduction = _addon.scripting.GetValue("Mage_Arcane_Shielding");
    if reduction > 0 then
        drain = drain * (1 - reduction / 100);
        calcedSpell:AddToBuffList({"Arcane Shielding"});
    end
    calcedSpell.effectiveCost = calcedSpell.effectiveCost + drain * calcedEffect.avgAfterMitigation;
    calcedSpell.castingData.castsToOom = _addon:GetEffectiveManaPool() / calcedSpell.effectiveCost;

    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;
end

--- Handler for things like Arcane Missiles or Searing Totem.
--- That is, periodic spells with ticks that behave much like a direct damage effect.
--- Can also be used for healing spells (e.g. Tranquility)
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function PeriodicTriggerSpell(calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local triggeredSpellData = calcedEffect.spellData;
    assert(triggeredSpellData, "triggeredSpellData for ptsa in spell "..spellName.." missing!");

    if spellInfo.extraTickAtApplication then
        calcedEffect.ticks = calcedEffect.ticks + 1;
    end

    calcedEffect.min = triggeredSpellData.effects[1].min;
    calcedEffect.max = triggeredSpellData.effects[1].max;
    calcedEffect.avg = triggeredSpellData.effects[1].avg;
    calcedEffect.minCrit = triggeredSpellData.effects[1].minCrit;
    calcedEffect.maxCrit = triggeredSpellData.effects[1].maxCrit;
    calcedEffect.avgCrit = triggeredSpellData.effects[1].avgCrit;
    calcedEffect.avgCombined = triggeredSpellData.effects[1].avgCombined;
    calcedEffect.avgAfterMitigation = triggeredSpellData.effects[1].avgAfterMitigation * calcedEffect.ticks;
    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.perSecDurOrCD = (calcedEffect.avgCombined * calcedEffect.ticks) / calcedSpell.duration;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;
end

--- Handler for increased mana regen.
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
local function PowerRegenPercent(calcedSpell, effNum, spellInfo)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    -- Everything happens in 2s intervals in classic
    local ticks = math.floor(calcedSpell.duration / 2);
    local regenMult = 1 + effectData.valueBase / 100;
    local defaultRegenPerTick = stats.manaRegBase * 2;
    local defaultCastingRegenPerTick = stats.manaRegCasting * 2;
    local perTickRegenExtra = (defaultRegenPerTick * regenMult) - defaultCastingRegenPerTick;

    calcedEffect.min = perTickRegenExtra;
    calcedEffect.max = calcedEffect.min;
    calcedEffect.avg = calcedEffect.min;
    calcedEffect.avgCombined = calcedEffect.min;
    calcedEffect.ticks = ticks;
    calcedEffect.tickPeriod = 2;
    calcedEffect.avgAfterMitigation = perTickRegenExtra * ticks;
end

--- Fill a mana restore effect: base values without spell power, damage modifiers or crit, and no per-second
--- value (the mana restore tooltip would show it as a proc chance). Per tick for periodic auras; the total
--- over the duration is avgAfterMitigation.
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
---@param pctOfMaxMana boolean The base value is a percentage of maximum mana.
local function FillManaValues(calcedSpell, effNum, spellInfo, spellName, spellId, pctOfMaxMana)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];
    FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, 0, 1, 0);
    if pctOfMaxMana then
        local pct = stats.manaMax / 100;
        calcedEffect.min = calcedEffect.min * pct;
        calcedEffect.max = calcedEffect.max * pct;
        calcedEffect.avg = calcedEffect.avg * pct;
        calcedEffect.avgCombined = calcedEffect.avg;
    end
    calcedEffect.minCrit = 0;
    calcedEffect.maxCrit = 0;
    calcedEffect.avgCrit = 0;
    calcedEffect.avgAfterMitigation = calcedEffect.avgCombined * (calcedEffect.ticks or 1);
    calcedEffect.perSec = 0;
    calcedEffect.doneToOom = 0;
    calcedEffect.perResource = 0;
end

--- Mana per tick over the duration: periodic energize auras, and drinks (mana regen auras, per 2 s tick).
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function PeriodicEnergize(calcedSpell, effNum, spellInfo, spellName, spellId)
    FillManaValues(calcedSpell, effNum, spellInfo, spellName, spellId, false);
end

--- A percentage of maximum mana per tick.
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function ObsModMana(calcedSpell, effNum, spellInfo, spellName, spellId)
    FillManaValues(calcedSpell, effNum, spellInfo, spellName, spellId, true);
end

--- Handler for dummy auras
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function DummyAura(calcedSpell, effNum, spellInfo, spellName, spellId)
    assert(dummyAuraHandlers[spellName], "No dummy aura handler for effect "..effNum.." on spell "..spellName.."!");
    dummyAuraHandlers[spellName](calcedSpell, effNum, spellInfo, spellName, spellId);
end

auraHandler[AURA_TYPES.SPELL_AURA_PERIODIC_DAMAGE] = PeriodicDamage;
auraHandler[AURA_TYPES.SPELL_AURA_PERIODIC_LEECH] = PeriodicDamage;
auraHandler[AURA_TYPES.SPELL_AURA_PERIODIC_HEAL] = PeriodicHeal;
auraHandler[AURA_TYPES.SPELL_AURA_DAMAGE_SHIELD] = DamageShield;
auraHandler[AURA_TYPES.SPELL_AURA_PROC_TRIGGER_DAMAGE] = DamageShield;
auraHandler[AURA_TYPES.SPELL_AURA_PROC_TRIGGER_SPELL] = DamageShield;
auraHandler[AURA_TYPES.SPELL_AURA_MANA_SHIELD] = ManaShield;
auraHandler[AURA_TYPES.SPELL_AURA_SCHOOL_ABSORB] = AbsorbAura;
auraHandler[AURA_TYPES.SPELL_AURA_PERIODIC_TRIGGER_SPELL] = PeriodicTriggerSpell;
auraHandler[AURA_TYPES.SPELL_AURA_PERIODIC_TRIGGER_SPELL_WITH_VALUE] = PeriodicTriggerSpell;
auraHandler[AURA_TYPES.SPELL_AURA_MOD_POWER_REGEN_PERCENT] = PowerRegenPercent;
auraHandler[AURA_TYPES.SPELL_AURA_DUMMY] = DummyAura;
auraHandler[AURA_TYPES.SPELL_AURA_PERIODIC_ENERGIZE] = PeriodicEnergize;
auraHandler[AURA_TYPES.SPELL_AURA_OBS_MOD_MANA] = ObsModMana;
auraHandler[AURA_TYPES.SPELL_AURA_MOD_POWER_REGEN] = PeriodicEnergize;

----------------------------------------------------------------------------------------------------------------------------------------
-- Effect Hanlder
----------------------------------------------------------------------------------------------------------------------------------------

---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function SchoolDamage(_, calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, calcedEffect.flatMod, calcedEffect.modBase, calcedEffect.effectivePower);
    FillCritValues(calcedSpell, calcedEffect, spellId);
    Mitigate(spellName, calcedSpell, calcedEffect);

    if stats.shamanLightningOverload[spellId] and stats.shamanLightningOverload[spellId].val > 0 then
        local procChance = stats.shamanLightningOverload[spellId].val / 100;
        -- Procs do 50% of normal spell damage and they can miss.
        -- avgAfterMitigation already includes misses from the main spell and resistances.
        local effectiveProcDmg = 0.5 * calcedEffect.avgAfterMitigation * procChance * calcedSpell.hitChance / 100;
        calcedEffect.avgAfterMitigation = calcedEffect.avgAfterMitigation + effectiveProcDmg;
        calcedSpell:AddToBuffList(stats.shamanLightningOverload[spellId].buffs);
    end

    if calcedSpell.charges and calcedSpell.charges > 1 then
        calcedEffect.avgAfterMitigation = calcedEffect.avgAfterMitigation * calcedSpell.charges;
    end

    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;

    if effectData.chains and effectData.chains > 1 then
        calcedEffect.chains = effectData.chains;
        local mult = effectData.chainMult;
        if stats.spellModChainMult[spellId] then
            mult = mult * (1 + stats.spellModChainMult[spellId].val / 100);
            calcedSpell:AddToBuffList(stats.spellModChainMult[spellId].buffs);
        end
        calcedEffect.chainMult = mult;
    end
end

---Spells that consume one of the player's periodic heals on the target and heal for its full duration:
---spell ID -> rank 1 of every periodic heal they can consume.
---@type table<integer, integer[]>
local HOT_CONSUMERS = {
    [18562] = { 774, 8936 }, -- Swiftmend: Rejuvenation, Regrowth
};

---Ranks in the spell data by spell name, highest spell level first. Built on first use.
---@type table<string, integer[]>|nil
local ranksByName;

---The highest rank of a spell the player knows; the highest rank of their level if the client can't tell.
---@param rank1Id integer
---@return integer|nil spellId
---@return string|nil spellName
local function HighestKnownRank(rank1Id)
    local name = GetSpellInfo(rank1Id);
    if not name then
        return;
    end

    if not ranksByName then
        ranksByName = {};
        for id in pairs(_addon.spellInfo) do
            local rankName = GetSpellInfo(id);
            if rankName then
                ranksByName[rankName] = ranksByName[rankName] or {};
                table.insert(ranksByName[rankName], id);
            end
        end
        for _, ids in pairs(ranksByName) do
            table.sort(ids, function(a, b) return _addon.spellInfo[a].spellLevel > _addon.spellInfo[b].spellLevel end);
        end
    end

    local ranks = ranksByName[name];
    if not ranks then
        return;
    end

    for _, id in ipairs(ranks) do
        if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
            return id, name;
        end
    end

    local level = UnitLevel("player");
    for _, id in ipairs(ranks) do
        if _addon.spellInfo[id].spellLevel <= level then
            return id, name;
        end
    end
end

---What a spell from HOT_CONSUMERS heals for each periodic heal it can consume: every tick of the highest known
---rank, as the addon calculates that spell.
---@param calcedSpell CalcedSpell
---@param rank1Ids integer[]
---@return ConsumedEffectData[]
local function ConsumedHots(calcedSpell, rank1Ids)
    local consumed = {};
    for _, rank1Id in ipairs(rank1Ids) do
        local hotId, hotName = HighestKnownRank(rank1Id);
        local hot = hotId and _addon:GetCalcedSpell(hotId);
        if hot then
            for _, hotEffect in ipairs(hot.effects) do
                if hotEffect.ticks and bit.band(hotEffect.effectFlags, _addon.CONST.ADDON_EFFECT_FLAGS.HEAL) > 0 then
                    table.insert(consumed, { name = hotName, value = hotEffect.avg * hotEffect.ticks });
                    -- What changed the periodic heal counts for this spell too; many apply to both.
                    for _, buffName in ipairs(hot.buffs) do
                        local listed = false;
                        for _, known in ipairs(calcedSpell.buffs) do
                            listed = listed or known == buffName;
                        end
                        if not listed then
                            table.insert(calcedSpell.buffs, buffName);
                        end
                    end
                    break;
                end
            end
        end
    end
    return consumed;
end

---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
function HealEffect(_, calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];

    calcedEffect.consumed = nil;
    if HOT_CONSUMERS[spellId] then
        -- Swiftmend: the periodic heal's total with this spell's own modifiers, lowest to highest of the heals
        -- it can consume.
        local consumed = ConsumedHots(calcedSpell, HOT_CONSUMERS[spellId]);
        local low, high = 0, 0;
        for i, hot in ipairs(consumed) do
            hot.value = (hot.value + calcedEffect.flatMod) * calcedEffect.modBase + calcedEffect.effectivePower;
            low = i == 1 and hot.value or math.min(low, hot.value);
            high = math.max(high, hot.value);
        end
        calcedEffect.min = low;
        calcedEffect.max = high;
        calcedEffect.avg = (low + high) * 0.5;
        calcedEffect.avgCombined = calcedEffect.avg;
        calcedEffect.consumed = consumed;
    else
        FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, calcedEffect.flatMod, calcedEffect.modBase, calcedEffect.effectivePower);
    end
    FillCritValues(calcedSpell, calcedEffect, spellId);

    calcedEffect.avgAfterMitigation = calcedEffect.avgCombined;

    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;

    if effectData.chains and effectData.chains > 1 then
        calcedEffect.chains = effectData.chains;
        local mult = effectData.chainMult;
        if stats.spellModChainMult[spellId] then
            mult = mult * (1 + stats.spellModChainMult[spellId].val / 100);
            calcedSpell:AddToBuffList(stats.spellModChainMult[spellId].buffs);
        end
        calcedEffect.chainMult = mult;
    end
end

--- Handle SPELL_EFFECT_APPLY_AURA or SPELL_EFFECT_PERSISTENT_AREA_AURA,
--- they are basically the same from the PoV of this addon.
---@param auraType SpellAuraType|nil
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function AuraOrAreaAura(auraType, calcedSpell, effNum, spellInfo, spellName, spellId)
    assert(auraType, "SPELL_EFFECT_APPLY_AURA handler called without auraType for spell "..spellName.." for effect #"..effNum);
    assert(auraHandler[auraType], "Auratype "..auraType.." not implemented! Used by spell "..spellName.." for effect #"..effNum);
    auraHandler[auraType](calcedSpell, effNum, spellInfo, spellName, spellId);
end

--- Handle Attack spell that triggers auto attack
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
local function AutoAttack(_, calcedSpell, effNum, spellInfo, spellName)
    local calcedEffect = calcedSpell.effects[effNum];

    -- MAIN HAND

    calcedEffect.min = stats.attackDmg.mainhand.min * calcedEffect.modBase;
    calcedEffect.max = stats.attackDmg.mainhand.max * calcedEffect.modBase;
    calcedEffect.avg = (calcedEffect.min + calcedEffect.max) / 2;

    calcedEffect.minCrit = calcedEffect.min * calcedSpell.critMult;
    calcedEffect.maxCrit = calcedEffect.max * calcedSpell.critMult;
    calcedEffect.avgCrit = (calcedEffect.minCrit + calcedEffect.maxCrit) / 2;

    local meleeMit = calcedSpell.meleeMitigation;
    assert(meleeMit, "Melee mitigation table missing in AA handler!");

    local glancePart = meleeMit.glancing / 100;
    local critChanceRemainder = math.min(calcedSpell.critChance, calcedSpell.hitChance - meleeMit.dodge - meleeMit.parry - meleeMit.glancing - meleeMit.block);
    local critPart = critChanceRemainder / 100;
    local hitPart = (calcedSpell.hitChance - meleeMit.dodge - meleeMit.parry) / 100 - glancePart - critPart;

    local glancePartialAvg = calcedEffect.avg * meleeMit.glancingDmg * glancePart;
    local critPartialAvg = calcedEffect.avgCrit * critPart;
    local normalPartialAvg = calcedEffect.avg * hitPart;
    local avgResultDmg = normalPartialAvg + critPartialAvg + glancePartialAvg;

    calcedEffect.avgAfterMitigation = avgResultDmg * (1 - calcedSpell.avgResist);
    calcedEffect.perSec = calcedEffect.avgAfterMitigation / stats.attackSpeed.mainhand;

    if not _addon:IsDualWieldEquipped() then
        if calcedEffect.offhandAttack then
            calcedEffect.offhandAttack.min = 0;
        end
        return;
    end

    -- OFF HAND

    local ohd = calcedEffect.offhandAttack;
    assert(ohd, "Offhand table missing in AA handler!");
    local ohdMit = ohd.meleeMitigation;

    ohd.min = stats.attackDmg.offhand.min * calcedEffect.modBase;
    ohd.max = stats.attackDmg.offhand.max * calcedEffect.modBase;
    ohd.avg = (ohd.min + ohd.max) / 2;

    ohd.minCrit = ohd.min * calcedSpell.critMult;
    ohd.maxCrit = ohd.max * calcedSpell.critMult;
    ohd.avgCrit = (ohd.minCrit + ohd.maxCrit) / 2;

    glancePart = ohdMit.glancing / 100;
    critChanceRemainder = math.min(ohd.critChance, ohd.hitChance - ohdMit.dodge - ohdMit.parry - ohdMit.glancing - ohdMit.block);
    critPart = critChanceRemainder / 100;
    hitPart = (ohd.hitChance - ohdMit.dodge - ohdMit.parry) / 100 - glancePart- critPart;

    glancePartialAvg = ohd.avg * ohdMit.glancingDmg * glancePart;
    critPartialAvg = ohd.avgCrit * critPart;
    normalPartialAvg = ohd.avg * hitPart;
    avgResultDmg = normalPartialAvg + critPartialAvg + glancePartialAvg;

    ohd.avgAfterMitigation = avgResultDmg * (1 - calcedSpell.avgResist);
    ohd.perSec = ohd.avgAfterMitigation / stats.attackSpeed.offhand;
end

--- Handle SPELL_EFFECT_ENERGIZE: mana potions, runes and mana gems.
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function Energize(_, calcedSpell, effNum, spellInfo, spellName, spellId)
    FillManaValues(calcedSpell, effNum, spellInfo, spellName, spellId, false);
end

--- Handle SPELL_EFFECT_ENERGIZE_PCT: a percentage of maximum mana.
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function EnergizePct(_, calcedSpell, effNum, spellInfo, spellName, spellId)
    FillManaValues(calcedSpell, effNum, spellInfo, spellName, spellId, true);
end

---Handles SPELL_EFFECT_WEAPON_DAMAGE
---@param calcedSpell CalcedSpell
---@param effNum integer
---@param spellInfo SpellInfo
---@param spellName string
---@param spellId integer
local function WeaponDamage(_, calcedSpell, effNum, spellInfo, spellName, spellId)
    local calcedEffect = calcedSpell.effects[effNum];
    local effectData = spellInfo.effects[effNum];
    assert(effectData, "effectData missing in SPELL_EFFECT_WEAPON_DAMAGE handler for spell "..spellName);

    local weaponCoef = effectData.weaponCoef * calcedEffect.modBase;

    local weaponLow, weaponHigh;
    if spellInfo.effects[effNum].effectType == EFFECT_TYPES.SPELL_EFFECT_NORMALIZED_WEAPON_DMG then
        weaponLow, weaponHigh = GetNormalizedWeaponDamage(spellInfo.isOffhandAttack and "offhand" or "mainhand", calcedEffect.attackPower, weaponCoef);
    else
        if spellInfo.isOffhandAttack then
            weaponLow = stats.attackDmg.offhand.min * weaponCoef;
            weaponHigh = stats.attackDmg.offhand.max * weaponCoef;
        else
            weaponLow = stats.attackDmg.mainhand.min * weaponCoef;
            weaponHigh = stats.attackDmg.mainhand.max * weaponCoef;
        end
    end

    FillBaseValues(calcedSpell, calcedEffect, spellId, spellInfo, spellName, effectData, calcedEffect.flatMod, weaponCoef, calcedEffect.effectivePower);
    calcedEffect.min = calcedEffect.min + weaponLow;
    calcedEffect.max = calcedEffect.max + weaponHigh;
    calcedEffect.avg = calcedEffect.avg + 0.5 * (weaponLow + weaponHigh);
    FillCritValues(calcedSpell, calcedEffect, spellId);
    Mitigate(spellName, calcedSpell, calcedEffect, true);

    calcedEffect.perSec = calcedEffect.avgAfterMitigation / calcedSpell.effCastTime;
    calcedEffect.doneToOom = calcedSpell.castingData.castsToOom * calcedEffect.avgAfterMitigation;
    calcedEffect.perResource = calcedEffect.avgAfterMitigation / calcedSpell.effectiveCost;

    if effectData.chains and effectData.chains > 1 then
        calcedEffect.chains = effectData.chains;
        local mult = effectData.chainMult;
        if stats.spellModChainMult[spellId] then
            mult = mult * (1 + stats.spellModChainMult[spellId].val / 100);
            calcedSpell:AddToBuffList(stats.spellModChainMult[spellId].buffs);
        end
        calcedEffect.chainMult = mult;
    end
end


effHandler[EFFECT_TYPES.SPELL_EFFECT_SCHOOL_DAMAGE] = SchoolDamage;
effHandler[EFFECT_TYPES.SPELL_EFFECT_HEALTH_LEECH] = SchoolDamage;
effHandler[EFFECT_TYPES.SPELL_EFFECT_HEAL] = HealEffect;
effHandler[EFFECT_TYPES.SPELL_EFFECT_APPLY_AURA] = AuraOrAreaAura;
effHandler[EFFECT_TYPES.SPELL_EFFECT_HEALTH_FUNNEL] = AuraOrAreaAura;
effHandler[EFFECT_TYPES.SPELL_EFFECT_PERSISTENT_AREA_AURA] = AuraOrAreaAura;
effHandler[EFFECT_TYPES.SPELL_EFFECT_APPLY_AREA_AURA_PARTY] = AuraOrAreaAura;
effHandler[EFFECT_TYPES.SPELL_EFFECT_ATTACK] = AutoAttack;
effHandler[EFFECT_TYPES.SPELL_EFFECT_ENERGIZE] = Energize;
effHandler[EFFECT_TYPES.SPELL_EFFECT_ENERGIZE_PCT] = EnergizePct;
effHandler[EFFECT_TYPES.SPELL_EFFECT_WEAPON_DAMAGE] = WeaponDamage;
effHandler[EFFECT_TYPES.SPELL_EFFECT_NORMALIZED_WEAPON_DMG] = WeaponDamage;
effHandler[EFFECT_TYPES.SPELL_EFFECT_WEAPON_PERCENT_DAMAGE] = WeaponDamage;