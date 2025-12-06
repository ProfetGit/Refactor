-- Refactor Addon - Chat Plus Module
-- Wowhead lookup on chat links, clickable URLs, copy chat

local addonName, addon = ...
local L = addon.L

local ChatPlus = {}
addon.Modules.ChatPlus = ChatPlus

----------------------------------------------
-- Constants
----------------------------------------------
local URL_PATTERNS = {
    "(https?://[%w_%-%.%/%?%%=&#:~]+)",
    "(www%.[%w_%-%.%/%?%%=&#:~]+)",
}

local WOWHEAD_BASE = "https://www.wowhead.com/"

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
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOM", 0, 12)
    closeBtn:SetText(CLOSE or "Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    table.insert(UISpecialFrames, "RefactorChatCopyFrame")
    
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
    if not addon.GetDBBool("ChatPlus") then
        return originalSetItemRef(link, text, button, chatFrame)
    end
    
    if not addon.GetDBBool("ChatPlus_WowheadLookup") then
        return originalSetItemRef(link, text, button, chatFrame)
    end
    
    -- Shift+Click = Wowhead lookup
    if IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown() then
        local linkType, linkID = link:match("^(%w+):(-?%d+)")
        
        if linkType == "item" then
            local itemName = C_Item.GetItemNameByID(tonumber(linkID))
            ShowWowheadLink("item", linkID, itemName)
            return
        elseif linkType == "spell" or linkType == "enchant" then
            local spellName = C_Spell.GetSpellName(tonumber(linkID))
            ShowWowheadLink("spell", linkID, spellName)
            return
        elseif linkType == "quest" then
            local questName = C_QuestLog.GetTitleForQuestID(tonumber(linkID))
            ShowWowheadLink("quest", linkID, questName)
            return
        elseif linkType == "achievement" then
            local _, name = GetAchievementInfo(tonumber(linkID))
            ShowWowheadLink("achievement", linkID, name)
            return
        elseif linkType == "currency" then
            local info = C_CurrencyInfo.GetCurrencyInfo(tonumber(linkID))
            ShowWowheadLink("currency", linkID, info and info.name)
            return
        end
    end
    
    return originalSetItemRef(link, text, button, chatFrame)
end

----------------------------------------------
-- Clickable URLs
----------------------------------------------
local function MakeURLsClickable(text)
    if not text then return text end
    
    for _, pattern in ipairs(URL_PATTERNS) do
        text = text:gsub(pattern, function(url)
            local cleanUrl = url
            if cleanUrl:sub(1, 4) == "www." then
                cleanUrl = "https://" .. cleanUrl
            end
            return "|cff00ccff|Hrefactor_url:" .. cleanUrl .. "|h[" .. url .. "]|h|r"
        end)
    end
    
    return text
end

local function ChatMessageFilter(self, event, msg, ...)
    if not addon.GetDBBool("ChatPlus") then
        return false, msg, ...
    end
    
    if not addon.GetDBBool("ChatPlus_ClickableURLs") then
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
        if addon.GetDBBool("ChatPlus") and link:match("^refactor_url:") then
            local url = link:gsub("^refactor_url:", "")
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
    btn:SetSize(20, 20)
    btn:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", -24, -4)
    btn:SetText("C")
    btn:SetNormalFontObject(GameFontHighlightSmall)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Copy Chat", 1, 1, 1)
        GameTooltip:AddLine("Click to copy recent messages", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    btn:SetScript("OnClick", function()
        if not addon.GetDBBool("ChatPlus") then return end
        
        local numMessages = chatFrame:GetNumMessages()
        if numMessages > 0 then
            local allText = {}
            for j = 1, math.min(numMessages, 100) do
                local msg = chatFrame:GetMessageInfo(j)
                if msg then
                    local clean = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
                    table.insert(allText, clean)
                end
            end
            
            if #allText > 0 then
                ShowCopyFrame(table.concat(allText, "\n"), "Recent Chat", nil)
            end
        end
    end)
    
    btn:SetAlpha(0)
    chatFrame:HookScript("OnEnter", function() 
        if addon.GetDBBool("ChatPlus") and addon.GetDBBool("ChatPlus_CopyButton") then
            btn:SetAlpha(0.6) 
        end
    end)
    chatFrame:HookScript("OnLeave", function() btn:SetAlpha(0) end)
    btn:HookScript("OnEnter", function() 
        if addon.GetDBBool("ChatPlus") and addon.GetDBBool("ChatPlus_CopyButton") then
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
end

----------------------------------------------
-- Registration
----------------------------------------------
addon.CallbackRegistry:Register("AddonLoaded", function()
    Initialize()
end)
