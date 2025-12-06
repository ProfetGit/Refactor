-- Refactor Addon - Skip Cinematics Module
-- Automatically skips previously seen cinematics and movies

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- Helper Functions
----------------------------------------------
local function ShouldSkip()
    if not isEnabled then return false end
    
    -- Check if modifier key is held to watch instead
    local modKey = addon.GetDBValue("SkipCinematics_ModifierKey")
    if modKey and modKey ~= "NONE" and addon.IsModifierKeyDown(modKey) then
        return false
    end
    
    return true
end

local function IsMovieSeen(movieID)
    if addon.GetDBBool("SkipCinematics_AlwaysSkip") then
        return true
    end
    
    local seen = addon.GetCharDBValue("SeenMovies")
    return seen and seen[movieID]
end

local function MarkMovieSeen(movieID)
    local seen = addon.GetCharDBValue("SeenMovies") or {}
    seen[movieID] = true
    addon.SetCharDBValue("SeenMovies", seen)
end

----------------------------------------------
-- In-Game Cinematics (CINEMATIC_START)
----------------------------------------------
local function OnCinematicStart()
    if not ShouldSkip() then return end
    
    if addon.GetDBBool("SkipCinematics_AlwaysSkip") then
        -- Stop the cinematic
        C_Timer.After(0.1, function()
            if CinematicFrame and CinematicFrame:IsShown() then
                CinematicFrame_CancelCinematic()
            else
                StopCinematic()
            end
        end)
    end
end

----------------------------------------------
-- Movie Playback (PLAY_MOVIE)
----------------------------------------------
local function OnPlayMovie(movieID)
    if not ShouldSkip() then 
        MarkMovieSeen(movieID)
        return 
    end
    
    if IsMovieSeen(movieID) then
        -- Stop the movie
        C_Timer.After(0.1, function()
            if MovieFrame and MovieFrame:IsShown() then
                MovieFrame:StopMovie()
            end
        end)
    else
        -- First time watching, mark as seen for next time
        MarkMovieSeen(movieID)
    end
end

----------------------------------------------
-- Event Frame
----------------------------------------------
local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CINEMATIC_START" then
        OnCinematicStart()
    elseif event == "PLAY_MOVIE" then
        local movieID = ...
        OnPlayMovie(movieID)
    end
end)

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true
    eventFrame:RegisterEvent("CINEMATIC_START")
    eventFrame:RegisterEvent("PLAY_MOVIE")
    addon.Print("Skip Cinematics enabled")
end

function Module:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("CINEMATIC_START")
    eventFrame:UnregisterEvent("PLAY_MOVIE")
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    -- Initial state
    if addon.GetDBBool("SkipCinematics") then
        self:Enable()
    end
    
    -- Listen for setting changes
    addon.CallbackRegistry:Register("SettingChanged.SkipCinematics", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
end

-- Register the module
addon.RegisterModule("SkipCinematics", Module)
