---@class AddonEnv
local _addon = select(2, ...);
local combat = _addon.combat;
local IsSecret = _addon.api.IsSecret;

---@return UniformStat
local function UniformStat()
    ---@class UniformStat
    ---@field val integer
    ---@field buffs string[]
    return {
        ---@type number
        val = 0,
        ---@type string[]
        buffs = {}
    }
end

---@return UniformStatMult
local function UniformStatMult()
    ---@class UniformStatMult
    ---@field currentMult number
    ---@field vals table<string, integer>
    ---@field buffs string[]
    return {
        currentMult = 1,
        vals = {},
        buffs = {}
    }
end

local function SchoolStatTable()
    local SCHOOL = _addon.CONST.SCHOOL;
    -- Keys are school types found in _addon.CONST.SCHOOL
    ---@type table<SpellSchool, UniformStat>
    local schoolTable = {
        [SCHOOL.PHYSICAL] = UniformStat(),
        [SCHOOL.HOLY] = UniformStat(),
        [SCHOOL.FIRE] = UniformStat(),
        [SCHOOL.NATURE] = UniformStat(),
        [SCHOOL.FROST] = UniformStat(),
        [SCHOOL.SHADOW] = UniformStat(),
        [SCHOOL.ARCANE] = UniformStat()
    }
    return schoolTable;
end

local function SchoolStatTableMult()
    local SCHOOL = _addon.CONST.SCHOOL;
    -- Keys are school types found in _addon.CONST.SCHOOL
    ---@type table<SpellSchool, UniformStatMult>
    local schoolTable = {
        [SCHOOL.PHYSICAL] = UniformStatMult(),
        [SCHOOL.HOLY] = UniformStatMult(),
        [SCHOOL.FIRE] = UniformStatMult(),
        [SCHOOL.NATURE] = UniformStatMult(),
        [SCHOOL.FROST] = UniformStatMult(),
        [SCHOOL.SHADOW] = UniformStatMult(),
        [SCHOOL.ARCANE] = UniformStatMult()
    }
    return schoolTable;
end

local function CreatureTypeStatTable()
    local CREATURE_TYPE = _addon.CONST.CREATURE_TYPE;
    -- Keys are creature types found in _addon.CONST.CREATURE_TYPE
    ---@type table<CreatureType, UniformStat>
    local creatureTable = {
        [CREATURE_TYPE.BEAST]    = UniformStat(),
        [CREATURE_TYPE.DRAGONKIN] = UniformStat(),
        [CREATURE_TYPE.DEMON] = UniformStat(),
        [CREATURE_TYPE.ELEMENTAL] = UniformStat(),
        [CREATURE_TYPE.GIANT] = UniformStat(),
        [CREATURE_TYPE.UNDEAD] = UniformStat(),
        [CREATURE_TYPE.HUMANOID] = UniformStat(),
        [CREATURE_TYPE.CRITTER] = UniformStat(),
        [CREATURE_TYPE.MECHANICAL] = UniformStat(),
        [CREATURE_TYPE.NOT_SPECIFIED] = UniformStat(),
        [CREATURE_TYPE.TOTEM] = UniformStat()
    }
    return creatureTable;
end

local function SpellStatTable()
    ---@type table<integer, UniformStat>
    local spellTable = {};
    return spellTable;
end

local function SpellStatTableMult()
    ---@type table<integer, UniformStatMult>
    local spellTable = setmetatable({}, {
        __index = function(self, key)
            rawset(self, key, UniformStatMult());
            return self[key];
        end
    });
    return spellTable;
end

local function MechanicStatTable()
    -- Keys are mechanic types found in _addon.CONST.SPELL_MECHANIC
    ---@type table<SpellMechanic, UniformStat>
    local mt = {}
    for _, mechanicId in pairs(_addon.CONST.SPELL_MECHANIC) do
        mt[mechanicId] = UniformStat();
    end
    return mt;
end

---@class InternalStats
local stats = {
    manaMax = 0, -- Maximum mana
    manaCurrent = 0, -- Current mana if update is active
    baseMana = 0,
    manaRegBase = 0, -- Mana regen based on spirit /sec
    manaRegCasting = 0, -- Mana regen from spirit while casting /sec
    manaRegAura = 0, -- Mana regen from SPELL_AURA_MOD_POWER_REGEN sources /sec
    spellPower = {
        [_addon.CONST.SCHOOL.PHYSICAL] = 0,
        [_addon.CONST.SCHOOL.HOLY] = 0,
        [_addon.CONST.SCHOOL.FIRE] = 0,
        [_addon.CONST.SCHOOL.NATURE] = 0,
        [_addon.CONST.SCHOOL.FROST] = 0,
        [_addon.CONST.SCHOOL.SHADOW] = 0,
        [_addon.CONST.SCHOOL.ARCANE] = 0
    },
    spellHealing = 0,
    spellCrit = {
        [_addon.CONST.SCHOOL.PHYSICAL] = 0,
        [_addon.CONST.SCHOOL.HOLY] = 0,
        [_addon.CONST.SCHOOL.FIRE] = 0,
        [_addon.CONST.SCHOOL.NATURE] = 0,
        [_addon.CONST.SCHOOL.FROST] = 0,
        [_addon.CONST.SCHOOL.SHADOW] = 0,
        [_addon.CONST.SCHOOL.ARCANE] = 0
    },
    attackPower = 0,
    attackPowerRanged = 0,
    attackSpeed = {
        mainhand = 0,
        offhand = 0,
        ranged = 0
    },
    baseAttackSpeed = {
        mainhand = 0,
        offhand = 0,
        ranged = 0
    },
    attack = {
        mainhand = 0,
        offhand = 0,
        ranged = 0
    },
    attackCrit = {
        mainhand = 0,
        ranged = 0
    },
    attackDmg = {
        mainhand = {
            min = 0, -- Base damage!
            max = 0  -- Base damage!
        },
        offhand = {
            min = 0, -- Base damage!
            max = 0  -- Base damage!
        },
        ranged = {
            min = 0, -- Base damage!
            max = 0  -- Base damage!
        }
    },
    weaponBaseDamage = {
        mainhand = {
            min = 0,
            max = 0
        },
        offhand = {
            min = 0,
            max = 0
        },
        ranged = {
            min = 0,
            max = 0
        }
    },

    schoolModSpellPen = SchoolStatTable(),
    schoolModPctDamage = SchoolStatTable(),
    --schoolModFlatCritChance = SchoolStatTable(),
    schoolModPctCritMult = SchoolStatTable(),
    schoolCritBaseMult = SchoolStatTable(),
    targetSchoolModDamageTaken = SchoolStatTable(),
    targetSchoolModResistancePct = SchoolStatTable(),
    targetSchoolModCritTaken = SchoolStatTable(),
    targetSchoolModHit = SchoolStatTable(),
    targetHealingRecieved = UniformStat(),
    targetSchoolModSpellPower = SchoolStatTable(),
    targetModHealPower = UniformStat(),

    schoolModPctDamageMult = SchoolStatTableMult(),

    spellModPctEffect = SpellStatTable(),
    spellModPctDamageHealing = SpellStatTable(),
    spellModPctDoTHoT = SpellStatTable(),
    spellModFlatDuration = SpellStatTable(), -- In milliseconds
    spellModFlatTickperiod = SpellStatTable(), -- In ms
    spellModFlatValue = SpellStatTable(),
    spellModFlatSpellpower = SpellStatTable(),
    spellModEff1FlatSpellpower = SpellStatTable(),
    spellModMageNWR = SpellStatTable(),
    spellModGCDms = SpellStatTable(), -- In ms
    spellModChainMult = SpellStatTable(),
    spellModAddTriggerSpell = SpellStatTable(),
    spellModFlatHitChance = SpellStatTable(),
    spellModFlatCritChance = SpellStatTable(),
    spellModPctCritMult = SpellStatTable(),
    spellModFlatSpellScale = SpellStatTable(),
    spellModPctSpellScale = SpellStatTable(),
    spellModClearCastChance = SpellStatTable(),
    spellModCharges = SpellStatTable(),
    spellModCritManaRestore = SpellStatTable(),
    spellModManaRestore = SpellStatTable(),
    spellModAllowDotCrit = SpellStatTable(),
    spellModAllowDotHaste = SpellStatTable(),
    spellModExtraOnCrit = SpellStatTable(),
    spellModExtraOnHit = SpellStatTable(),

    targetSpellModDmgTakenPersonal = SpellStatTableMult(),

    versusModPctDamage = CreatureTypeStatTable(),
    versusModPctCritDamage = CreatureTypeStatTable(),
    versusModFlatSpellpower = CreatureTypeStatTable(),
    versusModFlatAttackpower = CreatureTypeStatTable(),
    versusModFlatAttackpowerRanged = CreatureTypeStatTable(),
    versusModFlatDamage = CreatureTypeStatTable(),

    targetMechanicModDmgTakenPct = MechanicStatTable(),

    mp5 = UniformStat();
    fsrRegenMult = UniformStat();
    modhealingDone = UniformStat(),
    hitBonus = UniformStat();
    hitBonusSpell = UniformStat();
    clearCastChanceDmg = UniformStat(),
    clearCastChance = UniformStat(),
    illumination = UniformStat(),
    earthfuryReturn = UniformStat(),
    shamanLightningOverload = SpellStatTable(),
    castManaRestoreAvg = UniformStat(),
    modCriticalHealing = UniformStat(),
};

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

---Skip a read while combat restrictions are active and remember to redo it afterwards.
---@return boolean skipped
local function SkipIfRestricted()
    if combat.IsRestricted() then
        combat.MarkStale();
        return true;
    end
    return false;
end

---True if any of the values is a secret value. The read is then skipped so the old values stay, and it
---is redone when combat ends or the restriction lifts. This catches stats that come back secret while no
---restriction is reported (yet, or any more); storing them as 0 would stick until the next stat event.
---@return boolean secret
local function AnySecret(...)
    for i = 1, select("#", ...) do
        if IsSecret((select(i, ...))) then
            combat.MarkStale();
            return true;
        end
    end
    return false;
end

---Return the value, or 0 for nil (and, as a last resort, for a secret value a caller did not check).
---@param v number|nil
---@return number
local function Num(v)
    if v == nil or IsSecret(v) then return 0 end
    return v;
end

---------------------------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------------------------

---Update base mana for current level.
---@param level integer
local function UpdateBaseMana(level)
    local _, eclass = UnitClass("player");
    local basemana = _addon.GetBaseMana(eclass, level);
    if basemana ~= stats.baseMana then
        stats.baseMana = basemana;
        _addon:TriggerUpdate();
    end
end

--- Update spell power stats from API
local function UpdateSpellPower()
    if SkipIfRestricted() then return end
    local power = {};
    for i = 1, 7, 1 do
        local v = GetSpellBonusDamage(i);
        if AnySecret(v) then return end
        power[i] = v;
    end
    _addon.util.PrintDebug("Updating spell power");

    for i = 1, 7, 1 do
        stats.spellPower[i] = Num(power[i]);
    end

    _addon:TriggerUpdate();
end

---Update attack power.
local function UpdateAttackPower()
    if SkipIfRestricted() then return end
    local base, posBuff, negBuff = UnitAttackPower("player");
    if AnySecret(base, posBuff, negBuff) then return end
    stats.attackPower = Num(base) + Num(posBuff) + Num(negBuff);
    _addon:TriggerUpdate();
end

---Update ranged attack power.
local function UpdateRangedAttackPower()
    if SkipIfRestricted() then return end
    local base, posBuff, negBuff = UnitRangedAttackPower("player");
    if AnySecret(base, posBuff, negBuff) then return end
    stats.attackPowerRanged = Num(base) + Num(posBuff) + Num(negBuff);
    _addon:TriggerUpdate();
end

--- Update dmg done mods
local function UpdateDmgDoneMods()
    if SkipIfRestricted() then return end
    local spellHealing = GetSpellBonusHealing();
    local meleeCrit, rangedCrit = GetCritChance(), GetRangedCritChance();
    if AnySecret(spellHealing, meleeCrit, rangedCrit) then return end
    local spellCrit = {};
    for i = 1, 7, 1 do
        local v = GetSpellCritChance(i);
        if AnySecret(v) then return end
        spellCrit[i] = v;
    end

    spellHealing = Num(spellHealing);
    if spellHealing ~= stats.spellHealing then
        _addon.util.PrintDebug("Updating healing");
        stats.spellHealing = spellHealing;
    end

    _addon.util.PrintDebug("Updating dmg done mods");
    for i = 1, 7, 1 do
        stats.spellCrit[i] = Num(spellCrit[i]);
    end

    stats.attackCrit.mainhand = Num(meleeCrit);
    stats.attackCrit.ranged = Num(rangedCrit);

    _addon:TriggerUpdate();
end

---Update spirit based and MP5 regen values (classic rules: spirit only, no intellect term).
-- Classic Era gave priests and mages 0.125 mana per spirit per second and everyone else 0.1.
-- Forever uses 0.125 for every caster (StatLogic's Forever tables, CamelotLogic.lua, versus its
-- Era tables), so the priest/mage formula applies to all classes.
-- Whatever GetManaRegen reports above the spirit part is treated as mp5 (manaRegAura); see
-- CostHandler for how it combines with mp5 from the addon's own aura data.
function _addon:UpdateManaRegen()
    if SkipIfRestricted() then return end
    local _, spirit = UnitStat("player", 5);
    local apiRegen = GetManaRegen();
    if AnySecret(spirit, apiRegen) then return end
    spirit = Num(spirit);

    local spiritRegen = (12.5 + spirit / 4) / 2;

    local newmanaRegCasting = spiritRegen * (stats.fsrRegenMult.val / 100);
    local newmanaRegAura = math.max(0, Num(apiRegen) - spiritRegen);
    -- Remove minor errors in spirit regen calculation if mp5 should be 0.
    if newmanaRegAura < 0.1 then newmanaRegAura = 0 end

    if stats.manaRegBase ~= spiritRegen
        or stats.manaRegCasting ~= newmanaRegCasting
        or stats.manaRegAura ~= newmanaRegAura then
        stats.manaRegBase = spiritRegen;
        stats.manaRegCasting = newmanaRegCasting;
        stats.manaRegAura = newmanaRegAura;
        self:TriggerUpdate();
    end
end

--- Update general stats from API
local function UpdateStats()
    if SkipIfRestricted() then return end
    local manaMax = UnitPowerMax("player", 0);
    if AnySecret(manaMax) then return end
    _addon.util.PrintDebug("Updating stats");
    stats.manaMax = Num(manaMax);
    _addon:TriggerUpdate();
end

--- Update weapon attack speeds
local function UpdateAttackSpeeds()
    if SkipIfRestricted() then return end
    local m, o = UnitAttackSpeed("player");
    local r = UnitRangedDamage("player");
    if AnySecret(m, o, r) then return end

    stats.attackSpeed.mainhand = Num(m);
    stats.attackSpeed.offhand = Num(o);
    stats.attackSpeed.ranged = Num(r);

    _addon.util.PrintDebug(("Updated attack speeds: %s, %s, %s"):format(stats.attackSpeed.mainhand, stats.attackSpeed.offhand, stats.attackSpeed.ranged));

    _addon:TriggerUpdate();
end

---------------------------------------------------------------------------------------------
-- Weapon skill
-- The classic UnitAttackBothHands/UnitRangedAttack functions don't exist on the Mainline client.
-- Forever's own character sheet resolves the equipped weapon's skill line and reads it through
-- C_SkillInfo; this mirrors Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua.
---------------------------------------------------------------------------------------------

local SLOT_MAINHAND, SLOT_OFFHAND, SLOT_RANGED = 16, 17, 18;
local SKILL_LINE_UNARMED = 162;
local SKILL_LINE_FERAL = 3014;
---@type table<integer, integer> Enum.ItemWeaponSubclass -> skill line ID
local WEAPON_SUBCLASS_TO_SKILL_LINE = {};
do
    local ws = Enum.ItemWeaponSubclass or {};
    local map = {
        { "Sword1H", 43 }, { "Axe1H", 44 }, { "Bows", 45 }, { "Guns", 46 }, { "Mace1H", 54 },
        { "Sword2H", 55 }, { "Staff", 136 }, { "Mace2H", 160 }, { "Axe2H", 172 }, { "Dagger", 173 },
        { "Thrown", 176 }, { "Crossbow", 226 }, { "Wand", 228 }, { "Polearm", 229 }, { "Unarmed", 162 },
    };
    for _, entry in ipairs(map) do
        local subclass = ws[entry[1]];
        if subclass ~= nil then
            WEAPON_SUBCLASS_TO_SKILL_LINE[subclass] = entry[2];
        end
    end
end

---Skill line ID of the weapon in the given inventory slot, nil if there is nothing to attack with.
---@param slotID integer
---@return integer|nil
local function GetEquippedWeaponSkillLine(slotID)
    local _, class = UnitClass("player");
    if class == "DRUID" and GetShapeshiftForm() ~= 0 then
        return SKILL_LINE_FERAL;
    end

    local itemID = GetInventoryItemID("player", slotID);
    if not itemID then
        return slotID ~= SLOT_RANGED and SKILL_LINE_UNARMED or nil;
    end

    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID);
    if classID ~= Enum.ItemClass.Weapon then
        return nil;
    end

    return WEAPON_SUBCLASS_TO_SKILL_LINE[subclassID];
end

---Weapon skill rank and modifier for an inventory slot, as the API reports them (possibly nil or secret).
---@param slotID integer
---@return number|nil rank
---@return number|nil modifier
local function GetWeaponSkill(slotID)
    local skillLine = GetEquippedWeaponSkillLine(slotID);
    if not skillLine or not C_SkillInfo or not C_SkillInfo.GetSkillLineInfoByID then
        return 0, 0;
    end
    local info = C_SkillInfo.GetSkillLineInfoByID(skillLine);
    if not info then
        return 0, 0;
    end
    return info.rank, info.modifier;
end

--- Update weapon attack skill
local function UpdateWeaponAttack()
    if SkipIfRestricted() then return end
    local mh, mhMod = GetWeaponSkill(SLOT_MAINHAND);
    local oh, ohMod = GetWeaponSkill(SLOT_OFFHAND);
    local r, rMod = GetWeaponSkill(SLOT_RANGED);
    if AnySecret(mh, mhMod, oh, ohMod, r, rMod) then return end
    mh, mhMod, oh, ohMod, r, rMod = Num(mh), Num(mhMod), Num(oh), Num(ohMod), Num(r), Num(rMod);

    stats.attack.mainhand = mh + mhMod;
    stats.attack.offhand = oh + ohMod;
    stats.attack.ranged = r + rMod;

    _addon.util.PrintDebug(("Updated attack: M: %d + %d O: %d + %d R: %d + %d"):format(mh, mhMod, oh, ohMod, r, rMod));

    _addon:TriggerUpdate();
end

--- Update melee attack damage
local function UpdateAttackDmg()
    if SkipIfRestricted() then return end
    local low, high, offLow, offHigh, _, _, pctMod = UnitDamage("player");
    if AnySecret(low, high, offLow, offHigh, pctMod) then return end
    _addon.util.PrintDebug("Updated melee dmg");
    pctMod = Num(pctMod);
    if pctMod == 0 then pctMod = 1 end
    stats.attackDmg.mainhand.min = Num(low) / pctMod;
    stats.attackDmg.mainhand.max = Num(high) / pctMod;
    stats.attackDmg.offhand.min = Num(offLow) / pctMod;
    stats.attackDmg.offhand.max = Num(offHigh) / pctMod;
    _addon:TriggerUpdate();
end

--- Update ranged attack damage
local function UpdateRangedAttackDmg()
    if SkipIfRestricted() then return end
    local _, lowDmg, hiDmg, _, _, pctMod = UnitRangedDamage("player");
    if AnySecret(lowDmg, hiDmg, pctMod) then return end
    _addon.util.PrintDebug("Updated ranged dmg");
    pctMod = Num(pctMod);
    if pctMod == 0 then pctMod = 1 end
    stats.attackDmg.ranged.min = Num(lowDmg) / pctMod;
    stats.attackDmg.ranged.max = Num(hiDmg) / pctMod;
    _addon:TriggerUpdate();
end

local oldApiHitBonus = 0;
local oldApiHitBonusSpell = 0;

--- Combat ratings updated.
-- Classic rules: hit from gear is tracked through item effect data, the API hit modifiers are
-- not used (GetHitModifier only updates with a weapon equipped, GetSpellHitModifier is unreliable).
local function CombatRatingUpdate()
    if SkipIfRestricted() then return end
    _addon.util.PrintDebug("Combat rating update");

    local meleeHitBonus = 0;
    local spellHitBonus = 0;

    local changed = false;

    if meleeHitBonus ~= oldApiHitBonus then
        stats.hitBonus.val = stats.hitBonus.val - oldApiHitBonus + meleeHitBonus;
        oldApiHitBonus = meleeHitBonus;
        changed = true;
    end

    if spellHitBonus ~= oldApiHitBonusSpell then
        stats.hitBonusSpell.val = stats.hitBonusSpell.val - oldApiHitBonusSpell + spellHitBonus;
        oldApiHitBonusSpell = spellHitBonus;
        changed = true;
    end

    if changed then
        _addon.util.PrintDebug("Updated hit mods from API. M: " .. meleeHitBonus .. " - S: " .. spellHitBonus);
        _addon:TriggerUpdate();
    end
end

---Re-read everything.
local function UpdateAll()
    if SkipIfRestricted() then return end
    UpdateStats();
    UpdateSpellPower();
    UpdateDmgDoneMods();
    UpdateAttackSpeeds();
    UpdateWeaponAttack();
    UpdateAttackDmg();
    UpdateRangedAttackDmg();
    CombatRatingUpdate();
    _addon:UpdateManaRegen();
    UpdateAttackPower();
    UpdateRangedAttackPower();
    UpdateBaseMana(UnitLevel("player"));
end

_addon.stats = stats;

_addon.events.Register("UNIT_ATTACK_POWER", function (unit) if unit == "player" then UpdateAttackPower() end end);
_addon.events.Register("UNIT_RANGED_ATTACK_POWER", function (unit) if unit == "player" then UpdateRangedAttackPower() end end);
_addon.events.Register("UNIT_RANGEDDAMAGE", function (unit) if unit == "player" then UpdateRangedAttackDmg() end end);
_addon.events.Register("UNIT_DAMAGE", function (unit) if unit == "player" then UpdateAttackDmg() end end);
_addon.events.Register("UNIT_ATTACK", function (unit) if unit == "player" then UpdateWeaponAttack() end end);
_addon.events.Register("SKILL_LINES_CHANGED", function () UpdateWeaponAttack() end);
_addon.events.Register("UNIT_INVENTORY_CHANGED", function (unit) if unit == "player" then UpdateWeaponAttack() end end);
_addon.events.Register("UPDATE_SHAPESHIFT_FORM", function () UpdateWeaponAttack() end);
_addon.events.Register("UNIT_ATTACK_SPEED", function (unit) if unit == "player" then UpdateAttackSpeeds() end end);
_addon.events.Register("COMBAT_RATING_UPDATE", function () CombatRatingUpdate() end);
_addon.events.Register("PLAYER_DAMAGE_DONE_MODS", function (unit) if unit == "player" then UpdateDmgDoneMods() end end);
_addon.events.Register("SPELL_POWER_CHANGED", function () UpdateSpellPower() end);
_addon.events.Register("PLAYER_LEVEL_UP", function (level) UpdateBaseMana(level) end);
_addon.events.Register("PLAYER_ENTERING_WORLD", function() UpdateAll() end);
combat.OnResync(UpdateAll);

_addon.events.Register("UNIT_STATS", function (unit)
    if unit == "player" then
        UpdateStats();
        _addon:UpdateManaRegen();
    end
end);

_addon.events.Register("UNIT_AURA", function (unit)
    if unit == "player" then
        _addon:UpdateManaRegen();
    end
end);
