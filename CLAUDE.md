# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Refactor: quality of life addon for World of Warcraft: Forever. Lua 5.1, WoW addon API. The TOC declares both Retail (`120100`) and Forever (`16001`), and the same files run on both.

Full product spec: `docs/refactor-prd.md`. Delivery order: `docs/ROADMAP.md`. This file is the working contract, not the spec.

**Before any task, read the "Current milestone" section of `docs/ROADMAP.md`.** Work only inside that milestone. If a request falls outside it, say which milestone it belongs to and ask before starting.

## Commands

```
make dev-setup   # once: busted, luacheck and dkjson into .tools/
make lint        # luacheck + project rules (Tools/lint.lua)
make test        # busted against the mocked API in Tests/mock
make api-check   # every `requires` symbol verified against Data/api-retail.json; Forever gaps reported from Data/api-forever.json
make check       # lint + test + api-check. Run this before saying a task is done.
make package     # check, then Tools/package.py zips exactly the TOC's files into .release/Refactor-retail.zip (what CI runs)
make changelog   # regenerate Locales/Changelog.enUS.lua from CHANGELOG.md; changelog_spec fails while it is stale
make api-index   # regenerate Data/api-retail.json from a wow-ui-source checkout (SOURCE=~/wow-ui-source)
make probe-index # regenerate Data/api-forever.json from a Tools/Probe dump (PROBE=Data/forever-probe.lua)
```

Every target runs through `Tools/dev-env.sh`, which puts the project-local `.tools/` tree on the path. One spec file, or one test by name:

```
sh Tools/dev-env.sh busted --lua=lua5.1 Tests/spec/core_spec.lua --filter "residue"
```

`make check` must pass. If it cannot pass, say so explicitly rather than working around it.

## Non-negotiable rules

Violating any of these is a bug even if the code works.

1. **No taint.** Never touch `SecureActionButtonTemplate`, never `SetAttribute` on a secure frame, never hook a protected function. If a feature seems to need this, it is not built.
2. **No protected actions and no changes to secure or protected frames during combat lockdown.** Modules that would need it are not built. Changing Refactor's own non-secure frames in combat (hiding a tooltip, disabling a button) is fine, and so is declining to act in combat.
3. **One file writes globals.** Every write to `_G` lives in `Core/Namespace.lua`: the namespace, SavedVariables, the slash command, and `R:SetBlizzardTunable` for the short allowlist of Blizzard layout constants a module may change and must restore on disable (today only `MERCHANT_ITEMS_PER_PAGE`). Everything else is `local`.
4. **Every API symbol a module uses appears in its `requires` list.** No exceptions. This is what `make api-check` verifies and it is the main defence against invented functions.
5. **No allocation in files marked `-- @hot`.** No table literals, no `..` concatenation, no closures created per call. Use pools and caches.
6. **Every `SetScript("OnUpdate", fn)` has a matching `SetScript("OnUpdate", nil)` in the same file.** `OnUpdate` is only for something actively animating, and it removes itself when the animation ends. Zero active `OnUpdate` handlers while idle is a release gate.
7. **`OnDisable` fully reverses `OnEnable`.** Enable, disable, enable again leaves no residue. There is a test for this per module.
8. **Modules never reference each other.** A module file may import `Core` only. Cross-module communication goes through the event broker.
9. **No user-facing strings outside `Locales/`.**
10. **No new dependencies.** Ace3 is deliberately not used, see PRD 9.7. The complete list of embedded libraries: `LibStub`, `CallbackHandler-1.0`, `LibDataBroker-1.1`, `LibDBIcon-1.0`, and our own `LibRefactorPrice-1.0` and `LibRefactorTheme-1.0` (in-tree under `Libs/` until extracted). Anything else needs approval first.
11. **No frame creation inside an event handler.** Frames are created once at module enable and pooled.
12. **Never reskin Blizzard frames.** Refactor styles its own frames only, through `LibRefactorTheme` and the visual style in PRD 8.3. No colour literals or texture paths in module or widget code, only theme tokens. One layout exception, decided 19 Sep 2026: the vendor modules that work inside Blizzard's merchant window (`vendor.extendedUI`, `vendor.itemCosts`, `vendor.filter`) resize it, hide cells, and add widgets from Blizzard's own templates. They change where things sit, never how they look, and undo all of it on disable.
13. **Animation uses `AnimationGroup`.** `OnUpdate` only when an animation cannot be expressed that way. Alpha on a Blizzard frame is tweened by the one driver in `Core/Fade.lua`, never by an `AnimationGroup` created on the Blizzard frame and never by `UIFrameFadeIn`, which writes into the frame's table.

## API ground truth

Never write an API call from memory. Verify it, in this order:

1. `Data/api-retail.json`, generated by `Tools/source-index.py` from Blizzard's interface source at the installed build (currently Retail 12.1.0.69814). A symbol only enters it from the generated API documentation, from a reviewed source reference in `Data/legacy-api.json`, or, for a global the client exports but no Blizzard UI file calls, from `Data/client-api.json`, which names the client index that verified it and the build. Today that list is `GetCameraZoom` alone
2. The `hated-wow-mcp` tools, which index this client's API, atlases and icons
3. The `wow-ui-source` checkout the index was generated from, to see how Blizzard does it

`Data/probe-answers.json` holds what a one-off in-game dump established about tooltip fields, objective type strings and atlas availability. Treat it as evidence, not as a live index.

`Data/api-forever.json` is the Forever client's own answer rather than source evidence. `Tools/Probe` is a dev addon, never packaged, installed on Forever as its own `RefactorProbe` folder: it dumps every global, the fields of every API table, widget methods, CVars and documented events, and `make probe-index` converts the dump. Globals another addon wrote are kept apart in `addonGlobals`, because the dump cannot tell an addon's global from a client global the addon overwrote. Re-probe after every Forever build; the current dump is 1.60.1.70009, 25 Sep 2026.

If a symbol cannot be verified, say so and stop. Do not guess a plausible name. A wrong function name that ships is the single failure mode this project is built to avoid.

The baseline is the **Retail API surface** at the installed build. The first Probe dump backed Blizzard's claim that Forever uses the Retail API: Forever reports `WOW_PROJECT_ID` 1 (Mainline), carries Retail's secret-value restrictions in its API documentation, and exposes every symbol Refactor declares. That settles existence, not behaviour on Forever. See PRD 2.2 and section 13, and the retail-first note in `docs/ROADMAP.md`.

`make api-check` fails on a declared symbol found in neither index, which is the invented kind. A symbol Forever lacks is listed per file without failing, because capability probing already shows that module as unavailable there. Passing is not proof that the call behaves as expected or that it is unprotected. In-game verification is still a separate step.

Scope of the requires check: globals and `C_*` namespace fields. Method calls on frame objects are out of scope for static checking, see PRD 10.4.

## Repo layout

```
Core/           Namespace, Registry, Capabilities, Broker, Settings, Conditions, Visibility, Fade, Safety, Pools, Codec, Bench, Commands, Bootstrap
UI/             Window, Search, Widgets, Panels/, and the frames modules drive (LootFeed, FarmHud, Merchant*, ChatCopy, MapReveal)
Modules/        Feature modules, one folder per category
Modules_LoD/    Heavy and hot modules: Nameplates, Toasts, Tooltips. Despite the name they are listed in Refactor.toc and load with the rest
Integrations/   Neighbours (conflict panel), deference (Questie, Plater, Plumber, FrameOwners), price providers (TSM, Auctionator, Prices)
Locales/        enUS strings; Changelog.enUS.lua is generated
Libs/           LibStub, LibRefactorTheme-1.0, LibRefactorPrice-1.0
Media/          Refactor's own textures, and CustomTheme.lua (theme overrides)
Tests/mock/     Hand-written WoW API stubs
Tests/spec/     busted specs
Tools/          lint.lua, api-check.lua, source-index.py, probe-to-json.lua, Probe/, changelog.lua, package.py, map-overlays.py
Data/           api-retail.json and its inputs (legacy-api.json, client-api.json), api-forever.json, probe-answers.json, MapOverlays.lua (shipped)
docs/           refactor-prd.md, ROADMAP.md
```

One module per file. New file means new entry in `Refactor.toc` and a `requires` list. The TOC is the load order and the package list: `Tools/package.py` ships exactly what it names.

## Architecture

Every file shares the addon's private table `R` (`local _, R = ...`). `Core/Namespace.lua` also publishes it as `_G.Refactor`, so `/run` diagnostics can read `Refactor.moduleByID[id].state`, `.missing`, `.failure` and `Refactor.errors`.

Load order in `Refactor.toc`: Libs, Core, Locales, UI, Modules, Integrations, Modules_LoD, then `Core/Bench`, `Core/Commands` and `Core/Bootstrap` last. At file load a module only calls `R:RegisterModule`. Nothing turns on until `PLAYER_LOGIN`, when Bootstrap runs `InitSavedVariables` and `Settings:Init`, `UI:Initialize`, registers the price providers, runs `Registry:ReconcileAll` and registers the slash command.

- **Registry** (`Core/Registry.lua`). States are `disabled`, `enabled`, `unavailable` and `failed`. `Enable` marks a module `unavailable` when it set `unavailableReasonKey` (how a module defers to a neighbour addon) or when `Capabilities:Check(requires)` finds a symbol missing from the live `_G`, and names the symbol in `module.missing`. `OnEnable` runs inside `R:Try`; an error leaves the module `failed` until the player toggles it. Disable always ends with `Broker:UnsubscribeAll` and `R:CancelTimers` for the module.
- **The definition table is the module's `self`.** The table passed to `R:RegisterModule` is what every method receives, so per-visit state stored in a definition field (`self.id`, `self.requires`, `self.category`, `self.risk`) overwrites the registry's copy. Lint rejects those writes. This is how the auto gossip toggle broke once.
- **Settings** (`Core/Settings.lua`). Whether a feature is on resolves as character override, then the profile assigned to this character's GUID, then the account value, then the module's `defaultEnabled`. The window's Editing switch chooses which layer a click writes. Options (`GetOption` and `SetOption`) are values inside a feature, validated against `OPTION_DEFAULTS` and refilled from them by `Settings:Init`. Every change emits `REFACTOR_SETTINGS_CHANGED`, and a change to a module id (not to an option) re-reconciles every module, which is what makes the toggle live.
- **Broker** (`Core/Broker.lua`). One frame carries every Blizzard event. Events prefixed `REFACTOR_` are internal and never registered with the client (`REFACTOR_SETTINGS_CHANGED`, `REFACTOR_MODULE_CHANGED`, test events). `Subscribe(event, handler, owner, throttle, priority)`.
- **Errors.** Handlers run through `R:Try` and `R:SafeCall` (xpcall) and land in `R.errors`, shown by `/refactor errors`. They never reach BugGrabber, so an empty BugSack does not mean no errors.
- **Shared services modules call instead of reimplementing:** `R:Paused()` in `Core/Safety.lua` (the one pause modifier every automatic action honours), `Core/Conditions.lua` (player state flags, events held only while a consumer is started), `Core/Visibility.lua` with `Core/Fade.lua` (UI visibility rules and the only `OnUpdate` driver), `R:After` (timers cancelled with their owner), `Core/Pools.lua`, and `Core/Codec.lua` (profile share strings).
- **Tests.** `Tests/mock/runtime.lua` builds an environment where `_G` is the env itself, loads the Libs and Core into it, and drives time with `env:Advance` and events with `env:Fire`. Each spec stubs the gameplay API it needs. Without those stubs most modules resolve as `unavailable`, so a spec that only clicks the UI never enables them: reproduce a module bug with the module's own capability stubs, as `m4_spec.lua` does.

## Module contract

Every module file starts with this header and exposes exactly this shape:

```lua
--- @module vendor.autoSell
--- Purpose: sells junk items automatically when a merchant window opens.
--- Requires: C_Container.GetContainerItemInfo, C_Container.UseContainerItem
--- Events: MERCHANT_SHOW, MERCHANT_CLOSED, BAG_UPDATE_DELAYED (contextual)
--- Hot: no

local _, R = ...
local Broker, Settings = R.Broker, R.Settings

local AutoSell = R:RegisterModule({
    id        = "vendor.autoSell",
    category  = "Vendor",
    requires  = { "C_Container.GetContainerItemInfo", "C_Container.UseContainerItem" },
    conflicts = { "LeatrixPlus.sellJunk" },
    risk      = "safe",       -- safe | visible | automation
    defaultEnabled = true,
})

function AutoSell:OnEnable()
    Broker:Subscribe("MERCHANT_SHOW", self.OnMerchantShow, self)
end

function AutoSell:OnDisable()
    Broker:UnsubscribeAll(self)
end
```

Rules that follow from it:

- There are no presets and no first-run screen. `defaultEnabled` is the whole default: on only for a module that adds information or saves a click without deciding anything for the player. `risk = "automation"` modules are always `defaultEnabled = false`.
- Expensive events are registered when the module's context opens and dropped when it closes, not at enable. See PRD 9.4. A vendor module holds one handler while the player is questing.
- `Broker:Subscribe(event, handler, self, throttle)` takes a throttle. Hot events must pass one.

## Performance budgets

These are release gates, measured by `/refactor bench`. Do not regress them.

| Metric | Budget |
|---|---|
| Load time, all modules | < 30 ms |
| CPU idle, capital city | < 0.10 ms per frame |
| CPU, 25-player combat | < 0.30 ms per frame |
| Memory after load | < 1.5 MB |
| Memory growth per hour | < 100 KB |
| Active `OnUpdate` while idle | 0 |

The hot modules get real scrutiny: nameplate quest progress and the tooltip modules. Bag quality borders were dropped as native on Retail 12.1. Toasts are not hot because they animate with `AnimationGroup`. Everything else hangs off events that fire at human speed and needs correctness, not tuning. Do not micro-optimise cold modules.

## Caching

Any derived value is cached with a **named invalidation event**. No time-based cache expiry anywhere. If you cannot name the event that invalidates a cache, the cache is wrong.

One exception: a cache of data that never changes (item quality by item ID) may be permanent. It must carry a comment saying so.

Cache keys are nested tables, never strings built with `..`. Weak tables do not collect string keys, so never use a weak table as a bound on a string-keyed cache.

## Verifying work

Before reporting a task complete:

1. `make check` passes.
2. Pure logic has a spec in `Tests/spec/`. Settings resolution, price chain, sell-list precedence, and enable/disable residue are all testable headless and must be tested.
3. Anything needing a live client goes on the manual checklist in the PR description, not faked in the mock.

In-game errors: after `/reload`, BugGrabber writes every error with a stack trace to its SavedVariables file. Ask for the path and read it rather than speculating about a runtime failure. Errors inside Refactor's own handlers are caught before BugGrabber sees them: ask for `/refactor errors` output too. `/refactor saved` reports whether the client handed the saved variables back at login.

The mock in `Tests/mock` is deliberately incomplete. If a module touches an unmocked API the test fails loudly. Add the stub deliberately, do not stub broadly to make a test pass.

## Out of scope

Do not build, and do not suggest building:

- Quest database or levelling routes (Questie)
- Bag replacement (Bagnon, ArkInventory)
- Damage meter or combat log parser
- Unit frame or action bar replacements. Alpha-only visibility control of Blizzard frames is allowed; no Hide, Show, SetAttribute, EnableMouse or SetParent on secure frames
- Boss mods
- Auction house scanning or posting
- A reskin of the default UI

When a neighbouring addon is detected, Refactor defers to it. Detection and deference live in `Integrations/`. See PRD 5.4.

## Style

- Lua 5.1. No `goto`, no integer division, no bitwise operators, no `#!` shebangs.
- 4 spaces, no tabs. Max line 120.
- `local` everything. Upvalue any global used more than once in a hot function.
- Modules `PascalCase`, functions `PascalCase` for methods and `camelCase` for locals, constants `SCREAMING_SNAKE`.
- Module ids are `category.featureName`, lowercase first segment.
- Comments explain **why**. A comment restating the line below it gets removed in review.
- No emoji in source, in the UI, or in commit messages.
- No em dashes in user-facing strings, docs, or commit messages.

## Working style

- Make the smallest change that solves the problem. Do not reformat or refactor unrelated code in the same change.
- Do not add a feature that is not in the PRD without raising it first.
- If a requirement in the PRD looks wrong, say so rather than implementing it silently. The PRD is a draft and several of its decisions are explicitly marked as assumptions.
- Prefer deleting a module over keeping it when the game does the job natively. Feature count is not a goal.
- When a milestone's exit criteria are met, say so and stop. Do not start the next milestone without being asked.
