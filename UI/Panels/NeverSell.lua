local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme

-- The never-sell list is items, so it is shown and edited as items: drop one on the slot or
-- type its ID, and every listed item is an icon that names itself on hover. A box of comma
-- separated numbers asked the player to look up IDs on a website first.
local SLOT, SLOT_ART, CHIP, CHIP_GAP, MAX_CHIPS = 30, 52, 30, 6, 48
local ID_WIDTH, ADD_WIDTH, LABEL_HEIGHT, EMPTY_HEIGHT = 116, 104, 18, 16
local ICON_CROP = 0.08

local function sortedIDs()
    local ids = {}
    for id in pairs(Settings:GetOption("neverSellIDs") or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function withChange(id, keep)
    local list = {}
    for existing in pairs(Settings:GetOption("neverSellIDs") or {}) do list[existing] = true end
    list[id] = keep or nil
    return list
end

-- Item IDs from whatever was typed or pasted: bare numbers, or item links.
function UI:ParseItemIDs(text)
    local ids = {}
    for id in (text or ""):gmatch("item:(%d+)") do ids[#ids + 1] = tonumber(id) end
    if #ids > 0 then return ids end
    local parsed = self:ParseNeverSell(text)
    if not parsed then return nil end
    for id in pairs(parsed) do ids[#ids + 1] = id end
    table.sort(ids)
    return #ids > 0 and ids or nil
end

-- Adds every ID in text to the list; returns whether anything was added.
function UI:AddNeverSell(text)
    local ids = self:ParseItemIDs(text)
    if not ids then
        self.sellStatus:SetText(L.UI_NEVER_SELL_INVALID)
        return false
    end
    local list = withChange(ids[1], true)
    for _, id in ipairs(ids) do list[id] = true end
    if not Settings:SetOption("neverSellIDs", list) then
        self.sellStatus:SetText(L.UI_NEVER_SELL_INVALID)
        return false
    end
    self.neverSellInput:SetText("")
    self.neverSellInput:ClearFocus()
    self.sellStatus:SetText(#ids == 1 and L.UI_NEVER_SELL_ADDED or string.format(L.UI_NEVER_SELL_ADDED_N, #ids))
    self:Refresh()
    return true
end

function UI:RemoveNeverSell(id)
    if Settings:SetOption("neverSellIDs", withChange(id, false)) then
        self.sellStatus:SetText("")
        if GameTooltip then GameTooltip:Hide() end
        self:Refresh()
    end
end

-- An item carried on the cursor is dropped on the slot; the cursor is cleared the way
-- Blizzard's own slots clear it, so the item goes back to the bag it came from.
function UI:AddFromCursor()
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or type(itemID) ~= "number" then return end
    ClearCursor()
    self:AddNeverSell(tostring(itemID))
end

local function chipEnter(chip)
    if not GameTooltip or not chip.itemID then return end
    GameTooltip:SetOwner(chip, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(chip.itemID)
    local r, g, b = unpack(Theme.colors.TEXT_MUTED)
    GameTooltip:AddLine(L.UI_NEVER_SELL_REMOVE, r, g, b)
    GameTooltip:Show()
end

local function chipLeave()
    if GameTooltip then GameTooltip:Hide() end
end

function UI:BuildSellSettings(parent)
    local block = self.Widgets:SettingsBlock(parent)
    local label = Theme:Text(block, L.UI_NEVER_SELL, "body", "TEXT_BODY")
    block:Place(label, LABEL_HEIGHT)
    block:Index(L.UI_NEVER_SELL, L.UI_NEVER_SELL_EMPTY)
    block:Note(L.UI_NEVER_SELL_HELP)

    local slot = CreateFrame("Button", nil, block)
    slot:SetSize(SLOT, SLOT)
    block:Place(slot, SLOT, self.Widgets.NOTE_GAP)
    slot.art = Theme:Texture(slot, "itemSlot", "BACKGROUND")
    slot.art:SetSize(SLOT_ART, SLOT_ART)
    slot.art:SetPoint("CENTER")
    local glow = Theme:Texture(slot, "listHover", "HIGHLIGHT")
    glow:SetAllPoints()
    slot:SetScript("OnReceiveDrag", function() self:AddFromCursor() end)
    slot:SetScript("OnClick", function() self:AddFromCursor() end)
    slot:SetScript("OnEnter", function(widget)
        if not GameTooltip then return end
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L.UI_NEVER_SELL_SLOT)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", chipLeave)
    self.neverSellSlot = slot

    self.neverSellInput = self.Widgets:Input(block, ID_WIDTH)
    self.neverSellInput:SetPoint("LEFT", slot, "RIGHT", 10, 0)
    self.neverSellInput:SetScript("OnEnterPressed", function(widget) self:AddNeverSell(widget:GetText()) end)
    local add = Theme:Button(block, ADD_WIDTH, L.UI_NEVER_SELL_ADD, function()
        self:AddNeverSell(self.neverSellInput:GetText())
    end)
    add:SetPoint("LEFT", self.neverSellInput, "RIGHT", 8, 0)
    self.sellStatus = Theme:Text(block, "", "small", "TEXT_TITLE")
    self.sellStatus:SetPoint("LEFT", add, "RIGHT", 12, 0)
    self.sellStatus:SetPoint("RIGHT")
    self.sellStatus:SetWordWrap(false)

    -- Every chip is made here, once; a list longer than the pool says how many it leaves out.
    self.neverSellChips = {}
    for index = 1, MAX_CHIPS do
        local chip = CreateFrame("Button", nil, block)
        chip:SetSize(CHIP, CHIP)
        chip:RegisterForClicks("RightButtonUp")
        chip.icon = chip:CreateTexture(nil, "ARTWORK")
        chip.icon:SetAllPoints()
        chip.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
        chip.border = Theme:Texture(chip, "itemBorder", "OVERLAY")
        chip.border:SetAllPoints()
        chip:SetScript("OnEnter", chipEnter)
        chip:SetScript("OnLeave", chipLeave)
        chip:SetScript("OnClick", function(widget) self:RemoveNeverSell(widget.itemID) end)
        chip:Hide()
        self.neverSellChips[index] = chip
    end
    self.neverSellEmpty = Theme:Text(block, L.UI_NEVER_SELL_EMPTY, "small", "TEXT_MUTED")
    self.neverSellMore = Theme:Text(block, "", "small", "TEXT_MUTED")
    block.chipsTop = block.cursor
    self.sellBlock = block
    self:LoadNeverSell()
    self:RegisterModuleSettings("vendor.autoSell", block)
end

-- The chips wrap to the block's width and the block grows with them, so it is re-measured
-- whenever the list is re-read; Refresh lays the list out after reading it.
function UI:LoadNeverSell()
    local block = self.sellBlock
    if not block then return end
    local ids = sortedIDs()
    local perRow = math.max(1, math.floor((block.width + CHIP_GAP) / (CHIP + CHIP_GAP)))
    local shown = math.min(#ids, MAX_CHIPS)
    for index, chip in ipairs(self.neverSellChips) do
        local id = ids[index]
        chip.itemID = index <= shown and id or nil
        chip:SetShown(chip.itemID ~= nil)
        if chip.itemID then
            local row, column = math.floor((index - 1) / perRow), (index - 1) % perRow
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", column * (CHIP + CHIP_GAP), block.chipsTop - row * (CHIP + CHIP_GAP))
            local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
            if icon then
                chip.icon:SetTexture(icon)
            else
                Theme:ApplyAsset(chip.icon, "unknownItem")
            end
            chip.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
            local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
            local r, g, b = 1, 1, 1
            if quality and C_Item.GetItemQualityColor then r, g, b = C_Item.GetItemQualityColor(quality) end
            chip.border:SetVertexColor(r or 1, g or 1, b or 1, 1)
        end
    end
    local rows = math.ceil(shown / perRow)
    local height = rows > 0 and rows * (CHIP + CHIP_GAP) - CHIP_GAP or EMPTY_HEIGHT
    self.neverSellEmpty:SetShown(#ids == 0)
    self.neverSellEmpty:ClearAllPoints()
    self.neverSellEmpty:SetPoint("TOPLEFT", 0, block.chipsTop)
    local hidden = #ids - shown
    self.neverSellMore:SetShown(hidden > 0)
    if hidden > 0 then
        self.neverSellMore:SetText(string.format(L.UI_NEVER_SELL_MORE, hidden))
        self.neverSellMore:ClearAllPoints()
        self.neverSellMore:SetPoint("TOPLEFT", 0, block.chipsTop - height - CHIP_GAP)
        height = height + CHIP_GAP + EMPTY_HEIGHT
    end
    block:SetBodyHeight(block.top - block.chipsTop + height)
end
