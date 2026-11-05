---@class AddonEnv
local _addon = select(2, ...);

local LSM = LibStub("LibSharedMedia-3.0");

---@class ABFontString : FontString
---@field ApplyStyle fun(self:ABFontString, style:ABTextStyle)
---@field SetIsHeal fun(self:ABFontString, isHeal:boolean|nil, isMana:boolean|nil)
---@field button WoWFrame The action button
---@field overlay WoWFrame Frame holding the text, above the button's cooldown swipe
---@field isHeal boolean|nil
---@field isMana boolean|nil

---@class ABTextStyle
---@field font string
---@field size number
---@field flags string
---@field shadow boolean
---@field anchor string
---@field x number
---@field y number

---@type ABFontString[]
local buttonFontStrings = {};
---@type ActionButtonText|nil
local isSetup = nil;
local colorHarm = {1, 1, 0.3};
local colorHelp = {0.3, 1, 0.3};
local colorMana = {0.1, 0.7, 1};

--- Horizontal justification that matches an anchor point, so text grows away from the button edge.
local ANCHOR_JUSTIFY = {
    TOPLEFT = "LEFT", LEFT = "LEFT", BOTTOMLEFT = "LEFT",
    TOPRIGHT = "RIGHT", RIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT",
};

------------------------------------------------------------------------
-- Button Fontstring
------------------------------------------------------------------------

--- Frame level for the text overlay: above the button and its cooldown frames.
-- Regions (textures, font strings) of a frame always draw below child frames with a higher frame level,
-- so text on the button itself would be hidden by the cooldown swipe whatever its draw layer. The overlay
-- stays below Blizzard's own hotkey/count container, so those still draw on top.
---@param button WoWFrame
---@return integer
local function OverlayLevel(button)
    local level = button:GetFrameLevel();
    for _, key in ipairs({ "cooldown", "Cooldown", "chargeCooldown", "lossOfControlCooldown" }) do
        local cd = button[key];
        if type(cd) == "table" and cd.GetFrameLevel then
            level = math.max(level, cd:GetFrameLevel());
        end
    end
    return level + 2;
end

--- Set text color to dmg or heal.
---@param self ABFontString
---@param isHeal boolean|nil
---@param isMana boolean|nil
local function SetIsHeal(self, isHeal, isMana)
    if isHeal then
        self:SetTextColor(colorHelp[1], colorHelp[2], colorHelp[3]);
    elseif isMana then
        self:SetTextColor(colorMana[1], colorMana[2], colorMana[3]);
    else
        self:SetTextColor(colorHarm[1], colorHarm[2], colorHarm[3]);
    end
    self.isHeal = isHeal;
    self.isMana = isMana;
end

--- Apply font, outline, shadow and position.
---@param self ABFontString
---@param style ABTextStyle
local function ApplyStyle(self, style)
    -- Re-applied on every style update: bar addons may change their buttons' frame levels later.
    self.overlay:SetFrameLevel(OverlayLevel(self.button));

    self:SetFont(style.font, style.size, style.flags);
    if style.shadow then
        self:SetShadowColor(0, 0, 0, 1);
        self:SetShadowOffset(1, -1);
    else
        self:SetShadowColor(0, 0, 0, 0);
        self:SetShadowOffset(0, 0);
    end

    self:ClearAllPoints();
    self:SetPoint(style.anchor, self.overlay, style.anchor, style.x, style.y);
    self:SetJustifyH(ANCHOR_JUSTIFY[style.anchor] or "CENTER");
    self:SetIsHeal(self.isHeal, self.isMana);
end

--- Add string to the given button frame.
---@param buttonFrame WoWFrame
---@return ABFontString
local function CreateActionButtonFS(buttonFrame)
    -- A plain child frame: no mouse input, not protected, so the text can change at any time.
    local overlay = CreateFrame("Frame", nil, buttonFrame);
    overlay:SetAllPoints(buttonFrame);
    overlay:SetFrameLevel(OverlayLevel(buttonFrame));

    local fs = overlay:CreateFontString(nil, "OVERLAY")--[[@as ABFontString]];
    fs:SetWordWrap(false);
    fs.button = buttonFrame;
    fs.overlay = overlay;
    fs.SetIsHeal = SetIsHeal;
    fs.ApplyStyle = ApplyStyle;
    fs:Show();
    return fs;
end

--- Current style from the settings.
---@return ABTextStyle
local function CurrentStyle()
    local flags = SpellCalc_settings.abFontFlags or "OUTLINE";
    if flags == "NONE" then flags = "" end
    return {
        font = LSM:Fetch("font", SpellCalc_settings.abFont),
        size = SpellCalc_settings.abSize or 12,
        flags = flags,
        shadow = SpellCalc_settings.abShadow == true,
        anchor = SpellCalc_settings.abAnchor or "BOTTOM",
        x = SpellCalc_settings.abOffsetX or 0,
        y = SpellCalc_settings.abOffsetY or 3,
    };
end

------------------------------------------------------------------------
-- Buttons Setup
------------------------------------------------------------------------

--- Add strings to stock action buttons.
local function CreateStockButtonFS()
    for i = 1, 12 do
        buttonFontStrings[i] = CreateActionButtonFS(_G["ActionButton"..i]);
        buttonFontStrings[i+24] = CreateActionButtonFS(_G["MultiBarRightButton"..i]);
        buttonFontStrings[i+36] = CreateActionButtonFS(_G["MultiBarLeftButton"..i]);
        buttonFontStrings[i+48] = CreateActionButtonFS(_G["MultiBarBottomRightButton"..i]);
        buttonFontStrings[i+60] = CreateActionButtonFS(_G["MultiBarBottomLeftButton"..i]);
        -- Action bars 6-8 (action pages 13-15)
        for bar, offset in pairs({ MultiBar5Button = 144, MultiBar6Button = 156, MultiBar7Button = 168 }) do
            if _G[bar..i] then
                buttonFontStrings[i+offset] = CreateActionButtonFS(_G[bar..i]);
            end
        end
    end
end

--- Add strings to Domino buttons.
local function CreateDominosButtonFS()
    local slotId = 0;
    for i = 1, 60 do
        if i <= 12 then
            slotId = i+12;
        else
                slotId = i+60;
        end
        -- TODO: Hook button creation like for BT4? Only relevant when increasing bar size again, not that important.
        if _G["DominosActionButton"..i] then
            buttonFontStrings[slotId] = CreateActionButtonFS(_G["DominosActionButton"..i]);
        end
    end
    CreateStockButtonFS();
end

--- Add strings to ElvUI buttons.
local function CreateElvUIButtonFS()
    for bar = 1, 10 do
        for button = 1, 12 do
            buttonFontStrings[(bar - 1) * 12 + button] = CreateActionButtonFS(_G["ElvUI_Bar"..bar.."Button"..button]);
        end
    end
end

--- Add strings to Bartender4 buttons.
local function CreateBT4ButtonFS()
    -- BT4 doesn't even create disabled bars and buttons, only add created ones now
    for i = 1, 120 do
        if _G["BT4Button"..i] then
            buttonFontStrings[i] = CreateActionButtonFS(_G["BT4Button"..i]);
        end
    end
    -- Try to hook LibActionButton create function to add buttons created later
    if LibStub then
        local LAB10 = LibStub("LibActionButton-1.0");
        if LAB10 then
            hooksecurefunc(LAB10, "CreateButton", function(_, slotId, name)
                if name:find("BT4Button") then
                    _addon.util.PrintDebug("Add bartender4 button " .. name);
                    buttonFontStrings[slotId] = CreateActionButtonFS(_G[name]);
                    buttonFontStrings[slotId]:ApplyStyle(CurrentStyle());
                end
            end);
        end
    end
end

------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------

--- Setup strings for all action buttons.
function _addon:SetupActionButtonText()
    if isSetup then
        return isSetup;
    end

    ---@class ActionButtonText
    local buttonText = {};
    buttonText.detectedBars = "NONE DETECTED";

    --- Clear all buttons.
    buttonText.ClearAll = function()
        for _, v in pairs(buttonFontStrings) do
            v:SetText("");
        end
    end;

    --- Update font, outline, colors and position based on current settings.
    buttonText.UpdateStyle = function()
        colorHarm = SpellCalc_settings.abColorHarm;
        colorHelp = SpellCalc_settings.abColorHelp;
        colorMana = SpellCalc_settings.abColorMana;
        local style = CurrentStyle();
        for _, v in pairs(buttonFontStrings) do
            v:ApplyStyle(style);
        end
    end;

    --- Font string of a slot, if any (for debugging and tests).
    ---@param slot number
    ---@return ABFontString|nil
    buttonText.GetFontString = function(slot)
        return buttonFontStrings[slot];
    end;

    --- Check if text for button slot exists.
    ---@param slot number
    buttonText.HasButtonText = function(slot)
        return buttonFontStrings[slot] ~= nil;
    end

    --- Set button text and color.
    ---@param slot number
    ---@param text string
    ---@param isHeal boolean|nil
    ---@param isMana boolean|nil
    buttonText.SetButtonText = function(slot, text, isHeal, isMana)
        if buttonFontStrings[slot] == nil then
            return;
        end
        buttonFontStrings[slot]:SetText(text);
        buttonFontStrings[slot]:SetIsHeal(isHeal, isMana);
    end

    if _G["DominosActionButton1"] ~= nil then
        buttonText.detectedBars = "DOMINOS";
        CreateDominosButtonFS();
    elseif _G["ElvUI_Bar1Button1"] ~= nil then
        buttonText.detectedBars = "ELVUI";
        CreateElvUIButtonFS();
    elseif _G["BT4Button1"] ~= nil then
        buttonText.detectedBars = "BT4";
        CreateBT4ButtonFS();
    elseif _G["ActionButton1"] ~= nil then
        buttonText.detectedBars = "STOCK";
        CreateStockButtonFS();
    end

    buttonText.UpdateStyle();

    isSetup = buttonText;
    return buttonText;
end