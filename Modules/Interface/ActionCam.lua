--- @module interface.actionCam
--- Purpose: apply the chosen ActionCam profile and follow the player between situations.
--- Requires: ConsoleExec, C_CVar.SetCVar, C_CVar.GetCVarDefault, StaticPopup_Hide, CameraZoomIn,
---     CameraZoomOut, IsPlayerInWorld, IsInInstance, IsIndoors, IsResting, IsMounted, UnitOnTaxi,
---     UnitInVehicle, InCombatLockdown
--- Events: EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED, REFACTOR_SETTINGS_CHANGED, PLAYER_ENTERING_WORLD,
---     ZONE_CHANGED, ZONE_CHANGED_INDOORS, ZONE_CHANGED_NEW_AREA, PLAYER_UPDATE_RESTING,
---     PLAYER_MOUNT_DISPLAY_CHANGED, UNIT_ENTERED_VEHICLE, UNIT_EXITED_VEHICLE, PLAYER_CONTROL_LOST,
---     PLAYER_CONTROL_GAINED, PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, GOSSIP_SHOW, GOSSIP_CLOSED,
---     QUEST_GREETING, QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE, QUEST_FINISHED, MERCHANT_SHOW,
---     MERCHANT_CLOSED
--- Hot: no
local _, R = ...
local Profiles = R.CameraProfiles
local ActionCam = R:RegisterModule({
    id = "interface.actionCam", category = "Interface", nameKey = "ACTIONCAM_NAME",
    descriptionKey = "ACTIONCAM_DESC", detailKey = "ACTIONCAM_DETAIL",
    requires = { "ConsoleExec", "C_CVar.SetCVar", "C_CVar.GetCVarDefault", "StaticPopup_Hide",
        "CameraZoomIn", "CameraZoomOut", "IsPlayerInWorld", "IsInInstance", "IsIndoors", "IsResting",
        "IsMounted", "UnitOnTaxi", "UnitInVehicle", "InCombatLockdown" },
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
-- Further than any maximum the client allows, so a zoom in by this much always lands on
-- zero and a zoom out from there is the distance itself.
local FULL_ZOOM_IN = 50
local SITUATION_EVENTS = {
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}
local UNIT_EVENTS = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
-- An NPC window opening and closing. A gossip that hands over to a quest or a merchant
-- closes and reopens in the same tick, which the one-tick settle below folds away.
local TALK_OPEN = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "MERCHANT_SHOW" }
local TALK_CLOSE = { "GOSSIP_CLOSED", "QUEST_FINISHED", "MERCHANT_CLOSED" }
-- A delve reports as a scenario and plays like a dungeon.
local INSTANCE_SITUATIONS = { party = "dungeon", scenario = "dungeon", raid = "raid", pvp = "battleground",
    arena = "arena" }

local function decimal(value)
    return string.format("%.2f", value)
end

local function flag(value)
    return value and "1" or "0"
end

-- An instance first: it says more about what the player needs to see than anything that
-- happens inside it, and combat in a raid wants the raid's distance, not the open world's.
-- Then combat, then an NPC window, because a fight closes the window. Mounted over
-- indoors, because a mount indoors is passing through; indoors over resting, because an
-- inn is a room before it is a rest area.
local function situation(self)
    local _, instanceType = IsInInstance()
    local instance = INSTANCE_SITUATIONS[instanceType]
    if instance then
        return instance
    end
    if InCombatLockdown() then
        return "combat"
    end
    if self.talking then
        return "npc"
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

-- The client keeps a target distance that each zoom call moves and clamps at zero and at
-- the maximum, so a zoom in past any possible maximum lands on zero and the zoom out from
-- there is the distance itself. Both land before a frame is drawn, so the camera eases
-- straight to it at the client's own zoom speed. There is no source evidence for reading
-- the distance back, which is why it is set this way rather than by a difference.
function ActionCam:SetDistance(yards)
    CameraZoomIn(FULL_ZOOM_IN)
    CameraZoomOut(yards)
    self.distance = yards
end

-- force moves the camera even when the number is the one already applied: a situation
-- change and a profile change both mean "put it where the profile says". An edit to a
-- field of the profile moves it only when the field in play changed, so tuning a raid's
-- distance from an inn leaves the inn's camera where the player's wheel put it.
function ActionCam:ApplySituation(force)
    local profile = self.profile
    if not profile or profile.console then
        return
    end
    local values, current = profile.values, situation(self)
    self.situation = current
    local distance, shoulder = values.distance, values.shoulder
    if current then
        distance, shoulder = values[current .. "Distance"], values[current .. "Shoulder"]
    end
    C_CVar.SetCVar("test_cameraOverShoulder", decimal(shoulder))
    if force or distance ~= self.distance then
        self:SetDistance(distance)
    end
end

function ActionCam:Apply(force)
    local profile = Profiles:Active()
    self.profile, self.situation = profile, nil
    resetCVars()
    if not profile then
        return
    end
    C_CVar.SetCVar(CENTERED, "0")
    if profile.console then
        -- Blizzard's preset lives in the client, so its command is run rather than its
        -- values guessed. It knows nothing of situations and never moves the zoom.
        ConsoleExec(profile.console)
        return
    end
    local values = profile.values
    C_CVar.SetCVar("test_cameraDynamicPitch", flag(values.pitch))
    C_CVar.SetCVar("test_cameraHeadMovementStrength", decimal(values.headBob))
    C_CVar.SetCVar("test_cameraTargetFocusInteractEnable", flag(values.focusInteract))
    C_CVar.SetCVar("test_cameraTargetFocusEnemyEnable", flag(values.focusEnemy))
    self:ApplySituation(force)
end

function ActionCam:Evaluate()
    self.pending = nil
    if self.profile and not self.profile.console and situation(self) ~= self.situation then
        self:ApplySituation(true)
    end
end

-- Events arrive in bursts: a gossip closing as its quest opens, a zone change alongside
-- the indoors flag. The situation is read once, a tick later, so only where they all
-- landed moves the camera.
function ActionCam:OnSituation()
    if not self.pending then
        self.pending = R:After(self, 0, self.Evaluate)
    end
end

function ActionCam:OnUnitEvent(_, unit)
    if unit == "player" then
        self:OnSituation()
    end
end

function ActionCam:OnTalkOpen()
    self.talking = true
    self:OnSituation()
end

-- A gossip that closes because the interaction continues into a quest or a shop is not
-- the player walking away.
function ActionCam:OnTalkClose(event, continuing)
    if event == "GOSSIP_CLOSED" and continuing then
        return
    end
    self.talking = false
    self:OnSituation()
end

-- A login or reload applies the whole profile. Any other loading screen is a zone change,
-- and only the situation matters.
function ActionCam:OnEnteringWorld(_, isInitialLogin, isReloadingUi)
    if isInitialLogin or isReloadingUi then
        self.talking = false
        self:Apply(true)
    else
        self:OnSituation()
    end
end

function ActionCam:OnSettingsChanged(_, key)
    if key == "cameraProfile" then
        self:Apply(true)
    elseif key == "cameraProfiles" then
        self:Apply(false)
    end
end

function ActionCam:OnEnable()
    self.distance, self.profile, self.situation, self.talking, self.pending = nil, nil, nil, false, nil
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
    for _, event in ipairs(TALK_OPEN) do
        Broker:Subscribe(event, self.OnTalkOpen, self)
    end
    for _, event in ipairs(TALK_CLOSE) do
        Broker:Subscribe(event, self.OnTalkClose, self)
    end
    self:OnWarning()
    -- Enabled from the login sequence, the player is not in the world yet and the situation
    -- queries have nothing to answer; PLAYER_ENTERING_WORLD applies the profile then.
    if IsPlayerInWorld() then
        self:Apply(true)
    end
end

-- The camera stays where the last situation put it: with no way to read where it was
-- before, moving it again would only be a guess.
function ActionCam:OnDisable()
    R.Broker:UnsubscribeAll(self)
    resetCVars()
    C_CVar.SetCVar(CENTERED, C_CVar.GetCVarDefault(CENTERED) or "1")
    self.profile, self.situation, self.pending, self.distance = nil, nil, nil, nil
end
