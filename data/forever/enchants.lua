---@class AddonEnv
local _addon = select(2, ...);
local GetSpellName = _addon.api.GetSpellName;
local MOD_MANA_PER_5 = _addon.CONST.EFFECT_TYPE.MOD_MANA_PER_5;

-- Temporary weapon enchants whose effect the stat API may not report: the mana oils. Their mp5 is not a
-- visible stat on Classic clients, and whether Forever's GetManaRegen includes it is unverified; the cost
-- calculation takes the larger of the API's mp5 and this, so it is never counted twice (core/CostHandler.lua).
-- Wizard oils, sharpening stones and the shaman imbues change stats the API does report (spell power, crit,
-- weapon damage) or are procs, so they are not listed.
--
-- Values from Forever build 1.60.1.70532: SpellItemEnchantment 2624/2625/2629 apply the equip spells
-- 25114/25115/25116 (enchant effect type 3), whose SPELL_AURA_MOD_POWER_REGEN effect is 5/10/15. Their
-- +10/20/30 healing shows up in GetSpellBonusHealing. Upstream's Classic Era values were 4/8/12.
---@type table<integer, EnchantData>
_addon.enchantData = {
    [2624] = { -- Minor Mana Oil
        name = GetSpellName(25118) or "Minor Mana Oil",
        type = MOD_MANA_PER_5,
        value = 5,
    },
    [2625] = { -- Lesser Mana Oil
        name = GetSpellName(25120) or "Lesser Mana Oil",
        type = MOD_MANA_PER_5,
        value = 10,
    },
    [2629] = { -- Brilliant Mana Oil
        name = GetSpellName(25123) or "Brilliant Mana Oil",
        type = MOD_MANA_PER_5,
        value = 15,
    },
};
