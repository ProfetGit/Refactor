local _, R = ...

-- Blizzard's merchant page: cells of 153 by 44 from MerchantItemTemplate, 12 apart across
-- and 8 down, the first at (11, -69) in a 336 by 444 frame. Everything here derives from
-- those numbers, so an added cell is indistinguishable from the twelve the XML ships.
local CELL_WIDTH, CELL_HEIGHT, GAP_X, GAP_Y, LEFT, TOP = 153, 44, 12, 8, 11, 69
local BASE_WIDTH, BASE_COLUMNS = 336, 2
-- Below the last row: page buttons, repair row and money frames on the merchant tab, a
-- bare margin on the buyback tab. Blizzard's next-page button sits 26 in from the right
-- edge and the buyback slot 15 in and 33 up; both follow the edge once the frame grows.
local BOTTOM_MERCHANT, BOTTOM_BUYBACK = 123, 36
local NEXT_PAGE_INSET, NEXT_PAGE_Y, BUYBACK_INSET, BUYBACK_Y = 26, 96, 15, 33
local BLIZZARD_CELLS = 12
-- Every cell the grid could need is built at enable (rule 11). Settings validates the
-- same caps and the Options sliders run over them.
local MAX_COLUMNS, MAX_ROWS = 5, 8
local MAX_CELLS = MAX_COLUMNS * MAX_ROWS
local TEMPLATE, CELL_PREFIX = "MerchantItemTemplate", "MerchantItem"

local function capturePoint(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    return { point, relativeTo, relativePoint, x, y }
end

local function restorePoint(frame, saved)
    frame:ClearAllPoints()
    frame:SetPoint(saved[1], saved[2], saved[3], saved[4], saved[5])
end

local function stackHeight(lines, bottom)
    return TOP + lines * CELL_HEIGHT + (lines - 1) * GAP_Y + bottom
end

-- Reshapes Blizzard's merchant window rather than drawing beside it: the page size it
-- fills from, the cells it fills into, and the frame around them. Blizzard's own update
-- keeps filling the cells and paging; only where they sit is decided here.
function R.UI:CreateMerchantGrid(owner)
    if owner.refactorMerchantGrid then return owner.refactorMerchantGrid end
    local grid = { cells = {}, original = {}, active = false }
    local frame = MerchantFrame
    for index = 1, BLIZZARD_CELLS do
        local cell = _G[CELL_PREFIX .. index]
        grid.cells[index] = cell
        grid.original[index] = capturePoint(cell)
    end
    -- Named like Blizzard's so its update finds them with the same lookup it uses for
    -- the first twelve, and built from its template so they carry its art and scripts.
    for index = BLIZZARD_CELLS + 1, MAX_CELLS do
        local cell = CreateFrame("Frame", CELL_PREFIX .. index, frame, TEMPLATE)
        cell:Hide()
        R:OwnFrame(cell)
        grid.cells[index] = cell
        -- A cell born here gets its extra cost buttons here too, so the costs module
        -- never has to create frames after its own enable.
        self:PrepareMerchantCostRow(index)
    end
    local original = grid.original
    original.width, original.height = frame:GetWidth(), frame:GetHeight()
    original.perPage = MERCHANT_ITEMS_PER_PAGE
    original.borderWidth = MerchantFrameBottomLeftBorder:GetWidth()
    original.nextPage = capturePoint(MerchantNextPageButton)
    original.buyback = capturePoint(MerchantBuyBackItem)

    -- Blizzard's update re-anchors four cells on every pass and shows or hides the two
    -- buyback-only ones, so the grid is put back after each pass rather than once.
    function grid:Relayout()
        if not self.active then return end
        local columns = self.columns
        local count = frame.selectedTab == 2 and BUYBACK_ITEMS_PER_PAGE or columns * self.rows
        for index, cell in ipairs(self.cells) do
            if index <= count then
                local column, line = (index - 1) % columns, math.floor((index - 1) / columns)
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT + column * (CELL_WIDTH + GAP_X),
                    -(TOP + line * (CELL_HEIGHT + GAP_Y)))
                cell:Show()
            else
                cell:Hide()
            end
        end
    end

    -- Redraws through Blizzard's own update, which reaches Relayout through the hook. A
    -- page that no longer exists at the new page size would show nothing, so page one:
    -- the same write Blizzard's MerchantFrame_OnShow makes, hence the lint exemption.
    local function redraw()
        if frame:IsShown() then
            frame.page = 1 -- luacheck: ignore 122
            MerchantFrame_Update()
        else
            grid:Relayout()
        end
    end

    function grid:Apply(columns, rows)
        columns = math.max(BASE_COLUMNS, math.min(MAX_COLUMNS, columns or BASE_COLUMNS))
        rows = math.max(1, math.min(MAX_ROWS, rows or 1))
        self.columns, self.rows, self.active = columns, rows, true
        local buybackRows = math.ceil(BUYBACK_ITEMS_PER_PAGE / columns)
        self.width = BASE_WIDTH + (columns - BASE_COLUMNS) * (CELL_WIDTH + GAP_X)
        self.height = math.max(stackHeight(rows, BOTTOM_MERCHANT), stackHeight(buybackRows, BOTTOM_BUYBACK))
        R:SetBlizzardTunable("MERCHANT_ITEMS_PER_PAGE", columns * rows)
        frame:SetSize(self.width, self.height)
        MerchantFrameBottomLeftBorder:SetWidth(self.width - 2)
        MerchantNextPageButton:ClearAllPoints()
        MerchantNextPageButton:SetPoint("CENTER", frame, "BOTTOMRIGHT", -NEXT_PAGE_INSET, NEXT_PAGE_Y)
        MerchantBuyBackItem:ClearAllPoints()
        MerchantBuyBackItem:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BUYBACK_INSET, BUYBACK_Y)
        redraw()
    end

    function grid:Restore()
        if not self.active then return end
        self.active = false
        R:SetBlizzardTunable("MERCHANT_ITEMS_PER_PAGE", original.perPage)
        frame:SetSize(original.width, original.height)
        MerchantFrameBottomLeftBorder:SetWidth(original.borderWidth)
        restorePoint(MerchantNextPageButton, original.nextPage)
        restorePoint(MerchantBuyBackItem, original.buyback)
        for index, cell in ipairs(self.cells) do
            if index <= BLIZZARD_CELLS then
                restorePoint(cell, original[index])
            else
                cell:Hide()
            end
        end
        redraw()
    end

    -- A hook cannot be removed, so it is installed once and asks the grid whether it is on.
    hooksecurefunc("MerchantFrame_Update", function() grid:Relayout() end)
    owner.refactorMerchantGrid = grid
    return grid
end
