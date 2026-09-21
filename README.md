# Refactor

**Quality of life for World of Warcraft. Small features, each explained in a line, each switchable per character.**

Refactor removes the clicks you never wanted and leaves everything else alone. It never touches
secure frames, never reskins Blizzard's UI, and no automation runs unless you turned it on yourself.

Built for Retail 12.1.0 first. WoW Forever support follows once that client can be probed.

---

## Contents

- [Install](#install)
- [Getting started](#getting-started)
- [Features](#features)
  - [Loot](#loot)
  - [Vendor](#vendor)
  - [Quest](#quest)
  - [Items](#items)
  - [Chat and social](#chat-and-social)
  - [Interface and camera](#interface-and-camera)
  - [Tooltips](#tooltips)
  - [Nameplates](#nameplates)
- [Defaults](#defaults)
- [Profiles and per-character settings](#profiles-and-per-character-settings)
- [Price sources](#price-sources)
- [Plays nicely with](#plays-nicely-with)
- [Slash commands](#slash-commands)
- [Development](#development)

---

## Install

1. Download the release zip.
2. Extract it into `_retail_/Interface/AddOns/` so the folder is `AddOns/Refactor`.
3. If the build predates the current patch, tick **Load out of date AddOns** on the character
   selection screen.

## Getting started

Refactor starts with a sensible set of features on, see [Defaults](#defaults). Switches are account
wide, so a new character inherits them without a click.

Open the window any of these ways:

| How | What |
|---|---|
| Minimap button | Left click opens. Right click prints recorded errors. Drag moves it. |
| `/refactor` or `/rf` | Opens the window. `/rf` steps aside if another addon claimed it. |
| Blizzard Settings | A Refactor category with an Open button. |

Every feature is one row: a checkbox, a line saying what it does, and a chevron when it has
settings of its own. Search covers feature names, descriptions and every setting, so you never
need to know which feature owns an option.

Hold the **pause modifier** (Ctrl by default) at the moment of any automatic action to skip it.

---

## Features

The **Default** column says whether a feature is on before you touch it.

### Loot

| Feature | What it does | Default |
|---|---|---|
| **Fast loot** | Collects everything the moment the loot window opens, when auto-loot is on. | On |
| **Loot feed** | One rolling list of what you just looted: icon, name, count and price. Repeated drops bump a row, a multi-slot loot collapses into one row, rows fade one at a time. Minimum quality, price line, gold and currency rows, opacity, lifetime, row cap and size are settings. Move it in Edit Mode. Right click dismisses a row. | Off |
| **Farm session HUD** | A small display of what this farming session earns per hour: gold, items, kills, and a goal meter. Starts on the first loot, pauses when you idle, and hands you a summary you can copy. | Off |

### Vendor

| Feature | What it does | Default |
|---|---|---|
| **Sell junk** | Sells every grey stack when a merchant window opens. A never-sell list of item IDs always wins. | On |
| **Auto repair** | Repairs with your own gold, under a cap you set. Never touches guild funds. | On |
| **Vendor summary** | One chat line with what was actually sold and repaired when you leave. | On |
| **Bigger merchant window** | More rows and columns in Blizzard's own merchant window, from two by five up to five by eight. Paging and the wheel follow. | On |
| **Clearer merchant costs** | Greys out only the currency you are short of, and lists what the merchant takes in the coin box, including item costs like Glowcaps. | On |
| **Merchant filter** | A dropdown to show only mounts, pets, toys, appearances or recipes, owned or missing, laid out on pages of their own. | On |

### Quest

| Feature | What it does | Default |
|---|---|---|
| **Auto gossip** | Picks the gossip option you would have picked: an NPC's only quest, a finished hand-in, the one shop or trainer option among small talk. Shift click any option to teach it a choice for that NPC. Never picks payments, spells or rewards. | Off |
| **Auto accept quests** | Accepts a quest as soon as its dialog opens, and works through every quest an NPC offers. Skips PvP and repeatable quests. | Off |
| **Auto turn in quests** | Completes a quest when there is nothing to choose. A reward choice always stays yours. | Off |

### Items

| Feature | What it does | Default |
|---|---|---|
| **Fill DELETE confirmation** | Types DELETE into the item deletion confirmation for you. You still click Yes. | Off |

### Chat and social

| Feature | What it does | Default |
|---|---|---|
| **Clickable links in chat** | Web addresses become links that open a copy box. | On |
| **Auto decline duels** | Declines every duel request without a popup. | Off |
| **Auto accept resurrection** | Accepts a player's resurrection out of combat. Choose where: battlegrounds, dungeons and raids, the open world. | Off |
| **Auto accept party invites** | Joins a group when a friend, Battle.net friend or guild member invites you. Anyone else still gets the popup. | Off |

### Interface and camera

| Feature | What it does | Default |
|---|---|---|
| **ActionCam** | Camera profiles. Blizzard's Basic, On and Full, plus Refactor's **Immersive** (close, over the shoulder, tilting as it comes in, tuned for mouse and keyboard) **Controller: Ranged** and **Controller: Melee** (a gentle or a strong pull toward the target, no head sway, tuned for a gamepad), **Cinematic**, **Raider**, **Melee** and **Comfort**. Each profile names a camera distance and shoulder offset for where you are: indoors, in a city or inn, on a mount, in combat, talking to an NPC, or in a dungeon, raid, battleground or arena. Distances are absolute, so the camera never ends up inside your character, and a situation can leave the camera where you had it. Leaving a situation gives your own distance back. Save a copy of any profile, tune it on sliders, and share it as a string. | Off |
| **Maximum camera distance** | Lets the camera zoom out further than the options menu allows. | Off |
| **Screenshot on level up** | Takes a screenshot a moment after you level, so the effect is in frame. | Off |

### Tooltips

| Feature | What it does | Default |
|---|---|---|
| **Rarity-coloured border** | Tints the tooltip border with the item's quality colour, on the main, linked and comparison tooltips. | On |
| **Tooltip anchor** | Moves the default tooltip to the cursor or a fixed screen point, with offsets. | Off |
| **Hide the health bar** | Removes the green health bar under a unit tooltip. | Off |

### Nameplates

| Feature | What it does | Default |
|---|---|---|
| **Quest progress on nameplates** | A ring that fills as the objective advances, an icon for kills, items or a skull for the last one. Choose the side, dim completed mobs, reduce animation. | On |

---

## Defaults

There is no setup screen. Features that only add information or save a click start on: fast
loot, sell junk, auto repair, the vendor summary, the merchant window changes, clickable chat
links, the rarity border and quest progress on nameplates. Anything that acts on your behalf,
such as accepting quests or invites, or that changes the camera or how the screen looks, starts
off. Every feature has its own toggle.

## Profiles and per-character settings

- **Account defaults** apply to every character.
- A character can override any feature with **Inherit**, **On** or **Off**.
- A **profile** is a named set of feature switches. Assign one to a character, export it as a
  string, import a friend's.
- Options such as the repair cap, the never-sell list and camera profiles are account wide.

## Price sources

Vendor sell price is always on. **TradeSkillMaster** (with a custom price string) and
**Auctionator** are opt-in under General. A price from an auction database is labelled with its
source wherever it is shown: the loot feed, the farm HUD and the merchant window.

## Plays nicely with

Refactor steps aside when another addon already does the job, and says so on the feature's row
and in the Conflicts panel.

| Addon | What Refactor defers |
|---|---|
| Leatrix Plus | Fast loot, sell junk, auto repair, auto gossip |
| Questie, Plater, Threat Plates, NeatPlates | Quest progress on nameplates |
| Scrap | Sell junk |
| Plumber | Clearer merchant costs, when its Merchant Price is on |

## Slash commands

| Command | What it does |
|---|---|
| `/refactor` | Open or close the window. |
| `/refactor errors` | Print anything Refactor's error boundaries caught, with a trace. |
| `/refactor clear` | Clear the recorded errors. |
| `/refactor bench` | Load time, memory, garbage rate and CPU per frame, for release gates. |
| `/refactor loottest` | Push fake rows through the loot feed and name any texture that failed to load. |
| `/refactor farmtest` | Fill the farm HUD with sample data to check its art over a dark and a bright zone. |

---

## Development

```
make check     # luacheck, project rules, busted specs, API symbol check
make package   # deterministic zip in .release/
make api-index # regenerate Data/api-retail.json from a wow-ui-source checkout
```

`make dev-setup` installs busted, luacheck and dkjson into a local `.tools` tree.

Every API symbol a module uses is declared in its `requires` list and verified against
`Data/api-retail.json`, which is generated from Blizzard's own interface source for the
installed build. A symbol that cannot be found there does not ship.

The working contract is in `CLAUDE.md`, the product spec in `docs/refactor-prd.md`, and the
delivery order in `docs/ROADMAP.md`.

## Performance budgets

These are release gates, measured by `/refactor bench`.

| Metric | Budget |
|---|---|
| Load time, all modules | under 30 ms |
| CPU idle, capital city | under 0.10 ms per frame |
| CPU, 25-player combat | under 0.30 ms per frame |
| Memory after load | under 1.5 MB |
| Memory growth per hour | under 100 KB |
| Active `OnUpdate` handlers while idle | 0 |
