# Changelog

## Unreleased

M4 (18 Sep 2026), built against Retail 12.1.0, none of it verified in game yet:

- Forever saved variables: the beta client (1.60.1.69913) writes SavedVariables and never
  reads them back, so settings died on every reload. Refactor loads the last session from
  `Restore.lua` in its own folder when the client hands back nothing, and says at login when
  the client starts working again and the workaround can go. Temporary, with the removal
  list under Temporary workarounds in `docs/ROADMAP.md`.
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
  and stance bars, player and target frames, experience bars, micro menu, bags bar, quest
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
  hidden. The panel lists every element as a checkbox with a per-kind tick-all; one editor
  writes to every ticked element at once.
- Interface: maximum camera distance, ActionCam through its three CVars, screenshot on
  level up. Mail: remember last recipient per character.
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
