---@class AddonEnv
local _addon = select(2, ...);

do
    -- Blessing of Light Id -> HL, FoL
    local BOL_VALUES = {
        [19977] = { 210, 60 },
        [19978] = { 300, 85 },
        [19979] = { 400, 115 },
        [25890] = { 400, 115 },
    }

    ---@type AuraEffectBase
    local bolEffectHL = {
        type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_SPELLPOWER,
        affectSpell = { 2147483648 }
    };

    ---@type AuraEffectBase
    local bolEffectFoL = {
        type = _addon.CONST.EFFECT_TYPE.SPELLMOD_FLAT_SPELLPOWER,
        affectSpell = { 1073741824 }
    };

    _addon.scripting.RegisterAuraScript("Blessing_of_Light", function(apply, auraId, fromPlayer)
        local name = "Blessing_of_Light_Script_Effect";
        local values = BOL_VALUES[auraId];
        assert(values, "Undefined Blessing of Light spell!");
        if apply then
            _addon:ApplyAuraEffect(name.."HL", bolEffectHL, values[1], auraId, fromPlayer);
            _addon:ApplyAuraEffect(name.."FoL", bolEffectFoL, values[2], auraId, fromPlayer);
        else
            _addon:RemoveAuraEffect(name.."HL", bolEffectHL, values[1], auraId, fromPlayer);
            _addon:RemoveAuraEffect(name.."FoL", bolEffectFoL, values[2], auraId, fromPlayer);
        end
    end);

    for spellId in pairs(BOL_VALUES) do
        _addon.aurasTarget[spellId] = {
            {
                type = _addon.CONST.EFFECT_TYPE.SCRIPT_AURASCRIPT,
                value = 0,
                scriptKey = "Blessing_of_Light"
            }
        }
    end

    -- Offer Blessing of Light (highest rank) as an assumable buff on your heal target.
    table.insert(_addon.assumableTargetAuras, { spellId = 19979, class = "PALADIN", maxStacks = 1 });
end
