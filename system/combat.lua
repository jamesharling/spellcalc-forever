---@class AddonEnv
local _addon = select(2, ...);

-- World of Warcraft: Forever carries Midnight's secret-value rules: while the player is in
-- combat (and during encounters, Mythic+ and PvP matches, and on some maps) aura data and most
-- player stats come back as secret values that addon code cannot compare or do arithmetic with;
-- the aura API even raises an error. The addon therefore only reads game state while no
-- restriction is active, keeps the last snapshot meanwhile, and re-reads everything that was
-- skipped once combat ends or the restriction lifts.

local combat = {};
_addon.combat = combat;

---@type (fun():nil)[]
local resyncHandlers = {};
local resyncPending = false;

-- Addon restrictions that hide game state (all but Chat, which only limits addon messages).
local RESTRICTION_TYPES = {};
if Enum.AddOnRestrictionType then
    for name, value in pairs(Enum.AddOnRestrictionType) do
        if name ~= "Chat" then RESTRICTION_TYPES[#RESTRICTION_TYPES + 1] = value end
    end
end

---Call a restriction query; false if it doesn't exist or fails.
---@param fn function|nil
---@return boolean
local function Query(fn, ...)
    if not fn then return false end
    local ok, result = pcall(fn, ...);
    return ok and result == true;
end

---True while game-state reads should be skipped: in combat, or while an addon restriction
---(combat, encounter, Mythic+, PvP match, restricted map) is active.
---@return boolean
function combat.IsRestricted()
    if InCombatLockdown() == true then return true end
    local isActive = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive;
    for _, restrictionType in ipairs(RESTRICTION_TYPES) do
        if Query(isActive, restrictionType) then return true end
    end
    return false;
end

---True while aura data is secret; the aura API raises an error for addon code then.
---@return boolean
function combat.AurasRestricted()
    return combat.IsRestricted() or Query(C_Secrets and C_Secrets.ShouldAurasBeSecret);
end

---Register a function that re-reads game state. Called after combat if anything was skipped.
---@param fn fun():nil
function combat.OnResync(fn)
    table.insert(resyncHandlers, fn);
end

---Remember that a read was skipped because of combat restrictions.
function combat.MarkStale()
    resyncPending = true;
end

---Re-read everything now (used after combat and by the debug command).
function combat.Resync()
    resyncPending = false;
    _addon.util.PrintDebug("Resyncing game state after combat");
    for _, fn in ipairs(resyncHandlers) do
        fn();
    end
    _addon:TriggerUpdate();
end

_addon.events.Register("PLAYER_REGEN_ENABLED", function()
    if resyncPending then
        combat.Resync();
    end
end);

-- A restriction lifted, possibly out of combat (end of a Mythic+ run or PvP match). If another one is
-- still active the reads skip again and stay pending.
if Enum.AddOnRestrictionState then
    _addon.events.Register("ADDON_RESTRICTION_STATE_CHANGED", function(_, state)
        if state == Enum.AddOnRestrictionState.Inactive and resyncPending then
            combat.Resync();
        end
    end);
end

_addon:RegisterSlashCommand("resync", function()
    _addon.util.PrintWarn("Re-reading stats, auras and talents.");
    combat.Resync();
end);
