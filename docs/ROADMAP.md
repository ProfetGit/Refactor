# Roadmap

Delivery order for Refactor and Gear Refactor. The PRDs say what to build, this file says when.

Last updated: 18 Sep 2026 (M4 started)

## How to use this file

- Exactly one milestone per track is marked **Current**.
- Claude Code works only inside the current milestone. Anything else is raised, not started.
- A milestone is done when every exit criterion is ticked, not when the code "looks finished".
- Dates are targets. Exit criteria are not negotiable.

## Fixed dates

| Date | Event | Source |
|---|---|---|
| 17 Sep 2026 | Beta opens | Blizzard |
| 21 Oct 2026 | Beta ends (reported). No client access after this until launch. | Community |
| 4 Nov 2026 | Launch | Blizzard |
| 9 Dec 2026 | Raids unlock (reported) | Community |

Beta is reported capped at level 30. Anything that needs a live client must be verified before **21 Oct**.

---

## Current milestone

- Refactor track: **M4**, built against **Retail 12.1.0 (69814)**
- M3 closed 18 Sep 2026 with one exit criterion still open: the conflict panel has not
  been seen detecting Leatrix Plus or Questie on a live client. Headless spec only.
- Gear Refactor track: **not started** (starts after Refactor M3)

### Retail-first re-scope (17 Sep 2026)

Blizzard confirmed on stream that WoW Forever uses the Retail API, and there is no beta access
yet. So the addon is built and verified against the installed Retail client first, and Forever
support is added when that client can be probed. Consequences:

- `Data/api-retail.json` replaces `api-classic-era.json` as the interim index. It is generated
  by `Tools/source-index.py` from Blizzard's own interface source at the installed build, so it
  is source evidence, not a runtime Probe. `Data/api-retail-probe.json`, when a Probe dump is
  converted, is checked on top of it.
- M1 keeps only the parts that do not need beta: the index, the atlas choices, and the API
  answers that Retail source settles. The rest of M1 stays open until beta access.
- Every Forever-specific claim in the PRD stays an assumption until the client exists.

---

## Refactor track

### M0. Foundations (16 to 17 Sep)

Everything here is API-agnostic and testable headless. Safe to build before beta answers exist.

| Deliverable | PRD |
|---|---|
| Repo skeleton, TOC, `Core/Namespace.lua` | 10.2 |
| `Core/Registry.lua`: registration, `pcall` error boundaries, states `enabled / disabled / unavailable / failed` | 5.1 |
| `Core/Capabilities.lua`: resolve `requires` against the live `_G` | 5.1 |
| `Core/Broker.lua`: subscribe, unsubscribe, unsubscribe all, throttle | 5.2, 9.4 |
| `Core/Settings.lua`: three-state resolution, named profiles, GUID identity key, import and export | 5.3 |
| `Core/Pools.lua` | 9.3 |
| `Tests/mock` minimal stubs, busted specs for all of the above | 10.5 |
| `Tools/lint.lua` with the project rules, luacheck config | 10.4 |
| `Tools/Probe` dev addon and `Tools/probe-to-json.lua` | 10.8 |
| Run Probe on the current **Classic Era** client, commit `Data/api-classic-era.json` as the interim API index | 10.8 |
| `Tools/api-check.lua` with the scoped symbol check | 10.4 |
| CI workflow: lint, test, api-check | 10.6 |
| `docs/style-reference.jpg` committed | 8.3 |

Exit criteria:

- [x] `make check` passes (locally; CI run still pending, there is no git remote yet)
- [x] Settings resolution spec covers every combination of override, profile, account default, module default
- [x] A test module with a missing `requires` symbol ends in state `unavailable` and names the symbol
- [x] A test module that errors in `OnEnable` ends in `failed` and a second module still enables
- [x] Enable, disable, enable leaves no residue for the test module
- [ ] Probe runs on a client and produces a JSON index (Probe addon written, never run in game)

### M1. Beta day one (17 Sep)

| Deliverable | PRD |
|---|---|
| Install Probe on beta, log in, `/reload`, copy SavedVariables | 10.8 |
| `ExportInterfaceFiles code`, count `Secret` entries | 13 Q2 |
| Answer every question in PRD section 13 and Gear Refactor PRD section 13 that is answerable at level 1 | 13 |
| Generate `Data/api-forever.json`, switch `make api-check` to it | 10.8 |
| Diff `api-forever.json` against `api-classic-era.json`, note surprises | 2.2 |
| Pick Blizzard atlas candidates for the theme pieces | 8.3 |
| Write PRD Draft 2 against answers | 13 |

Exit criteria:

- [x] An API index committed and used by `make api-check` (`api-retail.json`; `api-forever.json` waits for beta)
- [ ] Every section 13 question answered or explicitly marked "needs higher level" (blocked on beta)
- [ ] Draft 2 of both PRDs committed (blocked on beta)
- [x] Any module made impossible by the API is marked unavailable: auto stand, protected on Retail

### M2. First beta build (by 24 Sep)

Goal: a small addon that works, on beta, as early as possible (PRD R4).

| Deliverable | PRD |
|---|---|
| `LibRefactorTheme-1.0` v1: tokens, panel, header banner, tile, row, scrollbar, following the reference style | 8.3 |
| Main window with global search and the three-state toggle | 8.2 |
| Slash commands, Blizzard Settings entry | 8.1 |
| Modules: fast loot, auto stand, DELETE fill, auto sell junk with never-sell list, auto repair (own funds), vendor summary, mail take-all | 7 |
| `/refactor errors` | 7.8 |
| Packaged build published as a GitHub release, install instructions with "Load out of date AddOns" | 10.6 |

Exit criteria:

- [ ] Loads on Retail with zero BugSack errors across a one-hour levelling session
- [ ] Every M2 module verified in-game, results in the PR checklist
      (nameplate quest progress verified and two bugs fixed; the other six modules are
      still unverified in game)
- [ ] Theme side by side with the reference screenshot looks like the same family
      (`docs/style-reference.jpg` is still missing, so there is nothing to compare against)
- [ ] Atlas names in `LibRefactorTheme` confirmed present on the live client; every one that is
      missing falls back to a flat colour today and `Theme.missingAtlases` names it
- [x] `make check` passes
- [x] The whole TOC load sequence, login and window run headless in `Tests/spec/load_spec.lua`

### M3. Profiles, presets, conflicts (by 8 Oct)

| Deliverable | PRD |
|---|---|
| First-run preset picker | 6.1 |
| Minimal, Standard, Full presets from module `tier` | 6.2 |
| Automation category with confirmation dialog and shared kill switch | 6.3, 5.6 |
| Named profiles UI, per-character assignment, import and export UI | 5.3 |
| Neighbour detection and conflict panel | 5.4 |
| Module status panel | 7.8 |
| `LibRefactorPrice-1.0` v1 in-tree, vendor provider only | 5.5 |

Exit criteria:

- [x] A second character on the same account inherits every setting with zero clicks
      (`Tests/spec/presets_spec.lua`, account table reused with a fresh character table)
- [ ] Conflict panel detects Leatrix Plus and Questie in game. Detection is specced headless
      against `C_AddOns.IsAddOnLoaded`; neither addon is installed here to confirm it live.
      Carried into the M4 in-game pass, M3 closed without it on 18 Sep
- [x] Automation modules cannot enable without the dialog (`Tests/spec/m3_spec.lua`)
- [x] `make check` passes

### M4. Remaining cold and visible modules, plus hot modules (by 14 Oct)

Hot modules must be done here, because there is no client after 21 Oct.

| Deliverable | PRD |
|---|---|
| Quest, chat, interface, items modules from the catalogue that survived Draft 2 | 7 |
| Extended vendor UI, bag junk value | 7.3 |
| Tooltip modules as load-on-demand: sell price, rarity border, anchoring | 7.7, 9.5 |
| Loot toasts with `AnimationGroup` | 7.2 |
| Bag quality borders | 7.6 |
| Nameplate quest progress with deference | 9.6 |
| `/refactor bench` harness | 9.2 |
| TSM and Auctionator providers, opt-in | 5.5 |

Native on Retail 12.1, so not built (PRD R2, "deleted rather than kept for feature count"):
bag quality borders (`SetItemButtonQuality` in Blizzard's ItemButtonTemplate), auto track
new quests (`autoQuestWatch` CVar), chat timestamps (`showTimestamps` CVar), sell-all-junk
button (`C_MerchantFrame.SellAllJunkItems`), and the flagged single-option gossip skip
(Blizzard selects options flagged `selectOptionWhenOnlyOption`). Re-check each on the
Forever client.

Auto gossip (`quest.autoGossip`, 18 Sep 2026) covers only what is not native: a choice the
player taught with a modifier click, an NPC's only quest or a finished hand-in, the one
service option among small talk, and an opt-in skip of a lone unflagged dialogue option.
Payment, spell, reward and quest-labelled options are never picked; inside an instance only
taught choices apply.

Deferred out of M4, raised for a later milestone: hide talking head, boss banner and
UI element visibility (7.4), auto select reward by vendor value (7.1), auto accept summon
and auto release (7.5), aggressive tooltip anchoring (7.7.1), session loot log and gold
per hour (7.2).

Status 18 Sep 2026: every deliverable above is written and specced headless except the
native ones listed. Manual checklist for the in-game pass, none of it done yet:

- Tooltip sell price line appears away from a merchant, not at one, with money icons
- Rarity border tints and returns to white when the tooltip clears; comparison tooltips too
- Tooltip anchor cursor and fixed-point modes; bag slots keep their own anchor as documented
- Loot feed on a kill, bumped count on a second drop of the same item, gold row on loot,
  no gold row when selling or taking mail, a burst past the row cap drops the oldest
- Right click dismisses a feed row, and a group row takes its children with it
- Loot feed textures load after a full client restart, checked with `/refactor loottest`
  over both a dark and a snow-bright zone; a multi-slot loot collapses into one row that
  expands and pauses its timer
- Vendor list search, usable filter, buy one, Shift buy stack, buyback row, junk readout
- Auto accept and auto turn in on an ordinary quest; a reward-choice quest stays open
- Auto gossip: `/dump C_GossipInfo.GetOptions()` at a vendor, trainer and flight master
  shows icon file IDs 132060, 132058 and 132057 and a plain dialogue line shows 132053 or
  1019848; Shift click an option and it is picked on the next visit; a quest-only NPC opens
  its quest; a dungeon NPC is left alone until taught; the flagged single option is still
  skipped by the client alone, once, with no double selection
- Chat link click opens the copy box; duel declined; resurrection accepted out of combat
- `AcceptGroup()` from a `/run` on a friend's invite: if it works, remove
  `unavailableReasonKey` from `Modules/Chat/AcceptInvites.lua`
- Camera CVars set on enable and restored on disable; screenshot 1.5 s after level up
- `/refactor bench` with `scriptProfile` on, idle in a capital city
- Conflict panel with Leatrix Plus installed (carried from M3)

Exit criteria:

- [ ] Every module verified in-game at level 30 or below
- [ ] Bench budgets met for load time, idle CPU, memory, garbage rate, zero idle `OnUpdate`
- [ ] Nameplate module tested entering a pull with 10 or more mobs
- [x] `make check` passes

### M5. Beta freeze (15 to 21 Oct)

| Deliverable |
|---|
| Bug fixes only, no new modules |
| Final in-game verification pass of every module |
| Bench output published in the README |
| CurseForge and Wago projects created, flavour tags confirmed |
| Locales complete for enUS |

Exit criteria:

- [ ] Zero known errors
- [ ] Release candidate tagged before the client closes on 21 Oct

### M6. Launch (4 Nov onward)

| Deliverable |
|---|
| Publish on launch day, CurseForge, Wago, GitHub |
| Launch-day patch check: TOC number, api-check against the live client (re-run Probe) |
| 25-player CPU measurement in a battleground, published as a follow-up release |
| Level 60 checks for anything level-dependent |
| Patch-day fixes within hours |

---

## Gear Refactor track

Starts after Refactor M3, so the module contract, theme and price library are proven first.

| Milestone | Scope | Exit |
|---|---|---|
| G0. Libraries | Extract `LibRefactorPrice` and `LibRefactorTheme` to `refactor-libs`, packager externals in both addons | Both addons build with the shared libs, LibStub loads one copy |
| G1. Scoring core | `StatReader` (API plus tooltip text fallback), `Evaluate`, `SpecDetect`, slot rules, cap math, blending, `RewardDecision`. All headless. | Every test in Gear PRD 10.2 passes with no Refactor mock |
| G2. Levelling weights | Weight pipeline, brackets 1 to 30, per-class load-on-demand data | Every DPS spec the sim supports has 1 to 30 weights; hand-built estimates for the rest |
| G3. Tooltip and arrows | Tooltip lines, Shift breakdown, default bag and loot arrows | Verified in-game on beta, hover budgets met |
| G4. Popup and reward highlight | Upgrade popup, reward highlight, Refactor ownership rules | Tested with both addons loaded, one owner per click |
| G5. Auto-pick and Pawn import | Reward auto-pick behind confirmation, Pawn import | Every decision table row verified; freeze by 21 Oct |
| G6. Launch and level 60 | Level 60 brackets and caps validated, promoted from `estimate` | Within 3 weeks of launch |

If G5 cannot be verified before 21 Oct, auto-pick ships disabled and hidden at launch rather than untested.

---

## Parking lot

Decisions deferred on purpose. Not work.

- Whether bag integrations beyond Baganator, Bagnon and ArkInventory are worth it
- Set bonus scoring (Gear Refactor v2)
- Locales beyond enUS
- Raid-specific behaviour, after 9 Dec
