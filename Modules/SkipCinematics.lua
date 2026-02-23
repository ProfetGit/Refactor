-- Refactor Addon - Skip Cinematics Module
-- Automatically skips previously seen cinematics and movies

local addonName, addon = ...
local L = addon.L

local Utils = addon.Utils

local Module = addon:NewModule("SkipCinematics", {
    settingKey = "SkipCinematics"
})

----------------------------------------------
-- Helper Functions
----------------------------------------------
local function ShouldSkip()
    if not Module.isEnabled then return false end

    -- Check if modifier key is held to watch instead
    local modKey = addon.GetDBValue("SkipCinematics_ModifierKey")
    if modKey and modKey ~= "NONE" and Utils.IsModifierKeyDown(modKey) then
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
-- Initialization
----------------------------------------------
function Module:OnEnable()
    eventFrame:RegisterEvent("CINEMATIC_START")
    eventFrame:RegisterEvent("PLAY_MOVIE")
end

function Module:OnDisable()
    eventFrame:UnregisterEvent("CINEMATIC_START")
    eventFrame:UnregisterEvent("PLAY_MOVIE")
end
