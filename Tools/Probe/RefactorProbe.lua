--- Dev only, never packaged (PRD 10.8). Records what this client really exposes to addons, so
--- API questions are settled by the client rather than by Retail source. It runs on the first
--- login of each client build, or on /refactorprobe, and records:
---   every global with its Lua type, and the addon that tainted it if one did
---   one level of fields on every global table that is not a frame or a mixin, two on Enum
---   the methods of each widget type it can create
---   whether each atlas LibRefactorTheme asks for exists
---   console variables and commands
---   events and secret-value counts from Blizzard's API documentation, when it loads
--- /reload writes RefactorProbeDB; Tools/probe-to-json.lua turns that file into an index.
local _G = _G
local pairs, ipairs, type, pcall, rawget, tostring = pairs, ipairs, type, pcall, rawget, tostring
local concat, sort = table.concat, table.sort

-- Walking every global in one go stalls a full UI for a noticeable moment at login, so the
-- walk yields whenever a frame's share is spent and carries on in the next frame.
local FRAME_BUDGET_MS = 20
-- A table this big is data rather than an API namespace: its size is kept, its keys are not.
local FIELD_CAP = 4000

local SAMPLE_FRAMES = {
    "Frame", "Button", "CheckButton", "EditBox", "ScrollFrame", "Slider", "StatusBar", "Cooldown",
    "GameTooltip", "MessageFrame", "ScrollingMessageFrame", "SimpleHTML", "ColorSelect",
    "Model", "PlayerModel", "DressUpModel", "CinematicModel", "TabardModel", "ModelScene",
}
local SAMPLE_ANIMATIONS = {
    "Alpha", "Translation", "Scale", "Rotation", "Path", "FlipBook", "TextureCoordTranslation",
    "LineScale", "LineTranslation", "VertexColor",
}

-- Each list is saved as one newline-joined string. A dump holds well over a hundred thousand
-- names, and one string per list keeps the file inside the constant limit a Lua 5.1 loader
-- has for a single chunk, which is how the converter reads it.
local function join(list)
    sort(list)
    return concat(list, "\n")
end

local errors
local function note(step, message)
    errors[#errors + 1] = step .. ": " .. tostring(message)
end

-- Samples are created once at load, never from an event handler.
local samples = {}
local function sample(create)
    local ok, object = pcall(create)
    if ok and object then samples[#samples + 1] = object end
end
local host = CreateFrame("Frame")
samples[1] = host
for _, kind in ipairs(SAMPLE_FRAMES) do
    sample(function() return CreateFrame(kind, nil, host) end)
end
sample(function() return host:CreateTexture() end)
sample(function() return host:CreateFontString() end)
sample(function() return host:CreateLine() end)
sample(function() return host:CreateMaskTexture() end)
local group
sample(function()
    group = host:CreateAnimationGroup()
    return group
end)
if group then
    for _, kind in ipairs(SAMPLE_ANIMATIONS) do
        sample(function() return group:CreateAnimation(kind) end)
    end
end
sample(function() return CreateFont("RefactorProbeFont") end)

local function widgetMethods()
    local widgets = {}
    for _, object in ipairs(samples) do
        local ok, kind = pcall(object.GetObjectType, object)
        local meta = getmetatable(object)
        local index = meta and meta.__index
        if ok and type(kind) == "string" and type(index) == "table" and not widgets[kind] then
            local names = {}
            for name, value in pairs(index) do
                if type(name) == "string" and type(value) == "function" then names[#names + 1] = name end
            end
            widgets[kind] = join(names)
        end
    end
    return widgets
end

local function isWidget(value)
    return type(rawget(value, 0)) == "userdata"
end

-- The addon that last wrote owner[key], when one did. Blizzard's own values read as secure.
local issecurevariable = rawget(_G, "issecurevariable")
local function taintOf(owner, key)
    if not issecurevariable then return nil end
    local ok, secure, taint = pcall(issecurevariable, owner, key)
    if ok and secure == false then return tostring(taint) end
end

-- One "key<tab>type[<tab>addon]" line per string key, or nil and the size when the table is data.
local function fieldsOf(value)
    local lines = {}
    for key, field in pairs(value) do
        if type(key) == "string" and not key:find("[\t\n]") then
            if #lines >= FIELD_CAP then return nil, FIELD_CAP + 1 end
            local line = key .. "\t" .. type(field)
            local taint = taintOf(value, key)
            lines[#lines + 1] = taint and line .. "\t" .. taint or line
        end
    end
    return join(lines), #lines
end

local function newBudget()
    local started = debugprofilestop()
    return function()
        if debugprofilestop() - started > FRAME_BUDGET_MS then
            coroutine.yield()
            started = debugprofilestop()
        end
    end
end

local function walkGlobals(db)
    local spend = newBudget()
    -- Keys first, in one pass: other addons may define globals between frames, and next()
    -- over a table that grew mid-walk is undefined.
    local names = {}
    for key in pairs(_G) do
        if type(key) == "string" and not key:find("[\t\n]") then names[#names + 1] = key end
    end
    local byType, tainted, fields, oversized = {}, {}, {}, {}
    for _, name in ipairs(names) do
        local value = rawget(_G, name)
        local kind = type(value)
        byType[kind] = byType[kind] or {}
        byType[kind][#byType[kind] + 1] = name
        local taint = taintOf(_G, name)
        if taint then
            tainted[taint] = tainted[taint] or {}
            tainted[taint][#tainted[taint] + 1] = name
        end
        if kind == "table" and name ~= "_G" and not name:match("Mixin$") then
            local ok, listed, size = pcall(function()
                if isWidget(value) then return nil, 0 end
                return fieldsOf(value)
            end)
            if not ok then note("fields " .. name, listed)
            elseif listed and size > 0 then fields[name] = listed
            elseif size > FIELD_CAP then oversized[#oversized + 1] = name end
        end
        spend()
    end
    local enum = rawget(_G, "Enum")
    if type(enum) == "table" then
        for name, value in pairs(enum) do
            if type(name) == "string" and type(value) == "table" then
                local ok, listed = pcall(fieldsOf, value)
                if ok and listed then fields["Enum." .. name] = listed end
            end
        end
    end
    db.globals = {}
    for kind, list in pairs(byType) do db.globals[kind] = join(list) end
    db.tainted = {}
    for addon, list in pairs(tainted) do db.tainted[addon] = join(list) end
    db.fields = fields
    db.oversized = join(oversized)
    db.taintKnown = issecurevariable ~= nil
end

local function themeAtlases()
    local libStub = rawget(_G, "LibStub")
    local theme = libStub and libStub("LibRefactorTheme-1.0", true)
    if not theme then return nil end
    local names = {}
    for _, asset in pairs(theme.assets) do
        if asset.atlas then names[#names + 1] = asset.atlas end
    end
    for _, piece in pairs(theme.editModeLayout or {}) do
        for _, kit in pairs(theme.editModeKits or {}) do names[#names + 1] = piece.atlas:format(kit) end
    end
    local found = {}
    for _, name in ipairs(names) do found[name] = C_Texture.GetAtlasInfo(name) ~= nil end
    return found
end

local function console()
    local cvarType = Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or 0
    local cvars, commands = {}, {}
    for _, info in ipairs(ConsoleGetAllCommands()) do
        local list = info.commandType == cvarType and cvars or commands
        list[#list + 1] = info.command
    end
    return join(cvars), join(commands)
end

local function loadedAddOns()
    local names = {}
    for index = 1, C_AddOns.GetNumAddOns() do
        if C_AddOns.IsAddOnLoaded(index) then names[#names + 1] = (C_AddOns.GetAddOnInfo(index)) end
    end
    return join(names)
end

-- Loading the documentation defines globals of its own, so it runs after the walk. It also
-- taints Blizzard's /api for the rest of the session, which is acceptable in a dev tool.
local function documentation()
    local out = { systems = 0, functions = 0, secret = {} }
    out.loaded = C_AddOns.LoadAddOn("Blizzard_APIDocumentationGenerated") == true
    local doc = rawget(_G, "APIDocumentation")
    if type(doc) ~= "table" or type(doc.systems) ~= "table" then return out end
    local events = {}
    for _, system in ipairs(doc.systems) do
        out.systems = out.systems + 1
        for _, info in ipairs(system.Functions or {}) do
            out.functions = out.functions + 1
            for key in pairs(info) do
                if type(key) == "string" and key:match("^Secret") then
                    out.secret[key] = (out.secret[key] or 0) + 1
                end
            end
        end
        for _, info in ipairs(system.Events or {}) do
            if info.LiteralName then events[#events + 1] = info.LiteralName end
        end
    end
    out.events = join(events)
    return out
end

local function count(text)
    if not text or text == "" then return 0 end
    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    return lines
end

local function report(db)
    local globals, found, atlases = 0, 0, 0
    for _, list in pairs(db.globals or {}) do globals = globals + count(list) end
    for _, exists in pairs(db.atlases or {}) do
        atlases = atlases + 1
        if exists then found = found + 1 end
    end
    local tables = 0
    for _ in pairs(db.fields or {}) do tables = tables + 1 end
    print(("Refactor Probe: %d globals, %d tables, %d of %d atlases, %d cvars, documentation %s, %d errors. "
        .. "/reload writes the file."):format(globals, tables, found, atlases, count(db.cvars),
        db.documentation and db.documentation.loaded and "loaded" or "missing", #db.errors))
end

local function run()
    local version, build, date, interface = GetBuildInfo()
    errors = {}
    local db = {
        schema = 1, finished = false, errors = errors, probedAt = GetServerTime(),
        client = {
            version = version, build = build, date = date, interface = interface,
            project = rawget(_G, "WOW_PROJECT_ID"), locale = GetLocale(),
        },
    }
    _G.RefactorProbeDB = db
    local steps = {
        { "widgets", function() db.widgets = widgetMethods() end },
        { "globals", function() walkGlobals(db) end, yields = true },
        { "atlases", function() db.atlases = themeAtlases() end },
        { "console", function() db.cvars, db.commands = console() end },
        { "addons", function() db.addons = loadedAddOns() end },
        { "documentation", function() db.documentation = documentation() end },
    }
    for _, step in ipairs(steps) do
        if step.yields then
            -- pcall cannot be yielded across in Lua 5.1, so this step guards its own pieces.
            step[2]()
        else
            local ok, err = pcall(step[2])
            if not ok then note(step[1], err) end
        end
    end
    db.finished = true
    report(db)
end

local runner
local function resume()
    local ok, err = coroutine.resume(runner)
    if not ok then
        note("run", err)
        print("Refactor Probe stopped: " .. tostring(err))
    elseif coroutine.status(runner) ~= "dead" then
        C_Timer.After(0, resume)
    end
end

local function start()
    if runner and coroutine.status(runner) ~= "dead" then return end
    runner = coroutine.create(run)
    resume()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local db = rawget(_G, "RefactorProbeDB")
    local current = type(db) == "table" and db.finished and db.client and db.client.build == select(2, GetBuildInfo())
    if not current then start() end
end)

_G.SLASH_REFACTORPROBE1 = "/refactorprobe"
_G.SlashCmdList.REFACTORPROBE = start
