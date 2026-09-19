local lfs = require("lfs")
local failures = {}
local DEFINITION_FIELDS = { "id", "category", "requires", "tier", "risk" }
local function fail(path, message) failures[#failures + 1] = path .. ": " .. message end
local function check(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    local chunk, err = loadstring(text, "@" .. path)
    if not chunk then fail(path, err) end
    if path:match("^Tests/") or path:match("^Tools/") then return end
    local code = text:gsub("%-%-[^\n]*", "")
    if code:find("SecureActionButtonTemplate", 1, true) then fail(path, "secure action template forbidden") end
    if code:match(":SetAttribute%s*%(") then fail(path, "attribute mutation forbidden") end
    if path ~= "Core/Namespace.lua" then
        -- Line scoped: reading _G, and comparisons with ==, are not global writes.
        for line in code:gmatch("[^\n]+") do
            if line:match("_G%s*%.%s*[%w_]+%s*=[^=]") or line:match("_G%s*%[[^%]]*%]%s*=[^=]") then
                fail(path, "global writes belong in Namespace.lua")
            end
        end
    end
    if code:match('SetScript%s*%(%s*["\']OnUpdate["\']')
        and not code:match('SetScript%s*%(%s*["\']OnUpdate["\']%s*,%s*nil%s*%)') then
        fail(path, "OnUpdate must have a matching clear")
    end
    if text:find("-- @hot", 1, true) then
        -- Storage and constant tables declared once at file scope are not per-call
        -- allocation. Everything else in a hot file is, including any concatenation.
        local body, inConstant = {}, false
        for line in code:gmatch("[^\n]*") do
            if inConstant then
                if line:match("^}") then inConstant = false end
            elseif line:match("^local [%w_]+ = {$") then
                inConstant = true
            elseif not line:match("^local [%w_]+ = {}%s*$") and not line:match("^[%w_][%w_%.]* = {}%s*$") then
                body[#body + 1] = line
            end
        end
        -- A vararg is not concatenation.
        local runtime = table.concat(body, "\n"):gsub("%.%.%.", "")
        if runtime:find("{", 1, true) or runtime:find("..", 1, true) then
            fail(path, "allocation in hot file")
        end
    end
    if path:match("^Modules/") then
        if not text:match("^%-%-%- @module ") then fail(path, "missing module contract header") end
        if not text:match("function .-:OnDisable%s*%(") then fail(path, "missing lifecycle cleanup") end
        if code:match("R%.moduleByID") or code:match("R%.modules") then fail(path, "cross-module access") end
        -- Module state lives on the definition table the registry reads, so reusing one of its
        -- identity fields for runtime state breaks settings lookup for that module. Checked on
        -- the left of each assignment, comparisons stripped, so a multiple assignment counts.
        for line in code:gmatch("[^\n]+") do
            local lhs = line:gsub("[~<>=]=", ""):match("^([^=]*)=")
            if lhs then
                for _, field in ipairs(DEFINITION_FIELDS) do
                    if (lhs .. " "):match("self%." .. field .. "[^%w_]") then
                        fail(path, "module state must not overwrite the definition's " .. field)
                    end
                end
            end
        end
        if code:find("CreateFrame", 1, true) then
            fail(path, "module frames must use a theme builder at enable, never game events")
        end
        if code:match("SetTexture%s*%(") or code:match("SetAtlas%s*%(") or code:match("SetVertexColor%s*%(") then
            fail(path, "module visuals must go through theme")
        end
    end
    if path:match("^UI/") and (code:find("Interface\\", 1, true) or code:find("UI-Panel-Button", 1, true)) then
        fail(path, "texture paths belong in theme asset manifest")
    end
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
for _, root in ipairs({"Core", "Modules", "Modules_LoD", "Integrations", "UI", "Locales", "Media",
    "Libs/LibRefactorTheme-1.0", "Libs/LibRefactorPrice-1.0"}) do walk(root) end

-- A file that is not in the TOC does not exist at runtime, which is invisible to every other check.
local listed, toc = {}, assert(io.open("Refactor.toc", "r"))
for line in toc:lines() do
    local entry = line:gsub("\\", "/"):gsub("%s+$", "")
    if entry:match("%.lua$") and entry:sub(1, 1) ~= "#" then
        listed[entry] = true
        if not lfs.attributes(entry) then fail("Refactor.toc", "lists a missing file: " .. entry) end
    end
end
toc:close()
local function requireListed(path)
    for entry in lfs.dir(path) do
        if entry ~= "." and entry ~= ".." then
            local child = path .. "/" .. entry
            if lfs.attributes(child, "mode") == "directory" then requireListed(child)
            elseif child:match("%.lua$") and not listed[child] then fail(child, "not loaded by Refactor.toc") end
        end
    end
end
for _, root in ipairs({"Core", "Modules", "Modules_LoD", "Integrations", "UI", "Locales", "Media",
    "Libs"}) do requireListed(root) end
if #failures > 0 then error(table.concat(failures, "\n"), 0) end
print("Project rules: passed (static checks complement, not replace, lifecycle and in-game tests).")
