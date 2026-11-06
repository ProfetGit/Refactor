# Refactor

**Product Requirements Document**
Quality of life addon for World of Warcraft: Forever

Status: Draft 1.1, pre-beta (audit fixes applied 16 Sep 2026)
Target client: World of Warcraft: Forever (beta 17 Sep 2026, launch 4 Nov 2026)
Distribution: Public, open source, CurseForge and Wago
Sibling project: Gear Refactor. Neither addon requires the other. Shared code lives in `LibRefactorPrice-1.0` and `LibRefactorTheme-1.0`.
Delivery order: see `docs/ROADMAP.md`. This document is the spec, the roadmap decides what is built now.

---

## 1. Summary

Refactor is a single addon that removes the repetitive friction of playing WoW Forever: clicking through quest dialogue, looting slot by slot, dragging junk to a vendor, re-configuring the same settings on every new alt.

It is deliberately **wide within one layer and empty outside it**. Refactor owns annoyance removal. It does not compete with Questie, Bagnon, Details, Plater, or any auction house addon, and it actively defers to them when they are present.

The differentiator is not feature count. It is the settings experience: a searchable config with sensible defaults that feels like part of the game, plus an account-wide profile system so a new character inherits everything instead of being reconfigured from scratch.

---

## 2. Context

WoW Forever is Blizzard's third permanent WoW experience, launching 4 November 2026 alongside Modern and Classic. It is set in the first year of Azeroth, keeps the level cap at 60, and adds three new zones, over 1,000 quests, nine dungeons, two raids, and the Skyborne elf race.

Two properties of Forever matter for this product:

1. **Everyone rebuilds their AddOns folder on day one.** A fresh client is a rare incumbency reset in a market where incumbency is otherwise decisive. This window is roughly four to eight weeks wide.
2. **Alt-heavy by design.** Horizontal progression at 60, four rulesets, and a fresh levelling curve mean players will roll many characters. That makes account-wide settings a headline feature rather than a footnote.

### 2.1 Beta facts reported so far

Community-reported, not confirmed by Blizzard. Treat as likely until beta day one says otherwise.

| Fact | Consequence |
|---|---|
| Beta runs 17 Sep to 21 Oct 2026 | No client access between beta end and launch. Anything needing a live client must be verified before 21 Oct. |
| Beta level cap is 30, no raids | Level 60 behaviour and 25-player performance cannot be measured until launch. |
| No realms. Four rulesets, two-part character names | Name-Realm is not a safe identity key. See 5.3. |
| Classic-family client, internal build line 1.60.x | See 2.2. |

### 2.2 API assumption and its hedge

**Assumption: Forever exposes a Classic Era style API surface (roughly classic_era 1.15.x), not retail.** Draft 1 assumed retail. Community reporting since BlizzCon describes a Classic-family client, so the baseline is flipped. Blizzard has still published nothing about the addon API, install folder, or TOC interface number.

Consequences:

- Core is written against APIs that exist on Classic Era today.
- Retail-only APIs (`TooltipDataProcessor`, `C_TooltipInfo`, newer `C_*` namespaces) are **optional capabilities**. A module may prefer them, but must declare a fallback or be marked unavailable without them.
- APIs that exist on both flavours (`C_Container`, the `Settings` panel API) are still verified, never assumed.

**Hedge, required regardless.** Every module declares the API symbols it depends on and is loaded inside its own error boundary. A missing symbol disables that one module with a human-readable reason shown in the settings UI. If the assumption is wrong in either direction, the cost is a list of greyed-out modules, not a dead addon.

This is specified in full in section 5.1. Section 13 lists what to verify on beta day one.

---

## 3. Goals and non-goals

### Goals

| # | Goal |
|---|---|
| G1 | A new character requires zero configuration. Settings are inherited from the account profile. |
| G2 | A new user has a good configuration on first login with no setup step (6.1). |
| G3 | Any setting is findable by typing a word into one search box. |
| G4 | Refactor never introduces taint and never touches secure or combat-protected frames. |
| G5 | One broken module never breaks another module. |
| G6 | Refactor detects neighbouring addons and defers rather than duplicating. |
| G7 | Nothing makes an irreversible decision on the player's behalf unless the player explicitly turned that specific thing on. Defaults may include actions that are reversible in the same session (selling junk is undone by buyback). Anything irreversible, or anything that answers another player or an NPC for the player, is Automation and starts off (6.2). |

### Non-goals

Refactor will **never** ship:

- A quest database or levelling route (Questie owns this)
- A bag replacement (Bagnon, ArkInventory)
- A damage meter or combat log parser
- Unit frames, action bars, or any secure frame replacement
- A boss mod
- An auction house scanner or posting interface
- A reskin of Blizzard's frames

The last one is a scope decision, not a taste one. Refactor styles only its own frames using Blizzard's own textures and fonts, so it looks native without owning the visual maintenance burden of the entire default UI.

---

## 4. Positioning

The honest competitive statement: Leatrix Plus occupies this niche today, is trusted, and will very likely ship a Forever build in week one. Refactor cannot win on "has features too."

Three axes where Refactor can be better:

| Axis | Incumbent behaviour | Refactor |
|---|---|---|
| Configuration | Long scrolling lists of checkboxes | Searchable, categorised, sensible defaults, with per-setting explanations |
| Alt handling | Per-character or one global profile | Three-state inheritance: account default, per-character override, explicit off |
| Neighbours | Overlaps silently, user resolves conflicts | Detects neighbours, defers, and says so in the UI |

The "one addon" pitch stays honest because the six things Refactor excludes are exactly the six that people install deliberately.

---

## 5. Architecture

### 5.1 Module system

Every feature is a module. A module is a table registered at load:

```lua
Refactor:RegisterModule({
    id       = "loot.fastLoot",
    category = "Loot",
    requires = { "C_Loot.IsAutoLootDefault", "GetNumLootItems" },
    conflicts = { "FastLoot", "LeatrixPlus.fastLoot" },
    tier     = "minimal",        -- minimal | standard | full | manual
    risk     = "safe",           -- safe | visible | automation
    OnEnable = function(self) ... end,
    OnDisable = function(self) ... end,
})
```

Rules:

- `requires` is resolved before `OnEnable` is ever called. A missing symbol sets the module state to `unavailable` with the missing symbol name surfaced in the UI.
- `OnEnable` and `OnDisable` run inside `pcall`. An error sets state to `failed`, logs a stack trace to `/refactor errors`, and leaves every other module untouched.
- `conflicts` drives the deference layer (5.4).
- Modules never call each other directly. They communicate through the event broker.

### 5.2 Event broker

A single dispatcher registers each game event once and fans it out to subscribed modules. Nine modules interested in `BAG_UPDATE_DELAYED` means one registration, not nine. Handlers are ranked so that cheap filters run before expensive scans, and a throttle wrapper is available for high-frequency events.

This is the main performance argument for an all-in-one addon and it should be measurable. Budgets are defined once, in 9.2.

### 5.3 Settings and profiles

Three-state model per setting:

| State | Meaning |
|---|---|
| Inherit | Use the account-wide value. Default for every setting on a new character. |
| On | Force on for this character regardless of the account value. |
| Off | Force off for this character regardless of the account value. |

Storage:

- `SavedVariables` holds the account profile plus every named profile.
- `SavedVariablesPerCharacter` holds only the overrides map and the first-run completion flag. It stays tiny.
- Character identity key for anything account-side (profile assignment, per-character lists) is `UnitGUID("player")`, not Name-Realm. Forever reportedly has no realms and uses two-part names across four rulesets. Verified on beta day one (13, Q12).

Named profiles exist on top of this (for example "Levelling", "Raiding", "Bank alt") and can be assigned per character. A character's effective value resolves in order: character override, then assigned profile, then account default, then module default.

Import and export as a base64 string so users can share configs, which is also the cheapest possible support tool: "paste your config string" beats twenty questions.

### 5.4 Neighbour detection and deference

At load, Refactor checks for known addons and adjusts:

| Detected | Refactor behaviour |
|---|---|
| Questie | Nameplate quest progress module offers to hand off, defaults to deferring |
| Plater, Threat Plates, NeatPlates | Nameplate modules route through the host's API where one exists, otherwise disable with an explanation |
| Leatrix Plus | Overlapping modules flagged in a conflict panel with a one-click "disable mine" |
| TradeSkillMaster, Auctionator | Registered as price providers (5.5) |
| Bagnon, ArkInventory | Bag tooltip modules adapt anchoring, no bag frame assumptions |
| Gear Refactor | Quest reward selection stands down when `GearRefactor.API.IsHandlingQuestRewards()` is true, and the settings row shows "Handled by Gear Refactor". Loot toast shows the Gear Refactor upgrade badge, and an upgrade prompt at the top centre offers Equip or Not now. All calls through the versioned API, wrapped in `pcall`. |

The conflict panel is a first-class UI surface, not a hidden warning. It lists every detected overlap with a plain-language description and a resolution button.

### 5.5 Price provider chain

Implemented in `LibRefactorPrice-1.0`, shared with Gear Refactor through LibStub. It starts in-tree under `Libs/` and is extracted to its own repo when Gear Refactor work begins (see roadmap). The rules below are the library's contract.

Loot toasts and bag value displays need a price. There is no single source, and on 4 November there is no auction data at all on any realm.

Resolution order, configurable, first hit wins:

1. TradeSkillMaster, via a user-configurable custom price string, default `dbMarket`
2. Auctionator, via its public API
3. Vendor sell price, always available from item info
4. No price shown

Default chain on a fresh install is **vendor price only**. AH providers are opt-in and, when enabled, the toast labels the source (a small `AH` or `Vendor` tag) so the number is never ambiguous. A price from a database with four scans in it is worse than no price if the user cannot tell the difference.

### 5.6 Safety boundaries

Hard rules, enforced by code review and a CI lint:

- No `SecureActionButtonTemplate`, no `SetAttribute` on secure frames, no hooking of protected functions.
- No protected action and no change to a secure or protected frame during combat lockdown. Modules that would need to are simply not built. Changing Refactor's **own** non-secure frames in combat is allowed (hiding a tooltip, disabling a button), and so is declining to act in combat (suppress looting).
- No `UseContainerItem` loop without a rate limiter and a hard cap per vendor visit.
- Every automation module has a kill switch bound to a modifier key held at the moment of the action. The key is one account setting (default Ctrl), stored in `LibRefactorTheme` shared settings so Refactor and Gear Refactor use the same key. Shift is avoided as default because Gear Refactor uses it to expand tooltips.

---

## 6. Settings posture and defaults

Decided 21 Sep 2026: no presets, no first-run screen and no confirmation dialogs. A preset asked
the player to choose a bundle before they knew what was in it. Instead each module declares
`defaultEnabled`, and the Refactor developer makes that call once.

### 6.1 What starts on

A module starts on when it adds information or removes a click, and decides nothing for the
player: fast loot, sell grey items, auto repair, vendor summary, the merchant window modules,
clickable chat links, chat copy, tooltip rarity border, nameplate quest progress, map zone
levels, the update notice.

### 6.2 What starts off

- Anything that acts on the player's behalf (`risk = "automation"`): auto accept and turn in
  quests, party invites, resurrection, duels, quick invite, placing new spells. The player turns
  each on with its own toggle. There is no confirmation dialog.
- Anything that changes the camera or how the default UI looks or sits: ActionCam, camera
  distance, UI visibility, tooltip anchor, hiding the tooltip health bar, map reveal, loot feed.
- Anything that removes a safeguard or writes files: DELETE fill, screenshot on level up.
- Auto gossip, farm session HUD.

---

## 7. Feature catalogue

Risk column: **S** safe, **V** visible (changes the screen), **A** automation (acts for the player, never preset-included).

### 7.1 Quest

| Feature | Notes | Tier | Risk |
|---|---|---|---|
| Auto accept quests | Modifier key held suppresses. Exclusion list for escort, PvP, and repeatable quests. | Manual | A |
| Auto accept only from items | Quest-starting items only, far lower blast radius | Manual | A |
| Auto turn in quests | Skipped entirely when the quest has a reward choice | Manual | A |
| Auto turn in when there is no reward choice | The safe two thirds of the above | Manual | A |
| Auto select reward by vendor value | Explicitly warns it ignores usefulness. Stands down when Gear Refactor owns reward choice (5.4). | Manual | A |
| Skip single-option gossip | The NPC has exactly one thing to say. Never skips a quest-accept or payment option. | Standard | S |
| Auto share quests with party | Only quests just accepted, not the whole log | Manual | A |
| Auto accept shared quests | From party members only | Manual | A |
| Auto track newly accepted quests | Standard | S |
| Auto untrack completed quests | Standard | S |
| Quest progress on nameplates | Defers to Questie and Plater. See 5.4. Optional group progress, off by default: a class-coloured mark per party member the mob still counts for, with their count when it differs from yours | Full | V |
| Quest progress in unit tooltip | Cheaper alternative to nameplates, same data | Full | V |
| Quest item button | Floating button for the active zone's quest items | Full | V |
| Show quest level in the log | Full | V |

### 7.2 Loot

| Feature | Notes | Tier | Risk |
|---|---|---|---|
| Fast loot | Verify necessity on beta. May be partly native. | Minimal | S |
| Loot toast | Icon, name, quality colour, stack count. Animated with `AnimationGroup`, not `OnUpdate` (9.1). Shows Gear Refactor badge when present. | Full | V |
| Toast price display | Provider chain per 5.5, source labelled | Full | V |
| Toast quality threshold | Hide greys, or hide anything below a chosen quality | Full | V |
| Toast aggregation | One toast for a multi-slot loot, expandable | Full | V |
| Currency and gold toasts | Full | V |
| Session loot log | Lightweight rolling list, resets on logout unless pinned | Manual | S |
| Gold per hour | Derived from the session log, off by default | Manual | S |
| Auto confirm BoP loot | Manual | A |
| Suppress looting during combat | Safety valve for melee | Standard | S |

### 7.3 Vendor and money

| Feature | Notes | Tier | Risk |
|---|---|---|---|
| Auto sell junk | Quality selector, default grey only | Standard | S |
| Always-sell list | User-defined, per account | Standard | S |
| Never-sell list | Takes precedence over everything, including quality rules | Standard | S |
| Auto repair | Cap in gold, own funds only by default | Standard | S |
| Repair from guild bank | Requires explicit opt-in, shows which funds were used | Manual | A |
| Vendor routine summary | One chat line: sold 14 items for 3g 20s, repaired for 1g 8s | Standard | S |
| Extended vendor UI | Grid layout, search box, filter by usable and by quality | Standard | V |
| Buyback panel promotion | Prominent, because it is the undo for auto-sell | Standard | V |
| Stack purchase shortcuts | Buy full stack, buy custom amount | Standard | V |
| Bag junk value readout | Total value plus a one-click sell all | Standard | V |
| Sell price in item tooltips | Unit and stack price | Standard | V |

### 7.4 Interface and camera

| Feature | Notes | Tier | Risk |
|---|---|---|---|
| ActionCam on login | Applied via individual CVars, not a console command, so it can be reverted cleanly. Per-character opt-out. Profiles follow situations (indoors, a city, a mount, an NPC, each instance type): indoors and an NPC only bring the camera closer, the rest only back it off, judged against the player's own distance, and a nudge of two yards or less is skipped. A fight never moves the camera: it holds through the fight and three seconds after. The shoulder eases, leaving a building lingers, the first step away from an NPC lets go, and a wheel turn inside a situation is remembered for the session. Blizzard's three presets run through the console command that defines them | Full | V |
| Maximum camera distance | A slider for `cameraDistanceMaxZoomFactor`, 1.0 to the client's 2.6 ceiling. The game's own limit is 1.9, so below that is a closer camera. Restores the default when off | Full | V |
| CVar profile | User-defined set of CVars applied at login, exportable | Manual | V |
| Hide talking head frame | Full | V |
| Hide boss banner and zone text | Individually toggleable | Full | V |
| UI element visibility | Alpha only. Named behaviours given to frame groups, one setup per kind of place, see 7.4.1 | Full | V |
| Screenshot on level up | Full | V |
| Place new abilities | A newly learned ability goes on the first empty slot of a bar that is on screen. Never overwrites a slot, never fills a hidden bar, waits out combat. Retail pushes new spells to bars itself through the AutoPushSpellToActionBar CVar; Forever does not, which is why this exists | Manual | A |
| Zone levels on the map | The hovered zone's level range beside its name on the world map, in the quest difficulty colour. Retail draws this itself; Forever draws the name alone and returns no level data, so the ranges come from a table keyed by zone name and the module stands down wherever the client answers | Full | V |
| Reveal the map | Unexplored areas drawn dimmed under the client's explored overlays, from Blizzard's overlay tables for the installed build, generated by a script; unavailable on a client the data was not made for | Full | V |
| Every class spell in the spellbook | A Refactor side panel on the spellbook's right lists every class spell with its unlock level, unlearned ones in grey and trainable ones marked, with search and learned or not filters, switched by a button in the book. Retail lists future spells itself; Forever lists learned spells only and no API has the rest, so the class trainer's list is recorded per class on each visit, and spells appear once a trainer has been seen | Full | V |
| Auto stand when looting or mounting | Minimal | S |
| Auto dismount for actions | Minimal | S |

#### 7.4.1 UI element visibility

Decided 20 Sep 2026, reworked 6 Nov 2026 at the owner's request. The first version gave every
element a mode, two opacities and two lists of the same conditions, tuned one element at a time
in Edit Mode, and setting up a whole screen was a chore.

An element follows a **behaviour**: a named set of rules made once and given to any number of
elements. A behaviour carries a resting opacity, a revealed opacity (never under a tenth),
whether mouseover reveals it, the conditions that reveal it, the conditions that hide it,
whether its elements reveal together, and a fade time each way. Each condition is listed once,
with a Reveal and a Hide column, so it does one or the other and never both. Opacities are a
share of the frame's own alpha, so an Edit Mode opacity still counts. Resolution is one pure
function: mouseover reveals when the behaviour has it on and beats everything, so a hidden
element can always be reached; then a hide condition takes the element to 0; then a reveal
condition reveals it; otherwise it rests. With reveal together on, hovering one element reveals
every element with that behaviour in the setup in use. An element with no behaviour is left as
the game has it. Editing a behaviour changes every element that has it. A variant is a copy
("Copy as new"), never a per-element override, so an element's look always has one source.

Behaviours are handed out in **setups**. World is the setup everywhere; a city or inn, a
dungeon or delve, a raid, and a battleground or arena can each have their own, which starts as
a copy of World. Where the player is picks the setup: the instance type first (party and
scenario are dungeons, pvp and arena are battlegrounds, as ActionCam reads them), then
resting, then World. A place without a setup of its own uses World's. Conditions come from
`Core/Conditions.lua` (combat, casting, mounted, resting, target, group, instance, stealth,
dead, plus dungeon, raid and pvp, which pick setups and are not offered as triggers), which
holds its events only while a module listens and publishes one event per change. Casting is a
spell with a cast bar, a channel or an empower; it comes from the player's own spellcast
events, registered for the player alone so a raid's casts never reach Lua, and the flag is
read from which event fired, never from a payload that can be secret.

Behaviours and setups are made in Refactor's window: the setup picker listing every element
with its behaviour comes first, because that is what a player does most, then the behaviour
editor. Selecting a system in Edit Mode attaches
Blizzard's settings dialog to it, and a small Refactor-owned companion opens beside that
dialog with the groups the system stands for, each with one behaviour picker that writes to
the setup in use, and a button to the window. Nothing is added to or changed in Blizzard's
dialog, whose setting widgets all write into Blizzard's own layout data. While Edit Mode is
open every element shows as the game has it. Starter behaviours (Fade away, Combat HUD, Clean
when mounted) replace the presets; they are ordinary behaviours the player can edit, copy or
delete, and a fresh install assigns none, so turning the feature on changes nothing until an
element is given one. Rules saved by the first version are converted at login: each distinct
rule and zone becomes a behaviour named Imported 1, 2 and so on, the elements of one zone keep
revealing together, and a condition that hid an element now takes it to 0. Groups:
chat windows, chat tabs, chat buttons, chat input box art, the eight action bars, pet bar,
stance bar, player, target, party and raid frames, experience and reputation bars, micro
menu, bags bar, quest list, minimap, minimap buttons. Buffs and anything else are data entries to add.

A group can also carry frames Refactor made itself. Nothing Refactor creates has a global name, so
the catalogue cannot name one: the feature that owns the frame hands it to `Core/Visibility.lua` and
the visibility module reads it back from there, which is how the chat copy button fades with
Blizzard's chat buttons without either module naming the other. A contributed frame joins a group
that exists; it never revives one whose own frames are missing, and it is given back its original
alpha when its owner withdraws it.

Alpha is the only tool. Never Hide, Show, EnableMouse, SetAttribute or SetParent on a
Blizzard frame. An invisible action bar still takes clicks and keybinds, and the setting
says so. Alpha multiplies down the frame tree, so a group whose frames sit inside another
group's frames can never be more visible than its parent, and the panel says so too.
Mouseover in comes from three signals: `GameTooltip:SetOwner` naming one of a group's
frames (the only signal a secure button gives, and no script of ours ever goes on a
protected or forbidden frame), `HookScript("OnEnter")` on frames that are not secure, and
Blizzard's own chat fade call. Mouseover out is never an event: while anything is hovered a
watch checks the mouse against the hovered frames ten times a second and stops when nothing
is, so a missed leave cannot strand an element visible. A spell or item on the cursor shows
every element at its revealed opacity so a bar can be dropped on. Where Blizzard writes an alpha of its own the group names the function or
frame method to hook and the rule goes straight back on. Fades run on the one
Refactor-owned OnUpdate driver in `Core/Fade.lua`, idle when nothing moves. Every frame is
resolved by name at enable: a missing frame or a neighbour that owns it (ElvUI takes the
whole module, Bartender4 and Dominos the bar groups) costs that group with the reason on
the panel. Turning the module off puts every captured alpha back.

The client draws the minimap's player arrow and quest, task and dig-site areas inside the
Minimap widget, past any frame alpha. The areas have alpha setters but no getters and no
default anywhere in Blizzard's UI code, so fading them is an opt-in on the minimap group and
the shown value is Refactor's own (ring on, fills off); a reload restores the client's. The
arrow has no alpha API on Retail 12.1 and stays.

### 7.5 Chat and social

| Feature | Notes | Tier | Risk |
|---|---|---|---|
| Copy chat | A Copy button in the corner of each chat window, in the Chat buttons visibility group so it hides with Blizzard's own. Plain text, oldest line first, a link kept as the words in its brackets. Lines the client hands over as secret values are counted, not guessed at | Standard | V |
| Chat timestamps | Standard | V |
| Clickable URLs | Standard | V |
| Sticky channels | Standard | S |
| Disable chat tab fade | Standard | V |
| Auto accept party invite | Friends and guild only, never strangers | Manual | A |
| Quick invite | Hold a modifier and click a player to invite them. The client hands addons no world click, so it reads the selection change the click causes and cannot tell left from right | Manual | A |
| Auto decline duels | Manual | A |
| Update notice | Guild and group members swap version numbers over the addon channel, the way DBM and BigWigs do, and a newer one is announced once per session. The only update check an addon can make | Standard | S |
| Auto accept resurrect | Out of combat only | Manual | A |
| Auto accept summon | With a countdown and a cancel | Manual | A |
| Auto release in battlegrounds | Manual | A |

### 7.6 Items and mail

| Feature | Notes | Tier | Risk |
|---|---|---|---|
| Auto-fill DELETE confirmation | Minimal | S |
| Quality borders on bag items | Adapts to detected bag addons | Full | V |
| Open all mail | Rate-limited, with a progress readout and a stop button | Standard | S |
| Take all attachments and gold | Standard | S |
| Remember last mail recipient | Standard | S |
| Bag upgrade | Right-click a bigger bag, or accept the prompt that appears when one lands in your bags, and it takes the place of your smallest bag of the same kind with that bag's contents carried over. See 7.6.1 | Standard | V |
| Confirm replacing enchants | Answers Yes on the "replace this enchant" dialog for your own item, never in a trade window, not in combat. Decided 6 Nov 2026 at the owner's request | Manual | A |
| Send to alts | At the mailbox, a panel beside Send Mail lists what belongs with your other characters, by kind of item or by what you mailed before, and a click attaches it. See 7.6.2 | Standard | V |

Tooltip features are consolidated in 7.7.

#### 7.6.1 Bag upgrade

Decided 6 Nov 2026 at the owner's request. A bag in the player's bags with more slots than an
equipped bag of the same kind is an upgrade. There are two ways in. Right-clicking it in
Blizzard's own bag windows does the swap at once. A prompt, the same one the loot feed uses for
gear, offers each upgrade when it lands in the bags and does the swap on Equip; it is the way in
that works with bag addons, whose item buttons the right-click hook never reaches.

- **Which bag goes.** An empty bag slot is used before anything is replaced. Otherwise the
  equipped bag with the fewest slots among those of the same container subclass, so a herb bag
  only ever replaces a herb bag; on a tie, the one holding fewer items. The backpack and the
  reagent bag slot are never touched.
- **Room first.** The outgoing bag's items need somewhere to go while the bags change, so a swap
  needs at least as many free slots in all as the outgoing bag has; no order of the other bags
  beats that, and replacing a different bag never needs less. Two things close a gap: a
  profession bag's free slots take the items of its trade, and partial stacks of one item that
  fit in one slot are combined, only as many as the swap is short of (6 Nov 2026, after the
  first in-game report). Short even then, nothing moves and the player is told how many slots
  to free.
- **Order.** The outgoing bag's items move to free slots elsewhere, the new bag goes into its
  slot, and the old bag, now empty, takes the place the new one left. Then the moved items go
  into the new bag, so the contents travel with it. That last step is an option, on by default.
- **Binding.** A bag that binds when equipped raises the client's own confirmation, which
  Refactor never answers. The prompt says the bag will bind. Cancelling leaves the moved items
  where they are and says so.
- **Resumable.** Every step reads the bags again before it acts, so a run can stop anywhere and
  carry on from what it finds. Combat pauses it and it resumes after. A refused move ends the
  run with a message, never a retry loop, and a step the client never answers times out.
- **Right-click stands down** while a merchant, bank, mailbox or trade window is open, where the
  click sells, stores or hands the bag over; when an empty bag slot already takes the bag, which
  the client does by itself; and while the pause modifier is held.
- **Slot count.** The client has no API for the size of a bag that is not equipped, so it comes
  from the bag's tooltip line matched against the client's `CONTAINER_SLOTS` format. A bag's
  size never changes for its item ID, so that cache is permanent, the third documented
  exception to the caching rule.
- One chat line when a swap is done.
- On by default: nothing happens until the player right-clicks a bag or presses Equip, and the
  one irreversible part, binding, stays the client's own question (G7).
- Not built: selling the replaced bag at the next merchant, and bank bags. Retail 12.1 has bank
  tabs rather than bank bag slots, and Forever's bank is unverified.

#### 7.6.2 Send to alts

Decided 6 Nov 2026 at the owner's request. With the Send Mail tab open, a panel of Refactor's
own sits beside Blizzard's mail window and lists the items in the bags that belong with another
of the player's characters. A click attaches one. Refactor never presses Send and never answers
a confirmation the client raises; the player sends each mail. The module is `items.sendToAlts`.

- **Recipients.** Every character the player logs in with Refactor is remembered account-side
  by GUID: name, surname when the client gives one, realm. The panel offers those on the
  current realm, never the current character. The **bank alt** is the one picked as the default
  recipient, from the panel or the settings. A player with no other known character never sees
  the panel.
- **What is suggested**, first rule that answers wins:
  1. Never: a bound item (account-bound included), a quest item, a locked item, an item that
     holds loot, and anything on the never-mail list.
  2. An item route: an item mailed by hand to the same own character twice goes to that
     character from then on. Mail to anyone who is not one of the player's characters teaches
     nothing.
  3. A category route. Categories: herbs, metal and stone, cloth, leather, enchanting, gems,
     cooking, elemental, inscription, other crafting reagents, recipes, and gear that binds when
     equipped at uncommon quality or better. Each goes to the bank alt unless the player routes
     it to another character or keeps it.
  4. Own crafts, an option on by default: a category one of this character's crafting
     professions uses stays in the bags (an alchemist keeps herbs). Item routes ignore it.
  - Nothing else is suggested: consumables, soulbound gear, quest items and the rest stay.
- **The panel.** A recipient dropdown with each recipient's count, then the suggested stacks as
  icons, by category and then by value. Click attaches a stack, Shift-click every stack of that
  item. Right-click opens a menu: where this category goes, where this item goes, never suggest
  it. Fill mail attaches as many as the mail has room for. The footer shows what is left and
  in how many mails, the postage, and the value of what is attached.
- **To.** Picking a recipient fills the To field, unless the mail already holds attachments for
  someone else; then the panel says so and attaches nothing. As an option on by default, an
  empty To is filled with the first recipient that has suggestions when the tab opens.
- **Batches.** A mail holds 12 items. After a mail sent with Fill mail, the next batch for the
  same recipient is attached and To filled again, so a big haul is Send, Send, Send.
- **Gold.** An option, off at 0: keep this much gold. The footer then has a button that puts the
  gold above that amount, less postage, in the money field.
- **How an item is attached.** The stack is picked up and dropped on the attachments, as a drag
  would; a stack the mail refuses goes back to the cursor and is put down again. Never by using
  the item, which equips or uses it if the client does not think the send tab is open.
- The pause modifier held as the tab opens skips filling To; held as a mail goes out, it skips
  the next batch.
- An item's category never changes for its item ID, so that cache is permanent, the fourth
  documented exception to the caching rule.
- Tradegoods subclass numbers have no client enum and come from the item data; the in-game
  checklist confirms them with `C_Item.GetItemSubClassInfo`.
- On by default: it attaches nothing until the player clicks, and sending stays the player's.
- Not built: sending from the bank, COD, mail to characters on other realms, and a warband bank
  route. Whether Forever has the warband bank is unverified.

### 7.7 Tooltips

Loaded on demand (9.5). Disabled users never load this code.

| Feature | Notes | Tier | Risk |
|---|---|---|---|
| Tooltip anchoring | User picks the anchor point. See 7.7.1. | Full | V |
| Anchor to cursor | Uses the client's native cursor anchor, no per-frame repositioning | Full | V |
| Manual anchor position | Drag a ghost frame to place it, position saved per character | Full | V |
| Rarity-coloured border | Border tinted to item quality, or to a hovered player's class colour, which is its own option. See 7.7.2. | Full | V |
| Rarity border on all tooltip types | Extends to comparison, bag, and merchant tooltips | Full | V |
| Item level and sell price in tooltips | Unit and stack price, uses the provider chain (5.5) | Standard | V |
| Hide tooltips in combat | Per-category: units, items, both | Manual | V |

#### 7.7.1 Anchoring, and its honest scope

Implemented by hooking `GameTooltip_SetDefaultAnchor`. That hook only reaches tooltips that ask for the default anchor. Frames that call `SetOwner` explicitly, which includes bag slots, action buttons, and most other addons' frames, keep their own anchoring.

Consequences for the spec:

- The settings row states the coverage explicitly rather than promising "all tooltips". Overpromising here generates support threads that cannot be fixed.
- An optional **aggressive mode**, off by default, additionally hooks `GameTooltip.SetOwner` to re-anchor everything. It carries a warning that it will fight other addons, and it appears in the conflict panel (5.4) when a known tooltip addon is present.
- Anchor options: cursor, or one of the nine screen-relative points on a chosen parent, with an X and Y offset, plus a free-drag placement mode.

Performance constraint: cursor following uses the client's own `ANCHOR_CURSOR_RIGHT` behaviour. Refactor does **not** reposition the tooltip in an `OnUpdate`, which is how most implementations of this feature are written and is precisely the pattern 9.3 forbids.

#### 7.7.2 Rarity border

Colour source is the item's quality colour, read once per item ID and cached. Item quality never changes for an item ID, so this cache is **permanent by design** and has no invalidation event. That is the one documented exception to the caching rule in 9.3, and the reason is recorded here so review does not flag it. Cache misses are filled on `GET_ITEM_INFO_RECEIVED`.

- The tooltip may be a `NineSlice` or a backdrop depending on client build. Both paths are implemented behind a capability check. Beta day question (section 13).
- Hovering a player tints the border with the class colour instead, behind its own option, on by default. The colour comes from `C_ClassColor.GetClassColor` and the unit from `TooltipUtil.GetDisplayedUnit`, since a unit tooltip carries a GUID rather than a token. Each class colour is read the first time a player of that class is hovered and kept for the session: the second documented exception to the caching rule, for the same reason as the first, and a class the client gives no colour for leaves the border white. Only players are coloured. A mob keeping the white border is how you tell one from a player at a glance.
- Baseline is an `OnTooltipSetItem` hook (Classic Era surface, 2.2). `TooltipDataProcessor.AddTooltipPostCall` is used only if the capability exists.
- The border is reset on hide. A tooltip that keeps the previous item's colour is the standard bug in every implementation of this feature, so it is an explicit test case.
- Hot path. No table allocation, no string work, and no `GetItemInfo` call per show. Quality colour is resolved from a cached table keyed by item ID, and cache misses fall back to the neutral border until item data is available.
- If Blizzard already colours quality borders natively on Forever, this module is deleted rather than kept for feature count (R2).

### 7.8 Diagnostics

| Feature | Notes |
|---|---|
| Module status panel | Every module, its state, and why if it is not enabled |
| Conflict panel | Detected neighbours and resolutions |
| `/refactor errors` | Captured stack traces from error boundaries |
| Config export string | Base64, for sharing and for support |
| CPU panel | Per-module CPU when the CVar is enabled |
| What's new panel | The changelog, newest first, generated from `CHANGELOG.md` by `make changelog` so it cannot drift from the file. `/refactor changelog` opens it |

### 7.9 Professions

| Feature | Notes | Tier | Risk |
|---|---|---|---|
| Profession levelling planner | Beside the profession window, the fewest crafts or the least gold from the current skill to the rank's cap, as a few steps with progress, replanned whenever the skill, recipes, bags or prices change. See 7.9.1 | Standard | V |

#### 7.9.1 Profession levelling planner

Decided 6 Nov 2026 at the owner's request. With a crafting profession's window open, a panel of
Refactor's own sits on the right edge of Blizzard's profession window and shows the best path
from the character's skill to the cap of the current rank, as a short list of steps. The module
is `items.professionPlanner`. It lists under Items: a category of its own would hold one row,
which the window's category list avoids.

- **Computed, not a guide.** The plan is a function of the skill, the recipes the client lists
  for the profession, the reagents the character holds and, when there are any, prices. Nothing
  in it is kept by hand, so it never goes out of date, and when the skill moves any other way
  (another recipe, a trainer, a different guide) the next update plans from where the character
  stands. That is the difference from the levelling route the non-goals rule out.
- **Recipe colours.** The client gives a recipe's colour at the current skill
  (`relativeDifficulty`) and its grey level (`maxTrivialLevel`), but not where it turns yellow
  or green, and a plan needs that for every level ahead. First source that answers wins:
  1. `Data/ProfessionThresholds.lua`, generated by `Tools/profession-thresholds.py` from the
     client's own `SkillLineAbility` table, which wago.tools publishes per build, the source
     `Tools/map-overlays.py` already uses. Yellow starts at `TrivialSkillLineRankLow`, grey at
     `TrivialSkillLineRankHigh`, green halfway between. Build 1.60.1.70009 has 2,545 recipes
     with thresholds on 16 skill lines (read 6 Nov 2026); Minor Healing Potion reads 55 and 95,
     its yellow and grey levels since Classic. Kept as packed strings per skill line, about
     44 KB, unpacked only for the profession whose window opens. Rerun the tool after each
     Forever build, like the Probe.
  2. Observation, for a recipe the table lacks or that disagrees with the client. Each time the
     window updates, a recipe's live colour narrows the range its yellow level can lie in. The
     plan uses the level 25 below grey, the median distance in the table, held inside that
     range. Kept in `RefactorDB.professionSeen` with the client build, at most 5,000 recipes; a
     different build at login is the invalidation event that clears it.
  - Every read checks the table against the client. A recipe whose live grey level or live
    colour disagrees is planned from observation instead, so a table left stale by a patch
    makes the plan rougher, never wrong. A step planned from an estimate says so.
- **Expected skill per craft.** Orange gives `numSkillUps` points. Yellow and green give a point
  with chance (grey - skill) / (grey - yellow), the formula the game has used since Classic and
  unverified on Forever. Grey gives nothing. Steps show crafts per point when it is above one,
  so the luck in a yellow or green recipe is visible rather than hidden in a promise.
- **What best means**, the option `plannerGoal`, on the panel and in the feature's settings:
  - Fewest crafts, the default. Between recipes a hair apart, one the bags can make now wins.
  - Least gold, when TSM or Auctionator prices the reagents (5.5). The vendor price in the chain
    is what a merchant pays, not what a reagent costs, so it never counts. Without an auction
    provider, or when a reagent the plan needs has no auction price, the plan counts crafts and
    says why. On 4 November there is no auction data anywhere.
  - The plan is an expected-cost programme over skill levels from now to the cap: a few hundred
    recipes over at most a few hundred levels, run when an input changes, never per frame.
    Within 5 percent of a level's own cost it stays on the recipe it was already on, so two
    recipes a hair apart read as one step rather than alternating.
- **Steps.** Levels planned with the same recipe collapse into one step: "x14 Minor Healing
  Potion" with the count in the title colour, then "1 to 15, 1.4 crafts per point". The second
  line drops "crafts", then the rate, before it would be cut beside the ready count
  (`GetCraftableCount`). The current step is marked, and its bar fills from the level it was
  first planned at. Under the title, the crafts left in all, with the gold when planning by gold.
  No rank bar: the profession window shows the rank itself (owner's call, 6 Nov 2026).
- **Shopping list.** Every reagent the rest of the plan needs, against what the bags, bank and
  reagent bank hold, shortest first. It updates as the bags change. Reagents the player could
  craft themselves are listed like any other.
- **Recipes not yet learned** are not planned: the client does not say what skill a trainer asks
  before it teaches one. Where nothing known gives skill any more, the panel says so and names
  up to three unlearned recipes that would carry on, nearest first, with `GetRecipeSourceText`
  in their tooltip. Learning one replans.
- **Rank cap.** The plan ends at the rank's cap (`maxSkillLevel`). At the cap the panel says a
  trainer can teach the next rank. Forever's rank sizes are unverified.
- **Clicking a step** shows its recipe through `C_TradeSkillUI.OpenRecipe`, the client's own call,
  never by writing into Blizzard's frame. Shift-click puts the recipe link in the chat line.
  Refactor never crafts: Create stays Blizzard's button and the player presses it (G7). The
  in-game checklist confirms the click selects the recipe and that crafting after it raises no
  taint in `/refactor errors` or BugSack.
- **The frame.** `ProfessionsFrame` is load-on-demand and absent from the Probe dump, so it is
  looked for a tick after `TRADE_SKILL_SHOW`; without it there is no panel. The panel is
  parented to it and leaves with it. Less folds the panel to its header and the current step,
  remembered per character.
- **Stands down** for someone else's profession, a guild's, or an NPC's crafting window, and
  until the client reports the profession data ready.
- **Which profession is open.** Forever answers `GetChildProfessionInfo` with an empty profession
  (line 0, skill 0 of 0, seen in game 6 Nov 2026), though its window shows the skill. The skill
  comes from the first source that answers: the child line, the base line
  (`GetBaseProfessionInfo`), the line of a recipe the player knows
  (`GetProfessionInfoByRecipeID`), then the spellbook (`GetProfessions`). Recipes are narrowed to
  that line with `IsRecipeInSkillLine` only when the narrowing keeps one the player knows.
  `Diagnose`, run with `/run Refactor.moduleByID["items.professionPlanner"]:Diagnose()`, prints
  every source's answer and each check the panel depends on.
- **Only while the window is open** (9.4). `TRADE_SKILL_SHOW` opens the context and
  `TRADE_SKILL_CLOSE` drops it. While open, `TRADE_SKILL_LIST_UPDATE` and `BAG_UPDATE_DELAYED`
  (throttled), `TRADE_SKILL_DATA_SOURCE_CHANGED`, `SKILL_LINES_CHANGED`, `NEW_RECIPE_LEARNED` and
  `REFACTOR_SETTINGS_CHANGED` invalidate the plan, and the next one rebuilds it. Nothing is held
  while questing.
- `C_TradeSkillUI.GetAllRecipeIDs`, `GetRecipeSourceText` and a few other calls are in the
  Forever dump but not in `Data/api-retail.json`, whose generated documentation leaves them out.
  `make api-check` passes on the Forever dump alone.
- When a known profession levelling addon is present the module defers (5.4). None is known on
  Forever yet.
- On by default: it shows information and decides nothing.
- Not built: gathering professions and fishing, whose levelling is a route through nodes and
  water, the data the non-goals leave to others; a first-craft bonus, unverified on Forever;
  crafting quality, specialisations and crafting orders; crafting the reagents of a step as
  steps of their own; reagents held by alts, which would need a Core service since modules never
  reference each other; buying reagents.

---

## 8. UI specification

### 8.1 Entry points

- **Blizzard Settings panel**: a category named Refactor containing a one-paragraph description and a single "Open Refactor" button. Native placement, no attempt to cram the config into the panel's layout.
- **Slash commands**: `/refactor` canonical, `/rf` registered only if unclaimed.
- **Minimap button and LibDataBroker**: both, minimap button hideable.

### 8.2 The window

Single resizable window, movable, position saved per character.

```
┌──────────────────────────────────────────────┐
│ Refactor          [search…]   Profile ▾   ✕  │
├───────────────┬──────────────────────────────┤
│ Presets       │  Loot                        │
│ Quest         │  ┌────────────────────────┐  │
│ Loot        ● │  │ Fast loot         [On] │  │
│ Vendor        │  │ Speeds up looting…  ⓘ  │  │
│ Interface     │  ├────────────────────────┤  │
│ Chat          │  │ Loot toast     [Inherit]│ │
│ Items         │  │ Shows what you looted ⓘ │ │
│ Automation  ⚠ │  └────────────────────────┘  │
│ ─────────     │                              │
│ Conflicts   2 │                              │
│ Diagnostics   │                              │
└───────────────┴──────────────────────────────┘
```

Rules:

- **Search is global.** Typing filters across every category and shows the category as a breadcrumb on each result. This is the single most important interaction in the addon.
- **Every row has a one-line description.** No setting is a bare label. If a setting cannot be explained in one line, it is two settings.
- **The toggle is three-state** on a character with an account profile: Inherit, On, Off. Inherit shows the resolved value greyed beside it.
- **The ⓘ opens detail**, including what the setting does mechanically, what it conflicts with, and what to do if it misbehaves.
- **Automation is visually distinct.** Warning-coloured category icon, an explanatory header on the page, and the confirmation dialog on first enable of each member.
- Styling follows the visual style in 8.3.

### 8.3 Visual style

Reference image: `docs/style-reference.jpg`. Refactor's own frames should read like that panel: dark, warm, ornate but quiet. Implemented once in `LibRefactorTheme-1.0` and shared with Gear Refactor.

| Element | Target |
|---|---|
| Panel | Near-black warm brown fill, thin bronze double-line border, small copper corner ornaments |
| Section header | Full-width banner bar, dark fill, bronze outline, pointed end caps with a small copper diamond, centred title in muted gold |
| Font | Blizzard's standard serif game font (`GameFontNormal` family). Titles muted gold, body text cream, secondary text grey |
| Tiles and toggles | Rounded rectangles with a subtle inset bevel. Inactive: dark fill, grey text. Active: light tan-grey fill, white text |
| List rows | Label left in cream, value right-aligned, square icon at the far right with a thin dark border |
| Scrollbar | Thin dark rail, copper thumb, diamond arrow caps |
| Spacing | 4 px grid, generous padding, no dense packing |
| Motion | Fades only, 150 ms, no bounce |

Colours are defined as named tokens in `LibRefactorTheme` (for example `PANEL_BG`, `BORDER_BRONZE`, `ACCENT_COPPER`, `TEXT_TITLE`, `TEXT_BODY`, `TEXT_MUTED`), never as literals in module code. Exact values are sampled from the reference image when the theme is built.

**Asset policy.**

1. Use Blizzard's own atlases and textures wherever an equivalent piece exists on the Forever client. Candidates are found with an atlas dump on beta day one, never guessed.
2. Where no equivalent exists, a small custom art kit is allowed, **for Refactor's own frames only**: one texture atlas, at most 256 KB, owned by `LibRefactorTheme`. No custom art is ever applied to a Blizzard frame.
3. Frames are assembled with `NineSlice` layouts or backdrops so pieces scale without new art.

The non-goal "no reskin of Blizzard's frames" is unchanged. This section governs only frames Refactor creates.

---

## 9. Performance

### 9.1 The real target

"No constant loops" is the wrong constraint. An `OnUpdate` that early-returns on a timestamp check costs single-digit microseconds. What actually costs frames in WoW addons is:

1. **Garbage generation.** Every table literal, string concatenation, and closure created in a handler feeds the Lua GC. Sustained allocation produces periodic collection pauses, which is what users perceive as stutter.
2. **Unthrottled handlers on high-frequency events.** `UNIT_AURA`, `NAME_PLATE_UNIT_ADDED`, `BAG_UPDATE`, and anything tooltip-related fire far more often than their consumers need.
3. **Frame creation at runtime.** Creating and discarding frames instead of pooling them.
4. **Repeated scans of data that did not change.** Re-reading 200 bag slots because one slot changed.

Refactor is mostly free by construction. Most modules hang off events that fire at human speed:

| Module class | Trigger | Frequency | Cost |
|---|---|---|---|
| Vendor, repair, sell | `MERCHANT_SHOW` | A few times per minute | Negligible |
| Quest automation | `QUEST_DETAIL`, `QUEST_COMPLETE` | A few times per minute | Negligible |
| Mail | `MAIL_SHOW` | Rare | Negligible |
| Loot, fast loot | `LOOT_OPENED` | Tens per minute | Low |
| Chat, camera, UI visibility | Login and config change only | Once | Zero after setup |
| **Bag borders** | `BAG_UPDATE_DELAYED` | Bursty | **Hot** |
| **Tooltip modules** (prices, rarity border) | `OnTooltipSetItem`, tooltip post-call | Very high while mousing | **Hot** |
| **Nameplate quest progress** | `NAME_PLATE_UNIT_ADDED`, combat | Up to 40 units, constant in combat | **Hot** |
| Toast animation | `AnimationGroup` while visible | Runs in the client, no Lua per frame | Low |

Three hot paths. All optimisation effort goes there. Toast animation was a fourth in Draft 1 and was removed by using Blizzard's animation system instead of `OnUpdate`. The other forty-plus modules need correctness, not tuning.

### 9.2 Budgets

Measured by `/refactor bench`, which runs a fixed scenario and prints per-module figures. These are release gates, not aspirations.

| Metric | Budget | Measured how |
|---|---|---|
| Load time, all modules enabled | < 30 ms | Timestamp delta across `ADDON_LOADED` to `PLAYER_LOGIN` |
| CPU, idle in a capital city | < 0.10 ms per frame | `GetAddOnCPUUsage` with `scriptProfile` on |
| CPU, 25-player combat | < 0.30 ms per frame | Same, in a raid or battleground |
| Memory after load | < 1.5 MB | `GetAddOnMemoryUsage` |
| Memory growth over one hour | < 100 KB | Same, sampled. Non-zero growth is a leak, not a tolerance. |
| Sustained garbage rate, idle | < 10 KB per second | `collectgarbage("count")` sampled |
| Active `OnUpdate` handlers while idle | **0** | Enforced by lint and asserted in bench |

Refactor is allowed to use `OnUpdate` only for something actively animating that `AnimationGroup` cannot express, and the handler removes itself when the animation ends.

### 9.3 Rules

1. **No allocation in hot handlers.** Hot paths use pre-allocated tables and object pools (`CreateFramePool`, `CreateObjectPool`). A lint rule flags table literals and `..` concatenation in files marked `-- @hot`.
2. **`C_Timer.After` over `OnUpdate`** for anything that is not per-frame animation.
3. **Self-terminating `OnUpdate`.** Any `SetScript("OnUpdate", ...)` must have a matching `SetScript("OnUpdate", nil)` in the same file. Lint-enforced.
4. **Upvalue every global used more than once** in a hot function.
5. **Debounce by default.** The event broker exposes `Subscribe(event, handler, throttle)`. Hot events must pass a throttle. `BAG_UPDATE` collapses into `BAG_UPDATE_DELAYED` and then debounces 0.1 s on top.
6. **Cache with explicit invalidation.** Any derived value (quest progress per GUID, price per item ID, junk total per bag) is cached with a named invalidation event. No cache is time-based. A cache of immutable data (item quality per item ID) may be permanent, and must say so in a comment.
7. **Frames are created once**, at module enable, and pooled. No `CreateFrame` inside an event handler.
8. **Disabled means zero.** A disabled module has no registered events, no frames, and its file is not even loaded (9.5).
9. **Animation uses `AnimationGroup`.** Alpha and translation animations run in the client. `OnUpdate` is a last resort.

### 9.4 Contextual event registration

The single biggest structural win, and it is free. A module listens only for its cheap entry trigger, then registers the expensive events when its context opens and drops them when it closes.

```lua
-- vendor module: holds exactly one handler while you are out questing
function Vendor:OnEnable()
    Broker:Subscribe("MERCHANT_SHOW", self.OnMerchantShow, self)
end

function Vendor:OnMerchantShow()
    Broker:Subscribe("BAG_UPDATE_DELAYED", self.RefreshJunk, self, 0.1)
    Broker:Subscribe("MERCHANT_CLOSED", self.OnMerchantClosed, self)
    self:RefreshJunk()
end

function Vendor:OnMerchantClosed()
    Broker:Unsubscribe("BAG_UPDATE_DELAYED", self)
    Broker:Unsubscribe("MERCHANT_CLOSED", self)
end
```

Applied across the catalogue, the steady-state handler count while questing drops to roughly a dozen, most of them on events that fire once a minute.

### 9.5 Lazy loading

Heavy modules ship as load-on-demand sub-addons declared in the TOC with `## LoadOnDemand: 1`. The core checks the saved profile at login and calls `C_AddOns.LoadAddOn` only for enabled ones.

Consequence: a user who leaves those features off never loads the nameplate, toast, or tooltip code at all. Their memory readout reflects what they actually use, which is also the number other players will judge the addon by.

### 9.6 Nameplate quest progress, the one genuinely dangerous module

This is the only module that does real work during combat, so it gets an explicit design rather than a general instruction:

- Quest progress is resolved **once per unit GUID** and cached. `NAME_PLATE_UNIT_ADDED` reads the cache.
- The cache is invalidated only on `QUEST_LOG_UPDATE` and `UNIT_QUEST_LOG_CHANGED`, and invalidation clears the table rather than rebuilding it. Entries are recomputed lazily on next sighting.
- Tooltip scanning happens on cache miss only, never per frame, never in `OnUpdate`.
- A per-frame work cap: at most N nameplates recomputed per frame, remainder deferred with `C_Timer.After(0, ...)` until the queue is empty. No persistent `OnUpdate`. Prevents a spike when 30 plates appear at once entering a pull.
- If Questie or Plater is present, the module defers entirely (5.4) and costs nothing.

### 9.7 No Ace3

Recommendation: do not embed Ace3. AceAddon, AceEvent, AceDB, AceConfig and AceGUI together add meaningful memory and a layer of indirection, and every one of their jobs now has a native equivalent:

| Ace3 component | Native replacement |
|---|---|
| AceAddon | The module registry in 5.1, roughly 80 lines |
| AceEvent | The event broker in 5.2, which we want anyway for throttling |
| AceDB | `SavedVariables` plus the inheritance resolver in 5.3 |
| AceConfig, AceGUI | Blizzard `Settings` API for the panel entry, hand-built window for the rest |
| AceTimer | `C_Timer` |
| AceHook | `hooksecurefunc` |

Embedded libraries, complete list:

| Library | Why |
|---|---|
| `LibStub` | Required to share versioned libraries with Gear Refactor |
| `CallbackHandler-1.0` | Dependency of LibDataBroker |
| `LibDataBroker-1.1`, `LibDBIcon-1.0` | Reimplementing the minimap button is pointless and they are tiny |
| `LibRefactorPrice-1.0` | Own library, price chain (5.5) |
| `LibRefactorTheme-1.0` | Own library, visual style (8.3) and shared settings such as the kill switch key |

This costs perhaps two days of extra work at the start. It buys the memory figure, which is the one performance number users actually see.

---

## 10. Codebase and engineering standards

### 10.1 The honest goal

Users do not read source. What they observe is the memory number in the addon list, whether BugSack stays quiet, and how fast patch day gets fixed. Elegant code that nobody opens convinces nobody.

If the specific concern is that people will dismiss the project as AI slop, the complaint behind that label is not about formatting. It is that such projects hallucinate API calls, are untested, and get abandoned. Formatting cannot answer that. These can:

| Signal | Why it is credible |
|---|---|
| A mocked-API test suite that runs headless in CI | Proves the logic was executed, not just written |
| A project-specific linter enforcing the rules in 9.3 | Proves the performance claims are mechanically checked |
| `/refactor bench` output published in the README, updated per release | Makes the performance claim falsifiable by anyone |
| A changelog where patch-day fixes land in hours | Proves someone is home |
| Issues answered by someone who can explain the code | The actual thing being tested |

Everything below serves those five.

### 10.2 Structure

```
Refactor/
├── Refactor.toc
├── Core/
│   ├── Namespace.lua       -- single global, everything else local
│   ├── Registry.lua        -- module registration, error boundaries, capabilities
│   ├── Broker.lua          -- event dispatch, throttling, subscription lifecycle
│   ├── Settings.lua        -- three-state resolution, profiles, import/export
│   ├── Capabilities.lua    -- API symbol probing (5.1)
│   └── Pools.lua           -- frame and table pools
├── Libs/
│   ├── LibStub/, CallbackHandler-1.0/, LibDataBroker-1.1/, LibDBIcon-1.0/
│   ├── LibRefactorPrice-1.0/   -- in-tree until extracted (roadmap)
│   └── LibRefactorTheme-1.0/   -- tokens, frame builders, art kit (8.3)
├── UI/
│   ├── Window.lua
│   ├── Search.lua
│   └── Widgets/            -- one file per widget type, styled only through LibRefactorTheme
├── Modules/
│   ├── Quest/
│   ├── Loot/
│   ├── Vendor/
│   ├── Interface/
│   ├── Chat/
│   └── Items/
├── Modules_LoD/            -- load-on-demand heavy modules (9.5)
│   ├── Nameplates/
│   ├── Toasts/
│   └── Tooltips/
├── Integrations/
│   ├── TSM.lua
│   ├── Auctionator.lua
│   ├── Questie.lua
│   └── Plater.lua
├── Locales/
├── Tests/
│   ├── mock/               -- WoW API stubs
│   └── spec/               -- busted specs
├── Tools/
│   ├── lint.lua, api-check.lua, bench parsing
│   └── Probe/              -- RefactorProbe dev addon, dumps the client's API (10.8)
├── Data/
│   └── api-forever.json    -- generated from Probe output
├── docs/
│   ├── PRD.md, ROADMAP.md, ARCHITECTURE.md
│   └── style-reference.jpg
└── .github/workflows/
```

One module per file. A module file may not reference another module file, only `Core` and the broker. This is what makes the error boundaries real rather than decorative.

### 10.3 Module file contract

Every module file, without exception:

- Begins with a header comment: purpose, API symbols required, events used, hot or cold.
- Declares everything `local`. The only global write in the entire addon is the namespace itself, lint-enforced.
- Exposes `OnEnable` and `OnDisable`, and `OnDisable` must fully reverse `OnEnable`. Enable, disable, enable again must leave no residue. This is a test case, not a convention.
- Contains no user-facing English strings. Those live in `Locales`.

### 10.4 Linting

`luacheck` with a WoW globals whitelist, plus a small custom checker for project rules:

| Rule | Rationale |
|---|---|
| No writes to `_G` outside `Namespace.lua` | Global leaks are the classic addon smell |
| Every `SetScript("OnUpdate", fn)` has a matching clear in the same file | Enforces 9.3 rule 3 |
| No `CreateFrame` inside a function registered as an event handler | Enforces 9.3 rule 7 |
| No table literals or `..` in files marked `-- @hot` | Enforces 9.3 rule 1 |
| Every module file declares `requires` | Enforces 5.1 |
| Every API symbol used appears in that module's `requires` | Catches hallucinated and removed API calls, which is the single highest-value check in this list |

That last rule deserves emphasis, and a precise scope, because static analysis of Lua cannot see everything:

- **In scope:** reads of undeclared globals (`GetNumLootItems`) and fields on `C_*` namespace tables (`C_Container.UseContainerItem`). Detected from luacheck's global access report plus a pattern pass for `C_Name.Field`.
- **Out of scope:** method calls on frame objects (`GameTooltip:SetOwner`, `frame:SetScript`). Their types cannot be resolved statically. These are covered by the widget method list in the Probe dump and by in-game testing.

`api-check.lua` then verifies every `requires` entry exists in `Data/api-forever.json`. It catches invented functions before they ship, which is precisely the failure mode people associate with AI-written addons.

### 10.5 Tests

Headless Lua 5.1 with `busted`, against a mocked WoW API in `Tests/mock`. The mock is hand-written and deliberately incomplete: a module that touches an unmocked API fails loudly, which keeps the dependency surface honest.

What gets tested:

- Settings inheritance resolution, every combination of account, profile, character override, and module default
- Price provider chain fallback, including all providers absent
- Sell list matching: never-sell beats always-sell beats quality rule
- Enable, disable, enable leaves no residue, for every module
- Capability probing disables the right modules given a stubbed-out API
- Config import and export round-trips

What does not get tested: anything that needs a real client. Those go on the beta checklist instead of being faked.

### 10.6 CI

On every push and pull request:

1. `luacheck` plus the custom rule set
2. `busted` suite
3. API symbol existence check against `Data/api-forever.json` (10.8)
4. TOC interface number validation
5. BigWigs packager dry run

On tag: packager publishes to CurseForge, Wago, and a GitHub release. Changelog generated from commits, so it is never skipped.

### 10.7 Documentation that has to exist

- `CONTRIBUTING.md` explaining the module contract, because it is the thing an outside contributor will get wrong
- A one-page architecture doc, kept to one page
- `docs/ROADMAP.md`, the delivery order, with exactly one milestone marked current
- `/refactor bench` output in the README, refreshed per release
- Inline comments explain **why**, never what. A comment restating the line below it is removed in review.

### 10.8 API ground truth: the Probe dump

`Blizzard_APIDocumentationGenerated` documents mainly the `C_*` namespaces. Many legacy globals the Classic surface depends on (`GetNumLootItems`, `GetQuestReward`, `UseContainerItem`) may be missing from it, so it cannot be the only source for `api-check`.

`Tools/Probe` is a tiny dev-only addon, never packaged. On `PLAYER_LOGIN` it:

1. Walks `_G` and records every function name.
2. Walks every table whose name starts with `C_` and records its function fields.
3. Records the methods available on a sample of each widget type (`Frame`, `Button`, `GameTooltip`, `Texture`, `FontString`, `AnimationGroup`).
4. Records every texture atlas name the client exposes, for the theme asset search (8.3).
5. Records `GetBuildInfo()` and the TOC interface number.
6. Writes all of it to its SavedVariables.

`Tools/probe-to-json.lua` converts that file to `Data/api-forever.json`. The exported API documentation is merged in as a second source for argument signatures. Re-run after every client build.

---

## 11. Success metrics

| Metric | Target |
|---|---|
| Median modules enabled per user after 7 days | > 12 |
| Sessions with zero caught module errors | > 99 percent |
| Memory reported in the addon list, Standard preset | < 1.0 MB |
| Performance budgets in 9.2 met at release | 100 percent, release gate |
| Users with at least one per-character override after 30 days | > 25 percent (proves the profile system is understood) |
| Median time from install to first setting change | < 3 minutes |
| Support threads that are actually neighbour conflicts | < 10 percent (proves the conflict panel works) |

---

## 12. Risk register

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | API surface differs from the Classic Era baseline in either direction | High | Baseline flipped to Classic Era in Draft 1.1 (2.2). Module isolation and capability declarations (5.1). Probe dump on beta day one (10.8). |
| R2 | Blizzard ships some of these natively | Medium | Audit on beta day one. A module made redundant is deleted, not kept for feature count. |
| R3 | Blizzard policy changes on quest automation | Medium | All automation isolated in one category, individually toggleable, removable as a unit without touching the rest of the addon. |
| R4 | Leatrix Plus ships first and takes the window | High | Ship a smaller, working addon on beta day, not a complete one on launch day. Presence during beta is the whole land-grab strategy. |
| R5 | No auction data at launch makes the price feature look broken | Medium | Vendor price is the default provider, sources are labelled (5.5). |
| R6 | Scope creep degrades the polish that is the differentiator | High | The non-goals list in section 3 is a hard boundary. New feature requests outside it are closed, not backlogged. |
| R7 | Auto-sell destroys something valuable | Medium | Never-sell list takes precedence over everything, buyback panel promoted, vendor summary posted to chat every time. |
| R8 | Solo or small team maintenance across 50 modules | High | Error boundaries mean a broken module degrades rather than blocks. Module ownership documented per file. |
| R9 | Hallucinated or removed API calls ship to users | High | The requires-versus-documentation check in 10.4 fails the build before release. |
| R10 | Performance claims drift as modules are added | Medium | The 9.2 budgets are a release gate, verified by the bench harness and published per release. |
| R11 | Beta capped at 30, and no client between 21 Oct and 4 Nov | High | Every module verified in-game before 21 Oct. 25-player CPU budget and level 60 behaviour measured in launch week, and published as a follow-up release, not a launch gate. |
| R12 | Custom art kit grows into a maintenance burden | Low | Own frames only, one atlas, 256 KB cap (8.3). Blizzard atlases preferred. |

---

## 13. Open questions, resolve on beta day one (17 September 2026)

These are cheap to answer with one login and they unblock the entire build. Step zero: install `Tools/Probe`, log in, `/reload`, copy its SavedVariables file (10.8).

1. TOC interface number and install folder name. Which flavour tag do CurseForge and Wago need?
2. Start the client with `-console` and run `ExportInterfaceFiles code` at the login screen. Count `Secret`-tagged entries in the generated API documentation. Thousands means retail-style restrictions, zero means the older policy. This single number decides R1.
3. Does `C_Container` exist, or is it the old `GetContainerItemInfo` namespace?
4. Is the nameplate quest indicator API present?
5. Do the ActionCam CVars exist and do they persist?
6. Value of `MERCHANT_ITEMS_PER_PAGE`, and is the merchant frame extensible?
7. Is the retail `Settings` API present (`Settings.RegisterCanvasLayoutCategory`), or is it the legacy `InterfaceOptions_AddCategory`?
8. Is looting already instant, which would make fast loot redundant?
9. Is there a native loot toast system to hook rather than rebuild?
10. Is the tooltip frame a `NineSlice`, and does `TooltipDataProcessor` exist? Decides the rarity border implementation (7.7.2).
11. Does the client already colour tooltip borders by item quality natively?
12. Confirm that `UnitGUID("player")` is stable across logins and ruleset structure, and check the two-part name format (5.3).
13. Do the ActionCam, `AnimationGroup` and `NineSlice` APIs behave as on Classic Era 1.15?
14. Which Blizzard atlases match the reference style pieces in 8.3 (border, corner, banner, tile)? Answered from the Probe atlas list.

Draft 2 of this document should be written the evening of 17 September, against answers rather than assumptions.
