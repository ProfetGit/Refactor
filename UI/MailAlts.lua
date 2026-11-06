local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")
local L = R.L

local WIDTH, PADDING, TITLE_TOP, ROW_TOP = 272, 12, 14, 34
local COLUMNS, ROWS, CELL, CELL_GAP = 6, 5, 36, 6
local GRID_TOP = ROW_TOP + Theme.dropdownRowHeight * 2 + 6
local GRID_HEIGHT = ROWS * CELL + (ROWS - 1) * CELL_GAP
local LINE_GAP, BUTTON_GAP = 18, 8
local HEIGHT = GRID_TOP + GRID_HEIGHT + 8 + LINE_GAP * 2 + BUTTON_GAP + Theme.buttonHeight + PADDING
local ICON_CROP, COUNT_INSET = 0.08, 2
-- Menu values that are not names: the bank alt rule, and a category the player keeps.
local BANK, KEEP, RULE = "\1bank", "\1keep", "\1rule"

local function itemLabel(entry)
    local name = entry.link and entry.link:match("%[(.-)%]")
    return name or ""
end

local function kindLabel(kind)
    return kind and L["MAIL_ALTS_KIND_" .. kind:upper()] or ""
end

local function reasonText(entry, recipient)
    if entry.reason == "item" then
        return string.format(L.MAIL_ALTS_REASON_ITEM, recipient)
    end
    return string.format(L.MAIL_ALTS_REASON_KIND, kindLabel(entry.reason), recipient)
end

local function hideTooltip(owner)
    if GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
end

local function cellEnter(cell)
    local entry, panel = cell.entry, cell.panel
    if not entry then return end
    local group = panel.owner:SelectedGroup()
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(entry.bag, entry.slot)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|c" .. Theme:Hex("TEXT_TITLE") .. reasonText(entry, group and group.recipient or "")
        .. "|r")
    GameTooltip:AddLine("|c" .. Theme:Hex("TEXT_MUTED") .. L.MAIL_ALTS_HINT .. "|r", nil, nil, nil, true)
    GameTooltip:Show()
end

-- Where this category and this item go, and a way to never see the item here again. The menu
-- is built on every open, so the ticks always show the routes as they are now.
local function openMenu(cell)
    local entry, owner = cell.entry, cell.panel.owner
    if not entry then return end
    local recipients = owner:Recipients()
    MenuUtil.CreateContextMenu(cell, function(_, root)
        root:CreateTitle(itemLabel(entry))
        if entry.kind then
            local kind = entry.kind
            local menu = root:CreateButton(string.format(L.MAIL_ALTS_MENU_KIND, kindLabel(kind)))
            local function current()
                local route = R.Settings:GetOption("mailRoutes")[kind]
                if route == false then return KEEP end
                return route or BANK
            end
            local function choose(value)
                if value == BANK then
                    owner:RouteKind(kind, nil)
                elseif value == KEEP then
                    owner:RouteKind(kind, false)
                else
                    owner:RouteKind(kind, value)
                end
            end
            local function selected(value) return current() == value end
            menu:CreateRadio(L.MAIL_ALTS_ROUTE_BANK, selected, choose, BANK)
            for _, name in ipairs(recipients) do menu:CreateRadio(name, selected, choose, name) end
            menu:CreateRadio(L.MAIL_ALTS_ROUTE_KEEP, selected, choose, KEEP)
        end
        local itemID = entry.itemID
        local items = root:CreateButton(L.MAIL_ALTS_MENU_ITEM)
        local function itemSelected(value)
            return (R.Settings:GetOption("mailItemRoutes")[itemID] or RULE) == value
        end
        local function itemChoose(value)
            owner:RouteItem(itemID, value ~= RULE and value or nil)
        end
        items:CreateRadio(L.MAIL_ALTS_ROUTE_RULE, itemSelected, itemChoose, RULE)
        for _, name in ipairs(recipients) do items:CreateRadio(name, itemSelected, itemChoose, name) end
        root:CreateButton(L.MAIL_ALTS_MENU_NEVER, function() owner:Never(itemID) end)
    end)
end

local function cellClick(cell, button)
    local entry, owner = cell.entry, cell.panel.owner
    if not entry then return end
    if button == "RightButton" then
        openMenu(cell)
    elseif IsShiftKeyDown() then
        owner:ClickAll(entry.itemID)
    else
        owner:Click(entry)
    end
end

local function createCell(panel, index)
    local cell = CreateFrame("Button", nil, panel)
    cell:SetSize(CELL, CELL)
    local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    cell:SetPoint("TOPLEFT", PADDING + column * (CELL + CELL_GAP), -(GRID_TOP + row * (CELL + CELL_GAP)))
    cell.panel = panel
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    cell.border = Theme:Texture(cell, "itemBorder", "OVERLAY")
    cell.border:SetAllPoints()
    cell.count = Theme:Text(cell, "", "small", "TEXT_HIGHLIGHT")
    cell.count:SetPoint("BOTTOMRIGHT", -COUNT_INSET, COUNT_INSET)
    Theme:Shadow(cell.count)
    Theme:Fill(cell, "HIGHLIGHT", "HIGHLIGHT")
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:SetScript("OnClick", cellClick)
    cell:SetScript("OnEnter", cellEnter)
    cell:SetScript("OnLeave", hideTooltip)
    cell:Hide()
    return cell
end

local function fillCell(cell, entry)
    cell.entry = entry
    cell.icon:SetTexture(entry.icon)
    cell.count:SetText(entry.count and entry.count > 1 and entry.count or "")
    local r, g, b = C_Item.GetItemQualityColor(entry.quality or 1)
    cell.border:SetVertexColor(r or 1, g or 1, b or 1, 1)
    cell:Show()
end

-- Beside the Send Mail tab: the bank alt, whose items are showing, the items, and what the mail
-- costs and carries. The owner decides what goes where and does the attaching; this frame only
-- shows and asks. Built once at module enable, never inside an event handler (rule 11).
function R.UI:CreateMailAltsPanel(owner)
    if owner.refactorMailPanel then return owner.refactorMailPanel end
    local inner = WIDTH - PADDING * 2
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, 0)
    panel:EnableMouse(true)
    Theme:Panel(panel)
    panel.owner = owner

    panel.title = Theme:Text(panel, L.MAIL_ALTS_TITLE, "body", "TEXT_TITLE")
    panel.title:SetPoint("TOPLEFT", PADDING, -TITLE_TOP)

    panel.bankAlt = Theme:Dropdown(panel, inner, {},
        function(value) return (R.Settings:GetOption("mailBankAlt") or "") == value end,
        function(value) owner:SetBankAlt(value) end)
    panel.bankAlt:SetPoint("TOPLEFT", PADDING, -ROW_TOP)
    panel.bankAlt:SetLabel(L.MAIL_ALTS_BANK_ALT)

    panel.recipient = Theme:Dropdown(panel, inner, {},
        function(value) return owner.selected == value end,
        function(value) owner:Select(value) end)
    panel.recipient:SetPoint("TOPLEFT", PADDING, -(ROW_TOP + Theme.dropdownRowHeight))
    panel.recipient:SetLabel(L.MAIL_ALTS_SHOWING)

    panel.cells = {}
    for index = 1, COLUMNS * ROWS do panel.cells[index] = createCell(panel, index) end
    panel.empty = Theme:Text(panel, "", "body", "TEXT_MUTED")
    panel.empty:SetPoint("TOPLEFT", PADDING, -(GRID_TOP + CELL))
    panel.empty:SetWidth(inner)
    panel.empty:SetJustifyH("CENTER")

    local half = (inner - BUTTON_GAP) / 2
    panel.fill = Theme:Button(panel, inner, L.MAIL_ALTS_FILL, function() owner:Fill() end)
    panel.fill:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    panel.gold = Theme:Button(panel, half, "", function() owner:AddGold() end)
    panel.gold:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    local coinY = PADDING + Theme.buttonHeight + BUTTON_GAP
    panel.summary = Theme:Text(panel, "", "small", "TEXT_BODY")
    panel.summary:SetPoint("BOTTOMLEFT", PADDING, coinY + LINE_GAP)
    panel.summary:SetWidth(inner)
    panel.postageLabel = Theme:Text(panel, L.MAIL_ALTS_POSTAGE, "small", "TEXT_MUTED")
    panel.postageLabel:SetPoint("BOTTOMLEFT", PADDING, coinY)
    panel.postage = Theme:Coins(panel)
    panel.value = Theme:Coins(panel)
    panel.valueLabel = Theme:Text(panel, L.MAIL_ALTS_VALUE, "small", "TEXT_MUTED")
    panel:Hide()

    function panel:RenderBankAlt()
        local current = R.Settings:GetOption("mailBankAlt") or ""
        local list, seen = { { value = "", text = L.MAIL_ALTS_NONE } }, {}
        for _, name in ipairs(owner:Characters()) do
            seen[name:lower()] = true
            list[#list + 1] = { value = name, text = name }
        end
        if current ~= "" and not seen[current:lower()] then list[#list + 1] = { value = current, text = current } end
        self.bankAlt:SetEntries(list)
        self.bankAlt:SetValueText(current ~= "" and current or L.MAIL_ALTS_NONE)
    end

    function panel:RenderGroups(groups, group)
        local list = {}
        for index, each in ipairs(groups) do
            list[index] = { value = each.key, text = string.format(L.MAIL_ALTS_GROUP, each.recipient, #each.entries) }
        end
        self.recipient:SetEntries(list)
        self.recipient:SetValueText(group and string.format(L.MAIL_ALTS_GROUP, group.recipient, #group.entries) or "")
        if #groups > 0 then self.recipient:Show() else self.recipient:Hide() end
    end

    function panel:RenderCells(group)
        local entries = group and group.entries or {}
        for index, cell in ipairs(self.cells) do
            local entry = entries[index]
            if entry then
                fillCell(cell, entry)
            else
                cell.entry = nil
                hideTooltip(cell)
                cell:Hide()
            end
        end
        local text = ""
        if not group then
            text = (R.Settings:GetOption("mailBankAlt") or "") == "" and L.MAIL_ALTS_PICK or L.MAIL_ALTS_NOTHING
        end
        self.empty:SetText(text)
    end

    function panel:RenderFooter(group)
        local summary = owner:Summary()
        if group then
            self.summary:SetText(string.format(L.MAIL_ALTS_LEFT, summary.left, summary.mails))
        else
            self.summary:SetText("")
        end
        local last = self.postage:Place(self.postageLabel, summary.postage, nil, "LEFT", self.postageLabel,
            "RIGHT", 4, 0)
        local leftmost = self.value:PlaceRight(self.postageLabel, summary.value, "BOTTOMRIGHT", self,
            "BOTTOMRIGHT", -PADDING, PADDING + Theme.buttonHeight + BUTTON_GAP)
        self.valueLabel:ClearAllPoints()
        self.valueLabel:SetPoint("RIGHT", leftmost or last, "LEFT", -4, 0)
        local gold = summary.gold
        if gold then
            self.gold:Show()
            self.gold.label:SetText(L.MAIL_ALTS_GOLD)
            self.gold:SetEnabled(gold > 0 and group ~= nil)
            self.fill:SetSize((WIDTH - PADDING * 2 - BUTTON_GAP) / 2, Theme.buttonHeight)
            self.fill.label:SetWidth((WIDTH - PADDING * 2 - BUTTON_GAP) / 2 - 16)
        else
            self.gold:Hide()
            self.fill:SetSize(WIDTH - PADDING * 2, Theme.buttonHeight)
            self.fill.label:SetWidth(WIDTH - PADDING * 2 - 16)
        end
        self.fill:SetEnabled(group ~= nil and summary.attached < ATTACHMENTS_MAX_SEND)
    end

    function panel:Render()
        local groups = owner:Groups()
        local group = owner:SelectedGroup()
        self:RenderBankAlt()
        self:RenderGroups(groups, group)
        self:RenderCells(group)
        self:RenderFooter(group)
        self:Show()
    end

    owner.refactorMailPanel = panel
    return panel
end
