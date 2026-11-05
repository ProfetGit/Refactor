--- Turn the saved variables file Tools/Probe writes into Data/api-<flavor>.json, the runtime
--- index `make api-check` reads beside the Retail source index (PRD 10.8).
---
---   lua5.1 Tools/probe-to-json.lua <path to RefactorProbe.lua> <flavor>
---
--- Globals and fields an addon tainted are left out of symbols. They belong to that addon, not
--- to the client, and an index listing LibStub would vouch for a library as client API. The
--- globals are kept apart in addonGlobals, because an addon that overwrites a client global
--- (Refactor's MERCHANT_ITEMS_PER_PAGE) taints it too, and the dump alone cannot tell the two apart.
local Probe = {}

-- dkjson's convention, so a decoded index and a converted one mark arrays the same way.
local ARRAY = { __jsontype = "array" }

local function lines(text)
    local list = {}
    if type(text) ~= "string" or text == "" then return list end
    for line in (text .. "\n"):gmatch("(.-)\n") do list[#list + 1] = line end
    return list
end

local function array(list)
    table.sort(list)
    return setmetatable(list, ARRAY)
end

function Probe.load(text)
    local chunk = assert(loadstring(text, "=probe"))
    local env = {}
    setfenv(chunk, env)
    chunk()
    return assert(env.RefactorProbeDB, "no RefactorProbeDB in the file")
end

-- One "key<tab>type" line per field, a third column naming the addon when one tainted it.
local function parseFields(text)
    local fields, hasFunction = {}, false
    for _, line in ipairs(lines(text)) do
        local key, kind, taint = line:match("^([^\t]*)\t([^\t]+)\t?(.*)$")
        if key and taint == "" then
            fields[#fields + 1] = { key = key, kind = kind }
            if kind == "function" then hasFunction = true end
        end
    end
    return fields, hasFunction
end

-- A table's fields are API when it is a C_ namespace, Enum or one of its enums, or holds at
-- least one function. The rest are data (StaticPopupDialogs, ChatTypeInfo) and would only
-- bury the namespaces in the index.
local function isNamespace(owner, hasFunction)
    return owner:match("^C_") ~= nil or owner == "Enum" or owner:match("^Enum%.") ~= nil or hasFunction
end

function Probe.convert(db, flavor)
    assert(type(flavor) == "string" and flavor:match("^%l+$"), "flavor must be a lowercase word")
    assert(db.schema == 1, "unknown probe schema")
    assert(db.finished, "the probe did not finish: " .. table.concat(db.errors or {}, "; "))
    local client = db.client
    local excluded, excludedCount = {}, 0
    for addon, names in pairs(db.tainted or {}) do
        for _, name in ipairs(lines(names)) do
            excluded[name] = addon
            excludedCount = excludedCount + 1
        end
    end
    local symbols = {}
    for kind, names in pairs(db.globals) do
        for _, name in ipairs(lines(names)) do
            if not excluded[name] then symbols[name] = kind end
        end
    end
    for owner, text in pairs(db.fields or {}) do
        local fields, hasFunction = parseFields(text)
        if not excluded[owner:match("^[^.]+")] and isNamespace(owner, hasFunction) then
            for _, field in ipairs(fields) do symbols[owner .. "." .. field.key] = field.kind end
        end
    end
    local widgets = {}
    for kind, methods in pairs(db.widgets or {}) do widgets[kind] = array(lines(methods)) end
    local documentation = db.documentation or {}
    return {
        schema = 1, flavor = flavor, provenance = "client-probe", runtimeVerified = true,
        version = client.version, build = client.build, interface = client.interface,
        project = client.project, locale = client.locale,
        probedAt = os.date("!%Y-%m-%d", db.probedAt),
        taintFiltered = db.taintKnown == true, excludedGlobals = excludedCount,
        symbols = symbols, addonGlobals = excluded, widgetMethods = widgets, atlases = db.atlases or {},
        cvars = array(lines(db.cvars)), commands = array(lines(db.commands)),
        events = array(lines(documentation.events)), addons = array(lines(db.addons)),
        oversizedTables = array(lines(db.oversized)), errors = array(db.errors or {}),
        documentation = {
            loaded = documentation.loaded == true, systems = documentation.systems or 0,
            functions = documentation.functions or 0, secret = documentation.secret or {},
        },
    }
end

-- Sorted keys and two-space indent, the layout Tools/source-index.py writes, so one build's
-- index diffs line by line against the next.
local function quote(text)
    return '"' .. text:gsub('[%c"\\]', function(char)
        local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
        return named[char] or string.format("\\u%04x", char:byte())
    end) .. '"'
end

local function encode(value, indent, out)
    local kind = type(value)
    if kind == "string" then
        out[#out + 1] = quote(value)
    elseif kind == "number" then
        out[#out + 1] = value == math.floor(value) and string.format("%d", value) or string.format("%.14g", value)
    elseif kind == "boolean" then
        out[#out + 1] = tostring(value)
    elseif kind == "nil" then
        out[#out + 1] = "null"
    else
        local inner = indent .. "  "
        if getmetatable(value) == ARRAY then
            if #value == 0 then out[#out + 1] = "[]"; return end
            out[#out + 1] = "[\n"
            for index, item in ipairs(value) do
                out[#out + 1] = inner
                encode(item, inner, out)
                out[#out + 1] = index < #value and ",\n" or "\n"
            end
            out[#out + 1] = indent .. "]"
        else
            local keys = {}
            for key in pairs(value) do keys[#keys + 1] = tostring(key) end
            if #keys == 0 then out[#out + 1] = "{}"; return end
            table.sort(keys)
            out[#out + 1] = "{\n"
            for index, key in ipairs(keys) do
                out[#out + 1] = inner .. quote(key) .. ": "
                encode(value[key], inner, out)
                out[#out + 1] = index < #keys and ",\n" or "\n"
            end
            out[#out + 1] = indent .. "}"
        end
    end
end

function Probe.render(index)
    local out = {}
    encode(index, "", out)
    return table.concat(out) .. "\n"
end

local function main(path, flavor)
    assert(path and flavor, "usage: lua5.1 Tools/probe-to-json.lua <RefactorProbe.lua> <flavor>")
    local file = assert(io.open(path, "r"))
    local db = Probe.load(file:read("*a"))
    file:close()
    local index = Probe.convert(db, flavor)
    local target = "Data/api-" .. flavor .. ".json"
    local output = assert(io.open(target, "w"))
    output:write(Probe.render(index))
    output:close()
    local count = 0
    for _ in pairs(index.symbols) do count = count + 1 end
    print(string.format("Wrote %s: %s %s (%s), %d symbols, %d tainted globals left out.",
        target, flavor, index.version, index.build, count, index.excludedGlobals))
end

-- `lua5.1 Tools/probe-to-json.lua file flavor` writes the index. require("Tools.probe-to-json")
-- hands the functions to the spec and writes nothing.
local first = ...
if first ~= "Tools.probe-to-json" then
    main(...)
end
return Probe
