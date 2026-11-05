-- The client surface the preview needs on top of Tests/mock/runtime.lua: geometry-aware
-- widgets, a screen-sized UIParent, the handful of Blizzard templates Refactor inherits, and
-- the atlas list of the Forever client so Theme:ApplyAsset takes the branch it takes in game.
local Geometry = require("geometry")
local Env = {}

local SCREEN_W, SCREEN_H = 1600, 900
Env.screen = { width = SCREEN_W, height = SCREEN_H }

local function child(env, parent, kind, key, layer)
    local object
    if kind == "Texture" then object = parent:CreateTexture(nil, layer)
    elseif kind == "FontString" then object = parent:CreateFontString(nil, layer, "GameFontNormal")
    else object = Geometry.newRegion(env, kind, parent) end
    parent[key] = object
    return object
end

-- Only the parts of each template Refactor reaches for, drawn close enough to judge layout.
local TEMPLATES = {}

function TEMPLATES.WowStyle1DropdownTemplate(env, frame)
    local bg = child(env, frame, "Texture", "Background", "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas("preview-dropdown")
    local label = child(env, frame, "FontString", "Text", "ARTWORK")
    label:SetFontObject("GameFontHighlightSmall")
    label:SetPoint("LEFT", 10, 0)
    label:SetPoint("RIGHT", -24, 0)
    label:SetJustifyH("LEFT")
    frame.label = label
    local arrow = child(env, frame, "Texture", "Arrow", "ARTWORK")
    arrow:SetAtlas("preview-dropdown-arrow")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -8, 0)
end

function TEMPLATES.UIPanelButtonTemplate(env, frame)
    local bg = child(env, frame, "Texture", "Background", "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas("preview-redbutton")
    local label = child(env, frame, "FontString", "Text", "ARTWORK")
    label:SetFontObject("GameFontNormal")
    label:SetPoint("CENTER")
    frame.SetText = function(self, text) self.Text:SetText(text) end
    frame.GetText = function(self) return self.Text:GetText() end
    frame.GetFontString = function(self) return self.Text end
end

function TEMPLATES.BasicFrameTemplateWithInset(env, frame)
    local bg = child(env, frame, "Texture", "Bg", "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas("preview-basicframe")
    local title = child(env, frame, "FontString", "TitleText", "OVERLAY")
    title:SetFontObject("GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    local close = Geometry.newRegion(env, "Button", frame)
    frame.CloseButton = close
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", 2, 1)
    local art = close:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    art:SetAtlas("RedButton-Exit")
end

function TEMPLATES.BackpackTokenTemplate(env, frame)
    local icon = child(env, frame, "Texture", "Icon", "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("RIGHT")
    local count = child(env, frame, "FontString", "Count", "ARTWORK")
    count:SetFontObject("GameFontHighlightSmall")
    count:SetPoint("RIGHT", icon, "LEFT", -2, 0)
end

local function createFrame(env, kind, name, parent, template)
    if type(parent) == "string" then parent = env[parent] end
    local frame = Geometry.newRegion(env, kind, parent or env.UIParent, name)
    if name then env[name] = frame end
    if type(template) == "string" then
        for part in template:gmatch("[^,%s]+") do
            if TEMPLATES[part] then TEMPLATES[part](env, frame) end
        end
    end
    return frame
end

-- Atlas sizes of the Forever client, written by Tools/Preview/run.py from the MCP index.
local function loadAtlases(path)
    local ok, atlases = pcall(dofile, path)
    return ok and atlases or {}
end

function Env.install(env, atlasPath)
    env.frames = env.frames or {}
    env.CreateFrame = function(kind, name, parent, template)
        return createFrame(env, kind, name, parent, template)
    end
    local root = Geometry.newRegion(env, "Frame", nil, "UIParent")
    root.isRoot, root.width, root.height = true, SCREEN_W, SCREEN_H
    env.UIParent = root
    env.WorldFrame = root
    local atlases = loadAtlases(atlasPath)
    env.previewAtlases = atlases
    env.C_Texture = {
        GetAtlasInfo = function(name)
            if type(name) ~= "string" then return nil end
            local size = atlases[name:lower()]
            if not size then return nil end
            return { width = size[1], height = size[2], file = size[3], leftTexCoord = 0, rightTexCoord = 1,
                topTexCoord = 0, bottomTexCoord = 1, tilesHorizontally = false, tilesVertically = false }
        end,
    }
    -- The border every Refactor window wears. Recorded so the renderer can draw the kit.
    env.NineSliceUtil = {
        GetLayout = function(name) return name end,
        ApplyLayoutByName = function(frame, name) frame.nineSlice = name end,
        ApplyLayout = function(frame, _, kit) frame.nineSlice = kit or "layout" end,
        DisableSharpening = function() end,
    }
    env.GetPhysicalScreenSize = function() return SCREEN_W, SCREEN_H end
    env.GetScreenWidth = function() return SCREEN_W end
    env.GetScreenHeight = function() return SCREEN_H end
    env.GetCursorPosition = function() return SCREEN_W / 2, SCREEN_H / 2 end
    env.Settings = {
        RegisterCanvasLayoutCategory = function(_, title) return { ID = title } end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,
    }
    for name, object in pairs(Geometry.fontObjects) do
        env[name] = { name = name, GetFont = function() return "Fonts\\FRIZQT__.TTF", object.size, "" end }
    end
    return env
end

Env.Geometry = Geometry
return Env
