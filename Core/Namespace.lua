local addonName, R = ...
_G.Refactor = R

-- Libs load before Core, so the theme is available to every file through the namespace.
R.Theme = LibStub("LibRefactorTheme-1.0")
R.Price = LibStub("LibRefactorPrice-1.0")
-- The one place the addon's own icon paths are spelled out lives in the theme; this is the
-- namespace handle onto it. The .toc IconTexture is Blizzard's copy of icons.app.
R.Media = { icons = R.Theme.icons }
R.name = addonName
R.modules = {}
R.moduleByID = {}
R.errors = {}
R.timers = {}
R.ownedFrames = {}

local unpack = unpack
local MAX_ERRORS, MAX_TRACE = 30, 4096

local function traceError(err)
    local message = tostring(err)
    if type(debugstack) == "function" then
        message = message .. "\n" .. debugstack(2, 12, 8)
    elseif debug and debug.traceback then
        message = debug.traceback(message, 2)
    end
    return message:sub(1, MAX_TRACE)
end

-- Frames Refactor creates register here so the bench can count idle OnUpdate handlers on
-- the frames themselves, not only through the lint rule.
function R:OwnFrame(frame)
    if type(frame) == "table" then
        self.ownedFrames[frame] = true
    end
end

function R:RecordError(owner, err, context)
    local errors = self.errors
    if #errors >= MAX_ERRORS then
        table.remove(errors, 1)
    end
    errors[#errors + 1] = {
        module = type(owner) == "table" and owner.id or "core",
        context = context,
        message = tostring(err):sub(1, MAX_TRACE),
    }
end

function R:Try(owner, callback, context, ...)
    local args, count = { ... }, select("#", ...)
    local ok, result = xpcall(function() return callback(owner, unpack(args, 1, count)) end, traceError)
    if not ok then
        self:RecordError(owner, result, context)
    end
    return ok, result
end

function R:SafeCall(owner, callback, context, ...)
    local ok, result = self:Try(owner, callback, context, ...)
    if not ok and self.Registry then
        self.Registry:Fail(owner, result)
    end
    return ok, result
end

function R:Fail(owner, err, context)
    self:RecordError(owner, err, context)
    if self.Registry then
        self.Registry:Fail(owner, err)
    end
end

function R:After(owner, seconds, callback)
    assert(type(owner) == "table", "timer owner required")
    assert(type(callback) == "function", "timer callback required")
    local owned = self.timers[owner]
    if not owned then
        owned = {}
        self.timers[owner] = owned
    end
    local token = { active = true }
    owned[token] = true
    function token:Cancel()
        self.active = false
        owned[self] = nil
        if self.native then
            self.native:Cancel()
        end
        if not next(owned) then
            R.timers[owner] = nil
        end
    end
    token.native = C_Timer.NewTimer(seconds, function()
        if not token.active then
            return
        end
        token.active = false
        owned[token] = nil
        if not next(owned) then
            R.timers[owner] = nil
        end
        R:SafeCall(owner, callback, "timer")
    end)
    return token
end

function R:CancelTimers(owner)
    local owned = self.timers[owner]
    if owned then
        for timer in pairs(owned) do
            timer:Cancel()
        end
        self.timers[owner] = nil
    end
end

-- Blizzard layout constants a module may change, each restored on disable. Kept here so
-- every global write in the addon stays in this one file (rule 3).
local BLIZZARD_TUNABLES = { MERCHANT_ITEMS_PER_PAGE = true }

function R:SetBlizzardTunable(name, value)
    assert(BLIZZARD_TUNABLES[name], "not an approved Blizzard tunable")
    _G[name] = value
end

-- SavedVariables and slash registration are the required Blizzard global exceptions.
function R:InitSavedVariables(guid)
    if type(_G.RefactorDB) ~= "table" then
        _G.RefactorDB = {}
    end
    if type(_G.RefactorCharDB) ~= "table" then
        _G.RefactorCharDB = {}
    end
    self.Settings:Init(_G.RefactorDB, _G.RefactorCharDB, guid)
end

function R:RegisterSlash(handler)
    _G.SLASH_REFACTOR1 = "/refactor"
    -- The short alias is a courtesy, never a claim: leave it alone if anything answers it.
    local taken = _G.hash_SlashCmdList and _G.hash_SlashCmdList["/RF"] or _G.SLASH_RF1
    if not taken then
        _G.SLASH_REFACTOR2 = "/rf"
    end
    _G.SlashCmdList.REFACTOR = handler
end
