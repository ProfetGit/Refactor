--- @core conditions
--- Purpose: track player state as named flags and announce every change once, for any module that asks.
--- Requires: InCombatLockdown, IsMounted, UnitOnTaxi, IsResting, UnitExists, IsInGroup, IsInInstance, IsStealthed,
---     UnitIsDeadOrGhost
--- Events: PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, PLAYER_MOUNT_DISPLAY_CHANGED, PLAYER_CONTROL_LOST,
---     PLAYER_CONTROL_GAINED, PLAYER_UPDATE_RESTING, PLAYER_TARGET_CHANGED, GROUP_ROSTER_UPDATE, UPDATE_STEALTH,
---     PLAYER_DEAD, PLAYER_ALIVE, PLAYER_UNGHOST, PLAYER_ENTERING_WORLD, held only while a consumer is started
--- Hot: no
local _, R = ...
local Conditions = { flags = {}, supported = {}, readers = {}, owners = {}, count = 0 }
R.Conditions = Conditions
local unpack = unpack

-- The order the settings panel lists them in.
Conditions.names = { "combat", "mounted", "resting", "hasTarget", "inGroup", "inInstance", "stealthed", "dead" }

-- What each flag reads: the globals it needs, then the read over them. Everything is resolved
-- by name when the first consumer starts, so a function this client lacks costs one flag,
-- reported unsupported and always false, never the service.
local READERS = {
    combat = { "InCombatLockdown", function(inCombat) return inCombat() == true end },
    -- A taxi is not a mount to the client, but it is to a player who wants the screen clear.
    mounted = { "IsMounted", "UnitOnTaxi", function(isMounted, onTaxi)
        return isMounted() == true or onTaxi("player") == true
    end },
    resting = { "IsResting", function(isResting) return isResting() == true end },
    hasTarget = { "UnitExists", function(exists) return exists("target") == true end },
    inGroup = { "IsInGroup", function(inGroup) return inGroup() == true end },
    inInstance = { "IsInInstance", function(inInstance) return (inInstance()) == true end },
    stealthed = { "IsStealthed", function(stealthed) return stealthed() == true end },
    dead = { "UnitIsDeadOrGhost", function(deadOrGhost) return deadOrGhost("player") == true end },
}

local EVENTS = {
    PLAYER_REGEN_DISABLED = { "combat" }, PLAYER_REGEN_ENABLED = { "combat" },
    PLAYER_MOUNT_DISPLAY_CHANGED = { "mounted" }, PLAYER_CONTROL_LOST = { "mounted" },
    PLAYER_CONTROL_GAINED = { "mounted" },
    PLAYER_UPDATE_RESTING = { "resting" }, PLAYER_TARGET_CHANGED = { "hasTarget" },
    GROUP_ROSTER_UPDATE = { "inGroup" }, UPDATE_STEALTH = { "stealthed" },
    PLAYER_DEAD = { "dead" }, PLAYER_ALIVE = { "dead" }, PLAYER_UNGHOST = { "dead" },
    PLAYER_ENTERING_WORLD = Conditions.names,
}

local function buildReader(spec)
    local functions, count = {}, #spec - 1
    for index = 1, count do
        local fn = R.Capabilities:Resolve(spec[index])
        if type(fn) ~= "function" then
            return nil
        end
        functions[index] = fn
    end
    local read = spec[#spec]
    return function() return read(unpack(functions, 1, count)) end
end

local function refresh(self, names)
    local flags, changed = self.flags, false
    for _, name in ipairs(names) do
        local reader = self.readers[name]
        local value = reader ~= nil and reader() or false
        if flags[name] ~= value then
            flags[name], changed = value, true
        end
    end
    return changed
end

-- Events arrive one flag at a time except PLAYER_ENTERING_WORLD, which re-reads everything;
-- either way one announcement carries the whole set, and none goes out when nothing moved.
function Conditions:OnEvent(event)
    if refresh(self, EVENTS[event]) then
        R.Broker:Emit("REFACTOR_CONDITIONS_CHANGED", self.flags)
    end
end

-- Reference counted: the events are held only while someone is listening (PRD 9.4). The
-- first start reads silently; a consumer reads State() rather than waiting for an event.
function Conditions:Start(owner)
    assert(type(owner) == "table", "conditions owner required")
    if self.owners[owner] then
        return self.flags
    end
    self.owners[owner] = true
    self.count = self.count + 1
    if self.count == 1 then
        for _, name in ipairs(self.names) do
            local reader = buildReader(READERS[name])
            self.readers[name], self.supported[name] = reader, reader ~= nil
        end
        for event in pairs(EVENTS) do
            R.Broker:Subscribe(event, self.OnEvent, self)
        end
        refresh(self, self.names)
    end
    return self.flags
end

function Conditions:Stop(owner)
    if not self.owners[owner] then
        return
    end
    self.owners[owner] = nil
    self.count = self.count - 1
    if self.count == 0 then
        R.Broker:UnsubscribeAll(self)
        for name in pairs(self.readers) do
            self.readers[name] = nil
        end
        for _, name in ipairs(self.names) do
            self.flags[name] = false
        end
    end
end

-- The one live table. Read it, never keep or edit it.
function Conditions:State()
    return self.flags
end

-- Unknown until a consumer has started; a name nobody has resolved yet reads as supported.
function Conditions:Supported(name)
    return self.supported[name] ~= false
end
