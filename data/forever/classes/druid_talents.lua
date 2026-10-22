-- GENERATED, DO NOT EDIT DIRECTLY!
-- Forever port: talents keyed by rank-1 spell ID; placeholder data generated from Classic Era tables.

---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "DRUID" then
    return;
end

---@type TalentDataRawEntry[]
_addon.talentDataRaw = {
    -----------------------------
    -- Balance
    -----------------------------
    { -- Improved Moonfire
        name = "Improved Moonfire",
        spellId = 16821,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {2, 0, 0, 64},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {2, 0, 0, 64},
                perPoint = 2,
            },
        }
    },
    { -- Natural Weapons
        name = "Natural Weapons",
        spellId = 16902,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SCHOOLMOD_PCT_DAMAGE,
                affectMask = 1,
                perPoint = 2,
            },
        }
    },
    { -- Improved Thorns
        name = "Improved Thorns",
        spellId = 16836,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {256, 0, 0, 0},
                perPoint = 25,
            },
        }
    },
    { -- Vengeance
        name = "Vengeance",
        spellId = 16909,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_CRIT_MULT,
                affectSpell = {7, 0, 33554432, 64},
                perPoint = 20,
            },
        }
    },
    { -- Moonfury
        name = "Moonfury",
        spellId = 16896,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {7, 0, 0, 64},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {0, 0, 33554432, 0},
                perPoint = 2,
            },
        }
    },
    -----------------------------
    -- Feral Combat
    -----------------------------
    { -- Feral Aggression
        name = "Feral Aggression",
        spellId = 16858,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {8388608, 0, 0, 0},
                perPoint = 3,
            },
        }
    },
    { -- Savage Fury
        name = "Savage Fury",
        spellId = 16998,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {6144, 1088, 0, 0},
                perPoint = 10,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {4096, 0, 0, 0},
                perPoint = 10,
            },
        }
    },
    -----------------------------
    -- Restoration
    -----------------------------
    { -- Reflection
        name = "Reflection",
        spellId = 17106,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.FSR_SPIRIT_REGEN,
                perPoint = 5,
            },
        }
    },
    { -- Improved Rejuvenation
        name = "Improved Rejuvenation",
        spellId = 17111,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {16, 0, 0, 0},
                perPoint = 5,
            },
        }
    },
    { -- Gift of Nature
        name = "Gift of Nature",
        spellId = 17104,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {240, 1174405136, 16777216, 0},
                perPoint = 2,
            },
        }
    },
    { -- Improved Regrowth
        name = "Improved Regrowth",
        spellId = 17074,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {64, 0, 0, 0},
                perPoint = 10,
            },
        }
    },
}
