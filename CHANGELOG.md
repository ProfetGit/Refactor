# Changelog

## Unreleased

M4 (18 Sep 2026), built against Retail 12.1.0, none of it verified in game yet:

- Tooltips: sell price per unit and per stack, labelled by source and hidden at merchants;
  rarity-coloured border on the main, linked and comparison tooltips, reset on clear;
  anchor mode (game default, cursor, fixed screen point with offsets).
- Loot feed: one anchored rolling list instead of floating toasts. Own loot only, parsed
  from the item link so no locale string is needed, newest row at the bottom, repeated
  drops bump one row, rows fade out one at a time and the rest slide up. A multi-slot loot
  collapses into one row with a chevron that expands it and pauses its timer. Minimum
  quality, optional price line and source tag, gold and currency rows without an icon
  frame, opacity, row lifetime and row cap are settings. Rows are Buttons, so Gear
  Refactor has an anchor for its badge later. Custom row art in Media, tinted in code.
  Fades and slides only, animated by the client, sixteen pooled frames.
- Loot feed prices use the client's coin icons instead of the letters g, s and c, and drop
  denominations that are zero: a grey reads "8c" with a copper coin, not "0g 0s 8c".
- Right click a loot feed row to dismiss it; the rows below slide up. On a group it takes
  the whole group. Left click stays reserved for Gear Refactor.
- Loot feed rows hold while hovered, show the item's own tooltip, and start their life
  again when the cursor leaves. Selecting the feed in Edit Mode opens a Blizzard-style
  dialog with size, row count and lifetime on minimal sliders, each with its own undo
  button. The dialog sits in screen space and is dragged on its own, so resizing the feed
  never moves it; its position is saved per character.
- `/refactor loottest` pushes fake rows through the feed and names any feed texture the
  client would not load.
- Vendor: bag junk value readout under the merchant window; extended vendor list beside
  it with search, usable filter, click to buy one, Shift click for a stack, and buyback.
- Quest automation: auto accept (skips PvP, repeatable and game-auto-accepted quests,
  optional items-only) and auto turn in when there is no reward choice.
- Chat and social: clickable web addresses with a copy box; auto decline duels; auto
  accept resurrection out of combat. Auto accept party invites is written but ships
  unavailable until AcceptGroup is confirmed callable from an addon.
- Interface: maximum camera distance, ActionCam through its three CVars, screenshot on
  level up. Mail: remember last recipient per character.
- Price providers: TradeSkillMaster (custom price string) and Auctionator, opt-in under
  Display options, labelled wherever a price is shown.
- `/refactor bench`: load time, memory, garbage rate, CPU per frame when scriptProfile is
  on, handler counts, and OnUpdate handlers on Refactor's frames.
- Display options panel. Diagnostics list scrolls. Window categories: Quest, Chat, Social,
  Tooltips, Toasts, Display.
- Not built because Retail does it natively: bag quality borders, auto track quests, chat
  timestamps, sell-all-junk, skip single-option gossip.

- First Retail build: module registry, capability probing, event broker, settings with
  three-state resolution and profiles, theme library on Dragonflight atlases.
- Modules: fast loot, DELETE fill, sell grey junk, repair with own money, vendor summary,
  mail take-all controls. Auto stand ships as unavailable, see below.
- Auto stand is permanently unavailable on Retail: standing is a protected action.
- `/refactor`, `/rf` when unclaimed, and `/refactor errors`.
- Nameplate quest progress: a ring that fills round as the objective advances, with a skull
  for kill objectives and a bag for item objectives, cached by NPC id, deferring entirely to
  Questie and Plater. Reads your own progress only.
- First-run preset picker: Minimal, Standard, Full, or browse. Writes account defaults, so
  every later character inherits the choice with no clicks.
- Automation features are their own category, are in no preset, and need a one-time
  confirmation dialog naming the pause modifier before they can be switched on.
- Profiles panel: create from what this character uses, assign, delete, import and export
  as a string.
- Conflicts panel: names an installed neighbour, the feature it overlaps, and offers to
  switch Refactor's version off. Refactor never touches the other addon.
- Diagnostics panel: every module with its state and reason, error count, and a config
  string to paste when reporting something.
- `LibRefactorPrice-1.0` in tree, vendor sell price only. Auction providers are opt-in and
  label their source.
- Nameplate count animates only the number that changed, eased in and out, no overshoot.
- Objective icons corrected: crossed swords for kill objectives, a bag for item objectives.
  Atlas names now match the client's own spelling, which is case sensitive for SetAtlas.
- On/off settings are checkboxes.
- Minimap button uses Blizzard's addon button ring and sits clear of the minimap rim at any
  minimap size.
- Diagnostics lists any art this client did not recognise.
- Minimap button with the Refactor icon: left click opens the window, right click prints
  recorded errors, drag to move. Hideable from the options page.
