--- @module social.acceptInvites
--- Purpose: accept party invites from friends and guild members, never from strangers.
--- Requires: AcceptGroup, StaticPopup_Hide, C_FriendList.IsFriend, C_BattleNet.GetAccountInfoByGUID, IsGuildMember
--- Events: PARTY_INVITE_REQUEST
--- Hot: no
local _, R = ...
local AcceptInvites = R:RegisterModule({
    id = "social.acceptInvites", category = "Social", nameKey = "SOCIAL_INVITE_NAME",
    descriptionKey = "SOCIAL_INVITE_DESC", detailKey = "SOCIAL_INVITE_DETAIL",
    requires = { "AcceptGroup", "StaticPopup_Hide", "C_FriendList.IsFriend", "C_BattleNet.GetAccountInfoByGUID",
        "IsGuildMember" },
    tier = "manual", risk = "automation", defaultEnabled = false,
    -- The API linter reports AcceptGroup as a protected call on Retail. Blizzard only ever
    -- calls it from secure popup handlers, so the source cannot settle it. Stays unavailable
    -- until a live client shows an addon call succeeding (M4 manual checklist).
    unavailableReasonKey = "SOCIAL_INVITE_UNVERIFIED",
})

function AcceptInvites:IsTrusted(name, guid)
    if type(guid) == "string" and #guid > 0 then
        if C_FriendList.IsFriend(guid) or C_BattleNet.GetAccountInfoByGUID(guid) ~= nil then
            return true
        end
    end
    return type(name) == "string" and IsGuildMember(name) == true
end

function AcceptInvites:OnInvite(_, name, _, _, _, _, _, inviterGUID)
    if R:Paused() or not self:IsTrusted(name, inviterGUID) then
        return
    end
    AcceptGroup()
    StaticPopup_Hide("PARTY_INVITE")
end

function AcceptInvites:OnEnable()
    R.Broker:Subscribe("PARTY_INVITE_REQUEST", self.OnInvite, self)
end

function AcceptInvites:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
