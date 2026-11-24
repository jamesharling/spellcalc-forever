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

-- Indexing a table with a secret value raises an error on the client; make the addon's lookup tables do the
-- same here (see __TrapSecretKeys in wow_env.lua).
for _, t in pairs({ A.spellInfo, A.aurasPlayer, A.aurasTarget, A.enchantData, A.itemEffects, A.itemSetData, A.setItemData,
    A.levelDefaultArmor, A.CONST.JUDGEMENT_IDS, A.CONST.STANCE_SPELLS, A.Target and A.Target.resistanceBase }) do
    __TrapSecretKeys(t)
end
for _, t in pairs(A.stats or {}) do
    if type(t) == "table" then
        __TrapSecretKeys(t)
        for _, inner in pairs(t) do __TrapSecretKeys(inner) end
    end
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
    local itemSpells = 0
    for _ in pairs(A.itemUseSpells or {}) do itemSpells = itemSpells + 1 end
    if itemSpells > 0 then emit("FAIL item use spells loaded for an unsupported class") end
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

-- node run.js --classes DRUID --dump: what the addon shows for the highest rank of every spell, to read through
-- a class' spell book. Level 60, 400 spell power, 800 attack power, no talents (see wow_env.lua).
if __DUMP then
    -- The top rank of every name: by rank number, then by spell level. Two spells can share a name and rank (a
    -- channel and the spell it triggers every tick, such as Arcane Missiles); both are printed.
    local function rankOf(id)
        return tonumber(name(id):match("%(Rank (%d+)%)")) or 0
    end
    local top = {}
    for _, id in ipairs(spellIds) do
        local n = __SPELL_NAMES[id] or ("spell " .. id)
        local cur = top[n]
        local rank, level = rankOf(id), A.spellInfo[id].spellLevel
        if not cur or rank > cur.rank or (rank == cur.rank and rank == 0 and level > cur.level) then
            top[n] = { rank = rank, level = level, ids = { id } }
        elseif rank == cur.rank and rank > 0 then
            cur.ids[#cur.ids + 1] = id
        end
    end
    local dumpIds = {}
    for _, entry in pairs(top) do
        for _, id in ipairs(entry.ids) do dumpIds[#dumpIds + 1] = id end
    end
    table.sort(dumpIds, function(a, b)
        if name(a) ~= name(b) then return name(a) < name(b) end
        return a < b
    end)
    for _, id in ipairs(dumpIds) do
        local status, cs = checkSpell(id)
        emit(("DUMP %s [%d] %s"):format(name(id), id, status == "ok" and "" or status))
        if status == "ok" then
            for i, e in ipairs(cs.effects) do
                emit(("DUMP     effect %d: %s-%s avg %s, with crits %s, ticks %s, sp coef %s, ap coef %s, flags %s")
                    :format(i, tostring(e.min), tostring(e.max), tostring(e.avg), tostring(e.avgCombined), tostring(e.ticks),
                        tostring(e.effectiveSpCoef), tostring(e.effectiveApCoef), tostring(e.effectFlags)))
            end
            tooltipFor(id)
            for _, line in ipairs(GameTooltip.__lines) do
                emit("DUMP     | " .. line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            end
        end
    end
end

-- Paladin seals. Seal of Righteousness: the rank's base points / 100 * weapon speed * 0.85 with a one-hander or
-- * 1.2 with a two-hander, plus 7.65% or 12% of spell power. Seal of Fury: its proc's base value plus 10% of spell
-- power on every swing, whatever the weapon. Seal of Command: 70% of a weapon hit plus 29% of spell power. Improved
-- Seals multiplies the Seal of Righteousness and Seal of Fury procs. Judgement uses the active seal's judgement.
if __CLASS == "PALADIN" then
    local abv = A.ActionBarValues
    local function avgOf(id)
        local status, cs = checkSpell(id)
        if status ~= "ok" then return nil, status .. ": " .. tostring(cs) end
        return cs.effects[1].avg, cs
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
    local function wield(itemId)
        __INVENTORY[16] = itemId
        __FireEvent("UNIT_INVENTORY_CHANGED", "player")
        settle()
    end
    local function setLevel(level)
        __PLAYER_LEVEL = level
        __FireEvent("PLAYER_LEVEL_UP", level)
        settle()
    end
    local function setSpellPower(sp)
        __SPELL_POWER = sp
        __FireEvent("SPELL_POWER_CHANGED")
        settle()
    end
    local function data(id) return A.spellInfo[id] and A.spellInfo[id].effects[1] end
    __WEAPONS[90001] = { subclass = Enum.ItemWeaponSubclass.Mace2H, low = 5, high = 9, speed = 2.9 }
    __WEAPONS[90002] = { subclass = Enum.ItemWeaponSubclass.Mace1H, low = 3, high = 7, speed = 2.6 }

    -- Level 1 without spell power, the case that showed 0
    local spBefore = __SPELL_POWER
    setLevel(1)
    setSpellPower(0)
    wield(90001)
    local low2h, err1 = avgOf(21084)
    __ACTION_SLOTS[31] = 21084
    __FireEvent("ACTIONBAR_SLOT_CHANGED", 31)
    __TickOnUpdate(10, 0.1)
    local barText = abv:GetSlotText(31)
    wield(90002)
    local low1h, err2 = avgOf(21084)
    emit(("seals: level 1, no spell power: Seal of Righteousness rank 1 %s with a 2.90 two-hander (bar %s), %s with a 2.60 one-hander")
        :format(low2h and ("%.2f"):format(low2h) or tostring(err1), tostring(barText), low1h and ("%.2f"):format(low1h) or tostring(err2)))
    if not near(low2h, 108 / 100 * 1.2 * 2.9) then emit("FAIL Seal of Righteousness rank 1 with a two-hander: " .. tostring(low2h or err1)) end
    if not near(low1h, 108 / 100 * 0.85 * 2.6) then emit("FAIL Seal of Righteousness rank 1 with a one-hander: " .. tostring(low1h or err2)) end
    if barText ~= "4" then emit("FAIL Seal of Righteousness bar value at level 1 is " .. tostring(barText) .. ", expected 4") end

    -- Level 60 with 400 spell power: rank 8 has base points 1786 + 2 levels * 47
    setLevel(60)
    setSpellPower(400)
    local sor1h = avgOf(20293)
    local sof1h = avgOf(1311649)
    wield(90001)
    local sor2h = avgOf(20293)
    local sof2h = avgOf(1311649)
    local socStatus, soc = checkSpell(20375)
    local sofData, socData = data(1311649), data(20375)
    local sofExpected = sofData and sofData.valueBase + sofData.coef * 400 or -1
    local socMin = socData and socData.weaponCoef * 100 + socData.coef * 400 or -1 -- UnitDamage gives 100-150
    local socMax = socData and socData.weaponCoef * 150 + socData.coef * 400 or -1
    emit(("seals: level 60, 400 spell power: Seal of Righteousness rank 8 %.2f (one-hander) / %.2f (two-hander), Seal of Fury rank 1 %.2f / %.2f, Seal of Command rank 1 %s")
        :format(sor1h or -1, sor2h or -1, sof1h or -1, sof2h or -1,
            socStatus == "ok" and ("%.1f-%.1f"):format(soc.effects[1].min, soc.effects[1].max) or socStatus))
    if not near(sor1h, 18.8 * 0.85 * 2.6 + 0.0765 * 400) then emit("FAIL Seal of Righteousness rank 8 with a one-hander: " .. tostring(sor1h)) end
    if not near(sor2h, 18.8 * 1.2 * 2.9 + 0.12 * 400) then emit("FAIL Seal of Righteousness rank 8 with a two-hander: " .. tostring(sor2h)) end
    if sofExpected ~= 6 + 0.10000000149 * 400 or not near(sof1h, sofExpected) or not near(sof2h, sofExpected) then
        emit(("FAIL Seal of Fury rank 1: %s / %s, expected %s"):format(tostring(sof1h), tostring(sof2h), tostring(sofExpected)))
    end
    if socStatus ~= "ok" or not near(soc.effects[1].min, socMin) or not near(soc.effects[1].max, socMax) then
        emit("FAIL Seal of Command doesn't add its spell power bonus to 70% of a weapon hit")
    end

    -- Improved Seals (15% at 5/5) reaches the procs that deal the damage
    __TALENT_TREE[1] = { spellId = 20224, maxRanks = 5 }
    __TALENT_RANKS[20224] = 5
    __FireEvent("TRAIT_CONFIG_UPDATED", 4001)
    settle()
    local sorTalent, sofTalent = avgOf(20293), avgOf(1311649)
    __TALENT_TREE[1], __TALENT_RANKS[20224] = nil, nil
    __FireEvent("TRAIT_CONFIG_UPDATED", 4001)
    settle()
    emit(("seals: Improved Seals 5/5: Seal of Righteousness x%.3f, Seal of Fury x%.3f"):format((sorTalent or 0) / (sor2h or 1), (sofTalent or 0) / (sof2h or 1)))
    if not near(sorTalent, (sor2h or 0) * 1.15) or not near(sofTalent, (sof2h or 0) * 1.15) then
        emit("FAIL Improved Seals doesn't apply to Seal of Righteousness and Seal of Fury")
    end

    -- Seal of Fury up: Judgement is Judgement of Fury
    __AURAS.player = { { name = __SPELL_NAMES[1311649], spellId = 1311649, applications = 1, sourceUnit = "player",
        auraInstanceID = 901, duration = 30, expirationTime = 0, isHelpful = true } }
    __FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
    settle()
    local judged = A.judgementSpell
    local judgement = avgOf(A.CONST.JUDGEMENT_ID)
    local jof = A.spellInfo[1311650]
    local jofExpected = -1
    if jof then
        local e = jof.effects[1]
        jofExpected = e.valueBase + e.valueRange / 2 + (math.min(60, jof.maxLevel) - jof.spellLevel) * e.valuePerLevel + e.coef * 400
    end
    __AURAS.player = {}
    __FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
    settle()
    emit(("seals: Judgement with Seal of Fury up is spell %s, %s on average"):format(tostring(judged), judgement and ("%.1f"):format(judgement) or "nothing"))
    if judged ~= 1311650 or not near(judgement, jofExpected) then emit("FAIL Judgement with Seal of Fury up isn't Judgement of Fury rank 1") end

    -- Back to unarmed at level 60 with the old spell power: the numbers from before
    wield(nil)
    setSpellPower(spBefore)
    __ACTION_SLOTS[31] = nil
    __FireEvent("ACTIONBAR_SLOT_CHANGED", 0)
    local differ, examples = 0, {}
    for id, v in pairs(runAll("seals checked")) do
        if base[id] and math.abs(base[id] - v) > 1e-6 then
            differ = differ + 1
            if #examples < 4 then examples[#examples + 1] = ("%s %.2f -> %.2f"):format(name(id), base[id], v) end
        end
    end
    if differ > 0 then emit(("FAIL %d spells differ after the seal checks: %s"):format(differ, table.concat(examples, ", "))) end
end

-- Channelled area spells (Hurricane, Blizzard, Rain of Fire): the cast spell only creates an area trigger on Forever;
-- the generator takes the damage from the spell its tooltip names. One tick per period of the channel.
do
    local AREA_CHANNELS = {
        DRUID = { id = 17402, name = "Hurricane", ticks = 10, base = 132 },
        MAGE = { id = 10187, name = "Blizzard", ticks = 8, base = 146 },
        WARLOCK = { id = 11678, name = "Rain of Fire", ticks = 4, base = 220 },
    }
    local want = AREA_CHANNELS[__CLASS]
    if want then
        local info = A.spellInfo[want.id]
        local status, cs = checkSpell(want.id)
        if not info or status ~= "ok" then
            emit(("FAIL %s [%d] is not calculated: %s"):format(want.name, want.id, info and status or "no data"))
        else
            local data, e = info.effects[1], cs.effects[1]
            local expected = data.valueBase + (math.min(60, info.maxLevel) - info.spellLevel) * (data.valuePerLevel or 0) + data.coef * 400
            emit(("area channel: %s %.1f x %s ticks"):format(name(want.id), e.avg, tostring(e.ticks)))
            if data.valueBase ~= want.base or e.ticks ~= want.ticks or math.abs(e.avg - expected) > 1e-6 or not info.isChannel then
                emit(("FAIL %s: %s x %s ticks, expected %s x %d (base %d)"):format(want.name, tostring(e.avg), tostring(e.ticks), tostring(expected), want.ticks, want.base))
            end
        end
    end
end

-- Druid. The stub reports 400 spell power for every school, physical included: feral abilities must not use it.
-- Claw is (weapon + 115) * 140%, Ferocious Bite gets 3% of attack power per combo point (5 assumed), Lacerate adds
-- 10% weapon damage per application already on the target (5 assumed) to its bleed, Swiftmend heals for all ticks
-- of the highest Rejuvenation or Regrowth.
if __CLASS == "DRUID" then
    local function fx(id, n)
        local status, cs = checkSpell(id)
        if status ~= "ok" then return { }, status end
        return cs.effects[n or 1] or { }, cs
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-4 end
    local claw, swipe, maul, bite = fx(9850), fx(9908), fx(9881), fx(31018)
    emit(("feral: Claw %s-%s, Swipe %s, Maul %s-%s, Ferocious Bite %s (%s of attack power)"):format(tostring(claw.min), tostring(claw.max),
        tostring(swipe.avg), tostring(maul.min), tostring(maul.max), tostring(bite.avg), tostring(bite.effectiveApCoef)))
    if not near(claw.min, (100 + 115) * 1.4) or not near(claw.max, (150 + 115) * 1.4) then emit("FAIL Claw rank 5 is not (weapon + 115) * 140%") end
    if not near(swipe.avg, 83) then emit("FAIL Swipe rank 5 is not 83") end
    if not near(maul.min, 100 + 128) or not near(maul.max, 150 + 128) then emit("FAIL Maul rank 7 is not weapon + 128") end
    if not near(bite.avg, 102 + 5 * 181 + 0.03 * 5 * 900) then emit("FAIL Ferocious Bite rank 6 is not 102 + 181 and 3% of attack power per combo point") end
    local withCoef, example = 0, nil
    for _, id in ipairs(spellIds) do
        local info = A.spellInfo[id]
        if info.schoolMask == 1 then
            for _, e in ipairs(info.effects) do
                if (e.coef or 0) ~= 0 then withCoef, example = withCoef + 1, example or name(id) end
            end
        end
    end
    if withCoef > 0 then emit(("FAIL %d physical spell effects have a spell power coefficient, %s for one"):format(withCoef, example)) end

    local hit, lacerate = fx(1235827, 1)
    local bleed = fx(1235827, 2)
    emit(("Lacerate: %s-%s weapon damage on 5 applications, bleed %s x %s"):format(tostring(hit.min), tostring(hit.max), tostring(bleed.avg), tostring(bleed.ticks)))
    if not near(hit.min, 0.5 * 100) or not near(hit.max, 0.5 * 150) then emit("FAIL Lacerate rank 5 is not 50% weapon damage with 5 applications") end
    if not near(bleed.avg, 15) or bleed.ticks ~= 5 or type(lacerate) ~= "table" or not bleed.auraStack then emit("FAIL Lacerate rank 5 bleed is not 15 x 5 with stacks") end
    -- 95% to hit, 5% dodged; a bleed ignores armor
    if not near(bleed.avgAfterMitigation, 15 * 5 * 0.90) then emit("FAIL Lacerate bleed is reduced by armor: " .. tostring(bleed.avgAfterMitigation)) end

    local rejuv, regrowthHot, swiftmend = fx(25299), fx(9858, 2), fx(18562)
    local rejuvTotal, regrowthTotal = (rejuv.avg or 0) * (rejuv.ticks or 0), (regrowthHot.avg or 0) * (regrowthHot.ticks or 0)
    local parts = {}
    for _, c in ipairs(swiftmend.consumed or {}) do parts[#parts + 1] = ("%s %.0f"):format(c.name, c.value) end
    emit(("Swiftmend: %s-%s (%s)"):format(tostring(swiftmend.min), tostring(swiftmend.max), table.concat(parts, ", ")))
    if rejuvTotal <= 0 or regrowthTotal <= 0 or #parts ~= 2
        or not near(swiftmend.min, math.min(rejuvTotal, regrowthTotal)) or not near(swiftmend.max, math.max(rejuvTotal, regrowthTotal)) then
        emit(("FAIL Swiftmend is %s-%s, Rejuvenation heals %s and Regrowth %s over their duration"):format(tostring(swiftmend.min), tostring(swiftmend.max), tostring(rejuvTotal), tostring(regrowthTotal)))
    end
    tooltipFor(18562)
    local lines = table.concat(GameTooltip.__lines, " / ")
    if not lines:find(__SPELL_NAMES[25299], 1, true) or not lines:find(__SPELL_NAMES[9858], 1, true) then emit("FAIL Swiftmend's tooltip doesn't name Rejuvenation and Regrowth") end

    if A.spellInfo[22845] then emit("FAIL Frenzied Regeneration's empty heal [22845] is in the data") end
end

-- Mage. Arcane Wrath gains 5% of maximum mana as spell power; Flamestrike burns for 4 more ticks (an area trigger
-- on Forever, the tick is the spell its tooltip names); Frost Ward and Ice Barrier absorb 10% of spell power more,
-- and Frost Warding 10% more per rank of all of it; Mana Shield drains 2 mana per point absorbed, less with Arcane
-- Shielding; Mage Armor keeps 50% of the regeneration while casting. A frozen target (assumed in the settings):
-- Ice Lance deals 300% more, Shatter adds its critical strike chance. Winter's Chill (assumed, 5 applications):
-- Cone of Cold takes 20% more damage and 7% of spell power more per application.
if __CLASS == "MAGE" then
    -- A copy of the numbers: the addon recalculates a spell in place, so the tables themselves change later.
    local function fx(id, n)
        local status, cs = checkSpell(id)
        if status ~= "ok" then return { } end
        local e = cs.effects[n or 1] or { }
        return { avg = e.avg, min = e.min, max = e.max, ticks = e.ticks, spellPower = e.spellPower,
            crit = cs.critChance, cost = cs.effectiveCost, baseCost = cs.baseCost }
    end
    local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-4 end
    local function baseOf(id, n)
        local info = A.spellInfo[id]
        local e = info and info.effects[n or 1]
        if not e then return nil, { } end
        return e.valueBase + e.valueRange / 2 + (math.min(60, info.maxLevel) - info.spellLevel) * (e.valuePerLevel or 0), e
    end
    local function talents(ranks)
        for i = #__TALENT_TREE, 1, -1 do
            __TALENT_RANKS[__TALENT_TREE[i].spellId] = nil
            __TALENT_TREE[i] = nil
        end
        for spellId, rank in pairs(ranks) do
            __TALENT_TREE[#__TALENT_TREE + 1] = { spellId = spellId, maxRanks = rank }
            __TALENT_RANKS[spellId] = rank
        end
        __FireEvent("TRAIT_CONFIG_UPDATED", 4001)
        settle()
    end
    local function assume(spellId, stacks)
        SpellCalc_settings.assumedTargetAuras[spellId] = stacks
        A:UpdateAssumedTargetAuras()
        settle()
    end
    local WRATH, FLAMESTRIKE, FROST_WARD, ICE_BARRIER, MANA_SHIELD = 1326082, 10216, 28609, 13033, 10193
    local ICE_LANCE, FROSTBOLT, CONE_OF_COLD, FROST_NOVA, WINTERS_CHILL = 1240047, 25304, 10161, 10230, 12579

    local maxMana = A.stats.manaMax
    local wrath = fx(WRATH)
    local wrathBase, wrathData = baseOf(WRATH)
    emit(("mage: Arcane Wrath %s with %s spell power (400 + 5%% of %s mana)"):format(tostring(wrath.avg), tostring(wrath.spellPower), tostring(maxMana)))
    if wrathData.spellPowerPctOfMana ~= 5 or maxMana <= 0 or not near(wrath.spellPower, 400 + 0.05 * maxMana)
        or not near(wrath.avg, wrathBase + (400 + 0.05 * maxMana) * wrathData.coef) then
        emit("FAIL Arcane Wrath doesn't gain 5% of maximum mana as spell power")
    end

    local burn = fx(FLAMESTRIKE, 2)
    local burnBase, burnData = baseOf(FLAMESTRIKE, 2)
    emit(("mage: Flamestrike burns for %s x %s"):format(tostring(burn.avg), tostring(burn.ticks)))
    if burnBase ~= 83 or burn.ticks ~= 4 or not near(burn.avg, 83 + (burnData.coef or 0) * 400) or (burnData.coef or 0) <= 0 then
        emit("FAIL Flamestrike rank 6 has no burn of 83 plus spell power every 2 s for 8 s")
    end

    local ward, barrier = fx(FROST_WARD), fx(ICE_BARRIER)
    local wardBase, barrierBase = baseOf(FROST_WARD), baseOf(ICE_BARRIER)
    local shield = fx(MANA_SHIELD)
    emit(("mage: Frost Ward %s, Ice Barrier %s, Mana Shield costs %s for %s absorbed"):format(tostring(ward.avg), tostring(barrier.avg),
        tostring(shield.cost), tostring(shield.avg)))
    if not near(ward.avg, wardBase + 0.1 * 400) then emit("FAIL Frost Ward doesn't absorb 10% of spell power on top of its base") end
    if not near(barrier.avg, barrierBase + 0.1 * 400) then emit("FAIL Ice Barrier doesn't absorb 10% of spell power on top of its base") end
    if not shield.avg or not near(shield.cost, shield.baseCost + 2 * shield.avg) then
        emit("FAIL Mana Shield doesn't drain 2 mana per point absorbed")
    end
    for _, id in ipairs({ 6117, 22782, 22783 }) do
        local aura = A.aurasPlayer[id]
        if not aura or aura[1].value ~= 50 then emit("FAIL Mage Armor [" .. id .. "] doesn't keep 50% of the mana regeneration while casting") end
    end

    -- Frost Warding 2/2, Arcane Shielding 2/2
    talents({ [11189] = 2, [11252] = 2 })
    local wardTalent, barrierTalent = fx(FROST_WARD), fx(ICE_BARRIER)
    local shieldTalent = fx(MANA_SHIELD)
    emit(("mage: Frost Warding 2/2: Frost Ward %s, Ice Barrier %s; Arcane Shielding 2/2: Mana Shield costs %s"):format(
        tostring(wardTalent.avg), tostring(barrierTalent.avg), tostring(shieldTalent.cost)))
    if not near(wardTalent.avg, (ward.avg or 0) * 1.2) or not near(barrierTalent.avg, (barrier.avg or 0) * 1.2) then
        emit("FAIL Frost Warding 2/2 doesn't add 20% to all of Frost Ward and Ice Barrier")
    end
    if not shieldTalent.avg or not near(shieldTalent.cost, shieldTalent.baseCost + 2 * (1 - 0.33) * shieldTalent.avg) then
        emit("FAIL Arcane Shielding 2/2 doesn't reduce Mana Shield's drain by 33%")
    end

    -- Frozen target, without and with Shatter 3/3
    talents({})
    local lance, bolt = fx(ICE_LANCE), fx(FROSTBOLT)
    assume(FROST_NOVA, 1)
    local lanceFrozen, boltFrozen = fx(ICE_LANCE), fx(FROSTBOLT)
    talents({ [11170] = 3 })
    local boltShatter = fx(FROSTBOLT)
    assume(FROST_NOVA, nil)
    local boltUnfrozen = fx(FROSTBOLT)
    talents({})
    local lanceAfter = fx(ICE_LANCE)
    emit(("mage: Ice Lance %s, %s on a frozen target; Frostbolt crit %s%%, %s%% frozen with Shatter 3/3"):format(tostring(lance.avg), tostring(lanceFrozen.avg),
        tostring(bolt.crit), tostring(boltShatter.crit)))
    if not lance.avg or lance.avg <= 0 or not near(lanceFrozen.avg, lance.avg * 4) then emit("FAIL Ice Lance doesn't deal 300% more damage to a frozen target") end
    if not near(boltFrozen.crit, bolt.crit) or not near(boltFrozen.avg, bolt.avg) then emit("FAIL a frozen target changes Frostbolt without Shatter") end
    if not near(boltShatter.crit, (bolt.crit or 0) + 50) then emit("FAIL Shatter 3/3 doesn't add 50% critical strike chance against a frozen target") end
    if not near(boltUnfrozen.crit, bolt.crit) then emit("FAIL Shatter adds critical strike chance to a target that isn't frozen") end
    if not near(lanceAfter.crit, lance.crit) or not near(lanceAfter.avg, lance.avg) then
        emit("FAIL Ice Lance isn't back to normal after the frozen target is deselected")
    end
    local frozenOption
    for _, group in pairs(A.AssumedTargetAuraSettings()) do
        if type(group) == "table" and group.type == "group" and group.args["aura" .. FROST_NOVA] then frozenOption = group.args["aura" .. FROST_NOVA].name end
    end
    if type(frozenOption) ~= "string" or not frozenOption:find("Frozen target", 1, true) or not frozenOption:find(__SPELL_NAMES[FROST_NOVA], 1, true) then
        emit("FAIL the frozen target option isn't offered as \"Frozen target (Frost Nova ...)\": " .. tostring(frozenOption))
    end

    -- Fire Power 3/3 with 4 of the mage's Fire effects on the target: 12% more Fire damage, nothing for Frost
    local FIREBALL, FIRE_POWER, FIRE_WARD = 25306, 11124, 10225
    local fireball, fireballDot, fireWard = fx(FIREBALL), fx(FIREBALL, 2), fx(FIRE_WARD)
    assume(FIRE_POWER, 4)
    local fireballNoTalent = fx(FIREBALL)
    talents({ [FIRE_POWER] = 3 })
    local fireballPower, fireballDotPower, boltPower, fireWardPower = fx(FIREBALL), fx(FIREBALL, 2), fx(FROSTBOLT), fx(FIRE_WARD)
    assume(FIRE_POWER, 2)
    local fireballTwo = fx(FIREBALL)
    assume(FIRE_POWER, nil)
    local fireballNoEffects = fx(FIREBALL)
    talents({})
    emit(("mage: Fireball %s, %s with Fire Power 3/3 and 4 Fire effects on the target, %s with 2"):format(tostring(fireball.avg), tostring(fireballPower.avg), tostring(fireballTwo.avg)))
    if not fireball.avg or not near(fireballPower.avg, fireball.avg * 1.12) or not near(fireballDotPower.avg, (fireballDot.avg or 0) * 1.12)
        or not near(fireballTwo.avg, fireball.avg * 1.06) then
        emit("FAIL Fire Power 3/3 doesn't add 3% Fire damage per assumed Fire effect on the target")
    end
    if not near(fireballNoTalent.avg, fireball.avg) or not near(fireballNoEffects.avg, fireball.avg) then
        emit("FAIL Fire Power changes Fireball without the talent or without Fire effects on the target")
    end
    if not near(boltPower.avg, bolt.avg) or not near(fireWardPower.avg, fireWard.avg) then emit("FAIL Fire Power changes Frostbolt or Fire Ward") end

    -- Winter's Chill, 5 applications
    local cone = fx(CONE_OF_COLD)
    local coneBase, coneData = baseOf(CONE_OF_COLD)
    assume(WINTERS_CHILL, 5)
    local coneChilled = fx(CONE_OF_COLD)
    assume(WINTERS_CHILL, nil)
    emit(("mage: Cone of Cold %s, %s with 5 applications of Winter's Chill"):format(tostring(cone.avg), tostring(coneChilled.avg)))
    if not near(cone.avg, coneBase + coneData.coef * 400) or not near(coneChilled.avg, (coneBase + (coneData.coef + 5 * 0.07) * 400) * 2) then
        emit("FAIL Winter's Chill x5 doesn't double Cone of Cold and add 35% of spell power")
    end

    local differ, examples = 0, {}
    for id, v in pairs(runAll("mage checked")) do
        if base[id] and math.abs(base[id] - v) > 1e-6 then
            differ = differ + 1
            if #examples < 4 then examples[#examples + 1] = ("%s %.2f -> %.2f"):format(name(id), base[id], v) end
        end
    end
    if differ > 0 then emit(("FAIL %d spells differ after the mage checks: %s"):format(differ, table.concat(examples, ", "))) end
end

-- Paladin. Consecration ticks through an area trigger (the tick spell has a part for every enemy and one for the
-- first enemies; shown together); Templar's Bulwark absorbs the paladin's maximum health; Hammer of the Righteous
-- deals 3 times the main hand's damage per second; Judgement of Command deals half its damage unless the target is
-- stunned (assumed in the settings); Light's Vigil shows the party heal its tooltip names; the Exorcist passive
-- replaces Exorcism with ranks that always crit Undead and Demons. Talents: Holy Power (critical heals), Two-Handed
-- Weapon Specialization (Holy damage too, with a two-hander), Consecrated Ground, Boundless Light. Oath of Light
-- (assumed on the heal target) adds a flat amount per level to three heals.
if __CLASS == "PALADIN" then
    -- A copy of the numbers: the addon recalculates a spell in place, so the tables themselves change later.
    local function fx(id, n)
        local status, cs = checkSpell(id)
        if status ~= "ok" then return { } end
        local e = cs.effects[n or 1] or { }
        return { avg = e.avg, min = e.min, max = e.max, ticks = e.ticks, crit = cs.critChance, critMult = cs.critMult,
            triggered = e.triggeredSpell }
    end
    local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-4 end
    local function baseOf(id, n)
        local info = A.spellInfo[id]
        local e = info and info.effects[n or 1]
        if not e then return nil, { } end
        return e.valueBase + e.valueRange / 2 + (math.min(60, info.maxLevel) - info.spellLevel) * (e.valuePerLevel or 0), e
    end
    local function talents(ranks)
        for i = #__TALENT_TREE, 1, -1 do
            __TALENT_RANKS[__TALENT_TREE[i].spellId] = nil
            __TALENT_TREE[i] = nil
        end
        for spellId, rank in pairs(ranks) do
            __TALENT_TREE[#__TALENT_TREE + 1] = { spellId = spellId, maxRanks = rank }
            __TALENT_RANKS[spellId] = rank
        end
        __FireEvent("TRAIT_CONFIG_UPDATED", 4001)
        settle()
    end
    local function assume(spellId, stacks)
        SpellCalc_settings.assumedTargetAuras[spellId] = stacks
        A:UpdateAssumedTargetAuras()
        settle()
    end
    local function wield(itemId)
        __INVENTORY[16] = itemId
        __FireEvent("UNIT_INVENTORY_CHANGED", "player")
        settle()
    end
    local function target(t)
        __TARGET = t
        __FireEvent("PLAYER_TARGET_CHANGED")
        settle()
    end
    local CONSECRATION, BULWARK, HAMMER, JOC, VIGIL, VIGIL_HEAL = 20924, 1311015, 407632, 20966, 1311595, 1311596
    local EXORCISM, EXORCISM_ANY, HOLY_LIGHT, FLASH, SHOCK_HEAL, SHOCK_DAMAGE = 10314, 415073, 25292, 19943, 25903, 25902
    local OATH, STUN, GROUND, HOLY_POWER, TWO_HAND, BOUNDLESS = 1328548, 10308, 1310905, 5923, 20111, 1328550

    local cons = fx(CONSECRATION)
    local consBase, consData = baseOf(CONSECRATION)
    emit(("paladin: Consecration %s x %s"):format(tostring(cons.avg), tostring(cons.ticks)))
    if consBase ~= 12 + 27 or cons.ticks ~= 8 or (consData.coef or 0) <= 0 or not near(cons.avg, 39 + consData.coef * 400) then
        emit("FAIL Consecration rank 5 doesn't tick 8 times for 12 + 27 plus spell power")
    end

    local bulwark = fx(BULWARK)
    local health = A.stats.healthMax or 0
    emit(("paladin: Templar's Bulwark absorbs %s with %s maximum health"):format(tostring(bulwark.avg), tostring(health)))
    if health <= 0 or not near(bulwark.avg, health) then emit("FAIL Templar's Bulwark doesn't absorb 100% of maximum health") end

    local hammer = fx(HAMMER)
    local _, hammerData = baseOf(HAMMER)
    local dps = (A.stats.attackDmg.mainhand.min + A.stats.attackDmg.mainhand.max) / 2 / A.stats.attackSpeed.mainhand
    emit(("paladin: Hammer of the Righteous %s with %.2f weapon damage per second"):format(tostring(hammer.avg), dps))
    if hammerData.weaponDpsMult ~= 3 or not near(hammer.avg, hammerData.valueBase + 3 * dps) then
        emit("FAIL Hammer of the Righteous doesn't deal 3 times the main hand's damage per second")
    end

    -- Judgement of Command rank 5: 356 + 6.1 per level and 42.9% of spell power in the client data, halved
    local joc, exorcism = fx(JOC), fx(EXORCISM)
    local jocBase, jocData = baseOf(JOC)
    assume(STUN, 1)
    local jocStunned, exorcismStunned = fx(JOC), fx(EXORCISM)
    assume(STUN, nil)
    emit(("paladin: Judgement of Command %s, %s on a stunned target"):format(tostring(joc.avg), tostring(jocStunned.avg)))
    if jocBase ~= 178 or A.spellInfo[JOC].stunnedDamagePct ~= 100 or not near(joc.avg, jocBase + jocData.coef * 400)
        or math.abs(jocData.coef - 0.429 / 2) > 1e-6 then
        emit("FAIL Judgement of Command isn't stored with half its damage")
    end
    if not joc.avg or not near(jocStunned.avg, joc.avg * 2) then emit("FAIL Judgement of Command doesn't deal double damage to a stunned target") end
    if not near(exorcismStunned.avg, exorcism.avg) then emit("FAIL a stunned target changes Exorcism") end
    local stunOption
    for _, group in pairs(A.AssumedTargetAuraSettings()) do
        if type(group) == "table" and group.type == "group" and group.args["aura" .. STUN] then stunOption = group.args["aura" .. STUN].name end
    end
    if type(stunOption) ~= "string" or not stunOption:find("Stunned or incapacitated target", 1, true) then
        emit("FAIL the stunned target option isn't offered as \"Stunned or incapacitated target (...)\": " .. tostring(stunOption))
    end

    local vigil, vigilHeal = fx(VIGIL), fx(VIGIL_HEAL)
    local vigilBase, vigilData = baseOf(VIGIL_HEAL)
    emit(("paladin: Light's Vigil heals each party member for %s"):format(tostring(vigilHeal.avg)))
    if vigil.triggered ~= VIGIL_HEAL or not vigilBase or not near(vigilHeal.avg, vigilBase + vigilData.coef * 700) or (vigilData.coef or 0) <= 0 then
        emit("FAIL Light's Vigil doesn't show the party heal named in its tooltip")
    end

    -- Exorcist: the client reports the override; Undead and Demons are always crit
    local any = fx(EXORCISM_ANY)
    __SPELL_OVERRIDES[EXORCISM] = EXORCISM_ANY
    local handled = A:GetHandledSpellID(EXORCISM)
    __SPELL_OVERRIDES[EXORCISM] = nil
    target({ name = "Risen Guard", level = 60, creatureType = { "Undead", 6 }, class = "WARRIOR", isPlayer = false })
    local anyUndead, plainUndead = fx(EXORCISM_ANY), fx(EXORCISM)
    target({ name = "Defias Thug", level = 60, creatureType = { "Humanoid", 7 }, class = "WARRIOR", isPlayer = false })
    local anyHumanoid = fx(EXORCISM_ANY)
    target(nil)
    emit(("paladin: Exorcism %s, %s as replaced by Exorcist (crit %s%%, %s%% against Undead)"):format(tostring(exorcism.avg), tostring(any.avg),
        tostring(any.crit), tostring(anyUndead.crit)))
    if handled ~= EXORCISM_ANY or A:GetHandledSpellID(EXORCISM) ~= EXORCISM then emit("FAIL a replaced Exorcism isn't calculated as the spell that replaces it") end
    if not any.avg or not exorcism.avg or any.avg <= exorcism.avg then emit("FAIL the Exorcism ranks of Exorcist aren't generated with their own values") end
    if anyUndead.crit ~= 100 or not near(anyHumanoid.crit, any.crit) or not near(plainUndead.crit, exorcism.crit) then
        emit("FAIL Exorcism with Exorcist doesn't always crit Undead, or crits other targets or the plain spell more often")
    end

    -- Holy Power 5/5: critical heals for 175%; Two-Handed Weapon Specialization 3/3: 6% Holy damage with a two-hander
    local light, shockDamage = fx(HOLY_LIGHT), fx(SHOCK_DAMAGE)
    talents({ [HOLY_POWER] = 5, [TWO_HAND] = 3 })
    local lightPower, exorcismUnarmed = fx(HOLY_LIGHT), fx(EXORCISM)
    __WEAPONS[90001] = { subclass = Enum.ItemWeaponSubclass.Mace2H, low = 5, high = 9, speed = 2.9 }
    __WEAPONS[90002] = { subclass = Enum.ItemWeaponSubclass.Mace1H, low = 3, high = 7, speed = 2.6 }
    wield(90001)
    local exorcismTwoHand, lightTwoHand = fx(EXORCISM), fx(HOLY_LIGHT)
    wield(90002)
    local exorcismOneHand = fx(EXORCISM)
    wield(nil)
    talents({})
    emit(("paladin: Holy Light crits for x%s, x%s with Holy Power 5/5; Exorcism %s, %s with Two-Handed Weapon Specialization 3/3 and a two-hander"):format(
        tostring(light.critMult), tostring(lightPower.critMult), tostring(exorcism.avg), tostring(exorcismTwoHand.avg)))
    if not near(light.critMult, 1.5) or not near(lightPower.critMult, 1.75) or not near(exorcismUnarmed.critMult, exorcism.critMult) then
        emit("FAIL Holy Power 5/5 doesn't raise critical heals to 175%, or changes damage crits")
    end
    if not near(exorcismTwoHand.avg, (exorcism.avg or 0) * 1.06) or not near(exorcismUnarmed.avg, exorcism.avg) or not near(exorcismOneHand.avg, exorcism.avg)
        or not near(lightTwoHand.avg, light.avg) then
        emit("FAIL Two-Handed Weapon Specialization 3/3 doesn't add 6% Holy damage with a two-hander only")
    end

    -- Oath of Light on the heal target; Boundless Light 2/2 only without it
    local flash, shockHeal = fx(FLASH), fx(SHOCK_HEAL)
    assume(OATH, 1)
    local lightOath, flashOath, shockOath, shockDamageOath = fx(HOLY_LIGHT), fx(FLASH), fx(SHOCK_HEAL), fx(SHOCK_DAMAGE)
    talents({ [BOUNDLESS] = 2 })
    local shockOathBoundless = fx(SHOCK_HEAL)
    assume(OATH, nil)
    local shockBoundless, shockDamageBoundless, lightBoundless = fx(SHOCK_HEAL), fx(SHOCK_DAMAGE), fx(HOLY_LIGHT)
    talents({})
    emit(("paladin: Oath of Light: Holy Light %s -> %s, Flash of Light %s -> %s, Holy Shock %s -> %s; Boundless Light 2/2: Holy Shock heal crit %s%% -> %s%%"):format(
        tostring(light.avg), tostring(lightOath.avg), tostring(flash.avg), tostring(flashOath.avg), tostring(shockHeal.avg), tostring(shockOath.avg),
        tostring(shockHeal.crit), tostring(shockBoundless.crit)))
    if not light.avg or math.abs((lightOath.avg or 0) - light.avg - 400) > 0.01 or math.abs((flashOath.avg or 0) - flash.avg - 115) > 0.01
        or math.abs((shockOath.avg or 0) - shockHeal.avg - 230) > 0.01 then
        emit("FAIL Oath of Light doesn't add 400 / 115 / 230 to Holy Light, Flash of Light and Holy Shock at level 60")
    end
    if not near(shockDamageOath.avg, shockDamage.avg) then emit("FAIL Oath of Light changes Holy Shock's damage") end
    if not near(shockBoundless.crit, (shockHeal.crit or 0) + 30) or not near(shockOathBoundless.crit, shockHeal.crit)
        or not near(shockDamageBoundless.crit, shockDamage.crit) or not near(lightBoundless.crit, light.crit) then
        emit("FAIL Boundless Light 2/2 doesn't add 30% critical strike chance to Holy Shock heals without Oath of Light only")
    end

    -- Consecrated Ground 2/2: Consecration always, other Holy damage against the first enemies in it
    talents({ [GROUND] = 2 })
    local consGround, exorcismGround = fx(CONSECRATION), fx(EXORCISM)
    assume(GROUND, 1)
    local consInside, exorcismInside, lightInside = fx(CONSECRATION), fx(EXORCISM), fx(HOLY_LIGHT)
    talents({})
    local exorcismNoTalent = fx(EXORCISM)
    assume(GROUND, nil)
    emit(("paladin: Consecrated Ground 2/2: Consecration %s -> %s; Exorcism %s -> %s against the first enemies in it"):format(
        tostring(cons.avg), tostring(consGround.avg), tostring(exorcism.avg), tostring(exorcismInside.avg)))
    if not near(consGround.avg, (cons.avg or 0) * 1.1) or not near(consInside.avg, (cons.avg or 0) * 1.1) then
        emit("FAIL Consecrated Ground 2/2 doesn't add 10% to Consecration (once)")
    end
    if not near(exorcismGround.avg, exorcism.avg) or not near(exorcismInside.avg, (exorcism.avg or 0) * 1.1) or not near(exorcismNoTalent.avg, exorcism.avg)
        or not near(lightInside.avg, light.avg) then
        emit("FAIL Consecrated Ground 2/2 doesn't add 10% Holy damage against the first enemies in the Consecration only")
    end

    local differ, examples = 0, {}
    for id, v in pairs(runAll("paladin checked")) do
        if base[id] and math.abs(base[id] - v) > 1e-6 then
            differ = differ + 1
            if #examples < 4 then examples[#examples + 1] = ("%s %.2f -> %.2f"):format(name(id), base[id], v) end
        end
    end
    if differ > 0 then emit(("FAIL %d spells differ after the paladin checks: %s"):format(differ, table.concat(examples, ", "))) end
end

-- Priest. Every rank of Penance is a dummy whose volleys are fired by other spells (the generator finds them
-- through the tooltip); Contingency Plan shows the heal and the absorb its tooltip names; Dark Sacrifice gives its
-- mana plus the priest's Spirit; Power Word: Shield scales with healing power. Talents: Divine Aegis (extra on a
-- critical heal), Improved Mind Flay (rising ticks, shown as their average), and three that depend on a state of
-- the target assumed in the settings: Renewed Hope (Weakened Soul), Power in Light (the priest's Holy Fire or
-- Shadow Word: Pain), Early Demise (low health). Spirit Tap lets half the mana regeneration continue while casting.
if __CLASS == "PRIEST" then
    -- A copy of the numbers: the addon recalculates a spell in place, so the tables themselves change later.
    local function fx(id, n)
        local status, cs = checkSpell(id)
        if status ~= "ok" then return { } end
        local e = cs.effects[n or 1] or { }
        return { avg = e.avg, avgCrit = e.avgCrit, critExtra = e.critExtraAvg, ticks = e.ticks, crit = cs.critChance, spellPower = e.spellPower }
    end
    local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-4 end
    local function baseOf(id, n)
        local info = A.spellInfo[id]
        local e = info and info.effects[n or 1]
        if not e then return nil, { } end
        return e.valueBase + e.valueRange / 2 + (math.min(60, info.maxLevel) - info.spellLevel) * (e.valuePerLevel or 0), e
    end
    local function talents(ranks)
        for i = #__TALENT_TREE, 1, -1 do
            __TALENT_RANKS[__TALENT_TREE[i].spellId] = nil
            __TALENT_TREE[i] = nil
        end
        for spellId, rank in pairs(ranks) do
            __TALENT_TREE[#__TALENT_TREE + 1] = { spellId = spellId, maxRanks = rank }
            __TALENT_RANKS[spellId] = rank
        end
        __FireEvent("TRAIT_CONFIG_UPDATED", 4001)
        settle()
    end
    local function assume(spellId, stacks)
        SpellCalc_settings.assumedTargetAuras[spellId] = stacks
        A:UpdateAssumedTargetAuras()
        settle()
    end
    local PENANCE, PENANCE_HEAL, PENANCE_DAMAGE, PLAN, SACRIFICE, SHIELD = 1316995, 1316991, 1316993, 1277640, 1277328, 10901
    local FLASH, SMITE, HOLY_FIRE, DEATH, MIND_BLAST, MIND_FLAY, SHADOWGUARD = 10917, 10934, 15261, 1309636, 10947, 18807, 28382
    local AEGIS, HOPE, LIGHT, DEMISE, IMPROVED_FLAY, WEAKENED_SOUL, SPIRIT_TAP = 431622, 425280, 1309969, 1310076, 1225139, 6788, 15271

    local penanceHeal, penanceDamage = fx(PENANCE, 1), fx(PENANCE, 2)
    local volleyHeal, volleyHealData = baseOf(PENANCE_HEAL)
    local volleyDamage, volleyDamageData = baseOf(PENANCE_DAMAGE)
    emit(("priest: Penance rank 4 heals %s x %s or deals %s x %s"):format(tostring(penanceHeal.avg), tostring(penanceHeal.ticks),
        tostring(penanceDamage.avg), tostring(penanceDamage.ticks)))
    if volleyHeal ~= 425 or volleyDamage ~= 92 or penanceHeal.ticks ~= 3 or penanceDamage.ticks ~= 3
        or not near(penanceHeal.avg, 425 + (volleyHealData.coef or 0) * 700) or not near(penanceDamage.avg, 92 + (volleyDamageData.coef or 0) * 400) then
        emit("FAIL Penance rank 4 isn't 3 volleys of 425 healing or 92 damage plus spell power")
    end
    for _, id in ipairs({ 402174, 1240720, 1240721 }) do
        if not A.spellInfo[id] or #A.spellInfo[id].effects ~= 2 then emit("FAIL Penance [" .. id .. "] has no heal and damage volleys") end
    end

    local planHeal, planAbsorb = fx(PLAN, 1), fx(PLAN, 2)
    local planHealBase, planHealData = baseOf(PLAN, 1)
    emit(("priest: Contingency Plan heals %s x %s and absorbs %s"):format(tostring(planHeal.avg), tostring(planHeal.ticks), tostring(planAbsorb.avg)))
    if planHealBase ~= 134 or planHeal.ticks ~= 5 or not near(planHeal.avg, 134 + (planHealData.coef or 0) * 700) or (planHealData.coef or 0) <= 0
        or not near(planAbsorb.avg, 926) then
        emit("FAIL Contingency Plan rank 5 isn't a heal of 134 plus spell power every 3 s for 15 s and an absorb of 926")
    end

    local sacrifice = fx(SACRIFICE)
    local spirit = A.stats.spirit or 0
    emit(("priest: Dark Sacrifice restores %s x %s with %s Spirit"):format(tostring(sacrifice.avg), tostring(sacrifice.ticks), tostring(spirit)))
    if spirit <= 0 or sacrifice.ticks ~= 5 or not near(sacrifice.avg, 320 + spirit / 5) then
        emit("FAIL Dark Sacrifice rank 5 doesn't restore 5 x 320 mana plus the priest's Spirit")
    end

    local shield = fx(SHIELD)
    local shieldBase, shieldData = baseOf(SHIELD)
    emit(("priest: Power Word: Shield absorbs %s with %s healing power"):format(tostring(shield.avg), tostring(A.stats.spellHealing)))
    if A.stats.spellHealing == A.stats.spellPower[2] or not near(shield.spellPower, A.stats.spellHealing)
        or not near(shield.avg, shieldBase + shieldData.coef * A.stats.spellHealing) then
        emit("FAIL Power Word: Shield doesn't scale with healing power")
    end

    -- Divine Aegis 3/3: 15% of a critical heal on top
    local flash, smite = fx(FLASH), fx(SMITE)
    talents({ [AEGIS] = 3 })
    local flashAegis, smiteAegis = fx(FLASH), fx(SMITE)
    talents({})
    emit(("priest: Flash Heal crits for %s, Divine Aegis 3/3 absorbs %s more"):format(tostring(flash.avgCrit), tostring(flashAegis.critExtra)))
    if flash.critExtra or not flash.avgCrit or not near(flashAegis.critExtra, flash.avgCrit * 0.15) or smiteAegis.critExtra then
        emit("FAIL Divine Aegis 3/3 doesn't add 15% of a critical heal, or adds it to damage")
    end

    -- Renewed Hope 5/5 on a target with Weakened Soul
    local volley, guard = fx(PENANCE_HEAL), fx(SHADOWGUARD)
    talents({ [HOPE] = 5 })
    local flashHopeOff = fx(FLASH)
    assume(WEAKENED_SOUL, 1)
    local flashHope, volleyHope, smiteHope, guardHope = fx(FLASH), fx(PENANCE_HEAL), fx(SMITE), fx(SHADOWGUARD)
    talents({})
    local flashSoulOnly = fx(FLASH)
    assume(WEAKENED_SOUL, nil)
    emit(("priest: Flash Heal crit %s%%, %s%% with Renewed Hope 5/5 on a Weakened Soul target"):format(tostring(flash.crit), tostring(flashHope.crit)))
    if not near(flashHope.crit, (flash.crit or 0) + 10) or not near(volleyHope.crit, (volley.crit or 0) + 10) then
        emit("FAIL Renewed Hope 5/5 doesn't add 10% critical strike chance to Flash Heal and Penance's heal on a Weakened Soul target")
    end
    if not near(flashHopeOff.crit, flash.crit) or not near(flashSoulOnly.crit, flash.crit) or not near(smiteHope.crit, smite.crit)
        or not near(guardHope.crit, guard.crit) then
        emit("FAIL Renewed Hope changes heals without Weakened Soul or without the talent, or changes damage spells")
    end

    -- Power in Light 5/5 against a target with the priest's Holy Fire or Shadow Word: Pain
    local fire, volleyDmg = fx(HOLY_FIRE), fx(PENANCE_DAMAGE)
    talents({ [LIGHT] = 5 })
    local smiteLightOff = fx(SMITE)
    assume(LIGHT, 1)
    local smiteLight, volleyLight, fireLight, flashLight = fx(SMITE), fx(PENANCE_DAMAGE), fx(HOLY_FIRE), fx(FLASH)
    talents({})
    assume(LIGHT, nil)
    emit(("priest: Smite %s, %s with Power in Light 5/5 against a target with Holy Fire or Shadow Word: Pain"):format(tostring(smite.avg), tostring(smiteLight.avg)))
    if not smite.avg or not near(smiteLight.avg, smite.avg * 1.1) or not near(volleyLight.avg, (volleyDmg.avg or 0) * 1.1) then
        emit("FAIL Power in Light 5/5 doesn't add 10% to Smite and Penance's damage against an afflicted target")
    end
    if not near(smiteLightOff.avg, smite.avg) or not near(fireLight.avg, fire.avg) or not near(flashLight.avg, flash.avg) then
        emit("FAIL Power in Light changes Smite without the target state, or changes Holy Fire or Flash Heal")
    end

    -- Early Demise 2/2 against a target at low health
    local death, blast = fx(DEATH), fx(MIND_BLAST)
    talents({ [DEMISE] = 2 })
    local deathOff = fx(DEATH)
    assume(DEMISE, 1)
    local deathLow, blastLow = fx(DEATH), fx(MIND_BLAST)
    talents({})
    assume(DEMISE, nil)
    emit(("priest: Shadow Word: Death crit %s%%, %s%% with Early Demise 2/2 at low health"):format(tostring(death.crit), tostring(deathLow.crit)))
    if not near(deathLow.crit, (death.crit or 0) + 30) or not near(deathOff.crit, death.crit) or not near(blastLow.crit, blast.crit) then
        emit("FAIL Early Demise 2/2 doesn't add 30% critical strike chance to Shadow Word: Death at low health only")
    end

    -- Improved Mind Flay 2/2: 3 ticks of 1, 1.2 and 1.44 times the tick
    local flay = fx(MIND_FLAY)
    talents({ [IMPROVED_FLAY] = 2 })
    local flayImproved, blastImproved = fx(MIND_FLAY), fx(MIND_BLAST)
    talents({})
    emit(("priest: Mind Flay %s x %s, %s on average with Improved Mind Flay 2/2"):format(tostring(flay.avg), tostring(flay.ticks), tostring(flayImproved.avg)))
    if flay.ticks ~= 3 or not near(flayImproved.avg, (flay.avg or 0) * (1 + 1.2 + 1.44) / 3) or not near(blastImproved.avg, blast.avg) then
        emit("FAIL Improved Mind Flay 2/2 doesn't make each of the 3 ticks 20% larger than the one before")
    end

    -- Spirit Tap: half the mana regeneration while casting
    local castingBefore = A.stats.manaRegCasting
    __AURAS.player = { { name = __SPELL_NAMES[SPIRIT_TAP], spellId = SPIRIT_TAP, applications = 1, sourceUnit = "player",
        auraInstanceID = 902, duration = 15, expirationTime = 0, isHelpful = true } }
    __FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
    settle()
    local castingTap, regen = A.stats.manaRegCasting, A.stats.manaRegBase
    __AURAS.player = {}
    __FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
    settle()
    emit(("priest: mana regeneration while casting %s, %s with Spirit Tap (%s when not casting)"):format(tostring(castingBefore), tostring(castingTap), tostring(regen)))
    if regen <= 0 or not near(castingTap, castingBefore + regen * 0.5) or not near(A.stats.manaRegCasting, castingBefore) then
        emit("FAIL Spirit Tap doesn't let 50% of the mana regeneration continue while casting")
    end

    for spellId, label in pairs({ [LIGHT] = "Your Holy Fire or Shadow Word: Pain on the target", [DEMISE] = "Target at or below 20% health" }) do
        local option
        for _, group in pairs(A.AssumedTargetAuraSettings()) do
            if type(group) == "table" and group.type == "group" and group.args["aura" .. spellId] then option = group.args["aura" .. spellId].name end
        end
        if type(option) ~= "string" or not option:find(label, 1, true) then
            emit(("FAIL the target state \"%s\" isn't offered under that name: %s"):format(label, tostring(option)))
        end
    end

    local differ, examples = 0, {}
    for id, v in pairs(runAll("priest checked")) do
        if base[id] and math.abs(base[id] - v) > 1e-6 then
            differ = differ + 1
            if #examples < 4 then examples[#examples + 1] = ("%s %.2f -> %.2f"):format(name(id), base[id], v) end
        end
    end
    if differ > 0 then emit(("FAIL %d spells differ after the priest checks: %s"):format(differ, table.concat(examples, ", "))) end
end

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

-- Items that heal or deal damage: an item action shows its use spell's value, and the Item tooltip shows
-- the spell's lines
do
    local abv = A.ActionBarValues
    local itemPostCalls = {}
    for _, pc in ipairs(__TOOLTIP_POSTCALLS) do
        if pc.kind == Enum.TooltipDataType.Item then itemPostCalls[#itemPostCalls + 1] = pc.fn end
    end
    -- Prefer Blessed Prayer Beads (19990); any mapped item otherwise
    local itemId, spellId = 19990, A.itemUseSpells and A.itemUseSpells[19990]
    if not spellId then
        for id, sp in pairs(A.itemUseSpells or {}) do itemId, spellId = id, sp; break end
    end
    local mapped = 0
    for _ in pairs(A.itemUseSpells or {}) do mapped = mapped + 1 end
    if not spellId then
        emit("FAIL no item use spells in the data")
    else
        __ACTION_SLOTS[27] = { "item", itemId }
        __ACTION_SLOTS[28] = spellId
        __FireEvent("ACTIONBAR_SLOT_CHANGED", 27)
        __FireEvent("ACTIONBAR_SLOT_CHANGED", 28)
        __TickOnUpdate(10, 0.1)
        local itemText, spellText = abv:GetSlotText(27), abv:GetSlotText(28)
        GameTooltip:ClearLines()
        local terr
        for _, fn in ipairs(itemPostCalls) do
            local ok, err = xpcall(fn, debug.traceback, GameTooltip, { id = itemId, type = Enum.TooltipDataType.Item })
            if not ok then terr = err end
        end
        local itemLines = GameTooltip:NumLines()
        local spellLines = tooltipFor(spellId)
        local status, cs = checkSpell(spellId)
        local e = status == "ok" and cs.effects[1] or nil
        emit(("item use spells: %d items mapped; item %d -> spell %d %s: bar value %s (spell %s), tooltip %d lines (spell %d), %s"):format(
            mapped, itemId, spellId, name(spellId), tostring(itemText), tostring(spellText), itemLines, spellLines,
            e and ("%.0f-%.0f avg %.0f"):format(e.min or 0, e.max or 0, e.avgCombined or 0) or status))
        if terr then emit("FAIL item tooltip error: " .. (tostring(terr):gsub("\n.*", ""))) end
        if not itemText or itemText == "" or itemText ~= spellText then emit("FAIL item action does not show its spell's value") end
        if itemLines == 0 or itemLines ~= spellLines then emit("FAIL item tooltip does not show the spell's lines") end
        if status ~= "ok" then emit("FAIL item use spell does not calculate: " .. tostring(cs)) end
        __ACTION_SLOTS[27], __ACTION_SLOTS[28] = nil, nil
        __FireEvent("ACTIONBAR_SLOT_CHANGED", 0)
    end
end

-- Items that restore mana: a potion (direct) and a drink or periodic one
do
    local abv = A.ActionBarValues
    local function effectOf(itemId)
        local sp = A.itemUseSpells and A.itemUseSpells[itemId]
        local info = sp and A.spellInfo[sp]
        return info and info.effects[1], sp
    end
    local function findItem(match)
        if match(13444) then return 13444 end -- Major Mana Potion
        local best
        for itemId in pairs(A.itemUseSpells or {}) do
            if match(itemId) and (not best or itemId < best) then best = itemId end
        end
        return best
    end
    local SET, SAT = A.CONST.SPELL_EFFECT_TYPES, A.CONST.SPELL_AURA_TYPES
    local potion = findItem(function(id) local e = effectOf(id); return e ~= nil and e.effectType == SET.SPELL_EFFECT_ENERGIZE end)
    local periodic = findItem(function(id) local e = effectOf(id); return e ~= nil and e.effectType == SET.SPELL_EFFECT_APPLY_AURA
        and (e.auraType == SAT.SPELL_AURA_PERIODIC_ENERGIZE or e.auraType == SAT.SPELL_AURA_MOD_POWER_REGEN) end)
    if not potion or not periodic then
        emit(("FAIL mana items missing from the data (potion %s, periodic %s)"):format(tostring(potion), tostring(periodic)))
    else
        __ACTION_SLOTS[29] = { "item", potion }
        __ACTION_SLOTS[30] = { "item", periodic }
        __FireEvent("ACTIONBAR_SLOT_CHANGED", 29)
        __FireEvent("ACTIONBAR_SLOT_CHANGED", 30)
        __TickOnUpdate(10, 0.1)
        local _, potionSpell = effectOf(potion)
        local _, periodicSpell = effectOf(periodic)
        local ps, pcs = checkSpell(potionSpell)
        local ds, dcs = checkSpell(periodicSpell)
        local pe = ps == "ok" and pcs.effects[1] or nil
        local de = ds == "ok" and dcs.effects[1] or nil
        local potionText, periodicText = abv:GetSlotText(29), abv:GetSlotText(30)
        emit(("mana items: %s [%d] %s, mana %s (bar %s); %s [%d] %s, mana %s per tick x %s (bar %s)"):format(
            name(potionSpell), potionSpell, ps, pe and ("%.0f-%.0f"):format(pe.min, pe.max) or "?", tostring(potionText),
            name(periodicSpell), periodicSpell, ds, de and ("%.1f"):format(de.avgCombined) or "?", de and tostring(de.ticks) or "?", tostring(periodicText)))
        if not pe or pe.avgCombined <= 0 or bit.band(pe.effectFlags, A.CONST.ADDON_EFFECT_FLAGS.MANA_RESTORE) == 0 then emit("FAIL mana potion has no mana value") end
        if not potionText or potionText == "" then emit("FAIL mana potion shows no bar value") end
        if not de or not de.ticks or de.ticks < 2 or math.abs(de.avgAfterMitigation - de.avgCombined * de.ticks) > 1e-6 then emit("FAIL periodic mana item total is not ticks x per tick") end
        if not periodicText or periodicText == "" then emit("FAIL periodic mana item shows no bar value") end
        __ACTION_SLOTS[29], __ACTION_SLOTS[30] = nil, nil
        __FireEvent("ACTIONBAR_SLOT_CHANGED", 0)
    end
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
            if type(option.name) ~= "string" or option.name:match("^spell %d+") then
                emit(("FAIL target aura option in %s has no spell name: %s"):format(key, tostring(option.name)))
            end
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

-- A target aura whose spell the client doesn't know (removed by a patch or hotfix): neither offered nor applied
do
    local GHOST = 99999901
    A.aurasTarget[GHOST] = { { type = A.CONST.EFFECT_TYPE.TARGET_SCHOOLMOD_DMG_TAKEN_PCT, affectMask = 126, value = 50 } }
    table.insert(A.assumableTargetAuras, { spellId = GHOST, class = __CLASS, maxStacks = 1 })
    local offeredGhost = false
    for _, group in pairs(A.AssumedTargetAuraSettings()) do
        if type(group) == "table" and group.type == "group" and group.args["aura" .. GHOST] then offeredGhost = true end
    end
    SpellCalc_settings.assumedTargetAuras[GHOST] = 1
    A:UpdateAssumedTargetAuras()
    settle()
    local changedByGhost = 0
    for id, v in pairs(runAll("unknown target aura selected")) do
        if cleared[id] and math.abs(cleared[id] - v) > 1e-6 then changedByGhost = changedByGhost + 1 end
    end
    emit(("unknown target aura: offered %s, changed %d spells"):format(tostring(offeredGhost), changedByGhost))
    if offeredGhost then emit("FAIL a target aura whose spell the client doesn't know is offered") end
    if changedByGhost > 0 then emit("FAIL a target aura whose spell the client doesn't know is applied") end
    SpellCalc_settings.assumedTargetAuras[GHOST] = nil
    A:UpdateAssumedTargetAuras()
    table.remove(A.assumableTargetAuras)
    A.aurasTarget[GHOST] = nil
    settle()
end

-- "From caster" auras of other classes, left selected by another character (the settings are shared by the
-- account): they only change their own class's spells, so they must not be applied here.
do
    local foreign = {}
    for _, aura in ipairs(A.assumableTargetAuras) do
        if aura.fromCaster and aura.class ~= __CLASS then
            foreign[#foreign + 1] = aura.spellId
            SpellCalc_settings.assumedTargetAuras[aura.spellId] = aura.maxStacks
        end
    end
    local ok, err = pcall(A.UpdateAssumedTargetAuras, A)
    settle()
    local changedByForeign = 0
    for id, v in pairs(runAll("other classes' target auras selected")) do
        if cleared[id] and math.abs(cleared[id] - v) > 1e-6 then changedByForeign = changedByForeign + 1 end
    end
    emit(("other classes' own-damage target auras: %d selected, changed %d spells"):format(#foreign, changedByForeign))
    if not ok then emit("FAIL applying another class's target auras raised an error: " .. tostring(err)) end
    if changedByForeign > 0 then emit("FAIL target auras that only change another class's damage are applied") end
    for _, spellId in ipairs(foreign) do SpellCalc_settings.assumedTargetAuras[spellId] = nil end
    A:UpdateAssumedTargetAuras()
    settle()
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
local mp5NoBuffs = A.stats.mp5.val -- the enchant check after the restriction expects this again
__AURAS.player = auraList
__FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
settle()
local buffed = runAll("with " .. #auraList .. " buffs")

-- Every player aura in the data, applied in batches through the aura API and removed again: no Lua errors, and
-- the numbers return to the buffed state afterwards. Batches overlap for one scan (the new batch is applied
-- before the old one is removed), like a buff replaced by another rank or Master Demonologist by another demon.
do
    local ids = {}
    for id in pairs(A.aurasPlayer or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local errorsBefore = #__ERRORS
    local batches = 0
    for first = 1, #ids, 40 do
        local batch = {}
        for i = first, math.min(first + 39, #ids) do
            local id = ids[i]
            batch[#batch + 1] = { name = __SPELL_NAMES[id] or ("spell " .. id), spellId = id, applications = 1,
                sourceUnit = "player", auraInstanceID = 5000 + i, duration = 0, expirationTime = 0, isHelpful = true }
        end
        __AURAS.player = batch
        __FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
        batches = batches + 1
    end
    __AURAS.player = auraList
    __FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
    settle()
    local notRestored = 0
    for id, v in pairs(runAll("after every player aura")) do
        if buffed[id] and math.abs(buffed[id] - v) > 1e-6 then notRestored = notRestored + 1 end
    end
    local newErrors = #__ERRORS - errorsBefore
    emit(("player auras: %d applied in %d batches and removed, %d Lua errors, %d spells differ afterwards"):format(#ids, batches, newErrors, notRestored))
    if newErrors > 0 then emit("FAIL Lua error while applying player auras: " .. (tostring(__ERRORS[errorsBefore + 1]):gsub("\n.*", ""))) end
    if notRestored > 0 then emit(("FAIL %d spells differ after applying and removing every player aura"):format(notRestored)) end
end

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
-- Brilliant Mana Oil on the weapon: its mp5 comes from the enchant data, and its ID comes back secret while
-- restricted.
local mp5BeforeOil = A.stats.mp5.val
__ENCHANT = 2629
__FireEvent("UNIT_AURA", "player")
settle()
local oilMp5 = A.enchantData[2629] and A.enchantData[2629].value or 0
emit(("weapon enchant: Brilliant Mana Oil gives mp5 +%d (enchant data says %d)"):format(A.stats.mp5.val - mp5BeforeOil, oilMp5))
if oilMp5 == 0 or math.abs(A.stats.mp5.val - mp5BeforeOil - oilMp5) > 1e-6 then emit("FAIL the weapon enchant did not apply its mp5") end
local beforeRestriction = runAll("before restriction")
__RESTRICTIONS[CHALLENGE] = true
__FireEvent("ADDON_RESTRICTION_STATE_CHANGED", CHALLENGE, Enum.AddOnRestrictionState.Active)
__FireEvent("UNIT_AURA", "player") -- the enchant ID comes back secret now
__AURAS.player = {} -- the buffs run out meanwhile
__ENCHANT = false   -- and so does the oil
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
if math.abs(A.stats.mp5.val - mp5NoBuffs) > 1e-6 then emit(("FAIL mp5 is %d after the oil and buffs ran out, expected %d"):format(A.stats.mp5.val, mp5NoBuffs)) end
local notResynced = 0
for id, v in pairs(lifted) do
    if cleared[id] and math.abs(cleared[id] - v) > 1e-6 then notResynced = notResynced + 1 end
end
emit(("restriction: %d spells changed while restricted, %d differ from the unbuffed numbers after it lifted"):format(changedUnder, notResynced))
if changedUnder > 0 then emit("FAIL numbers changed while restricted instead of keeping the last snapshot") end
if notResynced > 0 then emit("FAIL no resync after the restriction lifted (buffs that ran out still count)") end

-- Stats that come back secret while no restriction is reported (the restriction state lagging behind the
-- values): the read must keep the old values rather than store 0, and happen again once a restriction clears.
do
    local watched = {
        { "spell power", function() return A.stats.spellPower[2] end },
        { "spell crit", function() return A.stats.spellCrit[2] end },
        { "healing", function() return A.stats.spellHealing end },
        { "attack power", function() return A.stats.attackPower end },
        { "max mana", function() return A.stats.manaMax end },
        { "spirit regen", function() return A.stats.manaRegBase end },
        { "melee damage", function() return A.stats.attackDmg.mainhand.max end },
        { "attack speed", function() return A.stats.attackSpeed.mainhand end },
        { "weapon skill", function() return A.stats.attack.mainhand end },
    }
    local before = {}
    for i, w in ipairs(watched) do before[i] = w[2]() end
    __STATS_SECRET = true
    __SPELL_POWER = 450 -- changes while the addon cannot read it
    for _, event in ipairs({ "SPELL_POWER_CHANGED", "UNIT_STATS", "PLAYER_DAMAGE_DONE_MODS", "UNIT_ATTACK_POWER",
        "UNIT_RANGED_ATTACK_POWER", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED", "UNIT_ATTACK", "UNIT_AURA" }) do
        __FireEvent(event, "player")
    end
    settle()
    local kept = 0
    for i, w in ipairs(watched) do
        local v = w[2]()
        if v == before[i] and not issecretvalue(v) then
            kept = kept + 1
        else
            emit(("FAIL %s became %s while the API returned secret values (was %s)"):format(w[1], tostring(v), tostring(before[i])))
        end
    end
    __STATS_SECRET = false
    __FireEvent("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Combat, Enum.AddOnRestrictionState.Inactive)
    settle()
    local after = A.stats.spellPower[2]
    emit(("secret stats without a restriction: %d of %d values kept; spell power %s once a restriction state cleared (450 meanwhile)")
        :format(kept, #watched, tostring(after)))
    if after ~= 450 then emit("FAIL stats not re-read once the restriction state cleared") end
    __SPELL_POWER = 400
    __FireEvent("SPELL_POWER_CHANGED")
    settle()
end
__AURAS.player = auraList

return table.concat(out, "\n")
