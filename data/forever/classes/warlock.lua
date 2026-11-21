---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "WARLOCK" then
    return;
end

--------------------------------------------------------------------------
-- Player auras
--------------------------------------------------------------------------

-- Master Demonologist (23759 Imp: Fire damage, 23761 Succubus: Shadow damage) and Soul Link (25228) come from
-- the generated player aura data (area auras from the pet). Forever's Master Demonologist aura spells carry
-- the 5-rank value (10%); the talent gives 2% per rank.

--------------------------------------------------------------------------
-- Scripts
--------------------------------------------------------------------------

-- (The Season of Discovery Soul Siphon rune script was removed for the Forever port. Forever has a
-- Soul Siphon talent instead; model it when the Forever talent data is generated.)
