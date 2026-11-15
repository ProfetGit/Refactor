--- @module nameplates.friendTags
--- Purpose: tag friends, party and raid members on friendly player nameplates with a coloured word.
--- Requires: C_NamePlate.GetNamePlateForUnit, UnitGUID, UnitIsPlayer, UnitIsUnit, UnitInParty, UnitInRaid,
---     IsInRaid, C_FriendList.IsFriend, C_BattleNet.GetAccountInfoByGUID, issecretvalue
--- Events: NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED, GROUP_ROSTER_UPDATE (throttled),
---     FRIENDLIST_UPDATE (throttled), BN_FRIEND_INFO_CHANGED (throttled)
--- Hot: no
local _, R = ...
local Theme = R.Theme

local FriendTags = R:RegisterModule({
    id = "nameplates.friendTags",
    category = "Interface",
    nameKey = "NAMEPLATE_TAGS_NAME",
    descriptionKey = "NAMEPLATE_TAGS_DESC",
    detailKey = "NAMEPLATE_TAGS_DETAIL",
    requires = { "C_NamePlate.GetNamePlateForUnit", "UnitGUID", "UnitIsPlayer", "UnitIsUnit", "UnitInParty",
        "UnitInRaid", "IsInRaid", "C_FriendList.IsFriend", "C_BattleNet.GetAccountInfoByGUID", "issecretvalue" },
    risk = "visible",
    defaultEnabled = true,
})

-- A full raid fits; past that a plate goes untagged rather than a frame being built mid-stream.
local POOL_SIZE, TAG_GAP = 40, 1
local LABELS = { party = "NAMEPLATE_TAG_PARTY", raid = "NAMEPLATE_TAG_RAID", friend = "NAMEPLATE_TAG_FRIEND" }
local COLORS = { party = "PLATE_PARTY", raid = "PLATE_RAID", friend = "PLATE_FRIEND" }
local PLATE_UNITS = {}
for index = 1, 40 do
    PLATE_UNITS[index] = "nameplate" .. index
end

-- A secret answer can be neither tested nor passed on by addon code, so it counts as no.
local function yes(value)
    return value ~= nil and value ~= false and not issecretvalue(value)
end

-- Group first: a friend in the party is tagged for the party, which is what matters while
-- grouped. IsInRaid keeps a five-player party from reading as a raid.
function FriendTags:Kind(unit)
    if not yes(UnitIsPlayer(unit)) or yes(UnitIsUnit(unit, "player")) then
        return nil
    end
    if IsInRaid() and yes(UnitInRaid(unit)) then
        return "raid"
    end
    if yes(UnitInParty(unit)) then
        return "party"
    end
    local guid = UnitGUID(unit)
    if guid == nil or issecretvalue(guid) then
        return nil
    end
    if yes(C_FriendList.IsFriend(guid)) or C_BattleNet.GetAccountInfoByGUID(guid) ~= nil then
        return "friend"
    end
    return nil
end

function FriendTags:Drop(unit)
    local tag = self.tags[unit]
    if tag then
        self.tags[unit] = nil
        tag:ResetTag()
        self.pool:Release(tag)
    end
end

-- Placed by structure, never by measurement: nameplate regions cannot be measured on
-- Forever. With the health bar hidden (Blizzard's name-only friendly plates) the space under
-- the name is empty; with the bar showing, that space is the bar, so the tag goes above.
function FriendTags:Place(tag, plate, unitFrame)
    local container = unitFrame.HealthBarsContainer
    local bar = container and container.healthBar
    tag:SetParent(plate)
    tag:ClearAllPoints()
    if bar and container:IsShown() and bar:IsShown() then
        tag:SetPoint("BOTTOM", unitFrame.name, "TOP", 0, TAG_GAP)
    else
        tag:SetPoint("TOP", unitFrame.name, "BOTTOM", 0, -TAG_GAP)
    end
end

-- A plate whose Blizzard frame or name is hidden (another nameplate addon, a widget-only
-- plate) gets no tag: it would float under nothing.
function FriendTags:Resolve(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local unitFrame = plate and plate.UnitFrame
    local name = unitFrame and unitFrame.name
    local kind = name and unitFrame:IsShown() and name:IsShown() and self:Kind(unit)
    if not kind then
        self:Drop(unit)
        return
    end
    local tag = self.tags[unit]
    if not tag then
        if #self.pool.free == 0 then
            return
        end
        tag = self.pool:Acquire()
        self.tags[unit] = tag
    end
    tag:SetTag(R.L[LABELS[kind]], COLORS[kind])
    self:Place(tag, plate, unitFrame)
    tag:Show()
end

-- One frame late: Blizzard decides name-only mode in its own NAME_PLATE_UNIT_ADDED handler,
-- and the order two frames hear one event in is not promised.
function FriendTags:Queue(unit)
    self.pending[unit] = true
    if not self.draining then
        self.draining = true
        R:After(self, 0, self.Drain)
    end
end

-- One plate that cannot be read must not take the rest with it; the first error is kept
-- for /refactor errors.
function FriendTags:Drain()
    self.draining = false
    for unit in pairs(self.pending) do
        self.pending[unit] = nil
        if self.units[unit] then
            local ok, err = pcall(self.Resolve, self, unit)
            if not ok then
                if not self.reported then
                    self.reported = true
                    R:RecordError(self, err, "resolve")
                end
                pcall(self.Drop, self, unit)
            end
        end
    end
end

function FriendTags:OnPlateAdded(_, unit)
    if type(unit) == "string" then
        self.units[unit] = true
        self:Queue(unit)
    end
end

function FriendTags:OnPlateRemoved(_, unit)
    if type(unit) == "string" then
        self.units[unit], self.pending[unit] = nil, nil
        self:Drop(unit)
    end
end

-- Who is a friend or in the group changed: every plate up is asked again.
function FriendTags:OnRelationsChanged()
    for unit in pairs(self.units) do
        self:Queue(unit)
    end
end

function FriendTags:OnEnable()
    self.units, self.pending, self.tags = {}, {}, {}
    self.draining, self.reported = false, nil
    -- Kept across a toggle: frames cannot be freed, so building a second set would only grow.
    if not self.pool then
        self.pool = R.Pools:Create(function() return Theme:PlateTag(nil) end)
        for _ = 1, POOL_SIZE do
            self.pool:Acquire()
        end
        self.pool:ReleaseAll()
    end
    R.Broker:Subscribe("NAME_PLATE_UNIT_ADDED", self.OnPlateAdded, self)
    R.Broker:Subscribe("NAME_PLATE_UNIT_REMOVED", self.OnPlateRemoved, self)
    R.Broker:Subscribe("GROUP_ROSTER_UPDATE", self.OnRelationsChanged, self, 0.2)
    R.Broker:Subscribe("FRIENDLIST_UPDATE", self.OnRelationsChanged, self, 0.2)
    R.Broker:Subscribe("BN_FRIEND_INFO_CHANGED", self.OnRelationsChanged, self, 1)
    -- Turned on with plates already up, as from the window: they get tagged now, not only
    -- when they next appear.
    for index = 1, #PLATE_UNITS do
        local unit = PLATE_UNITS[index]
        if C_NamePlate.GetNamePlateForUnit(unit) then
            self:OnPlateAdded(nil, unit)
        end
    end
end

function FriendTags:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    if self.tags then
        for unit in pairs(self.tags) do
            self:Drop(unit)
        end
    end
    self.units, self.pending, self.tags = nil, nil, nil
    self.draining, self.reported = false, nil
end
