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

-- The bag upgrade's longest prompt line, offered straight to the prompt it drives.
scenario("bagupgrade", function()
    local env, R = boot()
    local L = R.L
    local prompt = R.UI:CreateUpgradePrompt({})
    prompt.titleKey, prompt.titleMoreKey = "BAG_UPGRADE_TITLE", "BAG_UPGRADE_TITLE_MORE"
    prompt.canEquip = function() return true end
    prompt:Offer({
        link = "item:14155", icon = 133652, itemName = "Mooncloth Bag", r = 0.12, g = 1, b = 0,
        badge = { text = string.format(L.BAG_UPGRADE_GAIN_BINDS, 10), token = "TEXT_WARNING" },
        replacesName = string.format(L.BAG_UPGRADE_BAG, "Cenarion Herb Bag", 12),
    })
    prompt:Offer({
        link = "item:4245", icon = 133639, itemName = "Small Silk Pack", r = 1, g = 1, b = 1,
        badge = { text = string.format(L.BAG_UPGRADE_FILLS, 12), token = "TEXT_ACTIVE" },
    })
    prompt.fader:Snap(1)
    reportErrors("bagupgrade", R)
    write("bagupgrade", env, R)
    prompt:Decide(false)
    prompt.fader:Snap(1)
    write("bagupgrade-empty-slot", env, R)
end)

-- The send-to-alts panel beside a stand-in mail window, driven by a fake owner: the layout only.
scenario("mailalts", function()
    local env, R = boot()
    env.ATTACHMENTS_MAX_SEND = 12
    local mail = env.CreateFrame("Frame", "MailFrame", env.UIParent)
    mail:SetSize(338, 424)
    mail:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 40, -120)
    mail:Show()
    R.Settings:SetOption("mailBankAlt", "Vaultkeeper")
    local function entries(count, start)
        local list = {}
        for index = 1, count do
            local id = start + index
            list[index] = { bag = 0, slot = index, itemID = id, link = "|Hitem:" .. id .. "|h[Item " .. id .. "]|h",
                icon = 130000 + id % 1000, count = index % 3 == 0 and 1 or 20, quality = 1 + index % 4,
                reason = "herb", kind = "herb" }
        end
        return list
    end
    local groups = {
        { key = "vaultkeeper", recipient = "Vaultkeeper", entries = entries(34, 2400) },
        { key = "brewmistress", recipient = "Brewmistress", entries = entries(5, 2600) },
    }
    local owner = { selected = "vaultkeeper", groups = groups }
    function owner:Groups() return self.groups end
    function owner:SelectedGroup()
        for _, group in ipairs(self.groups) do
            if group.key == self.selected then return group end
        end
    end
    function owner:Characters() return { "Brewmistress", "Vaultkeeper" } end
    function owner:Recipients() return { "Vaultkeeper", "Brewmistress" } end
    function owner:Summary()
        local group = self:SelectedGroup()
        return { left = group and #group.entries or 0, mails = 3, attached = 4, postage = 150, value = 1234567,
            gold = self.gold }
    end
    owner.gold = 4520000
    local panel = R.UI:CreateMailAltsPanel(owner)
    panel:Render()
    reportErrors("mailalts", R)
    write("mailalts", env, R)
    owner.gold = nil
    owner.groups = {}
    panel:Render()
    write("mailalts-nothing", env, R)
    R.Settings:SetOption("mailBankAlt", "")
    panel:Render()
    write("mailalts-pick", env, R)
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

-- Quest progress on stand-in nameplates, one per case of group progress. Plates are drawn
-- here (Blizzard's are not on disk); the indicator and the group row are the module's own,
-- placed by its own Apply from entries built the way a resolve writes them.
scenario("nameplates-group", function()
    local env, R = boot()
    env.C_NamePlate = { GetNamePlateForUnit = function() return nil end }
    env.UnitGUID, env.issecretvalue = function() return nil end, function() return false end
    env.IsInGroup, env.IsInRaid = function() return false end, function() return false end
    env.UnitExists, env.UnitIsUnit = function() return false end, function() return false end
    env.UnitName = function() return "Me" end
    local classes = { MAGE = { 0.25, 0.78, 0.92 }, PRIEST = { 1, 1, 1 }, WARLOCK = { 0.53, 0.53, 0.93 },
        DRUID = { 1, 0.49, 0.04 } }
    env.C_ClassColor = { GetClassColor = function(class)
        local rgb = classes[class]
        return rgb and { GetRGB = function() return rgb[1], rgb[2], rgb[3] end } or nil
    end }
    local module = R.moduleByID["nameplates.questProgress"]
    module:OnEnable()
    R.Settings:SetOption("nameplateShowGroup", true)
    local cases = {
        { label = "Solo, 5/8", own = { 5, 8 } },
        { label = "Mage behind, priest level", own = { 3, 8 },
            group = { { "MAGE", 1, 8 }, { "PRIEST", 3, 8 } } },
        { label = "You are done, warlock is not", own = { 8, 8, true }, group = { { "WARLOCK", 4, 8 } } },
        { label = "Only the druid has it", group = { { "DRUID", 2, 6 } } },
        { label = "Raid of seven", own = { 1, 12 }, group = { { "MAGE", 0, 12 }, { "PRIEST", 1, 12 },
            { "WARLOCK", 4, 12 }, { "DRUID", 1, 12 }, { "MAGE", 0, 12 }, { "PRIEST", 2, 12 } } },
    }
    for index, case in ipairs(cases) do
        local plate = env.CreateFrame("Frame", nil, env.UIParent)
        plate:SetSize(150, 12)
        plate:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 120, -60 - (index - 1) * 70)
        local unitFrame = env.CreateFrame("Frame", nil, plate)
        unitFrame:SetAllPoints(plate)
        local container = env.CreateFrame("Frame", nil, unitFrame)
        container:SetAllPoints(unitFrame)
        local bar = container:CreateTexture(nil, "ARTWORK")
        bar:SetAllPoints(container)
        bar:SetColorTexture(0.62, 0.12, 0.10, 1)
        container.healthBar = { bgTexture = bar }
        unitFrame.HealthBarsContainer = container
        -- The preview answers any unknown field with a method; a plate has neither of these.
        unitFrame.LevelFrame, unitFrame.PlayerLevelDiffFrame = false, false
        plate.UnitFrame = unitFrame
        local name = R.Theme:Text(plate, "Kobold Laborer", "small", "TEXT_HIGHLIGHT")
        name:SetPoint("BOTTOM", plate, "TOP", 0, 3)
        local note = R.Theme:Text(env.UIParent, case.label, "small", "TEXT_MUTED")
        note:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 420, -58 - (index - 1) * 70)
        local entry = { groupCount = 0, groupMember = {}, groupClass = {}, groupFulfilled = {},
            groupRequired = {}, groupRatio = {}, ok = false, fulfilled = 0, required = 0, plus = 0,
            kind = "kill", complete = false, lastOne = false }
        if case.own then
            entry.ok, entry.fulfilled, entry.required = true, case.own[1], case.own[2]
            entry.complete = case.own[3] == true
            entry.lastOne = not entry.complete and case.own[2] - case.own[1] == 1
        end
        for slot, member in ipairs(case.group or {}) do
            entry.groupCount = slot
            entry.groupMember[slot], entry.groupClass[slot] = slot, member[1]
            entry.groupFulfilled[slot], entry.groupRequired[slot] = member[2], member[3]
        end
        local unit = "nameplate" .. index
        module.guids[unit] = false
        module:Apply(unit, plate, entry)
        case.unit, case.plate, case.entry, case.y = unit, plate, entry, -60 - (index - 1) * 70
    end
    reportErrors("nameplates-group", R)
    write("nameplates-group", env, R)
    R.Settings:SetOption("nameplateSide", "LEFT")
    for _, case in ipairs(cases) do
        case.plate:ClearAllPoints()
        case.plate:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 200, case.y)
        module:Apply(case.unit, case.plate, case.entry)
    end
    write("nameplates-group-left", env, R)
end)

-- The spellbook is Blizzard's and not on disk: a stand-in window with the two children the
-- module looks for, and a mage's spell list answered through the same calls the client has.
local function allSpellsWorld(withTrainer)
    local env, R = boot()
    local window = env.CreateFrame("Frame", nil, env.UIParent)
    window:SetSize(540, 720)
    window:SetPoint("LEFT", env.UIParent, "LEFT", 90, 0)
    local book = env.CreateFrame("Frame", nil, window)
    book:SetAllPoints(window)
    book.SearchBox = env.CreateFrame("Frame", nil, book)
    book.SearchBox:SetSize(180, 22)
    book.SearchBox:SetPoint("TOPRIGHT", book, "TOPRIGHT", -24, -34)
    window.SpellBookFrame = book
    local face = window:CreateTexture(nil, "BACKGROUND")
    face:SetAllPoints()
    face:SetColorTexture(0.12, 0.09, 0.07, 1)
    env.PlayerSpellsFrame = window
    window:Show()
    book:Show()
    local lines = {
        { "General", { { 6603, "Attack", 1, true }, { 5019, "Shoot", 1, true } } },
        { "Arcane", { { 1459, "Arcane Intellect", 1, true, "Rank 1" }, { 5143, "Arcane Missiles", 8, false, "Rank 1" },
            { 118, "Polymorph", 8, false, "Rank 1" }, { 1449, "Arcane Explosion", 14, false, "Rank 1" },
            { 1953, "Blink", 20, false } } },
        { "Fire", { { 133, "Fireball", 1, true, "Rank 1" }, { 143, "Fireball", 6, false, "Rank 2" },
            { 2136, "Fire Blast", 6, false, "Rank 1" }, { 2120, "Flamestrike", 16, false, "Rank 1" },
            { 11366, "Pyroblast", 20, false, "Rank 1" } } },
        { "Frost", { { 168, "Frost Armor", 1, true, "Rank 1" }, { 116, "Frostbolt", 4, false, "Rank 1" },
            { 122, "Frost Nova", 10, false, "Rank 1" }, { 120, "Cone of Cold", 26, false } } },
    }
    local info, byID, items, skill = {}, {}, {}, {}
    local offset = 0
    for index, line in ipairs(lines) do
        skill[index] = { name = line[1], itemIndexOffset = offset, numSpellBookItems = #line[2] }
        for _, spell in ipairs(line[2]) do
            offset = offset + 1
            byID[spell[1]] = { name = spell[2], level = spell[3], known = spell[4], sub = spell[5] or "", line = line[1] }
            items[offset] = { actionID = spell[1], itemType = spell[4] and 1 or 2, name = spell[2] }
            info[offset] = spell[3]
        end
    end
    env.Enum = { TrainerType = { General = 0, Tradeskills = 1, Pet = 2 },
        SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
        SpellBookSpellBank = { Player = 0, Pet = 1 } }
    env.UnitClass = function() return "Mage", "MAGE", 8 end
    env.UnitLevel = function() return 6 end
    env.C_Spell = { GetSpellTexture = function(id) return 130000 + id % 700 end,
        GetSpellName = function(id) return byID[id] and byID[id].name end,
        GetSpellSubtext = function(id) return byID[id] and byID[id].sub or "" end }
    env.C_SpellBook = { GetNumSpellBookSkillLines = function() return #skill end,
        GetSpellBookSkillLineInfo = function(index) return skill[index] end,
        GetSpellBookItemInfo = function(slot) return items[slot] end,
        GetSpellBookItemLevelLearned = function(slot) return withTrainer and info[slot] or 0 end,
        IsSpellKnown = function(id) return byID[id] and byID[id].known or false end }
    env.C_AddOns.IsAddOnLoaded = function() return true end
    env.GameTooltip.SetSpellByID = function(tip, id)
        local spell = byID[id]
        tip:SetText(spell.name)
        tip:AddLine(spell.sub ~= "" and spell.sub or "Spell", 1, 1, 1)
        tip:AddLine("Requires level " .. spell.level)
    end
    local stubbed = { "IsTradeskillTrainer", "GetTrainerServiceTypeFilter", "SetTrainerServiceTypeFilter",
        "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceSkillLine",
        "GetTrainerServiceItemLink" }
    for _, name in ipairs(stubbed) do env[name] = function() return nil end end
    env.C_TooltipInfo = { GetTrainerService = function() return nil end }
    env.C_Trainer = { GetTrainerType = function() return 0 end }
    local recorded = {}
    if withTrainer then
        for id, spell in pairs(byID) do recorded[id] = { level = spell.level, line = spell.line } end
    end
    R.Settings.account.classSpells = { MAGE = recorded }
    R.Settings:SetAccount("interface.allSpells", true)
    R.Registry:ReconcileAll()
    local module = R.moduleByID["interface.allSpells"]
    reportErrors("allspells", R)
    if module.state ~= "enabled" then
        io.stderr:write("allspells: module " .. tostring(module.state) .. " " .. table.concat(module.missing or {}, ",")
            .. " " .. tostring(module.failure) .. "\n")
    end
    return env, R, module
end

scenario("allspells", function()
    local env, R, module = allSpellsWorld(true)
    module.ui.panel:Show()
    module.ui.panel.scripts.OnShow(module.ui.panel)
    write("allspells", env, R)
    module:OnTab("toLearn")
    write("allspells-tolearn", env, R)
    module:OnTab("all")
    module.ui.search:SetText("fire")
    module.ui.search.scripts.OnTextChanged(module.ui.search)
    write("allspells-search", env, R)
    module.ui.search:SetText("")
    module.ui.search.scripts.OnTextChanged(module.ui.search)
    local row = module.ui.pool[7]
    row.scripts.OnEnter(row)
    write("allspells-hover", env, R, { hovered = row })
    reportErrors("allspells", R)
end)

scenario("allspells-empty", function()
    local env, R, module = allSpellsWorld(false)
    module.ui.panel:Show()
    module.ui.panel.scripts.OnShow(module.ui.panel)
    write("allspells-empty", env, R)
    reportErrors("allspells-empty", R)
end)

-- Tailoring at 58 with thresholds from the generated table: Woolen Cloth while it is orange, then a recipe with
-- a long name (Linen Boots's thresholds) to 100, then a gap the unlearned recipes would fill.
local function plannerWorld(skill)
    local env, R = boot()
    local window = env.CreateFrame("Frame", nil, env.UIParent)
    window:SetSize(942, 658)
    window:SetPoint("LEFT", env.UIParent, "LEFT", 60, 0)
    local face = window:CreateTexture(nil, "BACKGROUND")
    face:SetAllPoints()
    face:SetColorTexture(0.12, 0.09, 0.07, 1)
    window:Show()
    env.ProfessionsFrame = window
    -- Forever's profession tabs, which stick out of the window's right edge.
    for index = 1, 4 do
        local tab = env.CreateFrame("Frame", nil, window)
        tab:SetSize(46, 50)
        tab:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, -40 - (index - 1) * 56)
        local art = tab:CreateTexture(nil, "ARTWORK")
        art:SetAllPoints()
        art:SetColorTexture(0.3, 0.22, 0.12, 1)
        tab:Show()
    end
    local items = { [2589] = "Linen Cloth", [2592] = "Wool Cloth", [2320] = "Coarse Thread",
        [2996] = "Bolt of Linen Cloth", [2997] = "Bolt of Woolen Cloth" }
    local bags = { [2589] = 24, [2592] = 12, [2320] = 5 }
    local recipes = {
        [2963] = { "Bolt of Linen Cloth", true, { { 2589, 2 } } },
        [2385] = { "Brown Linen Vest", true, { { 2996, 1 }, { 2320, 1 } } },
        [3915] = { "Brown Linen Shirt", true, { { 2996, 2 } } },
        [2386] = { "Enchant Chest - Inferior Stamina", true, { { 2996, 3 }, { 2320, 1 } } },
        [2964] = { "Bolt of Woolen Cloth", true, { { 2592, 3 } } },
        [3758] = { "Green Woolen Bag", false, { { 2997, 4 } } },
        [2403] = { "Gray Woolen Robe", false, { { 2997, 3 } } },
        [3844] = { "Heavy Woolen Cloak", false, { { 2997, 3 } } },
    }
    local data = R.ProfessionThresholds
    local function threshold(id)
        for _, chunk in ipairs(data.lines[197]) do
            for spell, low, high in chunk:gmatch("(%d+),(%d+),(%d+)") do
                if tonumber(spell) == id then return tonumber(low), tonumber(high) end
            end
        end
    end
    local function colour(low, high)
        if skill >= high then return 3 end
        if skill < low then return 0 end
        return skill < math.floor((low + high) / 2) and 1 or 2
    end
    env.Enum = { TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 },
        CraftingReagentType = { Basic = 1 } }
    env.IsShiftKeyDown = function() return false end
    env.ChatEdit_InsertLink = function() end
    env.GetProfessions = function() return nil end
    env.GetProfessionInfo = function() return nil end
    env.C_TradeSkillUI = {
        IsTradeSkillReady = function() return true end, IsTradeSkillLinked = function() return false end,
        IsTradeSkillGuild = function() return false end, IsNPCCrafting = function() return false end,
        GetChildProfessionInfo = function()
            return { professionID = 2948, professionName = "Tailoring", skillLevel = skill, maxSkillLevel = 150,
                parentProfessionID = 197 }
        end,
        GetBaseProfessionInfo = function() return { professionID = 197 } end,
        GetProfessionInfoByRecipeID = function() return nil end,
        GetAllRecipeIDs = function()
            local list = {}
            for id in pairs(recipes) do list[#list + 1] = id end
            table.sort(list)
            return list
        end,
        IsRecipeInSkillLine = function() return true end,
        GetRecipeInfo = function(id)
            local recipe, low, high = recipes[id], threshold(id)
            return { recipeID = id, name = recipe[1], icon = 130000 + id % 700, maxTrivialLevel = high,
                relativeDifficulty = colour(low, high), numSkillUps = 1, learned = recipe[2] }
        end,
        GetRecipeSchematic = function(id)
            local slots = {}
            for index, reagent in ipairs(recipes[id][3]) do
                slots[index] = { reagentType = 1, quantityRequired = reagent[2], reagents = { { itemID = reagent[1] } } }
            end
            return { reagentSlotSchematics = slots }
        end,
        GetCraftableCount = function(id) return id == 2964 and 4 or 0 end,
        GetRecipeSourceText = function() return "Trainer: Tailoring trainers in any capital" end,
        GetRecipeLink = function() return nil end, OpenRecipe = function() end,
    }
    env.C_Item.GetItemCount = function(id) return bags[id] or 0 end
    env.C_Item.GetItemInfo = function(id) return items[id], nil end
    env.C_Item.GetItemNameByID = function(id) return items[id] end
    -- On by default, so boot already settled it to enabled without its capabilities: enable it for real now
    -- that they are stubbed.
    local module = R.moduleByID["items.professionPlanner"]
    R.Registry:Disable(module)
    R.Registry:Enable("items.professionPlanner")
    if module.state ~= "enabled" then
        io.stderr:write("planner: module " .. tostring(module.state) .. " " .. table.concat(module.missing or {}, ",")
            .. " " .. tostring(module.failure) .. "\n")
    end
    env:Fire("TRADE_SKILL_SHOW")
    env:Advance(0.5)
    reportErrors("planner", R)
    return env, R, module
end

scenario("planner", function()
    local env, R, module = plannerWorld(58)
    write("planner", env, R)
    local row = module.ui.steps[1]
    row.scripts.OnEnter(row)
    write("planner-hover", env, R, { hovered = row })
    row.scripts.OnLeave(row)
    module:OnCollapse()
    write("planner-collapsed", env, R)
    module:OnCollapse()
    reportErrors("planner", R)
end)

scenario("planner-cap", function()
    local env, R = plannerWorld(150)
    write("planner-cap", env, R)
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
