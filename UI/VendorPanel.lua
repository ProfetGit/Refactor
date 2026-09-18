local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

local ROWS, ROW_HEIGHT, WIDTH = 14, 26, 340

local function moneyText(amount)
    return string.format(R.L.MONEY_TEXT, math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

-- A one-line readout under the merchant window. Refactor's own frame, anchored to
-- Blizzard's, never a change to it.
function R.UI:CreateJunkReadout(owner)
    if owner.refactorJunkReadout then return owner.refactorJunkReadout end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(300, 26)
    frame:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 8, -2)
    frame:SetFrameStrata("HIGH")
    Theme:Panel(frame, true)
    R:OwnFrame(frame)
    frame.text = Theme:Text(frame, "", "small", "TEXT_BODY")
    frame.text:SetPoint("LEFT", 10, 0)
    frame.text:SetPoint("RIGHT", -10, 0)
    function frame:SetText(text) self.text:SetText(text) end
    frame:Hide()
    owner.refactorJunkReadout = frame
    return frame
end

local function row(parent, onClick, onEnter)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(ROW_HEIGHT)
    button:RegisterForClicks("LeftButtonUp")
    Theme:Fill(button, "ROW_BG")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    button.icon:SetPoint("LEFT", 2, 0)
    button.name = Theme:Text(button, "", "small", "TEXT_BODY")
    button.name:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
    button.name:SetPoint("RIGHT", -104, 0)
    button.price = Theme:Text(button, "", "small", "TEXT_MUTED")
    button.price:SetPoint("RIGHT", -6, 0)
    button.price:SetWidth(96)
    button.price:SetJustifyH("RIGHT")
    local highlight = Theme:Texture(button, "buttonHighlight", "HIGHLIGHT")
    highlight:SetAllPoints()
    button:SetHighlightTexture(highlight)
    button:SetScript("OnClick", function(widget) onClick(widget) end)
    button:SetScript("OnEnter", function(widget) onEnter(widget) end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    function button:SetItem(item, r, g, b)
        self.item = item
        self.icon:SetTexture(item.texture)
        local label = item.name or ""
        if item.stackCount and item.stackCount > 1 then
            label = string.format(R.L.TOAST_COUNT, label, item.stackCount)
        end
        self.name:SetText(label)
        self.name:SetTextColor(r or 1, g or 1, b or 1, 1)
        self.price:SetText(moneyText(item.price or 0))
        self:Show()
    end
    button:Hide()
    return button
end

function R.UI:CreateVendorPanel(owner)
    if owner.refactorVendorPanel then return owner.refactorVendorPanel end
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(WIDTH, 64 + ROWS * ROW_HEIGHT + 4 * ROW_HEIGHT + 60)
    panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
    panel:SetFrameStrata("HIGH")
    Theme:Panel(panel)
    R:OwnFrame(panel)
    local title = Theme:Text(panel, R.L.VENDOR_UI_TITLE, "body", "TEXT_TITLE")
    title:SetPoint("TOPLEFT", 18, -16)
    panel.search = self.Widgets:Input(panel, WIDTH - 36, 28)
    panel.search:SetPoint("TOPLEFT", 18, -40)
    panel.search.placeholder = Theme:Text(panel.search, R.L.VENDOR_UI_SEARCH, "small", "TEXT_MUTED")
    panel.search.placeholder:SetPoint("LEFT", 10, 0)
    panel.search:SetScript("OnTextChanged", function(widget)
        widget.placeholder:SetShown(widget:GetText() == "")
        panel.offset = 0
        owner:Refresh()
    end)
    panel.usable = Theme:Checkbox(panel, 150, R.L.VENDOR_UI_USABLE, function() panel.offset = 0; owner:Refresh() end)
    panel.usable:SetPoint("TOPLEFT", 18, -74)
    local hint = Theme:Text(panel, R.L.VENDOR_UI_HINT, "small", "TEXT_MUTED")
    hint:SetPoint("LEFT", panel.usable, "RIGHT", 120, 0)
    hint:SetPoint("RIGHT", -18, 0)
    hint:SetJustifyH("RIGHT")

    local function enter(widget)
        if GameTooltip and widget.item then
            GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
            if widget.buyback then GameTooltip:SetBuybackItem(widget.item.index)
            else GameTooltip:SetMerchantItem(widget.item.index) end
            GameTooltip:Show()
        end
    end
    panel.rows, panel.offset = {}, 0
    for index = 1, ROWS do
        local button = row(panel, function(widget) owner:Buy(widget.item.index) end, enter)
        button:SetPoint("TOPLEFT", 18, -106 - (index - 1) * ROW_HEIGHT)
        button:SetPoint("RIGHT", -30, 0)
        panel.rows[index] = button
    end
    panel.empty = Theme:Text(panel, R.L.VENDOR_UI_EMPTY, "small", "TEXT_MUTED")
    panel.empty:SetPoint("TOPLEFT", 22, -112)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        panel.offset = math.max(0, math.min(panel.maxOffset or 0, panel.offset - delta))
        owner:Refresh()
    end)
    local buybackTitle = Theme:Text(panel, R.L.VENDOR_UI_BUYBACK, "body", "TEXT_TITLE")
    buybackTitle:SetPoint("TOPLEFT", 18, -116 - ROWS * ROW_HEIGHT)
    panel.buybackRows = {}
    for index = 1, 3 do
        local button = row(panel, function(widget) owner:Buyback(widget.item.index) end, enter)
        button.buyback = true
        button:SetPoint("TOPLEFT", 18, -140 - ROWS * ROW_HEIGHT - (index - 1) * ROW_HEIGHT)
        button:SetPoint("RIGHT", -30, 0)
        panel.buybackRows[index] = button
    end

    function panel:GetQuery() return (self.search:GetText() or ""):lower() end
    function panel:UsableOnly() return self.usable:GetChecked() == true end
    function panel:Render(items, buyback)
        self.maxOffset = math.max(0, #items - ROWS)
        self.offset = math.min(self.offset, self.maxOffset)
        for index, button in ipairs(self.rows) do
            local item = items[index + self.offset]
            if item then
                local r, g, b = 1, 1, 1
                if item.quality and C_Item and C_Item.GetItemQualityColor then
                    r, g, b = C_Item.GetItemQualityColor(item.quality)
                end
                button:SetItem(item, r, g, b)
            else
                button:Hide()
            end
        end
        self.empty:SetShown(#items == 0)
        for index, button in ipairs(self.buybackRows) do
            if buyback[index] then button:SetItem(buyback[index]) else button:Hide() end
        end
    end
    panel:Hide()
    owner.refactorVendorPanel = panel
    return panel
end
