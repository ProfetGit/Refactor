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
-- The coin box: Blizzard's token slots run 6 5 4 in the left box and 3 2 1 in the right,
-- slot one against the right edge and slot four at x 89. Past three tokens the money
-- frame gives way; with any token at all it moves into the left box.
local TOKEN_TEMPLATE, TOKEN_PREFIX, BLIZZARD_TOKEN = "BackpackTokenTemplate", "RefactorMerchantToken", "MerchantToken"
local TOKEN_WIDTH, TOKEN_Y, TOKEN_RIGHT_X, TOKEN_LEFT_X, LEFT_BOX_FIRST = 50, 8, -16, 89, 4
local MONEY_SLOTS, MONEY_SHARED_X, TOKEN_COUNT_CAP = 3, -169, 99999

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
    local costs = { active = false, verdicts = {}, items = {}, tokens = {} }
    for index = 1, MAX_CELLS do
        self:PrepareMerchantCostRow(index)
    end
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

    -- Item tokens take the slots after Blizzard's currency tokens, chained onto them the
    -- way Blizzard chains its own, and the money frame follows Blizzard's rule for the
    -- whole row rather than for its currencies alone.
    local function placeToken(token, slot, previous)
        token:ClearAllPoints()
        if slot == 1 then
            token:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", TOKEN_RIGHT_X, TOKEN_Y)
        elseif slot == LEFT_BOX_FIRST then
            token:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", TOKEN_LEFT_X, TOKEN_Y)
        elseif previous then
            token:SetPoint("RIGHT", previous, "LEFT", 0, 0)
        elseif slot < LEFT_BOX_FIRST then
            token:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT",
                TOKEN_RIGHT_X - TOKEN_WIDTH * (slot - 1), TOKEN_Y)
        else
            token:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT",
                TOKEN_LEFT_X - TOKEN_WIDTH * (slot - LEFT_BOX_FIRST), TOKEN_Y)
        end
    end

    local function updateCoinBox()
        local currencies = C_MerchantFrame.GetMerchantCurrencies() or {}
        local numCurrencies = math.min(#currencies, MAX_MERCHANT_CURRENCIES)
        local shown = math.min(collectCostItems(costs.items), MAX_MERCHANT_CURRENCIES - numCurrencies)
        for i, token in ipairs(costs.tokens) do
            if i <= shown then
                local entry, slot = costs.items[i], numCurrencies + i
                placeToken(token, slot, i > 1 and costs.tokens[i - 1] or _G[BLIZZARD_TOKEN .. (slot - 1)])
                token.itemLink, token.slot = entry.link, slot
                token.Icon:SetTexture(entry.texture)
                local owned = C_Item.GetItemCount(entry.link)
                token.Count:SetText(owned > TOKEN_COUNT_CAP and "*" or owned)
                token:Show()
            else
                token.itemLink, token.slot = nil, nil
                token:Hide()
            end
        end
        if shown == 0 then return end
        MerchantExtraCurrencyInset:Show()
        MerchantExtraCurrencyBg:Show()
        if numCurrencies + shown > MONEY_SLOTS then
            MerchantMoneyFrame:Hide()
        else
            MerchantMoneyFrame:SetPoint("BOTTOMRIGHT", MONEY_SHARED_X, TOKEN_Y)
            MerchantMoneyFrame:Show()
        end
    end

    -- Runs after Blizzard's own pass over the page, so every cell it touched is redone
    -- with the same calls it made, and the two extra buttons on top. The coin box is set
    -- at MERCHANT_SHOW before that pass and so is always redone here last.
    function costs:Refresh()
        if not self.active then return end
        updateCoinBox()
        if MerchantFrame.selectedTab ~= 1 then return end
        local perPage, total = MERCHANT_ITEMS_PER_PAGE, GetMerchantNumItems()
        for cellIndex = 1, perPage do
            if _G[CELL_PREFIX .. cellIndex] then
                local index = (MerchantFrame.page - 1) * perPage + cellIndex
                if index <= total then
                    updateCell(cellIndex, index)
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

    -- Blizzard's own passes restore its colours, money widths and coin box; only the
    -- extra buttons and the item tokens are ours to hide.
    function costs:Restore()
        if not self.active then return end
        self.active = false
        for cellIndex in pairs(extras) do
            reset(cellIndex)
        end
        hideTokens()
        if MerchantFrame:IsShown() then
            MerchantFrame_UpdateCurrencies()
            MerchantFrame_Update()
        end
    end

    hooksecurefunc("MerchantFrame_Update", function() costs:Refresh() end)
    owner.refactorMerchantCosts = costs
    return costs
end
