local _, R = ...
local UI, L = R.UI, R.L
local Theme = R.Theme
local unpack = unpack

-- A bullet hangs from a small copper square and sits in from the version heading; a paragraph
-- sits flush with it. The square is anchored to its own text, so a relayout moves both.
local INDENT, MARK_SIZE, MARK_INSET, MARK_Y = 18, 4, 12, 6
local HEADER_GAP, ENTRY_GAP, GROUP_GAP, VERSION_GAP, TAIL = 6, 6, 12, 26, 24
-- Kept clear between the text and the scroll bar.
local RIGHT_PAD = 12

function UI:BuildChangelog(parent)
    local layout = self.layout
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", layout.x, layout.top)
    panel:SetPoint("BOTTOMRIGHT", layout.right, layout.bottom)
    panel.helpKey, panel.countKey = "UI_CHANGELOG_HELP", "UI_CHANGELOG_TITLE"
    local list = self.Widgets:Scroll(panel)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", -16, 0)
    self.changelogList = list
    -- Built once from the generated table and only ever re-anchored: a paragraph's height is
    -- only known once it has a width, and the width only once the page is laid out.
    self.changelogVersions = {}
    for _, version in ipairs(L.CHANGELOG or {}) do
        local block = { header = Theme:SectionHeader(list.child, version.title), lines = {} }
        for _, entry in ipairs(version.entries) do
            local line = { entry = entry, text = Theme:Text(list.child, entry[1], "body", "TEXT_BODY") }
            line.text:SetJustifyV("TOP")
            if entry.bullet then
                local mark = list.child:CreateTexture(nil, "ARTWORK")
                mark:SetSize(MARK_SIZE, MARK_SIZE)
                mark:SetColorTexture(unpack(Theme.colors.ACCENT_COPPER))
                mark:SetPoint("TOPLEFT", line.text, "TOPLEFT", -MARK_INSET, -MARK_Y)
                line.mark = mark
            end
            block.lines[#block.lines + 1] = line
        end
        self.changelogVersions[#self.changelogVersions + 1] = block
    end
    self.changelogEmpty = Theme:Text(panel, L.UI_CHANGELOG_EMPTY, "body", "TEXT_MUTED")
    self.changelogEmpty:SetPoint("TOPLEFT", 0, -4)
    self.changelogEmpty:SetPoint("RIGHT")
    self.changelogEmpty:SetShown(#self.changelogVersions == 0)
    panel.Update = function() self:LoadChangelog() end
    self:RegisterPanel("Changelog", panel)
end

-- Runs on every refresh while the page is showing, like the other panels: cheap, and a width
-- the client settles only after the first show is picked up on the next.
function UI:LoadChangelog()
    local list = self.changelogList
    if not list then return end
    local child = list.child
    local width = list:GetWidth() - RIGHT_PAD
    local offset = 0
    for index, block in ipairs(self.changelogVersions) do
        if index > 1 then offset = offset + VERSION_GAP end
        local header = block.header
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 0, -offset)
        header:SetPoint("RIGHT", child, "RIGHT", -RIGHT_PAD, 0)
        Theme:AlignHairline(header.line, header, header.lineY)
        offset = offset + header.height + HEADER_GAP
        for _, line in ipairs(block.lines) do
            local entry = line.entry
            if entry.gap then offset = offset + GROUP_GAP end
            local indent = entry.bullet and INDENT or 0
            line.text:ClearAllPoints()
            line.text:SetPoint("TOPLEFT", indent, -offset)
            line.text:SetWidth(math.max(1, width - indent))
            local height = line.text:GetStringHeight()
            line.text:SetHeight(height)
            offset = offset + height + ENTRY_GAP
        end
    end
    list:UpdateExtent(offset + TAIL)
end
