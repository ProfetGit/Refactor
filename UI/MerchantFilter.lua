local _, R = ...

-- A dropdown in Blizzard's merchant window, beside Blizzard's own class filter, that
-- narrows the stock to a kind of item and to whether it is already in the player's
-- collection. Blizzard fills cells by position from its own page arithmetic, so a filter
-- has to page for itself: after Blizzard's pass the matching stock is laid out again from
-- the first cell, page by page, with the same calls Blizzard's pass makes (MerchantFrame.lua
-- at 12.1.0, MerchantFrame_UpdateMerchantInfo). With no filter set, Blizzard's pass stands.
local CELL_PREFIX = "MerchantItem"
-- Cost buttons a cell can carry: Blizzard's MAX_ITEM_COST plus the two the costs module adds.
local MAX_COST_BUTTONS = 5
-- Fits between the portrait and Blizzard's 152 px class filter in the stock 336 px window.
local DROPDOWN_WIDTH, DROPDOWN_GAP = 100, -6
-- Blizzard's MAX_MONEY_DISPLAY_WIDTH, a local in MerchantFrame.lua.
local MONEY_WIDTH = 120
local CATEGORIES = { "all", "mounts", "pets", "toys", "appearances", "recipes", "other" }
local COLLECTION = { "any", "owned", "missing" }
local CATEGORY_KEYS = {
    all = "VENDOR_FILTER_ALL", mounts = "VENDOR_FILTER_MOUNTS", pets = "VENDOR_FILTER_PETS",
    toys = "VENDOR_FILTER_TOYS", appearances = "VENDOR_FILTER_APPEARANCES",
    recipes = "VENDOR_FILTER_RECIPES", other = "VENDOR_FILTER_OTHER",
}
local COLLECTION_KEYS = { any = "VENDOR_FILTER_ANY", owned = "VENDOR_FILTER_OWNED", missing = "VENDOR_FILTER_MISSING" }
-- What kind of thing an item is never changes, so this cache is permanent on purpose.
local categories = {}
local MOUNT_COLLECTED_RETURN, PET_SPECIES_RETURN = 11, 13

local function classify(itemID, link)
    local known = categories[itemID]
    if known then return known end
    local category = "other"
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if link:find("battlepet:", 1, true) then
        category = "pets"
    elseif C_MountJournal.GetMountFromItem(itemID) then
        category = "mounts"
    elseif classID == Enum.ItemClass.Miscellaneous and subClassID == Enum.ItemMiscellaneousSubclass.CompanionPet
        or C_PetJournal.GetPetInfoByItemID(itemID) then
        category = "pets"
    elseif C_ToyBox.GetToyInfo(itemID) then
        category = "toys"
    elseif classID == Enum.ItemClass.Recipe then
        category = "recipes"
    elseif (classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon)
        and C_TransmogCollection.GetItemInfo(itemID) then
        category = "appearances"
    end
    categories[itemID] = category
    return category
end

-- Blizzard's tints for a cell, in its order: name plate, slot, icon, icon frame.
local function tint(cell, itemButton, nameR, nameG, nameB, slotR, slotG, slotB, iconR, iconG, iconB)
    SetItemButtonNameFrameVertexColor(cell, nameR, nameG, nameB)
    SetItemButtonSlotVertexColor(cell, slotR, slotG, slotB)
    SetItemButtonTextureVertexColor(itemButton, iconR, iconG, iconB)
    SetItemButtonNormalTextureVertexColor(itemButton, iconR, iconG, iconB)
end

local function emptyCell(cellIndex)
    local name = CELL_PREFIX .. cellIndex
    local cell, itemButton = _G[name], _G[name .. "ItemButton"]
    if not cell or not itemButton then return end
    itemButton.price, itemButton.hasItem, itemButton.name = nil, nil, nil
    itemButton:Hide()
    SetItemButtonNameFrameVertexColor(cell, 0.5, 0.5, 0.5)
    SetItemButtonSlotVertexColor(cell, 0.4, 0.4, 0.4)
    _G[name .. "Name"]:SetText("")
    _G[name .. "MoneyFrame"]:Hide()
    local alt = _G[name .. "AltCurrencyFrame"]
    alt:Hide()
    alt:SetScale(1)
    for cost = 1, MAX_COST_BUTTONS do
        local button = _G[name .. "AltCurrencyFrameItem" .. cost]
        if button then button:Hide() end
    end
end

-- One cell filled with one merchant index, the way Blizzard's pass fills it. The fields
-- on the item button are what Blizzard's click, drag and confirmation code reads back.
local function fillCell(cellIndex, index)
    local name = CELL_PREFIX .. cellIndex
    local cell, itemButton = _G[name], _G[name .. "ItemButton"]
    local info = cell and itemButton and C_MerchantFrame.GetItemInfo(index)
    if not info then
        emptyCell(cellIndex)
        return
    end
    local moneyName, money, alt = name .. "MoneyFrame", _G[name .. "MoneyFrame"], _G[name .. "AltCurrencyFrame"]
    if info.currencyID then
        info.name, info.texture, info.numAvailable = CurrencyContainerUtil.GetCurrencyContainerInfo(
            info.currencyID, info.numAvailable, info.name, info.texture, nil)
    end
    local canAfford = CanAffordMerchantItem(index)
    _G[name .. "Name"]:SetText(info.name)
    SetItemButtonCount(itemButton, info.stackCount)
    SetItemButtonStock(itemButton, info.numAvailable)
    SetItemButtonTexture(itemButton, info.texture)
    local link = GetMerchantItemLink(index)
    itemButton.name, itemButton.link, itemButton.texture = info.name, link, info.texture
    local color = canAfford == false and "gray" or nil
    if info.hasExtendedCost and info.price <= 0 then
        itemButton.price, itemButton.extendedCost = nil, true
        MerchantFrame_UpdateAltCurrency(index, cellIndex, canAfford)
        alt:ClearAllPoints()
        alt:SetPoint("BOTTOMLEFT", name .. "NameFrame", "BOTTOMLEFT", 0, 31)
        money:Hide()
        alt:Show()
    elseif info.hasExtendedCost then
        itemButton.price, itemButton.extendedCost = info.price, true
        local altWidth = MerchantFrame_UpdateAltCurrency(index, cellIndex, canAfford)
        MoneyFrame_SetMaxDisplayWidth(money, MONEY_WIDTH - altWidth)
        MoneyFrame_Update(moneyName, info.price)
        SetMoneyFrameColor(moneyName, color)
        alt:ClearAllPoints()
        alt:SetPoint("LEFT", moneyName, "RIGHT", -14, 0)
        alt:Show()
        money:Show()
    else
        itemButton.price, itemButton.extendedCost = info.price, nil
        MoneyFrame_SetMaxDisplayWidth(money, MONEY_WIDTH)
        MoneyFrame_Update(moneyName, info.price)
        SetMoneyFrameColor(moneyName, color)
        alt:Hide()
        money:Show()
    end
    if info.isQuestStartItem then
        itemButton.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
        itemButton.IconQuestTexture:Show()
    else
        itemButton.IconQuestTexture:Hide()
    end
    MerchantFrameItem_UpdateQuality(cell, link)
    local itemID = GetMerchantItemID(index)
    local isHeirloom = itemID and C_Heirloom.IsItemHeirloom(itemID)
    local isKnownHeirloom = isHeirloom and C_Heirloom.PlayerHasHeirloom(itemID)
    itemButton.showNonrefundablePrompt = not C_MerchantFrame.IsMerchantItemRefundable(index)
    itemButton.hasItem = true
    itemButton:SetID(index)
    itemButton:Show()
    local tintRed = not info.isPurchasable or (not info.isUsable and not isHeirloom)
    SetItemButtonDesaturated(itemButton, isKnownHeirloom)
    if info.numAvailable == 0 or isKnownHeirloom then
        if tintRed then
            tint(cell, itemButton, 0.5, 0, 0, 0.5, 0, 0, 0.5, 0, 0)
        else
            tint(cell, itemButton, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
        end
    elseif tintRed then
        tint(cell, itemButton, 1, 0, 0, 1, 0, 0, 0.9, 0, 0)
    else
        tint(cell, itemButton, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1, 1)
    end
end

local function tokenPaging(count, page, pages, perPage)
    if count > perPage then
        MerchantPrevPageButton:SetEnabled(page > 1)
        MerchantNextPageButton:SetEnabled(page < pages)
        MerchantPageText:SetText(string.format(MERCHANT_PAGE_NUMBER, page, pages))
        MerchantPageText:Show()
        MerchantPrevPageButton:Show()
        MerchantNextPageButton:Show()
    else
        MerchantPageText:Hide()
        MerchantPrevPageButton:Hide()
        MerchantNextPageButton:Hide()
    end
end

function R.UI:CreateMerchantFilter(owner)
    if owner.refactorMerchantFilter then return owner.refactorMerchantFilter end
    local filter = { active = false, category = "all", collection = "any", matches = {}, recipes = {} }
    local frame = MerchantFrame
    local button = R.Theme:DropdownButton(frame)
    if not button then
        error("merchant filter needs Blizzard's dropdown template")
    end
    button:SetWidth(DROPDOWN_WIDTH)
    if frame.FilterDropdown then
        button:SetPoint("RIGHT", frame.FilterDropdown, "LEFT", DROPDOWN_GAP, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -11, -30)
    end
    button:Hide()
    R:OwnFrame(button)
    filter.button = button

    -- true or false for a collectible, nil for anything with no collection to be in.
    -- Mounts, pets, toys and appearances are read fresh: learning one fires a bag update
    -- and Blizzard redraws on that. A recipe means building its tooltip, so that answer is
    -- kept for the visit and dropped on NEW_RECIPE_LEARNED and on the next merchant.
    local function collected(index, itemID, link, category)
        if category == "mounts" then
            local mountID = C_MountJournal.GetMountFromItem(itemID)
            return mountID and select(MOUNT_COLLECTED_RETURN, C_MountJournal.GetMountInfoByID(mountID)) == true
                or false
        elseif category == "pets" then
            local speciesID = select(PET_SPECIES_RETURN, C_PetJournal.GetPetInfoByItemID(itemID))
            if not speciesID then return nil end
            return (C_PetJournal.GetNumCollectedInfo(speciesID) or 0) > 0
        elseif category == "toys" then
            return PlayerHasToy(itemID) == true
        elseif category == "appearances" then
            return C_TransmogCollection.PlayerHasTransmogByItemInfo(link) == true
        elseif category == "recipes" then
            local known = filter.recipes[itemID]
            if known == nil then
                known = false
                local tooltip = C_TooltipInfo.GetMerchantItem(index)
                for _, line in ipairs(tooltip and tooltip.lines or {}) do
                    if line.leftText == ITEM_SPELL_KNOWN then known = true end
                end
                filter.recipes[itemID] = known
            end
            return known
        end
        return nil
    end

    function filter:IsNarrowing()
        return self.active and (self.category ~= "all" or self.collection ~= "any")
    end

    function filter:Text()
        local category, state = R.L[CATEGORY_KEYS[self.category]], R.L[COLLECTION_KEYS[self.collection]]
        if self.collection == "any" then return category end
        if self.category == "all" then return state end
        return string.format(R.L.VENDOR_FILTER_BOTH, category, state)
    end

    function filter:Matches(index)
        local link = GetMerchantItemLink(index)
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if not itemID then return true end
        local category = classify(itemID, link)
        if self.category ~= "all" and category ~= self.category then return false end
        if self.collection == "any" then return true end
        local owned = collected(index, itemID, link, category)
        if owned == nil then return false end
        return owned == (self.collection == "owned")
    end

    -- The merchant indices that pass, in stock order. The table is reused.
    function filter:Collect()
        local matches, count = self.matches, 0
        for index = 1, GetMerchantNumItems() do
            if self:Matches(index) then
                count = count + 1
                matches[count] = index
            end
        end
        for extra = count + 1, #matches do
            matches[extra] = nil
        end
        return count
    end

    -- After Blizzard's pass: lay the matching stock out again from the first cell, on
    -- pages of its own count, and put the page controls to those pages. Blizzard's own
    -- prev and next buttons still move MerchantFrame.page and redraw, which lands here.
    function filter:Apply()
        if not self:IsNarrowing() or frame.selectedTab ~= 1 then return end
        local perPage, count = MERCHANT_ITEMS_PER_PAGE, self:Collect()
        local pages = math.max(1, math.ceil(count / perPage))
        if frame.page > pages then
            frame.page = pages -- luacheck: ignore 122
        end
        local first = (frame.page - 1) * perPage
        for cellIndex = 1, perPage do
            local index = self.matches[first + cellIndex]
            if index then
                fillCell(cellIndex, index)
            else
                emptyCell(cellIndex)
            end
        end
        tokenPaging(count, frame.page, pages, perPage)
        R.Broker:Emit("REFACTOR_MERCHANT_FILTERED")
    end

    -- Quality colours arrive late for uncached items and Blizzard reapplies them by its
    -- own page arithmetic; the cells say which item they hold.
    function filter:ReapplyQuality()
        if not self:IsNarrowing() or frame.selectedTab ~= 1 then return end
        for cellIndex = 1, MERCHANT_ITEMS_PER_PAGE do
            local cell, itemButton = _G[CELL_PREFIX .. cellIndex], _G[CELL_PREFIX .. cellIndex .. "ItemButton"]
            if cell and itemButton and itemButton.hasItem then
                MerchantFrameItem_UpdateQuality(cell, GetMerchantItemLink(itemButton:GetID()))
            end
        end
    end

    -- A change of filter redraws through Blizzard's full pass, the path a change of its
    -- own class filter takes: its pass resets every cell, and the hook lays the page out
    -- again on top when the filter is on.
    function filter:Refresh()
        self.button:SetDefaultText(self:Text())
        self.button:GenerateMenu()
        if frame:IsShown() then MerchantFrame_Update() end
    end

    function filter:Set(category, collection)
        self.category, self.collection = category or self.category, collection or self.collection
        self:Refresh()
    end

    function filter:ForgetRecipes()
        for itemID in pairs(self.recipes) do
            self.recipes[itemID] = nil
        end
    end

    -- Back to everything on each visit, the way Blizzard resets its own filter: a filter
    -- left on from a mount vendor would empty the next food vendor without a word.
    function filter:Reset()
        self:ForgetRecipes()
        self:Set("all", "any")
    end

    button:SetupMenu(function(_, root)
        root:CreateTitle(R.L.VENDOR_FILTER_SHOW)
        for _, category in ipairs(CATEGORIES) do
            root:CreateRadio(R.L[CATEGORY_KEYS[category]], function(value) return filter.category == value end,
                function(value) filter:Set(value, nil) end, category)
        end
        root:CreateDivider()
        root:CreateTitle(R.L.VENDOR_FILTER_COLLECTION)
        for _, state in ipairs(COLLECTION) do
            root:CreateRadio(R.L[COLLECTION_KEYS[state]], function(value) return filter.collection == value end,
                function(value) filter:Set(nil, value) end, state)
        end
    end)

    function filter:Enable()
        self.active = true
        self.button:Show()
        self:Reset()
    end

    function filter:Disable()
        if not self.active then return end
        self.category, self.collection = "all", "any"
        self.active = false
        self.button:Hide()
        self:ForgetRecipes()
        if frame:IsShown() then MerchantFrame_Update() end
    end

    hooksecurefunc("MerchantFrame_Update", function() filter:Apply() end)
    hooksecurefunc("MerchantFrame_UpdateItemQualityBorders", function() filter:ReapplyQuality() end)
    owner.refactorMerchantFilter = filter
    return filter
end
