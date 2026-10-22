-- Assumed target auras.
--
-- Forever makes aura data secret in combat, and debuffs on a target almost only exist in combat, so the
-- addon doesn't scan the target's auras. Instead the player picks which target auras to assume
-- (Settings > Target Auras): their effects stay applied while selected, whatever the current target is.
--
-- The candidates are generated (data/forever/aurasTarget.lua, _addon.assumableTargetAuras): the highest
-- rank of every class debuff or helpful target buff that changes the calculations. auraCategory effects
-- (e.g. two armor reductions of the same category) still only apply the strongest one.

---@class AddonEnv
local _addon = select(2, ...);
local GetSpellName = _addon.api.GetSpellName;
local L = _addon:GetLocalization();

---@class AssumableTargetAura
---@field spellId integer
---@field class string Class token of the caster
---@field maxStacks integer
---@field fromCaster boolean|nil Only increases damage done by the aura's caster (offered to that class only)

local _, playerClass = UnitClass("player");

local CLASS_ORDER = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" };

---@type table<integer, integer> stacks currently applied per spell ID
local applied = {};

---@param spellId integer
---@param stacks integer
---@param apply boolean
local function SetAura(spellId, stacks, apply)
    local effects = _addon.aurasTarget[spellId];
    if not effects then return end
    for k, effect in ipairs(effects) do
        local value = effect.value or 0;
        if effect.hasStacks and stacks > 1 then
            value = value * stacks;
        end
        local name = "AssumedTargetAura-" .. spellId .. "-" .. k;
        if apply then
            _addon:ApplyAuraEffect(name, effect, value, spellId, true);
        else
            _addon:RemoveAuraEffect(name, effect, value, spellId, true);
        end
    end
end

---Apply the target auras selected in the settings, removing ones that were deselected.
function _addon:UpdateAssumedTargetAuras()
    local wanted = SpellCalc_settings.assumedTargetAuras or {};
    local changed = false;

    for spellId, stacks in pairs(applied) do
        if wanted[spellId] ~= stacks then
            SetAura(spellId, stacks, false);
            applied[spellId] = nil;
            changed = true;
        end
    end

    for spellId, stacks in pairs(wanted) do
        if type(stacks) == "number" and stacks > 0 and applied[spellId] == nil and self.aurasTarget[spellId] then
            SetAura(spellId, stacks, true);
            applied[spellId] = stacks;
            changed = true;
        end
    end

    if changed then self:TriggerUpdate() end
end

---@param spellId integer
---@return string
local function AuraName(spellId)
    local name = GetSpellName(spellId) or ("spell " .. spellId);
    local rank = _addon.api.GetSpellSubtext(spellId);
    if rank and rank ~= "" then
        return name .. " (" .. rank .. ")";
    end
    return name;
end

---@param spellId integer
---@return string
local function AuraDesc(spellId)
    local desc = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellId);
    if type(desc) ~= "string" or _addon.api.IsSecret(desc) then return "" end
    return desc;
end

---AceConfig args for the settings group (built by settings.lua once the addon is loaded).
---@return table
function _addon.AssumedTargetAuraSettings()
    local args = {
        desc = {
            order = 0,
            type = "description",
            name = L["Aura data is hidden from addons in combat, when debuffs are on your target, so the addon doesn't read your target's auras. Choose the target auras to include in the calculations instead. They apply to every target."],
        },
        clearAll = {
            order = 1,
            type = "execute",
            name = L["Clear all"],
            func = function()
                SpellCalc_settings.assumedTargetAuras = {};
                _addon:UpdateAssumedTargetAuras();
            end,
        },
    };

    ---@type table<string, AssumableTargetAura[]>
    local byClass = {};
    for _, aura in ipairs(_addon.assumableTargetAuras or {}) do
        -- "From caster" debuffs (Shadow Weaving, Improved Scorch, Stormstrike, ...) only boost the
        -- caster's own damage, so another class assuming them would get a bonus it never has.
        if not aura.fromCaster or aura.class == playerClass then
            byClass[aura.class] = byClass[aura.class] or {};
            table.insert(byClass[aura.class], aura);
        end
    end

    for order, class in ipairs(CLASS_ORDER) do
        local list = byClass[class];
        if list then
            local group = {
                order = 10 + order,
                type = "group",
                inline = true,
                name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class,
                args = {},
            };
            for i, aura in ipairs(list) do
                local spellId, maxStacks = aura.spellId, aura.maxStacks;
                local option = {
                    order = i,
                    name = AuraName(spellId),
                    desc = function() return AuraDesc(spellId) end,
                };
                if maxStacks > 1 then
                    option.type = "range";
                    option.min = 0;
                    option.max = maxStacks;
                    option.step = 1;
                    option.get = function() return SpellCalc_settings.assumedTargetAuras[spellId] or 0 end;
                    option.set = function(_, value)
                        SpellCalc_settings.assumedTargetAuras[spellId] = value > 0 and value or nil;
                        _addon:UpdateAssumedTargetAuras();
                    end;
                else
                    option.type = "toggle";
                    option.get = function() return SpellCalc_settings.assumedTargetAuras[spellId] ~= nil end;
                    option.set = function(_, value)
                        SpellCalc_settings.assumedTargetAuras[spellId] = value and 1 or nil;
                        _addon:UpdateAssumedTargetAuras();
                    end;
                end
                group.args["aura" .. spellId] = option;
            end
            args["class" .. class] = group;
        end
    end

    return args;
end

_addon.events.Register("PLAYER_ENTERING_WORLD", function() _addon:UpdateAssumedTargetAuras() end);
