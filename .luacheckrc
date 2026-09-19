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
    "GetQuestReward", "CompleteQuest", "IsQuestCompletable", "GetNumQuestChoices", "QuestGetAutoAccept",
    "QuestFlagsPVP", "GetQuestID", "QuestIsFromAdventureMap", "GetNumAvailableQuests", "GetAvailableQuestInfo",
    "SelectAvailableQuest", "CancelDuel", "AcceptGroup", "AcceptResurrect", "StaticPopup_Hide", "ConsoleExec", "EventRegistry", "NineSliceUtil",
    "IsGuildMember", "ChatFrameUtil", "SetItemRef", "SendMailNameEditBox", "SendMailFrame", "Screenshot",
    "GetFramerate", "GetAddOnCPUUsage", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "GetTimePreciseSec",
    -- Blizzard_SharedXML/Mainline/UIDropDownMenu.lua, loaded by Blizzard_SharedXML.toc at
    -- the installed build. Used by the farm HUD's right click menu only.
    "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton",
    "ToggleDropDownMenu", "CloseDropDownMenus",
}

files["Tests/"] = { std = "+busted" }
files["Tools/"] = { max_line_length = 160 }
