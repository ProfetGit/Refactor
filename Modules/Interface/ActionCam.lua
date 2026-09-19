--- @module interface.actionCam
--- Purpose: apply the chosen ActionCam profile and follow the player between situations.
--- Requires: ConsoleExec, C_CVar.SetCVar, C_CVar.GetCVarDefault, StaticPopup_Hide, CameraZoomIn,
---     CameraZoomOut, IsPlayerInWorld, IsIndoors, IsResting, IsMounted, UnitOnTaxi, UnitInVehicle,
---     InCombatLockdown
--- Events: EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED, REFACTOR_SETTINGS_CHANGED, PLAYER_ENTERING_WORLD,
---     ZONE_CHANGED, ZONE_CHANGED_INDOORS, ZONE_CHANGED_NEW_AREA, PLAYER_UPDATE_RESTING,
---     PLAYER_MOUNT_DISPLAY_CHANGED, UNIT_ENTERED_VEHICLE, UNIT_EXITED_VEHICLE, PLAYER_CONTROL_LOST,
---     PLAYER_CONTROL_GAINED, PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED
--- Hot: no
local _, R = ...
local Profiles = R.CameraProfiles
local ActionCam = R:RegisterModule({
    id = "interface.actionCam", category = "Interface", nameKey = "ACTIONCAM_NAME",
    descriptionKey = "ACTIONCAM_DESC", detailKey = "ACTIONCAM_DETAIL",
    requires = { "ConsoleExec", "C_CVar.SetCVar", "C_CVar.GetCVarDefault", "StaticPopup_Hide",
        "CameraZoomIn", "CameraZoomOut", "IsPlayerInWorld", "IsIndoors", "IsResting", "IsMounted",
        "UnitOnTaxi", "UnitInVehicle", "InCombatLockdown" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

-- Every test_camera CVar the installed client registers. A Blizzard preset is free to touch
-- any of them, so a profile change and a disable both start from the client's own
-- defaults rather than assuming which ones the last profile set.
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
-- Blizzard's motion sickness guard. It defaults on and, in the client's own words, can
-- override the other camera CVars, which leaves every ActionCam setting doing nothing.
-- Reduce Unexpected Movement defaults off and is left alone: a player who turned it on
-- chose to.
local CENTERED = "CameraKeepCharacterCentered"
local SITUATION_EVENTS = {
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}
local UNIT_EVENTS = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }

local function decimal(value)
    return string.format("%.2f", value)
end

local function flag(value)
    return value and "1" or "0"
end

-- Combat first: it is the situation with the least attention to spare for the camera.
-- Mounted over indoors, because a mount indoors is passing through; indoors over resting,
-- because an inn is a room before it is a rest area.
local function situation()
    if InCombatLockdown() then
        return "combat"
    end
    if IsMounted() or UnitOnTaxi("player") or UnitInVehicle("player") then
        return "mounted"
    end
    if IsIndoors() then
        return "indoors"
    end
    if IsResting() then
        return "resting"
    end
    return nil
end

local function resetCVars()
    for _, cvar in ipairs(CVARS) do
        C_CVar.SetCVar(cvar, C_CVar.GetCVarDefault(cvar) or "0")
    end
end

-- The client asks for confirmation every login once an experimental CVar is set. The
-- player already confirmed by enabling this module, so the dialog is closed again.
function ActionCam:OnWarning()
    StaticPopup_Hide("EXPERIMENTAL_CVAR_WARNING")
end

-- Moves the camera by the difference between what was last applied and what is asked for
-- now, so whatever the player did with the wheel in between is kept. There is no source
-- evidence for reading the distance back, which is why it is tracked rather than read.
-- settle records the target without moving: at login the client has already restored the
-- distance the last session left the camera at.
function ActionCam:MoveZoom(target, settle)
    local delta = target - (self.appliedZoom or 0)
    if not settle then
        if delta > 0 then
            CameraZoomIn(delta)
        elseif delta < 0 then
            CameraZoomOut(-delta)
        end
    end
    self.appliedZoom = target
end

function ActionCam:ApplySituation(settle)
    local profile = self.profile
    if not profile or profile.console then
        return
    end
    local values, current = profile.values, situation()
    self.situation = current
    local shoulder, zoom = values.shoulder, values.zoom
    if current then
        shoulder, zoom = values[current .. "Shoulder"], zoom + values[current .. "Zoom"]
    end
    C_CVar.SetCVar("test_cameraOverShoulder", decimal(shoulder))
    self:MoveZoom(zoom, settle)
end

function ActionCam:Apply(settle)
    local profile = Profiles:Active()
    self.profile, self.situation = profile, nil
    resetCVars()
    if not profile then
        self:MoveZoom(0, settle)
        return
    end
    C_CVar.SetCVar(CENTERED, "0")
    if profile.console then
        -- Blizzard's preset lives in the client, so its command is run rather than its
        -- values guessed. It knows nothing of situations, so the zoom goes back to where
        -- the last profile found it.
        ConsoleExec(profile.console)
        self:MoveZoom(0, settle)
        return
    end
    local values = profile.values
    C_CVar.SetCVar("test_cameraDynamicPitch", flag(values.pitch))
    C_CVar.SetCVar("test_cameraHeadMovementStrength", decimal(values.headBob))
    C_CVar.SetCVar("test_cameraTargetFocusInteractEnable", flag(values.focusInteract))
    C_CVar.SetCVar("test_cameraTargetFocusEnemyEnable", flag(values.focusEnemy))
    self:ApplySituation(settle)
end

function ActionCam:OnSituation()
    if self.profile and not self.profile.console and situation() ~= self.situation then
        self:ApplySituation(false)
    end
end

function ActionCam:OnUnitEvent(_, unit)
    if unit == "player" then
        self:OnSituation()
    end
end

-- A login or reload restores the camera where it was, so the profile is recorded rather
-- than moved. Any other loading screen is a zone change, and only the situation matters.
function ActionCam:OnEnteringWorld(_, isInitialLogin, isReloadingUi)
    if isInitialLogin or isReloadingUi then
        self:Apply(true)
    else
        self:OnSituation()
    end
end

function ActionCam:OnSettingsChanged(_, key)
    if key == "cameraProfile" or key == "cameraProfiles" then
        self:Apply(false)
    end
end

function ActionCam:OnEnable()
    self.appliedZoom, self.profile, self.situation = 0, nil, nil
    local Broker = R.Broker
    Broker:Subscribe("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED", self.OnWarning, self)
    Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
    Broker:Subscribe("PLAYER_ENTERING_WORLD", self.OnEnteringWorld, self)
    for _, event in ipairs(SITUATION_EVENTS) do
        Broker:Subscribe(event, self.OnSituation, self)
    end
    for _, event in ipairs(UNIT_EVENTS) do
        Broker:Subscribe(event, self.OnUnitEvent, self)
    end
    self:OnWarning()
    -- Enabled from the login sequence, the player is not in the world yet and the situation
    -- queries have nothing to answer; PLAYER_ENTERING_WORLD applies the profile then.
    if IsPlayerInWorld() then
        self:Apply(false)
    end
end

function ActionCam:OnDisable()
    R.Broker:UnsubscribeAll(self)
    resetCVars()
    C_CVar.SetCVar(CENTERED, C_CVar.GetCVarDefault(CENTERED) or "1")
    self:MoveZoom(0, false)
    self.profile, self.situation = nil, nil
end
