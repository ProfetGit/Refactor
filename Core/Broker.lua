local _, R = ...
local Broker = { events = {}, nextOrder = 0 }
R.Broker = Broker
local unpack = unpack
local frame = CreateFrame("Frame")
Broker.frame = frame

local function isInternal(event)
    return event:sub(1, 9) == "REFACTOR_"
end

local function invoke(subscription, event, args, count)
    if subscription.active then
        subscription.last = GetTime()
        R:SafeCall(subscription.owner, subscription.handler, event, event, unpack(args, 1, count))
    end
end

local function append(self, entries, handler, owner, throttle, priority)
    for _, entry in ipairs(entries) do
        if entry.owner == owner and entry.handler == handler then
            return entry
        end
    end
    self.nextOrder = self.nextOrder + 1
    local subscription = {
        owner = owner, handler = handler, throttle = throttle or 0,
        priority = priority or 0, order = self.nextOrder, active = true,
    }
    entries[#entries + 1] = subscription
    table.sort(entries, function(a, b)
        if a.priority == b.priority then
            return a.order < b.order
        end
        return a.priority > b.priority
    end)
    return subscription
end

function Broker:Subscribe(event, handler, owner, throttle, priority)
    assert(type(event) == "string" and type(handler) == "function" and type(owner) == "table")
    assert(throttle == nil or type(throttle) == "number" and throttle >= 0, "invalid throttle")
    local entries = self.events[event]
    assert(not (entries and entries.unit), "event is held for one unit")
    if not entries then
        entries = {}
        self.events[event] = entries
        if not isInternal(event) then
            frame:RegisterEvent(event)
        end
    end
    return append(self, entries, handler, owner, throttle, priority)
end

-- A unit event the client filters before Lua sees it: the player's spellcasts arrive, a
-- raid's never do, and nothing has to read the payload's unit, which can be secret while
-- casts are restricted. An event is held for one unit or for every unit, never both.
function Broker:SubscribeUnit(event, unit, handler, owner)
    assert(type(event) == "string" and not isInternal(event) and type(unit) == "string")
    assert(type(handler) == "function" and type(owner) == "table")
    local entries = self.events[event]
    assert(entries == nil or entries.unit == unit, "event is held for another unit")
    if not entries then
        entries = { unit = unit }
        self.events[event] = entries
        frame:RegisterUnitEvent(event, unit)
    end
    return append(self, entries, handler, owner)
end

function Broker:Unsubscribe(event, owner)
    local entries = self.events[event]
    if not entries then
        return
    end
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry.owner == owner then
            entry.active = false
            if entry.timer then
                entry.timer:Cancel()
            end
            entry.pending = nil
            table.remove(entries, i)
        end
    end
    if #entries == 0 then
        self.events[event] = nil
        if not isInternal(event) then
            frame:UnregisterEvent(event)
        end
    end
end

function Broker:UnsubscribeAll(owner)
    for event in pairs(self.events) do
        self:Unsubscribe(event, owner)
    end
end

function Broker:Emit(event, ...)
    local entries = self.events[event]
    if not entries then
        return
    end
    -- A callback may remove itself or another owner; a snapshot preserves dispatch order.
    local snapshot, args, count = {}, { ... }, select("#", ...)
    for i, entry in ipairs(entries) do
        snapshot[i] = entry
    end
    for _, entry in ipairs(snapshot) do
        if entry.active then
            local elapsed = entry.last and GetTime() - entry.last or entry.throttle
            if entry.throttle == 0 or elapsed >= entry.throttle then
                if entry.timer then
                    entry.timer:Cancel()
                    entry.timer, entry.pending = nil, nil
                end
                invoke(entry, event, args, count)
            else
                entry.pending, entry.pendingCount = args, count
                if not entry.timer then
                    entry.timer = R:After(entry.owner, entry.throttle - elapsed, function()
                        entry.timer = nil
                        local latest, latestCount = entry.pending, entry.pendingCount
                        entry.pending = nil
                        if latest then
                            invoke(entry, event, latest, latestCount)
                        end
                    end)
                end
            end
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    Broker:Emit(event, ...)
end)
