-- Deliberately small client model. Gameplay APIs must be supplied explicitly by each spec.
local Runtime = {}
local Frame = {}
Frame.__index = Frame

function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:IsEventRegistered(event) return self.events[event] == true end
function Frame:SetScript(name, callback) self.scripts[name] = callback end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:Hide() self.shown = false end
function Frame:Show() self.shown = true end
function Frame:IsShown() return self.shown end
function Frame:IsProtected() return false end

function Runtime.new()
    local env = { frames = {}, timers = {}, now = 0, messages = {}, R = {} }
    for _, key in ipairs({
        "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "tonumber", "tostring",
        "type", "unpack", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "string", "table",
        "math", "coroutine", "print", "collectgarbage",
    }) do
        env[key] = _G[key]
    end
    env.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    env._G = env
    env.wipe = function(value) for key in pairs(value) do value[key] = nil end return value end
    env.GetTime = function() return env.now end
    env.GetTimePreciseSec = env.GetTime
    env.debugstack = function() return debug.traceback("mock trace", 2) end
    env.UnitGUID = function() return "Player-test" end
    env.GetBuildInfo = function() return "12.1.0", "69814", "", 120100 end
    env.InCombatLockdown = function() return false end
    env.GetPhysicalScreenSize = function() return 1920, 1080 end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) env.messages[#env.messages + 1] = text end }
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    env.CreateFrame = function(kind, name, parent, template)
        local frame = setmetatable({
            kind = kind, name = name, parent = parent, template = template,
            events = {}, scripts = {}, shown = false,
        }, Frame)
        env.frames[#env.frames + 1] = frame
        if name then env[name] = frame end
        return frame
    end
    env.C_Timer = {}
    env.C_Timer.NewTimer = function(delay, callback)
        local timer = { due = env.now + delay, callback = callback }
        function timer:Cancel() self.cancelled = true end
        function timer:IsCancelled() return self.cancelled == true end
        env.timers[#env.timers + 1] = timer
        return timer
    end
    env.C_Timer.After = function(delay, callback) env.C_Timer.NewTimer(delay, callback) end
    function env:Load(path)
        local fn = assert(loadfile(path))
        setfenv(fn, self)
        fn("Refactor", self.R)
        return self.R
    end
    function env:Fire(event, ...)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end
    function env:Advance(seconds)
        local target, iterations = self.now + seconds, 0
        while true do
            local index, earliest
            for i, timer in ipairs(self.timers) do
                if not timer.cancelled and timer.due <= target and (not earliest or timer.due < earliest) then
                    index, earliest = i, timer.due
                end
            end
            if not index then break end
            iterations = iterations + 1
            assert(iterations < 10000, "timer loop did not terminate")
            local timer = table.remove(self.timers, index)
            self.now = timer.due
            timer.callback(timer)
        end
        self.now = target
    end
    function env:ActiveTimers()
        local count = 0
        for _, timer in ipairs(self.timers) do if not timer.cancelled then count = count + 1 end end
        return count
    end
    -- Namespace resolves the theme at load, so the libraries load first, exactly as the TOC does.
    env.strmatch, env.strfind, env.strsub, env.format = string.match, string.find, string.sub, string.format
    for _, path in ipairs({ "Libs/LibStub/LibStub.lua" }) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        chunk()
    end
    env:Load("Libs/LibRefactorTheme-1.0/LibRefactorTheme-1.0.lua")
    env:Load("Libs/LibRefactorPrice-1.0/LibRefactorPrice-1.0.lua")
    for _, path in ipairs({
        "Core/Namespace.lua", "Core/Capabilities.lua", "Core/Broker.lua", "Core/Registry.lua",
        "Core/Codec.lua", "Core/Settings.lua", "Core/Pools.lua", "Core/Safety.lua", "Core/Presets.lua",
    }) do env:Load(path) end
    env.R.Settings:Init({}, {}, "Player-test")
    return env
end

return Runtime
