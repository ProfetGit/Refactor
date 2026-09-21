--- @module tooltips.rarityBorder (hot half, registers nothing)
--- Purpose: quality lookup and border tint with no allocation per tooltip shown.
--- Requires: C_Item.GetItemQualityByID, C_Item.GetItemQualityColor, C_ClassColor.GetClassColor
--- Events: none, the module owns the pending lookup
--- Hot: yes
-- @hot
local _, R = ...

local Border = {}
R.RarityBorderData = Border

-- Permanent by design (PRD 7.7.2): an item ID never changes quality, so there is no
-- invalidation event. Keyed by number, never by a built string.
local qualities = {}
-- Three flat tables rather than one table per quality: filled once at enable.
local reds = {}
local greens = {}
local blues = {}
local MAX_QUALITY = 8

function Border:LoadColors()
    for quality = 0, MAX_QUALITY do
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if type(r) == "number" then
            reds[quality], greens[quality], blues[quality] = r, g, b
        end
    end
end

function Border:Tint(tooltip, quality)
    local nineSlice = tooltip.NineSlice
    if nineSlice and reds[quality] then
        nineSlice:SetBorderColor(reds[quality], greens[quality], blues[quality], 1)
    end
end

-- The quality of the item ID is the base item's. A scaled or modified drop shows a
-- different colour in its own name line, which is the colour the player actually sees.
function Border:TintColor(tooltip, r, g, b)
    local nineSlice = tooltip.NineSlice
    if nineSlice and type(r) == "number" then
        nineSlice:SetBorderColor(r, g, b, 1)
        return true
    end
end

-- Class colours are the client's own and do not change while you are logged in, so each is
-- read the first time a player of that class is hovered and kept. Permanent by design, the
-- same exception the quality cache above is, and keyed by the client's class string rather
-- than anything built here.
local classReds = {}
local classGreens = {}
local classBlues = {}

function Border:TintClass(tooltip, classFile)
    local red = classReds[classFile]
    if red == nil then
        local color = C_ClassColor.GetClassColor(classFile)
        if type(color) ~= "table" or type(color.GetRGB) ~= "function" then
            return false
        end
        classReds[classFile], classGreens[classFile], classBlues[classFile] = color:GetRGB()
        red = classReds[classFile]
    end
    return self:TintColor(tooltip, red, classGreens[classFile], classBlues[classFile]) == true
end

function Border:Clear(tooltip)
    local nineSlice = tooltip.NineSlice
    if nineSlice then
        nineSlice:SetBorderColor(1, 1, 1, 1)
    end
end

-- Returns the quality, or nil when the client has not cached the item yet.
function Border:Quality(itemID)
    local quality = qualities[itemID]
    if quality then
        return quality
    end
    quality = C_Item.GetItemQualityByID(itemID)
    if quality then
        qualities[itemID] = quality
    end
    return quality
end
