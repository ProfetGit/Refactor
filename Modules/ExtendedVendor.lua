local addonName, addon = ...

local Module = addon:NewModule("ExtendedVendor", {
    settingKey = "ExtendedVendor"
})

----------------------------------------------
-- Performance: Cache globals
----------------------------------------------
local InCombatLockdown = InCombatLockdown
local GetMerchantNumItems = GetMerchantNumItems

----------------------------------------------
-- Constants
----------------------------------------------
-- Reference values from EnhanceQoL/Submodules/Merchant.lua
local EXPANDED_WIDTH = 696
local EXTENDED_PER_PAGE = 20
local ORIGINAL_PER_PAGE = 10

-- State
local extraButtonsCreated = false
local originalFrameWidth = nil
local isExpanded = false

-- Save original positions of elements we move
local savedPositions = {}

----------------------------------------------
-- Position save/restore helpers
----------------------------------------------
local function SaveOriginalPoint(frame, key)
    if not frame or savedPositions[key] then return end
    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if point then
        savedPositions[key] = { point, relativeTo, relativePoint, xOfs, yOfs }
    end
end

local function RestoreOriginalPoint(frame, key)
    if not frame or not savedPositions[key] then return end
    local p = savedPositions[key]
    frame:ClearAllPoints()
    frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
    savedPositions[key] = nil
end

----------------------------------------------
-- Create the extra MerchantItem buttons (11-20)
----------------------------------------------
local function EnsureExtraButtonsExist()
    if extraButtonsCreated then return end
    if not MerchantFrame then return end

    for i = ORIGINAL_PER_PAGE + 1, EXTENDED_PER_PAGE do
        local name = "MerchantItem" .. i
        if not _G[name] then
            local item = CreateFrame("Frame", name, MerchantFrame, "MerchantItemTemplate")
            item:SetID(i)

            local itemButton = _G[name .. "ItemButton"]
            if itemButton then
                itemButton:SetID(i)
            end
        end
    end

    extraButtonsCreated = true
end

----------------------------------------------
-- Reposition items into 4-column grid (side-by-side)
----------------------------------------------
local function RepositionItems()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end

    local vertSpacing = -16
    local horizSpacing = 12
    local perSubpage = ORIGINAL_PER_PAGE

    for i = 1, EXTENDED_PER_PAGE do
        local buy_slot = _G["MerchantItem" .. i]
        if buy_slot then
            buy_slot:Show()
            buy_slot:ClearAllPoints()
            if (i % perSubpage) == 1 then
                if i == 1 then
                    buy_slot:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 24, -70)
                else
                    -- i is 11. Anchored to Item 2 to start the right half of the grid
                    buy_slot:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - (perSubpage - 1))], "TOPRIGHT", 12, 0)
                end
            else
                if (i % 2) == 1 then
                    -- Odd slots anchored to the slot 2 above
                    buy_slot:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 2)], "BOTTOMLEFT", 0, vertSpacing)
                else
                    -- Even slots anchored to the slot to their left
                    buy_slot:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 1)], "TOPRIGHT", horizSpacing, 0)
                end
            end
        end
    end

    -- Ensure navigation buttons are shown correctly
    local numMerchantItems = GetMerchantNumItems()
    if numMerchantItems <= EXTENDED_PER_PAGE then
        MerchantPageText:Show()
        MerchantPrevPageButton:Show()
        MerchantPrevPageButton:Disable()
        MerchantNextPageButton:Show()
        MerchantNextPageButton:Disable()
    end
end

----------------------------------------------
-- Bottom-left button positioning logic
----------------------------------------------
local function RepositionBuybackItem()
    local MerchantBuyBackItem = _G.MerchantBuyBackItem
    local MerchantItem10 = _G.MerchantItem10
    if MerchantBuyBackItem and MerchantItem10 then
        SaveOriginalPoint(MerchantBuyBackItem, "MerchantBuyBackItem")
        MerchantBuyBackItem:ClearAllPoints()
        MerchantBuyBackItem:SetPoint("TOPLEFT", MerchantItem10, "BOTTOMLEFT", 17, -20)
    end
end

local function RepositionSellAllJunkButton()
    if not CanMerchantRepair() then
        local MerchantSellAllJunkButton = _G.MerchantSellAllJunkButton
        local MerchantBuyBackItem = _G.MerchantBuyBackItem
        if MerchantSellAllJunkButton and MerchantBuyBackItem then
            SaveOriginalPoint(MerchantSellAllJunkButton, "MerchantSellAllJunkButton")
            MerchantSellAllJunkButton:ClearAllPoints()
            MerchantSellAllJunkButton:SetPoint("RIGHT", MerchantBuyBackItem, "LEFT", -18, 0)
        end
    end
end

local function RepositionGuildRepairButton()
    local MerchantGuildBankRepairButton = _G.MerchantGuildBankRepairButton
    local MerchantRepairAllButton = _G.MerchantRepairAllButton
    if MerchantGuildBankRepairButton and MerchantRepairAllButton then
        SaveOriginalPoint(MerchantGuildBankRepairButton, "MerchantGuildBankRepairButton")
        MerchantGuildBankRepairButton:ClearAllPoints()
        MerchantGuildBankRepairButton:SetPoint("LEFT", MerchantRepairAllButton, "RIGHT", 10, 0)
    end
end

local function AdjustBottomElements()
    if not MerchantFrame then return end

    -- Position pagination elements
    SaveOriginalPoint(MerchantPrevPageButton, "MerchantPrevPageButton")
    MerchantPrevPageButton:ClearAllPoints()
    MerchantPrevPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOM", 36, 55)

    SaveOriginalPoint(MerchantPageText, "MerchantPageText")
    MerchantPageText:ClearAllPoints()
    MerchantPageText:SetPoint("BOTTOM", MerchantFrame, "BOTTOM", 166, 50)

    SaveOriginalPoint(MerchantNextPageButton, "MerchantNextPageButton")
    MerchantNextPageButton:ClearAllPoints()
    MerchantNextPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOM", 296, 55)

    -- Unified Currency Bar Logic
    local MerchantMoneyBg = _G.MerchantMoneyBg
    local MerchantMoneyInset = _G.MerchantMoneyInset
    local MerchantExtraCurrencyInset = _G.MerchantExtraCurrencyInset
    local MerchantExtraCurrencyBg = _G.MerchantExtraCurrencyBg
    local MerchantMoneyFrame = _G.MerchantMoneyFrame

    -- Widening the main money background to cover the whole bottom-right area
    if MerchantMoneyBg then
        SaveOriginalPoint(MerchantMoneyBg, "MerchantMoneyBg")
        MerchantMoneyBg:ClearAllPoints()
        MerchantMoneyBg:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -8, 25)
        MerchantMoneyBg:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMRIGHT", -340, 6)
    end

    if MerchantMoneyInset then
        SaveOriginalPoint(MerchantMoneyInset, "MerchantMoneyInset")
        -- The inset is usually anchored to the Bg, but we'll be explicit
    end

    -- Hide the redundant extra currency bg elements
    if MerchantExtraCurrencyInset then
        SaveOriginalPoint(MerchantExtraCurrencyInset, "MerchantExtraCurrencyInset")
        MerchantExtraCurrencyInset:Hide()
    end
    if MerchantExtraCurrencyBg then
        SaveOriginalPoint(MerchantExtraCurrencyBg, "MerchantExtraCurrencyBg")
        MerchantExtraCurrencyBg:Hide()
    end

    -- Position Gold on the left of the new wide bar
    if MerchantMoneyFrame then
        SaveOriginalPoint(MerchantMoneyFrame, "MerchantMoneyFrame")
        MerchantMoneyFrame:ClearAllPoints()
        MerchantMoneyFrame:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMRIGHT", -332, 8)
    end

    -- Reposition tokens to the right of the gold
    local currencies = { GetMerchantCurrencies() }
    for index = 1, #currencies do
        local tokenButton = _G["MerchantToken" .. index]
        if tokenButton then
            SaveOriginalPoint(tokenButton, "MerchantToken" .. index)
            tokenButton:ClearAllPoints()
            if index == 1 then
                tokenButton:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -16, 8)
            else
                tokenButton:SetPoint("RIGHT", _G["MerchantToken" .. index - 1], "LEFT", -4, 0)
            end
        end
    end

    RepositionBuybackItem()
    RepositionSellAllJunkButton()
    RepositionGuildRepairButton()
end

local function RestoreBottomElements()
    local names = {
        "MerchantRepairItemButton",
        "MerchantRepairAllButton",
        "MerchantGuildBankRepairButton",
        "MerchantSellAllJunkButton",
        "MerchantBuyBackItem",
        "MerchantPageText",
        "MerchantPrevPageButton",
        "MerchantNextPageButton",
        "MerchantMoneyBg",
        "MerchantMoneyInset",
        "MerchantExtraCurrencyInset",
        "MerchantExtraCurrencyBg",
        "MerchantMoneyFrame",
    }
    for _, name in ipairs(names) do
        local btn = _G[name]
        if btn then
            RestoreOriginalPoint(btn, name)
            if name:find("ExtraCurrency") then
                btn:Show()
            end
        end
    end
    -- Also restore tokens
    for i = 1, 10 do
        local token = _G["MerchantToken" .. i]
        if token then
            RestoreOriginalPoint(token, "MerchantToken" .. i)
        end
    end
end

----------------------------------------------
-- Expand / Collapse
----------------------------------------------
local function ExpandMerchantFrame()
    if isExpanded or not MerchantFrame then return end

    EnsureExtraButtonsExist()

    if not originalFrameWidth then
        originalFrameWidth = MerchantFrame:GetWidth()
    end

    -- Tell Blizzard to handle 20 items per page
    _G.MERCHANT_ITEMS_PER_PAGE = EXTENDED_PER_PAGE

    MerchantFrame:SetWidth(EXPANDED_WIDTH)
    isExpanded = true

    -- Hook updates to reposition items and handle repair buttons correctly
    if not Module.hooked then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", RepositionItems)
        hooksecurefunc("MerchantFrame_UpdateRepairButtons", RepositionSellAllJunkButton)
        Module.hooked = true
    end

    -- Immediate update
    RepositionItems()
    AdjustBottomElements()
    MerchantFrame_Update()
end

local function CollapseMerchantFrame()
    if not isExpanded then return end

    -- Hide extra buttons
    for i = ORIGINAL_PER_PAGE + 1, EXTENDED_PER_PAGE do
        local item = _G["MerchantItem" .. i]
        if item then item:Hide() end
    end

    -- Restore page size
    _G.MERCHANT_ITEMS_PER_PAGE = ORIGINAL_PER_PAGE

    -- Restore frame width
    if originalFrameWidth and MerchantFrame then
        MerchantFrame:SetWidth(originalFrameWidth)
    end

    -- Restore bottom elements
    RestoreBottomElements()

    isExpanded = false
    
    if MerchantFrame:IsShown() then
        MerchantFrame_Update()
    end
end

----------------------------------------------
-- Module Implementation
----------------------------------------------
function Module:OnMerchantShow()
    if InCombatLockdown() then return end
    -- Small delay to ensure frame is fully initialized
    C_Timer.After(0.05, function()
        ExpandMerchantFrame()
    end)
end

function Module:OnEnable()
    if MerchantFrame and MerchantFrame:IsShown() then
        ExpandMerchantFrame()
    end
end

function Module:OnDisable()
    CollapseMerchantFrame()
end

Module.eventMap = {
    MERCHANT_SHOW = function(self) self:OnMerchantShow() end,
    MERCHANT_UPDATE = function(self) self:OnMerchantShow() end,
    MERCHANT_CLOSED = function(self) CollapseMerchantFrame() end,
}
