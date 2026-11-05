-- Player buff scanning.
--
-- On Forever, aura data is secret in combat and under other addon restrictions (system/combat.lua), and
-- the aura API raises an error then. The player's own buffs are scanned while auras are readable and the
-- last state is kept meanwhile (resync when combat ends or the restriction lifts). Target auras are not
-- scanned at all: debuffs on a target almost only exist in combat, so the player picks which target auras
-- to assume instead (system/assumedTargetAuras.lua).

---@class AddonEnv
local _addon = select(2, ...);
local combat = _addon.combat;
local IsSecret = _addon.api.IsSecret;
local GetSpellName = _addon.api.GetSpellName;
-- Mainline aura API; UnitAura/UnitBuff/UnitDebuff don't exist on the Forever client.
local GetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex;

---True => active, false => should be removed, nil => not active
---@type table<integer, boolean>
local activeAuraIds = {};
---@type table<integer, integer>
local activeAuraStacks = {};
---@type table<string, boolean|nil> aura names cast by the player, for removal bookkeeping
local aurasByNamePersonal = {};

---@type table<string, integer>
local scriptedValueCache = {};

---Apply unit aura effect.
---@param spellId integer
---@param auraEffect UnitAuraEffect
---@param name string
---@param stacks integer
---@param effectSlot integer
---@param personal boolean
local function ApplyUnitAuraEffect(spellId, auraEffect, name, stacks, effectSlot, personal)
    if effectSlot then
        name = name .. "-" .. effectSlot;
    end

    assert(auraEffect.value or auraEffect.scriptValue, "Aura effect " .. name .. " has no value or scriptValue defined!");
    local value = auraEffect.value or _addon.scripting.GetValue(auraEffect.scriptValue);
    if auraEffect.scriptValue then
        name = name.."-"..spellId;
        scriptedValueCache[name] = value;
    end

    if stacks > 1 and auraEffect.hasStacks then
        value = value * stacks;
    end

    return _addon:ApplyAuraEffect(name, auraEffect, value, spellId, personal);
end

--- Remove unit aura effect.
---@param spellId integer
---@param auraEffect UnitAuraEffect
---@param name string
---@param stacks integer
---@param effectSlot number|nil
---@param personal boolean
local function RemoveUnitAuraEffect(spellId, auraEffect, name, stacks, effectSlot, personal)
    if effectSlot then
        name = name .. "-" .. effectSlot;
    end

    local value = auraEffect.value;

    if value == nil then
        name = name.."-"..spellId;
        if not auraEffect.scriptValue then
            error("Aura effect " .. name .. " has no value or scriptValue defined!");
        end
        if scriptedValueCache[name] == nil then
            error("Removed "..name.." with scriptValue without having cached value!");
        end
        value = scriptedValueCache[name];
        scriptedValueCache[name] = nil;
    end

    if stacks > 1 and auraEffect.hasStacks then
        value = value * stacks;
    end

    return _addon:RemoveAuraEffect(name, auraEffect, value, spellId, personal);
end

---Scan the player's buffs or debuffs.
---@param filter "HARMFUL"|"HELPFUL"
---@return boolean aurasChanged
---@return boolean aborted True if aura data turned out to be restricted (secret) mid-scan.
local function UpdateAuratype(filter)
    local aurasChanged = false;
    local auraTable = _addon.aurasPlayer;

    for i = 1, 255 do
        -- Raises an error when aura data turned secret since AurasRestricted() was checked.
        local ok, aura = pcall(GetAuraDataByIndex, "player", i, filter);
        if not ok then
            combat.MarkStale();
            return aurasChanged, true;
        end
        if not aura then break end

        local name, count, source, spellId = aura.name, aura.applications, aura.sourceUnit, aura.spellId;
        if IsSecret(name) or IsSecret(spellId) or IsSecret(count) or IsSecret(source) then
            -- Aura data is restricted right now (combat/encounter); redo the scan when it's allowed again.
            combat.MarkStale();
            return aurasChanged, true;
        end
        if not name or not spellId then break end
        count = count or 0;
        local isPersonal = source == "player";
        if isPersonal then aurasByNamePersonal[name] = true end

        if auraTable[spellId] and (not auraTable[spellId][1].onlyPersonal or isPersonal) then
            local auraEffects = auraTable[spellId];

            if activeAuraStacks[spellId] ~= count then
                -- Remove old effects if stacks changed.
                if activeAuraStacks[spellId] ~= nil then
                    _addon.util.PrintDebug("Remove aura " .. name .. " (" .. spellId .. ") slot " .. i .. " because stacks changed.");
                    for k, effect in ipairs(auraEffects) do
                        aurasChanged = RemoveUnitAuraEffect(spellId, effect, name, activeAuraStacks[spellId], k, isPersonal) or aurasChanged;
                    end
                end
                _addon.util.PrintDebug("Add aura " .. name .. " (" .. spellId .. ") slot " .. i);
                for k, effect in ipairs(auraEffects) do
                    aurasChanged = ApplyUnitAuraEffect(spellId, effect, name, count, k, isPersonal) or aurasChanged;
                end

                activeAuraStacks[spellId] = count;
            end

            activeAuraIds[spellId] = true;
        end
    end

    return aurasChanged, false;
end

---Update the player's buffs and debuffs.
---@param clearOnly boolean|nil Only remove everything currently applied.
function _addon:UpdatePlayerAuras(clearOnly)
    if not clearOnly and combat.AurasRestricted() then
        -- Aura data is secret right now; keep the last known state and resync afterwards.
        combat.MarkStale();
        return;
    end

    local aurasChanged = false;
    local personalBefore = aurasByNamePersonal;
    aurasByNamePersonal = {};

    for spellId in pairs(activeAuraIds) do
        activeAuraIds[spellId] = false;
    end

    if not clearOnly then
        local changed, aborted = UpdateAuratype("HELPFUL");
        aurasChanged = changed or aurasChanged;
        if not aborted then
            changed, aborted = UpdateAuratype("HARMFUL");
            aurasChanged = changed or aurasChanged;
        end
        if aborted then
            aurasByNamePersonal = personalBefore;
            return;
        end
    end

    -- Remove effects from missing auras.
    for spellId, isActive in pairs(activeAuraIds) do
        if isActive == false then
            local auraEffects = self.aurasPlayer[spellId];
            local name = GetSpellName(spellId) or tostring(spellId);
            self.util.PrintDebug("Remove aura " .. name .. " " .. spellId);
            local wasPersonal = personalBefore[name] ~= nil;
            for k, effect in ipairs(auraEffects) do
                aurasChanged = RemoveUnitAuraEffect(spellId, effect, name, activeAuraStacks[spellId], k, wasPersonal) or aurasChanged;
            end
            activeAuraIds[spellId] = nil;
            activeAuraStacks[spellId] = nil;
        end
    end

    if aurasChanged then self:TriggerUpdate() end
end

--- Simulate having a buff.
---@param spellId integer
function _addon:DebugApplyBuff(spellId)
    local buffdata = self.aurasPlayer[spellId];
    local name = GetSpellName(spellId) or tostring(spellId);

    if buffdata == nil then
        self.util.PrintError("No data for ID " .. spellId);
        return;
    end

    self.util.PrintWarn("Add buff " .. name .. " (" .. spellId .. ")");

    for k, effect in ipairs(buffdata) do
        ApplyUnitAuraEffect(spellId, effect, name, 1, k, true);
    end

    self:TriggerUpdate();
end

_addon.events.Register("UNIT_AURA", function (unit)
    if unit == "player" then
        _addon:UpdatePlayerAuras();
    end
end);
_addon.events.Register("PLAYER_ENTERING_WORLD", function() _addon:UpdatePlayerAuras() end);
combat.OnResync(function() _addon:UpdatePlayerAuras() end);
