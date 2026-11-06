--- @module interface.actionCam
--- Purpose: apply the chosen ActionCam profile and follow the player between situations.
--- Requires: ConsoleExec, C_CVar.SetCVar, C_CVar.GetCVar, C_CVar.GetCVarBool, C_CVar.GetCVarDefault,
---     StaticPopup_Hide, CameraZoomIn, CameraZoomOut, GetCameraZoom, GetTime, IsPlayerInWorld, IsInInstance,
---     IsIndoors, IsResting, IsMounted, UnitOnTaxi, UnitInVehicle, UnitExists, InCombatLockdown,
---     GetShapeshiftFormID, Enum.PlayerInteractionType.Trainer, Enum.PlayerInteractionType.Banker,
---     Enum.PlayerInteractionType.Auctioneer
--- Events: EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED, REFACTOR_SETTINGS_CHANGED, REFACTOR_CAMERA_TEST,
---     PLAYER_ENTERING_WORLD, ZONE_CHANGED, ZONE_CHANGED_INDOORS, ZONE_CHANGED_NEW_AREA,
---     PLAYER_UPDATE_RESTING, PLAYER_MOUNT_DISPLAY_CHANGED, UPDATE_SHAPESHIFT_FORM, UNIT_ENTERED_VEHICLE,
---     UNIT_EXITED_VEHICLE, PLAYER_CONTROL_LOST, PLAYER_CONTROL_GAINED, PLAYER_REGEN_DISABLED (hold),
---     PLAYER_REGEN_ENABLED (hold), GOSSIP_SHOW, GOSSIP_CLOSED, QUEST_GREETING, QUEST_DETAIL, QUEST_PROGRESS,
---     QUEST_COMPLETE, QUEST_FINISHED, MERCHANT_SHOW, MERCHANT_CLOSED, TAXIMAP_OPENED, TAXIMAP_CLOSED,
---     PLAYER_INTERACTION_MANAGER_FRAME_SHOW, PLAYER_INTERACTION_MANAGER_FRAME_HIDE,
---     PLAYER_STARTED_MOVING (contextual: only while an NPC window is open)
--- Hot: no
local _, R = ...
local Profiles = R.CameraProfiles
local ActionCam = R:RegisterModule({
    id = "interface.actionCam", category = "Interface", nameKey = "ACTIONCAM_NAME",
    descriptionKey = "ACTIONCAM_DESC", detailKey = "ACTIONCAM_DETAIL",
    requires = { "ConsoleExec", "C_CVar.SetCVar", "C_CVar.GetCVar", "C_CVar.GetCVarBool",
        "C_CVar.GetCVarDefault", "StaticPopup_Hide", "CameraZoomIn", "CameraZoomOut", "GetCameraZoom",
        "GetTime", "IsPlayerInWorld", "IsInInstance", "IsIndoors", "IsResting", "IsMounted", "UnitOnTaxi",
        "UnitInVehicle", "UnitExists", "InCombatLockdown", "GetShapeshiftFormID",
        "Enum.PlayerInteractionType.Trainer", "Enum.PlayerInteractionType.Banker",
        "Enum.PlayerInteractionType.Auctioneer" },
    risk = "visible", defaultEnabled = false,
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
-- A change smaller than this is already where the camera is heading. LibCamera names 0.05 as
-- the smallest step the zoom calls take.
local ZOOM_STEP = 0.05
-- When the last zoom call went out. Kept at file level rather than on the module so a
-- disable and an enable in the same frame still count as one frame's budget.
local zoomedAt
local LEAVE = Profiles.LEAVE
-- The target pull is one number; the client has a yaw and a pitch strength. Blizzard's
-- defaults are 0.5 and 0.4, so the pitch follows the yaw at that ratio.
local PULL_PITCH_RATIO = 0.8
local SITUATION_EVENTS = {
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
}
local UNIT_EVENTS = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
-- An NPC window opening and closing, each under its own source so one handing over to another
-- (a gossip that turns into a trainer) is not mistaken for the player walking away. Blizzard's
-- interaction manager covers a trainer, a bank and the auction house but not gossip, a quest
-- giver or a flight master, which have their own events.
local TALK_OPEN = { GOSSIP_SHOW = "gossip", QUEST_GREETING = "quest", QUEST_PROGRESS = "quest",
    QUEST_COMPLETE = "quest", MERCHANT_SHOW = "merchant", TAXIMAP_OPENED = "taxi" }
local TALK_CLOSE = { GOSSIP_CLOSED = "gossip", QUEST_FINISHED = "quest", MERCHANT_CLOSED = "merchant",
    TAXIMAP_CLOSED = "taxi" }
-- A delve reports as a scenario and plays like a dungeon.
local INSTANCE_SITUATIONS = { party = "dungeon", scenario = "dungeon", raid = "raid", pvp = "battleground",
    arena = "arena" }
-- Travel, aquatic, Ghost Wolf, swift flight and flight forms ride like a mount. These form IDs
-- are verified in game with /refactor camtest, which prints the live one.
local TRAVEL_FORMS = { [3] = true, [4] = true, [16] = true, [27] = true, [29] = true }
local DIRECTIONS = Profiles.directions
-- A zoom this recent is still easing, so the number commanded stands in for the camera's.
local SETTLE = 2
-- How long a situation outlasts its cause when the next one is ambient, so chain pulls and
-- doorways do not pump the camera.
local LINGER = { indoors = 1, npc = 0.5 }
-- A fight holds the camera exactly where it was, and this long after one ends it is still
-- held, so chain pulls never move it at all (owner's report: every pull jarred the camera).
local COMBAT_HOLD = 3
local SHOULDER_SECONDS = 0.5
-- Within this many yards of a situation's distance, on the right side of it, the camera is
-- already where the situation wants it.
local TOLERANCE = 0.5
-- How far short of a situation's distance the camera may be and still count as there. A
-- yard or two is a move nobody notices except as a twitch, so a situation that would only
-- nudge the camera leaves it.
local SLACK = 2

local function decimal(value)
    return string.format("%.2f", value)
end

local function flag(value)
    return value and "1" or "0"
end

local function ambient(current)
    return current == nil or current == "indoors" or current == "resting"
end

-- An instance first: it says more about what the player needs to see than anything that
-- happens inside it. Then an NPC window, then a mount. Mounted over
-- indoors, because a mount indoors is passing through; indoors over resting, because an
-- inn is a room before it is a rest area.
local function situation(self)
    local _, instanceType = IsInInstance()
    local instance = INSTANCE_SITUATIONS[instanceType]
    if instance then
        return instance
    end
    if next(self.talk) ~= nil and not self.released and UnitExists("npc") and not UnitOnTaxi("player") then
        return "npc"
    end
    if IsMounted() or UnitOnTaxi("player") or UnitInVehicle("player") or TRAVEL_FORMS[GetShapeshiftFormID()] then
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

local function shoulderFor(values, current)
    return current and values[current .. "Shoulder"] or values.shoulder
end

local function resetCVars()
    for _, cvar in ipairs(CVARS) do
        C_CVar.SetCVar(cvar, C_CVar.GetCVarDefault(cvar) or "0")
    end
end

-- The distance a situation asks for, or nil when it leaves the camera alone. What the player
-- zoomed to last time in that situation stands in for the profile's number while that option
-- is on. Second result: whether it was the remembered one.
local function targetFor(self, current)
    local distance = current and self.profile.values[current .. "Distance"]
    if not distance or distance == LEAVE then
        return nil
    end
    local learned = self.learned[current]
    if learned and R.Settings:GetOption("cameraLearnZoom") then
        return learned, true
    end
    return distance, false
end

-- The client asks for confirmation every login once an experimental CVar is set. The
-- player already confirmed by enabling this module, so the dialog is closed again.
function ActionCam:OnWarning()
    StaticPopup_Hide("EXPERIMENTAL_CVAR_WARNING")
end

-- One table, refilled, for whoever shows what the camera is doing (the panel).
function ActionCam:Emit()
    local status, profile = self.status, self.profile
    status.active = profile ~= nil
    status.preset = profile ~= nil and profile.console ~= nil
    status.situation, status.target, status.direction, status.learned, status.shoulder = nil, nil, nil, false, nil
    if profile and not profile.console then
        local current = self.situation
        local target, learned = targetFor(self, current)
        status.situation, status.target, status.learned = current, target, learned or false
        status.direction = target and DIRECTIONS[current] or nil
        status.shoulder = shoulderFor(profile.values, current)
    end
    status.reduceMovement = C_CVar.GetCVarBool("CameraReduceUnexpectedMovement") == true
    R.Broker:Emit("REFACTOR_CAMERA_SITUATION", status)
end

-- The client takes one zoom call a frame and drops any other (LibCamera's source says as
-- much). This used to zoom all the way in and back out in one frame, and on Forever the zoom
-- in was the call dropped: every move pushed the camera further out by the whole distance,
-- and an NPC visit never came back (owner's report, 5 Nov 2026). So a move is one call, by
-- the difference from where the camera is heading, and a second move in the same frame is
-- sent on the next. target is what the rules work with from now; what the client was
-- actually told is sent.
function ActionCam:SetDistance(yards)
    self.target, self.movedAt = yards, GetTime()
    if zoomedAt == self.movedAt then
        if not self.flush then
            self.flush = R:After(self, 0, self.FlushZoom)
        end
        return
    end
    self:SendZoom(yards)
end

-- Where the client is taking the camera: what it was last told while that may still be
-- easing, since GetCameraZoom reads the camera mid-ease and a difference from that would
-- land short; the camera itself once it has had time to arrive.
function ActionCam:Heading()
    if self.sentAt and GetTime() - self.sentAt < SETTLE then
        return self.sent
    end
    return GetCameraZoom()
end

function ActionCam:SendZoom(yards)
    local change = yards - self:Heading()
    if change > ZOOM_STEP then
        CameraZoomOut(change)
    elseif change < -ZOOM_STEP then
        CameraZoomIn(-change)
    else
        return
    end
    self.sent, self.sentAt = yards, GetTime()
    zoomedAt = self.sentAt
end

function ActionCam:FlushZoom()
    self.flush = nil
    if self.target then
        self:SendZoom(self.target)
    end
end

-- Switched off in the same frame as a move, the restore would be the call the client drops,
-- and the module's own timers are cancelled with it. So it waits a frame under an owner of
-- its own, and OnEnable calls it off if the feature comes straight back.
local restorer = {}
local function restoreLater(owner)
    owner.token = nil
    owner.module:SendZoom(owner.yards)
end

-- Where the camera is, or will be: rules are never judged on a camera that is still easing.
function ActionCam:ZoomNow()
    if self.movedAt and GetTime() - self.movedAt < SETTLE then
        return self.target
    end
    return GetCameraZoom()
end

-- Put the camera back where the player had it, if a situation moved it.
function ActionCam:GiveBack()
    local saved = self.saved
    if saved then
        if math.abs(saved - self:ZoomNow()) > TOLERANCE then
            self:SetDistance(saved)
        end
        self.saved, self.commandedBy = nil, nil
    end
end

-- Leaving a situation this module moved, long after it settled: where the camera ended up is
-- where the player wants it in that situation, so the next visit goes there.
function ActionCam:Learn(left)
    if not left or self.commandedBy ~= left or not self.movedAt or not R.Settings:GetOption("cameraLearnZoom")
        or GetTime() - self.movedAt < SETTLE then
        return
    end
    local zoom = GetCameraZoom()
    if math.abs(zoom - self.target) >= 1 then
        self.learned[left] = math.max(Profiles.distanceMinimum, math.min(Profiles.distanceMaximum, zoom))
    end
end

-- Every situation is judged against the player's own distance, never against another
-- situation's: indoors with the wheel at 4 stays 4, a mount at 25 stays 25, and leaving
-- everything returns to the player's own. Only a camera on the wrong side of the distance
-- moves, and then the player's own distance is remembered once.
function ActionCam:Transition(left, new)
    self:Learn(left)
    local target = targetFor(self, new)
    local direction = DIRECTIONS[new]
    local own = self.saved or self:ZoomNow()
    local met = not target or (direction == "in" and own <= target + SLACK)
        or (direction == "out" and own >= target - SLACK)
    if met then
        self:GiveBack()
    else
        if not self.saved then
            self.saved = self:ZoomNow()
        end
        self:SetDistance(target)
        self.commandedBy = new
    end
end

local function writeShoulder(self, value)
    C_CVar.SetCVar("test_cameraOverShoulder", decimal(value))
    self.shoulder = value
end

-- Restarted from the value last written rather than retargeted: an Apply resets every CVar
-- first, and a fresh tween writes its start in the same frame, so the reset never shows.
function ActionCam:EaseShoulder(current)
    R.Fade:Cancel(self)
    R.Fade:Value(self, shoulderFor(self.profile.values, current), SHOULDER_SECONDS, writeShoulder,
        self.shoulder or 0)
end

function ActionCam:SnapShoulder(current)
    R.Fade:Cancel(self)
    writeShoulder(self, shoulderFor(self.profile.values, current))
end

function ActionCam:CancelLinger()
    if self.linger then
        self.linger:Cancel()
        self.linger = nil
    end
end

function ActionCam:CancelPending()
    if self.pending then
        self.pending:Cancel()
        self.pending = nil
    end
    self:CancelLinger()
end

-- A situation change: shoulder for where the player is now, zoom by the rule above.
function ActionCam:EnterSituation(current)
    local left = self.situation
    self.situation = current
    self:EaseShoulder(current)
    self:Transition(left, current)
    self:Emit()
end

local function writeProfile(self, values)
    local tilt = values.tilt
    C_CVar.SetCVar("test_cameraDynamicPitch", flag(tilt > 0))
    if tilt > 0 then
        C_CVar.SetCVar("test_cameraDynamicPitchBaseFovPad", decimal(tilt))
    end
    C_CVar.SetCVar("test_cameraHeadMovementStrength", decimal(values.headBob))
    if not values.swayWhileMoving then
        C_CVar.SetCVar("test_cameraHeadMovementMovingStrength", "0")
    end
    C_CVar.SetCVar("test_cameraTargetFocusInteractEnable", flag(values.focusInteract and not self.released))
    local pull = values.targetPull
    C_CVar.SetCVar("test_cameraTargetFocusEnemyEnable", flag(pull > 0))
    if pull > 0 then
        C_CVar.SetCVar("test_cameraTargetFocusEnemyStrengthYaw", decimal(pull))
        C_CVar.SetCVar("test_cameraTargetFocusEnemyStrengthPitch", decimal(pull * PULL_PITCH_RATIO))
    end
end

-- An edit to the profile in use moves the camera only when the number in play changed: the
-- current situation's distance previews exactly, the base distance applies outside any
-- situation, and anything else (tilt, sway, another situation) leaves the wheel alone.
function ActionCam:ApplyEdit(previous, values)
    local current = self.situation
    for _, name in ipairs(Profiles.situations) do
        local key = name .. "Distance"
        if previous[key] ~= values[key] then
            self.learned[name] = nil
        end
    end
    if current then
        local key = current .. "Distance"
        if previous[key] ~= values[key] then
            if values[key] == LEAVE then
                self:GiveBack()
            else
                if not self.saved then
                    self.saved = self:ZoomNow()
                end
                self:SetDistance(values[key])
                self.commandedBy = current
            end
        end
    elseif previous.distance ~= values.distance and values.distance ~= LEAVE then
        self:SetDistance(values.distance)
        self.saved, self.commandedBy = nil, nil
    end
end

-- The whole profile. force is a fresh start (enable, login, a profile switch): what was
-- learned is dropped and the base distance goes on exactly when no situation applies. What
-- was remembered survives a profile switch, so a switch made indoors still returns the
-- camera to the pre-building distance on the way out. Without force it is an edit to a
-- field of the profile in use, and only the number in play moves the camera: tuning a
-- raid's distance from an inn leaves the inn's camera where the player's wheel put it.
function ActionCam:Apply(force)
    local profile = Profiles:Active()
    local previous = self.profile and self.profile.values
    if not previous or not profile or profile.console or self.profile.id ~= profile.id then
        force = true
    end
    if force then
        self:CancelPending()
        self:EndHoldNow()
        self.learned = {}
    end
    self.profile = profile
    resetCVars()
    if not profile then
        R.Fade:Cancel(self)
        self.situation, self.shoulder = nil, nil
        self:Emit()
        return
    end
    C_CVar.SetCVar(CENTERED, "0")
    if profile.console then
        -- Blizzard's preset lives in the client, so its command is run rather than its
        -- values guessed. It knows nothing of situations and never moves the zoom beyond
        -- giving the player's own distance back.
        R.Fade:Cancel(self)
        self.situation, self.shoulder = nil, nil
        if self.saved then
            self:SetDistance(self.saved)
            self.saved = nil
        end
        self.commandedBy = nil
        ConsoleExec(profile.console)
        self:Emit()
        return
    end
    local values = profile.values
    writeProfile(self, values)
    if not force then
        self:SnapShoulder(self.situation)
        self:ApplyEdit(previous, values)
        self:Emit()
        return
    end
    local current = situation(self)
    self.situation = current
    self:EaseShoulder(current)
    if current then
        self:Transition(nil, current)
    elseif values.distance ~= LEAVE then
        self:SetDistance(values.distance)
        self.saved, self.commandedBy = nil, nil
    else
        self:GiveBack()
    end
    self:Emit()
end

-- Settle on the situation as it stands. A situation that outlasts its cause (a pull, a
-- doorway, an NPC window) waits before giving way to an ambient one, and is cancelled by
-- its own return; anything that is not ambient takes over at once.
function ActionCam:Settle(noLinger)
    if not self.profile or self.profile.console or self.holding then
        return
    end
    local current = situation(self)
    if current == self.situation then
        self:CancelLinger()
        return
    end
    -- Just after a fight only a deliberate change gets through: a mount, an NPC, an instance.
    if self.hold then
        if ambient(current) then
            return
        end
        self:EndHoldNow()
    end
    if not noLinger and ambient(current) then
        if self.linger then
            return
        end
        local wait = LINGER[self.situation]
        if wait then
            self.linger = R:After(self, wait, self.EndLinger)
            return
        end
    end
    self:CancelLinger()
    self:EnterSituation(current)
end

function ActionCam:Evaluate()
    self.pending = nil
    self:Settle(false)
end

-- A fight starting: nothing moves, and any wait already running is moot. Whatever changes
-- during the fight (a dismount, a doorway) is read once the hold ends.
function ActionCam:OnCombatStart()
    self.holding = true
    self:CancelLinger()
    self:EndHoldNow()
end

-- holding is the fight itself, when nothing moves; hold is the few seconds after it, when
-- only an ambient change still waits. Anything else that changed during the fight is read now.
function ActionCam:OnCombatEnd()
    self.holding = false
    if not self.hold then
        self.hold = R:After(self, COMBAT_HOLD, self.EndHold)
    end
    self:OnSituation()
end

function ActionCam:EndHoldNow()
    if self.hold then
        self.hold:Cancel()
        self.hold = nil
    end
end

-- The hold was the wait, so whatever the situation is now applies at once.
function ActionCam:EndHold()
    self.hold = nil
    self:Settle(true)
end

-- The wait is over. This enters whatever the situation is by now rather than asking
-- Evaluate, which would start the wait again.
function ActionCam:EndLinger()
    self.linger = nil
    if self.profile and not self.profile.console and not self.holding then
        local current = situation(self)
        if current ~= self.situation then
            self:EnterSituation(current)
        end
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

-- Any window opening is the player engaging again, even after a step away let go of the
-- last one: a quest picked from a gossip brings the focus back.
function ActionCam:AddTalk(source)
    if not source then
        return
    end
    if next(self.talk) == nil then
        R.Broker:Subscribe("PLAYER_STARTED_MOVING", self.OnStartedMoving, self)
    end
    self.talk[source] = true
    if self.released then
        self.released = false
        if self.profile and not self.profile.console then
            C_CVar.SetCVar("test_cameraTargetFocusInteractEnable", flag(self.profile.values.focusInteract))
        end
    end
    self:OnSituation()
end

-- The last window closing drops the movement event and gives the camera its focus back.
function ActionCam:EmptyTalk()
    R.Broker:Unsubscribe("PLAYER_STARTED_MOVING", self)
    if self.released then
        self.released = false
        if self.profile and not self.profile.console then
            C_CVar.SetCVar("test_cameraTargetFocusInteractEnable", flag(self.profile.values.focusInteract))
        end
    end
end

function ActionCam:RemoveTalk(source)
    if source and self.talk[source] then
        self.talk[source] = nil
        if next(self.talk) == nil then
            self:EmptyTalk()
        end
        self:OnSituation()
    end
end

function ActionCam:OnTalkOpen(event)
    self:AddTalk(TALK_OPEN[event])
end

function ActionCam:OnTalkClose(event)
    self:RemoveTalk(TALK_CLOSE[event])
end

-- A quest a party member shares, or one that starts from an item, is not an NPC talking.
function ActionCam:OnQuestDetail(_, questStartItemID)
    if not questStartItemID or questStartItemID == 0 then
        self:AddTalk("quest")
    end
end

function ActionCam:OnInteractionShow(_, interaction)
    if self.interactions[interaction] then
        self:AddTalk(interaction)
    end
end

function ActionCam:OnInteractionHide(_, interaction)
    if self.interactions[interaction] then
        self:RemoveTalk(interaction)
    end
end

-- The first step away from an open window lets go: the camera stops facing the NPC and goes
-- back to the player's distance at once, while the window stays Blizzard's until it closes
-- itself. Turning in place is a different event and does not count.
function ActionCam:OnStartedMoving()
    if next(self.talk) == nil then
        return
    end
    self.released = true
    if self.profile and not self.profile.console then
        C_CVar.SetCVar("test_cameraTargetFocusInteractEnable", "0")
    end
    self:CancelPending()
    self:Settle(true)
end

-- A login or reload applies the whole profile. Any other loading screen is a zone change,
-- and only the situation matters. Every loading screen ends whatever window was open.
function ActionCam:OnEnteringWorld(_, isInitialLogin, isReloadingUi)
    if next(self.talk) ~= nil then
        self.talk = {}
        self:EmptyTalk()
    end
    -- A loading screen ends a fight without always saying so.
    if self.holding and not InCombatLockdown() then
        if self.hold then
            self.hold:Cancel()
        end
        self.hold, self.holding = nil, false
    end
    if isInitialLogin or isReloadingUi then
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
    elseif key == "cameraLearnZoom" then
        self:Emit()
    end
end

local function listOf(keys)
    local names = {}
    for key in pairs(keys) do
        names[#names + 1] = tostring(key)
    end
    table.sort(names)
    return #names > 0 and table.concat(names, ",") or R.L.CMD_CAMERA_TEST_NONE
end

-- /refactor camtest: the live answers the rules depend on, which a debugger would otherwise
-- have to supply. The form ID and the NPC unit are the two nobody has verified on Forever.
function ActionCam:Test()
    local L, profile = R.L, self.profile
    local function show(value)
        return value == nil and L.CMD_CAMERA_TEST_NONE or tostring(value)
    end
    local target, learned = targetFor(self, self.situation)
    local direction = target and DIRECTIONS[self.situation]
    local rule = L.CMD_CAMERA_TEST_RULE_NONE
    if target then
        rule = string.format(direction == "in" and L.CMD_CAMERA_TEST_RULE_IN or L.CMD_CAMERA_TEST_RULE_OUT,
            target, learned and L.CMD_CAMERA_TEST_LEARNED or "")
    end
    R:Print(string.format(L.CMD_CAMERA_TEST_PROFILE, show(profile and (profile.name or profile.id)),
        show(self.situation), rule))
    local remembered = {}
    for name, yards in pairs(self.learned) do
        remembered[#remembered + 1] = name .. "=" .. string.format("%.1f", yards)
    end
    table.sort(remembered)
    R:Print(string.format(L.CMD_CAMERA_TEST_ZOOM, GetCameraZoom(), show(self.saved), show(self.commandedBy),
        #remembered > 0 and table.concat(remembered, ",") or L.CMD_CAMERA_TEST_NONE))
    -- Where the last move asked to go, beside the zoom line above: if the two disagree long
    -- after the move, the client is not moving the camera the way SetDistance assumes.
    if self.sentAt then
        R:Print(string.format(L.CMD_CAMERA_TEST_MOVE, self.sent, GetTime() - self.sentAt))
    end
    R:Print(string.format(L.CMD_CAMERA_TEST_CVARS, show(C_CVar.GetCVar("test_cameraOverShoulder")),
        show(C_CVar.GetCVar("CameraReduceUnexpectedMovement")), show(C_CVar.GetCVar(CENTERED)),
        show(C_CVar.GetCVar("cameraDistanceMaxZoomFactor"))))
    R:Print(string.format(L.CMD_CAMERA_TEST_HOLD, tostring(self.holding == true)))
    R:Print(string.format(L.CMD_CAMERA_TEST_TALK, listOf(self.talk), tostring(self.released),
        tostring(UnitExists("npc") == true), show(GetShapeshiftFormID())))
end

function ActionCam:OnEnable()
    if restorer.token then
        restorer.token:Cancel()
        restorer.token = nil
    end
    self.profile, self.situation, self.saved, self.commandedBy = nil, nil, nil, nil
    self.target, self.movedAt, self.shoulder = nil, nil, nil
    self.sent, self.sentAt, self.flush = nil, nil, nil
    self.talk, self.released, self.learned = {}, false, {}
    self.pending, self.linger, self.status = nil, nil, {}
    -- Switched on mid-fight, the camera is placed once and then held like any other fight.
    self.holding, self.hold = InCombatLockdown() == true, nil
    local types = Enum.PlayerInteractionType
    self.interactions = { [types.Trainer] = true, [types.Banker] = true, [types.Auctioneer] = true }
    local Broker = R.Broker
    Broker:Subscribe("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED", self.OnWarning, self)
    Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
    Broker:Subscribe("REFACTOR_CAMERA_TEST", self.Test, self)
    Broker:Subscribe("PLAYER_ENTERING_WORLD", self.OnEnteringWorld, self)
    Broker:Subscribe("PLAYER_REGEN_DISABLED", self.OnCombatStart, self)
    Broker:Subscribe("PLAYER_REGEN_ENABLED", self.OnCombatEnd, self)
    for _, event in ipairs(SITUATION_EVENTS) do
        Broker:Subscribe(event, self.OnSituation, self)
    end
    for _, event in ipairs(UNIT_EVENTS) do
        Broker:Subscribe(event, self.OnUnitEvent, self)
    end
    for event in pairs(TALK_OPEN) do
        Broker:Subscribe(event, self.OnTalkOpen, self)
    end
    for event in pairs(TALK_CLOSE) do
        Broker:Subscribe(event, self.OnTalkClose, self)
    end
    Broker:Subscribe("QUEST_DETAIL", self.OnQuestDetail, self)
    Broker:Subscribe("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", self.OnInteractionShow, self)
    Broker:Subscribe("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", self.OnInteractionHide, self)
    self:OnWarning()
    -- Enabled from the login sequence, the player is not in the world yet and the situation
    -- queries have nothing to answer; PLAYER_ENTERING_WORLD applies the profile then.
    if IsPlayerInWorld() then
        self:Apply(true)
    end
end

-- Off mid-situation, the camera goes back to where the player had it before that
-- situation moved it. With nothing remembered it stays where it is. The shoulder tween is
-- stopped first so nothing writes after the CVars are back at the client's defaults.
function ActionCam:OnDisable()
    R.Broker:UnsubscribeAll(self)
    self:CancelPending()
    R.Fade:Cancel(self)
    resetCVars()
    C_CVar.SetCVar(CENTERED, C_CVar.GetCVarDefault(CENTERED) or "1")
    -- sent and sentAt are kept: a restore that waits a frame still needs to know where the
    -- camera was heading.
    if self.flush then
        self.flush:Cancel()
        self.flush = nil
    end
    if self.saved then
        if zoomedAt == GetTime() then
            restorer.module, restorer.yards = self, self.saved
            restorer.token = R:After(restorer, 0, restoreLater)
        else
            self:SendZoom(self.saved)
        end
    end
    self.profile, self.situation, self.saved, self.commandedBy = nil, nil, nil, nil
    self.target, self.movedAt, self.shoulder = nil, nil, nil
    self.talk, self.released, self.learned = {}, false, {}
    if self.hold then
        self.hold:Cancel()
    end
    self.holding, self.hold = false, nil
    self:Emit()
end
