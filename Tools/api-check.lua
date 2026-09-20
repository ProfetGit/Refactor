local json, lfs, luacheck = require("dkjson"), require("lfs"), require("luacheck")
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end
local index = assert(json.decode(read("Data/api-retail.json")))
assert(index.flavor == "retail" and index.interface == 120100, "wrong source index target")
local failures, checked = {}, 0
local function fail(path, message) failures[#failures + 1] = path .. ": " .. message end
local function verify(path, text, requires)
    local report = luacheck.check_strings({ text }, { std = "lua51", globals = { "_G" } })[1]
    for _, warning in ipairs(report) do
        if warning.code == "113" or warning.code == "143" then
            local name = warning.name
            local declared = requires[name]
            for symbol in pairs(requires) do
                if symbol:match("^([%w_]+)%.") == name then declared = true end
            end
            if not declared then fail(path, "undeclared API global " .. name) end
        elseif warning.code == "111" or warning.code == "112" then
            fail(path, "module writes global " .. warning.name)
        end
    end
    -- Namespace roots alone cannot authorize arbitrary C_* fields.
    local code = text:gsub("%-%-[^\n]*", "")
    for symbol in code:gmatch("(C_[%w_]+%.[%w_]+)") do
        if not requires[symbol] then fail(path, "undeclared API field " .. symbol) end
    end
end
local function declare(path, requires, symbol)
    requires[symbol] = true
    checked = checked + 1
    if not index.symbols[symbol] then fail(path, "no source evidence for " .. symbol) end
end

-- Core files that reach the client API declare it in the same header comment modules use.
local function checkHeader(path)
    local text = read(path)
    local declaration = text:match("%-%-%- Requires:(.-)\n%-%-%- Events:")
    if not declaration then fail(path, "requires header missing"); return end
    local requires = {}
    for symbol in declaration:gmatch("[%w_][%w_%.]*") do
        if symbol ~= "none" then declare(path, requires, symbol) end
    end
    verify(path, text, requires)
end

local function check(path)
    local text = read(path)
    local declaration = text:match("requires%s*=%s*(%b{})")
    if not declaration then
        -- A module can be split across files; the support half declares in its header.
        if text:match("%-%-%- Requires:") then return checkHeader(path) end
        fail(path, "requires declaration missing")
        return
    end
    local requires = {}
    for symbol in declaration:gmatch('["\']([%w_%.]+)["\']') do declare(path, requires, symbol) end
    verify(path, text, requires)
end

local function walk(path)
    for entry in lfs.dir(path) do
        if entry ~= "." and entry ~= ".." then
            local child = path .. "/" .. entry
            if lfs.attributes(child, "mode") == "directory" then walk(child)
            elseif child:match("%.lua$") then check(child) end
        end
    end
end

walk("Modules")
walk("Modules_LoD")
for _, path in ipairs({
    "Core/Safety.lua", "Core/Commands.lua", "Core/Bootstrap.lua", "Core/Bench.lua", "Core/Conditions.lua",
    "Integrations/Neighbours.lua", "Integrations/Questie.lua", "Integrations/Plater.lua",
    "Integrations/TSM.lua", "Integrations/Auctionator.lua", "Integrations/Prices.lua",
    "Integrations/FrameOwners.lua",
}) do checkHeader(path) end
local toc = read("Refactor.toc")
assert(tonumber(toc:match("## Interface:%s*(%d+)")) == index.interface, "TOC/index interface mismatch")
if #failures > 0 then error(table.concat(failures, "\n"), 0) end
print(string.format("API check: %d dependencies match Retail %s (%s).", checked, index.version, index.build))
print("NOTE: source evidence only. Behaviour still needs the client.")
