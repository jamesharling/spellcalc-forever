---@class AddonEnv
local _A = select(2, ...);

-- World of Warcraft: Forever runs on the Mainline (retail-style) client. The classic global
-- functions this addon was written against (GetSpellInfo, GetItemInfo, UnitAura, ...) no
-- longer exist there. This file wraps the C_* replacements so they return the classic-style
-- values; files that need one declare a file-local alias, e.g.
--     local GetSpellInfo = _addon.api.GetSpellInfo;
-- It also holds the secret-value helpers (Midnight-style combat restrictions, see system/combat.lua).

local api = {};
_A.api = api;

local issecretvalue = issecretvalue;

---True if the value is a secret value that tainted code may not inspect.
---@param v any
---@return boolean
function api.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true;
end

---Return the value, or `fallback` if it is a secret value.
---@generic T
---@param v T
---@param fallback T|nil
---@return T|nil
function api.Unsecret(v, fallback)
    if v == nil or api.IsSecret(v) then
        return fallback;
    end
    return v;
end

---Classic-style GetSpellInfo on top of C_Spell.GetSpellInfo.
---Returns nil if the spell does not exist on this client.
---@param spellIdentifier integer|string
---@return string|nil name, nil rank, integer|nil icon, number|nil castTime, number|nil minRange, number|nil maxRange, integer|nil spellID, integer|nil originalIcon
function api.GetSpellInfo(spellIdentifier)
    if spellIdentifier == nil then return nil end
    local info = C_Spell.GetSpellInfo(spellIdentifier);
    if not info then return nil end
    return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIconID;
end

---Spell name only.
---@param spellIdentifier integer|string
---@return string|nil
function api.GetSpellName(spellIdentifier)
    if spellIdentifier == nil then return nil end
    return C_Spell.GetSpellName(spellIdentifier);
end

---Spell subtext (rank text).
---@param spellIdentifier integer|string
---@return string|nil
function api.GetSpellSubtext(spellIdentifier)
    if spellIdentifier == nil then return nil end
    return C_Spell.GetSpellSubtext(spellIdentifier);
end

---Power cost table, same shape as the classic GetSpellPowerCost.
---@param spellIdentifier integer|string
---@return table[]|nil
function api.GetSpellPowerCost(spellIdentifier)
    if spellIdentifier == nil then return nil end
    return C_Spell.GetSpellPowerCost(spellIdentifier);
end

---Item info, same returns as the classic GetItemInfo.
---@param itemInfo integer|string
function api.GetItemInfo(itemInfo)
    if itemInfo == nil then return nil end
    return C_Item.GetItemInfo(itemInfo);
end

---Spell ID of the spellbook entry matching a spell name (classic `select(2, GetSpellBookItemInfo(name))`).
---@param spellName string|nil
---@return integer|nil
function api.GetSpellBookSpellID(spellName)
    if not spellName or not C_SpellBook or not C_SpellBook.FindSpellBookSlotForSpell then return nil end
    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(spellName);
    if not slot then return nil end
    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank or Enum.SpellBookSpellBank.Player);
    return info and info.spellID or nil;
end
