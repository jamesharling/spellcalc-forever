# SpellCalc → World of Warcraft: Forever — feasibility analysis

> Status update (2026-10-22, later the same day): the fork decision was taken (`SpellCalc_Forever`, repo
> `spellcalc-forever`, Forever only), phase 0 plus the talent rewrite from §8 are implemented in this tree,
> and phase 1 (§6, generator port and data regeneration from build 1.60.1.70532) is done as well. See
> `README.md` for what changed, how to regenerate, and what still needs verification in-game.

Date: 2026-10-22. Based on SpellCalc `master` (last commit c6b53a7, 2024-03-17), the Forever beta client 1.60.1.70532 data on wago.tools, Blizzard's Forever UI source (`forever` branch of wow-ui-source, build 70450), and community beta probes. Forever launches 2026-11-04; the beta closed 2026-10-21, so nothing below has been run in-game.

## Verdict

**Feasible, but it is a port to the retail-style (Mainline) addon API plus a full data regeneration, not a TOC bump.** Roughly:

| Area | Severity | Why |
|---|---|---|
| Addon API | Medium | Forever uses the Mainline 12.x API. Every `GetSpellInfo`, `UnitAura`, `GetTalentInfo`, `GetItemInfo` and the tooltip hook the addon uses is gone. All replacements exist and are documented in Blizzard's Forever client. Mechanical work. |
| Talents | High | Forever's "classic" trees are stored and exposed through the modern Trait system (`C_Traits`). The talent reader and the talent part of the data generator must be rewritten, not patched. |
| Combat restrictions | Medium | Midnight's secret values are active on Forever. Auras and player stats become unreadable in combat. SpellCalc must freeze its model in combat and only update out of combat. |
| Game data | High (ongoing) | Blizzard retuned base damage and coefficients on every rank, added abilities, talents, a talent tier, a race and new racials. The generator's DB2 schema changed (`EffectBasePointsF`/`Variance`). All hand-curated fix lists need review. This is the dominant cost and will keep moving as Blizzard tunes. |
| Project state | Low–Medium | Upstream is dormant since March 2024 with open "doesn't load" issues; no fork has Forever work. Expect to maintain a fork. |

Order-of-magnitude effort for one experienced addon developer, casters and healers only (the classes SpellCalc supports today): about 1 week for the API port and talent rewrite, then 2–4 weeks for data regeneration, fixes and validation after launch, then ongoing tuning. The architecture (generated data tables + calculation engine + tooltip/action-bar UI) is sound and worth keeping.

## 1. What Forever is, technically

- Blizzard's standalone "Classic+" branch, level cap 60, launch 2026-11-04. Announced 2026-09-12.
- Client build line `1.60.1.x`. Interface number **16001** (`select(4, GetBuildInfo())` on beta). `WOW_PROJECT_ID == 18` (`WOW_PROJECT_CAMELOT`); `C_AddOns.GetAddOnMetadata(name, "X-Game")` returns `"Camelot"`. Earlier beta builds reported 1 (Mainline), so detect by named constant, not by a Classic check.
- TOC handling: the client loads `AddOn_Forever.toc` (or `_Camelot`) first, then the family file `AddOn_Mainline.toc`, then `AddOn.toc`. Comma-delimited `## Interface: 16001, 120105` also works. Addon folder on beta was `_classic_beta_\Interface\AddOns`.
- UI/API: Blizzard's UI team stated Forever shares the Mainline UI architecture and the vast majority of the 12.1.5 API, and carries Midnight's in-combat addon restrictions. The UI source confirms it: Forever-specific code lives in `Camelot/` subfolders of the Mainline addons (`Blizzard_PlayerSpells/Camelot`, `Blizzard_UIPanels_Game/Camelot`, `Blizzard_SharedTalentUI/Camelot`).
- `C_Secrets.HasSecretRestrictions()` returned `true` on beta. Combat log events are unavailable to addons (SpellCalc never used them, so no loss).
- wago.tools serves the Forever client data under product **`wowf`** (latest 1.60.1.70532, 2026-10-21; `wow_cn_beta` mirrors it). The existing `DataUpdater.ts` `?branch=` parameter works with `wowf` (verified by fetching `TalentTab`).

## 2. Where SpellCalc stands

- Two flavors: `SpellCalc_Vanilla.toc` (Interface 11500, Classic Era / Season of Discovery) and `SpellCalc_Wrath.toc` (30403). Data generated per flavor into `data/classic` and `data/wrath` (1.9 MB of generated Lua).
- Engine: `core/` (116 KB: `core.lua`, `effectHandlers.lua`, `MagicCalc.lua`, `MeleeCalc.lua`, `CostHandler.lua`), `system/` (96 KB: stats, auras, talents, items, target, SoD runes), `UI/` (85 KB: tooltip, action bar, stat display). Ace3 bundled from February 2024.
- Generator: `tools/spelldata_creator` (TypeScript, ~370 KB). Downloads 22 DB2 tables as CSV from wago.tools, builds spell/talent/aura/item-set tables for six classes (druid, priest, warlock, mage, paladin, shaman). Warrior, hunter, rogue and death knight are unsupported in the addon.
- Hand-maintained inputs the generator relies on: per-class spell name lists (`data/classic/class_spells/*.json`, which also contain SoD rune spells), per-class talent name lists, `spellDataFixes.ts` (22 KB of per-spell corrections), `ItemAuraHandlers.ts` (57 KB), `talentDummies.ts`, `hotFix.ts`, `missingCoef.json`, `sealData.json`, `totemSpells.json`, plus Lua-side `auraScripts.lua` and the 41 KB of effect handlers.
- Upstream: last push 2024-03-17; 14 open issues including "Not loading on TBC Anniversary Realm" (2026-02) and "Wrong values for classic era" (2024-12); one fork (illisw) did a partial Era data refresh in 2025-01. Nobody has touched Forever.
- Local note: `D:\SpellCalc` already contained a `SpellCalc-master` folder (byte-identical to upstream master). The fresh copy of master now sits at the root. Git is not installed on this machine, so the source was fetched as a zip; install Git before forking.

## 3. API compatibility matrix

Counts are from the addon's own files (libraries and DEV stubs excluded). "Forever status" is from Blizzard's Forever API documentation and `Camelot` UI code in the `forever` branch of wow-ui-source, plus beta probes.

| SpellCalc uses | Where | Forever status | Replacement |
|---|---|---|---|
| `GetSpellInfo` | 122 uses in 25 files, including generated `data/*` files | Removed | `C_Spell.GetSpellInfo(id)` returns a table. Add an addon-local shim that returns the old tuple, then fix call sites that only want the name. |
| `GetSpellPowerCost` | `core/core.lua` | Removed | `C_Spell.GetSpellPowerCost` |
| `GetSpellBookItemInfo` | 3 uses | Removed | `C_SpellBook.GetSpellBookItemInfo` |
| `GetItemInfo` | `system/items.lua` | Removed | `C_Item.GetItemInfo` (same multi-return). May return nil until cached; use `C_Item.RequestLoadItemDataByID` + `ITEM_DATA_LOAD_RESULT`. |
| `GetAddOnMetadata` | 1 use | Removed | `C_AddOns.GetAddOnMetadata` |
| `UnitAura(unit, i, filter)` | `system/unitAuras.lua` (player + target scan, name lookups) | Removed from Mainline in 11.0.2 | `C_UnitAuras.GetAuraDataByIndex`, `C_UnitAuras.GetUnitAuras`, `AuraUtil.ForEachAura`. Secret while auras are restricted (see §5). |
| `GameTooltip:HookScript("OnTooltipSetSpell")` + `tooltip:GetSpell()` | `UI/tooltip/SCTooltip.lua` | Removed from Mainline in 10.0.2 | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, fn)` and `TooltipUtil.GetDisplayedSpell(tooltip)`. `TooltipDataHandler.lua` ships in Forever's `Blizzard_SharedXMLGame/Tooltip`. |
| `GetTalentInfo(tab, index)` | `system/talents.lua`, `slashcmd.lua` | Removed | `C_ClassTalents.GetActiveConfigID()` + `C_Traits.GetConfigInfo / GetTreeNodes / GetNodeInfo / GetEntryInfo / GetDefinitionInfo` (§4). |
| `CHARACTER_POINTS_CHANGED`, `ACTIVE_TALENT_GROUP_CHANGED` | `system/talents.lua` | Classic events | `TRAIT_CONFIG_UPDATED`, `ACTIVE_COMBAT_CONFIG_CHANGED`, `PLAYER_TALENT_UPDATE` (verify at launch). |
| `UnitAttackBothHands`, `UnitRangedAttack` | `system/stats.lua` (weapon skill) | Not in Mainline. Forever's own character sheet uses `UnitDefenseSkill` and `C_SkillInfo.GetSkillLineInfoByID` | Read weapon skill through the skill-line API. Only matters for melee calcs (paladin, shaman, druid). |
| `GetGlyphSocketInfo` | `system/glyphs.lua` | Wrath only | Not loaded for Forever. |
| `C_Engraving`, SoD rune code | `helper.lua`, `system/sodrunes.lua` | `C_Engraving` is nil; already guarded | Keep SoD paths off for Forever. |
| `WOW_PROJECT_ID == WOW_PROJECT_CLASSIC / WRATH_CLASSIC` | `helper.lua`, 26 flavor-gated sites in 11 files | Both false on Forever, so code falls into the Wrath branch (e.g. the `sqrt(int)·spirit` mana regen formula, rating-based hit) | Add `IS_FOREVER = WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` and route it through the Classic-mechanics branches, then re-check each of the 26 sites. |
| Stat globals: `GetSpellBonusDamage/Healing`, `GetSpellCritChance`, `GetSpellHitModifier`, `GetHitModifier`, `GetCritChance`, `GetRangedCritChance`, `GetManaRegen`, `GetCombatRatingBonus`, `GetExpertise`, `GetDodgeChance`, `GetSpellPenetration`, `UnitStat`, `UnitAttackPower`, `UnitRangedAttackPower`, `UnitDamage`, `UnitRangedDamage`, `UnitAttackSpeed`, `UnitPowerMax` | `system/stats.lua` | **All present**: Forever's `Camelot/PaperDollFrameStats.lua` calls exactly these | None needed. Values may be secret in combat (§5). |
| `GetShapeshiftForm`, `GetWeaponEnchantInfo`, `GetInventoryItemLink/ID`, `GetActionInfo`, `IsPlayerSpell`, `hooksecurefunc`, `C_Timer` | various | Present | None. |
| Ace3 (Feb 2024), LibSharedMedia | `libs/` | Old | Update to current Ace3 (Midnight-compatible). `AceConfigDialog:AddToBlizOptions` already uses the Settings API. |
| Bartender4 / Dominos / ElvUI button hooks | `UI/actionbar/ActionBarValues.lua` | Those addons ship Mainline builds | Verify their Forever builds keep the same frame names. |

Nothing in SpellCalc touches `COMBAT_LOG_EVENT_UNFILTERED`, `CombatLogGetCurrentEventInfo`, chat, or protected frames, so the Midnight "disarmament" rules do not block its core function.

## 4. Talents: the one structural rewrite

Evidence from the 1.60.1.70532 client data:

- The legacy `Talent` and `TalentTab` tables still ship, with exactly the same 432 rows / 27 tabs as Classic Era 1.15.9. None of Forever's new talents are in them.
- Forever's trees live in the Trait tables. `TraitSystem` 10 (the class talent system) has one tree per class with 50–55 nodes each, laid out on a 7-row grid via `TraitNode.PosX/PosY`:

  | TraitTree | Class (from node spells) | Nodes |
  |---|---|---|
  | 1082 | Shaman (Convection, Concussion, Earth's Grasp…) | 50 |
  | 1089 | Druid (Improved Wrath, Genesis, Ferocity…) | 52 |
  | 1091 | Hunter | 52 |
  | 1100 | Paladin (Divine Strength, Redoubt…) | 50 |
  | 1111 | Rogue | 53 |
  | 1112 | Mage (Arcane Focus, Missile Barrage…) | 55 |
  | 1114 | Priest (Power in Light, Twin Disciplines…) | 53 |
  | 1116 | Warlock (Improved Life Tap, Suppression…) | 52 |
  | 1117 | Warrior | 52 |

  Plus a second druid tree (1083, 36 nodes), two small mage/shaman test trees, and three 9-node trees in system 45 (Master Chef, Bartering, Well Rested… a new non-class perk system). Shaman's tree is flagged system 0, which looks like a data quirk to double-check.
- `TraitNodeEntry.MaxRanks` carries the 1/2/3/5-point ranks; `TraitDefinition.SpellID` is the rank-1 talent spell; `TraitCond`/`TraitNodeGroup` encode the point gates (the 11/16/21/31 tiers); `TraitEdge` encodes prerequisites.
- New Forever talents exist only in `TraitDefinition`: Heating Up (400624), Power in Light (1309969), Lava Burst (408490), Arcane Blast (400574), Ice Lance (1312002), Lightning Overload (408438), Missile Barrage (400588). Of 535 trait definitions, 361 map to spells that also appear in the legacy table; the rest are new.
- Blizzard's Forever UI reads them with `C_Traits` (`Blizzard_TieredEntranceTraits.lua` calls `C_Traits.GetConfigIDByTreeID`, `GetTreeNodes`, `GetNodeInfo`), and the Forever `PlayerSpells` frame reuses the Mainline `ClassTalents` frame (`C_ClassTalents`). `C_SpecializationInfo.GetTalentInfo(query)` with `tier`/`column` also exists in the API list (the Mists-style query); whether it answers for Forever trees is untested.

What this means for SpellCalc:

- `system/talents.lua` (tree/tier/column walking with `GetTalentInfo`) must be rewritten on `C_Traits`. Key the generated talent data by rank-1 spell ID (`TraitDefinition.SpellID`) instead of `tree/tier/column`; that survives Blizzard moving talents around.
- `tools/spelldata_creator/modules/TalentCreator.ts` must read `TraitTree → TraitNode → TraitNodeXTraitNodeEntry → TraitNodeEntry → TraitDefinition` instead of `Talent`/`TalentTab`. The per-rank spell list comes from the definition's spell plus `MaxRanks` (rank spells are chained through `SpellRank_n` today; on the trait side rank N's spell ID must be resolved via the definition or the spell name).
- Dual spec (level 40) means talent config switches; handle `TRAIT_CONFIG_UPDATED`/`ACTIVE_COMBAT_CONFIG_CHANGED`.

## 5. Combat restrictions (secret values)

- Forever runs Midnight's secret-value system. Aura data is secret whenever "auras are restricted": in combat, during an encounter, in Mythic+ or in a PvP match. Single-aura lookups by spell ID or name are not callable while restricted; `GetUnitAuras` returns a non-secret list whose contents may be secret.
- The SpellScale author reports that player stats are hidden in combat on Forever, so `GetSpellBonusDamage` and friends should be assumed secret in combat too. Player `UnitHealth` returned a secret on beta.
- Secrets can be stored and passed to frames but not compared, used in arithmetic, indexed or used as table keys; `issecretvalue(v)` tells you. `pcall` does not help.
- Impact on SpellCalc: every `UNIT_AURA`, stat and talent update handler must bail out while `InCombatLockdown()`/`UnitAffectingCombat("player")` and re-sync on `PLAYER_REGEN_ENABLED`. Tooltips and action-bar values would then show the last out-of-combat snapshot, which is still useful. Target-debuff-aware numbers in combat are lost by design. The forced-restriction CVars (`secretCombatRestrictionsForced` etc.) exist for testing this without fighting.

## 6. Game data and the generator

Schema differences between the Forever client and Classic Era for the tables the generator reads:

| Table | Change | Generator impact |
|---|---|---|
| `SpellEffect` | `EffectBasePoints` and `EffectDieSides` are gone; `EffectBasePointsF` + `Variance` define the range (low = base·(1−v/2), high = base·(1+v/2)); `ScalingClass` added | `getCorectBase` / `fillBaseAndRange` in `app.ts`, the `SpellEffect` interface and anything in `spellDataFixes.ts`/`ItemAuraHandlers.ts` that reads base points must change. `EffectBonusCoefficient` is populated and is the spell-power coefficient (the retail `Coefficient` column is zero everywhere). |
| `SpellDuration` | `DurationPerLevel` → `DurationPerResource` | The "scales with level" guard in `SpellData.ts` must be re-pointed. |
| `SpellMisc`, `SpellPower`, `SpellCategories` | Columns added only | None. |
| `Talent`, `TalentTab` | Unchanged schema, stale content | Replace with Trait tables (§4). |
| `ItemSparse` | 104 vs 142 columns (random suffix, resistances, per-slot damage columns removed) | `ItemEffectsCreator`/`ItemSetCreator` joins need review. `ItemEffect` lost `ParentItemID`. |
| `SpellScaling` | Not present for Forever | Fine; the generator never used it. |

Content changes that invalidate current numbers and hand fixes:

- Every rank of every spell was retuned (community diff of 1.15.9 vs 1.60.1: Fireball max rank 596–760 → 425–541; Lightning Bolt 419–467 → 185–207 with cast time and cost changes; 124 of 392 simulated spells changed coefficient). Some coefficients moved or vanished (Arcane Shot, Serpent Sting, Consecration).
- Low ranks carry the full cast-time coefficient in the data (Fireball rank 1: 0.123 → 0.429). `core/core.lua:767` applies the Classic `(22 + maxLevel − level)/20` downrank penalty on the client side; whether Forever still applies any penalty server-side has to be checked against tooltips at launch. One fan guide claims downranking "costs bonus power and procs"; the DB2 says otherwise.
- New baseline abilities and talents per class (Arcane Blast, Ice Lance, Heating Up, Lava Burst, Lightning Overload, Holy Strike, Seal of Fury, Power in Light, Shadow Word: Death baseline, a 16-point talent tier, druid with 47 of 52 talents new or changed). All six supported classes need their spell lists, talent lists, dummy handlers and tooltip handlers revisited. SoD rune spells in the lists must go.
- New race (Skyborne) and four racials per race, with crit replacing weapon-skill racials (October 15 beta build). `data/classic/racials.lua` and `system/aura.lua` race handling need redoing.
- Reported itemization changes: unified hit (and possibly crit) across spell/melee/ranged, less weapon skill on gear, resistance racials removed. `system/stats.lua` hit handling and the melee hit table in `MeleeCalc.lua` must be re-verified.
- Item sets and item procs: Forever's items differ; `itemSetData` and `itemEffects` must be regenerated and the 57 KB of aura handlers re-run against the new tables.

Validation is the real cost. The existing data has `missingCoef.json` and dozens of spell-specific hacks because DBC data never fully describes what the server does. Forever is a new server ruleset, so expect a similar long tail, and Blizzard is still tuning weekly.

## 7. Prior art on Forever

The niche is already partly served, which both lowers risk (patterns to copy, including which APIs work) and raises the bar:

- SpellPowerCoefficients (CurseForge, data from build 70450): coefficient lines and live bonus per spell, out of combat.
- SpellScale (GitHub, irv-05): learns coefficients empirically from tooltips as stats change; explicitly works around the combat-log ban and in-combat secrets.
- SpellTips (GitHub, blodeAC): datamined `Data.lua` plus live talent reading; shows the math behind tooltip numbers.
- SpellCoda Forever (CurseForge): damage, healing and stat weights; reads talents "through the modern talent API".

SpellCalc's differentiators remain: full buff/debuff/talent/target modelling, crit/hit/resist, DPM/HPM/time-to-OOM, action-bar numbers. None of the above does all of that.

## 8. Work plan and estimate

Phase 0 — load and run on Forever with placeholder data (2–4 days)
1. `SpellCalc_Forever.toc` (`## Interface: 16001`, `## X-Game: Camelot` optional), `data/forever/` directory, `IS_FOREVER` flag, route flavor gates.
2. Addon-local `GetSpellInfo`/`GetItemInfo`/`GetSpellPowerCost`/`GetSpellBookItemInfo` shims over `C_Spell`/`C_Item`/`C_SpellBook`; fix generated files that call `GetSpellInfo` at load time (they run before anything else, so the shim must be defined in a file loaded first).
3. Rewrite tooltip hook on `TooltipDataProcessor`; rewrite aura scan on `C_UnitAuras`; replace weapon-skill reads.
4. Combat freeze + `issecretvalue` guards; update Ace3.

Phase 1 — talents (2–3 days)
5. `talents.lua` on `C_ClassTalents`/`C_Traits`, keyed by rank-1 spell ID.
6. `TalentCreator.ts` on the Trait tables.

Phase 2 — data (2–4 weeks after launch, then ongoing)
7. Port `DataUpdater.ts` to `wowf`, port `SpellData.ts`/`app.ts` to `EffectBasePointsF`/`Variance`, regenerate for the six classes.
8. Rebuild class spell/talent lists, dummy handlers, tooltip handlers, racials, item sets; prune SoD; review `spellDataFixes.ts`, `ItemAuraHandlers.ts`, `missingCoef.json`.
9. Validate against in-game tooltips per class (downranking, hit/crit unification, new abilities), ideally by cross-checking with SpellScale's empirical readings.

Beta is closed and launch is 2026-11-04, so phases 0–1 can be written now against the API docs and the `Camelot` UI source, but nothing can be verified in-game before launch. Budget the first week after launch for breakage.

## 9. Risks and open questions

1. In-combat behaviour: confirm exactly which of the stat/aura APIs return secrets, and when (combat only vs instances). Design for "out of combat only".
2. Downranking: data says no coefficient penalty; verify server behaviour from tooltips.
3. Talent API: confirm `C_Traits` tree IDs per class at runtime (`C_ClassTalents.GetActiveConfigID` → `C_Traits.GetConfigInfo(...).treeIDs`), and whether `C_SpecializationInfo.GetTalentInfo({tier, column})` works as a simpler path.
4. Weapon skill: how to read it (`C_SkillInfo.GetSkillLineInfoByID`?) and whether the melee hit table still depends on it.
5. Trait-table quirks: duplicate druid tree (1083 vs 1089), shaman tree flagged system 0, outlier node coordinates in hunter/priest trees.
6. Third-party action bars: Forever builds of Bartender4/Dominos/ElvUI and their button frame names.
7. Churn: Blizzard retunes between builds; the generator must be cheap to re-run (it is: one command per table set).
8. Upstream: coolmodi/SpellCalc is dormant; plan on a fork and your own CurseForge/Wago listing.

## Sources

- Blizzard: [World of Warcraft: Forever](https://worldofwarcraft.blizzard.com/en-us/forever); [Combat philosophy and addon disarmament in Midnight](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight); [How Midnight's changes impact combat addons](https://news.blizzard.com/en-us/article/24244638/how-midnights-upcoming-game-changes-will-impact-combat-addons); [Forever class deep dives: Priest and Warrior](https://news.blizzard.com/en-us/article/24301514/world-of-warcraft-forever-class-deep-dives-priest-and-warrior)
- Warcraft Wiki: [World of Warcraft: Forever](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever); [TOC format](https://warcraft.wiki.gg/wiki/TOC_format); [Patch 12.0.0 planned API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes); [Secret values](https://warcraft.wiki.gg/wiki/Secret_Values); [API UnitAura](https://warcraft.wiki.gg/wiki/API_UnitAura)
- Blizzard UI source mirror, `forever` branch: [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) (`Blizzard_TieredEntranceTraits`, `Blizzard_PlayerSpells/Camelot`, `Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua`, `Blizzard_APIDocumentationGenerated`)
- Client data: [wago.tools](https://wago.tools) product `wowf` build 1.60.1.70532; [Forever beta spell-data notes (gunba/wow-forever-sim)](https://github.com/gunba/wow-forever-sim/blob/forever/docs/spell-data-2026-09-17.md); [tweaks-forever data refresh](https://github.com/cjber/tweaks-forever/pull/212)
- Beta probes and guides: [nazumods/wow #952](https://github.com/nazumods/wow/issues/952), [#953](https://github.com/nazumods/wow/issues/953), [#955](https://github.com/nazumods/wow/issues/955), [#959](https://github.com/nazumods/wow/issues/959); [Forever addon API cheat sheet](https://wowforeverguides.com/addons/api-cheatsheet); [Forever addon developer guide](https://wowforeverguides.com/addons/developers); [Forever addons overview](https://wowforeverguides.com/addons); [Forever itemization changes](https://wowforeverguides.com/systems/itemization); [GameSpot on racial changes](https://www.gamespot.com/articles/wow-forever-just-changed-the-math-on-what-race-to-play-in-a-big-way/); [Icy Veins beta build news](https://www.icy-veins.com/wow-forever/news/a-new-beta-client-build-arrives-for-wow-forever/)
- Prior art: [SpellPowerCoefficients](https://www.curseforge.com/wow/addons/spc-forever); [SpellScale](https://github.com/irv-05/SpellScale); [SpellTips](https://github.com/blodeAC/spelltips); [SpellCoda Forever](https://www.curseforge.com/wow/addons/spellcodaforever)
- Upstream: [coolmodi/SpellCalc](https://github.com/coolmodi/SpellCalc)
