-- Refactor Addon - Edit Mode Framework
-- Reusable edit mode container with Blizzard-style highlight, drag, and settings flyout

local addonName, addon = ...

local EditMode = {}
addon.EditMode = EditMode

----------------------------------------------
-- Atlas Constants
----------------------------------------------
local ATLAS_MAIN = "Interface/Editmode/EditModeUI"
local ATLAS_VERT = "Interface/Editmode/EditModeUIVertical"
local ATLAS_HIGHLIGHT_BG = "Interface/Editmode/EditModeUIHighlightBackground"
local ATLAS_SELECTED_BG = "Interface/Editmode/EditModeUISelectedBackground"

-- Diamond Metal Frame Atlas
local FRAME_ATLAS = "Interface/FrameGeneral/UIFrameDiamondMetal2x"
local FRAME_BG_COLOR = {0.05, 0.05, 0.05, 0.95}

----------------------------------------------
-- Helpers
----------------------------------------------
local function SetupAtlasTexture(tex, atlas, left, right, top, bottom, horizTile, vertTile)
    tex:SetTexture(atlas)
    tex:SetTexCoord(left, right, top, bottom)
    tex:SetHorizTile(horizTile or false)
    tex:SetVertTile(vertTile or false)
end

----------------------------------------------
-- Scale Helper: Scales a frame while keeping top-right corner fixed
-- This mimics Blizzard's native edit mode behavior where only
-- the left and bottom edges move when scaling
----------------------------------------------
local function SetScaleFromTopRight(frame, newScale)
    -- Get current top-right position in screen coordinates (before scale change)
    local currentScale = frame:GetScale()
    local effectiveScale = frame:GetEffectiveScale()
    
    local right = frame:GetRight()
    local top = frame:GetTop()
    
    if not right or not top then
        -- Frame not yet positioned, just set scale
        frame:SetScale(newScale)
        return
    end
    
    -- Calculate top-right in absolute screen coords
    local screenRight = right * currentScale
    local screenTop = top * currentScale
    
    -- Apply new scale
    frame:SetScale(newScale)
    
    -- Calculate where top-right would be with new scale (using current anchor)
    local newRight = frame:GetRight()
    local newTop = frame:GetTop()
    
    if not newRight or not newTop then return end
    
    local newScreenRight = newRight * newScale
    local newScreenTop = newTop * newScale
    
    -- Calculate offset needed to keep top-right at same position
    local offsetX = (screenRight - newScreenRight) / newScale
    local offsetY = (screenTop - newScreenTop) / newScale
    
    -- Adjust frame position
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    if point then
        frame:ClearAllPoints()
        frame:SetPoint(point, relativeTo, relativePoint, x + offsetX, y + offsetY)
    end
end

----------------------------------------------
-- Nine-Slice Highlight Creation
----------------------------------------------
local function CreateNineSliceHighlight(parent, prefix, bgAtlas)
    local CORNER_SIZE = 16
    local EDGE_SIZE = 16
    local CORNER_OFFSET = 8
    
    local ns = {}
    
    -- Center (background)
    ns.center = parent:CreateTexture(nil, "BACKGROUND")
    ns.center:SetAllPoints()
    SetupAtlasTexture(ns.center, bgAtlas, 0, 1, 0, 1, true, true)
    
    -- Corner coordinates
    local cornerCoords = prefix == "highlight" 
        and {0.03125, 0.53125, 0.285156, 0.347656}
        or {0.03125, 0.53125, 0.355469, 0.417969}
    
    -- Corners
    ns.topleft = parent:CreateTexture(nil, "BORDER")
    ns.topleft:SetSize(CORNER_SIZE, CORNER_SIZE)
    ns.topleft:SetPoint("TOPLEFT", -CORNER_OFFSET, CORNER_OFFSET)
    SetupAtlasTexture(ns.topleft, ATLAS_MAIN, cornerCoords[1], cornerCoords[2], cornerCoords[3], cornerCoords[4], false, false)
    
    ns.topright = parent:CreateTexture(nil, "BORDER")
    ns.topright:SetSize(CORNER_SIZE, CORNER_SIZE)
    ns.topright:SetPoint("TOPRIGHT", CORNER_OFFSET, CORNER_OFFSET)
    SetupAtlasTexture(ns.topright, ATLAS_MAIN, cornerCoords[2], cornerCoords[1], cornerCoords[3], cornerCoords[4], false, false)
    
    ns.bottomleft = parent:CreateTexture(nil, "BORDER")
    ns.bottomleft:SetSize(CORNER_SIZE, CORNER_SIZE)
    ns.bottomleft:SetPoint("BOTTOMLEFT", -CORNER_OFFSET, -CORNER_OFFSET)
    SetupAtlasTexture(ns.bottomleft, ATLAS_MAIN, cornerCoords[1], cornerCoords[2], cornerCoords[4], cornerCoords[3], false, false)
    
    ns.bottomright = parent:CreateTexture(nil, "BORDER")
    ns.bottomright:SetSize(CORNER_SIZE, CORNER_SIZE)
    ns.bottomright:SetPoint("BOTTOMRIGHT", CORNER_OFFSET, -CORNER_OFFSET)
    SetupAtlasTexture(ns.bottomright, ATLAS_MAIN, cornerCoords[2], cornerCoords[1], cornerCoords[4], cornerCoords[3], false, false)
    
    -- Horizontal edges
    local topEdgeCoords = prefix == "highlight"
        and {0, 0.5, 0.0742188, 0.136719}
        or {0, 0.5, 0.214844, 0.277344}
    local bottomEdgeCoords = prefix == "highlight"
        and {0, 0.5, 0.00390625, 0.0664062}
        or {0, 0.5, 0.144531, 0.207031}
    
    ns.top = parent:CreateTexture(nil, "BORDER")
    ns.top:SetHeight(EDGE_SIZE)
    ns.top:SetPoint("TOPLEFT", CORNER_SIZE - CORNER_OFFSET, CORNER_OFFSET)
    ns.top:SetPoint("TOPRIGHT", -(CORNER_SIZE - CORNER_OFFSET), CORNER_OFFSET)
    SetupAtlasTexture(ns.top, ATLAS_MAIN, topEdgeCoords[1], topEdgeCoords[2], topEdgeCoords[3], topEdgeCoords[4], true, false)
    
    ns.bottom = parent:CreateTexture(nil, "BORDER")
    ns.bottom:SetHeight(EDGE_SIZE)
    ns.bottom:SetPoint("BOTTOMLEFT", CORNER_SIZE - CORNER_OFFSET, -CORNER_OFFSET)
    ns.bottom:SetPoint("BOTTOMRIGHT", -(CORNER_SIZE - CORNER_OFFSET), -CORNER_OFFSET)
    SetupAtlasTexture(ns.bottom, ATLAS_MAIN, bottomEdgeCoords[1], bottomEdgeCoords[2], bottomEdgeCoords[3], bottomEdgeCoords[4], true, false)
    
    -- Vertical edges
    local leftEdgeCoords = prefix == "highlight"
        and {0.0078125, 0.132812, 0, 1}
        or {0.289062, 0.414062, 0, 1}
    local rightEdgeCoords = prefix == "highlight"
        and {0.148438, 0.273438, 0, 1}
        or {0.429688, 0.554688, 0, 1}
    
    ns.left = parent:CreateTexture(nil, "BORDER")
    ns.left:SetWidth(EDGE_SIZE)
    ns.left:SetPoint("TOPLEFT", -CORNER_OFFSET, -(CORNER_SIZE - CORNER_OFFSET))
    ns.left:SetPoint("BOTTOMLEFT", -CORNER_OFFSET, CORNER_SIZE - CORNER_OFFSET)
    SetupAtlasTexture(ns.left, ATLAS_VERT, leftEdgeCoords[1], leftEdgeCoords[2], leftEdgeCoords[3], leftEdgeCoords[4], false, true)
    
    ns.right = parent:CreateTexture(nil, "BORDER")
    ns.right:SetWidth(EDGE_SIZE)
    ns.right:SetPoint("TOPRIGHT", CORNER_OFFSET, -(CORNER_SIZE - CORNER_OFFSET))
    ns.right:SetPoint("BOTTOMRIGHT", CORNER_OFFSET, CORNER_SIZE - CORNER_OFFSET)
    SetupAtlasTexture(ns.right, ATLAS_VERT, rightEdgeCoords[1], rightEdgeCoords[2], rightEdgeCoords[3], rightEdgeCoords[4], false, true)
    
    return ns
end

----------------------------------------------
-- Diamond Metal Frame Border (2x Atlas)
----------------------------------------------
local function CreateDiamondMetalFrame(parent)
    local CORNER_SIZE = 32  -- Full native size for best quality
    local EDGE_SIZE = 32    -- Match corner size
    
    -- Dark background - inset within border
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 6, -6)
    bg:SetPoint("BOTTOMRIGHT", -6, 6)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    
    -- =====================
    -- CORNERS (using SetAtlas for proper handling)
    -- =====================
    local cornerTL = parent:CreateTexture(nil, "BORDER")
    cornerTL:SetSize(CORNER_SIZE, CORNER_SIZE)
    cornerTL:SetPoint("TOPLEFT", 0, 0)
    cornerTL:SetAtlas("UI-Frame-DiamondMetal-CornerTopLeft", false)
    
    local cornerTR = parent:CreateTexture(nil, "BORDER")
    cornerTR:SetSize(CORNER_SIZE, CORNER_SIZE)
    cornerTR:SetPoint("TOPRIGHT", 0, 0)
    cornerTR:SetAtlas("UI-Frame-DiamondMetal-CornerTopRight", false)
    
    local cornerBL = parent:CreateTexture(nil, "BORDER")
    cornerBL:SetSize(CORNER_SIZE, CORNER_SIZE)
    cornerBL:SetPoint("BOTTOMLEFT", 0, 0)
    cornerBL:SetAtlas("UI-Frame-DiamondMetal-CornerBottomLeft", false)
    
    local cornerBR = parent:CreateTexture(nil, "BORDER")
    cornerBR:SetSize(CORNER_SIZE, CORNER_SIZE)
    cornerBR:SetPoint("BOTTOMRIGHT", 0, 0)
    cornerBR:SetAtlas("UI-Frame-DiamondMetal-CornerBottomRight", false)
    
    -- =====================
    -- TOP/BOTTOM EDGES (tiling)
    -- =====================
    local edgeT = parent:CreateTexture(nil, "BORDER")
    edgeT:SetHeight(EDGE_SIZE)
    edgeT:SetPoint("LEFT", cornerTL, "RIGHT", 0, 0)
    edgeT:SetPoint("RIGHT", cornerTR, "LEFT", 0, 0)
    edgeT:SetAtlas("_UI-Frame-DiamondMetal-EdgeTop", false)
    edgeT:SetHorizTile(true)
    
    local edgeB = parent:CreateTexture(nil, "BORDER")
    edgeB:SetHeight(EDGE_SIZE)
    edgeB:SetPoint("LEFT", cornerBL, "RIGHT", 0, 0)
    edgeB:SetPoint("RIGHT", cornerBR, "LEFT", 0, 0)
    edgeB:SetAtlas("_UI-Frame-DiamondMetal-EdgeBottom", false)
    edgeB:SetHorizTile(true)
    
    -- =====================
    -- LEFT/RIGHT EDGES
    -- The DiamondMetal atlas lacks EdgeLeft/EdgeRight, so we use the top edge
    -- rotated 90 degrees to create the side borders
    -- =====================
    local edgeL = parent:CreateTexture(nil, "BORDER")
    edgeL:SetWidth(EDGE_SIZE)
    -- Anchor to the LEFT side of the frame, not center of corners
    edgeL:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -CORNER_SIZE)
    edgeL:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, CORNER_SIZE)
    edgeL:SetAtlas("_UI-Frame-DiamondMetal-EdgeTop", false)
    -- Rotate the texture 90 degrees CW
    edgeL:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
    
    local edgeR = parent:CreateTexture(nil, "BORDER")
    edgeR:SetWidth(EDGE_SIZE)
    -- Anchor to the RIGHT side of the frame
    edgeR:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -CORNER_SIZE)
    edgeR:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, CORNER_SIZE)
    edgeR:SetAtlas("_UI-Frame-DiamondMetal-EdgeTop", false)
    -- Rotate the texture 90 degrees CCW
    edgeR:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
end

----------------------------------------------
-- Close Button (Red X) - Uses Interface/Buttons/redbutton2x
----------------------------------------------
local REDBUTTON_ATLAS = "Interface/Buttons/redbutton2x"

local function CreateCloseButton(parent, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(24, 25) -- Bigger for better visibility
    -- Center the button on the top-right corner
    btn:SetPoint("CENTER", parent, "TOPRIGHT", -10, -10)
    
    -- Normal texture
    local normal = btn:CreateTexture(nil, "ARTWORK")
    normal:SetAllPoints()
    normal:SetTexture(REDBUTTON_ATLAS)
    normal:SetTexCoord(0.152344, 0.292969, 0.0078125, 0.304688) -- RedButton-Exit
    btn:SetNormalTexture(normal)
    
    -- Highlight texture
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(REDBUTTON_ATLAS)
    highlight:SetTexCoord(0.449219, 0.589844, 0.0078125, 0.304688) -- RedButton-Highlight
    highlight:SetBlendMode("ADD")
    
    -- Pressed texture
    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetTexture(REDBUTTON_ATLAS)
    pushed:SetTexCoord(0.152344, 0.292969, 0.632812, 0.929688) -- RedButton-exit-pressed
    btn:SetPushedTexture(pushed)
    
    btn:SetScript("OnClick", onClick)
    
    return btn
end

----------------------------------------------
-- Settings Flyout Creation (Anchored to UIParent)
-- Styled to match Blizzard's Edit Mode settings panel
----------------------------------------------
local function CreateSettingsFlyout(container, options)
    local flyoutName = "Refactor" .. options.name .. "Settings"
    
    -- Parent to UIParent so it doesn't move with container scale
    local flyout = CreateFrame("Frame", flyoutName, UIParent)
    
    -- Calculate height based on settings count + buttons
    local settingsHeight = 0
    if options.settings then
        for _, setting in ipairs(options.settings) do
            if setting.type == "scale" or setting.type == "slider" then
                settingsHeight = settingsHeight + 32
            elseif setting.type == "checkbox" then
                settingsHeight = settingsHeight + 28
            end
        end
    end
    
    -- Frame size: title area + settings + 2 buttons (revert + reset)
    local PADDING = 16
    local TITLE_HEIGHT = 40
    local BUTTON_HEIGHT = 28
    local BUTTON_SPACING = 8
    local totalHeight = TITLE_HEIGHT + settingsHeight + (BUTTON_HEIGHT * 2) + BUTTON_SPACING + PADDING * 2
    
    flyout:SetSize(300, totalHeight)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(100)
    flyout:SetClampedToScreen(true)
    
    -- Make the flyout movable
    flyout:SetMovable(true)
    flyout:EnableMouse(true)
    flyout:RegisterForDrag("LeftButton")
    flyout:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    flyout:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    
    -- Diamond Metal border
    CreateDiamondMetalFrame(flyout)
    
    -- Close button (centered on corner)
    CreateCloseButton(flyout, function()
        flyout:Hide()
        if container.editHighlight then
            container.editHighlight:SetSelected(false)
        end
    end)
    
    -- =====================
    -- TITLE - White, centered, large font
    -- =====================
    local title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(options.label or options.name)
    title:SetTextColor(1, 1, 1) -- White color (not gold)
    
    -- =====================
    -- SETTINGS CONTROLS
    -- =====================
    local yOffset = -TITLE_HEIGHT
    flyout.controls = {}
    
    -- Session state storage (for Revert Changes)
    flyout.sessionState = {}
    
    if options.settings then
        for _, setting in ipairs(options.settings) do
            if setting.type == "scale" or setting.type == "slider" then
                local dbKey = options.dbPrefix .. "_" .. (setting.key or "Scale")
                
                -- Row container for label-slider-value layout
                local row = CreateFrame("Frame", nil, flyout)
                row:SetHeight(28)
                row:SetPoint("TOPLEFT", PADDING, yOffset)
                row:SetPoint("TOPRIGHT", -PADDING, yOffset)
                
                -- Label on the left (white text, larger font)
                local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                label:SetPoint("LEFT", 0, 0)
                label:SetText(setting.label or "Size")
                label:SetTextColor(1, 1, 1) -- White
                
                -- Modern slider (MinimalSliderWithSteppersTemplate)
                local slider = CreateFrame("Slider", flyoutName .. (setting.key or "Scale") .. "Slider", row, "MinimalSliderWithSteppersTemplate")
                slider:SetPoint("LEFT", label, "RIGHT", 16, 0)
                slider:SetPoint("RIGHT", row, "RIGHT", -40, 0)
                slider:SetHeight(18)
                
                local minVal = setting.min or 50
                local maxVal = setting.max or 150
                local step = setting.step or 5
                local defaultVal = setting.default or 100
                
                local steps = (maxVal - minVal) / step
                slider:Init(defaultVal, minVal, maxVal, steps, {
                    [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
                        MinimalSliderWithSteppersMixin.Label.Right, 
                        function(value)
                            return YELLOW_FONT_COLOR:WrapTextInColorCode(math.floor(value) .. "%")
                        end
                    )
                })
                
                -- Load current value
                local currentVal = (tonumber(addon.GetDBValue(dbKey)) or (defaultVal / 100)) * 100
                slider:SetValue(currentVal)
                
                -- OnValueChanged
                slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
                    local percent = math.floor(value + 0.5)
                    addon.SetDBValue(dbKey, percent / 100)
                    
                    local scale = percent / 100
                    if scale < minVal / 100 then scale = minVal / 100 end
                    if scale > maxVal / 100 then scale = maxVal / 100 end
                    SetScaleFromTopRight(container, scale)
                    
                    if setting.onChange then
                        setting.onChange(scale)
                    end
                    
                    -- Update Revert button state
                    if flyout.UpdateRevertButtonState then
                        flyout:UpdateRevertButtonState()
                    end
                end)
                
                flyout.controls[setting.key or "Scale"] = slider
                yOffset = yOffset - 32
            end
        end
    end
    
    -- =====================
    -- REVERT CHANGES BUTTON (Dark gray style)
    -- =====================
    local revertBtn = CreateFrame("Button", flyoutName .. "RevertBtn", flyout, "UIPanelButtonTemplate")
    revertBtn:SetSize(140, BUTTON_HEIGHT)
    revertBtn:SetPoint("BOTTOMLEFT", PADDING, PADDING + BUTTON_HEIGHT + BUTTON_SPACING)
    revertBtn:SetText("Revert Changes")
    revertBtn:SetNormalFontObject(GameFontNormal)
    revertBtn:SetHighlightFontObject(GameFontHighlight)
    revertBtn:SetDisabledFontObject(GameFontDisable)
    
    -- Start disabled (no changes yet)
    revertBtn:Disable()
    flyout.revertBtn = revertBtn
    
    -- Function to check if changes have been made
    function flyout:UpdateRevertButtonState()
        local state = self.sessionState
        if not state then 
            revertBtn:Disable()
            return 
        end
        
        local hasChanges = false
        
        -- Check scale change
        if state.scale and math.abs(container:GetScale() - state.scale) > 0.001 then
            hasChanges = true
        end
        
        -- Check position change (compare current to session start)
        local currentPoint, _, currentRelPoint, currentX, currentY = container:GetPoint()
        if currentPoint ~= state.point or 
           currentX ~= (state.x or 0) or 
           currentY ~= (state.y or 0) then
            hasChanges = true
        end
        
        if hasChanges then
            revertBtn:Enable()
        else
            revertBtn:Disable()
        end
    end
    
    -- OnClick - revert to session start values
    revertBtn:SetScript("OnClick", function()
        local state = flyout.sessionState
        if state then
            -- Revert scale
            if state.scale then
                addon.SetDBValue(options.dbPrefix .. "_Scale", state.scale)
                container:SetScale(state.scale)
                -- Update slider
                local scaleSlider = flyout.controls["Scale"]
                if scaleSlider then
                    scaleSlider:SetValue(state.scale * 100)
                end
            end
            
            -- Revert position
            if state.point then
                addon.SetDBValue(options.dbPrefix .. "_PosPoint", state.point)
                addon.SetDBValue(options.dbPrefix .. "_PosRelPoint", state.relPoint)
                addon.SetDBValue(options.dbPrefix .. "_PosX", state.x)
                addon.SetDBValue(options.dbPrefix .. "_PosY", state.y)
                
                container:ClearAllPoints()
                container:SetPoint(state.point, UIParent, state.relPoint or state.point, state.x or 0, state.y or 0)
            end
            
            -- Disable button since we're back to original
            revertBtn:Disable()
        end
    end)
    
    -- =====================
    -- RESET TO DEFAULT POSITION BUTTON (Red button style)
    -- =====================
    local resetBtn = CreateFrame("Button", flyoutName .. "ResetBtn", flyout, "UIPanelButtonTemplate")
    resetBtn:SetSize(flyout:GetWidth() - PADDING * 2, BUTTON_HEIGHT)
    resetBtn:SetPoint("BOTTOM", 0, PADDING)
    resetBtn:SetText("Reset To Default Position")
    
    -- Style with red button atlas (3-part: left, center, right)
    local REDBUTTON_128 = "Interface/Buttons/128RedButton"
    local btnHeight = resetBtn:GetHeight()
    local leftWidth = math.floor(114 * (btnHeight / 128) + 0.5)
    local rightWidth = math.floor(114 * (btnHeight / 128) + 0.5)
    
    -- Hide default textures
    if resetBtn.Left then resetBtn.Left:Hide() end
    if resetBtn.Middle then resetBtn.Middle:Hide() end
    if resetBtn.Right then resetBtn.Right:Hide() end
    
    -- Normal state
    local normalL = resetBtn:CreateTexture(nil, "BACKGROUND")
    normalL:SetTexture(REDBUTTON_128)
    normalL:SetTexCoord(0.763672, 0.986328, 0.444824, 0.507324)
    normalL:SetPoint("TOPLEFT", 0, 0)
    normalL:SetPoint("BOTTOMLEFT", 0, 0)
    normalL:SetWidth(leftWidth)
    
    local normalR = resetBtn:CreateTexture(nil, "BACKGROUND")
    normalR:SetTexture(REDBUTTON_128)
    normalR:SetTexCoord(0.00195312, 0.224609, 0.254395, 0.316895)
    normalR:SetPoint("TOPRIGHT", 0, 0)
    normalR:SetPoint("BOTTOMRIGHT", 0, 0)
    normalR:SetWidth(rightWidth)
    
    local normalC = resetBtn:CreateTexture(nil, "BACKGROUND", nil, -1)
    normalC:SetTexture(REDBUTTON_128)
    normalC:SetTexCoord(0, 0.125, 0.000488281, 0.0629883)
    normalC:SetPoint("TOPLEFT", normalL, "TOPRIGHT", 0, 0)
    normalC:SetPoint("BOTTOMRIGHT", normalR, "BOTTOMLEFT", 0, 0)
    normalC:SetHorizTile(true)
    
    -- Highlight
    local highlight = resetBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(REDBUTTON_128)
    highlight:SetTexCoord(0.00195312, 0.863281, 0.190918, 0.253418)
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    
    -- Font styling
    resetBtn:SetNormalFontObject(GameFontNormal)
    resetBtn:SetHighlightFontObject(GameFontHighlight)
    
    -- OnClick - reset to default position
    resetBtn:SetScript("OnClick", function()
        -- Clear saved position
        addon.SetDBValue(options.dbPrefix .. "_PosPoint", nil)
        addon.SetDBValue(options.dbPrefix .. "_PosRelPoint", nil)
        addon.SetDBValue(options.dbPrefix .. "_PosX", nil)
        addon.SetDBValue(options.dbPrefix .. "_PosY", nil)
        
        -- Reset to default position
        container:ClearAllPoints()
        container:SetPoint(options.defaultPos[1], UIParent, options.defaultPos[1], options.defaultPos[2], options.defaultPos[3])
    end)
    
    -- =====================
    -- Position update function (called when showing)
    -- =====================
    function flyout:UpdatePosition()
        local containerScale = container:GetEffectiveScale()
        local flyoutScale = self:GetEffectiveScale()
        
        local cx, cy = container:GetCenter()
        if cx and cy then
            cx = cx * containerScale / flyoutScale
            cy = cy * containerScale / flyoutScale
            
            local containerRight = container:GetRight() * containerScale / flyoutScale
            
            self:ClearAllPoints()
            self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", containerRight + 10, cy)
        end
    end
    
    flyout:Hide()
    return flyout
end

----------------------------------------------
-- Edit Mode Highlight Frame
----------------------------------------------
local function CreateEditModeHighlight(container, options)
    local h = CreateFrame("Frame", nil, container)
    h:SetAllPoints()
    h:SetFrameLevel(container:GetFrameLevel() + 10)
    
    -- Create both visual states
    local highlightParts = CreateNineSliceHighlight(h, "highlight", ATLAS_HIGHLIGHT_BG)
    local selectedParts = CreateNineSliceHighlight(h, "selected", ATLAS_SELECTED_BG)
    
    -- Label (bigger font, hidden by default)
    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    h.label:SetPoint("CENTER")
    h.label:SetTextColor(1, 1, 1)
    h.label:Hide()  -- Hidden by default
    
    -- Store the actual label text
    h.moduleName = options.label or options.name
    
    -- State tracking
    h.isDragging = false
    h.isHovered = false
    h.isSelected = false  -- Selected when flyout is open
    
    -- Helper functions
    local function ShowParts(parts, show)
        for _, tex in pairs(parts) do
            if show then tex:Show() else tex:Hide() end
        end
    end
    
    local function SetPartsAlpha(parts, alpha)
        for _, tex in pairs(parts) do
            tex:SetAlpha(alpha)
        end
    end
    
    local function UpdateState()
        if h.isDragging or h.isSelected then
            -- Pressed/Dragging/Selected: Show yellow selected state + module name
            ShowParts(highlightParts, false)
            ShowParts(selectedParts, true)
            h.label:SetText(h.moduleName)
            h.label:Show()
        elseif h.isHovered then
            -- Hover: Brighter blue + "Click To Edit"
            ShowParts(selectedParts, false)
            ShowParts(highlightParts, true)
            SetPartsAlpha(highlightParts, 1.0)
            h.label:SetText("Click To Edit")
            h.label:Show()
        else
            -- Normal: Default blue, no label
            ShowParts(selectedParts, false)
            ShowParts(highlightParts, true)
            SetPartsAlpha(highlightParts, 0.7)
            h.label:Hide()
        end
    end
    
    -- Initially show highlight, hide selected
    ShowParts(selectedParts, false)
    
    h.SetDragging = function(self, dragging)
        self.isDragging = dragging
        UpdateState()
    end
    
    h.SetSelected = function(self, selected)
        self.isSelected = selected
        UpdateState()
    end
    
    -- Mouse handling
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    
    h:SetScript("OnEnter", function(self)
        self.isHovered = true
        UpdateState()
    end)
    
    h:SetScript("OnLeave", function(self)
        self.isHovered = false
        UpdateState()
    end)
    
    h:SetScript("OnDragStart", function(self)
        -- Hide flyout when dragging
        if container.settingsFlyout and container.settingsFlyout:IsShown() then
            container.settingsFlyout:Hide()
            self:SetSelected(false)
        end
        container:StartMoving()
        self:SetDragging(true)
    end)
    
    h:SetScript("OnDragStop", function(self)
        container:StopMovingOrSizing()
        self:SetDragging(false)
        
        -- Save position
        local p, _, rp, x, y = container:GetPoint()
        addon.SetDBValue(options.dbPrefix .. "_PosPoint", p)
        addon.SetDBValue(options.dbPrefix .. "_PosRelPoint", rp)
        addon.SetDBValue(options.dbPrefix .. "_PosX", x)
        addon.SetDBValue(options.dbPrefix .. "_PosY", y)
        
        -- Update Revert button state
        if container.settingsFlyout and container.settingsFlyout.UpdateRevertButtonState then
            container.settingsFlyout:UpdateRevertButtonState()
        end
    end)
    
    -- Click to toggle settings flyout
    h:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not self.isDragging then
            if container.settingsFlyout then
                if container.settingsFlyout:IsShown() then
                    container.settingsFlyout:Hide()
                    self:SetSelected(false)
                else
                    -- Capture session state for Revert Changes
                    local flyout = container.settingsFlyout
                    flyout.sessionState = {
                        scale = container:GetScale(),
                        point = addon.GetDBValue(options.dbPrefix .. "_PosPoint"),
                        relPoint = addon.GetDBValue(options.dbPrefix .. "_PosRelPoint"),
                        x = addon.GetDBValue(options.dbPrefix .. "_PosX"),
                        y = addon.GetDBValue(options.dbPrefix .. "_PosY")
                    }
                    
                    -- Update slider values before showing
                    for key, slider in pairs(flyout.controls or {}) do
                        local dbKey = options.dbPrefix .. "_" .. key
                        local val = (tonumber(addon.GetDBValue(dbKey)) or 1.0) * 100
                        slider:SetValue(val)
                    end
                    -- Update position and show
                    flyout:UpdatePosition()
                    flyout:Show()
                    self:SetSelected(true)
                end
            end
        end
    end)
    
    h:Hide()
    return h
end

----------------------------------------------
-- Main API: CreateContainer
----------------------------------------------
function EditMode.CreateContainer(options)
    local container = CreateFrame("Frame", "Refactor" .. options.name .. "Container", options.parent or UIParent)
    container:SetSize(options.size[1], options.size[2])
    container:SetPoint(options.defaultPos[1], UIParent, options.defaultPos[1], options.defaultPos[2], options.defaultPos[3])
    container:SetFrameStrata(options.strata or "HIGH")
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:RegisterForDrag("LeftButton")
    container:EnableMouse(false)
    
    -- Create edit mode highlight
    container.editHighlight = CreateEditModeHighlight(container, options)
    
    -- Create settings flyout if settings defined
    if options.settings and #options.settings > 0 then
        container.settingsFlyout = CreateSettingsFlyout(container, options)
    end
    
    -- Drag handlers for the container itself
    container:SetScript("OnDragStart", function(self)
        if self.inEditMode then
            -- Hide flyout when dragging
            if self.settingsFlyout and self.settingsFlyout:IsShown() then
                self.settingsFlyout:Hide()
                self.editHighlight:SetSelected(false)
            end
            self:StartMoving()
            self.editHighlight:SetDragging(true)
        end
    end)
    
    container:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.editHighlight:SetDragging(false)
        
        local p, _, rp, x, y = self:GetPoint()
        addon.SetDBValue(options.dbPrefix .. "_PosPoint", p)
        addon.SetDBValue(options.dbPrefix .. "_PosRelPoint", rp)
        addon.SetDBValue(options.dbPrefix .. "_PosX", x)
        addon.SetDBValue(options.dbPrefix .. "_PosY", y)
    end)
    
    -- Load saved position
    local p = addon.GetDBValue(options.dbPrefix .. "_PosPoint")
    local x = addon.GetDBValue(options.dbPrefix .. "_PosX")
    if p and x then
        container:ClearAllPoints()
        container:SetPoint(p, UIParent, addon.GetDBValue(options.dbPrefix .. "_PosRelPoint") or p, x, addon.GetDBValue(options.dbPrefix .. "_PosY"))
    end
    
    -- Load and apply saved scale
    local savedScale = tonumber(addon.GetDBValue(options.dbPrefix .. "_Scale")) or 1.0
    if savedScale < 0.5 then savedScale = 0.5 end
    if savedScale > 1.5 then savedScale = 1.5 end
    container:SetScale(savedScale)
    
    -- Edit Mode API
    container.inEditMode = false
    
    function container:EnterEditMode()
        self.inEditMode = true
        self:EnableMouse(true)
        self.editHighlight:Show()
        if options.onEnterEditMode then
            options.onEnterEditMode(self)
        end
    end
    
    function container:ExitEditMode()
        self.inEditMode = false
        self:EnableMouse(false)
        self.editHighlight:Hide()
        self.editHighlight:SetSelected(false)
        if self.settingsFlyout then
            self.settingsFlyout:Hide()
        end
        if options.onExitEditMode then
            options.onExitEditMode(self)
        end
    end
    
    function container:IsInEditMode()
        return self.inEditMode
    end
    
    -- Register for Blizzard edit mode events
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            container:EnterEditMode()
        end)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            container:ExitEditMode()
        end)
    end
    
    -- Check if already in edit mode
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        container:EnterEditMode()
    end
    
    return container
end

return EditMode
