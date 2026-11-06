local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

local WIDTH, PADDING, TITLE_TOP, ITEM_TOP = 320, 16, 14, 36
local ICON, ICON_GAP, LINE_INSET, BADGE_GAP, BUTTON_GAP, BUTTON_TOP = 36, 10, 2, 6, 8, 12
local ICON_CROP, FADE = 0.08, 0.15
local HEIGHT = ITEM_TOP + ICON + BUTTON_TOP + Theme.buttonHeight + PADDING
-- Blizzard's own prompts start 135 px down (StaticPopup1, GameDialog.xml). The prompt ends
-- above that slot, so the bind confirmation an Equip can raise opens under it, not on it.
local TOP_OFFSET = -12
-- Every owner's prompt sits in the same place, so only one is on screen at a time and the
-- others wait until it closes.
local prompts = {}

local function othersShown(prompt)
    for _, other in ipairs(prompts) do
        if other ~= prompt and other:IsShown() then return true end
    end
    return false
end

local function wakeOthers(prompt)
    for _, other in ipairs(prompts) do
        if other ~= prompt and #other.queue > 0 and not other:IsShown() then
            other:Refresh()
            if other:IsShown() then return end
        end
    end
end

-- The tooltip opens under the whole prompt, so it never covers the two buttons.
local function itemEnter(widget)
    local entry = widget.prompt.queue[1]
    if entry and entry.link and GameTooltip then
        GameTooltip:SetOwner(widget.prompt, "ANCHOR_BOTTOM")
        GameTooltip:SetHyperlink(entry.link)
        GameTooltip:Show()
    end
end

local function itemLeave(widget)
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == widget.prompt then
        GameTooltip:Hide()
    end
end

-- One looted upgrade at a time, top centre: the item, Gear Refactor's verdict and what it
-- replaces, then Equip or Not now. Further upgrades wait their turn behind it. The owner
-- decides what is an upgrade and does the equipping; this frame only shows and asks. An owner
-- may name its own title keys and give its badge a theme token instead of a colour.
-- Built once at module enable, never inside an event handler (rule 11).
function R.UI:CreateUpgradePrompt(owner)
    if owner.refactorUpgradePrompt then return owner.refactorUpgradePrompt end
    local inner = WIDTH - PADDING * 2
    local prompt = CreateFrame("Frame", nil, UIParent)
    prompt:SetSize(WIDTH, HEIGHT)
    prompt:SetPoint("TOP", UIParent, "TOP", 0, TOP_OFFSET)
    prompt:SetFrameStrata("DIALOG")
    prompt:SetClampedToScreen(true)
    prompt:EnableMouse(true)
    Theme:Dialog(prompt)
    prompt.queue = {}

    prompt.title = Theme:Text(prompt, "", "body", "TEXT_TITLE")
    prompt.title:SetPoint("TOPLEFT", PADDING, -TITLE_TOP)
    prompt.title:SetPoint("TOPRIGHT", -PADDING, -TITLE_TOP)
    prompt.title:SetJustifyH("CENTER")

    -- The whole item block is one hover target for the item's own tooltip.
    local item = CreateFrame("Button", nil, prompt)
    item:SetSize(inner, ICON)
    item:SetPoint("TOPLEFT", PADDING, -ITEM_TOP)
    item.prompt = prompt
    item:SetScript("OnEnter", itemEnter)
    item:SetScript("OnLeave", itemLeave)
    prompt.item = item
    prompt.icon = item:CreateTexture(nil, "ARTWORK")
    prompt.icon:SetSize(ICON, ICON)
    prompt.icon:SetPoint("LEFT")
    prompt.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    prompt.border = Theme:Texture(item, "itemBorder", "OVERLAY")
    prompt.border:SetAllPoints(prompt.icon)
    prompt.name = Theme:Text(item, "", "body", "TEXT_BODY")
    -- Both ends of a line sit at the same height, or the two anchors fight over it.
    prompt.name:SetPoint("TOPLEFT", prompt.icon, "TOPRIGHT", ICON_GAP, -LINE_INSET)
    prompt.name:SetPoint("TOPRIGHT", 0, -LINE_INSET)
    prompt.name:SetWordWrap(false)
    prompt.badge = Theme:Text(item, "", "small", "TEXT_BODY")
    prompt.badge:SetPoint("BOTTOMLEFT", prompt.icon, "BOTTOMRIGHT", ICON_GAP, LINE_INSET)
    prompt.replaces = Theme:Text(item, "", "small", "TEXT_MUTED")
    prompt.replaces:SetPoint("BOTTOMLEFT", prompt.badge, "BOTTOMRIGHT", BADGE_GAP, 0)
    prompt.replaces:SetPoint("BOTTOMRIGHT", 0, LINE_INSET)
    prompt.replaces:SetWordWrap(false)

    -- Accept on the left and decline on the right, the order of Blizzard's own prompts.
    local half = (inner - BUTTON_GAP) / 2
    prompt.equip = Theme:Button(prompt, half, R.L.UPGRADE_EQUIP, function() prompt:Decide(true) end)
    prompt.equip:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    prompt.skip = Theme:Button(prompt, half, R.L.UPGRADE_SKIP, function() prompt:Decide(false) end)
    prompt.skip:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    prompt.fader = Theme:Fader(prompt, FADE, FADE)
    prompt:Hide()
    prompts[#prompts + 1] = prompt

    -- A second drop of an item already waiting takes its place rather than asking twice.
    function prompt:Offer(entry)
        for index, queued in ipairs(self.queue) do
            if queued == entry or (entry.link ~= nil and queued.link == entry.link) then
                self.queue[index] = entry
                self:Refresh()
                return
            end
        end
        self.queue[#self.queue + 1] = entry
        self:Refresh()
    end

    function prompt:Withdraw(entry)
        for index, queued in ipairs(self.queue) do
            if queued == entry then
                table.remove(self.queue, index)
                self:Refresh()
                return
            end
        end
    end

    -- Equip that the owner could not carry out leaves the item up, so it can be declined.
    function prompt:Decide(equip)
        local entry = self.queue[1]
        if not entry then return end
        if equip and not (self.onEquip and self.onEquip(entry)) then
            return
        end
        table.remove(self.queue, 1)
        if not equip and self.onSkip then self.onSkip(entry) end
        self:Refresh()
    end

    -- Equip greys out in combat and whenever the owner says it cannot equip right now.
    function prompt:Refresh()
        local entry = self.queue[1]
        if not entry then
            if self:IsShown() then
                itemLeave(self.item)
                self.fader:Snap(0)
                self:Hide()
                if self.onEmpty then self.onEmpty() end
                wakeOthers(self)
            end
            return
        end
        if not self:IsShown() and othersShown(self) then return end
        local waiting = #self.queue - 1
        local title, titleMore = R.L[self.titleKey or "UPGRADE_TITLE"], R.L[self.titleMoreKey or "UPGRADE_TITLE_MORE"]
        self.title:SetText(waiting > 0 and string.format(titleMore, waiting) or title)
        self.icon:SetTexture(entry.icon)
        self.border:SetVertexColor(entry.r or 1, entry.g or 1, entry.b or 1, 1)
        self.name:SetText(entry.itemName or "")
        if entry.r then
            self.name:SetTextColor(entry.r, entry.g, entry.b, 1)
        else
            Theme:Color(self.name, "TEXT_BODY", true)
        end
        -- The badge colour is Gear Refactor's own, handed over at runtime.
        local badge = entry.badge
        self.badge:SetText(badge and badge.text or "")
        if badge and badge.token then
            Theme:Color(self.badge, badge.token, true)
        elseif badge then
            self.badge:SetTextColor(badge.r or 1, badge.g or 1, badge.b or 1, 1)
        end
        self.replaces:SetText(entry.replacesName and string.format(R.L.UPGRADE_REPLACES, entry.replacesName) or "")
        self.equip:SetEnabled(self.canEquip ~= nil and self.canEquip() == true)
        if not self:IsShown() then
            self:Show()
            self.fader:To(1)
        end
    end

    function prompt:Clear()
        for index = #self.queue, 1, -1 do
            self.queue[index] = nil
        end
        itemLeave(self.item)
        local shown = self:IsShown()
        self.fader:Snap(0)
        self:Hide()
        if shown then wakeOthers(self) end
    end

    owner.refactorUpgradePrompt = prompt
    return prompt
end
