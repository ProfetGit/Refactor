local _, R = ...

-- Blizzard's merchant cell shows MAX_ITEM_COST (three) of an item's costs and greys every
-- one of them when the item as a whole is unaffordable. This fills the costs past three
-- into buttons of Blizzard's own template, greys each cost on its own shortfall, and puts
-- the items a merchant is priced in into the coin box at the bottom, next to the
-- currencies Blizzard already shows there, with how many the player carries.
local CELL_PREFIX, MAX_CELLS = "MerchantItem", 40
-- ItemExtendedCost carries up to five item and five currency entries; five shown is every
-- cost seen on a live vendor and keeps the extra buttons to two per cell.
local MAX_COSTS = 5
local COST_TEMPLATE, COST_GAP = "SmallDenominationTemplate", 4
-- Blizzard's MAX_MONEY_DISPLAY_WIDTH, a local in MerchantFrame.lua: the room a cell gives
-- the money and the costs together. A row past it is scaled down rather than clipped.
local ROW_BUDGET, MIN_SCALE = 120, 0.6
-- The coin box. Blizzard keeps two boxes along the bottom, currencies right and money
-- left, and hides the money past three currencies. Here the left box is stretched into
-- one strip and everything chains leftwards from the money: Blizzard's currency tokens,
-- then the items, for as long as the width holds. Numbers are Blizzard's own anchors.
local TOKEN_TEMPLATE, TOKEN_PREFIX, BLIZZARD_TOKEN = "BackpackTokenTemplate", "RefactorMerchantToken", "MerchantToken"
local TOKEN_WIDTH, TOKEN_COUNT_CAP = 50, 99999
local STRIP_INSET_X, STRIP_INSET_BOTTOM, STRIP_INSET_TOP = 4, 4, 27
local STRIP_BG_X, STRIP_BG_BOTTOM, STRIP_BG_TOP = 7, 6, 25
local MONEY_X, MONEY_Y, MONEY_GAP, STRIP_MARGIN = -8, 8, 6, 12

local extras = {}

-- Called for a cell by whichever builder creates it, so a cell has its extra cost buttons
-- whether the costs module or the grid module enabled first.
function R.UI:PrepareMerchantCostRow(index)
    if extras[index] then return extras[index] end
    local altName = CELL_PREFIX .. index .. "AltCurrencyFrame"
    local alt = _G[altName]
    if not alt then return nil end
    local buttons = {}
    for cost = MAX_ITEM_COST + 1, MAX_COSTS do
        local button = CreateFrame("Button", altName .. "Item" .. cost, alt, COST_TEMPLATE)
        button:SetPoint("LEFT", _G[altName .. "Item" .. (cost - 1)], "RIGHT", COST_GAP, 0)
        button:Hide()
        R:OwnFrame(button)
        buttons[cost] = button
    end
    extras[index] = buttons
    return buttons
end

-- nil means it cannot be told, which is not the same as short.
local function affordable(link, value, currencyName)
    if currencyName then
        local info = link and C_CurrencyInfo.GetCurrencyInfoFromLink(link)
        local owned = info and info.quantity
        if type(owned) ~= "number" then return nil end
        return owned >= value
    end
    if not link then return nil end
    return C_Item.GetItemCount(link) >= value
end

local function capturePoints(frame)
    local saved = {}
    for index = 1, 2 do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        if not point then break end
        saved[index] = { point, relativeTo, relativePoint, x, y }
    end
    return saved
end

local function restorePoints(frame, saved)
    frame:ClearAllPoints()
    for _, point in ipairs(saved) do
        frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
    end
end

local function tokenEnter(token)
    if token.itemLink and GameTooltip then
        GameTooltip:SetOwner(token, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(token.itemLink)
        GameTooltip:Show()
    end
end

local function tokenLeave()
    if GameTooltip then GameTooltip:Hide() end
end

-- Every item, as opposed to currency, the merchant's stock is priced in, once each in the
-- order first seen. Entries are reused; the count says how many are live.
local function collectCostItems(list)
    local seen, count = {}, 0
    for index = 1, GetMerchantNumItems() do
        for cost = 1, math.min(GetMerchantItemCostInfo(index) or 0, MAX_COSTS) do
            local texture, _, link, currencyName = GetMerchantItemCostItem(index, cost)
            local itemID = not currencyName and link and tonumber(link:match("item:(%d+)"))
            if itemID and not seen[itemID] then
                seen[itemID] = true
                count = count + 1
                local entry = list[count] or {}
                entry.texture, entry.link = texture, link
                list[count] = entry
            end
        end
    end
    return count
end

function R.UI:CreateMerchantCosts(owner)
    if owner.refactorMerchantCosts then return owner.refactorMerchantCosts end
    local costs = { active = false, verdicts = {}, items = {}, tokens = {}, blizzardTokens = {} }
    for index = 1, MAX_CELLS do
        self:PrepareMerchantCostRow(index)
    end
    -- Blizzard's own anchors for the strip, put back on disable. Its currency tokens are
    -- made lazily, so theirs are kept as each is first seen.
    costs.original = {
        inset = capturePoints(MerchantExtraCurrencyInset), background = capturePoints(MerchantExtraCurrencyBg),
        money = capturePoints(MerchantMoneyFrame),
    }
    for slot = 1, MAX_MERCHANT_CURRENCIES do
        local token = CreateFrame("Button", TOKEN_PREFIX .. slot, MerchantFrame, TOKEN_TEMPLATE)
        -- The template's scripts are for a currency: they would ask the tooltip for a
        -- backpack token and open the currency tab on click.
        token:SetScript("OnEnter", tokenEnter)
        token:SetScript("OnLeave", tokenLeave)
        token:SetScript("OnClick", nil)
        token:Hide()
        R:OwnFrame(token)
        costs.tokens[slot] = token
    end

    local function reset(cellIndex)
        for _, button in pairs(extras[cellIndex] or {}) do
            button:Hide()
        end
        local alt = _G[CELL_PREFIX .. cellIndex .. "AltCurrencyFrame"]
        if alt then alt:SetScale(1) end
    end

    -- Blizzard's verdict on the whole item decides whether anything greys. What greys is
    -- each cost's own shortfall; when none can be told, all of them, as Blizzard does.
    local function updateCell(cellIndex, index)
        local altName = CELL_PREFIX .. cellIndex .. "AltCurrencyFrame"
        local alt, info = _G[altName], C_MerchantFrame.GetItemInfo(index)
        local count = math.min(GetMerchantItemCostInfo(index) or 0, MAX_COSTS)
        if not alt or not info or not info.hasExtendedCost or count == 0 then
            reset(cellIndex)
            return
        end
        local canAfford = CanAffordMerchantItem(index) ~= false
        local price = info.price or 0
        local moneyOK = price <= 0 or GetMoney() >= price
        local verdicts, anyShort = costs.verdicts, price > 0 and not moneyOK
        for cost = 1, count do
            local _, value, link, currencyName = GetMerchantItemCostItem(index, cost)
            verdicts[cost] = affordable(link, value or 0, currencyName)
            if verdicts[cost] == false then anyShort = true end
        end
        local used, width = 0, 0
        for cost = 1, count do
            local texture, value, link = GetMerchantItemCostItem(index, cost)
            if texture then
                used = used + 1
                local buttonName = altName .. "Item" .. used
                local button = _G[buttonName]
                if button then
                    button.index, button.item, button.itemLink = index, cost, link
                    local white = canAfford or (anyShort and verdicts[cost] ~= false)
                    AltCurrencyFrame_Update(buttonName, texture, value, white)
                    button:Show()
                    width = width + button:GetWidth() + (used > 1 and COST_GAP or 0)
                end
            end
        end
        for cost = used + 1, MAX_COSTS do
            local button = _G[altName .. "Item" .. cost]
            if button then button:Hide() end
        end
        local moneyName = CELL_PREFIX .. cellIndex .. "MoneyFrame"
        local money, moneyWidth = _G[moneyName], 0
        if price > 0 and money then
            -- Blizzard sized the money for three costs; with more it has less room and
            -- drops silver and copper the way it already does for a wide price.
            if used > MAX_ITEM_COST then
                MoneyFrame_SetMaxDisplayWidth(money, math.max(0, ROW_BUDGET - width))
                MoneyFrame_Update(moneyName, price)
            end
            local grey = not (canAfford or (anyShort and moneyOK))
            SetMoneyFrameColor(moneyName, grey and "gray" or nil)
            moneyWidth = money:GetWidth()
        end
        local scale = 1
        if width > 0 and width + moneyWidth > ROW_BUDGET then
            scale = math.max(MIN_SCALE, (ROW_BUDGET - moneyWidth) / width)
        end
        alt:SetScale(scale)
    end

    local function hideTokens()
        for _, token in ipairs(costs.tokens) do
            token.itemLink, token.slot = nil, nil
            token:Hide()
        end
    end

    local function chain(token, previous, gap)
        token:ClearAllPoints()
        if previous then
            token:SetPoint("RIGHT", previous, "LEFT", -gap, 0)
        else
            token:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -STRIP_MARGIN, MONEY_Y)
        end
    end

    -- Blizzard's left box becomes the whole strip; its right box, the money's, goes.
    local function stretchStrip()
        local frame = MerchantFrame
        MerchantExtraCurrencyInset:ClearAllPoints()
        MerchantExtraCurrencyInset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", STRIP_INSET_X, STRIP_INSET_BOTTOM)
        MerchantExtraCurrencyInset:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -STRIP_INSET_X - 1, STRIP_INSET_TOP)
        MerchantExtraCurrencyInset:Show()
        MerchantExtraCurrencyBg:ClearAllPoints()
        MerchantExtraCurrencyBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", STRIP_BG_X, STRIP_BG_BOTTOM)
        MerchantExtraCurrencyBg:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -STRIP_BG_X, STRIP_BG_TOP)
        MerchantExtraCurrencyBg:Show()
        MerchantMoneyInset:Hide()
        MerchantMoneyBg:Hide()
    end

    -- Money at the right, unless Blizzard's own tokens leave it no room, in which case
    -- it gives way as it does in Blizzard's layout. Then Blizzard's tokens in Blizzard's
    -- order, then the items, each as long as it still fits inside the strip.
    local function updateCoinBox()
        local frame, money = MerchantFrame, MerchantMoneyFrame
        stretchStrip()
        local room = frame:GetWidth() - STRIP_MARGIN * 2
        local blizzard, blizzardWidth = 0, 0
        for slot = 1, MAX_MERCHANT_CURRENCIES do
            local token = _G[BLIZZARD_TOKEN .. slot]
            if not token or not token:IsShown() then break end
            blizzard, blizzardWidth = slot, blizzardWidth + token:GetWidth()
        end
        local previous
        if blizzardWidth + money:GetWidth() + MONEY_GAP <= room then
            money:ClearAllPoints()
            money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", MONEY_X, MONEY_Y)
            money:Show()
            previous, room = money, room - money:GetWidth() - MONEY_GAP
        else
            money:Hide()
        end
        for slot = 1, blizzard do
            local token = _G[BLIZZARD_TOKEN .. slot]
            if not costs.blizzardTokens[token] then
                costs.blizzardTokens[token] = capturePoints(token)
            end
            chain(token, previous, previous == money and MONEY_GAP or 0)
            previous, room = token, room - token:GetWidth()
        end
        local count = collectCostItems(costs.items)
        for i, token in ipairs(costs.tokens) do
            if i <= count and room >= TOKEN_WIDTH then
                local entry = costs.items[i]
                chain(token, previous, previous == money and MONEY_GAP or 0)
                token.itemLink, token.slot = entry.link, blizzard + i
                token.Icon:SetTexture(entry.texture)
                local owned = C_Item.GetItemCount(entry.link)
                token.Count:SetText(owned > TOKEN_COUNT_CAP and "*" or owned)
                token:Show()
                previous, room = token, room - TOKEN_WIDTH
            else
                token.itemLink, token.slot = nil, nil
                token:Hide()
            end
        end
    end

    -- Which item a cell holds is read off its item button: the merchant filter lays pages
    -- out in its own order, and Blizzard sets the same ID on the same button.
    function costs:Refresh()
        if not self.active then return end
        updateCoinBox()
        if MerchantFrame.selectedTab ~= 1 then return end
        for cellIndex = 1, MERCHANT_ITEMS_PER_PAGE do
            local itemButton = _G[CELL_PREFIX .. cellIndex .. "ItemButton"]
            if itemButton then
                if itemButton.hasItem and itemButton:IsShown() then
                    updateCell(cellIndex, itemButton:GetID())
                else
                    reset(cellIndex)
                end
            end
        end
    end

    function costs:Apply()
        self.active = true
        if MerchantFrame:IsShown() then self:Refresh() end
    end

    -- Blizzard's own passes restore its colours and money widths. The strip, the money
    -- and its tokens go back to the anchors they had, and its currency pass then shows
    -- and hides the boxes by its own rule.
    function costs:Restore()
        if not self.active then return end
        self.active = false
        for cellIndex in pairs(extras) do
            reset(cellIndex)
        end
        hideTokens()
        local original = self.original
        restorePoints(MerchantExtraCurrencyInset, original.inset)
        restorePoints(MerchantExtraCurrencyBg, original.background)
        restorePoints(MerchantMoneyFrame, original.money)
        MerchantMoneyInset:Show()
        MerchantMoneyBg:Show()
        for token, points in pairs(self.blizzardTokens) do
            restorePoints(token, points)
        end
        if MerchantFrame:IsShown() then
            MerchantFrame_UpdateCurrencies()
            MerchantFrame_Update()
        end
    end

    hooksecurefunc("MerchantFrame_Update", function() costs:Refresh() end)
    owner.refactorMerchantCosts = costs
    return costs
end
