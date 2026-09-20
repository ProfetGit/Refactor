--- @module interface.visibility
--- Purpose: fade groups of Blizzard frames out, back in under the mouse, or by player state, with alpha alone.
--- Requires: hooksecurefunc
--- Events: REFACTOR_CONDITIONS_CHANGED, REFACTOR_SETTINGS_CHANGED; EditMode.Enter and EditMode.Exit through
---     EventRegistry where the client has one. Frames, Blizzard's chat fade functions and EventRegistry are
---     resolved by name at enable, so one missing piece costs its group, never the module.
--- Hot: no
local _, R = ...
local Rules, Fade, Conditions = R.Visibility, R.Fade, R.Conditions
local Visibility = R:RegisterModule({
    id = "interface.visibility", category = "Interface", nameKey = "VISIBILITY_NAME",
    descriptionKey = "VISIBILITY_DESC", detailKey = "VISIBILITY_DETAIL",
    requires = { "hooksecurefunc" },
    conflicts = { "ElvUI.ui", "Bartender4.bars", "Dominos.bars" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

-- Neither a script hook nor a secure hook can be removed, so each is installed once for the
-- session and every handler checks the module is active first. This table outlives enable
-- and disable on purpose.
Visibility.hooked = {}

local CHAT_FADE_IN, CHAT_FADE_OUT = "FCF_FadeInChatFrame", "FCF_FadeOutChatFrame"
local EDIT_MODE_ENTER, EDIT_MODE_EXIT = "EditMode.Enter", "EditMode.Exit"
-- A catalogue entry may leave optional and reapply out; a later group should not need to spell them.
local EMPTY = {}

local function isFrame(value)
    return type(value) == "table" and type(value.GetAlpha) == "function"
end

function Visibility:Group(id)
    return self.groups and self.groups[id]
end

-- Alpha is applied as a share of what the frame had when the module took it over, so
-- "visible" leaves Blizzard's own alpha alone. Edit Mode shows everything: a bar nobody can
-- see cannot be dragged.
function Visibility:ApplyGroup(id, snap)
    local group = self:Group(id)
    if not group or group.status ~= "ok" then
        return
    end
    local rule = Rules:Rule(id)
    local target = self.editing and 1 or Rules:Resolve(rule, Conditions:State(), group.hovered)
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

function Visibility:MouseOver(group)
    for _, frame in ipairs(group.frames) do
        if frame:IsMouseOver() then
            return true
        end
    end
    return false
end

function Visibility:OnEnter(id)
    local group = self.active and self:Group(id)
    if not group then
        return
    end
    if group.leaveCheck then
        group.leaveCheck:Cancel()
        group.leaveCheck = nil
    end
    if not group.hovered then
        group.hovered = true
        self:ApplyGroup(id)
    end
end

-- A leave is checked a tick later rather than acted on: the mouse crossing from one button
-- of a bar to the next leaves and enters in the same frame, and a fade that started on the
-- leave would flicker. Typing in a chat window counts as hovering it.
function Visibility:OnLeave(id)
    local group = self.active and self:Group(id)
    if not group or not group.hovered or group.leaveCheck then
        return
    end
    group.leaveCheck = R:After(self, 0, function()
        group.leaveCheck = nil
        if self.active and group.hovered and not group.typing and not self:MouseOver(group) then
            group.hovered = false
            self:ApplyGroup(id)
        end
    end)
end

-- Blizzard tracks the cursor over its chat windows itself and calls these as it fades them;
-- the windows take no mouse of their own, so this is the only hover signal they have.
function Visibility:OnChatFade(shown)
    if not self.active then
        return
    end
    for id, group in pairs(self.groups) do
        if group.def.hover.chat and group.status == "ok" then
            if shown then
                self:OnEnter(id)
            else
                self:OnLeave(id)
            end
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
        self:OnEnter(id)
    else
        self:OnLeave(id)
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
-- per frame and group, and a texture, which takes no mouse, is skipped.
function Visibility:HookFrame(frame, id)
    if type(frame.HookScript) ~= "function" then
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
    frame:HookScript("OnEnter", function() self:OnEnter(id) end)
    frame:HookScript("OnLeave", function() self:OnLeave(id) end)
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
        self:HookGlobal(CHAT_FADE_IN, function() self:OnChatFade(true) end)
        self:HookGlobal(CHAT_FADE_OUT, function() self:OnChatFade(false) end)
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

-- A group is available when every frame it needs exists and no neighbour owns it. Deference
-- is decided once, per group, so the chat groups keep working beside a bar addon.
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

function Visibility:PrepareGroup(def)
    local group = { def = def, id = def.id, frames = {}, extras = {}, hovered = false, typing = false, status = "ok" }
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
    for _, frame in ipairs(group.frames) do
        self.captured[frame] = frame:GetAlpha()
    end
    self:PrepareExtras(group)
    self:InstallHooks(group)
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
    self.groups, self.captured = {}, {}
    local manager = R.Capabilities:Resolve("EditModeManagerFrame")
    self.editing = type(manager) == "table" and type(rawget(manager, "IsEditModeActive") or manager.IsEditModeActive)
        == "function" and manager:IsEditModeActive() == true
    for _, def in ipairs(Rules.groups) do
        self:PrepareGroup(def)
    end
    self:HookEditMode()
    Conditions:Start(self)
    R.Broker:Subscribe("REFACTOR_CONDITIONS_CHANGED", self.OnConditions, self)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
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
    self.groups, self.captured, self.editing = nil, nil, false
end
