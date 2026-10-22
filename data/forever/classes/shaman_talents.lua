-- GENERATED, DO NOT EDIT DIRECTLY!
-- Forever port: talents keyed by rank-1 spell ID; placeholder data generated from Classic Era tables.

---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "SHAMAN" then
    return;
end

---@type TalentDataRawEntry[]
_addon.talentDataRaw = {
    -----------------------------
    -- Elemental
    -----------------------------
    { -- Concussion
        name = "Concussion",
        spellId = 16035,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {-1877999613, 0, 0, 0},
                perPoint = 1,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {268435456, 0, 0, 0},
                perPoint = 1,
            },
        }
    },
    { -- Call of Flame
        name = "Call of Flame",
        spellId = 16038,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {1073741824, 0, 0, 0},
                perPoint = 5,
            },
        }
    },
    { -- Elemental Focus
        name = "Elemental Focus",
        spellId = 16164,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.CLEARCAST_CHANCE_DMG,
                perPoint = 10,
            },
        }
    },
    { -- Call of Thunder
        name = "Call of Thunder",
        spellId = 16041,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {3, 0, 0, 0},
                values = {2, 3, 4, 6},
            },
        }
    },
    { -- Elemental Fury
        name = "Elemental Fury",
        spellId = 16089,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_CRIT_MULT,
                affectSpell = {-785383421, 4096, 0, 1073741824},
                values = {},
            },
        }
    },
    -----------------------------
    -- Enhancement
    -----------------------------
    { -- Improved Lightning Shield
        name = "Improved Lightning Shield",
        spellId = 16261,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {1024, 0, 0, 0},
                perPoint = 5,
            },
        }
    },
    { -- Weapon Mastery
        name = "Weapon Mastery",
        spellId = 29082,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SCHOOLMOD_PCT_DAMAGE,
                affectMask = 1,
                perPoint = 2,
            },
        }
    },
    -----------------------------
    -- Restoration
    -----------------------------
    { -- Nature's Guidance
        name = "Nature's Guidance",
        spellId = 16180,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.GLOBAL_FLAT_HIT_CHANCE,
                perPoint = 1,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.GLOBAL_FLAT_HIT_CHANCE_SPELL,
                perPoint = 1,
            },
        }
    },
    { -- Tidal Mastery
        name = "Tidal Mastery",
        spellId = 16194,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {1475, 0, 8388688, 0},
                perPoint = 1,
            },
        }
    },
    { -- Purification
        name = "Purification",
        spellId = 16178,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {448, 0, 8388688, 0},
                perPoint = 2,
            },
        }
    },
}
