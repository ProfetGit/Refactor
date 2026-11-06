-- Lint noise control only. This whitelist is not evidence that a symbol exists:
-- Tools/api-check.lua verifies every declared dependency against Data/api-retail.json.
std = "lua51"
self = false
max_line_length = 120
exclude_files = { ".tools", ".release" }

read_globals = {
    -- Addon loading and libraries
    "LibStub",
    -- Frames and widgets
    "CreateFrame", "CreateColor", "UIParent", "UISpecialFrames", "DEFAULT_CHAT_FRAME", "Minimap", "GameTooltip",
    "GetCursorPosition", "GetPhysicalScreenSize",
    -- Blizzard's merchant window, reshaped by vendor.extendedUI
    "MerchantMoneyInset", "MerchantMoneyBg",
    "MerchantFrame_UpdateItemQualityBorders", "MerchantFrame_UpdateAltCurrency", "MerchantFrameItem_UpdateQuality", "MERCHANT_PAGE_NUMBER", "MerchantPrevPageButton", "MerchantPageText", "TEXTURE_ITEM_QUEST_BANG", "GetMerchantItemID", "CurrencyContainerUtil", "C_Heirloom", "SetItemButtonCount", "SetItemButtonStock", "SetItemButtonTexture", "SetItemButtonDesaturated", "SetItemButtonNameFrameVertexColor", "SetItemButtonSlotVertexColor", "SetItemButtonTextureVertexColor", "SetItemButtonNormalTextureVertexColor",
    "PlayerHasToy", "ITEM_SPELL_KNOWN", "C_MountJournal", "C_PetJournal", "C_ToyBox", "C_TransmogCollection",
    "MAX_MERCHANT_CURRENCIES", "MerchantFrame_UpdateCurrencies", "MerchantMoneyFrame", "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg",
    "CanAffordMerchantItem", "GetMerchantItemCostInfo", "GetMerchantItemCostItem", "MAX_ITEM_COST", "AltCurrencyFrame_Update", "SetMoneyFrameColor", "MoneyFrame_SetMaxDisplayWidth", "MoneyFrame_Update",
    "MerchantBuyBackItem", "MerchantNextPageButton", "MerchantFrameBottomLeftBorder", "MerchantFrame_Update", "MERCHANT_ITEMS_PER_PAGE", "BUYBACK_ITEMS_PER_PAGE",
    -- Slash command registration
    "SlashCmdList",
    -- Blizzard settings panel namespace
    "Settings",
    -- Core client API
    "C_AddOns", "C_CVar", "C_Container", "C_GossipInfo", "C_Item", "C_Mail", "C_NamePlate", "C_QuestLog",
    "C_Texture", "C_Timer", "C_TooltipInfo",
    "Enum", "GetBuildInfo", "GetTime", "UnitGUID", "debugstack",
    -- Retail 12's secret values: a nameplate's GUID while unit identity is restricted
    "issecretvalue",
    -- Input and combat state
    "InCombatLockdown", "IsAltKeyDown", "IsControlKeyDown", "IsInInstance", "IsModifiedClick", "IsShiftKeyDown",
    -- Loot
    "GetLootSlotInfo", "GetNumLootItems", "LootSlot",
    -- Vendor and money
    "CanMerchantRepair", "GetMoney", "GetRepairAllCost", "MerchantFrame", "RepairAllItems",
    -- Mail
    "ATTACHMENTS_MAX", "GetInboxHeaderInfo", "GetInboxNumItems", "HasInboxItem",
    "TakeInboxItem", "TakeInboxMoney",
    -- Items
    "DELETE_ITEM_CONFIRM_STRING", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "StaticPopup_FindVisible",
    -- M4: tooltips, toasts, quest, social, merchant, bench
    "hooksecurefunc", "GossipOptionButtonMixin", "TooltipDataProcessor", "TooltipUtil", "SetTooltipMoney", "GameTooltip_SetDefaultAnchor",
    "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "C_CurrencyInfo", "C_MerchantFrame",
    "C_FriendList", "C_BattleNet", "GetMerchantNumItems", "GetMerchantItemLink", "GetMerchantItemMaxStack",
    "BuyMerchantItem", "GetNumBuybackItems", "GetBuybackItemInfo", "BuybackItem", "AcceptQuest",
    "GetQuestReward", "CompleteQuest", "IsQuestCompletable", "GetNumQuestChoices", "GetQuestMoneyToGet",
    "QuestGetAutoAccept",
    "QuestFlagsPVP", "GetQuestID", "QuestIsFromAdventureMap", "GetNumAvailableQuests", "GetAvailableQuestInfo",
    "SelectAvailableQuest", "CancelDuel", "AcceptGroup", "AcceptResurrect", "StaticPopup_Hide", "ConsoleExec", "EventRegistry", "NineSliceUtil",
    "IsGuildMember", "ChatFrameUtil", "SetItemRef", "SendMailNameEditBox", "SendMailFrame", "Screenshot",
    "GetFramerate", "GetAddOnCPUUsage", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "GetTimePreciseSec",
    -- Blizzard_Menu's context menu, the farm HUD's right click menu.
    "MenuUtil",
    -- Quick invite: the unit tests Blizzard's own invite entry uses, and the invite itself
    "C_PartyInfo", "UnitExists", "UnitIsUnit", "UnitIsPlayer", "UnitIsHumanPlayer", "UnitIsConnected",
    "UnitCanCooperate", "UnitInParty", "UnitInRaid", "UnitName",
    -- Update notice: guild and group membership, and the addon message channel
    "C_ChatInfo", "IsInGuild", "IsInGroup", "IsInRaid", "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE",
    -- Class coloured tooltip border
    "UnitClassBase", "UnitClass", "C_ClassColor",
    -- Placing a newly learned ability: the spellbook queries, the cursor and the action slots
    "C_Spell", "C_SpellBook", "C_ActionBar", "GetCursorInfo", "ClearCursor",
    -- ActionCam profiles: situation queries and the two camera zoom calls
    "IsIndoors", "IsResting", "IsMounted", "UnitOnTaxi", "UnitInVehicle", "IsPlayerInWorld",
    "CameraZoomIn", "CameraZoomOut", "GetCameraZoom", "GetShapeshiftFormID",
    -- Zone levels on the map: Blizzard's map frame, the label it hooks and the difficulty colour
    "WorldMapFrame", "C_Map", "UnitLevel", "GetQuestDifficultyColor",
    -- Bag upgrade: the bag slots, the cursor and the windows where a right-click on a bag means something else
    "NUM_BAG_SLOTS", "GetInventoryItemID", "CursorHasItem", "PutItemInBag", "CONTAINER_SLOTS",
    "BankFrame", "MailFrame", "TradeFrame",
    -- Send to alts: the send tab's attachments and money field, the realm, and crafting professions
    "ATTACHMENTS_MAX_SEND", "HasSendMailItem", "GetSendMailItem", "GetSendMailItemLink", "GetSendMailPrice",
    "ClickSendMailItemButton", "MoneyInputFrame_SetCopper", "SendMailMoney", "GetRealmName",
    "GetProfessions", "GetProfessionInfo", "C_TradeSkillUI",
}

files["Tests/"] = { std = "+busted" }
files["Tools/"] = { max_line_length = 160 }
-- The Probe is its own dev addon, so its saved variables and slash command are its globals.
files["Tools/Probe/"] = {
    max_line_length = 160,
    globals = { "RefactorProbeDB", "SLASH_REFACTORPROBE1" },
    read_globals = { "CreateFont", "ConsoleGetAllCommands", "GetLocale", "GetServerTime", "debugprofilestop", "print" },
}
