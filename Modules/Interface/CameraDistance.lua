--- @module interface.cameraDistance
--- Purpose: raise the camera zoom limit while enabled and restore the default when not.
--- Requires: C_CVar.SetCVar, C_CVar.GetCVarDefault
--- Events: none
--- Hot: no
local _, R = ...
local CameraDistance = R:RegisterModule({
    id = "interface.cameraDistance", category = "Interface", nameKey = "CAMERA_DISTANCE_NAME",
    descriptionKey = "CAMERA_DISTANCE_DESC", detailKey = "CAMERA_DISTANCE_DETAIL",
    requires = { "C_CVar.SetCVar", "C_CVar.GetCVarDefault" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

local CVAR, MAXIMUM = "cameraDistanceMaxZoomFactor", "2.6"

function CameraDistance:OnEnable()
    C_CVar.SetCVar(CVAR, MAXIMUM)
end

function CameraDistance:OnDisable()
    C_CVar.SetCVar(CVAR, C_CVar.GetCVarDefault(CVAR) or "1.9")
end
