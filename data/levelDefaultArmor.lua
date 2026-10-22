---@class AddonEnv
local _addon = select(2, ...);

-- Base armor of NPCs by level, used when no custom armor value is set (Settings > Target).
_addon.levelDefaultArmor = {
    20,
    21,
    46,
    82,
    126,
    180,
    245,
    322,
    412,
    518,
    545,
    580,
    615,
    650,
    685,
    721,
    756,
    791,
    826,
    861,
    897,
    932,
    967,
    1002,
    1037,
    1072,
    1108,
    1142,
    1177,
    1212,
    1247,
    1283,
    1317,
    1353,
    1387,
    1494,
    1607,
    1724,
    1845,
    1980,
    2117,
    2262,
    2414,
    2574,
    2742,
    2798,
    2852, -- interpolated
    2907,
    2962, -- interpolated
    3018,
    3072,
    3127, -- interpolated
    3182, -- interpolated
    3237, -- interpolated
    3292, -- interpolated
    3348,
    3401, -- interpolated
    3456, -- interpolated
    3489,
    3791,
    4091,
    4391,
    4691,
    4991,
    5291,
    5591,
    5892,
    6192,
    6492,
    6792, -- 70
    7092,
    7392,
    7692, -- 73
    7918,
    8219, -- 75
    8520,
    8822,
    9124,
    9426,
    9729, -- 80
    10033,
    10356,
    10643, -- 83
}