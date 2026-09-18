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
    "SetHighlightTexture", "SetNormalTexture", "SetPushedTexture", "SetEnabled", "SetStartDelay", "SetScale",
    "SetDuration", "SetOrder", "SetFromAlpha", "SetToAlpha", "Play", "Stop",
    "SetAutoFocus", "SetMultiLine", "SetFontObject", "SetTextInsets", "SetMaxLetters",
    "ClearFocus", "SetFocus", "SetScrollChild", "SetVerticalScroll",
    "SetOrientation", "SetMinMaxValues", "SetValueStep", "SetThumbTexture",
    "RegisterForClicks", "SetRadialProgressBarStartOffset", "SetRadialProgressBarFeather",
    "SetRadialProgressBarReverse", "SetSmoothing", "SetSmoothScaling", "SetCheckedTexture",
    "SetDisabledCheckedTexture", "SetHitRectInsets", "SetToFinalAlpha",
}

local values = {
    GetWidth = 920, GetHeight = 660, GetFrameLevel = 1, IsEnabled = true, HasFocus = false,
    -- A headless animation never runs, so it always reports itself parked at the start.
    IsPlaying = false, GetSmoothProgress = 0, GetAlpha = 1, IsMouseOver = false,
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
    function Frame:GetMinMaxValues() return 0, self.maximum or 0 end

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
    function Frame:GetFont() return rawget(self, "fontFile") or "mock-font", 12, "" end
    function Frame:SetFont(file, size, flags) self.fontFile, self.fontSize, self.fontFlags = file, size, flags end
    function Frame:SetShadowOffset() end
    function Frame:SetGradient(orientation, bottom, top)
        self.gradient = { orientation = orientation, bottom = bottom, top = top }
    end
    function Frame:SetAtlas(atlas) self.atlas = atlas end
    function Frame:SetChecked(checked) self.checked = checked == true end
    function Frame:GetChecked() return rawget(self, "checked") == true end
    function Frame:SetBlendMode() end
    -- Stubbed deliberately: the ring asks for this method and falls back when it is absent.
    function Frame:SetRadialProgressBarPercent(percent) self.percent = percent end
    function Frame:GetRadialProgressBarPercent() return rawget(self, "percent") or 0 end
    function Frame:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
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
