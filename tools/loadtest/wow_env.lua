-- Minimal World of Warcraft: Forever API environment for loading SpellCalc_Forever headless.
-- Runs on fengari (Lua 5.3); WoW uses Lua 5.1, so a few 5.1 names are shimmed first.
-- Values returned by the unit/stat stubs are plausible level 60 numbers, not real client data.
-- Everything the addon touches that is not defined here is recorded in __MISSING_GLOBALS /
-- __MISSING_MEMBERS so the test can report it.

----------------------------------------------------------------------------------------------
-- Lua 5.1 compatibility
----------------------------------------------------------------------------------------------
unpack = table.unpack
loadstring = load
table.getn = function(t) return #t end
math.mod = math.fmod
math.pow = function(a, b) return a ^ b end
string.gfind = string.gmatch
getfenv = function() return _G end
setfenv = function(f) return f end

-- Lua 5.1 truncates floats passed to integer format specifiers; 5.3 raises an error instead.
local rawformat = string.format
local INT_SPECS = { d = true, i = true, x = true, X = true, o = true, c = true }
string.format = function(fmt, ...)
    local args = table.pack(...)
    local i = 0
    for spec in tostring(fmt):gmatch("%%[-+ #0]*%d*%.?%d*([%a%%])") do
        if spec ~= "%" then
            i = i + 1
            if INT_SPECS[spec] and type(args[i]) == "number" then
                local v = args[i]
                if v ~= v or v == math.huge or v == -math.huge then v = 0 end
                args[i] = v >= 0 and math.floor(v) or math.ceil(v)
            end
        end
    end
    return rawformat(fmt, table.unpack(args, 1, args.n))
end

-- WoW's bit library is Lua BitOp: arguments wrap to 32 bits and results are SIGNED 32 bit
-- integers, so a result with bit 31 set is negative (bit.band(2^31, 2^31) == -2147483648).
local M32 = 0xFFFFFFFF
local function u32(x)
    x = math.floor(x)
    return math.tointeger(x) and (math.tointeger(x) & M32) or 0
end
local function s32(v)
    v = v & M32
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end
bit = {
    band = function(...) local r = M32; for i = 1, select("#", ...) do r = r & u32(select(i, ...)) end return s32(r) end,
    bor = function(...) local r = 0; for i = 1, select("#", ...) do r = r | u32(select(i, ...)) end return s32(r) end,
    bxor = function(...) local r = 0; for i = 1, select("#", ...) do r = r ~ u32(select(i, ...)) end return s32(r) end,
    bnot = function(a) return s32(~u32(a)) end,
    lshift = function(a, n) return s32(u32(a) << (n % 32)) end,
    rshift = function(a, n) return s32(u32(a) >> (n % 32)) end,
    arshift = function(a, n) return s32(s32(u32(a)) >> (n % 32) | (s32(u32(a)) < 0 and ~(M32 >> (n % 32)) or 0)) end,
    tobit = function(a) return s32(u32(a)) end,
}

----------------------------------------------------------------------------------------------
-- Test bookkeeping
----------------------------------------------------------------------------------------------
__MISSING_GLOBALS = {}
__MISSING_MEMBERS = {}
__UNKNOWN_METHODS = {}
__PRINTS = {}
__ERRORS = {}
__TIMERS = {}
__TOOLTIP_POSTCALLS = {}
__REGISTERED_EVENTS = {}
__AURAS = { player = {}, target = {} }
__TALENT_RANKS = {}     -- [spellId] = rank, simulated purchased talents
__TALENT_TREE = {}      -- list of { spellId = n, maxRanks = n }
__CLASS = __CLASS or "MAGE"
__SPELL_NAMES = __SPELL_NAMES or {}
__SPELL_SUBTEXT = __SPELL_SUBTEXT or {}
__NOW = 1000

local function noop() end

print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    __PRINTS[#__PRINTS + 1] = table.concat(parts, " ")
end

local function recordError(msg)
    __ERRORS[#__ERRORS + 1] = tostring(msg)
end
geterrorhandler = function() return recordError end
seterrorhandler = noop
securecall = function(f, ...) if type(f) == "string" then f = _G[f] end return f(...) end
securecallfunction = securecall
issecure = function() return false end
forceinsecure = noop

---Namespace table that records access to members the stubs don't define.
local function namespace(name, t)
    return setmetatable(t, { __index = function(_, k)
        local key = name .. "." .. tostring(k)
        __MISSING_MEMBERS[key] = (__MISSING_MEMBERS[key] or 0) + 1
        return nil
    end })
end

----------------------------------------------------------------------------------------------
-- WoW Lua globals (string/table helpers)
----------------------------------------------------------------------------------------------
strmatch = string.match; strfind = string.find; strsub = string.sub; strlen = string.len
strlower = string.lower; strupper = string.upper; strrep = string.rep; strbyte = string.byte
strchar = string.char; gsub = string.gsub; gmatch = string.gmatch; format = string.format
strrev = string.reverse
floor = math.floor; ceil = math.ceil; abs = math.abs; min = math.min; max = math.max
sqrt = math.sqrt; mod = math.fmod; random = math.random
tinsert = table.insert; tremove = table.remove; sort = table.sort; tconcat = table.concat
date = os and os.date or function() return "" end
time = os and os.time or function() return 0 end

strtrim = function(s, chars)
    chars = chars and ("[" .. chars:gsub("%p", "%%%0") .. "]") or "%s"
    return (s:gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
end
strsplit = function(delim, str, pieces)
    local out, start = {}, 1
    pieces = pieces or 0
    while true do
        if pieces > 0 and #out == pieces - 1 then out[#out + 1] = str:sub(start); break end
        local s, e = str:find(delim, start, true)
        if not s then out[#out + 1] = str:sub(start); break end
        out[#out + 1] = str:sub(start, s - 1)
        start = e + 1
    end
    return table.unpack(out)
end
strsplittable = function(delim, str, pieces) return { strsplit(delim, str, pieces) } end
strjoin = function(delim, ...) return table.concat({ ... }, delim) end
strconcat = function(...) return table.concat({ ... }) end
tostringall = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end return table.unpack(t) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
tInvert = function(t) local r = {}; for k, v in pairs(t) do r[v] = k end return r end
CopyTable = function(t) local r = {}; for k, v in pairs(t) do r[k] = type(v) == "table" and CopyTable(v) or v end return r end
Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
CreateFromMixins = function(...) return Mixin({}, ...) end
GetTime = function() return __NOW end
GetTimePreciseSec = GetTime
debugprofilestop = function() return __NOW * 1000 end
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.60.1", "70532", "Oct 21 2026", 16001 end
IsLoggedIn = function() return true end
GetCVar = function() return nil end
GetCVarBool = function() return false end
SetCVar = noop
Ambiguate = function(name) return name end
GetCursorPosition = function() return 0, 0 end
GetScreenWidth = function() return 1920 end
GetScreenHeight = function() return 1080 end
PlaySound = noop
StaticPopup_Show = noop
StaticPopupDialogs = {}
CloseDropDownMenus = noop
GetMouseFocus = noop
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
IsAltKeyDown = function() return false end

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_CAMELOT = 18
WOW_PROJECT_ID = 18
LE_UNIT_STAT_STRENGTH, LE_UNIT_STAT_AGILITY, LE_UNIT_STAT_STAMINA, LE_UNIT_STAT_INTELLECT, LE_UNIT_STAT_SPIRIT = 1, 2, 3, 4, 5
INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED = 16, 17, 18
SCHOOL_STRINGS = { "Physical", "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0, GetRGB = function(s) return s.r, s.g, s.b end }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1, GetRGB = function(s) return s.r, s.g, s.b end }
GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5, GetRGB = function(s) return s.r, s.g, s.b end }
ChatFontNormal = {}
GameFontNormal = {}; GameFontHighlight = {}; GameFontHighlightSmall = {}; GameFontNormalSmall = {}
GameFontDisable = {}; GameFontNormalLarge = {}; GameFontHighlightLarge = {}
CLOSE = "Close"; OKAY = "Okay"; CANCEL = "Cancel"; ACCEPT = "Accept"; DEFAULTS = "Defaults"

SlashCmdList = {}
hash_SlashCmdList = {}

hooksecurefunc = function(a, b, c)
    local tbl, name, fn
    if type(a) == "table" then tbl, name, fn = a, b, c else tbl, name, fn = _G, a, b end
    local orig = rawget(tbl, name) or tbl[name]
    if type(orig) ~= "function" then return end
    tbl[name] = function(...)
        local r = table.pack(orig(...))
        fn(...)
        return table.unpack(r, 1, r.n)
    end
end

----------------------------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------------------------
local FrameMethods = {}
local FrameMT = {}
local allFrames = {}

local function newObject(kind, name, parent)
    local o = setmetatable({ __kind = kind, __name = name, __parent = parent, __scripts = {},
        __events = {}, __shown = true, __lines = {}, __text = "", __children = {} }, FrameMT)
    if type(parent) == "table" and rawget(parent, "__children") then
        table.insert(parent.__children, o)
    end
    if name and name ~= "" then
        if parent and type(parent) == "table" and name:find("$parent", 1, true) then
            name = name:gsub("%$parent", parent.__name or "")
            o.__name = name
        end
        rawset(_G, name, o)
    end
    allFrames[#allFrames + 1] = o
    return o
end
__newObject = newObject

-- Unknown capitalised keys are either widget methods (called as frame:Foo()) or template
-- children (frame.ScrollBar). Return a child object that is also callable as a no-op method.
FrameMT.__call = function() return nil end
FrameMT.__index = function(t, k)
    local m = FrameMethods[k]
    if m then return m end
    if type(k) == "string" and k:match("^[A-Z]") then
        __UNKNOWN_METHODS[k] = (__UNKNOWN_METHODS[k] or 0) + 1
        local child = newObject("Frame", nil, t)
        rawset(t, k, child)
        return child
    end
    return nil
end

function FrameMethods:GetName() return self.__name end
function FrameMethods:GetParent() return self.__parent end
function FrameMethods:SetParent(p) self.__parent = p end
function FrameMethods:GetObjectType() return self.__kind end
function FrameMethods:IsObjectType(t) return self.__kind == t end
function FrameMethods:IsForbidden() return false end
function FrameMethods:SetScript(name, fn) self.__scripts[name] = fn end
function FrameMethods:GetScript(name) return self.__scripts[name] end
function FrameMethods:HasScript() return true end
function FrameMethods:HookScript(name, fn)
    local orig = self.__scripts[name]
    self.__scripts[name] = function(...) if orig then orig(...) end fn(...) end
end
function FrameMethods:RegisterEvent(e)
    if type(e) ~= "string" then error("RegisterEvent: event must be a string") end
    self.__events[e] = true
    __REGISTERED_EVENTS[e] = true
end
FrameMethods.RegisterUnitEvent = FrameMethods.RegisterEvent
function FrameMethods:UnregisterEvent(e) self.__events[e] = nil end
function FrameMethods:UnregisterAllEvents() self.__events = {} end
function FrameMethods:IsEventRegistered(e) return self.__events[e] == true end
function FrameMethods:Show() self.__shown = true end
function FrameMethods:Hide() self.__shown = false end
function FrameMethods:SetShown(v) self.__shown = v and true or false end
function FrameMethods:IsShown() return self.__shown end
function FrameMethods:IsVisible() return self.__shown end
function FrameMethods:GetWidth() return 100 end
function FrameMethods:GetHeight() return 20 end
function FrameMethods:GetSize() return 100, 20 end
function FrameMethods:GetLeft() return 0 end
function FrameMethods:GetRight() return 100 end
function FrameMethods:GetTop() return 20 end
function FrameMethods:GetBottom() return 0 end
function FrameMethods:GetCenter() return 50, 10 end
function FrameMethods:GetScale() return 1 end
function FrameMethods:GetEffectiveScale() return 1 end
function FrameMethods:GetFrameLevel()
    if self.__level then return self.__level end
    local p = rawget(self, "__parent")
    if type(p) == "table" and p.GetFrameLevel then return p:GetFrameLevel() + 1 end
    return 1
end
function FrameMethods:SetFrameLevel(l) self.__level = l end
function FrameMethods:SetPoint(point, rel, relPoint, x, y) self.__point = { point, rel, relPoint, x, y } end
function FrameMethods:ClearAllPoints() self.__point = nil end
function FrameMethods:SetFont(font, size, flags) self.__font, self.__fontSize, self.__flags = font, size, flags; return true end
function FrameMethods:SetShadowOffset(x, y) self.__shadowOffset = { x, y } end
function FrameMethods:SetJustifyH(j) self.__justifyH = j end
function FrameMethods:GetFrameStrata() return "MEDIUM" end
function FrameMethods:GetNumPoints() return 0 end
function FrameMethods:GetAlpha() return 1 end
function FrameMethods:GetID() return self.__id or 0 end
function FrameMethods:SetID(id) self.__id = id end
function FrameMethods:GetAttribute(k) return self.__attr and self.__attr[k] end
function FrameMethods:SetAttribute(k, v) self.__attr = self.__attr or {}; self.__attr[k] = v end
function FrameMethods:SetText(t) self.__text = t end
function FrameMethods:GetText() return self.__text end
function FrameMethods:SetFormattedText(f, ...) self.__text = string.format(f, ...) end
function FrameMethods:GetStringWidth() return 50 end
function FrameMethods:GetStringHeight() return 12 end
function FrameMethods:GetFont() return STANDARD_TEXT_FONT, 12, "" end
function FrameMethods:GetNumChildren() return 0 end
function FrameMethods:GetChildren() end
function FrameMethods:GetRegions() end
function FrameMethods:GetNumRegions() return 0 end
function FrameMethods:IsMouseOver() return false end
function FrameMethods:CreateFontString(name) return newObject("FontString", name, self) end
function FrameMethods:CreateTexture(name) return newObject("Texture", name, self) end
function FrameMethods:CreateMaskTexture(name) return newObject("MaskTexture", name, self) end
function FrameMethods:CreateLine(name) return newObject("Line", name, self) end
function FrameMethods:CreateAnimationGroup(name) return newObject("AnimationGroup", name, self) end
function FrameMethods:CreateAnimation(kind, name) return newObject(kind or "Animation", name, self) end
function FrameMethods:GetFontString() self.__fs = self.__fs or newObject("FontString", nil, self); return self.__fs end
function FrameMethods:GetNormalTexture() return newObject("Texture", nil, self) end
function FrameMethods:GetHighlightTexture() return newObject("Texture", nil, self) end
function FrameMethods:GetPushedTexture() return newObject("Texture", nil, self) end
function FrameMethods:GetScrollChild() return self.__scrollChild end
function FrameMethods:SetScrollChild(c) self.__scrollChild = c end
function FrameMethods:GetVerticalScroll() return 0 end
function FrameMethods:GetVerticalScrollRange() return 0 end
function FrameMethods:GetValue() return 0 end
function FrameMethods:GetMinMaxValues() return 0, 1 end
function FrameMethods:GetChecked() return false end
function FrameMethods:IsEnabled() return true end
-- Tooltip methods
function FrameMethods:AddLine(text) self.__lines[#self.__lines + 1] = tostring(text) end
function FrameMethods:AddDoubleLine(l, r) self.__lines[#self.__lines + 1] = tostring(l) .. " || " .. tostring(r) end
function FrameMethods:NumLines() return #self.__lines end
function FrameMethods:ClearLines() self.__lines = {} end
function FrameMethods:IsOwned() return true end
function FrameMethods:GetOwner() return UIParent end
function FrameMethods:GetSpell() return nil end
function FrameMethods:GetItem() return nil end
function FrameMethods:GetUnit() return nil end

CreateFrame = function(kind, name, parent, template, id)
    if type(kind) ~= "string" then error("CreateFrame: invalid frame type") end
    local f = newObject(kind, name, parent)
    f.__template = template
    if id then f.__id = id end
    return f
end

UIParent = newObject("Frame", "UIParent")
WorldFrame = newObject("Frame", "WorldFrame")
DEFAULT_CHAT_FRAME = newObject("ScrollingMessageFrame", "DEFAULT_CHAT_FRAME")
GameTooltip = newObject("GameTooltip", "GameTooltip", UIParent)
ItemRefTooltip = newObject("GameTooltip", "ItemRefTooltip", UIParent)
SettingsPanel = newObject("Frame", "SettingsPanel", UIParent)
MainActionBar = newObject("Frame", "MainActionBar", UIParent)
for i = 1, 12 do
    local button = newObject("CheckButton", "ActionButton" .. i, MainActionBar)
    -- Stock action buttons have a cooldown frame one level above the button.
    button.cooldown = newObject("Cooldown", nil, button)
    button.cooldown:SetFrameLevel(button:GetFrameLevel() + 1)
    for _, bar in ipairs({ "MultiBarRightButton", "MultiBarLeftButton", "MultiBarBottomRightButton", "MultiBarBottomLeftButton" }) do
        newObject("CheckButton", bar .. i, UIParent)
    end
end

--- Fire an event to every frame that registered it.
function __FireEvent(event, ...)
    for _, f in ipairs(allFrames) do
        if f.__events[event] and f.__scripts.OnEvent then
            local ok, err = xpcall(f.__scripts.OnEvent, debug.traceback, f, event, ...)
            if not ok then recordError(event .. ": " .. tostring(err)) end
        end
    end
end

--- Run OnUpdate scripts of shown frames for `ticks` frames of `elapsed` seconds each.
function __TickOnUpdate(ticks, elapsed)
    for _ = 1, ticks or 10 do
        __NOW = __NOW + (elapsed or 0.1)
        for _, f in ipairs(allFrames) do
            local fn = f.__scripts.OnUpdate
            if fn and f.__shown then
                local ok, err = xpcall(fn, debug.traceback, f, elapsed or 0.1)
                if not ok then recordError("OnUpdate: " .. tostring(err)) end
            end
        end
    end
end

----------------------------------------------------------------------------------------------
-- C_Timer
----------------------------------------------------------------------------------------------
local function addTimer(seconds, fn, iterations)
    local t = { due = __NOW + (seconds or 0), fn = fn, cancelled = false, left = iterations or 1 }
    t.Cancel = function(self) self.cancelled = true end
    t.IsCancelled = function(self) return self.cancelled end
    __TIMERS[#__TIMERS + 1] = t
    return t
end
C_Timer = namespace("C_Timer", {
    After = function(s, fn) addTimer(s, fn, 1) end,
    NewTimer = function(s, fn) return addTimer(s, fn, 1) end,
    NewTicker = function(s, fn, n) return addTimer(s, fn, n or 1) end,
})

--- Run due timers, advancing the clock. Repeating tickers run at most `n` times in total.
function __RunTimers(maxRounds)
    for _ = 1, maxRounds or 50 do
        if #__TIMERS == 0 then return end
        local pending = __TIMERS
        __TIMERS = {}
        local latest = __NOW
        for _, t in ipairs(pending) do if t.due > latest then latest = t.due end end
        __NOW = latest
        for _, t in ipairs(pending) do
            if not t.cancelled then
                local ok, err = xpcall(t.fn, debug.traceback, t)
                if not ok then recordError("timer: " .. tostring(err)) end
                t.left = t.left - 1
            end
        end
    end
end

----------------------------------------------------------------------------------------------
-- Addon/settings APIs
----------------------------------------------------------------------------------------------
C_AddOns = namespace("C_AddOns", {
    IsAddOnLoaded = function() return false end,
    GetAddOnMetadata = function(_, field) return field == "Version" and "0.1.0" or nil end,
    LoadAddOn = function() return false end,
    GetAddOnEnableState = function() return 0 end,
    DoesAddOnExist = function() return false end,
})
IsAddOnLoaded = C_AddOns.IsAddOnLoaded
GetAddOnMetadata = C_AddOns.GetAddOnMetadata

local nextCategory = 100
local function newCategory(name)
    nextCategory = nextCategory + 1
    local id = nextCategory
    return { ID = id, name = name, GetID = function() return id end, GetName = function() return name end,
        SetOrder = noop, SetParentCategory = noop }
end
Settings = namespace("Settings", {
    RegisterCanvasLayoutCategory = function(_, name) return newCategory(name) end,
    RegisterCanvasLayoutSubcategory = function(_, _, name) return newCategory(name) end,
    RegisterVerticalLayoutCategory = function(name) return newCategory(name) end,
    RegisterAddOnCategory = noop,
    OpenToCategory = noop,
    GetCategory = function() return nil end,
})

----------------------------------------------------------------------------------------------
-- Tooltips
----------------------------------------------------------------------------------------------
Enum = {
    TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
    ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6 },
    ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5, Polearm = 6,
        Sword1H = 7, Sword2H = 8, Warglaive = 9, Staff = 10, Bearclaw = 11, Catclaw = 12, Unarmed = 13,
        Generic = 14, Dagger = 15, Thrown = 16, Obsolete3 = 17, Crossbow = 18, Wand = 19, Fishingpole = 20 },
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4 },
}
TooltipDataProcessor = namespace("TooltipDataProcessor", {
    AddTooltipPostCall = function(kind, fn) __TOOLTIP_POSTCALLS[#__TOOLTIP_POSTCALLS + 1] = { kind = kind, fn = fn } end,
    AddLinePostCall = noop,
})
TooltipUtil = namespace("TooltipUtil", {
    GetDisplayedSpell = function() return nil end,
    GetDisplayedItem = function() return nil end,
})

----------------------------------------------------------------------------------------------
-- Spells and items
----------------------------------------------------------------------------------------------
local nameToId = nil
local function spellIdOf(ident)
    if type(ident) == "number" then return ident end
    if type(ident) ~= "string" then return nil end
    if not nameToId then
        nameToId = {}
        for id, name in pairs(__SPELL_NAMES) do
            if not nameToId[name] or id < nameToId[name] then nameToId[name] = id end
        end
    end
    return nameToId[ident] or tonumber(ident)
end

C_Spell = namespace("C_Spell", {
    GetSpellInfo = function(ident)
        local id = spellIdOf(ident)
        local name = id and __SPELL_NAMES[id]
        if not name then return nil end
        return { name = name, iconID = 136243, originalIconID = 136243, castTime = 2000, minRange = 0, maxRange = 30, spellID = id }
    end,
    GetSpellName = function(ident) local id = spellIdOf(ident); return id and __SPELL_NAMES[id] end,
    GetSpellSubtext = function(ident) local id = spellIdOf(ident); return id and __SPELL_SUBTEXT[id] or "" end,
    GetSpellPowerCost = function(ident)
        if not spellIdOf(ident) then return nil end
        return { { type = 0, name = "MANA", cost = 100, minCost = 100, costPercent = 0, costPerSec = 0, requiredAuraID = 0, hasRequiredAura = false } }
    end,
    GetSpellDescription = function() return "" end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 } end,
    GetSpellTexture = function() return 136243 end,
    IsSpellPassive = function() return false end,
    DoesSpellExist = function(ident) local id = spellIdOf(ident); return id ~= nil and __SPELL_NAMES[id] ~= nil end,
    GetSpellLink = function(ident) local id = spellIdOf(ident); return id and ("|Hspell:" .. id .. "|h[" .. (__SPELL_NAMES[id] or "?") .. "]|h") end,
})
C_SpellBook = namespace("C_SpellBook", {
    FindSpellBookSlotForSpell = function() return nil end,
    GetSpellBookItemInfo = function() return nil end,
    IsSpellInSpellBook = function() return true end,
    IsSpellKnown = function() return true end,
})
IsSpellKnown = function() return true end
IsPlayerSpell = function() return true end

-- Any item ID is a cached cloth armor piece; the driver equips items through __INVENTORY (slot -> item ID).
__INVENTORY = {}
C_Item = namespace("C_Item", {
    GetItemInfo = function(item)
        local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
        if not id then return nil end
        return "item " .. id, ("|cffa335ee|Hitem:%d::::::::60:::::|h[item %d]|h|r"):format(id, id), 4, 60, 60, "Armor", "Cloth",
            1, "INVTYPE_CHEST", 0, 0, 4, 1
    end,
    GetItemInfoInstant = function() return nil end,
    GetItemStats = function() return {} end,
    GetItemSetInfo = function() return nil end,
    GetItemNameByID = function() return nil end,
    RequestLoadItemDataByID = noop,
    IsItemDataCachedByID = function() return false end,
})
C_TooltipInfo = namespace("C_TooltipInfo", {
    GetItemByID = function() return { lines = { { leftText = "Two-Hand", rightText = "Staff" }, { leftText = "100 - 150 Damage", rightText = "Speed 3.00" } } } end,
    GetSpellByID = function() return { lines = {} } end,
})
LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin", PRIEST = "Priest",
    ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior" }
GetInventoryItemLink = function(unit, slot)
    local id = unit == "player" and __INVENTORY[slot]
    if id then return (select(2, C_Item.GetItemInfo(id))) end
end
GetInventoryItemID = function(unit, slot) if unit == "player" then return __INVENTORY[slot] end end
GetInventoryItemDurability = function() return nil end
GetWeaponEnchantInfo = function() return false end

----------------------------------------------------------------------------------------------
-- Unit and stats (plausible level 60 caster values)
----------------------------------------------------------------------------------------------
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
issecretvalue = function() return false end
InCombatLockdown = function() return false end
UnitClass = function(unit)
    if unit == "player" then return __CLASS:sub(1, 1) .. __CLASS:sub(2):lower(), __CLASS, CLASS_IDS[__CLASS] end
    return nil
end
UnitRace = function(unit) if unit == "player" then return "Human", "Human", 1 end end
UnitName = function(unit) if unit == "player" then return "Tester" end end
UnitGUID = function(unit) if unit == "player" then return "Player-1-00000001" end end
UnitExists = function(unit) return unit == "player" end
UnitIsUnit = function(a, b) return a == b end
UnitIsPlayer = function(unit) return unit == "player" end
UnitIsFriend = function() return true end
UnitCanAttack = function() return false end
UnitCreatureType = function() return nil end
UnitLevel = function(unit) if unit == "player" then return 60 end return -1 end
UnitEffectiveLevel = UnitLevel
UnitSex = function() return 2 end
UnitStat = function(_, i) return 100, 150, 50, 0 end
UnitPower = function() return 4000 end
UnitPowerMax = function() return 5000 end
UnitPowerType = function() return 0, "MANA" end
UnitHealth = function() return 3000 end
UnitHealthMax = function() return 3000 end
UnitArmor = function() return 1000, 1000, 1000, 0, 0 end
UnitResistance = function() return 0, 0, 0, 0 end
UnitAttackPower = function() return 800, 100, 0 end
UnitRangedAttackPower = function() return 300, 0, 0 end
UnitDamage = function() return 100, 150, 0, 0, 0, 0, 1 end
UnitRangedDamage = function() return 0, 0, 0, 0, 0, 1 end
UnitAttackSpeed = function() return 2.6, nil end
UnitAffectingCombat = function() return false end
GetSpellBonusDamage = function() return 400 end
GetSpellBonusHealing = function() return 700 end
GetSpellCritChance = function() return 8.5 end
GetCritChance = function() return 7 end
GetRangedCritChance = function() return 5 end
GetHitModifier = function() return 0 end
GetSpellHitModifier = function() return 0 end
GetManaRegen = function() return 12, 3 end
GetExpertise = function() return 0, 0 end
GetCombatRatingBonus = function() return 0 end
GetComboPoints = function() return 0 end
GetShapeshiftForm = function() return 0 end
GetShapeshiftFormInfo = function() return nil end
GetNumShapeshiftForms = function() return 0 end
__ACTION_SLOTS = {}
GetActionInfo = function(slot) local id = __ACTION_SLOTS[slot]; if id then return "spell", id end end
HasAction = function(slot) return __ACTION_SLOTS[slot] ~= nil end
GetMacroSpell = function() return nil end
GetActionBarPage = function() return 1 end
GetBonusBarOffset = function() return 0 end

C_UnitAuras = namespace("C_UnitAuras", {
    GetAuraDataByIndex = function(unit, index) local l = __AURAS[unit]; return l and l[index] end,
    GetPlayerAuraBySpellID = function(id) for _, a in ipairs(__AURAS.player) do if a.spellId == id then return a end end end,
    GetAuraDataBySpellName = function() return nil end,
})

C_SkillInfo = namespace("C_SkillInfo", {
    GetSkillLineInfoByID = function(id) return { skillLineID = id, rank = 300, maxRank = 300, modifier = 0, name = "Skill " .. tostring(id) } end,
})

----------------------------------------------------------------------------------------------
-- Talents (trait system); ranks are simulated through __TALENT_TREE / __TALENT_RANKS
----------------------------------------------------------------------------------------------
local CONFIG_ID, TREE_ID = 4001, 1112
C_SpecializationInfo = namespace("C_SpecializationInfo", {
    GetActiveSpecGroup = function() return 1 end,
    GetCombatConfigIDForSpecGroup = function(group) return group == 1 and CONFIG_ID or nil end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return nil end,
})
C_ClassTalents = namespace("C_ClassTalents", {
    GetActiveConfigID = function() return CONFIG_ID end,
})
C_Traits = namespace("C_Traits", {
    GetConfigInfo = function(id) if id == CONFIG_ID then return { ID = id, treeIDs = { TREE_ID }, type = 1 } end end,
    GetTreeNodes = function(tree)
        if tree ~= TREE_ID then return {} end
        local ids = {}
        for i = 1, #__TALENT_TREE do ids[i] = 10000 + i end
        return ids
    end,
    GetNodeInfo = function(_, nodeID)
        local t = __TALENT_TREE[nodeID - 10000]
        if not t then return nil end
        local rank = __TALENT_RANKS[t.spellId] or 0
        return { ID = nodeID, maxRanks = t.maxRanks, activeRank = rank, ranksPurchased = rank, entryIDs = { 20000 + nodeID - 10000 },
            activeEntry = rank > 0 and { entryID = 20000 + nodeID - 10000, rank = rank } or nil }
    end,
    GetEntryInfo = function(_, entryID) return { definitionID = 30000 + entryID - 20000, maxRanks = 5, type = 1 } end,
    GetDefinitionInfo = function(defID)
        local t = __TALENT_TREE[defID - 30000]
        return t and { spellID = t.spellId } or nil
    end,
})

----------------------------------------------------------------------------------------------
-- Track globals the stubs don't define (must be last)
----------------------------------------------------------------------------------------------
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" then __MISSING_GLOBALS[k] = (__MISSING_GLOBALS[k] or 0) + 1 end
    return nil
end })
