# Changelog

## 0.1.0

The first release, made for WoW Forever. Type /refactor to open it. Everything is one list
you can search, and a new character starts with the settings your others already use.

### Quest

- Accept quests as they open and hand them in when there is nothing to choose. An NPC with
  several quests is worked through one at a time.
- Auto gossip picks the obvious option at an NPC, and learns the ones you teach it with a
  Shift click.
- Quest progress on nameplates: how many more of a mob you need, right on its nameplate.

### Loot

- Fast loot, and a loot feed that shows each drop with its icon, count and price.
- A farm session HUD with gold per hour, your best drop, and a summary you can copy.

### Vendor

- Sell junk and repair on arrival, with one line of what it came to when you leave. Drag an
  item onto the never-sell slot to keep it off the list for good.
- A bigger merchant window, costs that grey out only what you are short of, and a filter
  for mounts, pets, toys, appearances and recipes you have or are missing.

### Interface

- Zoom the camera further out, and ActionCam profiles that follow you indoors, onto a mount,
  into combat and into dungeons. Customize any profile and share it as a string.
- Zone level ranges on the world map, and the parts of each map you have not explored yet.
- UI visibility fades bars, frames, chat and the minimap until you need them, tuned element
  by element in Edit Mode.
- New abilities go straight onto a free action bar slot, and a screenshot is taken when you
  level up.

### Chat and social

- Web addresses in chat become links you can copy, and every chat window gets a Copy button.
- Decline duels, accept resurrections and invites from friends, and invite a player with a
  modifier click.
- A notice when someone in your guild or group runs a newer Refactor.

### Tooltips

- Tooltip borders in the item's quality or the player's class colour, no health bar under
  unit tooltips, and tooltips at the cursor or a fixed point.

### Everywhere

- Account defaults, profiles and per-character settings, with one switch at the top of the
  list that says which of them your clicks change.
- Refactor steps aside when another addon already does the same job, and says so under
  Conflicts.
- Diagnostics shows what every feature is doing and why, and /refactor errors lists anything
  that went wrong.

## Development notes

Launch fixes (5 Nov 2026), checked headless, not yet in game:

- An upgrade opens a prompt at the top centre of the screen instead of putting an Equip
  button on the loot row: the item, how much better it is and what it replaces, then Equip
  or Not now. Several upgrades are asked about one at a time. Equip is greyed out in combat,
  and the prompt closes on its own if the item is equipped another way.
- Nameplate quest progress works in a group. Forever's tooltip heads your own progress with
  your name and surname, which was never recognised as yours, so the plate stayed blank on
  every quest a party member shared. Your lines are now known by your quest log's own text
  first and by your full name second, and a quest only a party member has never shows.
- A nameplate that cannot be read costs that plate only. Before, one error switched quest
  progress off on every plate until the feature was toggled; the first such error now shows
  in /refactor errors. A plate with no readable GUID is still resolved, just not cached.
- A mob you already finished is dimmed without its checkmark flashing again on every loot.
  The checkmark plays once, for the kill that finished it.
- Nameplate settings apply to the plates already on screen. The Progress ring checkbox is
  gone: the ring itself was removed earlier and the box did nothing.

Polish pass (25 Sep 2026), checked headless and in the layout preview, not yet in game:

- Feature rows carry their one-line description under the name (PRD 8.2); the hover tooltip
  holds the long detail and opens beside the window instead of over the sidebar. Section
  headings count what is on. The sidebar foot shows the icon and version and opens What's new.
- The Editing switch heads the list. With a profile assigned it offers that profile as a layer,
  since the account layer no longer reaches the character; assigning a profile points the
  switch at it. Undo says what it goes back to.
- Settings blocks are laid out top down by the block itself and every note is measured, so no
  help text is cut off at a fixed height. Block contents line up with the row's name.
- Never sell is an item list: drop an item on the slot or type an ID or link; icons with
  quality borders, right click to remove.
- ActionCam: Customize copies a built-in profile under the player's name in one click.
- Profiles page: what this character uses on top, saved profiles with their counts, save this
  setup, share. Delete asks twice. Conflicts lists every neighbour it checks for, and a feature
  that is on beside a neighbour doing the same job says so on its row.
- Diagnostics has a summary line, state dots and the full reason on hover. The minimap
  button's right click opens Diagnostics, and a broker launcher registers when LDB is loaded.
- `/refactor <words>` opens the window searching for them; search reads the detail text too
  and counts its results. A first install prints one line saying where Refactor lives.
- The farm HUD menu runs on Blizzard_Menu instead of UIDropDownMenu, whose shared state
  addons are known to taint. The session summary and copy box wear Refactor's own window.
- The loot feed and nameplate quest progress list under Loot and Quest. Loot toasts are the
  Loot feed; a vendor price no longer carries "(vendor)". The vendor summary uses the
  client's coins and says only what happened.
- What's new shows this player-facing changelog; these notes stay out of the game.
- Section headings start with a copper diamond (new art, Media/Diamond.tga, loads on a full
  restart). Enter saves a typed field. The loot feed's Edit Mode dialog links to the rest of
  its settings. The Edit Mode visibility note and the session summary header are measured,
  so neither cuts its last line.
- `Tools/Preview` renders the real UI headless to HTML and PNG for layout review.

M4 (18 Sep 2026), built against Retail 12.1.0, none of it verified in game yet:

- Presets and the first-run screen are gone. Each feature has its own default instead:
  information and click savers start on (sell junk, auto repair, merchant window, chat links,
  rarity border, nameplate quest progress and a few more), anything that acts for you or
  changes the camera or screen starts off. Automation features turn on with one click, with no
  confirmation dialog.
- `/refactor saved` reports whether the client restored the saved variables, from a probe
  taken before any of our code runs.
- Settings: the Editing switch opens on Account defaults and keeps whichever layer you
  last chose for that character. Editing the account layer now drops that character's own
  setting for the feature, so the click takes effect instead of writing behind an override
  that still wins; a feature the character has pinned says so on its row while the account
  layer is on screen.
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
  denominations that are zero: a grey reads "8c" with a copper coin, not "0g 0s 8c". The
  coins are drawn as part of the row, so they stay with it while the feed slides or is
  dragged instead of trailing behind. The farm HUD's details panel draws its coins the same
  way, and the best drop's value now sits flush right like the top items below it.
- Right click a loot feed row to dismiss it; the rows below slide up. On a group it takes
  the whole group. Left click stays reserved for Gear Refactor.
- With Gear Refactor installed, loot feed rows carry its upgrade badge. A group's row shows
  the best upgrade inside it, so a collapsed loot never hides one. Gear Refactor's own popup
  stays off while the feed is on, as before.
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
  optional items-only) and auto turn in when there is nothing to choose. A lone reward is
  taken the way Blizzard's Complete button takes it, and a quest that costs gold is left for
  you to confirm.
- Auto gossip: Shift click an option at an NPC and it is picked there from then on; an
  NPC's only quest or a finished hand-in is opened; the one shop, trainer, flight, bank,
  auction or transmog option is opened when the rest is small talk; a lone unflagged line
  of dialogue can be skipped (off by default). Nothing that costs, casts, rewards or starts
  a quest is picked, inside instances only remembered choices apply, a menu that loops back
  on itself stops, and the pause modifier keeps the frame. Learn modifier and a forget
  button under Display options.
- Chat and social: clickable web addresses with a copy box; auto decline duels; auto
  accept resurrection out of combat. Auto accept party invites is written but ships
  unavailable until AcceptGroup is confirmed callable from an addon.
- Quick invite: hold a modifier, Alt unless changed, and click a player to invite them to
  your party with no menu. The client gives addons no click on the 3D world, so the module
  reads the selection the click causes and only acts when the new target is the unit under
  the cursor. That is what keeps tab targeting from inviting anyone; it also means the
  mouse button cannot be told apart, so either one sends it, and clicking someone already
  selected sends nothing. Off by default, in no preset, and behind the automation
  confirmation. `/refactor invitetest` reports what the last modified click looked like.
- ActionCam profiles: Blizzard's Basic, On and Full run through the console command that
  defines them; Refactor's Immersive (close, over the shoulder, tilting as it comes in, a
  faint head sway, tuned for mouse and keyboard), Controller: Ranged and Controller: Melee
  (a gentle or a strong pull toward the target, no sway, wide or close), Cinematic (far and centred, for the story), Raider (far
  everywhere, nothing moves on its own), Melee (close, hard over the shoulder, target
  focus) and Comfort (Immersive's distances with tilt, sway and focus off). Refactor's
  profiles move and recentre the camera
  for where you are: indoors, in a city or inn, on a mount, in combat, talking to an NPC,
  or in a dungeon or delve, raid, battleground or arena. Every distance is absolute, in
  yards from the character, so a close camera walking into a building never ends up in
  first person, and a situation's distance can be "stays where you had it". Entering a
  situation remembers where the wheel had the camera and leaving gives it back, so a
  mount backs off and a dismount returns exactly to where you were. Melee moves the
  camera only for a mount and a raid. Save a copy of any profile and tune it on sliders;
  export and import a
  profile as a string. The Keep Character Centered accessibility option, which overrides
  ActionCam, is off while a profile is on and back at its default when the feature is off.
- UI visibility: chat windows, tabs, buttons and input box art, the eight action bars, pet
  and stance bars, player, target, party and raid frames, experience bars, micro menu, bags bar, quest
  list, minimap and its buttons can be
  visible, visible on mouseover, or hidden, with conditions that always show or always hide
  a group (combat, mounted, resting, target, group, instance, stealth, dead) and a fade time
  each way. Presets: Full immersion, Show in combat only, Clean when mounted, Off. Alpha
  only, so keybinds and clicks keep working on an invisible bar. Chat hover rides Blizzard's
  own chat fade; typing keeps the window shown; Edit Mode shows everything. Stands down
  behind ElvUI, and per bar group behind Bartender4 or Dominos. `Core/Conditions.lua` is a
  shared player state service and `Core/Fade.lua` the one OnUpdate driver. The minimap's
  quest areas can follow it (opt-in, the game exposes no way to read their defaults); the
  player arrow cannot be faded on this client. Each element has an opacity for shown and for
  hidden. Elements are tuned in Edit Mode: select one and Refactor's settings for it open
  beside Blizzard's dialog, with the element previewing its shown opacity; "same for all"
  pushes a rule to the whole kind. Refactor's window keeps the preset. Hover comes from the
  tooltip an element shows, so no secure button is ever hooked; leaving is watched, not
  trusted to an event; elements in the same zone reveal together; a spell on the cursor
  shows everything. A frame that takes no mouse gets no hook, so an overlay never swallows
  the hover and tooltip of what sits under it.
- Interface: maximum camera distance, ActionCam through its three CVars, screenshot on
  level up. Mail: remember last recipient per character.
- Zone levels on the map: hover a zone on a continent map and its level range appears beside
  the name in the quest difficulty colour. Forever's map draws the name alone and returns no
  level data, so the ranges come from Refactor's own table, keyed by the name the label shows:
  the original zones, Riverglades and Zephras Isle. Mount Hyjal and Shen'dralas wait for a
  published range. Where the client answers, as Retail does, nothing of ours draws.
- Reveal the map: the parts of a map you have not explored are drawn too, grey and dimmer,
  under the client's own explored areas, so a zone's shape and what is left to explore show
  at a glance. The art comes from Blizzard's overlay tables for one client build through
  `Tools/map-overlays.py`; on another build the feature stays unavailable.
- Update notice: guild and group members swap Refactor version numbers on the addon channel,
  and a newer one in your guild or group is announced once per session in chat, with
  `/refactor update` to ask again. Nothing is downloaded and nothing is looked up online.
- What's new: the changelog in the window, under Tools, and at `/refactor changelog`. The
  page is generated from CHANGELOG.md by `make changelog`, and the checks fail while it is
  behind, so the two cannot drift.
- Price providers: TradeSkillMaster (custom price string) and Auctionator, opt-in under
  Display options, labelled wherever a price is shown.
- `/refactor bench`: load time, memory, garbage rate, CPU per frame when scriptProfile is
  on, handler counts, and OnUpdate handlers on Refactor's frames.
- Display options panel. Diagnostics list scrolls. Window categories: Quest, Chat, Social,
  Tooltips, Toasts, Display.
- `GetCameraZoom` enters the API index through `Data/client-api.json`: a global the client
  exports but no Blizzard UI file calls, verified against the client index at this build.
- Not built because Retail does it natively: bag quality borders, auto track quests, chat
  timestamps, sell-all-junk, the client's own flagged single-option gossip skip.

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
- Automation features list under their own category (Quest, Social), are in no preset,
  and need a one-time confirmation dialog naming the pause modifier before they can be
  switched on.
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
