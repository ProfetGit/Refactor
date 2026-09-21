--- @module social.quickInvite
--- Purpose: invite the player under the cursor to a party with a modified click.
--- Requires: C_PartyInfo.InviteUnit, UnitExists, UnitIsUnit, UnitIsPlayer, UnitIsHumanPlayer,
---     UnitIsConnected, UnitCanCooperate, UnitInParty, UnitInRaid, UnitName, UnitGUID,
---     IsControlKeyDown, IsShiftKeyDown, IsAltKeyDown
--- Events: PLAYER_TARGET_CHANGED, UPDATE_MOUSEOVER_UNIT, REFACTOR_INVITE_TEST
--- Hot: no
local _, R = ...
local QuickInvite = R:RegisterModule({
    id = "social.quickInvite", category = "Social", nameKey = "SOCIAL_QUICKINVITE_NAME",
    descriptionKey = "SOCIAL_QUICKINVITE_DESC", detailKey = "SOCIAL_QUICKINVITE_DETAIL",
    requires = { "C_PartyInfo.InviteUnit", "UnitExists", "UnitIsUnit", "UnitIsPlayer",
        "UnitIsHumanPlayer", "UnitIsConnected", "UnitCanCooperate", "UnitInParty", "UnitInRaid",
        "UnitName", "UnitGUID", "IsControlKeyDown", "IsShiftKeyDown", "IsAltKeyDown" },
    risk = "automation", defaultEnabled = false,
})

local MODIFIER_CHECKS = { CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown, ALT = IsAltKeyDown }

local function modifierDown()
    local check = MODIFIER_CHECKS[R.Settings:GetOption("inviteModifier")] or MODIFIER_CHECKS.ALT
    return type(check) == "function" and check() == true
end

-- Cross-realm invites need the realm spelled out. UnitName returns one only when it differs
-- from ours, which is exactly when C_PartyInfo.InviteUnit needs it.
local function fullName(unit)
    local name, realm = UnitName(unit)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

-- The same test Blizzard's own Invite entry uses before it draws itself: a connected human
-- player, not you, on a side you can group with, and not already in the group.
function QuickInvite:CanInvite(unit)
    if not UnitExists(unit) or UnitIsUnit(unit, "player") then
        return false
    end
    if not UnitIsPlayer(unit) or not UnitIsHumanPlayer(unit) then
        return false
    end
    if not UnitIsConnected(unit) or not UnitCanCooperate("player", unit) then
        return false
    end
    return not UnitInParty(unit) and not UnitInRaid(unit)
end

-- The cursor's unit, remembered. A click may clear mouseover before the selection change
-- arrives, which would leave the click unreadable, so the GUID from the last hover stands
-- in for it. It is dropped the moment the cursor leaves a unit, so it can never name
-- anyone but whoever the cursor was last actually on.
function QuickInvite:OnMouseoverChanged()
    self.hoverGUID = UnitExists("mouseover") and UnitGUID("mouseover") or nil
end

-- Which of the two said the new target is the one under the cursor, or nil for neither.
function QuickInvite:UnderCursor()
    if UnitExists("mouseover") and UnitIsUnit("target", "mouseover") then
        return "mouseover"
    end
    if self.hoverGUID ~= nil and self.hoverGUID == UnitGUID("target") then
        return "hover"
    end
    return nil
end

-- The client hands Lua no click on the 3D world, so the click is read from its effect:
-- clicking a unit selects it, and the cursor is on that unit when the selection changes.
-- Requiring the new target to be the unit under the cursor is what keeps a held modifier
-- from inviting whoever tab or soft targeting lands on next.
--
-- Both early returns are one function call each, which is why this sits on the event for
-- as long as the module is enabled rather than waiting for a context to open (PRD 9.4).
function QuickInvite:OnTargetChanged()
    local report = self.report
    report.changes = report.changes + 1
    if R:Paused() or not modifierDown() then
        return
    end
    report.modified = report.modified + 1
    report.name, report.via = fullName("target"), self:UnderCursor()
    if report.via == nil then
        report.verdict = "CURSOR"
        return
    end
    if not self:CanInvite("target") then
        report.verdict = "REFUSED"
        return
    end
    if not report.name then
        report.verdict = "NONAME"
        return
    end
    report.verdict = "SENT"
    C_PartyInfo.InviteUnit(report.name)
    R:Print(string.format(R.L.SOCIAL_QUICKINVITE_SENT, report.name))
end

-- /refactor invitetest. The click itself is invisible to us, so the only way to tell a
-- modifier that never arrived from a cursor that was already gone is to say what the last
-- modified selection change actually looked like.
function QuickInvite:Test()
    local report, L = self.report, R.L
    R:Print(string.format(L.CMD_INVITE_TEST_COUNTS, report.changes, report.modified,
        R.Settings:GetOption("inviteModifier")))
    if report.verdict == nil then
        R:Print(L.CMD_INVITE_TEST_NONE)
    else
        R:Print(string.format(L.CMD_INVITE_TEST_LAST, tostring(report.name),
            tostring(report.via), L["CMD_INVITE_VERDICT_" .. report.verdict]))
    end
    R:Print(string.format(L.CMD_INVITE_TEST_NOW, tostring(fullName("mouseover")),
        tostring(fullName("target"))))
end

function QuickInvite:OnEnable()
    self.report = { changes = 0, modified = 0 }
    R.Broker:Subscribe("PLAYER_TARGET_CHANGED", self.OnTargetChanged, self)
    R.Broker:Subscribe("UPDATE_MOUSEOVER_UNIT", self.OnMouseoverChanged, self)
    R.Broker:Subscribe("REFACTOR_INVITE_TEST", self.Test, self)
end

function QuickInvite:OnDisable()
    R.Broker:UnsubscribeAll(self)
    self.hoverGUID, self.report = nil, nil
end
