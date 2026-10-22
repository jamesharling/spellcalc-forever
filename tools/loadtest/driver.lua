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

for _, id in ipairs(sampleIds) do
    emit(("sample %s [%d]: %s | with talents %s"):format(name(id), id, baseSamples[id], sampleLine(id)))
end

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
