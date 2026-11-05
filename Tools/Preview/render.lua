-- Draws the preview environment as one HTML page: every visible texture and font string an
-- absolutely placed box, in the client's draw order, clipped by the frames that clip. Blizzard
-- atlases are not on disk, so each is drawn as a CSS stand-in keyed by name (preview.css);
-- Refactor's own TGA art is drawn from PNG copies, tinted the way SetVertexColor tints it.
local Geometry = require("geometry")
local Render = {}

local STRATA, LAYERS = Geometry.strata, Geometry.layers

local function isRegion(object) return object.kind == "Texture" or object.kind == "FontString" end

local function owner(object)
    if isRegion(object) then return object.parent end
    return object
end

local function visible(object, hovered)
    if object.stateHidden then return false end
    if object.layer == "HIGHLIGHT" then
        local node, lit = object.parent, false
        while node do
            if node == hovered then lit = true break end
            node = node.parent
        end
        if not lit then return false end
    end
    local node = object
    while node do
        if not node.shown then return false end
        node = node.parent
    end
    return true
end

local function clipRect(object)
    local clip
    local node = object.parent
    while node do
        if node.clips or node.kind == "ScrollFrame" then
            local r = node:Rect()
            if r then
                if not clip then
                    clip = { left = r.left, right = r.right, top = r.top, bottom = r.bottom }
                else
                    clip.left = math.max(clip.left, r.left)
                    clip.right = math.min(clip.right, r.right)
                    clip.top = math.min(clip.top, r.top)
                    clip.bottom = math.max(clip.bottom, r.bottom)
                end
            end
        end
        node = node.parent
    end
    return clip
end

local function escapeHTML(text)
    return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function rgba(c, alpha)
    if not c then return "transparent" end
    local r, g, b, a = c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, c[4] or c.a or 1
    return string.format("rgba(%d,%d,%d,%.3f)", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), a * (alpha or 1))
end

-- Colour codes to spans, inline textures to small boxes, newlines kept.
local function markup(text)
    text = escapeHTML(text or "")
    local out, open = {}, 0
    local i = 1
    while i <= #text do
        local c = text:sub(i, i)
        if c == "|" then
            local nextChar = text:sub(i + 1, i + 1)
            if nextChar == "c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
                local hex = text:sub(i + 4, i + 9)
                out[#out + 1] = '<span style="color:#' .. hex .. '">'
                open = open + 1
                i = i + 10
            elseif nextChar == "r" then
                if open > 0 then out[#out + 1] = "</span>" open = open - 1 end
                i = i + 2
            elseif nextChar == "n" then
                out[#out + 1] = "<br>"
                i = i + 2
            elseif nextChar == "T" or nextChar == "A" then
                local close = nextChar == "T" and "|t" or "|a"
                local stop = text:find(close, i + 2, true)
                local body = stop and text:sub(i + 2, stop - 1) or ""
                local size = tonumber(body:match(":(%d+)")) or 12
                if size == 0 then size = 12 end
                out[#out + 1] = string.format('<i class="inline" title="%s" style="width:%dpx;height:%dpx"></i>',
                    body, size, size)
                i = (stop or #text) + 2
            elseif nextChar == "H" then
                local stop = text:find("|h", i + 2, true)
                i = (stop or #text) + 2
            elseif nextChar == "h" then
                i = i + 2
            else
                out[#out + 1] = c
                i = i + 1
            end
        elseif c == "\n" then
            out[#out + 1] = "<br>"
            i = i + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    for _ = 1, open do out[#out + 1] = "</span>" end
    return table.concat(out)
end

local MEDIA_PREFIX = "interface\\addons\\refactor\\media\\"

local function fileStyle(value, vertex, texCoord, assets)
    if type(value) == "number" then
        local known = { [616343] = true, [136430] = true, [136467] = true, [136477] = true }
        return nil, "file-" .. value .. (known[value] and "" or " itemicon"), "fileID " .. value
    end
    local lower = tostring(value):lower():gsub("/", "\\")
    if lower:sub(1, #MEDIA_PREFIX) == MEDIA_PREFIX then
        local name = lower:sub(#MEDIA_PREFIX + 1):gsub("%.tga$", ""):gsub("%.blp$", "")
        local png = assets[name]
        if png then
            local size, position = "100% 100%", "0 0"
            if texCoord and #texCoord == 4 then
                local l, r, t, b = texCoord[1], texCoord[2], texCoord[3], texCoord[4]
                local w, h = r - l, b - t
                if w ~= 0 and h ~= 0 and (w ~= 1 or h ~= 1) then
                    size = string.format("%.3f%% %.3f%%", 100 / math.abs(w), 100 / math.abs(h))
                    local px = math.abs(w) < 1 and (l / (1 - math.abs(w))) * 100 or 0
                    local py = math.abs(h) < 1 and (t / (1 - math.abs(h))) * 100 or 0
                    position = string.format("%.3f%% %.3f%%", px, py)
                end
            end
            local tinted = vertex and (vertex[1] ~= 1 or vertex[2] ~= 1 or vertex[3] ~= 1)
            if tinted then
                return string.format("background-color:%s;-webkit-mask-image:url(%s);mask-image:url(%s);"
                    .. "mask-size:%s;-webkit-mask-size:%s;mask-position:%s;-webkit-mask-position:%s;"
                    .. "mask-repeat:no-repeat;-webkit-mask-repeat:no-repeat;", rgba(vertex), png, png, size, size,
                    position, position), nil, name
            end
            return string.format("background-image:url(%s);background-size:%s;background-position:%s;"
                .. "background-repeat:no-repeat;%s", png, size, position,
                vertex and vertex[4] and vertex[4] < 1 and ("opacity:" .. vertex[4] .. ";") or ""), nil, name
        end
        return nil, "missing", name
    end
    local short = lower:match("([^\\]+)$") or lower
    return nil, "file-" .. short:gsub("[^%w]", "-"), tostring(value)
end

local function textureBox(t, assets)
    local art = t.art
    local style, class = "", "tex"
    local vertex = t.vertex
    if t.gradient then
        local g = t.gradient
        local dir = g.orientation == "HORIZONTAL" and "to right" or "to top"
        style = string.format("background:linear-gradient(%s,%s,%s);", dir, rgba(g.from), rgba(g.to))
        return style, class, "gradient"
    end
    if not art then return nil end
    if art.kind == "color" then
        local c = art.value
        local v = vertex or { 1, 1, 1, 1 }
        style = "background:" .. rgba({ c[1] * v[1], c[2] * v[2], c[3] * v[3], (c[4] or 1) * (v[4] or 1) }) .. ";"
        return style, class, "color"
    elseif art.kind == "atlas" then
        local name = tostring(art.value)
        local key = name:lower():gsub("[^%w]", "-")
        class = class .. " atlas a-" .. key
        if vertex and (vertex[1] ~= 1 or vertex[2] ~= 1 or vertex[3] ~= 1) then
            style = style .. "--tint:" .. rgba(vertex) .. ";"
            class = class .. " tinted"
        end
        return style, class, name
    else
        local fstyle, fclass, ftitle = fileStyle(art.value, vertex, t.texCoord, assets)
        if fstyle then return fstyle, class .. " file", ftitle end
        if vertex and (vertex[1] ~= 1 or vertex[2] ~= 1 or vertex[3] ~= 1) then
            style = style .. "--tint:" .. rgba(vertex) .. ";"
            fclass = fclass .. " tinted"
        end
        return style, class .. " file " .. fclass, ftitle
    end
end

local function drawKey(object)
    local frame = owner(object)
    local strata = STRATA[frame:GetFrameStrata()] or 3
    local level = frame:GetFrameLevel()
    local layer = isRegion(object) and (LAYERS[object.layer or "ARTWORK"] or 3) or 2
    return { strata, level, layer, object.sublevel or 0, object.order }
end

local function before(a, b)
    for index = 1, 5 do
        if a.key[index] ~= b.key[index] then return a.key[index] < b.key[index] end
    end
    return false
end

-- One entry per box: the texture or font string, or a frame drawn for a template (border,
-- edit box text).
function Render.collect(env, hovered)
    local items = {}
    for _, object in ipairs(env.frames) do
        local kind = object.kind
        local drawable = kind == "Texture" or kind == "FontString" or object.nineSlice
            or (kind == "EditBox" and (object.text or "") ~= "")
        if drawable and visible(object, hovered) and object:GetEffectiveAlpha() > 0.001 then
            local rect = object:Rect()
            if rect and rect.right - rect.left > 0.01 and rect.top - rect.bottom > 0.01 then
                items[#items + 1] = { object = object, rect = rect, key = drawKey(object) }
            end
        end
    end
    table.sort(items, before)
    return items
end

local function textHTML(object, rect, scale, flags)
    local size = (object:FontInfo()) * scale
    local r, g, b, a = object:GetTextColor()
    local width = (rect.right - rect.left) / scale
    local lines = object:TextLines((object.width or (object.points[2] and width)) and width or nil)
    local lineHeight = size * 1.15
    local justifyH = (object.justifyH or "CENTER"):upper()
    local justifyV = (object.justifyV or "MIDDLE"):upper()
    local align = justifyH == "LEFT" and "left" or justifyH == "RIGHT" and "right" or "center"
    local valign = justifyV == "TOP" and "flex-start" or justifyV == "BOTTOM" and "flex-end" or "center"
    local wrapText = object.wordWrap ~= false and (object.width or #object.points >= 2)
    local shadow = "1px 1px 0 rgba(0,0,0,0.9)"
    if (object.fontFlags or ""):find("OUTLINE") then
        shadow = "-1px 0 0 #000,1px 0 0 #000,0 -1px 0 #000,0 1px 0 #000,1px 1px 0 #000"
    end
    local natural = object:NaturalWidth() * scale
    local truncated = (not wrapText and natural > (rect.right - rect.left) + 1.5)
        or (#lines * lineHeight > (rect.top - rect.bottom) + lineHeight * 0.5)
    if truncated then flags[#flags + 1] = "trunc" end
    local style = string.format("font-size:%.2fpx;line-height:%.2fpx;color:%s;text-align:%s;"
        .. "justify-content:%s;align-items:%s;text-shadow:%s;white-space:%s;",
        size, lineHeight, rgba({ r, g, b, a }), align, align == "left" and "flex-start"
        or align == "right" and "flex-end" or "center", valign, shadow, wrapText and "normal" or "nowrap")
    return style, '<span class="t">' .. markup(object.text or "") .. "</span>"
end

function Render.page(env, options)
    options = options or {}
    local assets = options.assets or {}
    local screenH = env.UIParent.height
    local out = {}
    local items = Render.collect(env, options.hovered)
    local truncatedCount = 0
    for z, item in ipairs(items) do
        local object, rect = item.object, item.rect
        local left, top = rect.left, screenH - rect.top
        local width, height = rect.right - rect.left, rect.top - rect.bottom
        local alpha = object:GetEffectiveAlpha()
        local style = string.format("left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;z-index:%d;",
            left, top, width, height, z)
        if alpha < 0.999 then style = style .. string.format("opacity:%.3f;", alpha) end
        local clip = clipRect(object)
        if clip then
            local cl, cr = clip.left - rect.left, rect.right - clip.right
            local ct, cb = rect.top - clip.top, clip.bottom - rect.bottom
            if cl > 0 or cr > 0 or ct > 0 or cb > 0 then
                if cl + cr >= width or ct + cb >= height then
                    style = nil
                else
                    style = style .. string.format("clip-path:inset(%.2fpx %.2fpx %.2fpx %.2fpx);",
                        math.max(0, ct), math.max(0, cr), math.max(0, cb), math.max(0, cl))
                end
            end
        end
        if style then
            local scale = object:GetEffectiveScale()
            if object.kind == "Texture" then
                local tstyle, class, title = textureBox(object, assets)
                if tstyle then
                    if object.rotation and object.rotation ~= 0 then
                        tstyle = tstyle .. string.format("transform:rotate(%.3frad);", -object.rotation)
                    end
                    if object.blend == "ADD" then tstyle = tstyle .. "mix-blend-mode:screen;" end
                    if object.desaturation and object.desaturation > 0 then
                        tstyle = tstyle .. string.format("filter:grayscale(%.2f);", object.desaturation)
                    end
                    out[#out + 1] = string.format('<div class="%s" title="%s" style="%s%s"></div>',
                        class, escapeHTML(title or ""), style, tstyle)
                end
            elseif object.kind == "FontString" then
                local flags = {}
                local tstyle, inner = textHTML(object, rect, scale, flags)
                if #flags > 0 then truncatedCount = truncatedCount + 1 end
                out[#out + 1] = string.format('<div class="fs %s" title="%s" style="%s%s">%s</div>',
                    table.concat(flags, " "), escapeHTML(object.text or ""), style, tstyle, inner)
            elseif object.kind == "EditBox" then
                local insets = object.insets or { 0, 0, 0, 0 }
                local size = (object:FontInfo()) * scale
                local r, g, b, a = object:GetTextColor()
                out[#out + 1] = string.format('<div class="edit" style="%spadding:%dpx %dpx %dpx %dpx;'
                    .. 'font-size:%.2fpx;color:%s;align-items:%s;white-space:%s">%s</div>', style,
                    insets[3] * scale, insets[2] * scale, insets[4] * scale, insets[1] * scale, size,
                    rgba({ r, g, b, a }), object.multiLine and "flex-start" or "center",
                    object.multiLine and "pre-wrap" or "nowrap", markup(object.text or ""))
            else
                out[#out + 1] = string.format('<div class="nine nine-%s" style="%s"></div>',
                    tostring(object.nineSlice):lower():gsub("[^%w]", "-"), style)
            end
        end
    end
    return table.concat(out, "\n"), truncatedCount, #items
end

return Render
