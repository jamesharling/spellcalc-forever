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

local spellPostCalls, macroPostCalls = {}, {}
for _, pc in ipairs(__TOOLTIP_POSTCALLS) do
    if pc.kind == Enum.TooltipDataType.Spell then spellPostCalls[#spellPostCalls + 1] = pc.fn end
    if pc.kind == Enum.TooltipDataType.Macro then macroPostCalls[#macroPostCalls + 1] = pc.fn end
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

-- Macros: bar values and Macro tooltips must show the macro's current spell
do
    local abv = A.ActionBarValues
    local spellA, spellB = __ACTION_SLOTS[1], __ACTION_SLOTS[2]
    local textA, textB = abv:GetSlotText(1), abv:GetSlotText(2)
    __MACROS[3] = spellA
    __ACTION_SLOTS[25] = { "macro", spellA, "spell" } -- macro 3, currently casting spell A
    __ACTION_SLOTS[26] = { "macro", 3, "" }            -- a macro that casts no spell right now
    __FireEvent("ACTIONBAR_SLOT_CHANGED", 25)
    __FireEvent("ACTIONBAR_SLOT_CHANGED", 26)
    __TickOnUpdate(10, 0.1)
    local macroText, emptyText = abv:GetSlotText(25), abv:GetSlotText(26)
    -- The macro's conditions switch it to spell B; the client signals that with slot 0 (every slot)
    __ACTION_SLOTS[25] = { "macro", spellB, "spell" }
    __FireEvent("ACTIONBAR_SLOT_CHANGED", 0)
    __TickOnUpdate(10, 0.1)
    local switchedText = abv:GetSlotText(25)
    emit(("macros: bar value %s (spell %s), %s after switching (spell %s), %q for a macro without a spell")
        :format(tostring(macroText), tostring(textA), tostring(switchedText), tostring(textB), tostring(emptyText or "")))
    if not macroText or macroText == "" or macroText ~= textA then emit("FAIL macro slot doesn't show its spell's value") end
    if switchedText ~= textB then emit("FAIL macro slot not updated after ACTIONBAR_SLOT_CHANGED 0") end
    if emptyText and emptyText ~= "" then emit("FAIL macro without a spell shows a value") end

    -- Tooltips: on the button (its action reports spell B), and elsewhere (macro 3 -> GetMacroSpell -> spell A)
    local function macroTooltip(owner)
        GameTooltip:ClearLines()
        GameTooltip:SetOwner(owner)
        for _, fn in ipairs(macroPostCalls) do
            local ok, err = xpcall(fn, debug.traceback, GameTooltip, { id = 3, type = Enum.TooltipDataType.Macro })
            if not ok then return nil, err end
        end
        return GameTooltip:NumLines()
    end
    local button = CreateFrame("Button")
    button.action = 25
    local onButton, err1 = macroTooltip(button)
    local elsewhere, err2 = macroTooltip(UIParent)
    GameTooltip:SetOwner(nil)
    local linesA, linesB = tooltipFor(spellA), tooltipFor(spellB)
    emit(("macro tooltips: %s lines on the button (spell %d lines), %s elsewhere (spell %d lines)")
        :format(tostring(onButton), linesB, tostring(elsewhere), linesA))
    if err1 or err2 then emit("FAIL macro tooltip error: " .. (tostring(err1 or err2):gsub("\n.*", ""))) end
    if onButton ~= linesB or elsewhere ~= linesA or linesA == 0 then emit("FAIL macro tooltips don't show the macro's spell") end
    __ACTION_SLOTS[25], __ACTION_SLOTS[26], __MACROS[3] = nil, nil, nil
    __FireEvent("ACTIONBAR_SLOT_CHANGED", 0)
end

-- Action bars 6-8 (slots 145-180): first and last slot of each
do
    local abv = A.ActionBarValues
    local slots = { 145, 156, 157, 168, 169, 180 }
    for i, slot in ipairs(slots) do
        __ACTION_SLOTS[slot] = __ACTION_SLOTS[i]
        __FireEvent("ACTIONBAR_SLOT_CHANGED", slot)
    end
    __TickOnUpdate(10, 0.1)
    local shown = 0
    for i, slot in ipairs(slots) do
        local text = abv:GetSlotText(slot)
        if text and text ~= "" and text == abv:GetSlotText(i) then shown = shown + 1 end
    end
    emit(("action bars 6-8: %d of %d slots show their spell's value"):format(shown, #slots))
    if shown ~= #slots then emit("FAIL action bars 6-8 don't show values") end
    for _, slot in ipairs(slots) do __ACTION_SLOTS[slot] = nil end
    __FireEvent("ACTIONBAR_SLOT_CHANGED", 0)
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
local buffed = runAll("with " .. #auraList .. " buffs")

-- Equipped items: the class's tier 0 set (hotfix-only items, see hotfixItems.json), then every item with
-- effects in the data, then nothing again, which must restore the numbers.
local ARMOR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
local TIER0 = { MAGE = "Magister's Regalia", PRIEST = "Vestments of the Devout", WARLOCK = "Dreadmist Raiment",
    DRUID = "Wildheart Raiment", SHAMAN = "The Elements", PALADIN = "Lightforge Armor" }
local function equip(itemIds)
    __INVENTORY = {}
    for i, itemId in ipairs(itemIds) do __INVENTORY[ARMOR_SLOTS[i]] = itemId end
    __FireEvent("UNIT_INVENTORY_CHANGED", "player")
    settle()
end

local setId
for id, set in pairs(A.itemSetData or {}) do
    if set.name == TIER0[__CLASS] then setId = id end
end
if not setId then
    emit("FAIL tier 0 set " .. tostring(TIER0[__CLASS]) .. " not in the data")
else
    local setItems = {}
    for itemId, id in pairs(A.setItemData) do
        if id == setId then setItems[#setItems + 1] = itemId end
    end
    table.sort(setItems)
    local expected = 0
    for _, effect in ipairs(A.itemSetData[setId].effects) do
        if effect.need <= #setItems and effect.type == A.CONST.EFFECT_TYPE.MOD_MANA_PER_5 then expected = expected + effect.value end
    end
    local mp5Before = A.stats.mp5.val
    equip(setItems)
    runAll("with " .. TIER0[__CLASS])
    local gained = A.stats.mp5.val - mp5Before
    emit(("set: %d pieces of %s [%d] equipped, mp5 +%d from its bonuses"):format(#setItems, TIER0[__CLASS], setId, gained))
    if gained ~= expected or expected == 0 then emit(("FAIL %s gave mp5 +%d, expected +%d"):format(TIER0[__CLASS], gained, expected)) end
end

local effectItems = {}
for itemId in pairs(A.itemEffects or {}) do effectItems[#effectItems + 1] = itemId end
table.sort(effectItems)
local itemChanged = {}
for first = 1, #effectItems, #ARMOR_SLOTS do
    local batch = {}
    for i = first, math.min(first + #ARMOR_SLOTS - 1, #effectItems) do batch[#batch + 1] = effectItems[i] end
    equip(batch)
    for id, v in pairs(runAll(("with item effects %d-%d"):format(first, first + #batch - 1))) do
        if buffed[id] and math.abs(buffed[id] - v) > 1e-6 then itemChanged[id] = true end
    end
end
local changedCount = 0
for _ in pairs(itemChanged) do changedCount = changedCount + 1 end
emit(("item effects: %d items equipped in batches of %d, changed the average of %d spells"):format(#effectItems, #ARMOR_SLOTS, changedCount))

equip({})
local unequipped = runAll("items removed")
local itemsNotRestored = 0
for id, v in pairs(unequipped) do
    if buffed[id] and math.abs(buffed[id] - v) > 1e-6 then itemsNotRestored = itemsNotRestored + 1 end
end
if itemsNotRestored > 0 then emit(("FAIL %d spells differ after removing all items"):format(itemsNotRestored)) end

-- Targets: a readable one, then the same target with secret identity (inside instances, in combat).
-- Secret values must be treated as unknown and never stored.
local function selectTarget(t)
    __TARGET = t
    __FireEvent("PLAYER_TARGET_CHANGED")
    settle()
end
local function targetState()
    local T = A.Target
    return ("level %s (diff %s), creature type %s, class %s, player %s"):format(tostring(T.level), tostring(T.levelDiff),
        tostring(T.creatureType), tostring(T.class), tostring(T.isPlayer))
end
local dummy = { name = "Risen Guard", level = 62, creatureType = { "Undead", 6 }, class = "WARRIOR", isPlayer = false }
selectTarget(dummy)
runAll("readable target")
emit("readable target: " .. targetState())
if A.Target.level ~= 62 or A.Target.levelDiff ~= 2 or A.Target.creatureType ~= 6 or A.Target.class ~= "WARRIOR" then
    emit("FAIL readable target not read correctly: " .. targetState())
end

dummy.secret = true
selectTarget(dummy)
runAll("secret target")
emit("secret target: " .. targetState())
for k, v in pairs(A.Target) do
    if issecretvalue(v) then emit("FAIL secret value stored in Target." .. tostring(k)) end
end
local defaultLevel = UnitLevel("player") + SpellCalc_settings.defaultTargetLvlOffset
if A.Target.level ~= defaultLevel or A.Target.creatureType ~= nil or A.Target.class ~= nil then
    emit("FAIL secret target not treated as unknown: " .. targetState())
end
selectTarget(nil)

-- A Mythic+ run: an addon restriction outside combat. Auras and stats turn secret and the aura API raises
-- an error. The addon must keep its last snapshot, then resync when the restriction lifts, without
-- combat ending.
local CHALLENGE = Enum.AddOnRestrictionType.ChallengeMode
local beforeRestriction = runAll("before restriction")
__RESTRICTIONS[CHALLENGE] = true
__FireEvent("ADDON_RESTRICTION_STATE_CHANGED", CHALLENGE, Enum.AddOnRestrictionState.Active)
__AURAS.player = {} -- the buffs run out meanwhile
for _, event in ipairs({ "UNIT_AURA", "UNIT_STATS", "SPELL_POWER_CHANGED", "COMBAT_RATING_UPDATE", "UNIT_ATTACK_POWER" }) do
    __FireEvent(event, "player")
end
settle()
local underRestriction = runAll("restricted (Mythic+)")
local changedUnder = 0
for id, v in pairs(underRestriction) do
    if beforeRestriction[id] and math.abs(beforeRestriction[id] - v) > 1e-6 then changedUnder = changedUnder + 1 end
end
__RESTRICTIONS = {}
__FireEvent("ADDON_RESTRICTION_STATE_CHANGED", CHALLENGE, Enum.AddOnRestrictionState.Inactive)
settle()
local lifted = runAll("restriction lifted")
local notResynced = 0
for id, v in pairs(lifted) do
    if cleared[id] and math.abs(cleared[id] - v) > 1e-6 then notResynced = notResynced + 1 end
end
emit(("restriction: %d spells changed while restricted, %d differ from the unbuffed numbers after it lifted"):format(changedUnder, notResynced))
if changedUnder > 0 then emit("FAIL numbers changed while restricted instead of keeping the last snapshot") end
if notResynced > 0 then emit("FAIL no resync after the restriction lifted (buffs that ran out still count)") end
__AURAS.player = auraList

return table.concat(out, "\n")
