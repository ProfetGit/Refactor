--- @module interface.visibility
--- Purpose: fade groups of Blizzard frames out, back in under the mouse, or by player state, with alpha alone.
--- Requires: hooksecurefunc
--- Events: CURSOR_CHANGED, REFACTOR_CONDITIONS_CHANGED, REFACTOR_SETTINGS_CHANGED; EditMode.Enter and
---     EditMode.Exit through EventRegistry where the client has one. Frames, GameTooltip, GetCursorInfo,
---     Blizzard's chat fade function, EventRegistry and the Edit Mode settings dialog are resolved by name at
---     enable, so one missing piece costs its group or its convenience, never the module.
--- Hot: no
local _, R = ...
local Rules, Fade, Conditions = R.Visibility, R.Fade, R.Conditions
local Visibility = R:RegisterModule({
    id = "interface.visibility", category = "Interface", nameKey = "VISIBILITY_NAME",
    descriptionKey = "VISIBILITY_DESC", detailKey = "VISIBILITY_DETAIL",
    requires = { "hooksecurefunc" },
    conflicts = { "ElvUI.ui", "Bartender4.bars", "Dominos.bars" },
    risk = "visible", defaultEnabled = false,
})

-- Neither a script hook nor a secure hook can be removed, so each is installed once for the
-- session and every handler checks the module is active first. This table outlives enable
-- and disable on purpose.
Visibility.hooked = {}

local CHAT_FADE_IN = "FCF_FadeInChatFrame"
local EDIT_MODE_ENTER, EDIT_MODE_EXIT = "EditMode.Enter", "EditMode.Exit"
-- Blizzard's per-system Edit Mode dialog; ours opens beside it, never inside it.
local DIALOG = "EditModeSystemSettingsDialog"
-- Nearly everything with a mouse shows a tooltip, and every tooltip names its owner. That
-- one call is the hover signal for secure buttons, which get no script hook of ours.
local TOOLTIP, TOOLTIP_OWNER = "GameTooltip", "SetOwner"
local CURSOR = "GetCursorInfo"
-- A button or a member frame sits a few levels under its group's frame.
local PARENT_DEPTH = 6
-- Leaving is never trusted to an event: while anything is hovered, the mouse is checked
-- against the hovered frames this often, and the watch stops the moment nothing is.
local WATCH_INTERVAL = 0.1
-- A catalogue entry may leave optional and reapply out; a later group should not need to spell them.
local EMPTY = {}

local function isFrame(value)
    return type(value) == "table" and type(value.GetAlpha) == "function"
end

-- Secure and forbidden frames are Blizzard's alone: no script of ours goes on one. Nor does one
-- that takes no mouse: giving a frame an OnEnter turns its mouse on, and an overlay that
-- suddenly catches the pointer steals the hover, and the tooltip, from whatever sits under it.
local function hookable(frame)
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then
        return false
    end
    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then
        return false
    end
    if type(frame.IsProtected) == "function" and frame:IsProtected() then
        return false
    end
    local takesMouse = frame.IsMouseMotionEnabled or frame.IsMouseEnabled
    return type(takesMouse) == "function" and takesMouse(frame) == true
end

function Visibility:Group(id)
    return self.groups and self.groups[id]
end

-- Alpha is applied as a share of what the frame had when the module took it over, so
-- "visible" leaves Blizzard's own alpha alone. Edit Mode shows everything as the game has
-- it, except the element being tuned, which previews its shown opacity so the slider shows
-- what it does. A spell or item on the cursor shows everything too: a bar that cannot be
-- seen cannot be dropped on.
function Visibility:ApplyGroup(id, snap)
    local group = self:Group(id)
    if not group or group.status ~= "ok" then
        return
    end
    local rule = Rules:Rule(id)
    local target
    if self.editing then
        target = self.preview[id] and rule.shownAlpha or 1
    elseif self.dragging then
        target = rule.shownAlpha
    else
        target = Rules:Resolve(rule, Conditions:State(), group.hovered)
    end
    for _, frame in ipairs(group.frames) do
        local goal = self.captured[frame] * target
        local seconds = goal > frame:GetAlpha() and rule.fadeIn or rule.fadeOut
        Fade:To(frame, goal, snap and 0 or seconds)
    end
    -- An extra the player has not opted into is left exactly as the client has it, unless
    -- this module already moved it: then it goes back to the shown value and stays there.
    for _, extra in ipairs(group.extras) do
        local wanted = R.Settings:GetOption(extra.option) == true
        if wanted or extra.touched then
            local goal = wanted and extra.shown * target or extra.shown
            local seconds = goal > extra:GetAlpha() and rule.fadeIn or rule.fadeOut
            Fade:To(extra, goal, (snap or not wanted) and 0 or seconds)
            extra.touched = wanted
        end
    end
end

function Visibility:ApplyAll(snap)
    for id in pairs(self.groups) do
        self:ApplyGroup(id, snap)
    end
end

-- Whether the mouse is still on a group by its own evidence: typing in it, its tooltip up,
-- Blizzard's chat fade holding it, or the pointer over one of its frames. A frame the
-- client refuses to measure counts as not under the mouse rather than as an error.
function Visibility:Over(group)
    if group.typing then
        return true
    end
    if self.tooltipGroup == group.id and self.tooltip and self.tooltip:IsShown() then
        return true
    end
    for _, frame in ipairs(group.frames) do
        if group.def.hover.chat and rawget(frame, "hasBeenFaded") then
            return true
        end
        local ok, over = pcall(frame.IsMouseOver, frame)
        if ok and over then
            return true
        end
    end
    return false
end

-- The one pass that decides hover for every group. A zone is hovered while any of its
-- members is, so a bar, the bags and the micro menu come and go as one.
function Visibility:Watch()
    self.watch = nil
    if not self.active then
        return
    end
    local zones, any = self.zoneOver, false
    for zone in pairs(zones) do
        zones[zone] = nil
    end
    for _, group in pairs(self.groups) do
        group.over = group.status == "ok" and self:Over(group)
        if group.over then
            local zone = Rules:Rule(group.id).zone
            if zone ~= Rules.noZone then
                zones[zone] = true
            end
        end
    end
    for id, group in pairs(self.groups) do
        local hovered = group.over or zones[Rules:Rule(id).zone] == true
        if hovered ~= group.hovered then
            group.hovered = hovered
            self:ApplyGroup(id)
        end
        any = any or hovered
    end
    if any then
        self.watch = R:After(self, WATCH_INTERVAL, self.Watch)
    end
end

-- Any hover-in signal lands here; the watch takes it from there.
function Visibility:Hover(id)
    local group = self.active and self:Group(id)
    if not group or group.status ~= "ok" then
        return
    end
    if not group.hovered then
        group.hovered = true
        self:ApplyGroup(id)
        local zone = Rules:Rule(id).zone
        if zone ~= Rules.noZone then
            for otherId, other in pairs(self.groups) do
                if other.status == "ok" and not other.hovered and Rules:Rule(otherId).zone == zone then
                    other.hovered = true
                    self:ApplyGroup(otherId)
                end
            end
        end
    end
    if not self.watch then
        self.watch = R:After(self, WATCH_INTERVAL, self.Watch)
    end
end

-- The group a frame belongs to: the frame itself, or an ancestor a few levels up.
function Visibility:GroupOfFrame(frame)
    local depth = 0
    while type(frame) == "table" and depth < PARENT_DEPTH do
        local id = self.frameGroup[frame]
        if id then
            return id
        end
        local ok, parent = pcall(frame.GetParent, frame)
        frame = ok and parent or nil
        depth = depth + 1
    end
    return nil
end

function Visibility:OnTooltipOwner(owner)
    if not self.active then
        return
    end
    local id = self:GroupOfFrame(owner)
    self.tooltipGroup = id
    local group = id and self:Group(id)
    if group and group.def.hover.tooltip then
        self:Hover(id)
    end
end

-- Blizzard tracks the cursor over its chat windows itself and calls this as it fades them
-- in; the windows take no mouse of their own, so this is the only hover signal they have.
function Visibility:OnChatFade()
    if not self.active then
        return
    end
    for id, group in pairs(self.groups) do
        if group.def.hover.chat then
            self:Hover(id)
        end
    end
end

function Visibility:OnTyping(id, typing)
    local group = self.active and self:Group(id)
    if not group then
        return
    end
    group.typing = typing
    if typing then
        self:Hover(id)
    end
end

function Visibility:OnCursor()
    local read = self.cursor
    local dragging = read ~= nil and read() ~= nil
    if dragging ~= self.dragging then
        self.dragging = dragging
        self:ApplyAll(false)
    end
end

function Visibility:SetEditing(editing)
    if not self.active then
        return
    end
    self.editing = editing
    self:ApplyAll(editing)
end

function Visibility:OnConditions()
    self:ApplyAll(false)
end

function Visibility:OnSettingsChanged(_, key)
    if key == Rules.option or Rules.extraOptions[key] then
        self:ApplyAll(false)
    end
end

-- A frame can serve two groups, a minimap button being inside the minimap, so the record is
-- per frame and group. Only a frame's own hover-in is hooked; leaving is the watch's job.
function Visibility:HookFrame(frame, id)
    if not hookable(frame) then
        return
    end
    local groups = self.hooked[frame]
    if not groups then
        groups = {}
        self.hooked[frame] = groups
    end
    if groups[id] then
        return
    end
    groups[id] = true
    frame:HookScript("OnEnter", function() self:Hover(id) end)
end

function Visibility:HookChildren(frame, id, depth)
    if type(frame.GetChildren) ~= "function" then
        return
    end
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        self:HookFrame(child, id)
        if depth > 1 then
            self:HookChildren(child, id, depth - 1)
        end
    end
end

function Visibility:HookGlobal(name, handler)
    if self.hooked[name] then
        return true
    end
    if type(R.Capabilities:Resolve(name)) ~= "function" then
        return false
    end
    self.hooked[name] = true
    hooksecurefunc(name, handler)
    return true
end

function Visibility:HookMethod(frameName, method, handler)
    local key = frameName .. "." .. method
    if self.hooked[key] then
        return true
    end
    local frame = R.Capabilities:Resolve(frameName)
    if type(frame) ~= "table" or type(rawget(frame, method) or frame[method]) ~= "function" then
        return false
    end
    self.hooked[key] = true
    hooksecurefunc(frame, method, handler)
    return true
end

function Visibility:InstallHooks(group)
    local def, id = group.def, group.id
    for _, frame in ipairs(group.frames) do
        if def.hover.frames then
            self:HookFrame(frame, id)
        end
        if def.hover.children then
            self:HookChildren(frame, id, def.hover.children == true and 1 or def.hover.children)
        end
        local editBox = def.hover.editBox and rawget(frame, "editBox")
        if type(editBox) == "table" and type(editBox.HookScript) == "function" and not self.hooked[editBox] then
            self.hooked[editBox] = true
            editBox:HookScript("OnEditFocusGained", function() self:OnTyping(id, true) end)
            editBox:HookScript("OnEditFocusLost", function() self:OnTyping(id, false) end)
        end
    end
    if def.hover.chat then
        self:HookGlobal(CHAT_FADE_IN, function() self:OnChatFade() end)
    end
    if def.hover.tooltip then
        self:HookMethod(TOOLTIP, TOOLTIP_OWNER, function(_, owner) self:OnTooltipOwner(owner) end)
    end
    for _, entry in ipairs(def.reapply or EMPTY) do
        -- Blizzard wrote an alpha of its own; the rule's answer goes straight back on. An entry
        -- marked baseline is Blizzard setting the frame's resting alpha (an Edit Mode opacity),
        -- which is what the rule is a share of from then on.
        local baseline = type(entry) == "table" and entry.baseline
        local function reapply(frame)
            if not self.active then
                return
            end
            if baseline and self.captured[frame] then
                self.captured[frame] = frame:GetAlpha()
            end
            self:ApplyGroup(id, true)
        end
        if type(entry) == "string" then
            self:HookGlobal(entry, reapply)
        else
            self:HookMethod(entry.frame, entry.method, reapply)
        end
    end
end

-- Selecting a system in Edit Mode attaches Blizzard's dialog to it; the companion opens
-- beside the dialog with the groups that system stands for, and closes with it.
function Visibility:OnSystemSelected(systemFrame)
    if not self.active then
        return
    end
    local ids = Rules:GroupsForSystem(systemFrame, self.editIds)
    for id in pairs(self.preview) do
        self.preview[id] = nil
    end
    if #ids == 0 then
        self.companion:Close()
    else
        for _, id in ipairs(ids) do
            self.preview[id] = true
        end
        self.companion:Open(R.Capabilities:Resolve(DIALOG), ids)
    end
    self:ApplyAll(true)
end

function Visibility:OnSystemClosed()
    if not self.active then
        return
    end
    for id in pairs(self.preview) do
        self.preview[id] = nil
    end
    self.companion:Close()
    self:ApplyAll(true)
end

function Visibility:HookDialog()
    if self.hooked.dialog then
        return
    end
    local dialog = R.Capabilities:Resolve(DIALOG)
    if type(dialog) ~= "table" or type(dialog.HookScript) ~= "function"
        or type(rawget(dialog, "AttachToSystemFrame") or dialog.AttachToSystemFrame) ~= "function" then
        return
    end
    self.hooked.dialog = true
    hooksecurefunc(dialog, "AttachToSystemFrame", function(_, systemFrame) self:OnSystemSelected(systemFrame) end)
    dialog:HookScript("OnHide", function() self:OnSystemClosed() end)
end

function Visibility:HookEditMode()
    if self.hooked.editMode then
        return
    end
    local registry = R.Capabilities:Resolve("EventRegistry")
    if type(registry) ~= "table" or type(registry.RegisterCallback) ~= "function" then
        return
    end
    self.hooked.editMode = true
    registry:RegisterCallback(EDIT_MODE_ENTER, function() self:SetEditing(true) end, self)
    registry:RegisterCallback(EDIT_MODE_EXIT, function() self:SetEditing(false) end, self)
end

-- A widget alpha setter, wrapped so the fade driver can drive it like a frame. The client
-- gives no getter, so the value it holds is the last one written, starting from the shown
-- one. Nothing is written until the group first applies with the option on.
local function adapter(frame, method, shown)
    local extra = { frame = frame, method = method, shown = shown, value = shown, touched = false }
    function extra:GetAlpha()
        return self.value
    end
    function extra:SetAlpha(alpha)
        self.value = alpha
        self.frame[self.method](self.frame, alpha)
    end
    return extra
end

function Visibility:PrepareExtras(group)
    for _, entry in ipairs(group.def.extras or EMPTY) do
        local frame = R.Capabilities:Resolve(entry.frame)
        if type(frame) == "table" then
            for method, shown in pairs(entry.alphas) do
                if type(rawget(frame, method) or frame[method]) == "function" then
                    local extra = adapter(frame, method, shown)
                    extra.option = entry.option
                    group.extras[#group.extras + 1] = extra
                end
            end
        end
    end
end

-- A group is available when every frame it needs exists and no neighbour owns it. Deference
-- is decided once, per group, so the chat groups keep working beside a bar addon.
function Visibility:PrepareGroup(def)
    local group = { def = def, id = def.id, frames = {}, extras = {}, hovered = false, over = false,
        typing = false, status = "ok" }
    self.groups[def.id] = group
    local integrations = R.Integrations
    local owner = integrations and integrations.FrameGroupOwner and integrations:FrameGroupOwner(def.id)
    if owner then
        group.status, group.owner = "owned", owner
        return
    end
    for _, name in ipairs(def.frames) do
        local frame = R.Capabilities:Resolve(name)
        if not isFrame(frame) then
            group.status, group.missing, group.frames = "missing", name, {}
            return
        end
        group.frames[#group.frames + 1] = frame
    end
    for _, name in ipairs(def.optional or EMPTY) do
        local frame = R.Capabilities:Resolve(name)
        if isFrame(frame) then
            group.frames[#group.frames + 1] = frame
        end
    end
    -- Frames another part of Refactor handed to this group, the chat copy button being one.
    -- They join a group that exists; they cannot bring a missing one back.
    for _, frame in ipairs(Rules:Contributions(def.id)) do
        if isFrame(frame) then
            group.frames[#group.frames + 1] = frame
        end
    end
    for _, frame in ipairs(group.frames) do
        -- Only ever captured once. A group rebuilt while it is faded would otherwise take
        -- the faded alpha for the frame's own, and every rebuild would dim it again.
        if self.captured[frame] == nil then
            self.captured[frame] = frame:GetAlpha()
        end
        self.frameGroup[frame] = def.id
    end
    self:PrepareExtras(group)
    self:InstallHooks(group)
end

-- A frame joined or left a group after it was built. Building that one group again is
-- cheaper than working out which half of it moved, and every hook it installs is guarded.
function Visibility:OnFramesChanged(_, groupId)
    local def = Rules:Group(groupId)
    if not self.active or not def then
        return
    end
    local before, group = {}, self.groups[groupId]
    for _, frame in ipairs(group and group.frames or EMPTY) do
        before[#before + 1] = frame
    end
    self:PrepareGroup(def)
    -- A frame that left goes back to the alpha the group found it at, or it would be
    -- stranded wherever the rule last put it.
    for _, frame in ipairs(before) do
        local kept = false
        for _, current in ipairs(self.groups[groupId].frames) do
            kept = kept or current == frame
        end
        if not kept and self.captured[frame] then
            Fade:Snap(frame, self.captured[frame])
            self.captured[frame], self.frameGroup[frame] = nil, nil
        end
    end
    self:ApplyGroup(groupId, true)
end

function Visibility:OnEnable()
    local integrations = R.Integrations
    local owner = integrations and integrations.Owner and integrations:Owner(self.id)
    if owner then
        -- ElvUI replaces chat and bars alike, so there is nothing here left to fade.
        self.unavailableReasonKey = "VISIBILITY_DEFERRED"
        self.state = "unavailable"
        self.unavailableReason = string.format(R.L.VISIBILITY_DEFERRED, owner)
        R.Broker:Emit("REFACTOR_MODULE_CHANGED", self.id)
        return
    end
    self.groups, self.captured, self.preview, self.editIds = {}, {}, {}, {}
    self.frameGroup, self.zoneOver, self.tooltipGroup, self.watch = {}, {}, nil, nil
    -- One companion for the session: a frame cannot be destroyed, so it is built once.
    self.companion = self.companion or R.UI:CreateVisibilityCompanion(self)
    local tooltip = R.Capabilities:Resolve(TOOLTIP)
    self.tooltip = type(tooltip) == "table" and type(tooltip.IsShown) == "function" and tooltip or nil
    local cursor = R.Capabilities:Resolve(CURSOR)
    self.cursor = type(cursor) == "function" and cursor or nil
    local manager = R.Capabilities:Resolve("EditModeManagerFrame")
    self.editing = type(manager) == "table" and type(rawget(manager, "IsEditModeActive") or manager.IsEditModeActive)
        == "function" and manager:IsEditModeActive() == true
    self.dragging = self.cursor ~= nil and self.cursor() ~= nil
    for _, def in ipairs(Rules.groups) do
        self:PrepareGroup(def)
    end
    self:HookEditMode()
    self:HookDialog()
    Conditions:Start(self)
    R.Broker:Subscribe("REFACTOR_CONDITIONS_CHANGED", self.OnConditions, self)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
    R.Broker:Subscribe("REFACTOR_VISIBILITY_FRAMES", self.OnFramesChanged, self)
    if self.cursor then
        R.Broker:Subscribe("CURSOR_CHANGED", self.OnCursor, self)
    end
    self.active = true
    self:ApplyAll(true)
end

-- Every frame goes back to the alpha it had, at once: a fade on the way out would leave a
-- record behind for a module that is already off.
function Visibility:OnDisable()
    self.active = false
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    Conditions:Stop(self)
    if self.companion then
        self.companion:Close()
    end
    for frame, alpha in pairs(self.captured or {}) do
        Fade:Snap(frame, alpha)
    end
    for _, group in pairs(self.groups or EMPTY) do
        for _, extra in ipairs(group.extras) do
            if extra.touched then
                Fade:Snap(extra, extra.shown)
            end
        end
    end
    self.groups, self.captured, self.preview, self.frameGroup, self.zoneOver = nil, nil, nil, nil, nil
    self.watch, self.tooltipGroup, self.editing, self.dragging = nil, nil, false, false
end
