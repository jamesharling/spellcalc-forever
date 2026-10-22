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
(the folder name must match `SpellCalc_Forever.toc`), for example
`World of Warcraft\_forever_\Interface\AddOns\SpellCalc_Forever`. For development, a directory junction
from that path to your clone works too. `/sc` or `/spellcalc` opens the options.

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
- **Player buffs** are scanned with `C_UnitAuras.GetAuraDataByIndex` instead of `UnitAura`, out of combat only.
- **Target auras are assumed, not scanned.** Aura data is secret in combat, and debuffs on a target almost
  only exist in combat, so the addon doesn't read the target's auras. Settings > Target Auras lists the
  class debuffs and heal-target buffs the calculator models (Curse of the Elements, Sunder Armor, Faerie
  Fire, Judgement of the Crusader, Mortal Strike, Amplify Magic, Blessing of Light, ...). The ones you pick
  apply to every target. Debuffs that only boost their caster's own damage (Shadow Weaving, Improved Scorch,
  Stormstrike, Winter's Chill, Improved Shadow Bolt) are only offered to that class.
- **Fixed assumptions instead of live state** where the live value is only readable when it doesn't matter:
  the mana pool always starts full (current mana is secret in combat), finishing moves use an assumed
  combo point count (Settings > Target), and the table of raid boss resistances by NPC ID is gone (unit
  identity is secret inside instances, where those bosses are). Target level and creature type are still read
  when available, and the default level difference applies otherwise.
- **Weapon damage and speed** come from `C_TooltipInfo.GetItemByID` instead of scanning a hidden tooltip.
- **Talents** are read from the trait system (`C_SpecializationInfo` / `C_ClassTalents` + `C_Traits`), which is how
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
2. Talent reading: tree IDs and ranks from `C_Traits` (`/sc debugtalents` also prints which API returned the
   config ID). The config comes from `C_SpecializationInfo.GetCombatConfigIDForSpecGroup`, as in StatLogic and
   RatingBuster on Forever, with `C_ClassTalents.GetActiveConfigID` as a fallback.
3. Weapon skill values from `C_SkillInfo` (`/sc info` shows attack values).
4. Downranking: compare low-rank tooltips with the addon's numbers.
5. Events: unknown events are skipped with a warning in chat; check for warnings after login.
6. Action bar support: stock bars use `MainActionBar` paging; Bartender4, Dominos and ElvUI need their Forever builds.
7. Mana regen: Forever stores mp5 as an item stat, so mp5 has to show up in `GetManaRegen`. The addon treats
   whatever `GetManaRegen` reports above its spirit formula as mp5 and uses the larger of that and the mp5 it
   knows from aura data, so mp5 is not counted twice. Spirit regen uses 0.125 mana per spirit per second for
   every caster, as StatLogic's Forever tables do. Compare `/sc info` ("Spirit/Int base regen", "Mp5 from API")
   with the character sheet.
8. Conditional talents (Fire Power per Fire effect on the target, Shadow Weaving, Eclipse, Maelstrom Weapon,
   procs and target-state bonuses) are listed in `generation_report.txt` and have no effect in the calculator,
   same as upstream. Active talents (Arcane Power, Inner Focus, ...) only count while their buff is up.
9. Target auras: if aura data on the target turns out to be readable in combat (in the open world, say), the
   removed target scan is in the git history (`system/unitAuras.lua` before the assumed target auras).
   Also check the "from caster" debuffs (aura types 270 and 271) really only boost their caster's damage.

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
  `values` list. All passive talents of a tree are processed; active ones (Arcane Power, Combustion, ...) are
  skipped because their buffs are handled as auras. Weapon specializations get a weapon requirement
  (`neededWeaponMask`); weapon-restricted bonuses to magic schools (Wand Specialization) are dropped because
  they only apply to the weapon's own damage. The handful that need hand-written definitions (Ignite,
  Illumination, Master of Elements, Arcane Concentration, Elemental Focus) live in `modules/talentDummies.ts`
  and take their numbers from the client data.
- Effects the addon can only calculate through per-spell handlers (mana gain auras and energize effects:
  Forever's Blessing of Wisdom, Dark Sacrifice, Water Shield) are left out unless such a handler exists,
  currently only for Innervate.
- **Item effects** are linked through `ItemXItemEffect`. Forever turned most "Equip: +X" spell bonuses into
  plain item stats (which the addon reads from the API), so `itemEffects.lua` only lists the remaining spell
  modifiers and procs.
- **Target auras** come from the curated list in `data/forever/targetAuras.json`: the generator picks the
  highest rank of each entry and converts its effects, including Forever's "damage taken from caster" (270,
  271) and armor reduction (674) aura types. The bleed mechanic list and the full target aura dump are gone.
- **Level scaling variables** (`$<power>` style formulas) are only attached to a spell whose description
  really references them. No learnable Forever spell does; the sets still get emitted for completeness.
- Nothing aborts the run any more: everything the generator cannot interpret (dummy auras of new talents and
  set bonuses, removed spells, unhandled spell modifier types) is listed in
  `tools/spelldata_creator/data/forever/generation_report.txt` for review.

## Testing without the game

`tools/loadtest` checks the addon without a WoW client (Node.js 18 or newer):

```bash
cd tools/loadtest
npm install
npm test
```

- `syntax.js` parses every Lua file of the addon and its libraries as Lua 5.1 (no `goto`).
- `run.js` loads the addon in TOC order, libraries included, into a Lua VM ([fengari](https://github.com/fengari-lua/fengari))
  on a stubbed WoW API (`wow_env.lua`), once per supported class. `driver.lua` then fires the login events and
  calculates every spell in the generated data, with no talents, with every talent at max rank (through a
  simulated trait API), and with a sample of buffs from `auras.lua`. It runs the spell tooltip hook for each
  spell too. It then enables every target aura offered in the settings through the real settings options,
  checks they change the numbers, and checks that clearing them restores the previous numbers. Warrior,
  hunter and rogue are loaded too, to check the tooltip hook copes with a class that has no data. Lua errors,
  `NaN` or infinite results, min above max, and talents not read back fail the run.

It catches load errors, broken data references and crashes in the calculation and tooltip code. The stub
returns made-up stats, so it cannot tell whether numbers match the game. It also lists the globals the addon
reads that the stubs don't define; most exist in the real client.

## Debug commands

- `/sc debug` toggles debug output.
- `/sc resync` re-reads stats, auras and talents.
- `/sc debugtalents` prints the tracked talents and their current ranks.
- `/sc info` toggles the stat overview window.
- `/sc cs <spellId>` prints the calculated data for a spell.

## Credits

SpellCalc was written by coolmodi. Feasibility notes for this port are in `FOREVER_FEASIBILITY.md`.
