# SpellCalc Forever

A World of Warcraft: Forever port of [SpellCalc](https://github.com/coolmodi/SpellCalc) by coolmodi.
It shows calculated numbers for your spells in tooltips and on action bars: damage and healing with your
current spell power, crit and hit chance, average resisted damage, DPS/HPS, damage or healing per mana and
"done until out of mana", taking your talents, buffs, debuffs on the target and equipped items into account.

This is NOT a combat simulation tool. Values are for the current stats and buffs of your character and
target. Not all effects in the game are implemented, numbers won't be correct in all situations.

**Status: pre-release, not yet tested in-game.** The addon API port to the Forever client is done and the
spell, talent, item and aura tables under `data/forever` are generated from the Forever client database
(build 1.60.1.70532, the last beta build before launch; see *Regenerating data*). Warrior, hunter and rogue
are not supported, same as upstream.

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
7. Mana regen from gear: Forever stores mp5 and similar bonuses as item stats instead of equip auras, so
   `system/stats.lua` has to take them from the API (`GetManaRegen`) rather than from `itemEffects.lua`.
8. Talents listed in `generation_report.txt` as "SPELL_AURA_DUMMY spell not handled" (Fire Power, Shadow
   Weaving, Eclipse, Maelstrom Weapon, ...) have no effect in the calculator until someone writes handlers.

## Regenerating data

`tools/spelldata_creator` builds everything under `data/forever` (and the variable sets at the end of
`system/variableScaling.lua`) from wago.tools CSV exports of the Forever client database. It needs Node.js
18 or newer:

```bash
cd tools/spelldata_creator
npm install
npm run update-tables-forever   # downloads the tables of the newest wago.tools "wowf" build into data/forever/dbc
npm start                       # writes data/forever/* and data/forever/generation_report.txt
```

`npm run update-tables-forever -- 1.60.1.70532` pins a build. Every generated file carries the build it was
made from in its first line.

What the generator does differently from upstream, because of the Forever (Mainline-style) database:

- **Spell values** come from `SpellEffect.EffectBasePointsF` and `Variance` (low = base·(1−v/2),
  high = base·(1+v/2)) instead of base points + die sides.
- **Class spell lists** are no longer hand-maintained: a class gets every learnable spell of its skill lines
  (`SkillLineAbility`, acquire method 3 = unobtainable Season of Discovery runes excluded), plus the spells of
  its talent tree, plus the few extras in `data/forever/class_spells/<class>.json`. Hundreds of skill line
  entries point at spells Forever removed (old ranks, Fire Nova Totem, racial priest spells); they are skipped.
- **Talents** come from the trait tables. Each talent is one spell (`TraitDefinition.SpellID`) whose effects hold
  the max-rank values; `TraitDefinitionEffectPoints` → `Curve` → `CurvePoint` give the value per rank. The
  generator runs the aura handlers once per rank and emits `perPoint` when the values are linear, otherwise a
  `values` list. All talents of a tree are processed; the handful that need hand-written definitions
  (Ignite, Illumination, Master of Elements, Arcane Concentration, Elemental Focus) live in
  `modules/talentDummies.ts` and now take their numbers from the client data.
- **Item effects** are linked through `ItemXItemEffect`. Forever turned most "Equip: +X" spell bonuses into
  plain item stats (which the addon reads from the API), so `itemEffects.lua` only lists the remaining spell
  modifiers and procs.
- **Level scaling variables** (`$<power>` style formulas) are only attached to a spell whose description
  really references them. No learnable Forever spell does; the sets still get emitted for completeness.
- Nothing aborts the run any more: everything the generator cannot interpret (dummy auras of new talents and
  set bonuses, removed spells, unhandled spell modifier types) is listed in
  `tools/spelldata_creator/data/forever/generation_report.txt` for review.

## Debug commands

- `/sc debug` toggles debug output.
- `/sc resync` re-reads stats, auras and talents.
- `/sc debugtalents` prints the tracked talents and their current ranks.
- `/sc info` toggles the stat overview window.
- `/sc cs <spellId>` prints the calculated data for a spell.

## Credits

SpellCalc was written by coolmodi. Feasibility notes for this port are in `FOREVER_FEASIBILITY.md`.
