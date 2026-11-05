---@class AddonEnv
local _addon = select(2, ...);
local SCHOOL = _addon.CONST.SCHOOL;

---@class Target
---@field class string|nil
---@field creatureType number|nil
---@field resistanceBase table<number, number>
local Target = {
    level = 0,
    levelDiff = 0,
    isPlayer = false,
    isSelf = false,
    exists = false,
    resistanceBase = {
        [SCHOOL.PHYSICAL] = 0,
        [SCHOOL.HOLY] = 0,
        [SCHOOL.FIRE] = 0,
        [SCHOOL.NATURE] = 0,
        [SCHOOL.FROST] = 0,
        [SCHOOL.SHADOW] = 0,
        [SCHOOL.ARCANE] = 0
    }
};

--- Update resistance values for current target.
-- Custom values from the settings, otherwise armor by level. (A table of raid boss resistances by NPC ID
-- was removed: unit identity is secret inside instances on Forever, where those bosses are.)
local function UpdateResistances()
    for _, schoolNum in pairs(SCHOOL) do
        Target.resistanceBase[schoolNum] = 0;
    end

    if SpellCalc_settings.resOverrideFire > 0 then
        Target.resistanceBase[SCHOOL.FIRE] = SpellCalc_settings.resOverrideFire;
    end
    if SpellCalc_settings.resOverrideFrost > 0 then
        Target.resistanceBase[SCHOOL.FROST] = SpellCalc_settings.resOverrideFrost;
    end
    if SpellCalc_settings.resOverrideNature > 0 then
        Target.resistanceBase[SCHOOL.NATURE] = SpellCalc_settings.resOverrideNature;
    end
    if SpellCalc_settings.resOverrideShadow > 0 then
        Target.resistanceBase[SCHOOL.SHADOW] = SpellCalc_settings.resOverrideShadow;
    end
    if SpellCalc_settings.resOverrideArcane > 0 then
        Target.resistanceBase[SCHOOL.ARCANE] = SpellCalc_settings.resOverrideArcane;
    end
    if SpellCalc_settings.resOverrideArmor > 0 then
        Target.resistanceBase[SCHOOL.PHYSICAL] = SpellCalc_settings.resOverrideArmor;
    end

    if Target.isPlayer then
        return;
    end

    if Target.resistanceBase[SCHOOL.PHYSICAL] == 0 then
        Target.resistanceBase[SCHOOL.PHYSICAL] = _addon.levelDefaultArmor[Target.level];
        if Target.class == "PALADIN" then
            -- This is just a rough value. Always seems to be between 0.80-0.83 of "warrior" armor,
            -- with higher levels closer to 0.8, so this should be close enough.
            Target.resistanceBase[SCHOOL.PHYSICAL] = Target.resistanceBase[SCHOOL.PHYSICAL] * 0.81;
        elseif Target.class == "MAGE" then
            Target.resistanceBase[SCHOOL.PHYSICAL] = Target.resistanceBase[SCHOOL.PHYSICAL] * 0.5;
        end
    end
end

---Return resistance for school after reductions on target.
---@param school number
---@return number
function Target:GetEffectiveResistance(school)
    local r = self.resistanceBase[school];
    if _addon.stats.targetSchoolModResistancePct[school].val ~= 0 then
        r = r * (1 + _addon.stats.targetSchoolModResistancePct[school].val/100);
    end
    return r;
end

--- Update currently selected target.
-- Unit identity (name, GUID, creature type, class, level) can be a secret value inside instances and in
-- combat; such values are treated as unknown rather than compared or used as table keys.
function Target:Update()
    local Unsecret = _addon.api.Unsecret;
    local rawName = UnitName("target");
    local pLevel = UnitLevel("player");
    local _, class = UnitClass("target");
    -- Second return: the CreatureType ID (1 Beast ... 7 Humanoid ... 11 Totem), so no localized names.
    local _, creatureTypeId = UnitCreatureType("target");
    local level = UnitLevel("target");
    local tLevel = Unsecret(level);

    self.class = Unsecret(class);
    self.isSelf = Unsecret(UnitIsUnit("player", "target"), false) == true;
    self.isPlayer = Unsecret(UnitIsPlayer("target"), false) == true;
    self.exists = rawName ~= nil;

    -- An unknown (secret) level gets the default level difference, not the skull level (-1).
    if not self.exists or not SpellCalc_settings.useCurrentTarget or tLevel == nil then
        self.level = pLevel + SpellCalc_settings.defaultTargetLvlOffset;
        self.levelDiff = SpellCalc_settings.defaultTargetLvlOffset;
    else
        if tLevel == -1 then
            tLevel = pLevel + 3;
        end
        self.level = tLevel;
        self.levelDiff = tLevel - pLevel;
    end

    -- Make sure level can never be below 1.
    if self.level < 1 then
        local diffToOne = self.level - 1;
        self.level = 1;
        self.levelDiff = self.levelDiff - diffToOne;
    end

    if self.exists then
        if not self.isPlayer then
            self.creatureType = Unsecret(creatureTypeId);
        else
            self.creatureType = 7;
        end
    else
        self.creatureType = nil;
    end

    UpdateResistances();

    _addon.util.PrintDebug(("New target: %d (%d), Player: %s"):format(self.level, self.levelDiff, tostring(self.isPlayer)));
    _addon.util.PrintDebug(("P: %d, H: %d, Fi: %d, N: %d, Fr: %d, S: %d, A: %d"):format(self.resistanceBase[SCHOOL.PHYSICAL], self.resistanceBase[SCHOOL.HOLY], self.resistanceBase[SCHOOL.FIRE],
        self.resistanceBase[SCHOOL.NATURE], self.resistanceBase[SCHOOL.FROST], self.resistanceBase[SCHOOL.SHADOW], self.resistanceBase[SCHOOL.ARCANE]));

    _addon:TriggerUpdate();
end

_addon.Target = Target;

_addon.events.Register("PLAYER_ENTERING_WORLD", function() Target:Update() end);
_addon.events.Register("PLAYER_TARGET_CHANGED", function () Target:Update() end);

