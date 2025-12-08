-- Refactor Addon - Chat Plus Module
-- Wowhead lookup on chat links, clickable URLs, copy chat

local addonName, addon = ...
local L = addon.L

local ChatPlus = {}
addon.Modules.ChatPlus = ChatPlus

----------------------------------------------
-- Performance: Cache globals
----------------------------------------------
local pairs, ipairs = pairs, ipairs
local string_match, string_gsub, string_lower, string_sub = string.match, string.gsub, string.lower, string.sub
local table_insert, table_concat = table.insert, table.concat
local IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown = IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown
local C_Item_GetItemNameByID = C_Item.GetItemNameByID
local C_Spell_GetSpellName = C_Spell.GetSpellName
local C_QuestLog_GetTitleForQuestID = C_QuestLog.GetTitleForQuestID
local C_CurrencyInfo_GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo

----------------------------------------------
-- Constants
----------------------------------------------
local URL_PATTERNS = {
    "https?://[%w_%-%.%/%?%%=&#:~]+",
    "www%.[%w_%-%.%/%?%%=&#:~]+",
}

local WOWHEAD_BASE = "https://www.wowhead.com/"

----------------------------------------------
-- Cached Settings (updated on setting change)
----------------------------------------------
local cachedEnabled = false
local cachedClickableURLs = false
local cachedWowheadLookup = false
local cachedCopyButton = false

local function UpdateCachedSettings()
    cachedEnabled = addon.GetDBBool("ChatPlus")
    cachedClickableURLs = addon.GetDBBool("ChatPlus_ClickableURLs")
    cachedWowheadLookup = addon.GetDBBool("ChatPlus_WowheadLookup")
    cachedCopyButton = addon.GetDBBool("ChatPlus_CopyButton")
end

----------------------------------------------
-- Atlas Button Helper (3-Part Red Button)
-- Uses Left/Center/Right pieces for proper scaling
----------------------------------------------
local function StyleButtonWithAtlas(button)
    -- Hide default UIPanelButtonTemplate textures
    if button.Left then button.Left:Hide() end
    if button.Middle then button.Middle:Hide() end
    if button.Right then button.Right:Hide() end
    
    -- Create texture sets for each state
    -- Atlas dimensions: Left=114x128, Center=64x128 (tiling), Right=292x128
    local function CreateButtonTextures(suffix, layer)
        local btnHeight = button:GetHeight()
        -- Calculate scaled widths based on aspect ratio (original height is 128)
        local leftWidth = math.floor(114 * (btnHeight / 128) + 0.5)
        local rightWidth = math.floor(292 * (btnHeight / 128) + 0.5)
        
        local left = button:CreateTexture(nil, layer)
        left:SetAtlas("128-RedButton-Left" .. suffix, false)
        left:SetPoint("TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", 0, 0)
        left:SetWidth(leftWidth)
        
        local right = button:CreateTexture(nil, layer)
        right:SetAtlas("128-RedButton-Right" .. suffix, false)
        right:SetPoint("TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", 0, 0)
        right:SetWidth(rightWidth)
        
        local center = button:CreateTexture(nil, layer, nil, -1)
        center:SetAtlas("_128-RedButton-Center" .. suffix, false)
        center:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        center:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
        
        return { left = left, center = center, right = right }
    end
    
    -- Normal state
    button.normalTex = CreateButtonTextures("", "BACKGROUND")
    
    -- Pressed state (hidden by default)
    button.pushedTex = CreateButtonTextures("-Pressed", "BACKGROUND")
    button.pushedTex.left:Hide()
    button.pushedTex.center:Hide()
    button.pushedTex.right:Hide()
    
    -- Disabled state (hidden by default)
    button.disabledTex = CreateButtonTextures("-Disabled", "BACKGROUND")
    button.disabledTex.left:Hide()
    button.disabledTex.center:Hide()
    button.disabledTex.right:Hide()
    
    -- Highlight overlay
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("128-RedButton-Highlight", false)
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    
    -- Helper functions to show/hide texture sets
    local function ShowTexSet(set)
        set.left:Show()
        set.center:Show()
        set.right:Show()
    end
    
    local function HideTexSet(set)
        set.left:Hide()
        set.center:Hide()
        set.right:Hide()
    end
    
    -- Handle button states via scripts
    button:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() then
            HideTexSet(self.normalTex)
            ShowTexSet(self.pushedTex)
        end
    end)
    
    button:HookScript("OnMouseUp", function(self)
        if self:IsEnabled() then
            HideTexSet(self.pushedTex)
            ShowTexSet(self.normalTex)
        end
    end)
    
    -- Reset state when leaving button while pressed
    button:HookScript("OnLeave", function(self)
        if self:IsEnabled() then
            HideTexSet(self.pushedTex)
            ShowTexSet(self.normalTex)
        end
    end)
    
    -- Handle disabled state
    button:HookScript("OnDisable", function(self)
        HideTexSet(self.normalTex)
        HideTexSet(self.pushedTex)
        ShowTexSet(self.disabledTex)
    end)
    
    button:HookScript("OnEnable", function(self)
        HideTexSet(self.disabledTex)
        HideTexSet(self.pushedTex)
        ShowTexSet(self.normalTex)
    end)
    
    -- Update text appearance for red button
    button:SetNormalFontObject(GameFontNormal)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)
    button:SetPushedTextOffset(0, -2)
end

----------------------------------------------
-- Copy Frame
----------------------------------------------
local CopyFrame = nil

local function CreateCopyFrame()
    if CopyFrame then return CopyFrame end
    
    local frame = CreateFrame("Frame", "RefactorChatCopyFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 180)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    frame:SetBackdropBorderColor(0.3, 0.5, 0.8)
    
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetTextColor(0.6, 0.8, 1)
    frame.title = title
    
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    frame.subtitle = subtitle
    
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", subtitle, "BOTTOM", 0, -8)
    hint:SetText(L.CHAT_COPY_HINT or "Press Ctrl+C to copy, then Escape to close")
    hint:SetTextColor(0.6, 0.6, 0.6)
    
    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetSize(460, 25)
    editBox:SetPoint("TOP", hint, "BOTTOM", 0, -10)
    editBox:SetFontObject(GameFontHighlight)
    editBox:SetAutoFocus(true)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnEnterPressed", function() frame:Hide() end)
    frame.editBox = editBox
    
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 24)
    closeBtn:SetPoint("BOTTOM", 0, 12)
    closeBtn:SetText(CLOSE or "Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    StyleButtonWithAtlas(closeBtn)
    
    table_insert(UISpecialFrames, "RefactorChatCopyFrame")
    
    frame:Hide()
    CopyFrame = frame
    return frame
end

local function ShowCopyFrame(url, titleText, subtitleText)
    local frame = CreateCopyFrame()
    frame.title:SetText(titleText or "Wowhead Link")
    frame.subtitle:SetText(subtitleText or "")
    frame.subtitle:SetShown(subtitleText and subtitleText ~= "")
    frame.editBox:SetText(url)
    frame:Show()
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
end

----------------------------------------------
-- Wowhead Link Generation
----------------------------------------------
local function ShowWowheadLink(linkType, id, name)
    if not id then return end
    local url = WOWHEAD_BASE .. linkType .. "=" .. id
    local title = "Wowhead: " .. linkType:gsub("^%l", string.upper)
    ShowCopyFrame(url, title, name)
end

----------------------------------------------
-- Hook: SetItemRef (Chat Links)
----------------------------------------------
local originalSetItemRef = SetItemRef

local function HookedSetItemRef(link, text, button, chatFrame)
    -- Fast path: check cached settings
    if not cachedEnabled or not cachedWowheadLookup then
        return originalSetItemRef(link, text, button, chatFrame)
    end
    
    -- Shift+Click = Wowhead lookup
    if IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown() then
        local linkType, linkID = string_match(link, "^(%w+):(-?%d+)")
        if not linkType or not linkID then
            return originalSetItemRef(link, text, button, chatFrame)
        end
        
        local numericID = tonumber(linkID)
        if linkType == "item" then
            local itemName = C_Item_GetItemNameByID(numericID)
            ShowWowheadLink("item", linkID, itemName)
            return
        elseif linkType == "spell" or linkType == "enchant" then
            local spellName = C_Spell_GetSpellName(numericID)
            ShowWowheadLink("spell", linkID, spellName)
            return
        elseif linkType == "quest" then
            local questName = C_QuestLog_GetTitleForQuestID(numericID)
            ShowWowheadLink("quest", linkID, questName)
            return
        elseif linkType == "achievement" then
            local _, name = GetAchievementInfo(numericID)
            ShowWowheadLink("achievement", linkID, name or "")
            return
        elseif linkType == "currency" then
            local info = C_CurrencyInfo_GetCurrencyInfo(numericID)
            ShowWowheadLink("currency", linkID, info and info.name or "")
            return
        end
    end
    
    return originalSetItemRef(link, text, button, chatFrame)
end

----------------------------------------------
-- Clickable URLs (OPTIMIZED)
----------------------------------------------
-- Pre-compiled pattern check - fast rejection before expensive gsub
local function ContainsURL(text)
    -- Quick checks before regex
    if not text then return false end
    local len = #text
    if len < 10 then return false end -- URLs are at least 10 chars
    
    -- Fast substring checks
    if string.find(text, "http", 1, true) then return true end
    if string.find(text, "www.", 1, true) then return true end
    return false
end

local function MakeURLsClickable(text)
    if not ContainsURL(text) then return text end
    
    for _, pattern in ipairs(URL_PATTERNS) do
        text = string_gsub(text, "(" .. pattern .. ")", function(url)
            local cleanUrl = url
            if string_sub(cleanUrl, 1, 4) == "www." then
                cleanUrl = "https://" .. cleanUrl
            end
            return "|cff00ccff|Hrefactor_url:" .. cleanUrl .. "|h[" .. url .. "]|h|r"
        end)
    end
    
    return text
end

local function ChatMessageFilter(self, event, msg, ...)
    -- Fast path: check cached settings (no function call overhead)
    if not cachedEnabled or not cachedClickableURLs then
        return false, msg, ...
    end
    
    -- Fast rejection: no URL found
    if not ContainsURL(msg) then
        return false, msg, ...
    end
    
    local modified = MakeURLsClickable(msg)
    if modified ~= msg then
        return false, modified, ...
    end
    
    return false, msg, ...
end

----------------------------------------------
-- Chat Frame Hooks
----------------------------------------------
local function HookChatFrame(chatFrame)
    if chatFrame.RefactorHooked then return end
    chatFrame.RefactorHooked = true
    
    if not chatFrame:GetScript("OnHyperlinkClick") then return end
    
    local originalHandler = chatFrame:GetScript("OnHyperlinkClick")
    chatFrame:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if cachedEnabled and string_match(link, "^refactor_url:") then
            local url = string_gsub(link, "^refactor_url:", "")
            ShowCopyFrame(url, "Copy URL", nil)
            return
        end
        
        if originalHandler then
            return originalHandler(self, link, text, button)
        end
    end)
end

----------------------------------------------
-- Copy Button on Chat Frames
----------------------------------------------
local function CreateChatCopyButton(chatFrame)
    if chatFrame.RefactorCopyButton then return end
    
    local btn = CreateFrame("Button", nil, chatFrame, "UIPanelButtonTemplate")
    btn:SetSize(22, 22)
    btn:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", -24, -4)
    btn:SetText("C")
    StyleButtonWithAtlas(btn)
    btn:SetNormalFontObject(GameFontHighlightSmall)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Copy Chat", 1, 1, 1)
        GameTooltip:AddLine("Click to copy recent messages", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    btn:SetScript("OnClick", function()
        if not cachedEnabled then return end
        if not chatFrame.GetNumMessages or not chatFrame.GetMessageInfo then return end
        
        local numMessages = chatFrame:GetNumMessages()
        if numMessages > 0 then
            local allText = {}
            local limit = numMessages < 100 and numMessages or 100
            for j = 1, limit do
                local msg = chatFrame:GetMessageInfo(j)
                if msg and msg ~= "" then
                    -- Strip color codes and hyperlinks in one efficient pass
                    local clean = msg
                    clean = string_gsub(clean, "|c%x%x%x%x%x%x%x%x", "")
                    clean = string_gsub(clean, "|r", "")
                    clean = string_gsub(clean, "|H.-|h", "")
                    clean = string_gsub(clean, "|h", "")
                    if clean ~= "" then
                        table_insert(allText, clean)
                    end
                end
            end
            
            if #allText > 0 then
                ShowCopyFrame(table_concat(allText, "\n"), "Recent Chat", nil)
            end
        end
    end)
    
    btn:SetAlpha(0)
    chatFrame:HookScript("OnEnter", function() 
        if cachedEnabled and cachedCopyButton then
            btn:SetAlpha(0.6) 
        end
    end)
    chatFrame:HookScript("OnLeave", function() btn:SetAlpha(0) end)
    btn:HookScript("OnEnter", function() 
        if cachedEnabled and cachedCopyButton then
            btn:SetAlpha(1) 
        end
    end)
    btn:HookScript("OnLeave", function() btn:SetAlpha(0) end)
    
    chatFrame.RefactorCopyButton = btn
end

----------------------------------------------
-- Initialize
----------------------------------------------
local function Initialize()
    -- Cache initial settings
    UpdateCachedSettings()
    
    -- Hook SetItemRef for Wowhead lookup
    SetItemRef = HookedSetItemRef
    
    -- Hook all chat frames
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            HookChatFrame(chatFrame)
            CreateChatCopyButton(chatFrame)
        end
    end
    
    -- Hook new chat windows
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        C_Timer.After(0.1, function()
            for i = 1, NUM_CHAT_WINDOWS do
                local chatFrame = _G["ChatFrame" .. i]
                if chatFrame and not chatFrame.RefactorHooked then
                    HookChatFrame(chatFrame)
                    CreateChatCopyButton(chatFrame)
                end
            end
        end)
    end)
    
    -- Register URL filters
    local chatEvents = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_CHANNEL", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_SYSTEM", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    }
    
    for _, event in ipairs(chatEvents) do
        ChatFrame_AddMessageEventFilter(event, ChatMessageFilter)
    end
    
    -- Register setting change callbacks
    addon.CallbackRegistry:Register("SettingChanged.ChatPlus", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.ChatPlus_ClickableURLs", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.ChatPlus_WowheadLookup", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.ChatPlus_CopyButton", UpdateCachedSettings)
end

----------------------------------------------
-- Registration
----------------------------------------------
addon.CallbackRegistry:Register("AddonLoaded", function()
    Initialize()
end)
