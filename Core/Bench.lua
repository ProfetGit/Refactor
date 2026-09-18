--- @core bench
--- Purpose: measure the release-gate budgets in PRD 9.2 from inside the client.
--- Requires: GetTime, GetTimePreciseSec, UpdateAddOnMemoryUsage, GetAddOnMemoryUsage, GetAddOnCPUUsage,
---     GetFramerate, C_CVar.GetCVarBool
--- Events: ADDON_LOADED, PLAYER_LOGIN
--- Hot: no
local _, R = ...
local Bench = { frames = R.ownedFrames }
R.Bench = Bench

local SAMPLE_SECONDS = 5

local function now()
    local clock = R.Capabilities:Resolve("GetTimePreciseSec")
    return clock and clock() or GetTime()
end

Bench.loadedAt = now()

function Bench:OnAddonLoaded(_, name)
    if name == R.name then
        self.addonLoadedAt = now()
        R.Broker:Unsubscribe("ADDON_LOADED", self)
    end
end

function Bench:OnLogin()
    self.loginAt = now()
    R.Broker:Unsubscribe("PLAYER_LOGIN", self)
end

function Bench:CountOnUpdate()
    local count = 0
    for frame in pairs(self.frames) do
        if frame.GetScript and frame:GetScript("OnUpdate") then
            count = count + 1
        end
    end
    return count
end

function Bench:Memory()
    local update = R.Capabilities:Resolve("UpdateAddOnMemoryUsage")
    local read = R.Capabilities:Resolve("GetAddOnMemoryUsage")
    if not update or not read then
        return nil
    end
    update()
    return read(R.name)
end

function Bench:Handlers()
    local events, handlers = 0, 0
    for _, entries in pairs(R.Broker.events) do
        events = events + 1
        handlers = handlers + #entries
    end
    return events, handlers
end

function Bench:Enabled()
    local count = 0
    for _, module in ipairs(R.modules) do
        if module.state == "enabled" then
            count = count + 1
        end
    end
    return count
end

function Bench:Start(report)
    if self.sample then
        report(R.L.BENCH_RUNNING)
        return
    end
    local cpuRead = R.Capabilities:Resolve("GetAddOnCPUUsage")
    local profiling = C_CVar.GetCVarBool("scriptProfile") == true
    self.sample = {
        report = report, startedAt = now(),
        memory = self:Memory(), garbage = collectgarbage("count"),
        cpu = profiling and cpuRead and cpuRead(R.name) or nil,
        framerate = GetFramerate(),
    }
    report(string.format(R.L.BENCH_SAMPLING, SAMPLE_SECONDS))
    R:After(self, SAMPLE_SECONDS, self.Finish)
end

function Bench:Finish()
    local sample = self.sample
    self.sample = nil
    if not sample then
        return
    end
    local elapsed = math.max(0.001, now() - sample.startedAt)
    local lines = self:Lines(sample, elapsed)
    for _, line in ipairs(lines) do
        sample.report(line)
    end
end

function Bench:Lines(sample, elapsed)
    local L = R.L
    local lines = {}
    if self.addonLoadedAt and self.loginAt then
        lines[#lines + 1] = string.format(L.BENCH_LOAD, (self.loginAt - self.addonLoadedAt) * 1000)
    end
    local memory = self:Memory()
    if memory then
        lines[#lines + 1] = string.format(L.BENCH_MEMORY, memory)
    end
    local garbage = (collectgarbage("count") - sample.garbage) / elapsed
    lines[#lines + 1] = string.format(L.BENCH_GARBAGE, garbage)
    local cpuRead = R.Capabilities:Resolve("GetAddOnCPUUsage")
    if sample.cpu and cpuRead then
        local frames = math.max(1, elapsed * ((sample.framerate + GetFramerate()) / 2))
        lines[#lines + 1] = string.format(L.BENCH_CPU, (cpuRead(R.name) - sample.cpu) / frames)
    else
        lines[#lines + 1] = L.BENCH_CPU_OFF
    end
    local events, handlers = self:Handlers()
    lines[#lines + 1] = string.format(L.BENCH_HANDLERS, self:Enabled(), events, handlers)
    lines[#lines + 1] = string.format(L.BENCH_ONUPDATE, self:CountOnUpdate())
    return lines
end

R.Broker:Subscribe("ADDON_LOADED", Bench.OnAddonLoaded, Bench)
R.Broker:Subscribe("PLAYER_LOGIN", Bench.OnLogin, Bench, nil, 1000)
