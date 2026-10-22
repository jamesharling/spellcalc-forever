-- GENERATED, DO NOT EDIT DIRECTLY!
-- Forever port: talents keyed by rank-1 spell ID; placeholder data generated from Classic Era tables.

---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "WARLOCK" then
    return;
end

---@type TalentDataRawEntry[]
_addon.talentDataRaw = {
    -----------------------------
    -- Affliction
    -----------------------------
    { -- Suppression
        name = "Suppression",
        spellId = 18174,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_HIT_CHANCE,
                affectSpell = {-2142714854, 264449, 0, 0},
                perPoint = 2,
            },
        }
    },
    { -- Improved Drain Life
        name = "Improved Drain Life",
        spellId = 17804,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {8, 0, 0, 0},
                perPoint = 2,
            },
        }
    },
    { -- Improved Curse of Agony
        name = "Improved Curse of Agony",
        spellId = 18827,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {1024, 0, 0, 0},
                perPoint = 2,
            },
        }
    },
    { -- Shadow Mastery
        name = "Shadow Mastery",
        spellId = 18271,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {147, 329728, 131072, 0},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {2, 256, 0, 0},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {541704, 1, 0, 0},
                perPoint = 2,
            },
        }
    },
    -----------------------------
    -- 
    -----------------------------
    -----------------------------
    -- Destruction
    -----------------------------
    { -- Devastation
        name = "Devastation",
        spellId = 18130,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {997, 196672, 131072, 0},
                perPoint = 1,
            },
        }
    },
    { -- Improved Searing Pain
        name = "Improved Searing Pain",
        spellId = 17927,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {256, 0, 0, 0},
                perPoint = 2,
            },
        }
    },
    { -- Improved Immolate
        name = "Improved Immolate",
        spellId = 17815,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {4, 0, 0, 0},
                perPoint = 5,
            },
        }
    },
    { -- Ruin
        name = "Ruin",
        spellId = 17959,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_CRIT_MULT,
                affectSpell = {997, 196672, 131072, 0},
                values = {},
            },
        }
    },
    { -- Emberstorm
        name = "Emberstorm",
        spellId = 17954,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {868, 131136, 2, 0},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {100, 0, 2, 0},
                perPoint = 2,
            },
        }
    },
}
