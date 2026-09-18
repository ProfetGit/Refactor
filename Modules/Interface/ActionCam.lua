--- @module interface.actionCam
--- Purpose: enable ActionCam's basic preset, reverting every CVar it can touch on disable.
--- Requires: ConsoleExec, C_CVar.SetCVar, C_CVar.GetCVarDefault, StaticPopup_Hide
--- Events: EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED
--- Hot: no
local _, R = ...
local ActionCam = R:RegisterModule({
    id = "interface.actionCam", category = "Interface", nameKey = "ACTIONCAM_NAME",
    descriptionKey = "ACTIONCAM_DESC", detailKey = "ACTIONCAM_DETAIL",
    requires = { "ConsoleExec", "C_CVar.SetCVar", "C_CVar.GetCVarDefault", "StaticPopup_Hide" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

-- The preset lives in the client, not in Lua, so the command is run rather than its
-- values guessed. "basic" is the same argument the player types at /console.
local PRESET = "actioncam basic"

-- Every test_camera CVar the installed client registers. The preset is free to touch any
-- of them, so disable restores the whole set to the client's own defaults rather than
-- assuming which three it changed.
local CVARS = {
    "test_cameraDynamicPitch", "test_cameraDynamicPitchBaseFovPad",
    "test_cameraDynamicPitchBaseFovPadDownScale", "test_cameraDynamicPitchBaseFovPadFlying",
    "test_cameraDynamicPitchSmartPivotCutoffDist", "test_cameraHeadMovementDeadZone",
    "test_cameraHeadMovementFirstPersonDampRate", "test_cameraHeadMovementMovingDampRate",
    "test_cameraHeadMovementMovingStrength", "test_cameraHeadMovementRangeScale",
    "test_cameraHeadMovementStandingDampRate", "test_cameraHeadMovementStandingStrength",
    "test_cameraHeadMovementStrength", "test_cameraOverShoulder",
    "test_cameraTargetFocusEnemyEnable", "test_cameraTargetFocusEnemyStrengthPitch",
    "test_cameraTargetFocusEnemyStrengthYaw", "test_cameraTargetFocusInteractEnable",
    "test_cameraTargetFocusInteractStrengthPitch", "test_cameraTargetFocusInteractStrengthYaw",
}

-- The client asks for confirmation every login once an experimental CVar is set. The
-- player already confirmed by enabling this module, so the dialog is closed again.
function ActionCam:OnWarning()
    StaticPopup_Hide("EXPERIMENTAL_CVAR_WARNING")
end

function ActionCam:OnEnable()
    ConsoleExec(PRESET)
    R.Broker:Subscribe("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED", self.OnWarning, self)
    self:OnWarning()
end

function ActionCam:OnDisable()
    R.Broker:UnsubscribeAll(self)
    for _, cvar in ipairs(CVARS) do
        C_CVar.SetCVar(cvar, C_CVar.GetCVarDefault(cvar) or "0")
    end
end
