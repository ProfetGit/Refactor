--- @module interface.cameraDistance
--- Purpose: set the camera zoom limit to the distance the player picked, and restore the default when off.
--- Requires: C_CVar.SetCVar, C_CVar.GetCVarDefault
--- Events: REFACTOR_SETTINGS_CHANGED
--- Hot: no
local _, R = ...
local CameraDistance = R:RegisterModule({
    id = "interface.cameraDistance", category = "Interface", nameKey = "CAMERA_DISTANCE_NAME",
    descriptionKey = "CAMERA_DISTANCE_DESC", detailKey = "CAMERA_DISTANCE_DETAIL",
    requires = { "C_CVar.SetCVar", "C_CVar.GetCVarDefault" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

local CVAR, OPTION, FALLBACK = "cameraDistanceMaxZoomFactor", "cameraMaxZoom", "1.9"

-- Written with two decimals rather than through tostring: the CVar takes a string, and a
-- slider step that lands on 2.5999999 would otherwise be spelled out in full.
function CameraDistance:Apply()
    local factor = R.Settings:GetOption(OPTION)
    if type(factor) ~= "number" then
        return
    end
    C_CVar.SetCVar(CVAR, string.format("%.2f", factor))
end

function CameraDistance:OnEnable()
    self:Apply()
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.Apply, self)
end

function CameraDistance:OnDisable()
    R.Broker:UnsubscribeAll(self)
    C_CVar.SetCVar(CVAR, C_CVar.GetCVarDefault(CVAR) or FALLBACK)
end
