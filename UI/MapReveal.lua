local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

local FILTER = "TRILINEAR"

-- One frame the size of the map canvas, sitting one level under Blizzard's exploration pin
-- and holding a pool of textures. Made once and kept; the module shows and hides it and
-- sets its level each time it draws, because the map re-levels its pins.
function R.UI:MapRevealLayer(canvas)
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    frame.textures = R.Pools:Create(function()
        local texture = frame:CreateTexture(nil, "ARTWORK")
        Theme:Unexplored(texture)
        return texture
    end, function(texture)
        texture:Hide()
        texture:ClearAllPoints()
    end)
    return frame
end

function R.UI:MapRevealClear(frame)
    frame.textures:ReleaseAll()
end

-- The smallest power of two that holds a cut tile, which is how the client sizes the file.
local function fileSize(pixels)
    local size = 16
    while size < pixels do
        size = size * 2
    end
    return size
end

-- Mirrors MapExplorationPinMixin:RefreshOverlays. An overlay is a grid of tiles, whole ones
-- except the last column and row, which are cut to the overlay's size and read from a file
-- rounded up to a power of two. An overlay whose tile count does not fit its size is data
-- from another layer or a broken row, and is skipped rather than drawn wrong.
function R.UI:MapRevealDraw(frame, overlays, tileWidth, tileHeight)
    local pool = frame.textures
    for _, overlay in ipairs(overlays) do
        local wide = math.ceil(overlay.width / tileWidth)
        local tall = math.ceil(overlay.height / tileHeight)
        if #overlay.ids == wide * tall then
            for row = 1, tall do
                local height, fileHeight = tileHeight, tileHeight
                if row == tall then
                    height = overlay.height % tileHeight
                    if height == 0 then
                        height = tileHeight
                    end
                    fileHeight = fileSize(height)
                end
                for column = 1, wide do
                    local width, fileWidth = tileWidth, tileWidth
                    if column == wide then
                        width = overlay.width % tileWidth
                        if width == 0 then
                            width = tileWidth
                        end
                        fileWidth = fileSize(width)
                    end
                    local texture = pool:Acquire()
                    texture:SetSize(width, height)
                    texture:SetTexCoord(0, width / fileWidth, 0, height / fileHeight)
                    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", overlay.x + tileWidth * (column - 1),
                        -(overlay.y + tileHeight * (row - 1)))
                    texture:SetTexture(overlay.ids[(row - 1) * wide + column], nil, nil, FILTER)
                    texture:Show()
                end
            end
        end
    end
end
