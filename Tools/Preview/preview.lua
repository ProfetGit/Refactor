-- Layout preview: loads the real TOC into a geometry-aware mock, drives it into a state
-- (window open on a section, a block expanded, a search typed, the loot feed full) and draws
-- each state as an HTML page. Run through Tools/Preview/run.py, which prepares the assets.
--   lua5.1 Tools/Preview/preview.lua <outdir> [scenario ...]
package.path = "Tools/Preview/?.lua;" .. package.path
local Runtime = require("Tests.mock.runtime")
local Env = require("env")
local Render = require("render")
local Geometry = require("geometry")

local outdir = arg[1] or "."
local wanted = {}
for index = 2, #arg do wanted[arg[index]] = true end

local function tocFiles()
    local files = {}
    for line in assert(io.open("Refactor.toc", "r")):lines() do
        local entry = line:gsub("\\", "/"):gsub("%s+$", "")
        if entry:match("%.lua$") and entry:sub(1, 1) ~= "#" then files[#files + 1] = entry end
    end
    return files
end

local function readAssets()
    local assets = {}
    local handle = io.open(outdir .. "/assets/index.txt", "r")
    if handle then
        for line in handle:lines() do
            local name, file = line:match("^(%S+)%s+(%S+)$")
            if name then assets[name] = file end
        end
        handle:close()
    end
    return assets
end

-- GameTooltip drawn as a frame of our own, so a hovered row's detail shows where it would.
local function installTooltip(env)
    local tip = env.CreateFrame("Frame", "GameTooltip", env.UIParent)
    tip:SetFrameStrata("TOOLTIP")
    tip:Hide()
    tip.bg = tip:CreateTexture(nil, "BACKGROUND")
    tip.bg:SetAllPoints()
    tip.bg:SetColorTexture(0.03, 0.03, 0.06, 0.94)
    tip.border = tip:CreateTexture(nil, "BORDER")
    tip.border:SetAllPoints()
    tip.border:SetAtlas("preview-tooltip-border")
    tip.lines, tip.pool = {}, {}
    function tip:SetOwner(owner, anchor, x, y) self.owner, self.anchor, self.ox, self.oy = owner, anchor, x, y self:ClearLines() end
    function tip:GetOwner() return self.owner end
    function tip:ClearLines()
        for _, line in ipairs(self.pool) do line:Hide() end
        self.lines = {}
    end
    function tip:AddLine(text, r, g, b, wrap)
        self.lines[#self.lines + 1] = { text = text, color = r and { r, g, b, 1 }, wrap = wrap }
    end
    function tip:AddDoubleLine(left, right, lr, lg, lb)
        self.lines[#self.lines + 1] = { text = tostring(left) .. "    " .. tostring(right), color = lr and { lr, lg, lb, 1 } }
    end
    function tip:SetText(text, r, g, b, _, wrap) self:ClearLines() self:AddLine(text, r, g, b, wrap) end
    function tip:SetHyperlink(link) self:ClearLines() self:AddLine(link) self:AddLine("Item tooltip", 1, 1, 1) end
    function tip:NumLines() return #self.lines end
    function tip:SetMinimumWidth() end
    function tip:Show()
        local widest, anyWrap = 0, false
        for index, line in ipairs(self.lines) do
            local size = index == 1 and 14 or 12
            if line.wrap then anyWrap = true else
                widest = math.max(widest, Geometry.measure(line.text or "", size))
            end
        end
        local width = math.max(widest, anyWrap and 260 or 0)
        local y = -10
        for index, line in ipairs(self.lines) do
            local fs = self.pool[index]
            if not fs then
                fs = self:CreateFontString(nil, "ARTWORK", index == 1 and "GameFontHighlightLarge" or "GameFontHighlight")
                self.pool[index] = fs
            end
            fs:SetFontObject(index == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
            fs:SetFont("Fonts\\FRIZQT__.TTF", index == 1 and 14 or 12, "")
            fs:SetText(line.text)
            fs:SetTextColor(unpack(line.color or (index == 1 and { 1, 1, 1, 1 } or { 1, 0.82, 0, 1 })))
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 10, y)
            fs:SetWidth(width)
            fs:Show()
            y = y - fs:GetStringHeight() - 2
        end
        self:SetSize(width + 20, -y + 8)
        local owner = self.owner or env.UIParent
        local anchor = self.anchor or "ANCHOR_RIGHT"
        if anchor == "ANCHOR_NONE" then self.shown = true return end
        self:ClearAllPoints()
        if anchor == "ANCHOR_LEFT" then self:SetPoint("BOTTOMRIGHT", owner, "TOPLEFT", self.ox or 0, self.oy or 0)
        elseif anchor == "ANCHOR_TOPLEFT" then self:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", self.ox or 0, self.oy or 0)
        elseif anchor == "ANCHOR_BOTTOMRIGHT" then self:SetPoint("TOPLEFT", owner, "BOTTOMRIGHT", self.ox or 0, self.oy or 0)
        else self:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", self.ox or 0, self.oy or 0) end
        self.shown = true
    end
    return tip
end

local function boot()
    local env = Runtime.new()
    Env.install(env, outdir .. "/atlases.lua")
    installTooltip(env)
    -- Read-only answers the window shows but no module needs: the TOC version, item icons.
    env.C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and "0.1.0" or nil end,
        IsAddOnLoaded = function() return false end }
    env.C_Item = { GetItemIconByID = function(id) return 130000 + id % 1000 end,
        GetItemQualityByID = function(id) return id % 5 end,
        GetItemQualityColor = function(quality)
            local colors = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 },
                { 0.64, 0.21, 0.93 } }
            return unpack(colors[quality] or colors[1])
        end }
    local R
    for _, path in ipairs(tocFiles()) do
        if path:match("^Libs/LibStub/") then
            local chunk = assert(loadfile(path))
            setfenv(chunk, env)
            chunk()
        else
            R = env:Load(path)
        end
    end
    env:Fire("PLAYER_LOGIN")
    -- Nothing gameplay is stubbed, so every module would read unavailable. The picture is of
    -- the layout, so each takes the state its switch implies; a few are left as they are to
    -- show the warning state.
    local function settle()
        for _, module in ipairs(R.modules) do
            if module.state == "unavailable" and not module.unavailableReasonKey then
                module.state = R.Settings:Get(module.id) and "enabled" or "disabled"
                module.missing = nil
            end
        end
    end
    settle()
    -- A switch flipped in a scenario reconciles again; keep the picture's states honest to it.
    local reconcile = R.Registry.ReconcileAll
    R.Registry.ReconcileAll = function(...) reconcile(...) settle() end
    return env, R
end

local function write(name, env, R, options)
    options = options or {}
    R.UI:Refresh()
    local body, truncated, count = Render.page(env, { assets = readAssets(), hovered = options.hovered })
    local css = assert(io.open("Tools/Preview/preview.css", "r")):read("*a")
    local html = table.concat({
        '<!doctype html><html><head><meta charset="utf-8"><title>', name, "</title><style>", css,
        "</style></head><body class=\"debug\">",
        '<div class="bar"><b>', name, "</b> &middot; ", count, " boxes &middot; ", truncated,
        " truncated text boxes (dashed red)</div>",
        '<div class="screen', options.snow and " snow" or "", '" style="width:', env.UIParent.width, "px;height:",
        env.UIParent.height, 'px">', body, "</div></body></html>",
    })
    local handle = assert(io.open(outdir .. "/" .. name .. ".html", "w"))
    handle:write(html)
    handle:close()
    io.write(string.format("%-40s %5d boxes %3d truncated\n", name, count, truncated))
end

local scenarios = {}
local order = {}
local function scenario(name, fn) scenarios[name] = fn order[#order + 1] = name end

scenario("window", function()
    local env, R = boot()
    R.UI:Toggle()
    write("window", env, R)
end)

scenario("window-hover", function()
    local env, R = boot()
    R.UI:Toggle()
    local row = R.UI.rows[3]
    env.hovered = row
    row.scripts.OnEnter(row)
    write("window-hover", env, R, { hovered = row })
end)

scenario("window-search", function()
    local env, R = boot()
    R.UI:Toggle()
    R.UI.search:SetText("sell")
    write("window-search", env, R)
end)

scenario("window-search-empty", function()
    local env, R = boot()
    R.UI:Toggle()
    R.UI.search:SetText("zzzz")
    write("window-search-empty", env, R)
end)

scenario("window-sections", function()
    local env, R = boot()
    R.UI:Toggle()
    for _, category in ipairs(R.UI.categories) do
        R.UI:SelectCategory(category)
        write("section-" .. category, env, R)
    end
end)

scenario("window-blocks", function()
    local env, R = boot()
    R.UI:Toggle()
    local ids = {}
    for id in pairs(R.UI.moduleSettings) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        R.UI:OpenModule(id)
        R.UI:CancelExpand()
        write("block-" .. id, env, R)
    end
end)

scenario("window-neversell", function()
    local env, R = boot()
    R.UI:Toggle()
    R.UI:OpenModule("vendor.autoSell")
    R.UI:CancelExpand()
    R.UI:AddNeverSell("6948, 2589, 2592, 4306, 14047, 7005, 6256, 5956, 2901, 3371, 2320, 2321, 4470, 159")
    write("window-neversell", env, R)
end)

scenario("window-panels", function()
    local env, R = boot()
    R.UI:Toggle()
    for _, key in ipairs({ "Profiles", "Conflicts", "Diagnostics", "Changelog" }) do
        R.UI:SelectCategory(key)
        write("panel-" .. key, env, R)
    end
end)

scenario("window-profiles-filled", function()
    local env, R = boot()
    R.UI:Toggle()
    local values = {}
    for index, module in ipairs(R.modules) do values[module.id] = index % 3 ~= 0 end
    R.Settings:CreateProfile("Levelling alts", values)
    R.Settings:CreateProfile("Gatherer", {})
    R.UI:AssignProfile("Levelling alts")
    R.UI:SelectCategory("Profiles")
    write("panel-Profiles-filled", env, R)
    R.UI:SelectCategory("Quest")
    write("window-profile-scope", env, R)
end)

-- The feed and the HUD through their own test commands, so the rows are the real path's.
local function gameplay(env)
    env.GetMoney = function() return 1234567 end
    env.C_CurrencyInfo = {
        GetCurrencyInfo = function() return { name = "Honor", quantity = 10, iconFileID = 1455894 } end,
        GetCoinTextureString = function(amount) return tostring(amount) end,
    }
    env.C_Item.GetItemInfo = function(id) return "Item " .. tostring(id), "item:" .. tostring(id), 2 end
    env.C_Item.GetItemNameByID = function(id) return "Item " .. tostring(id) end
    env.GetItemInfo = env.C_Item.GetItemInfo
    env.MenuUtil = { CreateContextMenu = function() end }
end

local function reportErrors(name, R)
    for _, entry in ipairs(R.errors or {}) do
        io.stderr:write(name .. ": " .. tostring(entry.message or entry[1] or entry) .. "\n")
    end
end

scenario("lootfeed", function()
    local env, R = boot()
    gameplay(env)
    R.Settings:SetAccount("toasts.loot", true)
    env.SlashCmdList.REFACTOR("loottest")
    -- No animation plays here, so the upgrade prompt's fade in is put where the client ends it.
    R.moduleByID["toasts.loot"].prompt.fader:Snap(1)
    reportErrors("lootfeed", R)
    write("lootfeed", env, R)
    write("lootfeed-snow", env, R, { snow = true })
end)

scenario("farmhud", function()
    local env, R = boot()
    gameplay(env)
    R.Settings:SetAccount("loot.farmSession", true)
    env.SlashCmdList.REFACTOR("farmtest")
    reportErrors("farmhud", R)
    write("farmhud", env, R)
    R.Settings:SetOption("farmExpand", true)
    write("farmhud-expanded", env, R)
    write("farmhud-expanded-snow", env, R, { snow = true })
    local farm = R.moduleByID["loot.farmSession"]
    R.UI:ShowSessionSummary(function() return farm:BuildReport() end)
    write("farm-summary", env, R)
    R.UI.sessionSummary.copy:Click()
    write("farm-copy", env, R)
end)

-- Blizzard's Settings window hosts the canvas; here it sits on a plain dark sheet that size.
scenario("settings-canvas", function()
    local env, R = boot()
    local panel = R.UI.settingsPanel
    local sheet = env.CreateFrame("Frame", nil, env.UIParent)
    sheet:SetSize(650, 560)
    sheet:SetPoint("CENTER")
    local ground = sheet:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints()
    ground:SetColorTexture(0.06, 0.06, 0.07, 0.95)
    panel:SetParent(sheet)
    panel:SetAllPoints(sheet)
    write("settings-canvas", env, R)
end)

scenario("window-account", function()
    local env, R = boot()
    R.UI:Toggle()
    R.UI.mode = "account"
    R.Settings:SetScope("account")
    write("window-account", env, R)
end)

local run = {}
for name in pairs(wanted) do run[#run + 1] = name end
if #run == 0 then run = order end
for _, name in ipairs(run) do
    local fn = scenarios[name]
    if not fn then error("unknown scenario " .. name) end
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then io.stderr:write("scenario " .. name .. " failed: " .. tostring(err) .. "\n") end
end
local unknown = {}
for key, count in pairs(Geometry.unknown) do unknown[#unknown + 1] = key .. "=" .. count end
table.sort(unknown)
io.write("unmodelled methods: " .. table.concat(unknown, " ") .. "\n")
