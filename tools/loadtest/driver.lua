-- Test driver, run after all addon files are loaded. Returns a report as one string.
-- Lines starting with FAIL make the class fail; DETAIL lines are shown with --verbose only.

local A = __ADDON_TABLE
local ADDON = __ADDON_NAME
local out = {}
local function emit(s) out[#out + 1] = s end

local function isBad(v) return type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) end

local function settle()
    __RunTimers(60)
    __TickOnUpdate(10, 0.1)  -- the addon invalidates its calculation cache from an OnUpdate script
    __RunTimers(60)
end

-- Saved settings from before the action bar text rework (version 3, percent position): must migrate.
if not __UNSUPPORTED then
    SpellCalc_settings = { version = 3, abPosition = 50, firstStart = false }
end

-- Login sequence
__FireEvent("ADDON_LOADED", ADDON)
__FireEvent("PLAYER_LOGIN")
__FireEvent("PLAYER_ENTERING_WORLD", true, false)
__FireEvent("SPELLS_CHANGED")
settle()

if not A.spellInfo then
    emit("FAIL no spell data loaded for " .. __CLASS)
    return table.concat(out, "\n")
end

if __UNSUPPORTED then
    -- Warrior, hunter and rogue have no data; the addon disables its events for them. The tooltip hook is
    -- still registered, so it must cope with any spell.
    local hooks = 0
    for _, pc in ipairs(__TOOLTIP_POSTCALLS) do
        if pc.kind == Enum.TooltipDataType.Spell then
            hooks = hooks + 1
            for _, id in ipairs({ 133, 116, 6603, 78, 1752 }) do
                GameTooltip:ClearLines()
                local ok, err = xpcall(pc.fn, debug.traceback, GameTooltip, { id = id, type = Enum.TooltipDataType.Spell })
                if not ok then emit("FAIL tooltip hook error on spell " .. id .. ": " .. tostring(err):gsub("\n.*", "")) end
                if GameTooltip:NumLines() > 0 then emit("FAIL tooltip hook added lines for an unsupported class") end
            end
        end
    end
    emit(("unsupported class: %d spells in data, %d tooltip hooks ran without adding lines"):format(next(A.spellInfo) and 1 or 0, hooks))
    return table.concat(out, "\n")
end

local spellIds = {}
for id in pairs(A.spellInfo) do spellIds[#spellIds + 1] = id end
table.sort(spellIds)

local EFFECT_FIELDS = { "min", "max", "avg", "minCrit", "maxCrit", "avgCrit", "avgCombined", "avgAfterMitigation",
    "perSec", "perResource", "doneToOom", "spellPower", "effectivePower", "effectiveSpCoef", "modBase", "modBonus" }
local SPELL_FIELDS = { "critChance", "critMult", "hitChance", "effectiveCost", "effCastTime", "avgResist", "gcd" }

---Calculate one spell and validate the numbers.
---@return string status ok|nil|error|bad
---@return any detail
local function checkSpell(id)
    local ok, cs = xpcall(SpellCalc.GetSpell, debug.traceback, id)
    if not ok then return "error", cs end
    if not cs then return "nil" end
    for _, f in ipairs(SPELL_FIELDS) do
        if isBad(cs[f]) then return "bad", ("%s = %s"):format(f, tostring(cs[f])) end
    end
    for i, e in ipairs(cs.effects or {}) do
        for _, f in ipairs(EFFECT_FIELDS) do
            if isBad(e[f]) then return "bad", ("effect %d %s = %s"):format(i, f, tostring(e[f])) end
        end
        if type(e.min) == "number" and type(e.max) == "number" and e.min > e.max + 1e-6 then
            return "bad", ("effect %d min %s > max %s"):format(i, e.min, e.max)
        end
    end
    return "ok", cs
end

local spellPostCalls = {}
for _, pc in ipairs(__TOOLTIP_POSTCALLS) do
    if pc.kind == Enum.TooltipDataType.Spell then spellPostCalls[#spellPostCalls + 1] = pc.fn end
end

---Run the spell tooltip hooks for a spell, return number of lines added or an error.
local function tooltipFor(id)
    GameTooltip:ClearLines()
    for _, fn in ipairs(spellPostCalls) do
        local ok, err = xpcall(fn, debug.traceback, GameTooltip, { id = id, type = Enum.TooltipDataType.Spell })
        if not ok then return nil, err end
    end
    return GameTooltip:NumLines()
end

local function name(id)
    local n = __SPELL_NAMES[id] or ("spell " .. id)
    local sub = __SPELL_SUBTEXT[id]
    return (sub and sub ~= "") and (n .. " (" .. sub .. ")") or n
end

---Calculate all spells; returns counts and a value snapshot per spell.
local function runAll(phase)
    local counts = { ok = 0, ["nil"] = 0, error = 0, bad = 0, tooltipLines = 0, tooltipErrors = 0, noTooltip = 0 }
    local snapshot = {}
    local shown = 0
    for _, id in ipairs(spellIds) do
        local status, detail = checkSpell(id)
        counts[status] = counts[status] + 1
        if status == "ok" then
            local e = detail.effects and detail.effects[1]
            snapshot[id] = e and e.avgCombined or 0
        elseif status ~= "nil" and shown < 8 then
            shown = shown + 1
            local msg = tostring(detail):gsub("\n.*", "")
            emit(("FAIL [%s] %s %d %s: %s"):format(phase, status, id, name(id), msg))
        end
        local lines, terr = tooltipFor(id)
        if terr then
            counts.tooltipErrors = counts.tooltipErrors + 1
            if counts.tooltipErrors <= 5 then emit(("FAIL [%s] tooltip error %d %s: %s"):format(phase, id, name(id), tostring(terr):gsub("\n.*", ""))) end
        elseif lines == 0 then
            counts.noTooltip = counts.noTooltip + 1
        else
            counts.tooltipLines = counts.tooltipLines + lines
        end
    end
    emit(("[%s] %d spells: %d ok, %d not handled, %d errors, %d bad numbers; tooltips: %d errors, %d without lines, %d lines total")
        :format(phase, #spellIds, counts.ok, counts["nil"], counts.error, counts.bad, counts.tooltipErrors, counts.noTooltip, counts.tooltipLines))
    return snapshot
end

-- Highest-level ranks of a few signature spells per class, for a readable sample.
local SAMPLES = {
    MAGE = { "Fireball", "Frostbolt", "Arcane Missiles" },
    PRIEST = { "Greater Heal", "Mind Blast", "Power Word: Shield" },
    DRUID = { "Healing Touch", "Starfire", "Rejuvenation" },
    PALADIN = { "Holy Light", "Flash of Light", "Holy Shock" },
    SHAMAN = { "Lightning Bolt", "Healing Wave", "Chain Heal" },
    WARLOCK = { "Shadow Bolt", "Immolate", "Corruption" },
}
local sampleIds = {}
for _, wanted in ipairs(SAMPLES[__CLASS] or {}) do
    local best, bestLevel
    for _, id in ipairs(spellIds) do
        local info = A.spellInfo[id]
        if __SPELL_NAMES[id] == wanted and (not bestLevel or info.spellLevel > bestLevel) then best, bestLevel = id, info.spellLevel end
    end
    if best then sampleIds[#sampleIds + 1] = best end
end

local function sampleLine(id)
    local status, cs = checkSpell(id)
    if status ~= "ok" then return status end
    local e = cs.effects[1]
    -- Spells that only trigger other spells (Holy Shock) carry the numbers in the triggered spell.
    if e.spellData and (e.avgCombined or 0) == 0 then
        cs = e.spellData
        e = cs.effects[1]
    end
    return ("%.0f-%.0f avg %.0f, crit %.1f%%"):format(e.min or 0, e.max or 0, e.avgCombined or 0, cs.critChance or 0)
end

local base = runAll("no talents")

-- The options table must pass AceConfig validation (it is only validated when the panel opens in game)
do
    local registry = LibStub("AceConfigRegistry-3.0")
    local ok, err = pcall(registry.GetOptionsTable, registry, ADDON, "dialog", "AceConfigDialog-3.0")
    if ok then emit("settings options table passes AceConfig validation")
    else emit("FAIL settings options table invalid: " .. tostring(err):gsub("\n.*", "")) end
end

-- Settings migration (version 3 -> current)
do
    local sv = SpellCalc_settings
    local expectedY = math.floor(50 * 0.36 + 0.5) - 6
    if sv.abPosition ~= nil or sv.abAnchor ~= "BOTTOM" or sv.abOffsetY ~= expectedY or (sv.version or 0) < 4 then
        emit(("FAIL settings migration: abPosition=%s abAnchor=%s abOffsetY=%s version=%s"):format(
            tostring(sv.abPosition), tostring(sv.abAnchor), tostring(sv.abOffsetY), tostring(sv.version)))
    else
        emit(("settings migrated to version %d (old 50%% position -> BOTTOM %+d px)"):format(sv.version, sv.abOffsetY))
    end
end

-- Action bar text: put calculated spells on the first 12 stock slots
do
    local abv = A.ActionBarValues
    local slotted = 0
    for _, id in ipairs(spellIds) do
        if slotted == 12 then break end
        if id ~= 6603 then
            slotted = slotted + 1
            __ACTION_SLOTS[slotted] = id
        end
    end
    for slot = 1, slotted do __FireEvent("ACTIONBAR_SLOT_CHANGED", slot) end
    __TickOnUpdate(50, 0.1) -- delayed full slot update after 3s, then the update loop
    local shown = 0
    for slot = 1, slotted do
        local text = abv:GetSlotText(slot)
        if text and text ~= "" then shown = shown + 1 end
    end
    emit(("action bar: %d of %d slotted spells show a value"):format(shown, slotted))
    if shown == 0 then emit("FAIL no action bar values shown") end

    -- The text must live on an overlay frame above the button's cooldown frame
    local button = _G.ActionButton1
    local fs, overlay
    for _, child in ipairs(button.__children) do
        for _, region in ipairs(child.__children or {}) do
            if region.__kind == "FontString" then fs, overlay = region, child end
        end
    end
    if not fs then
        emit("FAIL no action bar font string found on ActionButton1")
    else
        local ok = overlay:GetFrameLevel() > button.cooldown:GetFrameLevel()
        emit(("action bar text on an overlay at frame level %d, cooldown at %d"):format(overlay:GetFrameLevel(), button.cooldown:GetFrameLevel()))
        if not ok then emit("FAIL action bar text is not above the cooldown frame") end

        -- Every anchor and font style must apply
        local styleErrors = 0
        for _, anchor in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
            for _, flags in ipairs({ "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROME", "MONOCHROME,OUTLINE", "MONOCHROME,THICKOUTLINE" }) do
                for _, shadow in ipairs({ false, true }) do
                    SpellCalc_settings.abAnchor, SpellCalc_settings.abFontFlags, SpellCalc_settings.abShadow = anchor, flags, shadow
                    SpellCalc_settings.abOffsetX, SpellCalc_settings.abOffsetY = -4, 7
                    local okStyle, err = pcall(abv.UpdateStyle, abv)
                    local p = fs.__point
                    local expectedFlags = flags == "NONE" and "" or flags
                    if not okStyle or not p or p[1] ~= anchor or p[3] ~= anchor or p[4] ~= -4 or p[5] ~= 7
                        or fs.__flags ~= expectedFlags or (shadow and fs.__shadowOffset[1] == 0) or (not shadow and fs.__shadowOffset[1] ~= 0) then
                        styleErrors = styleErrors + 1
                        if styleErrors <= 3 then emit(("FAIL style %s/%s/%s not applied: %s"):format(anchor, flags, tostring(shadow), tostring(err))) end
                    end
                end
            end
        end
        emit(("action bar styles: %d anchor/outline/shadow combinations checked, %d wrong"):format(9 * 6 * 2, styleErrors))
    end
end

local baseSamples = {}
for _, id in ipairs(sampleIds) do baseSamples[id] = sampleLine(id) end

-- All talents at max rank through the simulated trait API
local talentCount = 0
for i, t in ipairs(A.talentDataRaw or {}) do
    __TALENT_TREE[i] = { spellId = t.spellId, maxRanks = t.maxRanks or 5 }
    __TALENT_RANKS[t.spellId] = t.maxRanks or 5
    talentCount = talentCount + 1
end
__FireEvent("TRAIT_CONFIG_UPDATED", 4001)
settle()

local applied = 0
for _, t in ipairs(A.talentDataRaw or {}) do
    if A.GetTalentRankBySpellId and A:GetTalentRankBySpellId(t.spellId) > 0 then applied = applied + 1 end
end
emit(("talents: %d in data, %d read back as learned through the trait API"):format(talentCount, applied))
if talentCount > 0 and applied ~= talentCount then emit("FAIL talents not all read back from the trait API") end

local talented = runAll("all talents")
local changed = 0
for id, v in pairs(talented) do
    if base[id] and math.abs(base[id] - v) > 1e-6 then changed = changed + 1 end
end
emit(("talents changed the average of %d spells"):format(changed))

local talentSamples = {}
for _, id in ipairs(sampleIds) do talentSamples[id] = sampleLine(id) end

-- Assumed target auras, set through the generated settings options like a player would
local settingsArgs = A.AssumedTargetAuraSettings and A.AssumedTargetAuraSettings() or {}
local offered, enabled = 0, 0
for key, group in pairs(settingsArgs) do
    if type(group) == "table" and group.type == "group" then
        for _, option in pairs(group.args) do
            offered = offered + 1
            local ok, err = pcall(function()
                if option.type == "range" then option.set(nil, option.max) else option.set(nil, true) end
                local v = option.get()
                if not v or v == 0 then error("option " .. tostring(option.name) .. " did not keep its value") end
                if type(option.desc) == "function" then option.desc() end
            end)
            if ok then enabled = enabled + 1 else emit("FAIL target aura option in " .. key .. ": " .. tostring(err)) end
        end
    end
end
settle()
local withAuras = runAll("assumed target auras")
local auraChanged = 0
for id, v in pairs(withAuras) do
    if talented[id] and math.abs(talented[id] - v) > 1e-6 then auraChanged = auraChanged + 1 end
end
emit(("target auras: %d offered to this class, %d enabled through the options, changed the average of %d spells"):format(offered, enabled, auraChanged))
if offered > 0 and auraChanged == 0 then emit("FAIL assumed target auras changed no spell") end

for _, id in ipairs(sampleIds) do
    emit(("sample %s [%d]: %s | talents %s | + target auras %s"):format(name(id), id, baseSamples[id], talentSamples[id], sampleLine(id)))
end

-- Clearing them must restore the talent-only numbers
if settingsArgs.clearAll then settingsArgs.clearAll.func() end
settle()
local cleared = runAll("target auras cleared")
local notRestored = 0
for id, v in pairs(cleared) do
    if talented[id] and math.abs(talented[id] - v) > 1e-6 then notRestored = notRestored + 1 end
end
if notRestored > 0 then emit(("FAIL %d spells differ after clearing the target auras"):format(notRestored)) end

-- A few player buffs from the generated aura data through the C_UnitAuras path
local auraIds = {}
for id in pairs(A.aurasPlayer or {}) do auraIds[#auraIds + 1] = id end
table.sort(auraIds)
local auraList = {}
for i = 1, math.min(25, #auraIds) do
    local id = auraIds[math.floor(i * #auraIds / 26) + 1]
    auraList[#auraList + 1] = { name = __SPELL_NAMES[id] or ("spell " .. id), spellId = id, applications = 1,
        sourceUnit = "player", auraInstanceID = i, duration = 0, expirationTime = 0, isHelpful = true }
end
__AURAS.player = auraList
__FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
settle()
runAll("with " .. #auraList .. " buffs")

return table.concat(out, "\n")
