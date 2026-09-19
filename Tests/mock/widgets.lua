-- Smoke-test widget surface. Separate from Tests/mock/runtime.lua on purpose: this exists to
-- run the real load sequence end to end, so an unstubbed method is an error naming itself
-- rather than a silent no-op. Behaviour assertions belong in the specs, not here.
local Widgets = {}

local noops = {
    "SetPoint", "SetAllPoints", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight",
    "SetTexCoord", "SetTexture", "SetColorTexture", "SetAlpha",
    "SetTextColor", "SetJustifyH", "SetJustifyV",
    "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "SetMovable", "SetResizable",
    "SetResizeBounds", "EnableMouse", "EnableMouseWheel", "RegisterForDrag",
    "StartMoving", "StopMovingOrSizing", "StartSizing",
    "SetHighlightTexture", "SetNormalTexture", "SetPushedTexture", "SetStartDelay", "SetScale",
    "SetDuration", "SetOrder", "SetFromAlpha", "SetToAlpha",
    "SetAutoFocus", "SetMultiLine", "SetFontObject", "SetTextInsets", "SetMaxLetters",
    "ClearFocus", "SetFocus", "SetScrollChild", "SetVerticalScroll",
    "SetOrientation", "SetValueStep", "SetThumbTexture",
    "RegisterForClicks", "SetRadialProgressBarStartOffset", "SetRadialProgressBarFeather",
    "SetRadialProgressBarReverse", "SetSmoothing", "SetSmoothScaling", "SetCheckedTexture",
    "SetDisabledCheckedTexture", "SetHitRectInsets", "SetToFinalAlpha",
    "SetTexelSnappingBias", "SetSnapToPixelGrid",
    -- A settings block clips its contents to however much of it is currently revealed.
    "SetClipsChildren",
    -- Loot feed rows: a text shadow, and the Translation the slide plays. The Edit Mode
    -- dialog's sliders are Blizzard's minimal slider, which steps on drag.
    "SetShadowColor", "SetObeyStepOnDrag",
    -- The session summary: a multi-line header, a hand-rolled scroll frame, and the copy
    -- box that selects its own text so Ctrl C works.
    "SetSpacing", "SetVerticalScrollRange", "HighlightText",
    "SetRadians",
}

local values = {
    GetWidth = 920, GetHeight = 660, GetFrameLevel = 1, HasFocus = false,
    GetEffectiveScale = 1,
    -- A headless animation never runs, so it always reports itself parked at the start.
    IsPlaying = false, GetSmoothProgress = 0, GetAlpha = 1, IsMouseOver = false,
    -- Nothing has a screen rect here, so nothing is ever scrolled off the bottom.
    GetVerticalScroll = 0, GetVerticalScrollRange = 0,
}

function Widgets.install(env)
    local Frame = {}
    Frame.__index = Frame

    for _, name in ipairs(noops) do
        Frame[name] = function() end
    end
    for name, value in pairs(values) do
        Frame[name] = function() return value end
    end

    -- Blizzard's dropdown button, enough of it to drive the menu generator from a spec:
    -- SetupMenu keeps the generator, and Open runs it against a recording root description
    -- so the entries, the selected one and the setter are all really exercised.
    function Frame:SetupMenu(generator) self.menuGenerator = generator end
    function Frame:SetDefaultText(text) self.defaultText = text end
    function Frame:GetDefaultText() return self.defaultText end
    function Frame:GenerateMenu() end
    function Frame:OpenMenu()
        local root, picked = {}, {}
        function root:CreateRadio(text, isSelected, setSelected, value)
            picked[#picked + 1] = { text = text, value = value,
                selected = isSelected(value) == true, choose = function() setSelected(value) end }
            return { SetTooltip = function() end }
        end
        function root:SetTag() end
        function root:SetScrollMode() end
        if self.menuGenerator then self.menuGenerator(self, root) end
        return picked
    end

    function Frame:RegisterEvent(event) self.events[event] = true end
    function Frame:UnregisterEvent(event) self.events[event] = nil end
    function Frame:UnregisterAllEvents() self.events = {} end
    function Frame:IsEventRegistered(event) return self.events[event] == true end
    function Frame:SetScript(name, callback) self.scripts[name] = callback end
    function Frame:GetScript(name) return self.scripts[name] end
    function Frame:Hide() self.shown = false end
    function Frame:Show() self.shown = true end
    function Frame:SetShown(shown) self.shown = shown == true end
    function Frame:IsShown() return self.shown == true end
    function Frame:IsProtected() return false end
    function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function Frame:GetValue() return self.value or 0 end
    function Frame:SetValue(value) self.value = value end
    -- Real bounds, not a stub returning zero: a stepper that clamps against them would
    -- otherwise be tested against a range that does not exist.
    function Frame:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
    function Frame:GetMinMaxValues() return self.minimum or 0, self.maximum or 0 end

    local function region(env_, kind)
        local object = setmetatable({ kind = kind, events = {}, scripts = {} }, Frame)
        env_.frames[#env_.frames + 1] = object
        return object
    end

    function Frame:CreateTexture() return region(env, "Texture") end
    function Frame:CreateFontString() return region(env, "FontString") end

    -- Recorded rather than dropped: the specs assert on what a plate ends up showing.
    function Frame:SetText(text) self.text = text end
    function Frame:GetText() return self.text or "" end
    function Frame:GetStringWidth() return #(self.text or "") * 8 end
    function Frame:SetTexture(texture) self.texture = texture end
    -- The loot feed asks whether the client accepted a custom file path, and a mock that
    -- answered nil would report every one of them missing.
    function Frame:GetTexture() return self.texture end
    function Frame:GetFont() return rawget(self, "fontFile") or "mock-font", 12, "" end
    function Frame:SetFont(file, size, flags) self.fontFile, self.fontSize, self.fontFlags = file, size, flags end
    function Frame:SetShadowOffset() end
    function Frame:SetGradient(orientation, bottom, top)
        self.gradient = { orientation = orientation, bottom = bottom, top = top }
    end
    function Frame:SetAtlas(atlas) self.atlas = atlas end
    -- Headless frames have no screen rect, so pixel alignment has nothing to measure and
    -- the code under test must fall back rather than guess.
    function Frame:GetTop() return nil end
    function Frame:GetLeft() return nil end
    -- Recorded, not dropped: a row refuses a click while its toggle is disabled, and that
    -- is only testable if the mock remembers being disabled.
    function Frame:SetEnabled(enabled) self.enabled = enabled ~= false end
    function Frame:IsEnabled() return rawget(self, "enabled") ~= false end
    function Frame:SetChecked(checked) self.checked = checked == true end
    function Frame:GetChecked() return rawget(self, "checked") == true end
    function Frame:SetBlendMode() end
    -- Stubbed deliberately: the ring asks for this method and falls back when it is absent.
    function Frame:SetRadialProgressBarPercent(percent) self.percent = percent end
    function Frame:GetRadialProgressBarPercent() return rawget(self, "percent") or 0 end
    function Frame:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    -- Recorded, not dropped: which way the chevron ended up pointing is the thing under test.
    function Frame:SetRotation(radians) self.rotation = radians end
    function Frame:GetRotation() return rawget(self, "rotation") or 0 end
    -- An animation that overshoots is only correct if its legs sum back to the distance it
    -- was meant to travel, so the legs have to be readable.
    function Frame:SetOffset(x, y) self.offsetX, self.offsetY = x, y end
    function Frame:GetOffset() return rawget(self, "offsetX") or 0, rawget(self, "offsetY") or 0 end
    function Frame:SetDegrees(degrees) self.degrees = degrees end
    function Frame:GetDegrees() return rawget(self, "degrees") or 0 end
    -- A headless group never runs, so what it was asked to do is all there is to assert on.
    function Frame:Play() self.playCount = (rawget(self, "playCount") or 0) + 1 end
    function Frame:Stop() self.stopCount = (rawget(self, "stopCount") or 0) + 1 end
    function Frame:GetPlayCount() return rawget(self, "playCount") or 0 end
    function Frame:SetParent(parent) self.parent = parent end
    function Frame:GetParent() return self.parent end
    function Frame:CreateAnimationGroup() return region(env, "AnimationGroup") end
    function Frame:CreateAnimation() return region(env, "Animation") end

    Frame.__index = function(object, key)
        local value = rawget(Frame, key)
        if value ~= nil then return value end
        -- Widget methods are verb-prefixed PascalCase. Anything else read off a frame is
        -- a data field an addon put there, which is allowed to be missing.
        if type(key) ~= "string" then return nil end
        if not key:match("^Set%u") and not key:match("^Get%u") and not key:match("^Is%u")
            and not key:match("^Create%u") and not key:match("^Register%u")
            and not key:match("^Unregister%u") and not key:match("^Add%u") then
            return nil
        end
        error("unstubbed widget method: " .. tostring(key) .. " on " .. tostring(rawget(object, "kind")), 2)
    end

    env.CreateFrame = function(kind, name, parent, template)
        local frame = setmetatable({
            kind = kind, name = name, parent = parent, template = template,
            events = {}, scripts = {}, shown = false,
        }, Frame)
        env.frames[#env.frames + 1] = frame
        if name then env[name] = frame end
        -- Only the parentKey children the addon actually reaches for, and only on the
        -- template that owns them: an unstubbed one must still be an error that names itself.
        if type(template) == "string" and template:find("BasicFrameTemplate", 1, true) then
            frame.TitleText = region(env, "FontString")
            frame.CloseButton = region(env, "Button")
        end
        return frame
    end
    -- The client's string aliases that embedded libraries expect to be global.
    env.strmatch, env.strfind, env.strsub, env.format = string.match, string.find, string.sub, string.format
    env.UIParent = env.CreateFrame("Frame", "UIParent")
    -- Spelled exactly as the client's own atlas list spells them, and matched case
    -- sensitively on purpose: SetAtlas is, and a lowercase name drew nothing in game.
    local knownAtlases = {
        ["Crosshair_Attack_48"] = 48, ["Crosshair_buy_48"] = 48,
        ["QuestSkull"] = 32, ["QuestObjective"] = 32, ["QuestNormal"] = 32, ["QuestTurnin"] = 32,
        ["bags-icon-questitem"] = 50, ["common-icon-checkmark"] = 25, ["Objective-Nub"] = 11,
        ["combat_swords-icon"] = 64,
    }
    env.C_Texture = {
        GetAtlasInfo = function(name)
            local size = knownAtlases[name]
            return size and { width = size, height = size, elementName = name } or nil
        end,
    }
    env.Settings = {
        RegisterCanvasLayoutCategory = function(_, title) return { ID = title } end,
        RegisterAddOnCategory = function() end,
    }
    return env
end

return Widgets
