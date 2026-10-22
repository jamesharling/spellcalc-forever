---@class AddonEnv
local _addon = select(2, ...);
local combat = _addon.combat;
local GetSpellName = _addon.api.GetSpellName;

-- Forever's class talent trees are regular trait trees (the Mainline talent system), so
-- they are read through C_ClassTalents / C_Traits. Addon talent data is keyed by the rank-1
-- spell ID of the talent (TraitDefinition.SpellID), which survives Blizzard moving talents
-- around the tree.

---@class InternalTalentData
---@field spellId integer rank-1 spell ID of the talent
---@field name string identifier used for the applied effects
---@field addonData TalentDataRawEntry

---@type table<integer, InternalTalentData> tracked talents by rank-1 spell ID
local trackedTalents = {};
---@type table<integer, integer> rank currently applied per tracked spell ID
local appliedRanks = {};
---@type table<integer, integer> last read rank for every talent in the active config
local currentRanks = {};
local talentDataCreated = false;
local retriesLeft = 20;

---Build the lookup from the generated talent data.
local function SetupTalentData()
    trackedTalents = {};
    for _, v in ipairs(_addon.talentDataRaw or {}) do
        assert(v.spellId, "Talent data entry without spellId!");
        local name = v.name or GetSpellName(v.spellId) or ("Talent" .. v.spellId);
        trackedTalents[v.spellId] = { spellId = v.spellId, name = name, addonData = v };
    end
    talentDataCreated = true;
    _addon.util.PrintDebug("Tracking " .. #(_addon.talentDataRaw or {}) .. " talents");
end

---Read rank per rank-1 spell ID from the active trait config.
---@return table<integer, integer>|nil ranks nil if the talent API isn't ready yet
local function ReadTraitRanks()
    if not C_ClassTalents or not C_Traits then return nil end

    local configID = C_ClassTalents.GetActiveConfigID();
    if not configID then return nil end

    local configInfo = C_Traits.GetConfigInfo(configID);
    if not configInfo or not configInfo.treeIDs then return nil end

    local ranks = {};
    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodeIDs = C_Traits.GetTreeNodes(treeID);
        if nodeIDs then
            for _, nodeID in ipairs(nodeIDs) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
                if nodeInfo then
                    local entryID, rank;
                    if nodeInfo.activeEntry then
                        entryID = nodeInfo.activeEntry.entryID;
                        rank = nodeInfo.activeEntry.rank;
                    elseif nodeInfo.entryIDs and nodeInfo.entryIDs[1] then
                        entryID = nodeInfo.entryIDs[1];
                        rank = nodeInfo.activeRank or nodeInfo.ranksPurchased;
                    end
                    rank = rank or 0;

                    if entryID and rank > 0 then
                        local entryInfo = C_Traits.GetEntryInfo(configID, entryID);
                        local defID = entryInfo and entryInfo.definitionID;
                        local defInfo = defID and C_Traits.GetDefinitionInfo(defID);
                        local spellID = defInfo and defInfo.spellID;
                        if spellID then
                            ranks[spellID] = rank;
                        end
                    end
                end
            end
        end
    end

    return ranks;
end

---Value of a talent effect at a given rank.
---@param effect table
---@param rank integer
---@return number|nil
local function TalentEffectValue(effect, rank)
    if effect.values then
        -- Rank counts can differ from the data the addon was generated with; clamp instead of erroring.
        return effect.values[math.min(rank, #effect.values)];
    end
    return effect.perPoint * rank;
end

---Apply or remove the effects of a talent at a rank.
---@param talent InternalTalentData
---@param rank integer
---@param apply boolean
local function SetTalentEffects(talent, rank, apply)
    local idName = talent.name .. rank;
    _addon.util.PrintDebug((apply and "Add talent rank " or "Remove talent rank ") .. idName);
    for k, effect in ipairs(talent.addonData.effects) do
        local value = TalentEffectValue(effect, rank);
        if value == nil then
            _addon.util.PrintError("Talent def for " .. idName .. " has no value!");
        else
            local useName = (k > 1) and idName .. "-" .. k or idName;
            if apply then
                _addon:ApplyAuraEffect(useName, effect, value, -1, true);
            else
                _addon:RemoveAuraEffect(useName, effect, value, -1, true);
            end
        end
    end
end

--- Update player talents.
local function UpdateTalents()
    if combat.IsRestricted() then
        combat.MarkStale();
        return;
    end

    if not talentDataCreated then
        SetupTalentData();
    end

    local ranks = ReadTraitRanks();
    if not ranks then
        if retriesLeft > 0 then
            retriesLeft = retriesLeft - 1;
            _addon.util.PrintDebug("Talent data not available yet, retrying.");
            C_Timer.After(3, UpdateTalents);
        else
            _addon.util.PrintError("Could not read talents from the talent API.");
        end
        return;
    end
    retriesLeft = 20;
    currentRanks = ranks;

    _addon.util.PrintDebug("Updating talents");

    for spellId, talent in pairs(trackedTalents) do
        local newRank = ranks[spellId] or 0;
        local oldRank = appliedRanks[spellId];

        if oldRank ~= nil and oldRank ~= newRank then
            SetTalentEffects(talent, oldRank, false);
            appliedRanks[spellId] = nil;
        end

        if newRank > 0 and appliedRanks[spellId] == nil then
            SetTalentEffects(talent, newRank, true);
            appliedRanks[spellId] = newRank;
        end
    end

    _addon:TriggerUpdate();
end

---Return current rank for a talent given its rank-1 spell ID (0 if not taken or unknown).
---@param spellId integer
---@return integer
function _addon:GetTalentRankBySpellId(spellId)
    return currentRanks[spellId] or 0;
end

_addon.events.Register("PLAYER_ENTERING_WORLD", function() UpdateTalents() end);
_addon.events.Register("TRAIT_CONFIG_UPDATED", function() UpdateTalents() end);
_addon.events.Register("TRAIT_CONFIG_LIST_UPDATED", function() UpdateTalents() end);
_addon.events.Register("ACTIVE_COMBAT_CONFIG_CHANGED", function() UpdateTalents() end);
_addon.events.Register("PLAYER_TALENT_UPDATE", function() UpdateTalents() end);
_addon.events.Register("ACTIVE_TALENT_GROUP_CHANGED", function() UpdateTalents() end);
combat.OnResync(UpdateTalents);

_addon:RegisterSlashCommand("debugtalents", function()
    _addon.util.PrintWarn("Updating talents with debug output!");
    local debugSetting = SpellCalc_settings.debug;
    SpellCalc_settings.debug = true;
    SetupTalentData();
    UpdateTalents();
    for spellId, talent in pairs(trackedTalents) do
        print(("  %s (%d): rank %d"):format(talent.name, spellId, currentRanks[spellId] or 0));
    end
    SpellCalc_settings.debug = debugSetting;
end);
