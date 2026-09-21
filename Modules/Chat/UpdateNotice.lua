--- @module social.updateNotice
--- Purpose: say once when a guild or group member runs a newer Refactor than this one.
--- Requires: C_ChatInfo.RegisterAddonMessagePrefix, C_ChatInfo.SendAddonMessage,
---     C_AddOns.GetAddOnMetadata, IsInGuild, IsInGroup, IsInRaid, LE_PARTY_CATEGORY_HOME,
---     LE_PARTY_CATEGORY_INSTANCE, GetTime
--- Events: CHAT_MSG_ADDON, GROUP_ROSTER_UPDATE (throttled), REFACTOR_UPDATE_REPORT
--- Hot: no
local _, R = ...
local UpdateNotice = R:RegisterModule({
    id = "social.updateNotice", category = "Social", nameKey = "SOCIAL_UPDATE_NAME",
    descriptionKey = "SOCIAL_UPDATE_DESC", detailKey = "SOCIAL_UPDATE_DETAIL",
    requires = { "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage",
        "C_AddOns.GetAddOnMetadata", "IsInGuild", "IsInGroup", "IsInRaid",
        "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE", "GetTime" },
    risk = "safe", defaultEnabled = true,
})

-- The client allows sixteen characters of prefix. The payload starts with a letter for its
-- kind, so a later message can carry its own letter under the same prefix.
local PREFIX = "Refactor"
-- Long enough after login for guild membership and a group to be settled on the client.
local ANNOUNCE_DELAY = 10
-- Two sends on one channel closer than this are a burst, whatever caused it.
local SEND_GAP = 5
local ROSTER_THROTTLE = 5
-- Every newer copy that hears an older one waits a random slice of this window before
-- answering, and drops its answer when a copy at least as new speaks first. A guild of
-- fifty on one build sends about one answer per login rather than fifty.
local REPLY_MIN, REPLY_MAX = 1, 4
local MAX_PART = 9999
local REPLY_CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- One number per version, so newer is a plain comparison, and the version reduced to the
-- three numbers that were compared. A packager token or a string with no numbers gives
-- nil, and a copy with no rank neither speaks nor compares.
local function rankOf(text)
    local major, minor, patch = tostring(text or ""):match("^v?(%d+)%.(%d+)%.(%d+)")
    if not major then
        return nil
    end
    major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
    if major > MAX_PART or minor > MAX_PART or patch > MAX_PART then
        return nil
    end
    local rank = (major * (MAX_PART + 1) + minor) * (MAX_PART + 1) + patch
    return rank, string.format("%d.%d.%d", major, minor, patch)
end

function UpdateNotice:Send(channel)
    local now, last = GetTime(), self.lastSent[channel]
    if last and now - last < SEND_GAP then
        return false
    end
    self.lastSent[channel] = now
    C_ChatInfo.SendAddonMessage(PREFIX, self.wire, channel)
    return true
end

-- An instance group and a home group can exist at once, which is why this is not one
-- chain. The channel names are the ones the client's own chat box maps each group to.
function UpdateNotice:SendToGroup()
    local sent = false
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        sent = self:Send("INSTANCE_CHAT") or sent
    end
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then
        sent = self:Send("RAID") or sent
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        sent = self:Send("PARTY") or sent
    end
    return sent
end

function UpdateNotice:Announce()
    local sent = false
    if IsInGuild() then
        sent = self:Send("GUILD") or sent
    end
    sent = self:SendToGroup() or sent
    -- Roster churn at login would otherwise speak before the announcement does.
    self.inGroup = IsInGroup()
    R.Broker:Subscribe("GROUP_ROSTER_UPDATE", self.OnRoster, self, ROSTER_THROTTLE)
    return sent
end

-- Only the moment of joining speaks. Everyone already there hears the newcomer, and the
-- ones with something newer answer, so a roster that keeps changing costs nothing more.
function UpdateNotice:OnRoster()
    local inGroup = IsInGroup()
    if inGroup and not self.inGroup then
        self:SendToGroup()
    end
    self.inGroup = inGroup
end

function UpdateNotice:DropReply(channel)
    local pending = self.pendingReply[channel]
    if pending then
        pending:Cancel()
        self.pendingReply[channel] = nil
    end
end

function UpdateNotice:QueueReply(channel)
    if not REPLY_CHANNELS[channel] or self.pendingReply[channel] then
        return
    end
    local delay = REPLY_MIN + math.random() * (REPLY_MAX - REPLY_MIN)
    self.pendingReply[channel] = R:After(self, delay, function()
        self.pendingReply[channel] = nil
        self:Send(channel)
    end)
end

function UpdateNotice:OnMessage(_, prefix, text, channel, sender)
    if prefix ~= PREFIX then
        return
    end
    local rank, version = rankOf(tostring(text):match("^V(%d+%.%d+%.%d+)$"))
    if not rank then
        return
    end
    if rank > self.rank then
        -- Whoever asked on this channel has been answered by someone newer than us.
        self:DropReply(channel)
        if not self.newestRank or rank > self.newestRank then
            self.newestRank, self.newestVersion, self.newestFrom = rank, version, tostring(sender)
        end
        if not self.toldRank or rank > self.toldRank then
            self.toldRank = rank
            R:Print(string.format(R.L.SOCIAL_UPDATE_AVAILABLE, version, tostring(sender), self.version))
        end
    elseif rank == self.rank then
        self:DropReply(channel)
    else
        self:QueueReply(channel)
    end
end

-- /refactor update.
function UpdateNotice:Report()
    local L = R.L
    if not self.rank then
        R:Print(L.CMD_UPDATE_NO_VERSION)
        return
    end
    R:Print(string.format(L.CMD_UPDATE_RUNNING, self.version))
    if self.newestVersion then
        R:Print(string.format(L.CMD_UPDATE_NEWEST, self.newestVersion, self.newestFrom))
    else
        R:Print(L.CMD_UPDATE_NONE)
    end
    -- A deliberate ask always goes out, so the burst gap is cleared first.
    for channel in pairs(self.lastSent) do
        self.lastSent[channel] = nil
    end
    R:Print(self:Announce() and L.CMD_UPDATE_ASKED or L.CMD_UPDATE_NOBODY)
end

function UpdateNotice:OnEnable()
    self.lastSent, self.pendingReply = {}, {}
    self.newestRank, self.newestVersion, self.newestFrom, self.toldRank = nil, nil, nil, nil
    R.Broker:Subscribe("REFACTOR_UPDATE_REPORT", self.Report, self)
    self.rank, self.version = rankOf(C_AddOns.GetAddOnMetadata(R.name, "Version"))
    if not self.rank then
        return
    end
    self.wire = "V" .. self.version
    -- A prefix stays registered for the session; the client offers no way to drop one.
    -- Leaving the event below is what makes disable silent.
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    -- Unthrottled on purpose: a throttle keeps only the newest event, and an older copy's
    -- question must not vanish because a newer copy spoke in the same instant. The first
    -- line of the handler drops every other addon's traffic.
    R.Broker:Subscribe("CHAT_MSG_ADDON", self.OnMessage, self)
    R:After(self, ANNOUNCE_DELAY, self.Announce)
end

function UpdateNotice:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    self.lastSent, self.pendingReply, self.inGroup = nil, nil, nil
    self.rank, self.version, self.wire = nil, nil, nil
    self.newestRank, self.newestVersion, self.newestFrom, self.toldRank = nil, nil, nil, nil
end
