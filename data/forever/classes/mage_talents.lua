-- GENERATED, DO NOT EDIT DIRECTLY!
-- Forever port: talents keyed by rank-1 spell ID; placeholder data generated from Classic Era tables.

---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "MAGE" then
    return;
end

---@type TalentDataRawEntry[]
_addon.talentDataRaw = {
    -----------------------------
    -- Arcane
    -----------------------------
    { -- Arcane Subtlety
        name = "Arcane Subtlety",
        spellId = 11210,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SCHOOLMOD_RESISTANCE_PENETRATION,
                affectMask = 126,
                perPoint = 5,
            },
        }
    },
    { -- Arcane Focus
        name = "Arcane Focus",
        spellId = 11222,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_HIT_CHANCE,
                affectSpell = {539230208, 0, 268697664, 16384},
                perPoint = 2,
            },
        }
    },
    { -- Arcane Concentration
        name = "Arcane Concentration",
        spellId = 11213,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.CLEARCAST_CHANCE_DMG,
                perPoint = 2,
            },
        }
    },
    { -- Improved Arcane Explosion
        name = "Improved Arcane Explosion",
        spellId = 11242,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {4096, 0, 0, 0},
                perPoint = 2,
            },
        }
    },
    { -- Arcane Meditation
        name = "Arcane Meditation",
        spellId = 18462,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.FSR_SPIRIT_REGEN,
                perPoint = 5,
            },
        }
    },
    { -- Arcane Instability
        name = "Arcane Instability",
        spellId = 15058,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {551686903, 69632, 268697696, 540672},
                perPoint = 1,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {4194437, 131072, 262144, 0},
                perPoint = 1,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {551688951, 69632, 268701792, 540674},
                perPoint = 1,
            },
        }
    },
    -----------------------------
    -- Fire
    -----------------------------
    { -- Ignite
        name = "Ignite",
        spellId = 11119,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_EXTRA_ON_CRIT,
                affectSpell = {43451023732, 200704, 525064, 536887296},
                perPoint = 8,
            },
        }
    },
    { -- Incinerate
        name = "Incinerate",
        spellId = 18459,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {18, 0, 0, 0},
                perPoint = 2,
            },
        }
    },
    { -- Improved Flamestrike
        name = "Improved Flamestrike",
        spellId = 11108,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {4, 0, 0, 0},
                perPoint = 5,
            },
        }
    },
    { -- Master of Elements
        name = "Master of Elements",
        spellId = 29074,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.ILLUMINATION,
                perPoint = 10,
            },
        }
    },
    { -- Critical Mass
        name = "Critical Mass",
        spellId = 11115,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {12582935, 69632, 262400, 16384},
                perPoint = 2,
            },
        }
    },
    { -- Fire Power
        name = "Fire Power",
        spellId = 11124,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {12582935, 69632, 262144, 16384},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {4194309, 131072, 262144, 0},
                perPoint = 2,
            },
        }
    },
    -----------------------------
    -- Frost
    -----------------------------
    { -- Elemental Precision
        name = "Elemental Precision",
        spellId = 29438,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_HIT_CHANCE,
                affectSpell = {12714743, 1249280, 262240, 540672},
                perPoint = 2,
            },
        }
    },
    { -- Ice Shards
        name = "Ice Shards",
        spellId = 11207,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_CRIT_MULT,
                affectSpell = {131808, 4096, 96, 524288},
                perPoint = 20,
            },
        }
    },
    { -- Piercing Ice
        name = "Piercing Ice",
        spellId = 11151,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {131808, 4096, 96, 524288},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {128, 0, 0, 0},
                perPoint = 2,
            },
        }
    },
    { -- Improved Cone of Cold
        name = "Improved Cone of Cold",
        spellId = 11190,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {512, 0, 0, 0},
                values = {25, 35},
            },
        }
    },
}
