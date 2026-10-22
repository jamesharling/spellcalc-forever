# SpellCalc Forever

A World of Warcraft: Forever port of [SpellCalc](https://github.com/coolmodi/SpellCalc) by coolmodi.
It shows calculated numbers for your spells in tooltips and on action bars: damage and healing with your
current spell power, crit and hit chance, average resisted damage, DPS/HPS, damage or healing per mana and
"done until out of mana", taking your talents, buffs, debuffs on the target and equipped items into account.

This is NOT a combat simulation tool. Values are for the current stats and buffs of your character and
target. Not all effects in the game are implemented, numbers won't be correct in all situations.

**Status: pre-release, not yet tested in-game.** The addon API port to the Forever client is done, but the
spell, talent, item and aura tables under `data/forever` are still the Classic Era data the original addon
shipped with. Forever retuned most spells and reworked talents, so numbers will be off until the data is
regenerated from the Forever client (see *Regenerating data*). Warrior, hunter and rogue are not supported,
same as upstream.

## Installing

Copy or clone this repository into the Forever client's `Interface\AddOns` folder as `SpellCalc_Forever`
(the folder name must match `SpellCalc_Forever.toc`). `/sc` or `/spellcalc` opens the options.

## What the Forever port changed

Forever runs on the Mainline (retail-style) client with Midnight's combat restrictions, so this fork differs
from upstream SpellCalc in more than the TOC:

- **Forever only.** The Wrath and Season of Discovery code paths, data sets and rune handling were removed.
  Classic-era combat rules are assumed everywhere (flat hit percentages, spirit-only mana regen, no haste on
  the GCD, classic glancing/armor formulas).
- **Removed APIs.** `GetSpellInfo`, `GetSpellPowerCost`, `GetSpellSubtext`, `GetItemInfo` and the spellbook
  lookups go through thin wrappers in `compat.lua` (`_addon.api.*`) over `C_Spell`, `C_Item` and `C_SpellBook`.
- **Tooltips** hook `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, ...)` instead of
  the removed `OnTooltipSetSpell` script.
- **Auras** are scanned with `C_UnitAuras.GetAuraDataByIndex` instead of `UnitAura`.
- **Talents** are read from the trait system (`C_ClassTalents.GetActiveConfigID` + `C_Traits`), which is how
  Forever stores its classic-style trees. Talent data is keyed by the rank-1 spell ID of each talent
  (`spellId` in `data/forever/classes/*_talents.lua`) instead of tree/tier/column.
- **Weapon skill** is resolved from the equipped weapon's skill line via `C_SkillInfo.GetSkillLineInfoByID`,
  mirroring Forever's own character sheet, because `UnitAttackBothHands` no longer exists.
- **Combat restrictions.** Aura data and player stats become secret values in combat. `system/combat.lua`
  makes every read skip while in combat, keeps the last snapshot, and re-reads everything on
  `PLAYER_REGEN_ENABLED`. Tooltips and action-bar numbers in combat show the last out-of-combat state.
  Target identity that comes back secret (inside instances) is treated as unknown.
- **No downranking penalty** on coefficients: Forever's spell data carries the full coefficient on every rank.
- Settings open through the Settings API (`Settings.OpenToCategory`); Ace3 updated to r1386.

## Needs verification at launch

Nothing here has run on a live Forever client (the beta closed before this port was written). Check first:

1. Secret values: which stat and aura APIs are secret, and only in combat or also elsewhere.
2. Talent reading: tree IDs and ranks from `C_Traits` (`/sc debugtalents`).
3. Weapon skill values from `C_SkillInfo` (`/sc info` shows attack values).
4. Downranking: compare low-rank tooltips with the addon's numbers.
5. Events: unknown events are skipped with a warning in chat; check for warnings after login.
6. Action bar support: stock bars use `MainActionBar` paging; Bartender4, Dominos and ElvUI need their Forever builds.

## Regenerating data

`tools/spelldata_creator` builds everything under `data/forever` from wago.tools CSV exports of the client
database. `npm run update-tables-forever` downloads the tables for the Forever client (wago.tools product
`wowf`). Before `npm start` works against Forever data the generator still needs porting:

- `SpellEffect` on Forever has `EffectBasePointsF` + `Variance` instead of `EffectBasePoints` + `EffectDieSides`
  (low = base·(1−v/2), high = base·(1+v/2)); `SpellDuration` renamed `DurationPerLevel`.
- Talents must come from the trait tables (`TraitTree`, `TraitNode`, `TraitNodeXTraitNodeEntry`,
  `TraitNodeEntry`, `TraitDefinition`); the legacy `Talent`/`TalentTab` tables in the Forever client are a
  stale Classic Era copy without Forever's new talents.
- The per-class spell and talent name lists under `tools/spelldata_creator/data/forever` still contain Season of
  Discovery entries and lack Forever's new abilities; `spellDataFixes.ts`, `ItemAuraHandlers.ts`,
  `talentDummies.ts` and `missingCoef.json` need a review against Forever.

## Debug commands

- `/sc debug` toggles debug output.
- `/sc resync` re-reads stats, auras and talents.
- `/sc debugtalents` prints the tracked talents and their current ranks.
- `/sc info` toggles the stat overview window.
- `/sc cs <spellId>` prints the calculated data for a spell.

## Credits

SpellCalc was written by coolmodi. Feasibility notes for this port are in `FOREVER_FEASIBILITY.md`.
