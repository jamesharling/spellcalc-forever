---@class AddonEnv
local _addon = select(2, ...);

-- World of Warcraft: Forever carries Midnight's secret-value rules: while the player is in
-- combat (and during encounters, Mythic+ and PvP matches) aura data and most player stats
-- come back as secret values that addon code cannot compare or do arithmetic with. The
-- addon therefore only reads game state out of combat, keeps the last snapshot while
-- fighting, and re-reads everything that was skipped once combat ends.

local combat = {};
_addon.combat = combat;

---@type (fun():nil)[]
local resyncHandlers = {};
local resyncPending = false;

---True while game-state reads should be skipped.
---@return boolean
function combat.IsRestricted()
    return InCombatLockdown() == true;
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

_addon:RegisterSlashCommand("resync", function()
    _addon.util.PrintWarn("Re-reading stats, auras and talents.");
    combat.Resync();
end);
