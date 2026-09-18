local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

local POOL_SIZE, GAP = 5, 6
local TOAST_WIDTH, TOAST_HEIGHT = 272, 52
local DEFAULT_POSITION = { point = "BOTTOM", relativePoint = "CENTER", x = 0, y = -240 }
local VALID_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

-- The host owns a fixed pool of toast frames, created once at module enable (rule 11), and
-- stacks whatever is visible upward from a single anchor. Modules ask for a toast by key,
-- so a second copy of the same item bumps the count instead of adding a frame.
function R.UI:CreateToastHost(owner)
    if owner.refactorToastHost then return owner.refactorToastHost end
    local host = CreateFrame("Frame", nil, UIParent)
    -- The host is the footprint the stack grows into, so Edit Mode has something to outline.
    -- Toasts still anchor to its bottom edge, which is where they sat when it was 1x1.
    host:SetSize(TOAST_WIDTH, POOL_SIZE * TOAST_HEIGHT + (POOL_SIZE - 1) * GAP)
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    host.owner = owner
    host.visible, host.byKey = {}, {}
    host.pool = R.Pools:Create(function()
        local toast = Theme:Toast(host)
        toast.onHidden = function(widget) host:Release(widget) end
        return toast
    end, function(toast) toast:ResetToast() end)
    for _ = 1, POOL_SIZE do host.pool:Acquire() end
    host.pool:ReleaseAll()

    function host:Layout()
        local previous
        for _, toast in ipairs(self.visible) do
            toast:ClearAllPoints()
            if previous then toast:SetPoint("BOTTOM", previous, "TOP", 0, GAP)
            else toast:SetPoint("BOTTOM", self, "BOTTOM") end
            previous = toast
        end
    end

    function host:Release(toast)
        for index, shown in ipairs(self.visible) do
            if shown == toast then table.remove(self.visible, index) end
        end
        if toast.key then self.byKey[toast.key] = nil end
        toast.key = nil
        self.pool:Release(toast)
        self:Layout()
    end

    -- Returns nil when every frame is busy: a burst of loot drops the overflow rather than
    -- creating frames during an event.
    function host:Acquire(key)
        local toast = self.byKey[key]
        if toast then return toast, true end
        if #self.pool.free == 0 then return nil end
        toast = self.pool:Acquire()
        toast.key = key
        self.byKey[key] = toast
        self.visible[#self.visible + 1] = toast
        self:Layout()
        return toast, false
    end

    function host:Clear()
        for index = #self.visible, 1, -1 do
            self:Release(self.visible[index])
        end
    end

    function host:SavePosition()
        local character = R.Settings.character
        if not character then return end
        local point, _, relativePoint, x, y = self:GetPoint(1)
        character.toast = { point = point, relativePoint = relativePoint, x = x, y = y }
    end

    function host:RestorePosition()
        local saved = R.Settings.character and R.Settings.character.toast or nil
        if type(saved) ~= "table" or not VALID_POINTS[saved.point] or not VALID_POINTS[saved.relativePoint]
            or type(saved.x) ~= "number" or type(saved.y) ~= "number" then
            saved = DEFAULT_POSITION
        end
        self:ClearAllPoints()
        self:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    end

    host:RestorePosition()

    -- Created once here, never inside an event handler (rule 11).
    local selection = Theme:EditModeSelection(host, R.L.UI_TOAST_SYSTEM_LABEL)
    host.selection = selection
    selection:SetScript("OnEnter", function(widget) widget:SetSelected(true) end)
    selection:SetScript("OnLeave", function(widget) widget:SetSelected(widget.dragging == true) end)
    selection:SetScript("OnDragStart", function(widget)
        widget.dragging = true
        widget:SetSelected(true)
        host:StartMoving()
    end)
    selection:SetScript("OnDragStop", function(widget)
        widget.dragging = nil
        host:StopMovingOrSizing()
        host:SavePosition()
        widget:SetSelected(false)
    end)

    -- Blizzard fires these for everyone the moment Edit Mode opens and closes. Refactor is
    -- not a registered system, so this is the whole integration.
    function host:SetEditing(editing)
        self.selection:SetShown(editing and self.owner.state == "enabled")
    end

    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() host:SetEditing(true) end, host)
        EventRegistry:RegisterCallback("EditMode.Exit", function() host:SetEditing(false) end, host)
    end

    owner.refactorToastHost = host
    return host
end
