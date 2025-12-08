-- Refactor Addon - ActionCam Module
-- Manages ActionCam settings
local addonName, addon = ...
local L = addon.L

local Module = {}

function Module:Apply()
    if not addon.GetDBBool("ActionCam") then
        -- Optional: If disabled, we could enforce "off", but usually better to leave it alone unless user explicitly selects "off" mode.
        -- However, usually "Disable ActionCam Module" implies "Turn off ActionCam".
        -- Let's stick to doing nothing if disabled, as per standard addon behavior,
        -- BUT since this is a "Manager", if I disable the manager, I expect the effect to stop.
        -- Since ActionCam is stateful in the client, "Stopping the effect" might mean "Reset to default".
        -- For now, I'll just return. The user can select "Off" mode if they want to turn it off.
        return 
    end

    local mode = addon.GetDBValue("ActionCam_Mode") or "basic"
    
    -- Helper to safely set CVar (silently)
    local function SafeSetCVar(cvar, value)
        C_CVar.SetCVar(cvar, tostring(value)) 
    end

    if mode == "off" then
        SafeSetCVar("test_cameraOverShoulder", 0)
        SafeSetCVar("test_cameraHeadMovementStrength", 0)
        SafeSetCVar("test_cameraTargetFocusEnemyEnable", 0)
        SafeSetCVar("test_cameraTargetFocusInteractEnable", 0)
        SafeSetCVar("test_cameraDynamicPitch", 0)
        SafeSetCVar("CameraKeepCharacterCentered", 1)
        
    elseif mode == "basic" then
        -- ActionCam Basic emulation:
        -- 1. Must disable "KeepCharacterCentered" for Dynamic Pitch (tilt) to work.
        -- 2. Must set "OverShoulder" to 0 to prevent the screen shifting right.
        
        SafeSetCVar("CameraKeepCharacterCentered", 0) -- Enable ActionCam Engine
        SafeSetCVar("test_cameraOverShoulder", 0)     -- Force Center (No right shift)
        
        SafeSetCVar("test_cameraHeadMovementStrength", 0)
        SafeSetCVar("test_cameraTargetFocusEnemyEnable", 0)
        SafeSetCVar("test_cameraTargetFocusInteractEnable", 0)
        SafeSetCVar("test_cameraDynamicPitch", 1)     -- Enable the Tilt/Angle change
        
    elseif mode == "full" then
        -- Full Mode: Everything ON
        SafeSetCVar("CameraKeepCharacterCentered", 0)
        SafeSetCVar("test_cameraOverShoulder", 1)
        SafeSetCVar("test_cameraHeadMovementStrength", 1)
        SafeSetCVar("test_cameraTargetFocusEnemyEnable", 1)
        SafeSetCVar("test_cameraTargetFocusInteractEnable", 1)
        SafeSetCVar("test_cameraDynamicPitch", 1)
    end
end

function Module:OnInitialize()
    -- Suppress the "Experimental Features" confirmation popup
    if UIParent then
        UIParent:UnregisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
    end

    -- Listen for setting changes
    addon.CallbackRegistry:Register("SettingChanged.ActionCam", function(val)
        if val then
            Module:Apply()
        else
            -- Force off if disabled
            C_CVar.SetCVar("test_cameraOverShoulder", "0")
            C_CVar.SetCVar("test_cameraHeadMovementStrength", "0")
            C_CVar.SetCVar("test_cameraTargetFocusEnemyEnable", "0")
            C_CVar.SetCVar("test_cameraTargetFocusInteractEnable", "0")
            C_CVar.SetCVar("test_cameraDynamicPitch", "0")
            C_CVar.SetCVar("CameraKeepCharacterCentered", "1")
        end
    end)

    addon.CallbackRegistry:Register("SettingChanged.ActionCam_Mode", function(val)
        if addon.GetDBBool("ActionCam") then
            Module:Apply()
        end
    end)

    -- Apply on login (if enabled)
    addon.CallbackRegistry:Register("PlayerEnteringWorld", function()
        if addon.GetDBBool("ActionCam") then
            -- Delay slightly to ensure client is ready and overriding other addons
            C_Timer.After(2, function()
                Module:Apply()
            end)
        end
    end)
    
    -- Also apply immediately if we are initialized late
    if addon.GetDBBool("ActionCam") then
         C_Timer.After(1, function() Module:Apply() end)
    end
end

addon.RegisterModule("ActionCam", Module)
