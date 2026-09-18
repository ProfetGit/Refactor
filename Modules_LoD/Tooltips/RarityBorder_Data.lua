--- @module tooltips.rarityBorder (hot half, registers nothing)
--- Purpose: quality lookup and border tint with no allocation per tooltip shown.
--- Requires: C_Item.GetItemQualityByID, C_Item.GetItemQualityColor
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
