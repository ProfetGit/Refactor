-- Refactor Addon - Settings Main Panel
-- Redesigned with 3 tabs: General, Automation, Tooltip

local addonName, addon = ...
local L = addon.L
local Components = addon.SettingsUI

----------------------------------------------
-- Panel State
----------------------------------------------
local SettingsPanel = {}
addon.SettingsPanel = SettingsPanel

local frame = nil
local containers = {}
local tabs = {}

----------------------------------------------
-- Smooth Scroll Animation Config
----------------------------------------------
local SCROLL_SPEED = 60
local SCROLL_SMOOTHNESS = 0.25
local SCROLL_THRESHOLD = 0.5

----------------------------------------------
-- Helper: Create Tab Container with Smooth Scroll
----------------------------------------------
local function CreateTabContainer(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 5)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    content:SetHeight(800)
    
    scrollFrame:SetScrollChild(content)
    
    -- Smooth scroll state
    local targetScroll = 0
    local isAnimating = false
    
    local animFrame = CreateFrame("Frame", nil, scrollFrame)
    animFrame:Hide()
    
    animFrame:SetScript("OnUpdate", function(self, elapsed)
        local currentScroll = scrollFrame:GetVerticalScroll()
        local diff = targetScroll - currentScroll
        
        if math.abs(diff) < SCROLL_THRESHOLD then
            scrollFrame:SetVerticalScroll(targetScroll)
            isAnimating = false
            self:Hide()
            return
        end
        
        local newScroll = currentScroll + (diff * SCROLL_SMOOTHNESS)
        scrollFrame:SetVerticalScroll(newScroll)
    end)
    
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = content:GetHeight() - scrollFrame:GetHeight()
        if maxScroll < 0 then maxScroll = 0 end
        
        targetScroll = targetScroll - (delta * SCROLL_SPEED)
        
        if targetScroll < 0 then targetScroll = 0 end
        if targetScroll > maxScroll then targetScroll = maxScroll end
        
        if not isAnimating then
            isAnimating = true
            animFrame:Show()
        end
    end)
    
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(self, delta)
        scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta)
    end)
    
    scrollFrame:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(width)
    end)
    
    container.scrollFrame = scrollFrame
    container.content = content
    container.sections = {}
    
    return container
end

----------------------------------------------
-- Tab 1: General (Overview Dashboard)
----------------------------------------------
local function SetupGeneralTab(parent)
    local container = CreateTabContainer(parent)
    local content = container.content
    
    -- Logo/Title area
    local infoInset = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
    infoInset:SetPoint("TOP", 0, -10)
    infoInset:SetPoint("LEFT", 15, 0)
    infoInset:SetPoint("RIGHT", -15, 0)
    infoInset:SetHeight(75)
    
    local logo = infoInset:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    logo:SetSize(52, 52)
    logo:SetPoint("LEFT", 12, 0)
    
    local name = infoInset:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    name:SetText(L.ADDON_NAME)
    name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -5)
    
    local version = infoInset:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetText("v" .. addon.VERSION)
    version:SetPoint("LEFT", name, "RIGHT", 8, 0)
    version:SetTextColor(0.5, 0.5, 0.5)
    
    local desc = infoInset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetText(L.ADDON_DESCRIPTION)
    desc:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 10, 5)
    
    -- Quick toggles header
    local header = Components.CreateHeader(content, "Quick Toggles")
    header:SetPoint("TOP", infoInset, "BOTTOM", 0, -20)
    
    -- Module quick toggles
    local lastFrame = header
    for _, moduleInfo in ipairs(addon.ModuleInfo) do
        local toggle = Components.CreateModuleToggle(content, moduleInfo)
        toggle:SetPoint("TOP", lastFrame, "BOTTOM", 0, -5)
        lastFrame = toggle
    end
    
    -- Calculate height
    content:SetHeight(85 + 40 + (#addon.ModuleInfo * 55) + 50)
    
    container:SetScript("OnShow", function()
        -- Refresh all toggle states
        for i = 1, content:GetNumChildren() do
            local child = select(i, content:GetChildren())
            if child.UpdateState then
                child:UpdateState()
            end
        end
    end)
    
    return container
end

----------------------------------------------
-- Tab 2: Automation (All auto-features)
----------------------------------------------
local function SetupAutomationTab(parent)
    local container = CreateTabContainer(parent)
    local content = container.content
    
    -- Expand/Collapse All buttons container
    local controlBar = CreateFrame("Frame", nil, content)
    controlBar:SetPoint("TOPLEFT", 30, -8)
    controlBar:SetPoint("RIGHT", -30, 0)
    controlBar:SetHeight(24)
    
    local expandAllBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    expandAllBtn:SetSize(90, 22)
    expandAllBtn:SetPoint("LEFT", 0, 0)
    expandAllBtn:SetText("Expand All")
    expandAllBtn:SetNormalFontObject(GameFontHighlightSmall)
    
    local collapseAllBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    collapseAllBtn:SetSize(90, 22)
    collapseAllBtn:SetPoint("LEFT", expandAllBtn, "RIGHT", 8, 0)
    collapseAllBtn:SetText("Collapse All")
    collapseAllBtn:SetNormalFontObject(GameFontHighlightSmall)
    
    -- Function to recalculate section positions
    local function RecalculateLayout()
        local yOffset = -40 -- Account for control bar
        for _, section in ipairs(container.sections) do
            section:ClearAllPoints()
            section:SetPoint("TOP", 0, yOffset)
            section:SetPoint("LEFT", 30, 0)
            section:SetPoint("RIGHT", -15, 0)
            local height = section.isExpanded and section.innerHeight or section.collapsedHeight
            yOffset = yOffset - height - 10
        end
        content:SetHeight(math.abs(yOffset) + 50)
    end
    
    -- Button handlers
    expandAllBtn:SetScript("OnClick", function()
        for _, section in ipairs(container.sections) do
            section:SetExpanded(true)
        end
        RecalculateLayout()
    end)
    
    collapseAllBtn:SetScript("OnClick", function()
        for _, section in ipairs(container.sections) do
            section:SetExpanded(false)
        end
        RecalculateLayout()
    end)
    
    -- ========== AUTO-SELL JUNK (Smart Vendor) ==========
    local sellSection = Components.CreateModuleSection(
        content,
        L.MODULE_AUTO_SELL,
        "Sell junk + optionally old soulbound gear. BoE never sold.",
        "AutoSellJunk",
        true
    )
    sellSection:SetPoint("TOP", 0, -40)
    sellSection:AddCheckbox(L.SHOW_NOTIFICATIONS, "AutoSellJunk_ShowNotify", L.TIP_SELL_NOTIFY)
    sellSection:AddCheckbox(L.SELL_KNOWN_TRANSMOG, "AutoSellJunk_SellKnownTransmog", L.TIP_SELL_KNOWN_TRANSMOG)
    sellSection:AddCheckbox(L.KEEP_TRANSMOG, "AutoSellJunk_KeepTransmog", L.TIP_KEEP_TRANSMOG)
    sellSection:AddCheckbox(L.SELL_LOW_ILVL, "AutoSellJunk_SellLowILvl", L.TIP_SELL_LOW_ILVL)
    sellSection:AddSliderWithTooltip(L.MAX_ILVL_TO_SELL, "AutoSellJunk_MaxILvl", 0, 700, 10, L.TIP_MAX_ILVL)
    sellSection.OnExpandChanged = RecalculateLayout
    table.insert(container.sections, sellSection)
    
    -- ========== AUTO-REPAIR ==========
    local repairSection = Components.CreateModuleSection(
        content,
        L.MODULE_AUTO_REPAIR,
        "Automatically repair gear when visiting a repair vendor.",
        "AutoRepair",
        true
    )
    repairSection:AddCheckbox(L.USE_GUILD_FUNDS, "AutoRepair_UseGuild", L.TIP_USE_GUILD_FUNDS)
    repairSection:AddCheckbox(L.SHOW_NOTIFICATIONS, "AutoRepair_ShowNotify", L.TIP_REPAIR_NOTIFY)
    repairSection.OnExpandChanged = RecalculateLayout
    table.insert(container.sections, repairSection)
    
    -- ========== FAST LOOT ==========
    local lootSection = Components.CreateModuleSection(
        content,
        L.MODULE_FAST_LOOT,
        "Instantly loot all items without showing the loot window.",
        "FastLoot",
        false
    )
    lootSection.OnExpandChanged = RecalculateLayout
    table.insert(container.sections, lootSection)
    
    -- ========== AUTO-QUEST ==========
    local questSection = Components.CreateModuleSection(
        content,
        L.MODULE_AUTO_QUEST,
        "Automatically accept and turn in quests.",
        "AutoQuest",
        true
    )
    questSection:AddCheckbox(L.AUTO_ACCEPT, "AutoQuest_Accept", L.TIP_AUTO_ACCEPT)
    questSection:AddCheckbox(L.AUTO_TURNIN, "AutoQuest_TurnIn", L.TIP_AUTO_TURNIN)
    questSection:AddCheckbox(L.SKIP_GOSSIP, "AutoQuest_SkipGossip", L.TIP_SKIP_GOSSIP)
    questSection:AddCheckbox(L.DAILY_QUESTS_ONLY, "AutoQuest_DailyOnly", L.TIP_DAILY_ONLY)
    questSection:AddDropdown(L.MODIFIER_KEY, "AutoQuest_ModifierKey", {
        { value = "SHIFT", label = L.MODIFIER_SHIFT },
        { value = "CTRL", label = L.MODIFIER_CTRL },
        { value = "ALT", label = L.MODIFIER_ALT },
        { value = "NONE", label = L.MODIFIER_NONE },
    })
    questSection.OnExpandChanged = RecalculateLayout
    table.insert(container.sections, questSection)
    
    -- ========== SKIP CINEMATICS ==========
    local cinSection = Components.CreateModuleSection(
        content,
        L.MODULE_SKIP_CINEMATICS,
        "Skip cinematics and movies you've already seen.",
        "SkipCinematics",
        true
    )
    cinSection:AddCheckbox(L.ALWAYS_SKIP, "SkipCinematics_AlwaysSkip", L.TIP_ALWAYS_SKIP)
    cinSection:AddDropdown(L.MODIFIER_KEY, "SkipCinematics_ModifierKey", {
        { value = "SHIFT", label = L.MODIFIER_SHIFT },
        { value = "CTRL", label = L.MODIFIER_CTRL },
        { value = "ALT", label = L.MODIFIER_ALT },
        { value = "NONE", label = L.MODIFIER_NONE },
    })
    cinSection.OnExpandChanged = RecalculateLayout
    table.insert(container.sections, cinSection)
    
    -- ========== AUTO-CONFIRM ==========
    local confirmSection = Components.CreateModuleSection(
        content,
        L.MODULE_AUTO_CONFIRM,
        "Auto-confirm ready checks, summons, role checks, and more.",
        "AutoConfirm",
        true
    )
    confirmSection:AddCheckbox(L.CONFIRM_READY_CHECK, "AutoConfirm_ReadyCheck", L.TIP_READY_CHECK)
    confirmSection:AddCheckbox(L.CONFIRM_SUMMON, "AutoConfirm_Summon", L.TIP_SUMMON)
    confirmSection:AddCheckbox(L.CONFIRM_ROLE_CHECK, "AutoConfirm_RoleCheck", L.TIP_ROLE_CHECK)
    confirmSection:AddCheckbox(L.CONFIRM_RESURRECT, "AutoConfirm_Resurrect", L.TIP_RESURRECT)
    confirmSection:AddCheckbox(L.CONFIRM_BINDING, "AutoConfirm_Binding", L.TIP_BINDING)
    confirmSection:AddCheckbox(L.CONFIRM_DELETE_GREY, "AutoConfirm_DeleteGrey", L.TIP_DELETE_GREY)
    confirmSection.OnExpandChanged = RecalculateLayout
    table.insert(container.sections, confirmSection)
    
    -- ========== AUTO-INVITE ==========
    local inviteSection = Components.CreateModuleSection(
        content,
        L.MODULE_AUTO_INVITE,
        "Accept party invites from trusted sources.",
        "AutoInvite",
        true
    )
    inviteSection:AddCheckbox(L.INVITE_FRIENDS, "AutoInvite_Friends", L.TIP_INVITE_FRIENDS)
    inviteSection:AddCheckbox(L.INVITE_BNET, "AutoInvite_BNetFriends", L.TIP_INVITE_BNET)
    inviteSection:AddCheckbox(L.INVITE_GUILD, "AutoInvite_Guild", L.TIP_INVITE_GUILD)
    inviteSection:AddCheckbox(L.INVITE_GUILD_INVITES, "AutoInvite_GuildInvites", L.TIP_GUILD_INVITES)
    inviteSection.OnExpandChanged = RecalculateLayout
    table.insert(container.sections, inviteSection)
    
    -- ========== AUTO-RELEASE ==========
    local releaseSection = Components.CreateModuleSection(
        content,
        L.MODULE_AUTO_RELEASE,
        "Release spirit automatically in selected content.",
        "AutoRelease",
        true
    )
    releaseSection:AddDropdown(L.RELEASE_MODE, "AutoRelease_Mode", {
        { value = "ALWAYS", label = L.RELEASE_ALWAYS },
        { value = "PVP", label = L.RELEASE_PVP },
        { value = "PVE", label = L.RELEASE_PVE },
        { value = "OPENWORLD", label = L.RELEASE_OPENWORLD },
    })
    releaseSection:AddCheckbox(L.SHOW_NOTIFICATIONS, "AutoRelease_Notify", L.TIP_RELEASE_NOTIFY)
    releaseSection.OnExpandChanged = RecalculateLayout
    table.insert(container.sections, releaseSection)
    
    -- Initial layout
    RecalculateLayout()
    
    container:SetScript("OnShow", function()
        for _, section in ipairs(container.sections) do
            section:RefreshOptions()
        end
    end)
    
    return container
end

----------------------------------------------
-- Tab 3: Tooltip (All tooltip features)
----------------------------------------------
local function SetupTooltipTab(parent)
    local container = CreateTabContainer(parent)
    local content = container.content
    
    -- Main header
    local header = Components.CreateHeader(content, L.MODULE_TOOLTIP_PLUS)
    header:SetPoint("TOP", 0, -10)
    
    -- Enable checkbox
    local enableTooltip = Components.CreateCheckbox(content, L.ENABLE, 28, function(state)
        addon.SetDBValue("TooltipPlus", state, true)
    end)
    enableTooltip.option = "TooltipPlus"
    enableTooltip:SetPoint("TOP", header, "BOTTOM", 0, 0)
    
    -- === POSITIONING SECTION ===
    local posHeader = Components.CreateHeader(content, "Positioning")
    posHeader:SetPoint("TOP", enableTooltip, "BOTTOM", 0, -10)
    
    local anchorDropdown = Components.CreateDropdown(
        content,
        L.TOOLTIP_ANCHOR,
        {
            { value = "DEFAULT", label = L.ANCHOR_DEFAULT },
            { value = "MOUSE", label = L.ANCHOR_MOUSE },
            { value = "TOPLEFT", label = L.ANCHOR_TOPLEFT },
            { value = "TOPRIGHT", label = L.ANCHOR_TOPRIGHT },
            { value = "BOTTOMLEFT", label = L.ANCHOR_BOTTOMLEFT },
            { value = "BOTTOMRIGHT", label = L.ANCHOR_BOTTOMRIGHT },
        },
        function(value) return addon.GetDBValue("TooltipPlus_Anchor") == value end,
        function(value) addon.SetDBValue("TooltipPlus_Anchor", value, true) end
    )
    anchorDropdown:SetPoint("TOP", posHeader, "BOTTOM", 0, -5)
    
    local sideDropdown = Components.CreateDropdown(
        content,
        L.TOOLTIP_MOUSE_SIDE,
        {
            { value = "RIGHT", label = L.SIDE_RIGHT },
            { value = "LEFT", label = L.SIDE_LEFT },
            { value = "TOP", label = L.SIDE_TOP },
            { value = "BOTTOM", label = L.SIDE_BOTTOM },
        },
        function(value) return addon.GetDBValue("TooltipPlus_MouseSide") == value end,
        function(value) addon.SetDBValue("TooltipPlus_MouseSide", value, true) end
    )
    sideDropdown:SetPoint("TOP", anchorDropdown, "BOTTOM", 0, -5)
    
    -- === APPEARANCE SECTION ===
    local appearHeader = Components.CreateHeader(content, "Appearance")
    appearHeader:SetPoint("TOP", sideDropdown, "BOTTOM", 0, -10)
    
    local classColors = Components.CreateCheckbox(content, L.TOOLTIP_CLASS_COLORS, 28, function(state)
        addon.SetDBValue("TooltipPlus_ClassColors", state, true)
    end)
    classColors.option = "TooltipPlus_ClassColors"
    classColors:SetPoint("TOP", appearHeader, "BOTTOM", 0, 0)
    
    local rarityBorder = Components.CreateCheckbox(content, L.TOOLTIP_RARITY_BORDER, 28, function(state)
        addon.SetDBValue("TooltipPlus_RarityBorder", state, true)
    end)
    rarityBorder.option = "TooltipPlus_RarityBorder"
    rarityBorder:SetPoint("TOP", classColors, "BOTTOM", 0, 0)
    
    local compact = Components.CreateCheckbox(content, L.TOOLTIP_COMPACT, 28, function(state)
        addon.SetDBValue("TooltipPlus_Compact", state, true)
    end)
    compact.option = "TooltipPlus_Compact"
    compact:SetPoint("TOP", rarityBorder, "BOTTOM", 0, 0)
    
    local showTransmog = Components.CreateCheckbox(content, L.TOOLTIP_SHOW_TRANSMOG, 28, function(state)
        addon.SetDBValue("TooltipPlus_ShowTransmog", state, true)
    end)
    showTransmog.option = "TooltipPlus_ShowTransmog"
    showTransmog:SetPoint("TOP", compact, "BOTTOM", 0, 0)
    
    -- === TRANSMOG OVERLAY SECTION ===
    local transmogHeader = Components.CreateHeader(content, "Transmog Overlay")
    transmogHeader:SetPoint("TOP", showTransmog, "BOTTOM", 0, -10)
    
    local transmogOverlay = Components.CreateCheckbox(content, L.TOOLTIP_TRANSMOG_OVERLAY, 28, function(state)
        addon.SetDBValue("TooltipPlus_TransmogOverlay", state, true)
    end)
    transmogOverlay.option = "TooltipPlus_TransmogOverlay"
    transmogOverlay:SetPoint("TOP", transmogHeader, "BOTTOM", 0, 0)
    
    local transmogCorner = Components.CreateDropdown(content, L.TOOLTIP_TRANSMOG_CORNER, {
        { value = "TOPLEFT", label = L.ANCHOR_TOPLEFT },
        { value = "TOPRIGHT", label = L.ANCHOR_TOPRIGHT },
        { value = "BOTTOMLEFT", label = L.ANCHOR_BOTTOMLEFT },
        { value = "BOTTOMRIGHT", label = L.ANCHOR_BOTTOMRIGHT },
    }, function(value)
        return addon.GetDBValue("TooltipPlus_TransmogCorner") == value
    end, function(value)
        addon.SetDBValue("TooltipPlus_TransmogCorner", value, true)
    end)
    transmogCorner.option = "TooltipPlus_TransmogCorner"
    transmogCorner:SetPoint("TOP", transmogOverlay, "BOTTOM", 0, -5)
    
    -- === HIDE ELEMENTS SECTION ===
    local hideHeader = Components.CreateHeader(content, "Hide Elements")
    hideHeader:SetPoint("TOP", transmogCorner, "BOTTOM", 0, -10)
    
    local hideHealthbar = Components.CreateCheckbox(content, L.TOOLTIP_HIDE_HEALTHBAR, 28, function(state)
        addon.SetDBValue("TooltipPlus_HideHealthbar", state, true)
    end)
    hideHealthbar.option = "TooltipPlus_HideHealthbar"
    hideHealthbar:SetPoint("TOP", hideHeader, "BOTTOM", 0, 0)
    
    local hideGuild = Components.CreateCheckbox(content, L.TOOLTIP_HIDE_GUILD, 28, function(state)
        addon.SetDBValue("TooltipPlus_HideGuild", state, true)
    end)
    hideGuild.option = "TooltipPlus_HideGuild"
    hideGuild:SetPoint("TOP", hideHealthbar, "BOTTOM", 0, 0)
    
    local hideFaction = Components.CreateCheckbox(content, L.TOOLTIP_HIDE_FACTION, 28, function(state)
        addon.SetDBValue("TooltipPlus_HideFaction", state, true)
    end)
    hideFaction.option = "TooltipPlus_HideFaction"
    hideFaction:SetPoint("TOP", hideGuild, "BOTTOM", 0, 0)
    
    local hidePvP = Components.CreateCheckbox(content, L.TOOLTIP_HIDE_PVP, 28, function(state)
        addon.SetDBValue("TooltipPlus_HidePvP", state, true)
    end)
    hidePvP.option = "TooltipPlus_HidePvP"
    hidePvP:SetPoint("TOP", hideFaction, "BOTTOM", 0, 0)
    
    local hideRealm = Components.CreateCheckbox(content, L.TOOLTIP_HIDE_REALM, 28, function(state)
        addon.SetDBValue("TooltipPlus_HideRealm", state, true)
    end)
    hideRealm.option = "TooltipPlus_HideRealm"
    hideRealm:SetPoint("TOP", hidePvP, "BOTTOM", 0, 0)
    
    -- === EXTRA INFO SECTION ===
    local infoHeader = Components.CreateHeader(content, "Extra Info")
    infoHeader:SetPoint("TOP", hideRealm, "BOTTOM", 0, -10)
    
    local showItemID = Components.CreateCheckbox(content, L.TOOLTIP_SHOW_ITEM_ID, 28, function(state)
        addon.SetDBValue("TooltipPlus_ShowItemID", state, true)
    end)
    showItemID.option = "TooltipPlus_ShowItemID"
    showItemID:SetPoint("TOP", infoHeader, "BOTTOM", 0, 0)
    
    local showSpellID = Components.CreateCheckbox(content, L.TOOLTIP_SHOW_SPELL_ID, 28, function(state)
        addon.SetDBValue("TooltipPlus_ShowSpellID", state, true)
    end)
    showSpellID.option = "TooltipPlus_ShowSpellID"
    showSpellID:SetPoint("TOP", showItemID, "BOTTOM", 0, 0)
    
    content:SetHeight(750)
    
    -- Store all checkboxes for refresh
    local allCheckboxes = {
        enableTooltip, classColors, rarityBorder, compact, showTransmog,
        transmogOverlay,
        hideHealthbar, hideGuild, hideFaction, hidePvP, hideRealm,
        showItemID, showSpellID
    }
    
    -- Store dropdowns for refresh
    local allDropdowns = { transmogCorner }
    
    container:SetScript("OnShow", function()
        -- Refresh checkboxes
        for _, cb in ipairs(allCheckboxes) do
            if cb.SetValue and cb.option then
                cb:SetValue(addon.GetDBBool(cb.option))
            end
        end
        -- Refresh dropdowns
        for _, dd in ipairs(allDropdowns) do
            if dd.SetValue then
                dd:SetValue()
            end
        end
    end)
    
    return container
end

----------------------------------------------
-- Tab Configuration (3 Tabs)
----------------------------------------------
local TabSetups = {
    { name = L.SETTINGS_GENERAL, callback = SetupGeneralTab },
    { name = L.SETTINGS_AUTOMATION, callback = SetupAutomationTab },
    { name = L.SETTINGS_TOOLTIP, callback = SetupTooltipTab },
}

----------------------------------------------
-- Create Main Frame
----------------------------------------------
local function CreateSettingsFrame()
    if frame then return frame end
    
    frame = CreateFrame("Frame", "RefactorSettingsDialog", UIParent, "ButtonFrameTemplate")
    frame:SetToplevel(true)
    frame:SetSize(500, 550)
    frame:SetPoint("CENTER")
    frame:Raise()
    
    -- Make it movable
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        frame:StartMoving()
        frame:SetUserPlaced(false)
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
    end)
    
    -- Configure frame
    ButtonFrameTemplate_HidePortrait(frame)
    ButtonFrameTemplate_HideButtonBar(frame)
    frame.Inset:Hide()
    frame:EnableMouse(true)
    frame:SetScript("OnMouseWheel", function() end)
    
    frame:SetTitle(L.SETTINGS_TITLE)
    
    -- Add to special frames
    table.insert(UISpecialFrames, frame:GetName())
    
    -- Create tabs
    local lastTab = nil
    for i, setup in ipairs(TabSetups) do
        local tabContainer = setup.callback(frame)
        tabContainer:SetPoint("TOPLEFT", 10, -65)
        tabContainer:SetPoint("BOTTOMRIGHT", -10, 10)
        tabContainer:Hide()
        
        local tabButton = Components.CreateTab(frame, setup.name)
        if lastTab then
            tabButton:SetPoint("LEFT", lastTab, "RIGHT", 5, 0)
        else
            tabButton:SetPoint("TOPLEFT", 15, -25)
        end
        lastTab = tabButton
        tabContainer.button = tabButton
        
        tabButton:SetScript("OnClick", function()
            for _, c in ipairs(containers) do
                PanelTemplates_DeselectTab(c.button)
                c:Hide()
            end
            PanelTemplates_SelectTab(tabButton)
            tabContainer:Show()
        end)
        
        table.insert(tabs, tabButton)
        table.insert(containers, tabContainer)
    end
    
    frame.Tabs = tabs
    PanelTemplates_SetNumTabs(frame, #tabs)
    
    -- Show first tab
    containers[1].button:Click()
    
    frame:SetScript("OnShow", function()
        local shownContainer = nil
        for _, c in ipairs(containers) do
            if c:IsShown() then
                shownContainer = c
                break
            end
        end
        if shownContainer then
            PanelTemplates_SetTab(frame, tIndexOf(containers, shownContainer))
        end
    end)
    
    frame:Hide()
    return frame
end

----------------------------------------------
-- Public Functions
----------------------------------------------
function SettingsPanel:Toggle()
    if not frame then
        CreateSettingsFrame()
    end
    frame:SetShown(not frame:IsShown())
end

function SettingsPanel:Show()
    if not frame then
        CreateSettingsFrame()
    end
    frame:Show()
end

function SettingsPanel:Hide()
    if frame then
        frame:Hide()
    end
end

----------------------------------------------
-- Initialize
----------------------------------------------
addon.CallbackRegistry:Register("AddonLoaded", function()
    C_Timer.After(1, function()
        CreateSettingsFrame()
    end)
end)
