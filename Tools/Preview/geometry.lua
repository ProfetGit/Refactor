-- A widget model with real geometry, for the layout preview only. Tests/mock/widgets.lua
-- answers every question with a constant because specs assert on behaviour; this one resolves
-- anchors the way the client does, so a page can be drawn and looked at. Permissive by design:
-- an unknown setter is recorded and ignored, because a missing method here should cost one
-- detail of the picture, never the picture.
local Metrics = require("metrics")
local Geometry = {}

local FONT_OBJECTS = {
    GameFontNormal = { size = 12, color = { 1, 0.82, 0, 1 } },
    GameFontNormalSmall = { size = 10, color = { 1, 0.82, 0, 1 } },
    GameFontNormalLarge = { size = 16, color = { 1, 0.82, 0, 1 } },
    GameFontNormalHuge = { size = 20, color = { 1, 0.82, 0, 1 } },
    GameFontHighlight = { size = 12, color = { 1, 1, 1, 1 } },
    GameFontHighlightSmall = { size = 10, color = { 1, 1, 1, 1 } },
    GameFontHighlightLarge = { size = 16, color = { 1, 1, 1, 1 } },
    GameFontDisableSmall = { size = 10, color = { 0.5, 0.5, 0.5, 1 } },
    GameFontDisable = { size = 12, color = { 0.5, 0.5, 0.5, 1 } },
    ChatFontNormal = { size = 14, color = { 1, 1, 1, 1 } },
}
Geometry.fontObjects = FONT_OBJECTS
local DEFAULT_FONT = FONT_OBJECTS.GameFontNormal
local LINE_FACTOR = 1.15

local STRATA = { WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
Geometry.strata, Geometry.layers = STRATA, LAYERS

local generation = 0
local function touch() generation = generation + 1 end

-- Text measured in the font the page is drawn in. Escapes are stripped first: a colour code
-- has no width, an inline texture has the size it names.
local function plain(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T[^|]*|t", "\1"):gsub("|A[^|]*|a", "\1")
    text = text:gsub("|H[^|]*|h", ""):gsub("|h", "")
    return text
end

local function measure(text, size)
    local width = 0
    for index = 1, #text do
        local code = text:byte(index)
        if code == 1 then
            width = width + size
        elseif code >= 128 then
            -- One advance per UTF-8 sequence, counted on its lead byte.
            if code >= 192 then width = width + 0.6 * size end
        else
            width = width + (Metrics[code] or 0.55) * size
        end
    end
    return width
end
Geometry.measure = function(text, size) return measure(plain(text), size) end

-- Word wrap into lines no wider than width, the way a FontString with a width does.
local function wrap(text, size, width)
    local lines = {}
    for paragraph in (plain(text) .. "\n"):gmatch("(.-)\n") do
        if not width or width <= 0 then
            lines[#lines + 1] = paragraph
        else
            local line = ""
            for word in paragraph:gmatch("%S+") do
                local candidate = line == "" and word or (line .. " " .. word)
                if line ~= "" and measure(candidate, size) > width + 0.5 then
                    lines[#lines + 1] = line
                    line = word
                else
                    line = candidate
                end
            end
            lines[#lines + 1] = line
        end
    end
    return lines
end
Geometry.wrap = wrap

local Region = {}
Region.__index = Region
Geometry.Region = Region

local creation = 0
local function newRegion(env, kind, parent, name)
    creation = creation + 1
    local region = setmetatable({
        kind = kind, parent = parent, name = name, children = {}, regions = {},
        points = {}, shown = true, alpha = 1, scale = 1, events = {}, scripts = {},
        order = creation, env = env,
    }, Region)
    if parent then
        local list = (kind == "Texture" or kind == "FontString") and parent.regions or parent.children
        list[#list + 1] = region
    end
    env.frames[#env.frames + 1] = region
    touch()
    return region
end
Geometry.newRegion = newRegion

-- Anchoring -------------------------------------------------------------------------------

function Region:SetPoint(point, a, b, c, d)
    local relativeTo, relativePoint, x, y
    if type(a) == "number" then
        x, y = a, b
    else
        relativeTo = a
        if type(b) == "number" then
            x, y = b, c
        else
            relativePoint, x, y = b, c, d
        end
    end
    if type(relativeTo) == "string" then relativeTo = self.env[relativeTo] end
    point = point:upper()
    for index, existing in ipairs(self.points) do
        if existing.point == point then table.remove(self.points, index) break end
    end
    self.points[#self.points + 1] = { point = point, rel = relativeTo, relPoint = (relativePoint or point):upper(),
        x = x or 0, y = y or 0 }
    touch()
end

function Region:SetAllPoints(relativeTo)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", relativeTo or self.parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", relativeTo or self.parent, "BOTTOMRIGHT", 0, 0)
end

function Region:ClearAllPoints() self.points = {} touch() end
function Region:ClearPoint(point)
    for index, existing in ipairs(self.points) do
        if existing.point == point then table.remove(self.points, index) touch() return end
    end
end
function Region:GetNumPoints() return #self.points end
function Region:GetPoint(index)
    local p = self.points[index or 1]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
end
function Region:SetWidth(width) self.width = width touch() end
function Region:SetHeight(height) self.height = height touch() end
function Region:SetSize(width, height) self.width, self.height = width, height touch() end
function Region:SetScale(scale) self.scale = scale touch() end
function Region:GetScale() return self.scale end
function Region:SetParent(parent)
    if type(parent) == "string" then parent = self.env[parent] end
    local old = self.parent
    if old then
        local list = (self.kind == "Texture" or self.kind == "FontString") and old.regions or old.children
        for index, child in ipairs(list) do
            if child == self then table.remove(list, index) break end
        end
    end
    self.parent = parent
    if parent then
        local list = (self.kind == "Texture" or self.kind == "FontString") and parent.regions or parent.children
        list[#list + 1] = self
    end
    touch()
end
function Region:GetParent() return self.parent end

function Region:GetEffectiveScale()
    local scale, node = 1, self
    while node do
        if node.kind ~= "Texture" and node.kind ~= "FontString" then scale = scale * (node.scale or 1) end
        node = node.parent
    end
    return scale
end

local H_PART = { TOPLEFT = "L", LEFT = "L", BOTTOMLEFT = "L", TOPRIGHT = "R", RIGHT = "R", BOTTOMRIGHT = "R",
    TOP = "C", CENTER = "C", BOTTOM = "C" }
local V_PART = { TOPLEFT = "T", TOP = "T", TOPRIGHT = "T", BOTTOMLEFT = "B", BOTTOM = "B", BOTTOMRIGHT = "B",
    LEFT = "C", CENTER = "C", RIGHT = "C" }

local function coord(rect, point)
    local h, v = H_PART[point] or "C", V_PART[point] or "C"
    local x = h == "L" and rect.left or h == "R" and rect.right or (rect.left + rect.right) / 2
    local y = v == "T" and rect.top or v == "B" and rect.bottom or (rect.top + rect.bottom) / 2
    return x, y
end

function Region:FontInfo()
    local object = FONT_OBJECTS[self.fontObject or ""] or DEFAULT_FONT
    return self.fontSize or object.size, object
end

function Region:TextLines(width)
    local size = self:FontInfo()
    local lines = wrap(self.text or "", size, width)
    if self.maxLines and self.maxLines > 0 and #lines > self.maxLines then
        local kept = {}
        for index = 1, self.maxLines do kept[index] = lines[index] end
        lines = kept
    end
    return lines
end

function Region:NaturalWidth()
    local size = self:FontInfo()
    local widest = 0
    for _, line in ipairs(wrap(self.text or "", size, nil)) do
        local w = measure(line, size)
        if w > widest then widest = w end
    end
    return widest
end

local cache, cacheGeneration, resolving = {}, -1, {}

-- Screen rect in UIParent units, y up, or nil when the anchors do not settle it.
function Region:Rect()
    if cacheGeneration ~= generation then
        cache, cacheGeneration = {}, generation
    end
    local cached = cache[self]
    if cached ~= nil then return cached or nil end
    if self.isRoot then
        cached = { left = 0, right = self.width, bottom = 0, top = self.height }
        cache[self] = cached
        return cached
    end
    if resolving[self] then return nil end
    resolving[self] = true
    local rect = self:ResolveRect()
    resolving[self] = nil
    cache[self] = rect or false
    return rect
end

function Region:ResolveRect()
    local scale = self:GetEffectiveScale()
    if self.scrollParent then
        local frame = self.scrollParent:Rect()
        if not frame then return nil end
        local w, h = (self.width or 0) * scale, (self.height or 0) * scale
        local top = frame.top + (self.scrollParent.verticalScroll or 0) * scale
        return { left = frame.left, right = frame.left + w, top = top, bottom = top - h }
    end
    if self.thumbOf then
        -- A slider places its thumb along the track by value, whatever the thumb's own anchors.
        local slider = self.thumbOf
        local track = slider:Rect()
        if not track then return nil end
        local low, high = slider:GetMinMaxValues()
        local fraction = high > low and ((slider.value or low) - low) / (high - low) or 0
        local w, h = (self.width or 8) * scale, (self.height or 8) * scale
        if slider:GetOrientation() == "VERTICAL" then
            local top = track.top - fraction * ((track.top - track.bottom) - h)
            local cx = (track.left + track.right) / 2
            return { left = cx - w / 2, right = cx + w / 2, top = top, bottom = top - h }
        end
        local left = track.left + fraction * ((track.right - track.left) - w)
        local cy = (track.top + track.bottom) / 2
        return { left = left, right = left + w, top = cy + h / 2, bottom = cy - h / 2 }
    end
    local L, R, T, B, CX, CY
    for _, p in ipairs(self.points) do
        local relative = p.rel or self.parent or self.env.UIParent
        local rr = relative ~= self and relative.Rect and relative:Rect()
        if rr then
            local ax, ay = coord(rr, p.relPoint)
            local x, y = ax + p.x * scale, ay + p.y * scale
            local h, v = H_PART[p.point], V_PART[p.point]
            if h == "L" then L = x elseif h == "R" then R = x else CX = x end
            if v == "T" then T = y elseif v == "B" then B = y else CY = y end
        end
    end
    local isText = self.kind == "FontString"
    local width = self.width and self.width > 0 and self.width * scale or nil
    if not width and isText and not (L and R) then width = self:NaturalWidth() * scale end
    if L and R then
        L, R = math.min(L, R), math.max(L, R)
    elseif L and width then R = L + width
    elseif R and width then L = R - width
    elseif CX and width then L, R = CX - width / 2, CX + width / 2
    elseif CX and L then R = 2 * CX - L
    elseif CX and R then L = 2 * CX - R
    else return nil end
    local height = self.height and self.height > 0 and self.height * scale or nil
    if not height and isText and not (T and B) then
        local size = self:FontInfo()
        height = #self:TextLines((R - L) / scale) * size * LINE_FACTOR * scale
    end
    if T and B then
        T, B = math.max(T, B), math.min(T, B)
    elseif T and height then B = T - height
    elseif B and height then T = B + height
    elseif CY and height then T, B = CY + height / 2, CY - height / 2
    elseif CY and T then B = 2 * CY - T
    elseif CY and B then T = 2 * CY - B
    else return nil end
    return { left = L, right = R, top = T, bottom = B }
end

function Region:GetWidth()
    local rect = self:Rect()
    if rect then return (rect.right - rect.left) / self:GetEffectiveScale() end
    if self.kind == "FontString" and not self.width then return self:NaturalWidth() end
    return self.width or 0
end
function Region:GetHeight()
    local rect = self:Rect()
    if rect then return (rect.top - rect.bottom) / self:GetEffectiveScale() end
    return self.height or 0
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetLeft() local r = self:Rect() return r and r.left / self:GetEffectiveScale() end
function Region:GetRight() local r = self:Rect() return r and r.right / self:GetEffectiveScale() end
function Region:GetTop() local r = self:Rect() return r and r.top / self:GetEffectiveScale() end
function Region:GetBottom() local r = self:Rect() return r and r.bottom / self:GetEffectiveScale() end
function Region:GetCenter()
    local r = self:Rect()
    if not r then return nil end
    local s = self:GetEffectiveScale()
    return (r.left + r.right) / 2 / s, (r.top + r.bottom) / 2 / s
end
function Region:GetRect()
    local r = self:Rect()
    if not r then return nil end
    local s = self:GetEffectiveScale()
    return r.left / s, r.bottom / s, (r.right - r.left) / s, (r.top - r.bottom) / s
end
function Region:IsRectValid() return self:Rect() ~= nil end

-- Visibility and state ---------------------------------------------------------------------

function Region:Show()
    local was = self:IsVisible()
    self.shown = true
    touch()
    if not was and self:IsVisible() and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Region:Hide()
    local was = self:IsVisible()
    self.shown = false
    touch()
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Region:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Region:IsShown() return self.shown == true end
function Region:IsVisible()
    local node = self
    while node do
        if not node.shown then return false end
        node = node.parent
    end
    return true
end
function Region:SetAlpha(alpha) self.alpha = alpha touch() end
function Region:GetAlpha() return self.alpha end
function Region:GetEffectiveAlpha()
    local alpha, node = 1, self
    while node do alpha = alpha * (node.alpha or 1) node = node.parent end
    return alpha
end
function Region:SetFrameStrata(strata) self.strata = strata touch() end
function Region:GetFrameStrata()
    local node = self
    while node do
        if node.strata then return node.strata end
        node = node.parent
    end
    return "MEDIUM"
end
function Region:SetFrameLevel(level) self.level = level touch() end
function Region:GetFrameLevel()
    if self.level then return self.level end
    local depth, node = 0, self.parent
    while node do
        if node.level then return node.level + depth + 1 end
        depth = depth + 1
        node = node.parent
    end
    return depth
end
-- Raise puts a frame above every other frame of its strata, as the client does.
function Region:Raise()
    local strata, top = self:GetFrameStrata(), 0
    for _, other in ipairs(self.env.frames) do
        if other ~= self and other.kind ~= "Texture" and other.kind ~= "FontString" and other.GetFrameStrata
            and other.points and other:GetFrameStrata() == strata then
            top = math.max(top, other:GetFrameLevel())
        end
    end
    self.level = top + 1
    touch()
end
function Region:SetToplevel(on) self.toplevel = on == true end
function Region:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel or 0 touch() end
function Region:GetDrawLayer() return self.layer or "ARTWORK", self.sublevel or 0 end
function Region:GetObjectType() return self.kind end
function Region:IsObjectType(kind) return self.kind == kind end
function Region:GetName() return self.name end
function Region:SetClipsChildren(clips) self.clips = clips == true touch() end
function Region:IsProtected() return false end
function Region:IsForbidden() return false end
function Region:IsMouseOver() return self.env.hovered == self end
function Region:IsMouseEnabled() return self.mouse == true end
function Region:EnableMouse(enabled) self.mouse = enabled ~= false end
function Region:GetChildren() return unpack(self.children) end
function Region:GetRegions() return unpack(self.regions) end
function Region:GetNumChildren() return #self.children end

-- Scripts and events -----------------------------------------------------------------------

function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = old and function(...) old(...) fn(...) end or fn
end
function Region:HasScript() return true end
function Region:RegisterEvent(event) self.events[event] = true end
function Region:RegisterUnitEvent(event) self.events[event] = true end
function Region:UnregisterEvent(event) self.events[event] = nil end
function Region:UnregisterAllEvents() self.events = {} end
function Region:IsEventRegistered(event) return self.events[event] == true end

-- Textures ---------------------------------------------------------------------------------

function Region:CreateTexture(_, layer, _, sublevel)
    local texture = newRegion(self.env, "Texture", self)
    texture.layer, texture.sublevel = layer or "ARTWORK", sublevel or 0
    return texture
end
function Region:CreateFontString(_, layer, font)
    local text = newRegion(self.env, "FontString", self)
    text.layer, text.fontObject = layer or "ARTWORK", font
    text.justifyH, text.justifyV, text.wordWrap = "CENTER", "MIDDLE", true
    return text
end
function Region:CreateMaskTexture(_, layer) return self:CreateTexture(nil, layer) end
function Region:AddMaskTexture() end
function Region:SetTexture(texture)
    self.art = texture ~= nil and { kind = "file", value = texture } or nil
    touch()
end
function Region:GetTexture() return self.art and self.art.kind == "file" and self.art.value or nil end
function Region:SetAtlas(atlas, useSize)
    self.art = atlas and { kind = "atlas", value = atlas } or nil
    if useSize and atlas then
        local info = self.env.C_Texture.GetAtlasInfo(atlas)
        if info then self.width, self.height = info.width, info.height end
    end
    touch()
end
function Region:GetAtlas() return self.art and self.art.kind == "atlas" and self.art.value or nil end
function Region:SetColorTexture(r, g, b, a)
    self.art = { kind = "color", value = { r, g, b, a or 1 } }
    touch()
end
function Region:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } touch() end
function Region:GetVertexColor()
    local v = self.vertex or { 1, 1, 1, 1 }
    return v[1], v[2], v[3], v[4]
end
function Region:SetTexCoord(...) self.texCoord = { ... } touch() end
function Region:SetDesaturated(on) self.desaturation = on and 1 or 0 end
function Region:SetDesaturation(value) self.desaturation = value end
function Region:SetGradient(orientation, from, to)
    self.gradient = { orientation = orientation, from = from, to = to }
    touch()
end
function Region:SetBlendMode(mode) self.blend = mode end
function Region:SetRotation(radians) self.rotation = radians touch() end
function Region:GetRotation() return self.rotation or 0 end

-- Text -------------------------------------------------------------------------------------

function Region:SetText(text)
    self.text = text ~= nil and tostring(text) or nil
    touch()
    if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function Region:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end
function Region:GetText() return self.text or (self.kind == "FontString" and nil or "") end
function Region:SetFontObject(font)
    if type(font) == "table" then font = font.name end
    self.fontObject = font
    touch()
end
function Region:GetFontObject() return self.fontObject end
function Region:SetFont(file, size, flags) self.fontFile, self.fontSize, self.fontFlags = file, size, flags touch() end
function Region:GetFont()
    local size = self:FontInfo()
    return self.fontFile or "Fonts\\FRIZQT__.TTF", size, self.fontFlags or ""
end
function Region:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
function Region:GetTextColor()
    local _, object = self:FontInfo()
    local c = self.textColor or object.color
    return c[1], c[2], c[3], c[4]
end
function Region:SetJustifyH(value) self.justifyH = value touch() end
function Region:SetJustifyV(value) self.justifyV = value touch() end
function Region:GetJustifyH() return self.justifyH end
function Region:SetWordWrap(value) self.wordWrap = value touch() end
function Region:SetMaxLines(value) self.maxLines = value touch() end
function Region:SetNonSpaceWrap() end
function Region:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a } end
function Region:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
function Region:SetSpacing(value) self.spacing = value end
function Region:GetStringWidth()
    if self.kind ~= "FontString" then return 0 end
    return self:NaturalWidth()
end
function Region:GetUnboundedStringWidth() return self:NaturalWidth() end
function Region:GetStringHeight()
    local size = self:FontInfo()
    local width = self.width
    if not width then
        local rect = self:Rect()
        width = rect and (rect.right - rect.left) / self:GetEffectiveScale()
    end
    return #self:TextLines(width) * size * LINE_FACTOR
end
function Region:GetLineHeight() return (self:FontInfo()) * LINE_FACTOR end
function Region:IsTruncated() return false end

-- Buttons, checks, sliders, edit boxes, scroll frames ---------------------------------------

local function ownTexture(frame, texture, layer)
    if type(texture) == "string" or type(texture) == "number" then
        local made = frame:CreateTexture(nil, layer)
        made:SetTexture(texture)
        made:SetAllPoints()
        return made
    end
    if texture and texture.SetDrawLayer then texture.layer = layer or texture.layer end
    return texture
end
function Region:SetNormalTexture(t) self.normalTexture = ownTexture(self, t, "ARTWORK") end
local function stateTexture(frame, t)
    local texture = ownTexture(frame, t, "ARTWORK")
    if texture then texture.stateHidden = true end
    return texture
end
function Region:SetPushedTexture(t) self.pushedTexture = stateTexture(self, t) end
function Region:SetDisabledTexture(t) self.disabledTexture = stateTexture(self, t) end
function Region:SetHighlightTexture(t) self.highlightTexture = ownTexture(self, t, "HIGHLIGHT") end
function Region:SetCheckedTexture(t)
    self.checkedTexture = ownTexture(self, t, "ARTWORK")
    if self.checkedTexture then self.checkedTexture.stateHidden = not self.checked end
end
function Region:SetDisabledCheckedTexture(t)
    self.disabledCheckedTexture = ownTexture(self, t, "ARTWORK")
    if self.disabledCheckedTexture then self.disabledCheckedTexture.stateHidden = true end
end
function Region:GetNormalTexture() return self.normalTexture end
function Region:GetHighlightTexture() return self.highlightTexture end
function Region:GetPushedTexture() return self.pushedTexture end
function Region:GetCheckedTexture() return self.checkedTexture end
function Region:UpdateCheckArt()
    local enabled = self.enabled ~= false
    if self.checkedTexture then self.checkedTexture.stateHidden = not (self.checked and enabled) end
    if self.disabledCheckedTexture then
        self.disabledCheckedTexture.stateHidden = not (self.checked and not enabled)
        if self.checkedTexture and not self.disabledCheckedTexture then
            self.checkedTexture.stateHidden = not self.checked
        end
    end
    touch()
end
function Region:SetChecked(checked) self.checked = checked == true self:UpdateCheckArt() end
function Region:GetChecked() return self.checked == true end
function Region:SetEnabled(enabled)
    self.enabled = enabled ~= false
    if self.UpdateCheckArt then self:UpdateCheckArt() end
    local script = self.scripts[self.enabled and "OnEnable" or "OnDisable"]
    if script then script(self) end
end
function Region:Enable() self:SetEnabled(true) end
function Region:Disable() self:SetEnabled(false) end
function Region:IsEnabled() return self.enabled ~= false end
function Region:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton", false) end end
function Region:SetID(id) self.id = id end
function Region:GetID() return self.id or 0 end

function Region:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum touch() end
function Region:GetMinMaxValues() return self.minimum or 0, self.maximum or 0 end
function Region:SetValue(value)
    local low, high = self.minimum or value, self.maximum or value
    if self.kind == "Slider" then value = math.max(low, math.min(high, value)) end
    local changed = self.value ~= value
    self.value = value
    touch()
    if changed and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value, false) end
end
function Region:GetValue() return self.value or 0 end
function Region:SetThumbTexture(texture)
    if type(texture) ~= "table" then texture = ownTexture(self, texture, "ARTWORK") end
    self.thumbTexture = texture
    if texture then texture.thumbOf = self end
    touch()
end
function Region:GetThumbTexture() return self.thumbTexture end
function Region:SetOrientation(orientation) self.orientation = orientation end
function Region:GetOrientation() return self.orientation or "HORIZONTAL" end
function Region:SetValueStep(step) self.step = step end
function Region:GetValueStep() return self.step or 1 end
function Region:SetStatusBarTexture(texture) self.barTexture = texture end
function Region:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a } end

function Region:SetScrollChild(child)
    self.scrollChild = child
    child.scrollParent = self
    touch()
end
function Region:GetScrollChild() return self.scrollChild end
function Region:SetVerticalScroll(value) self.verticalScroll = value touch() end
function Region:GetVerticalScroll() return self.verticalScroll or 0 end
function Region:GetVerticalScrollRange()
    local child = self.scrollChild
    if not child then return 0 end
    return math.max(0, (child.height or 0) - self:GetHeight())
end
function Region:SetHorizontalScroll() end
function Region:UpdateScrollChildRect() end

function Region:SetTextInsets(l, r, t, b) self.insets = { l or 0, r or 0, t or 0, b or 0 } end
function Region:SetMultiLine(multi) self.multiLine = multi == true end
function Region:IsMultiLine() return self.multiLine == true end
function Region:HasFocus() return self.focus == true end
function Region:SetFocus() self.focus = true end
function Region:ClearFocus() self.focus = false end
function Region:SetCursorPosition() end
function Region:HighlightText() end
function Region:GetNumLetters() return #(self.text or "") end
function Region:Insert(text) self:SetText((self.text or "") .. text) end

-- Animation groups never run in a still picture; they are kept so code can drive them.
function Region:CreateAnimationGroup()
    local group = newRegion(self.env, "AnimationGroup", nil)
    group.target = self
    return group
end
function Region:CreateAnimation(kind)
    local anim = newRegion(self.env, "Animation", nil)
    anim.animKind = kind
    return anim
end
function Region:Play() self.playing = true end
function Region:Stop() self.playing = false end
function Region:IsPlaying() return false end
function Region:GetSmoothProgress() return 0 end
function Region:GetProgress() return 0 end
function Region:SetOffset(x, y) self.offsetX, self.offsetY = x, y end
function Region:GetOffset() return self.offsetX or 0, self.offsetY or 0 end
function Region:GetDuration() return self.duration or 0 end
function Region:SetDuration(duration) self.duration = duration end

-- Dropdown button (Blizzard_Menu): enough to label itself from the selected radio.
function Region:SetupMenu(generator) self.menuGenerator = generator self:GenerateMenu() end
function Region:SetDefaultText(text) self.defaultText = text self:GenerateMenu() end
function Region:GetDefaultText() return self.defaultText end
function Region:GenerateMenu()
    if not self.label then return end
    local chosen
    if self.menuGenerator then
        local root = {}
        local sink = { SetTooltip = function() end, SetEnabled = function() end, CreateRadio = function() end,
            CreateButton = function() end }
        sink.CreateRadio = function() return sink end
        function root.CreateRadio(_, text, isSelected, _, value)
            if not chosen and isSelected(value) then chosen = text end
            return sink
        end
        function root.CreateButton() return sink end
        function root.CreateCheckbox() return sink end
        function root.CreateTitle() return sink end
        function root.CreateDivider() return sink end
        function root.SetTag() end
        function root.SetScrollMode() end
        pcall(self.menuGenerator, self, root)
    end
    self.label:SetText(chosen or self.defaultText or "")
end
function Region:OpenMenu() end
function Region:CloseMenu() end

-- Anything else: a setter is ignored, a getter answers nil. Named in the report so the
-- picture's blind spots are known.
Geometry.unknown = {}
local fallbackPrefixes = { "Set", "Enable", "Disable", "Register", "Unregister", "Start", "Stop", "Lock",
    "Unlock", "Add", "Clear", "Release", "Reset", "Update", "Hook" }
setmetatable(Region, { __index = function(_, key)
    if type(key) ~= "string" or not key:match("^%u") then return nil end
    Geometry.unknown[key] = (Geometry.unknown[key] or 0) + 1
    for _, prefix in ipairs(fallbackPrefixes) do
        if key:sub(1, #prefix) == prefix then return function() end end
    end
    return function() return nil end
end })

return Geometry
