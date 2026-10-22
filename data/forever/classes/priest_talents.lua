-- GENERATED, DO NOT EDIT DIRECTLY!
-- Forever port: talents keyed by rank-1 spell ID; placeholder data generated from Classic Era tables.

---@class AddonEnv
local _addon = select(2, ...);
local _, playerClass = UnitClass("player");
if playerClass ~= "PRIEST" then
    return;
end

---@type TalentDataRawEntry[]
_addon.talentDataRaw = {
    -----------------------------
    -- Discipline
    -----------------------------
    { -- Improved Power Word: Shield
        name = "Improved Power Word: Shield",
        spellId = 14748,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {1, 0, 0, 0},
                perPoint = 5,
            },
        }
    },
    { -- Meditation
        name = "Meditation",
        spellId = 14521,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.FSR_SPIRIT_REGEN,
                perPoint = 5,
            },
        }
    },
    { -- Force of Will
        name = "Force of Will",
        spellId = 18544,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {139993232, 557058, 65536, 1024},
                perPoint = 1,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {5775504, 565250, 65536, 1024},
                perPoint = 1,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {10518528, 8192, 0, 268435456},
                perPoint = 1,
            },
        }
    },
    -----------------------------
    -- Holy
    -----------------------------
    { -- Improved Renew
        name = "Improved Renew",
        spellId = 14908,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {64, 0, 0, 0},
                perPoint = 5,
            },
        }
    },
    { -- Holy Specialization
        name = "Holy Specialization",
        spellId = 14889,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_CRIT_CHANCE,
                affectSpell = {424943232, 98336, 0, 0},
                perPoint = 1,
            },
        }
    },
    { -- Searing Light
        name = "Searing Light",
        spellId = 14909,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {1048704, 0, 0, 0},
                perPoint = 5,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {1048576, 0, 0, 0},
                perPoint = 5,
            },
        }
    },
    { -- Spiritual Healing
        name = "Spiritual Healing",
        spellId = 14898,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {419700288, 65568, 0, 0},
                perPoint = 2,
            },
        }
    },
    -----------------------------
    -- Shadow
    -----------------------------
    { -- Improved Shadow Word: Pain
        name = "Improved Shadow Word: Pain",
        spellId = 15275,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_DURATION,
                affectSpell = {32768, 0, 0, 0},
                perPoint = 3000,
            },
        }
    },
    { -- Shadow Focus
        name = "Shadow Focus",
        spellId = 15260,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_HIT_CHANCE,
                affectSpell = {109813760, 1572866, 65536, 268436480},
                perPoint = 2,
            },
        }
    },
    { -- Darkness
        name = "Darkness",
        spellId = 15259,
        effects = {
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {33562624, 524288, 0, 0},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_OVER_TIME,
                affectSpell = {8421376, 0, 0, 268435456},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_DAMAGE_HEALING,
                affectSpell = {524288, 0, 65536, 1024},
                perPoint = 2,
            },
            {
                type = _addon.CONST.EFFECT_TYPE.SPELLMOD_PCT_EFFECT,
                affectSpell = {0, 2, 0, 0},
                perPoint = 2,
            },
        }
    },
}
