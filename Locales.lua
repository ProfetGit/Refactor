-- Refactor Addon - Localization
-- English (Default)

local addonName, addon = ...

addon.L = {
    -- General
    ADDON_NAME = "Refactor",
    ADDON_DESCRIPTION = "Quality of life automation for World of Warcraft",

    -- Slash Commands
    SLASH_HELP = "Usage: /refactor or /rf [command]",
    SLASH_HELP_ENABLE = "  enable <module> - Enable a module",
    SLASH_HELP_DISABLE = "  disable <module> - Disable a module",
    SLASH_HELP_STATUS = "  status - Show module status",
    SLASH_INVALID_MODULE = "Invalid module name: %s",
    SLASH_ENABLED = "%s has been enabled.",
    SLASH_DISABLED = "%s has been disabled.",

    -- Module Names
    MODULE_AUTO_SELL = "Auto-Sell Junk",
    MODULE_AUTO_REPAIR = "Auto-Repair",
    MODULE_AUTO_QUEST = "Auto-Quest",
    MODULE_FAST_LOOT = "Fast Loot",
    MODULE_SKIP_CINEMATICS = "Skip Cinematics",
    MODULE_TOOLTIP_PLUS = "Tooltip Plus",
    MODULE_AUTO_CONFIRM = "Auto-Confirm",
    MODULE_AUTO_INVITE = "Auto-Invite",
    MODULE_AUTO_RELEASE = "Auto-Release",
    MODULE_QUEST_NAMEPLATES = "Quest Nameplates",
    MODULE_LOOT_TOAST = "Loot Toast",
    MODULE_ACTIONCAM = "Action Cam",
    MODULE_COMBAT_FADE = "Combat Fade",

    -- Combat Fade Labels
    TIP_COMBAT_FADE = "Hide UI elements when not in combat. Elements reveal on mouseover or when entering combat.",
    COMBAT_FADE_ACTION_BARS = "Hide Action Bars",
    TIP_COMBAT_FADE_ACTION_BARS = "Fade out action bars when out of combat.",
    COMBAT_FADE_ACTION_BARS_OPACITY = "Action Bars Opacity",
    TIP_COMBAT_FADE_ACTION_BARS_OPACITY = "How visible action bars are when hidden (0 = invisible, 100 = fully visible).",
    COMBAT_FADE_PLAYER_FRAME = "Hide Player Frame",
    TIP_COMBAT_FADE_PLAYER_FRAME = "Fade out the player frame when out of combat.",
    COMBAT_FADE_PLAYER_FRAME_OPACITY = "Player Frame Opacity",
    TIP_COMBAT_FADE_PLAYER_FRAME_OPACITY =
    "How visible the player frame is when hidden (0 = invisible, 100 = fully visible).",

    -- Speed Display Labels
    MODULE_SPEED_DISPLAY = "Speed Display",
    SPEED_DECIMALS = "Show Decimals",
    TIP_SPEED_DISPLAY = "Display your current movement speed as a percentage near the player frame.",
    TIP_SPEED_DECIMALS = "Show speed with one decimal place (e.g., 100.5% instead of 101%).",

    -- Auto-Sell
    SOLD_JUNK = "Sold %d item(s) for %s",
    NO_JUNK = "No junk items to sell.",
    SELL_LOW_ILVL = "Sell Old Soulbound Gear",
    SELL_KNOWN_TRANSMOG = "Sell Collected Transmogs",
    KEEP_TRANSMOG = "Keep Uncollected Appearances",
    MAX_ILVL_TO_SELL = "Max iLvl to Sell",

    -- Auto-Sell Tooltips
    TIP_SELL_NOTIFY = "Show a chat message when items are sold, including total gold earned.",
    TIP_SELL_KNOWN_TRANSMOG =
    "Sell soulbound equipment if you already have that appearance in your collection. Great for clearing old gear!",
    TIP_KEEP_TRANSMOG = "Never sell soulbound equipment if you haven't collected the appearance yet. Fashion first!",
    TIP_SELL_LOW_ILVL =
    "Sell soulbound equipment below the max iLvl threshold. Only works on SOULBOUND items - BoE items are NEVER sold.",
    TIP_MAX_ILVL =
    "Items with item level BELOW this value will be considered for selling. Items at or above this level are always kept. The addon also protects items equal to or higher than your lowest equipped piece.",

    -- Auto-Repair
    REPAIRED_GUILD = "Repaired for %s using guild funds.",
    REPAIRED_SELF = "Repaired for %s.",
    REPAIR_FAILED = "Not enough gold to repair (%s needed).",
    REPAIR_GUILD_FAILED = "Cannot use guild funds for repair.",
    NO_REPAIR_NEEDED = "No repairs needed.",

    -- Auto-Repair Tooltips
    TIP_USE_GUILD_FUNDS =
    "Attempt to use guild bank funds for repairs first. Falls back to personal gold if unavailable or insufficient.",
    TIP_REPAIR_NOTIFY = "Show a chat message when gear is repaired, including the cost.",

    -- Auto-Quest
    QUEST_ACCEPTED = "Accepted quest: %s",
    QUEST_TURNED_IN = "Turned in quest: %s",
    QUEST_HOLD_MODIFIER = "Hold %s to read quest text.",

    -- Auto-Quest Tooltips
    TIP_AUTO_ACCEPT = "Automatically accept quests from NPCs. Works with most quest givers.",
    TIP_AUTO_TURNIN = "Automatically turn in completed quests and select rewards.",
    TIP_SKIP_GOSSIP = "Skip NPC gossip dialogue and go straight to quest options.",
    TIP_AUTO_SINGLE_OPTION = "Automatically select the dialogue option when an NPC has only one choice.",
    TIP_AUTO_CONTINUE_DIALOGUE = "Automatically click 'Continue' and similar dialogue progression options.",
    TIP_DAILY_ONLY = "Only auto-accept daily and repeatable quests. Regular quests will require manual acceptance.",
    TIP_QUEST_MODIFIER = "Hold this key to pause automation and read quest text manually.",

    -- Skip Cinematics
    CINEMATIC_SKIPPED = "Skipped cinematic (seen before).",
    CINEMATIC_FIRST_TIME = "First time viewing - will skip next time.",

    -- Skip Cinematics Tooltips
    TIP_ALWAYS_SKIP = "Skip ALL cinematics immediately, even ones you haven't seen before.",
    TIP_SKIP_MODIFIER = "Hold this key to watch the cinematic instead of skipping.",

    -- Auto-Confirm
    CONFIRM_READY_CHECK = "Ready Checks",
    CONFIRM_SUMMON = "Summons",
    CONFIRM_ROLE_CHECK = "Role Checks",
    CONFIRM_RESURRECT = "Resurrections",
    CONFIRM_BINDING = "BoP/BoE Dialogs",

    -- Auto-Confirm Tooltips
    TIP_READY_CHECK = "Automatically confirm ready checks in dungeons and raids.",
    TIP_SUMMON = "Automatically accept warlock summons and meeting stones.",
    TIP_ROLE_CHECK = "Automatically confirm your role (tank/healer/DPS) when prompted.",
    TIP_RESURRECT = "Automatically accept resurrection spells from other players.",
    TIP_BINDING = "Automatically confirm 'Bind on Equip' and 'Bind on Pickup' dialogs.",

    -- Auto-Invite
    INVITE_FRIENDS = "Accept from Friends",
    INVITE_BNET = "Accept from BNet Friends",
    INVITE_GUILD = "Accept from Guild",
    INVITE_GUILD_INVITES = "Accept Guild Invites",

    -- Auto-Invite Tooltips
    TIP_INVITE_FRIENDS = "Automatically accept party invites from your in-game friends list.",
    TIP_INVITE_BNET = "Automatically accept party invites from your Battle.net friends.",
    TIP_INVITE_GUILD = "Automatically accept party invites from guild members.",
    TIP_GUILD_INVITES = "Automatically accept guild invites (joining a new guild).",

    -- Auto-Release
    RELEASE_MODE = "Release Mode",
    RELEASE_ALWAYS = "Always",
    RELEASE_PVP = "PvP Only",
    RELEASE_PVE = "Dungeons/Raids Only",
    RELEASE_OPENWORLD = "Open World Only",
    RELEASE_DELAY = "Delay (seconds)",

    -- Auto-Release Tooltips
    TIP_RELEASE_MODE = "Choose when to automatically release your spirit after death.",
    TIP_RELEASE_NOTIFY = "Show a chat message when auto-releasing.",

    -- ActionCam
    ACTIONCAM_MODE = "Camera Mode",
    ACTIONCAM_BASIC = "Basic",
    ACTIONCAM_FULL = "Full",
    ACTIONCAM_DEFAULT = "Default",

    -- ActionCam Tooltips
    TIP_ACTIONCAM = "Automatically enable ActionCam modes (Motion sickness warning for 'Full' mode).",
    TIP_ACTIONCAM_MODE = "Select which ActionCam mode to enforce on login/reload.",

    -- Settings UI
    SETTINGS_TITLE = "Refactor Settings",
    SETTINGS_GENERAL = "General",
    SETTINGS_AUTOMATION = "Automation",
    SETTINGS_VENDOR = "Vendor",
    SETTINGS_LOOT = "Loot",
    SETTINGS_QUESTS = "Quests",
    SETTINGS_CINEMATICS = "Cinematics",
    SETTINGS_TOOLTIP = "Tooltip",
    SETTINGS_NAMEPLATES = "Nameplates",

    -- Quest Nameplates Labels
    SHOW_KILL_ICON = "Show Kill Objective Icon",
    SHOW_LOOT_ICON = "Show Loot/Interact Icon",
    TIP_QUEST_NAMEPLATES = "Display quest progress icons and text on nameplates of mobs needed for your active quests.",

    -- Loot Toast Labels
    LOOT_TOAST_DURATION = "Toast Duration",
    LOOT_TOAST_MAX_VISIBLE = "Max Visible Toasts",
    LOOT_TOAST_SHOW_CURRENCY = "Show Currency",
    LOOT_TOAST_SHOW_QUANTITY = "Show Item Quantity",
    TIP_LOOT_TOAST = "Display looted items in elegant popup notifications on the bottom-left of the screen.",
    TIP_LOOT_TOAST_DURATION = "How long each toast stays visible before fading out (in seconds).",
    TIP_LOOT_TOAST_MAX = "Maximum number of toasts visible at once. Older ones fade out first.",
    TIP_LOOT_TOAST_CURRENCY = "Show currency (gold, silver, copper) in the toast feed.",
    TIP_LOOT_TOAST_QUANTITY = "Display the quantity next to items when looting multiple.",
    LOOT_TOAST_MIN_QUALITY = "Minimum Quality",
    TIP_LOOT_TOAST_MIN_QUALITY =
    "Only show items at or above this quality level. Currency always respects the 'Show Currency' setting.",
    LOOT_TOAST_ALWAYS_SHOW_UNCOLLECTED = "Always Show Uncollected Transmog",
    TIP_LOOT_TOAST_ALWAYS_SHOW_UNCOLLECTED =
    "Always show items with uncollected transmog appearances, even if they're below the minimum quality threshold.",

    -- Loot Quality Levels
    QUALITY_ALL = "Show All",
    QUALITY_COMMON = "Common+",
    QUALITY_UNCOMMON = "Uncommon+",
    QUALITY_RARE = "Rare+",
    QUALITY_EPIC = "Epic+",
    QUALITY_LEGENDARY = "Legendary+",

    -- Settings Labels
    ENABLE = "Enable",
    DISABLE = "Disable",
    SHOW_NOTIFICATIONS = "Show Chat Notifications",
    USE_GUILD_FUNDS = "Use Guild Funds First",
    AUTO_ACCEPT = "Auto-Accept Quests",
    AUTO_TURNIN = "Auto Turn-in Quests",
    SKIP_GOSSIP = "Skip Gossip Dialogue",
    AUTO_SINGLE_OPTION = "Auto-Select Single Option",
    AUTO_CONTINUE_DIALOGUE = "Auto-Continue Dialogue",
    DAILY_QUESTS_ONLY = "Daily/Repeatable Quests Only",
    MODIFIER_KEY = "Hold Modifier to Pause",
    SKIP_SEEN_ONLY = "Skip Previously Seen Only",
    ALWAYS_SKIP = "Always Skip All",

    -- Tooltip Plus Labels
    TOOLTIP_ANCHOR = "Tooltip Position",
    TOOLTIP_MOUSE_SIDE = "Mouse Anchor Side",
    TOOLTIP_MOUSE_OFFSET = "Mouse Offset Distance",
    TOOLTIP_SCALE = "Tooltip Scale",
    TOOLTIP_HIDE_HEALTHBAR = "Hide Healthbar",
    TOOLTIP_HIDE_GUILD = "Hide Guild Name",
    TOOLTIP_HIDE_FACTION = "Hide Faction",
    TOOLTIP_HIDE_PVP = "Hide PvP Status",
    TOOLTIP_HIDE_REALM = "Hide Realm Name",
    TOOLTIP_CLASS_COLORS = "Class-Colored Borders",
    TOOLTIP_RARITY_BORDER = "Item Rarity Borders",
    TOOLTIP_COMPACT = "Compact Mode",
    TOOLTIP_SHOW_ITEM_ID = "Show Item IDs",
    TOOLTIP_SHOW_SPELL_ID = "Show Spell IDs",
    TOOLTIP_SHOW_TRANSMOG = "Show Transmog Status",
    TOOLTIP_TRANSMOG_OVERLAY = "Show Transmog Icon on Items",
    TOOLTIP_TRANSMOG_CORNER = "Icon Corner",
    TOOLTIP_TRANSMOG_SHOW_COLLECTED = "Show Collected Icon",
    TOOLTIP_TRANSMOG_SHOW_NOT_COLLECTED = "Show Not Collected Icon",

    -- Transmog Overlay Tooltips
    TIP_TRANSMOG_OVERLAY =
    "Display a small icon on item buttons in bags and vendors showing if the appearance is collected.",
    TIP_TRANSMOG_CORNER = "Which corner of the item icon to display the transmog status indicator.",
    TIP_TRANSMOG_COLLECTED = "Show a green checkmark on items with appearances you've already collected.",
    TIP_TRANSMOG_NOT_COLLECTED = "Show an orange X on items with appearances you haven't collected yet.",

    -- Anchor Positions
    ANCHOR_DEFAULT = "Default",
    ANCHOR_MOUSE = "Follow Mouse",
    ANCHOR_TOPLEFT = "Top Left",
    ANCHOR_TOPRIGHT = "Top Right",
    ANCHOR_BOTTOMLEFT = "Bottom Left",
    ANCHOR_BOTTOMRIGHT = "Bottom Right",

    -- Mouse Sides
    SIDE_RIGHT = "Right",
    SIDE_LEFT = "Left",
    SIDE_TOP = "Top",
    SIDE_BOTTOM = "Bottom",

    -- Modifier Keys
    MODIFIER_SHIFT = "Shift",
    MODIFIER_CTRL = "Ctrl",
    MODIFIER_ALT = "Alt",
    MODIFIER_NONE = "None",
}

-- Future: Add other locales here
-- if GetLocale() == "deDE" then ... end
