local addonName, addon = ...
local L = addon.L

local CombatFade = {}
addon.RegisterModule("CombatFade", CombatFade)

-- Action Bar frame names
local actionBarFrameNames = {
    "MainActionBar",
    "MainMenuBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "StanceBar",
    "PetActionBar",
    "PossessActionBar",
    "OverrideActionBar",
    "StatusTrackingBarManager",
}

for i = 1, 12 do
    table.insert(actionBarFrameNames, "ActionButton" .. i)
end

-- Player Frame names
local playerFrameNames = {
    "PlayerFrame",
}

local actionBarObjects = {}
local actionBarGryphons = {}
local playerFrameObjects = {}
local initialized = false

local f = CreateFrame("Frame")
local FADE_IN_TIME = 0.2
local FADE_OUT_TIME = 0.5

local actionBarAlpha = 1
local playerFrameAlpha = 1
local actionBarGryphonsHidden = false

function CombatFade:OnInitialize()
    C_Timer.After(1, function()
        self:UpdateState()
    end)
end

local function AddToList(list, obj)
    if not obj then return end
    if type(obj) ~= "table" then return end
    if not (obj.SetAlpha and obj.GetAlpha) then return end
    
    for _, o in ipairs(list) do
        if o == obj then return end
    end
    table.insert(list, obj)
end

local function AddGryphon(obj)
    if not obj then return end
    if type(obj) ~= "table" then return end
    if not (obj.Hide and obj.Show) then return end
    
    for _, o in ipairs(actionBarGryphons) do
        if o == obj then return end
    end
    table.insert(actionBarGryphons, obj)
end

local function SafeGetName(frame)
    if frame and type(frame) == "table" and frame.GetName then
        local success, name = pcall(function() return frame:GetName() end)
        if success then return name end
    end
    return nil
end

local function SearchForArt(frame, depth)
    depth = depth or 0
    if depth > 5 then return end
    if not frame then return end
    if type(frame) ~= "table" then return end
    
    local name = SafeGetName(frame)
    if name then
        local lowerName = name:lower()
        if lowerName:find("endcap") or lowerName:find("gryphon") or lowerName:find("artframe") or lowerName:find("borderart") then
            AddGryphon(frame)
            AddToList(actionBarObjects, frame)
        end
    end
    
    if frame.EndCaps then AddGryphon(frame.EndCaps) end
    if frame.LeftEndCap then AddGryphon(frame.LeftEndCap) end
    if frame.RightEndCap then AddGryphon(frame.RightEndCap) end
    if frame.BorderArt then AddGryphon(frame.BorderArt); AddToList(actionBarObjects, frame.BorderArt) end
    if frame.ArtFrame then AddGryphon(frame.ArtFrame); AddToList(actionBarObjects, frame.ArtFrame) end
    
    if frame.GetChildren then
        local success, children = pcall(function() return { frame:GetChildren() } end)
        if success and children then
            for _, child in ipairs(children) do
                SearchForArt(child, depth + 1)
            end
        end
    end
end

local function InitFrames()
    if initialized then return end
    
    actionBarObjects = {}
    actionBarGryphons = {}
    playerFrameObjects = {}
    
    -- Action bars
    for _, name in ipairs(actionBarFrameNames) do
        local frame = _G[name]
        if frame then 
            AddToList(actionBarObjects, frame)
            SearchForArt(frame, 0)
        end
    end
    
    if MainActionBar then
        AddToList(actionBarObjects, MainActionBar)
        SearchForArt(MainActionBar, 0)
        
        if MainActionBar.EndCaps then
            AddGryphon(MainActionBar.EndCaps)
            if MainActionBar.EndCaps.LeftEndCap then AddGryphon(MainActionBar.EndCaps.LeftEndCap) end
            if MainActionBar.EndCaps.RightEndCap then AddGryphon(MainActionBar.EndCaps.RightEndCap) end
        end
    end
    
    -- Player frame
    for _, name in ipairs(playerFrameNames) do
        local frame = _G[name]
        if frame then
            AddToList(playerFrameObjects, frame)
        end
    end
    
    initialized = true
end

function CombatFade:UpdateState()
    local moduleEnabled = addon.GetDBBool("CombatFade")
    local actionBarsEnabled = addon.GetDBBool("CombatFade_ActionBars")
    local playerFrameEnabled = addon.GetDBBool("CombatFade_PlayerFrame")
    
    if moduleEnabled and (actionBarsEnabled or playerFrameEnabled) then
        if not initialized then InitFrames() end
        f:SetScript("OnUpdate", self.OnUpdate)
    else
        f:SetScript("OnUpdate", nil)
        self:ForceShow()
    end
end

function CombatFade:ForceShow()
    if not initialized then InitFrames() end
    
    for _, obj in ipairs(actionBarObjects) do
        if obj.SetAlpha then obj:SetAlpha(1) end
    end
    
    for _, obj in ipairs(actionBarGryphons) do
        if obj.Show then obj:Show() end
    end
    
    for _, obj in ipairs(playerFrameObjects) do
        if obj.SetAlpha then obj:SetAlpha(1) end
    end
    
    actionBarAlpha = 1
    playerFrameAlpha = 1
    actionBarGryphonsHidden = false
end

local function IsMouseOverList(list)
    for _, obj in ipairs(list) do
        if obj.IsShown and obj:IsShown() and obj.IsMouseOver and obj:IsMouseOver() then
            return true
        end
    end
    return false
end

function CombatFade.OnUpdate(self, elapsed)
    if not initialized then InitFrames() end

    local inCombat = InCombatLockdown()
    local moduleEnabled = addon.GetDBBool("CombatFade")
    local actionBarsEnabled = moduleEnabled and addon.GetDBBool("CombatFade_ActionBars")
    local playerFrameEnabled = moduleEnabled and addon.GetDBBool("CombatFade_PlayerFrame")
    
    -- Get opacity settings (0-100) and convert to alpha (0-1)
    local actionBarMinAlpha = (addon.GetDBValue("CombatFade_ActionBars_Opacity") or 0) / 100
    local playerFrameMinAlpha = (addon.GetDBValue("CombatFade_PlayerFrame_Opacity") or 0) / 100
    
    -- Calculate target alpha for action bars
    local actionBarTarget = actionBarMinAlpha
    if not actionBarsEnabled then
        actionBarTarget = 1
    elseif inCombat then
        actionBarTarget = 1
    elseif IsMouseOverList(actionBarObjects) or IsMouseOverList(actionBarGryphons) then
        actionBarTarget = 1
    elseif SpellFlyout and SpellFlyout:IsShown() and SpellFlyout:IsMouseOver() then
        actionBarTarget = 1
    end
    
    -- Calculate target alpha for player frame
    local playerFrameTarget = playerFrameMinAlpha
    if not playerFrameEnabled then
        playerFrameTarget = 1
    elseif inCombat then
        playerFrameTarget = 1
    elseif IsMouseOverList(playerFrameObjects) then
        playerFrameTarget = 1
    end
    
    -- Smooth transition for action bars
    if actionBarAlpha ~= actionBarTarget then
        local change = elapsed / (actionBarTarget > actionBarAlpha and FADE_IN_TIME or FADE_OUT_TIME)
        if actionBarTarget > actionBarAlpha then
            actionBarAlpha = math.min(actionBarTarget, actionBarAlpha + change)
        else
            actionBarAlpha = math.max(actionBarTarget, actionBarAlpha - change)
        end
    end
    
    -- Smooth transition for player frame
    if playerFrameAlpha ~= playerFrameTarget then
        local change = elapsed / (playerFrameTarget > playerFrameAlpha and FADE_IN_TIME or FADE_OUT_TIME)
        if playerFrameTarget > playerFrameAlpha then
            playerFrameAlpha = math.min(playerFrameTarget, playerFrameAlpha + change)
        else
            playerFrameAlpha = math.max(playerFrameTarget, playerFrameAlpha - change)
        end
    end
    
    -- Apply action bar alpha
    for _, obj in ipairs(actionBarObjects) do
        if obj.SetAlpha then
            obj:SetAlpha(actionBarAlpha)
        end
    end
    
    -- Handle gryphons (Hide/Show at threshold)
    local gryphonThreshold = actionBarMinAlpha + 0.05
    if actionBarAlpha <= gryphonThreshold and not actionBarGryphonsHidden then
        for _, obj in ipairs(actionBarGryphons) do
            if obj.Hide then obj:Hide() end
        end
        actionBarGryphonsHidden = true
    elseif actionBarAlpha > gryphonThreshold + 0.4 and actionBarGryphonsHidden then
        for _, obj in ipairs(actionBarGryphons) do
            if obj.Show then obj:Show() end
        end
        actionBarGryphonsHidden = false
    end
    
    -- Apply player frame alpha
    for _, obj in ipairs(playerFrameObjects) do
        if obj.SetAlpha then
            obj:SetAlpha(playerFrameAlpha)
        end
    end
end

-- Listen for setting changes
addon.CallbackRegistry:Register("SettingChanged.CombatFade", CombatFade.UpdateState, CombatFade)
addon.CallbackRegistry:Register("SettingChanged.CombatFade_ActionBars", CombatFade.UpdateState, CombatFade)
addon.CallbackRegistry:Register("SettingChanged.CombatFade_PlayerFrame", CombatFade.UpdateState, CombatFade)
