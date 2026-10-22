-- GENERATED, DO NOT EDIT DIRECTLY!
-- Forever port: talents keyed by rank-1 spell ID; placeholder data generated from Classic Era tables.

---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "PALADIN" then
    return;
end

---@type TalentDataRawEntry[]
_addon.talentDataRaw = {
    -----------------------------
    -- Holy
    -----------------------------
    { -- Improved Seal of Righteousness
        name = "Improved Seal of Righteousness",
        spellId = 20224,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {1024, 0, 16, 0},
                perPoint = 3,
            },
        }
    },
    { -- Healing Light
        name = "Healing Light",
        spellId = 20237,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {-1073741824, 0, 0, 0},
                perPoint = 4,
            },
        }
    },
    { -- Illumination
        name = "Illumination",
        spellId = 20210,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.ILLUMINATION,
                perPoint = 20,
            },
        }
    },
    -----------------------------
    -- Protection
    -----------------------------
    { -- Precision
        name = "Precision",
        spellId = 20189,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.GLOBAL_FLAT_HIT_CHANCE,
                perPoint = 1,
            },
        }
    },
    { -- One-Handed Weapon Specialization
        name = "One-Handed Weapon Specialization",
        spellId = 20196,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SCHOOLMOD_PCT_DAMAGE,
                affectMask = 1,
                perPoint = 2,
            },
        }
    },
    -----------------------------
    -- Retribution
    -----------------------------
    { -- Improved Retribution Aura
        name = "Improved Retribution Aura",
        spellId = 20091,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {8, 0, 0, 0},
                perPoint = 25,
            },
        }
    },
    { -- Two-Handed Weapon Specialization
        name = "Two-Handed Weapon Specialization",
        spellId = 20111,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SCHOOLMOD_PCT_DAMAGE,
                affectMask = 1,
                perPoint = 2,
            },
        }
    },
}
