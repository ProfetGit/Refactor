--- @module social.acceptInvites
--- Purpose: accept party invites from friends and guild members, never from strangers.
--- Requires: AcceptGroup, StaticPopup_Hide, StaticPopup_FindVisible, C_FriendList.IsFriend,
---     C_BattleNet.GetAccountInfoByGUID, IsGuildMember
--- Events: PARTY_INVITE_REQUEST
--- Hot: no
local _, R = ...
local AcceptInvites = R:RegisterModule({
    id = "social.acceptInvites", category = "Social", nameKey = "SOCIAL_INVITE_NAME",
    descriptionKey = "SOCIAL_INVITE_DESC", detailKey = "SOCIAL_INVITE_DETAIL",
    requires = { "AcceptGroup", "StaticPopup_Hide", "StaticPopup_FindVisible", "C_FriendList.IsFriend",
        "C_BattleNet.GetAccountInfoByGUID", "IsGuildMember" },
    tier = "manual", risk = "automation", defaultEnabled = false,
})

function AcceptInvites:IsTrusted(name, guid)
    if type(guid) == "string" and #guid > 0 then
        if C_FriendList.IsFriend(guid) or C_BattleNet.GetAccountInfoByGUID(guid) ~= nil then
            return true
        end
    end
    return type(name) == "string" and IsGuildMember(name) == true
end

-- The invite event fires before Blizzard shows PARTY_INVITE, and that dialog's OnHide
-- calls DeclineGroup unless it is marked accepted. So the popup is cleared a tick later,
-- once it exists, with the flag Blizzard's own accept button sets.
function AcceptInvites:ClearPopup()
    local dialog = StaticPopup_FindVisible("PARTY_INVITE")
    if dialog then
        dialog.inviteAccepted = 1
        StaticPopup_Hide("PARTY_INVITE")
    end
end

function AcceptInvites:OnInvite(_, name, _, _, _, _, _, inviterGUID)
    if R:Paused() or not self:IsTrusted(name, inviterGUID) then
        return
    end
    AcceptGroup()
    R:After(self, 0, self.ClearPopup)
end

function AcceptInvites:OnEnable()
    R.Broker:Subscribe("PARTY_INVITE_REQUEST", self.OnInvite, self)
end

function AcceptInvites:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
