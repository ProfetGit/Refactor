local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local function base(widgets)
    local env = Runtime.new()
    if widgets then Widgets.install(env) end
    for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Commands.enUS.lua",
        "Locales/Tooltips.enUS.lua", "Locales/Toasts.enUS.lua", "Locales/Features.enUS.lua" }) do
        env:Load(path)
    end
    env.control, env.combat = false, false
    env.IsControlKeyDown = function() return env.control end
    env.InCombatLockdown = function() return env.combat end
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    env.R.UI = env.R.UI or {}
    return env
end

local function enable(env, path, id)
    env:Load(path)
    assert.is_true(env.R.Registry:Enable(id), id .. " did not enable: "
        .. tostring(env.R.moduleByID[id].failure) .. " " .. table.concat(env.R.moduleByID[id].missing or {}, ","))
    return env.R.moduleByID[id]
end

local function strsplit_lines(text)
    local lines = {}
    for line in tostring(text):gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    return unpack(lines)
end

local function noResidue(env, module)
    env.R.Registry:Disable(module)
    assert.equals(0, env:ActiveTimers())
    for _, entries in pairs(env.R.Broker.events) do
        for _, entry in ipairs(entries) do
            assert.is_not.equal(module, entry.owner)
        end
    end
    assert.is_true(env.R.Registry:Enable(module))
    env.R.Registry:Disable(module)
end

local function tooltipEnv()
    local env = base()
    env.postCalls = {}
    env.TooltipDataProcessor = { AddTooltipPostCall = function(dataType, fn)
        env.postCalls[#env.postCalls + 1] = { dataType = dataType, fn = fn }
    end }
    env.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
    env.units = { player1 = { player = true, class = "MAGE" } }
    env.UnitIsPlayer = function(unit) return (env.units[unit] or {}).player == true end
    env.UnitClassBase = function(unit) return (env.units[unit] or {}).class end
    env.classColors = { MAGE = { 0.41, 0.8, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 } }
    env.C_ClassColor = { GetClassColor = function(classFile)
        local color = env.classColors[classFile]
        if not color then return nil end
        return { GetRGB = function() return color[1], color[2], color[3] end }
    end }
    env.MerchantFrame = { IsShown = function() return env.merchantOpen == true end }
    env.hooks = {}
    env.hooksecurefunc = function(name, fn) env.hooks[name] = fn end
    env.GameTooltip_SetDefaultAnchor = function() end
    env.UIParent = { name = "UIParent" }
    local function tooltip(name)
        local tip = { name = name, shown = true, money = {}, scripts = {}, border = { 1, 1, 1, 1 } }
        tip.NineSlice = { SetBorderColor = function(_, r, g, b, a) tip.border = { r, g, b, a } end }
        function tip:HookScript(script, fn) self.scripts[script] = fn end
        function tip:IsShown() return self.shown end
        function tip:Show() self.shown = true end
        function tip:SetOwner(owner, anchor, x, y) self.owner = { owner = owner, anchor = anchor, x = x, y = y } end
        function tip:ClearAllPoints() self.point = nil end
        function tip:SetPoint(point, relative, relativePoint, x, y)
            self.point = { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y }
        end
        return tip
    end
    env.GameTooltip, env.ItemRefTooltip = tooltip("GameTooltip"), tooltip("ItemRefTooltip")
    env.ShoppingTooltip1, env.ShoppingTooltip2 = tooltip("ShoppingTooltip1"), tooltip("ShoppingTooltip2")
    env.SetTooltipMoney = function(tip, amount, _, label) tip.money[#tip.money + 1] = { amount, label } end
    env.TooltipUtil = {
        GetDisplayedItem = function() return "Sword", env.link, 7 end,
        GetDisplayedUnit = function() return "Someone", env.hoveredUnit end,
    }
    env.link = "|cffffffff|Hitem:7::::::::1:::::|h[Sword]|h|r"
    env.qualities = { [7] = 3 }
    env.C_Item = {
        GetItemInfo = function() return "Sword", env.link, 3, 1, 1, "", "", env.stack or 1, "", 1, 25 end,
        GetItemQualityByID = function(id) return env.qualities[id] end,
        GetItemQualityColor = function(q) return q / 10, q / 20, q / 40, "hex" end,
    }
    function env:PostCall(tip, data)
        for _, call in ipairs(self.postCalls) do
            if call.dataType == self.Enum.TooltipDataType.Item then call.fn(tip, data or { id = 7 }) end
        end
    end
    -- A unit post call takes the tooltip alone: the unit comes back from the client.
    function env:HoverUnit(tip, unit)
        self.hoveredUnit = unit
        for _, call in ipairs(self.postCalls) do
            if call.dataType == self.Enum.TooltipDataType.Unit then call.fn(tip) end
        end
    end
    return env
end

describe("M4 tooltips", function()
    it("tints the border with a hovered player's class colour, and only a player's", function()
        local env = tooltipEnv()
        env.units.mob = { class = "MAGE" }
        env.units.warlock = { player = true, class = "WARLOCK" }
        env.units.nobody = { player = true, class = "TINKER" }
        env:Load("Modules_LoD/Tooltips/RarityBorder_Data.lua")
        local module = enable(env, "Modules_LoD/Tooltips/RarityBorder.lua", "tooltips.rarityBorder")
        env:HoverUnit(env.GameTooltip, "player1")
        assert.same({ 0.41, 0.8, 0.94, 1 }, env.GameTooltip.border)
        env.GameTooltip.scripts.OnTooltipCleared(env.GameTooltip)
        assert.same({ 1, 1, 1, 1 }, env.GameTooltip.border)
        -- A second class is read once and kept; the first is answered from the cache.
        env:HoverUnit(env.GameTooltip, "warlock")
        assert.same({ 0.58, 0.51, 0.79, 1 }, env.GameTooltip.border)
        env.classColors.MAGE = nil
        env.GameTooltip.scripts.OnTooltipCleared(env.GameTooltip)
        env:HoverUnit(env.GameTooltip, "player1")
        assert.same({ 0.41, 0.8, 0.94, 1 }, env.GameTooltip.border)
        -- A mob, a unit the client gives no colour for, and no unit at all: border left white.
        for _, unit in ipairs({ "mob", "nobody" }) do
            env.GameTooltip.scripts.OnTooltipCleared(env.GameTooltip)
            env:HoverUnit(env.GameTooltip, unit)
            assert.same({ 1, 1, 1, 1 }, env.GameTooltip.border)
        end
        env.GameTooltip.scripts.OnTooltipCleared(env.GameTooltip)
        env:HoverUnit(env.GameTooltip, nil)
        assert.same({ 1, 1, 1, 1 }, env.GameTooltip.border)
        -- Off, the item half of the feature carries on alone.
        env.R.Settings:SetOption("tooltipClassBorder", false)
        env:HoverUnit(env.GameTooltip, "player1")
        assert.same({ 1, 1, 1, 1 }, env.GameTooltip.border)
        env:PostCall(env.GameTooltip)
        assert.same({ 0.3, 0.15, 0.075, 1 }, env.GameTooltip.border)
        noResidue(env, module)
    end)

    it("rarity border tints, resets on clear, fills a miss when item data arrives", function()
        local env = tooltipEnv()
        env:Load("Modules_LoD/Tooltips/RarityBorder_Data.lua")
        local module = enable(env, "Modules_LoD/Tooltips/RarityBorder.lua", "tooltips.rarityBorder")
        env:PostCall(env.GameTooltip)
        assert.same({ 0.3, 0.15, 0.075, 1 }, env.GameTooltip.border)
        env.GameTooltip.scripts.OnTooltipCleared(env.GameTooltip)
        assert.same({ 1, 1, 1, 1 }, env.GameTooltip.border)
        env:PostCall(env.ShoppingTooltip1, { id = 9 })
        assert.same({ 1, 1, 1, 1 }, env.ShoppingTooltip1.border)
        assert.is_not_nil(env.R.Broker.events.GET_ITEM_INFO_RECEIVED)
        env.qualities[9] = 4
        env:Fire("GET_ITEM_INFO_RECEIVED", 9, true)
        assert.same({ 0.4, 0.2, 0.1, 1 }, env.ShoppingTooltip1.border)
        assert.is_nil(env.R.Broker.events.GET_ITEM_INFO_RECEIVED)
        env:PostCall(env.GameTooltip)
        env.R.Registry:Disable(module)
        assert.same({ 1, 1, 1, 1 }, env.GameTooltip.border)
        env:PostCall(env.GameTooltip)
        assert.same({ 1, 1, 1, 1 }, env.GameTooltip.border)
        noResidue(env, module)
    end)

    it("anchor follows the option and does nothing when disabled", function()
        local env = tooltipEnv()
        local module = enable(env, "Modules_LoD/Tooltips/Anchor.lua", "tooltips.anchor")
        local hook = env.hooks.GameTooltip_SetDefaultAnchor
        env.R.Settings:SetOption("tooltipAnchor", "cursor")
        hook(env.GameTooltip, env.UIParent)
        assert.equal("ANCHOR_CURSOR_RIGHT", env.GameTooltip.owner.anchor)
        env.R.Settings:SetOption("tooltipAnchor", "point")
        env.R.Settings:SetOption("tooltipPoint", "TOPLEFT")
        env.R.Settings:SetOption("tooltipX", 40)
        hook(env.GameTooltip, env.UIParent)
        assert.equal("TOPLEFT", env.GameTooltip.point.point)
        assert.equal(40, env.GameTooltip.point.x)
        env.R.Registry:Disable(module)
        env.GameTooltip.point = nil
        hook(env.GameTooltip, env.UIParent)
        assert.is_nil(env.GameTooltip.point)
        noResidue(env, module)
    end)
end)

local function toastEnv()
    local env = base(true)
    env:Load("UI/LootFeed.lua")
    env.GetMoney = function() return env.money or 0 end
    env.money = 1000
    env.C_Item = {
        GetItemQualityByID = function(id) return env.qualities and env.qualities[id] or 1 end,
        GetItemIconByID = function(id) return 100 + id end,
        GetItemQualityColor = function(q) return q, q, q end,
        GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 30 end,
    }
    env.C_CurrencyInfo = {
        GetCurrencyInfo = function(id) return { name = "Marks", iconFileID = 5, quality = 2, currencyID = id } end,
        -- Shaped like the client's: coin icons, and no denomination that is zero.
        GetCoinTextureString = function(amount)
            local gold, silver = math.floor(amount / 10000), math.floor(amount / 100) % 100
            local parts = {}
            if gold > 0 then parts[#parts + 1] = gold .. "|TGold|t" end
            if silver > 0 or gold > 0 then parts[#parts + 1] = silver .. "|TSilver|t" end
            parts[#parts + 1] = (amount % 100) .. "|TCopper|t"
            return table.concat(parts, " ")
        end,
    }
    env.GameTooltip = {
        SetOwner = function(tip, owner, anchor) tip.owner, tip.anchor = owner, anchor end,
        SetHyperlink = function(tip, link) tip.hyperlink = link end,
        Show = function(tip) tip.shown = true end,
        Hide = function(tip) tip.shown, tip.hyperlink = false, nil end,
    }
    function env:Loot(text, guid)
        self:Fire("CHAT_MSG_LOOT", text, "Me", "", "", "Me", "", 0, 0, "", 0, 1, guid or "Player-test")
    end
    function env:Rows(host)
        local rows = {}
        for _, item in ipairs(host.items) do
            rows[#rows + 1] = item.row
            for _, child in ipairs(item.children) do rows[#rows + 1] = child end
        end
        return rows
    end
    return env
end

local LINK = "|cff0070dd|Hitem:2000:0:0:0:0:0:0:0:60:0:0:0:0|h[Blue Thing]|h|r"

local function itemLink(id)
    return "|cff0070dd|Hitem:" .. id .. ":0|h[Item " .. id .. "]|h|r"
end

describe("M4 loot feed", function()
    it("parses links locale-free and shows only the player's own loot", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env:Loot("You receive loot: " .. LINK .. "x3.", "Player-other")
        assert.equal(0, #module.host.items)
        env:Loot("You receive loot: " .. LINK .. "x3.")
        assert.equal(1, #module.host.items)
        local row = module.host.items[1].row
        assert.equal("Blue Thing x3", row.name:GetText())
        assert.equal("90|TCopper|t (vendor)", row.detail:GetText())
        assert.equal(2100, row.icon.texture)
        -- The newest row is the bottom one, so it wears no separator.
        assert.is_false(row.underline:IsShown())
        env:Loot("Vous recevez: " .. LINK .. ".")
        assert.equal(1, #module.host.items)
        assert.equal("Blue Thing x4", row.name:GetText())
        noResidue(env, module)
    end)

    it("respects the quality threshold, the price toggle and the source tag", function()
        local env = toastEnv()
        env.qualities = { [2000] = 1 }
        env.R.Settings:SetOption("toastMinQuality", 2)
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env:Loot("loot " .. LINK)
        assert.equal(0, #module.host.items)
        env.qualities[2000], env.qualities[2001] = 2, 2
        env.R.Settings:SetOption("toastShowSource", false)
        env:Loot("loot " .. LINK)
        assert.equal(1, #module.host.items)
        assert.equal("30|TCopper|t", module.host.items[1].row.detail:GetText())
        env.R.Settings:SetOption("toastShowPrice", false)
        env:Loot("loot " .. itemLink(2001))
        assert.equal("", module.host.items[2].row.detail:GetText())
        noResidue(env, module)
    end)

    it("shows gold only around a loot window, and currency on gain", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env.money = 1500
        env:Fire("PLAYER_MONEY")
        assert.equal(0, #module.host.items)
        env:Fire("LOOT_OPENED", true, false)
        env.money = 1650
        env:Fire("PLAYER_MONEY")
        assert.equal(1, #module.host.items)
        local gold = module.host.items[1].row
        assert.equal("+1|TSilver|t 50|TCopper|t", gold.detail:GetText())
        -- Gold shows the coin icon, unframed like a currency row.
        assert.is_true(gold.icon:IsShown())
        assert.is_false(gold.iconFrame:IsShown())
        env:Fire("LOOT_CLOSED")
        env:Advance(0.6)
        assert.is_nil(env.R.Broker.events.PLAYER_MONEY)
        env:Fire("CURRENCY_DISPLAY_UPDATE", 42, 10, 5)
        assert.equal(2, #module.host.items)
        local currency = module.host.items[2].row
        assert.equal("+5", currency.detail:GetText())
        assert.is_true(currency.icon:IsShown())
        assert.is_false(currency.iconFrame:IsShown())
        env:Fire("CURRENCY_DISPLAY_UPDATE", 42, 10, -5)
        assert.equal(2, #module.host.items)
        env.R.Registry:Disable(module)
        assert.equal(0, #module.host.items)
        noResidue(env, module)
    end)

    it("collapses a multi-slot loot into one row that expands and pauses its own timer", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env:Fire("LOOT_OPENED", true, false)
        for id = 3000, 3003 do env:Loot("loot " .. itemLink(id)) end
        -- Nothing is shown until the burst has finished arriving.
        assert.equal(0, #module.host.items)
        env:Advance(0.4)
        assert.equal(1, #module.host.items)
        local item = module.host.items[1]
        assert.equal("4 items, 1|TSilver|t 20|TCopper|t", item.row.name:GetText())
        assert.is_true(item.row.chevron:IsShown())
        item.row.chevron:GetScript("OnClick")(item.row.chevron)
        assert.is_true(item.expanded)
        assert.equal(4, #item.children)
        assert.equal(5, #env:Rows(module.host))
        assert.equal("Item 3000", item.children[1].name:GetText())
        item.row.chevron:GetScript("OnClick")(item.row.chevron)
        assert.is_false(item.expanded)
        assert.equal(1, #env:Rows(module.host))
        -- A second loot window after the first has closed is its own group.
        env:Fire("LOOT_CLOSED")
        env:Advance(0.6)
        env:Loot("loot " .. itemLink(3010))
        assert.equal(2, #module.host.items)
        assert.equal("Item 3010", module.host.items[2].row.name:GetText())
        noResidue(env, module)
    end)

    it("pushes one row per item when aggregation is off", function()
        local env = toastEnv()
        env.R.Settings:SetOption("toastAggregate", false)
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env:Fire("LOOT_OPENED", true, false)
        for id = 3000, 3002 do env:Loot("loot " .. itemLink(id)) end
        env:Advance(0.4)
        assert.equal(3, #module.host.items)
        assert.is_false(module.host.items[1].row.chevron:IsShown())
        noResidue(env, module)
    end)

    it("drops the oldest row instead of creating frames during a burst", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        local frames = #env.frames
        for index = 1, 8 do env:Loot("loot " .. itemLink(index)) end
        assert.equal(5, #module.host.items)
        assert.equal("Item 4", module.host.items[1].row.name:GetText())
        assert.equal(frames, #env.frames)
        -- The cap is a live setting and trims what is already on screen.
        env.R.Settings:SetOption("toastMaxRows", 3)
        assert.equal(3, #module.host.items)
        assert.equal("Item 6", module.host.items[1].row.name:GetText())
        noResidue(env, module)
    end)

    it("holds a hovered row, shows its tooltip, and starts its life again on leaving", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env:Loot("You receive loot: " .. LINK .. "x3.")
        local row = module.host.items[1].row
        local presented, present = 0, row.Present
        row.Present = function(widget, lifetime)
            presented = presented + 1
            present(widget, lifetime)
        end
        row:GetScript("OnEnter")(row)
        assert.is_true(row.hover:IsShown())
        assert.equal(LINK, env.GameTooltip.hyperlink)
        assert.equal("ANCHOR_LEFT", env.GameTooltip.anchor)
        assert.equal(0, presented)
        row:GetScript("OnLeave")(row)
        assert.is_false(row.hover:IsShown())
        assert.is_nil(env.GameTooltip.hyperlink)
        assert.equal(1, presented)
        -- A row inside an expanded group is paused, so leaving it must not start a countdown.
        env:Fire("LOOT_OPENED", true, false)
        for id = 3000, 3001 do env:Loot("loot " .. itemLink(id)) end
        env:Advance(0.4)
        local group = module.host.items[2]
        group.row.chevron:GetScript("OnClick")(group.row.chevron)
        local child = group.children[1]
        child:GetScript("OnEnter")(child)
        child:GetScript("OnLeave")(child)
        assert.is_true(child.paused)
        assert.is_nil(child.lifetime)
        noResidue(env, module)
    end)

    it("opens native Edit Mode settings on click and writes size, rows and lifetime", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        local host, dialog = module.host, module.host.dialog
        host:SetEditing(true)
        assert.is_false(dialog:IsShown())
        host.selection:GetScript("OnMouseUp")(host.selection)
        assert.is_true(dialog:IsShown())
        assert.equal("100%", dialog.scale.valueText:GetText())
        assert.equal("5 rows", dialog.rows.valueText:GetText())
        assert.equal("5 seconds", dialog.lifetime.valueText:GetText())
        assert.is_false(dialog.scale.undo:IsShown())
        dialog.scale.slider:GetScript("OnValueChanged")(dialog.scale.slider, 120)
        dialog.rows.slider:GetScript("OnValueChanged")(dialog.rows.slider, 7)
        dialog.lifetime.slider:GetScript("OnValueChanged")(dialog.lifetime.slider, 8)
        assert.equal(1.2, env.R.Settings:GetOption("toastScale"))
        assert.equal(7, env.R.Settings:GetOption("toastMaxRows"))
        assert.equal(8, env.R.Settings:GetOption("toastLifetime"))
        assert.equal(1.2, host:Scale())
        assert.equal("120%", dialog.scale.valueText:GetText())
        -- A stepper moves by one step and writes the same way a drag does.
        dialog.rows.forward:GetScript("OnClick")(dialog.rows.forward)
        assert.equal(8, dialog.rows.slider:GetValue())
        -- Each setting carries its own undo, shown only while it differs from the default.
        assert.is_true(dialog.scale.undo:IsShown())
        dialog.scale.undo:GetScript("OnClick")(dialog.scale.undo)
        assert.equal(1, env.R.Settings:GetOption("toastScale"))
        assert.is_false(dialog.scale.undo:IsShown())
        assert.is_true(dialog.lifetime.undo:IsShown())
        -- The click that ends a drag is not the click that opens settings.
        dialog:Hide()
        host.selection:GetScript("OnDragStart")(host.selection)
        host.selection:GetScript("OnDragStop")(host.selection)
        host.selection:GetScript("OnMouseUp")(host.selection)
        assert.is_false(dialog:IsShown())
        host.selection:GetScript("OnMouseUp")(host.selection)
        assert.is_true(dialog:IsShown())
        env.R.Registry:Disable(module)
        assert.is_false(dialog:IsShown())
        assert.is_false(host.selection:IsShown())
    end)

    it("dismisses a row on right click and leaves it alone on left click", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env:Loot("loot " .. itemLink(4000))
        env:Loot("loot " .. itemLink(4001))
        assert.equal(2, #module.host.items)
        local row = module.host.items[1].row
        row:GetScript("OnClick")(row, "LeftButton")
        assert.equal(2, #module.host.items)
        row:GetScript("OnClick")(row, "RightButton")
        assert.equal(1, #module.host.items)
        assert.equal("Item 4001", module.host.items[1].row.name:GetText())
        -- A right click anywhere on an expanded group takes the whole group with it.
        env:Fire("LOOT_OPENED", true, false)
        for id = 4100, 4102 do env:Loot("loot " .. itemLink(id)) end
        env:Advance(0.4)
        local group = module.host.items[2]
        group.row.chevron:GetScript("OnClick")(group.row.chevron)
        assert.equal(3, #group.children)
        local child = group.children[2]
        child:GetScript("OnClick")(child, "RightButton")
        assert.equal(1, #module.host.items)
        assert.equal(1, #env:Rows(module.host))
        -- The dismissed rows went back to the pool rather than being abandoned.
        env:Loot("loot " .. itemLink(4200))
        env:Advance(0.4)
        assert.equal(2, #module.host.items)
        noResidue(env, module)
    end)

    it("keeps the settings dialog in screen space so resizing the feed cannot drag it", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        local host, dialog = module.host, module.host.dialog
        local anchors = {}
        dialog.SetPoint = function(_, _, relative) anchors[#anchors + 1] = relative end
        -- Headless frames report no screen rect, so this dialog is given one to pin itself to.
        dialog.GetLeft, dialog.GetTop = function() return 320 end, function() return 540 end
        host:SetEditing(true)
        host.selection:GetScript("OnMouseUp")(host.selection)
        assert.equal(env.UIParent, anchors[#anchors])
        -- Changing the feed size touches the feed only, never the dialog.
        local before = #anchors
        env.R.Settings:SetOption("toastScale", 1.3)
        assert.equal(before, #anchors)
        dialog:GetScript("OnDragStop")(dialog)
        assert.same({ x = 320, y = 540 }, env.R.Settings.character.lootDialog)
        -- A saved position is what the next open uses, with no detour past the feed.
        dialog:Hide()
        anchors = {}
        host.selection:GetScript("OnMouseUp")(host.selection)
        assert.equal(1, #anchors)
        assert.equal(env.UIParent, anchors[1])
        noResidue(env, module)
    end)

    it("offers the Edit Mode handle only while the module is on, and saves a drag", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        local host = module.host
        assert.is_false(host.selection:IsShown())
        host:SetEditing(true)
        assert.is_true(host.selection:IsShown())
        host.selection:GetScript("OnDragStart")(host.selection)
        host.selection:GetScript("OnDragStop")(host.selection)
        assert.same({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }, env.R.Settings.character.toast)
        host:SetEditing(false)
        assert.is_false(host.selection:IsShown())
        env.R.Registry:Disable(module)
        host:SetEditing(true)
        assert.is_false(host.selection:IsShown())
    end)

    it("pushes test rows on command and names any texture the client refused", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env.R.Broker:Emit("REFACTOR_LOOT_TEST")
        assert.matches("Feed textures loaded", env.messages[1])
        assert.matches("Pushed five test rows", env.messages[2])
        assert.equal(5, #module.host.items)
        assert.equal("Copper Ore x20", module.host.items[2].row.name:GetText())
        assert.equal("4 items, 2|TGold|t 16|TSilver|t 0|TCopper|t", module.host.items[5].row.name:GetText())
        env.messages = {}
        env.R.Theme.missingFiles.lootRow = true
        env.R.Broker:Emit("REFACTOR_LOOT_TEST")
        assert.matches("lootRow", env.messages[1])
        assert.matches("not enough", env.messages[1])
        env.R.Theme.missingFiles.lootRow = nil
        noResidue(env, module)
    end)
end)

describe("M4 quest automation", function()
    local function questEnv()
        local env = base()
        env.accepted, env.selected, env.available, env.greeting = 0, {}, {}, {}
        env.AcceptQuest = function() env.accepted = env.accepted + 1 end
        env.QuestGetAutoAccept = function() return env.autoAccept == true end
        env.QuestFlagsPVP = function() return env.pvp == true end
        env.QuestIsFromAdventureMap = function() return env.adventureMap == true end
        env.GetQuestID = function() return 500 end
        env.npc = "Creature-0-3061-1-42177-38038-002FAC4343"
        env.UnitGUID = function() return env.npc end
        env.C_QuestLog = {
            IsRepeatableQuest = function() return env.repeatable == true end,
            -- The accepted count comes second: the first return includes the log's headers.
            GetNumQuestLogEntries = function() return (env.logQuests or 0) + 3, env.logQuests or 0 end,
            GetMaxNumQuestsCanAccept = function() return env.logLimit or 35 end,
        }
        env.C_GossipInfo = {
            GetAvailableQuests = function() return env.available end,
            SelectAvailableQuest = function(questID) env.selected[#env.selected + 1] = questID end,
        }
        env.GetNumAvailableQuests = function() return #env.greeting end
        env.GetAvailableQuestInfo = function(index)
            local offer = env.greeting[index]
            return offer.isTrivial, offer.frequency, offer.repeatable, false, offer.questID
        end
        -- Negative entries mark a greeting selection, which names a slot rather than a quest.
        env.SelectAvailableQuest = function(index) env.selected[#env.selected + 1] = -index end
        return env
    end

    it("accepts unless flagged, repeatable, paused, limited to item quests, or the log is full", function()
        local env = questEnv()
        local module = enable(env, "Modules/Quest/AutoAccept.lua", "quest.autoAccept")
        env:Fire("QUEST_DETAIL")
        assert.equal(1, env.accepted)
        env.autoAccept = true
        env:Fire("QUEST_DETAIL")
        env.autoAccept, env.pvp = false, true
        env:Fire("QUEST_DETAIL")
        env.pvp, env.repeatable = false, true
        env:Fire("QUEST_DETAIL")
        env.repeatable, env.adventureMap = false, true
        env:Fire("QUEST_DETAIL")
        env.adventureMap, env.control = false, true
        env:Fire("QUEST_DETAIL")
        assert.equal(1, env.accepted)
        env.control = false
        env.R.Settings:SetOption("questAcceptItemsOnly", true)
        env:Fire("QUEST_DETAIL", nil)
        assert.equal(1, env.accepted)
        env:Fire("QUEST_DETAIL", 4321)
        assert.equal(2, env.accepted)
        env.R.Settings:SetOption("questAcceptItemsOnly", false)
        -- A full log is said once, not once per offer.
        env.logQuests, env.logLimit = 35, 35
        env:Fire("QUEST_DETAIL")
        env:Fire("QUEST_DETAIL")
        assert.equal(2, env.accepted)
        assert.equal(1, #env.messages)
        assert.matches("quest log is full", env.messages[1])
        noResidue(env, module)
    end)

    it("works through an NPC's offers on the gossip list and on the greeting panel", function()
        local env = questEnv()
        local module = enable(env, "Modules/Quest/AutoAccept.lua", "quest.autoAccept")
        env.available = { { questID = 10, isIgnored = true }, { questID = 11, repeatable = true },
            { questID = 12 }, { questID = 13 } }
        env:Fire("GOSSIP_SHOW")
        assert.same({ 12 }, env.selected)
        -- An accepted quest leaves the list, and the page that follows carries on down it.
        env.available = { { questID = 10, isIgnored = true }, { questID = 11, repeatable = true },
            { questID = 13 } }
        env:Fire("GOSSIP_SHOW")
        assert.same({ 12, 13 }, env.selected)
        -- Nothing left that this visit has not opened.
        env:Fire("GOSSIP_SHOW")
        assert.same({ 12, 13 }, env.selected)
        -- Same NPC on the greeting panel: slot 1 was opened as quest 13, slot 2 is repeatable.
        env.greeting = { { questID = 13 }, { questID = 14, repeatable = true }, { questID = 15 } }
        env:Fire("QUEST_GREETING")
        assert.same({ 12, 13, -3 }, env.selected)
        -- A different NPC starts its own list.
        env.npc = "Creature-0-3061-1-42177-38039-002FAC4343"
        env.greeting = { { questID = 13 } }
        env:Fire("QUEST_GREETING")
        assert.same({ 12, 13, -3, -1 }, env.selected)
        noResidue(env, module)
    end)

    it("leaves a list alone when paused, in combat, limited to items, switched off, or the log is full", function()
        local env = questEnv()
        local module = enable(env, "Modules/Quest/AutoAccept.lua", "quest.autoAccept")
        env.available = { { questID = 20 } }
        env.control = true
        env:Fire("GOSSIP_SHOW")
        env.control, env.combat = false, true
        env:Fire("GOSSIP_SHOW")
        env.combat = false
        env.R.Settings:SetOption("questAcceptItemsOnly", true)
        env:Fire("GOSSIP_SHOW")
        env.R.Settings:SetOption("questAcceptItemsOnly", false)
        env.R.Settings:SetOption("questAcceptLists", false)
        env:Fire("GOSSIP_SHOW")
        env.R.Settings:SetOption("questAcceptLists", true)
        env.logQuests, env.logLimit = 25, 25
        env:Fire("GOSSIP_SHOW")
        assert.same({}, env.selected)
        assert.equal(1, #env.messages)
        -- A refusal spends no offer, so making room is enough to carry on.
        env.logQuests = 24
        env:Fire("GOSSIP_SHOW")
        assert.same({ 20 }, env.selected)
        noResidue(env, module)
    end)

    it("stops after ten offers at one NPC", function()
        local env = questEnv()
        local module = enable(env, "Modules/Quest/AutoAccept.lua", "quest.autoAccept")
        for index = 1, 12 do
            env.greeting[index] = { questID = 100 + index }
        end
        for _ = 1, 12 do
            env:Fire("QUEST_GREETING")
        end
        assert.equal(10, #env.selected)
        noResidue(env, module)
    end)

    it("turns in only when completable and without a reward choice", function()
        local env = base()
        local completed, rewarded = 0, 0
        env.IsQuestCompletable = function() return env.completable == true end
        env.CompleteQuest = function() completed = completed + 1 end
        env.GetNumQuestChoices = function() return env.choices or 0 end
        env.GetQuestReward = function() rewarded = rewarded + 1 end
        local module = enable(env, "Modules/Quest/AutoTurnIn.lua", "quest.autoTurnIn")
        env:Fire("QUEST_PROGRESS")
        assert.equal(0, completed)
        env.completable = true
        env:Fire("QUEST_PROGRESS")
        assert.equal(1, completed)
        env:Fire("QUEST_COMPLETE")
        assert.equal(1, rewarded)
        env.choices = 2
        env:Fire("QUEST_COMPLETE")
        assert.equal(1, rewarded)
        env.choices, env.combat = 0, true
        env:Fire("QUEST_COMPLETE")
        assert.equal(1, rewarded)
        noResidue(env, module)
    end)
    local function gossipEnv()
        local env = base()
        env.shift, env.instance, env.force = false, false, false
        env.IsShiftKeyDown = function() return env.shift end
        env.IsAltKeyDown = function() return false end
        env.IsInInstance = function() return env.instance end
        env.npc = "Creature-0-3061-1-42177-38038-002FAC4343"
        env.UnitGUID = function(unit) return unit == "npc" and env.npc or "Player-test" end
        env.Enum = {
            GossipOptionStatus = { Available = 0, Locked = 2 },
            GossipOptionRecFlags = { QuestLabelPrepend = 1, HideOptionIDFromClient = 2, PlayMovieLabelPrepend = 4 },
        }
        env.hookCount = 0
        env.hooksecurefunc = function(target, name, fn)
            local original = target[name]
            target[name] = function(...) original(...); fn(...) end
            env.hookCount = env.hookCount + 1
        end
        env.options, env.available, env.active, env.picked, env.quests = {}, {}, {}, {}, {}
        -- Blizzard's option button: the mixin is copied onto each button, and its OnClick
        -- selects by the button's ID, which is the option's order index.
        env.GossipOptionButtonMixin = {
            OnClick = function(button) env.C_GossipInfo.SelectOptionByIndex(button:GetID()) end,
        }
        function env.click(index)
            env.GossipOptionButtonMixin.OnClick({ GetID = function() return index end }, "LeftButton")
        end
        env.C_GossipInfo = {
            GetOptions = function()
                local copy = {}
                for index, option in ipairs(env.options) do copy[index] = option end
                return copy
            end,
            GetAvailableQuests = function() return env.available end,
            GetActiveQuests = function() return env.active end,
            ForceGossip = function() return env.force end,
            SelectOptionByIndex = function(index) env.picked[#env.picked + 1] = index end,
            SelectAvailableQuest = function(id) env.quests[#env.quests + 1] = id end,
            SelectActiveQuest = function(id) env.quests[#env.quests + 1] = -id end,
        }
        function env.option(index, icon, fields)
            local option = { gossipOptionID = 1000 + index, orderIndex = index, name = "Option " .. index,
                icon = icon, status = 0, flags = 0, rewards = {}, selectOptionWhenOnlyOption = false }
            for key, value in pairs(fields or {}) do option[key] = value end
            return option
        end
        function env.visit(...)
            env:Fire("GOSSIP_SHOW", ...)
            env:Fire("GOSSIP_CLOSED", false)
        end
        return env
    end
    local VENDOR, TRAINER, TALK, INNKEEPER = 132060, 132058, 132053, 4955461

    it("gossip: remembers a modifier click per NPC, picks it next visit, forgets on a paused click", function()
        local env = gossipEnv()
        local module = enable(env, "Modules/Quest/AutoGossip.lua", "quest.autoGossip")
        env.options = { env.option(1, VENDOR), env.option(2, TALK), env.option(3, TALK) }
        env.available = { { questID = 10 } }
        env:Fire("GOSSIP_SHOW")
        assert.same({}, env.picked)
        env.shift = true
        env.click(2)
        env.shift = false
        assert.same({ 2 }, env.picked)
        assert.equal(1002, env.R.Settings:GetOption("gossipLearned").Creature[38038])
        assert.is_truthy(env.messages[#env.messages]:find("Option 2", 1, true))
        env:Fire("GOSSIP_CLOSED", false)
        env:Fire("GOSSIP_SHOW")
        assert.same({ 2, 2 }, env.picked)
        -- Its own pick passes through the hook without re-teaching.
        assert.equal(1002, env.R.Settings:GetOption("gossipLearned").Creature[38038])
        env:Fire("GOSSIP_CLOSED", false)
        -- A locked memory shows the frame rather than guessing another option.
        env.options[2].status = 2
        env.visit()
        assert.same({ 2, 2 }, env.picked)
        env.options[2].status = 0
        -- Paused, the frame stays; a learn click on the remembered option forgets it.
        env.control, env.shift = true, true
        env:Fire("GOSSIP_SHOW")
        assert.same({ 2, 2 }, env.picked)
        env.click(2)
        assert.is_nil(env.R.Settings:GetOption("gossipLearned").Creature)
        assert.is_truthy(env.messages[#env.messages]:find("Forgot", 1, true))
        -- An option whose ID the server hides cannot be remembered.
        env.options[3].gossipOptionID = nil
        env.click(3)
        assert.is_nil(env.R.Settings:GetOption("gossipLearned").Creature)
        env.control, env.shift = false, false
        env:Fire("GOSSIP_CLOSED", false)
        -- Nor can a player.
        env.npc = "Player-1-000000AB"
        env.shift = true
        env:Fire("GOSSIP_SHOW")
        env.click(1)
        assert.same({}, env.R.Settings:GetOption("gossipLearned"))
        env.shift = false
        env:Fire("GOSSIP_CLOSED", false)
        -- A learn modifier other than Shift, and a game object.
        env.npc = "GameObject-0-3061-1-42177-555-002FAC4343"
        env.R.Settings:SetOption("gossipLearnModifier", "CTRL")
        env:Fire("GOSSIP_SHOW")
        env.shift = true
        env.click(1)
        assert.same({}, env.R.Settings:GetOption("gossipLearned"))
        env.shift, env.control = false, true
        env.click(1)
        env.control = false
        assert.equal(1001, env.R.Settings:GetOption("gossipLearned").GameObject[555])
        -- The hook is installed once at load and is inert while the module is off.
        noResidue(env, module)
        assert.equal(1, env.hookCount)
        env.shift = true
        env:Fire("GOSSIP_SHOW")
        env.click(2)
        env.shift = false
        assert.equal(1001, env.R.Settings:GetOption("gossipLearned").GameObject[555])
        assert.equal(0, #env.R.errors)
    end)

    it("gossip: opens an NPC's only quest or a finished hand-in, leaves a real choice open", function()
        local env = gossipEnv()
        local module = enable(env, "Modules/Quest/AutoGossip.lua", "quest.autoGossip")
        env.available = { { questID = 10 } }
        env.visit()
        assert.same({ 10 }, env.quests)
        env.available = { { questID = 10 }, { questID = 11 } }
        env.visit()
        assert.same({ 10 }, env.quests)
        env.available = { { questID = 10 }, { questID = 11, isIgnored = true } }
        env.visit()
        assert.same({ 10, 10 }, env.quests)
        env.available, env.active = { { questID = 10 } }, { { questID = 12 } }
        env.visit()
        assert.same({ 10, 10 }, env.quests)
        env.active = { { questID = 12 }, { questID = 13, isComplete = true } }
        env:Fire("GOSSIP_SHOW")
        assert.same({ 10, 10, -13 }, env.quests)
        -- The hand-in changes the page, so the next one follows within the same visit.
        env:Fire("GOSSIP_CLOSED", true)
        env.active = { { questID = 12 }, { questID = 14, isComplete = true } }
        env.visit()
        assert.same({ 10, 10, -13, -14 }, env.quests)
        env.active = {}
        env.R.Settings:SetOption("gossipOpenQuests", false)
        env.visit()
        assert.same({ 10, 10, -13, -14 }, env.quests)
        env.R.Settings:SetOption("gossipOpenQuests", true)
        -- A gossip option next to a quest is a choice, whichever rule would cover it.
        env.options = { env.option(1, VENDOR) }
        env.visit()
        assert.same({ 10, 10, -13, -14 }, env.quests)
        assert.same({}, env.picked)
        noResidue(env, module)
    end)

    it("gossip: opens the one service among small talk and nothing when the choice is real", function()
        local env = gossipEnv()
        local module = enable(env, "Modules/Quest/AutoGossip.lua", "quest.autoGossip")
        local function show(options)
            env.options = options
            env.visit()
        end
        show({ env.option(1, TALK), env.option(2, VENDOR), env.option(3, TALK) })
        assert.same({ 2 }, env.picked)
        show({ env.option(1, VENDOR) })
        show({ env.option(1, VENDOR), env.option(2, TALK, { flags = 2 }) })
        assert.same({ 2, 1, 1 }, env.picked)
        show({ env.option(1, VENDOR), env.option(2, TRAINER) })
        show({ env.option(1, VENDOR), env.option(2, INNKEEPER) })
        show({ env.option(1, VENDOR), env.option(2, TALK, { rewards = { { id = 1 } } }) })
        show({ env.option(1, VENDOR), env.option(2, TALK, { spellID = 5 }) })
        show({ env.option(1, VENDOR), env.option(2, TALK, { flags = 1 }) })
        show({ env.option(1, VENDOR), env.option(2, TALK, { flags = 6 }) })
        show({ env.option(1, VENDOR), env.option(2, TALK, { overrideIconID = 99 }) })
        show({ env.option(1, VENDOR, { status = 2 }), env.option(2, TALK) })
        assert.same({ 2, 1, 1 }, env.picked)
        env.R.Settings:SetOption("gossipOpenServices", false)
        show({ env.option(1, VENDOR), env.option(2, TALK) })
        assert.same({ 2, 1, 1 }, env.picked)
        noResidue(env, module)
    end)

    it("gossip: skips a lone line of dialogue only when asked, never the client's flagged option", function()
        local env = gossipEnv()
        local module = enable(env, "Modules/Quest/AutoGossip.lua", "quest.autoGossip")
        env.options = { env.option(1, TALK) }
        env.visit()
        assert.same({}, env.picked)
        env.R.Settings:SetOption("gossipSkipDialogue", true)
        env.visit()
        assert.same({ 1 }, env.picked)
        env.options = { env.option(1, TALK, { selectOptionWhenOnlyOption = true }) }
        env.visit()
        env.options = { env.option(1, TALK, { spellID = 7 }) }
        env.visit()
        env.options = { env.option(1, TALK), env.option(2, TALK) }
        env.visit()
        env.options = { env.option(1, INNKEEPER) }
        env.visit()
        assert.same({ 1 }, env.picked)
        noResidue(env, module)
    end)

    it("gossip: stands down for custom frames, forced gossip, combat, pause and instances", function()
        local env = gossipEnv()
        local module = enable(env, "Modules/Quest/AutoGossip.lua", "quest.autoGossip")
        env.options = { env.option(1, VENDOR), env.option(2, TALK) }
        env.visit("npe-guide")
        env.force = true
        env.visit()
        env.force = false
        env.combat = true
        env.visit()
        env.combat = false
        env.control = true
        env.visit()
        env.control = false
        env.instance = true
        env.visit()
        assert.same({}, env.picked)
        -- Inside an instance only a taught choice applies, unless the option says otherwise.
        env.R.Settings:SetOption("gossipLearned", { Creature = { [38038] = 1002 } })
        env.visit()
        assert.same({ 2 }, env.picked)
        env.R.Settings:SetOption("gossipLearned", {})
        env.R.Settings:SetOption("gossipInInstances", true)
        env.visit()
        assert.same({ 2, 1 }, env.picked)
        env.instance = false
        env.visit()
        assert.same({ 2, 1, 1 }, env.picked)
        noResidue(env, module)
    end)

    it("gossip: acts once per page and gives up on a visit that keeps going", function()
        local env = gossipEnv()
        local module = enable(env, "Modules/Quest/AutoGossip.lua", "quest.autoGossip")
        env.R.Settings:SetOption("gossipSkipDialogue", true)
        env.options = { env.option(1, TALK) }
        env:Fire("GOSSIP_SHOW")
        env:Fire("GOSSIP_CLOSED", true)
        env:Fire("GOSSIP_SHOW")
        env:Fire("GOSSIP_SHOW")
        assert.same({ 1 }, env.picked)
        -- Another page within the visit is fine; the first one coming back is a loop.
        env.options = { env.option(2, TALK) }
        env:Fire("GOSSIP_SHOW")
        env.options = { env.option(1, TALK) }
        env:Fire("GOSSIP_SHOW")
        assert.same({ 1, 2 }, env.picked)
        -- A real close starts a fresh visit, and so does another NPC.
        env:Fire("GOSSIP_CLOSED", false)
        env:Fire("GOSSIP_SHOW")
        assert.same({ 1, 2, 1 }, env.picked)
        env.npc = "Creature-0-3061-1-42177-777-002FAC4343"
        env:Fire("GOSSIP_SHOW")
        assert.same({ 1, 2, 1, 1 }, env.picked)
        env:Fire("GOSSIP_CLOSED", false)
        for index = 1, 12 do
            env.options = { env.option(index, TALK) }
            env:Fire("GOSSIP_SHOW")
            env:Fire("GOSSIP_CLOSED", true)
        end
        assert.equal(4 + 8, #env.picked)
        noResidue(env, module)
    end)

    it("gossip: keeps its registry id through a visit, so the window toggle keeps working", function()
        local env = gossipEnv()
        local module = enable(env, "Modules/Quest/AutoGossip.lua", "quest.autoGossip")
        env.options = { env.option(1, VENDOR) }
        env.visit()
        assert.equal("quest.autoGossip", module.id)
        env.R.Settings:SetOverride("quest.autoGossip", false)
        env.R.Registry:Reconcile(module)
        assert.equal("disabled", module.state)
        assert.equal("quest.autoGossip", module.id)
        noResidue(env, module)
    end)

    it("accept: leaves a gossip page the gossip module already acted on", function()
        local env = gossipEnv()
        env.AcceptQuest = function() end
        env.QuestGetAutoAccept = function() return false end
        env.QuestFlagsPVP = function() return false end
        env.QuestIsFromAdventureMap = function() return false end
        env.GetQuestID = function() return 500 end
        env.GetNumAvailableQuests = function() return 0 end
        env.GetAvailableQuestInfo = function() return false, nil, false, false, nil end
        env.SelectAvailableQuest = function() end
        env.C_QuestLog = {
            IsRepeatableQuest = function() return false end,
            GetNumQuestLogEntries = function() return 3, 0 end,
            GetMaxNumQuestsCanAccept = function() return 35 end,
        }
        local gossip = enable(env, "Modules/Quest/AutoGossip.lua", "quest.autoGossip")
        local accept = enable(env, "Modules/Quest/AutoAccept.lua", "quest.autoAccept")
        env.available = { { questID = 10 } }
        env:Fire("GOSSIP_SHOW")
        -- The gossip module opens the only offer, and the page is selected once, not twice.
        assert.same({ 10 }, env.quests)
        env:Fire("GOSSIP_CLOSED", false)
        -- Two offers are past the gossip module's rule, so the accept module takes the first.
        env.available = { { questID = 11 }, { questID = 12 } }
        env:Fire("GOSSIP_SHOW")
        assert.same({ 10, 11 }, env.quests)
        env:Fire("GOSSIP_CLOSED", false)
        -- With the gossip module gone, the accept module handles the lone offer itself.
        env.R.Registry:Disable(gossip)
        env.available = { { questID = 13 } }
        env:Fire("GOSSIP_SHOW")
        assert.same({ 10, 11, 13 }, env.quests)
        noResidue(env, accept)
    end)
end)

describe("M4 chat and social", function()
    it("wraps addresses, removes its filters on disable, and opens the copy box on click", function()
        local env = base()
        env.filters = {}
        env.ChatFrameUtil = {
            AddMessageEventFilter = function(event, fn) env.filters[event] = fn end,
            RemoveMessageEventFilter = function(event, fn)
                if env.filters[event] == fn then env.filters[event] = nil end
            end,
        }
        env.hooks = {}
        -- Chained in the order installed, as the client chains them.
        env.hooksecurefunc = function(name, fn)
            local previous = env.hooks[name]
            env.hooks[name] = previous and function() previous() fn() end or fn
        end
        env.SetItemRef = function() end
        local shown
        env.R.UI.ShowUrl = function(_, url) shown = url end
        local module = enable(env, "Modules/Chat/Urls.lua", "chat.urls")
        local filter = env.filters.CHAT_MSG_SAY
        local discard, text, extra = filter(nil, "CHAT_MSG_SAY", "see https://example.com/x?y=1 now", "Bob")
        assert.is_false(discard)
        assert.equal("Bob", extra)
        assert.matches("|Hrefactorurl:1|h%[https://example.com/x%?y=1%]|h|r now", text)
        assert.is_nil(select(2, filter(nil, "CHAT_MSG_SAY", "no link here", "Bob")))
        env.hooks.SetItemRef("refactorurl:1", "", "LeftButton")
        assert.equal("https://example.com/x?y=1", shown)
        env.R.Registry:Disable(module)
        assert.is_nil(env.filters.CHAT_MSG_SAY)
        noResidue(env, module)
    end)

    it("declines duels, accepts resurrection out of combat, and invites only from friends", function()
        local env = base()
        local hidden, actions = {}, {}
        env.StaticPopup_Hide = function(which) hidden[#hidden + 1] = which end
        env.CancelDuel = function() actions[#actions + 1] = "duel" end
        env.AcceptResurrect = function() actions[#actions + 1] = "res" end
        env.AcceptGroup = function() actions[#actions + 1] = "group" end
        env.C_FriendList = { IsFriend = function(guid) return guid == "Player-friend" end }
        env.C_BattleNet = { GetAccountInfoByGUID = function(guid) return guid == "Player-bnet" and {} or nil end }
        env.IsGuildMember = function(name) return name == "Guildie" end
        env.instanceType = "none"
        env.IsInInstance = function() return env.instanceType ~= "none", env.instanceType end
        local popup = { inviteAccepted = nil }
        env.StaticPopup_FindVisible = function(which) return which == "PARTY_INVITE" and popup or nil end
        local duels = enable(env, "Modules/Chat/DeclineDuels.lua", "social.declineDuels")
        local res = enable(env, "Modules/Chat/AcceptResurrect.lua", "social.acceptResurrect")
        local invites = enable(env, "Modules/Chat/AcceptInvites.lua", "social.acceptInvites")
        assert.is_true(invites:IsTrusted("Stranger", "Player-friend"))
        assert.is_true(invites:IsTrusted("Guildie", "Player-x"))
        assert.is_true(invites:IsTrusted("Bnet", "Player-bnet"))
        assert.is_false(invites:IsTrusted("Stranger", "Player-stranger"))
        env:Fire("DUEL_REQUESTED", "Bob")
        assert.same({ "duel" }, actions)
        assert.same({ "DUEL_REQUESTED" }, hidden)
        env.combat = true
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.same({ "duel" }, actions)
        env.combat = false
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.same({ "duel", "res" }, actions)
        -- Area options: battlegrounds only is the other two switched off, and an
        -- instanceType the client never returned today is not accepted anywhere.
        env.R.Settings:SetOption("resurrectWorld", false)
        env.R.Settings:SetOption("resurrectInstance", false)
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.same({ "duel", "res" }, actions)
        env.instanceType = "party"
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.same({ "duel", "res" }, actions)
        env.instanceType = "pvp"
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.same({ "duel", "res", "res" }, actions)
        env.instanceType = "arena"
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.same({ "duel", "res", "res", "res" }, actions)
        env.instanceType = "somethingnew"
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.equal(4, #actions)
        env.R.Settings:SetOption("resurrectInstance", true)
        env.instanceType = "raid"
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.equal(5, #actions)
        env.instanceType = "none"
        env.R.Settings:SetOption("resurrectWorld", true)
        env:Fire("PARTY_INVITE_REQUEST", "Stranger", false, false, false, true, false, "Player-stranger", false)
        assert.equal(5, #actions)
        env:Fire("PARTY_INVITE_REQUEST", "Friend", false, false, false, true, false, "Player-friend", false)
        assert.equal("group", actions[6])
        -- The popup is only cleared once it exists, and only with the flag that stops
        -- Blizzard's OnHide from declining the invite we just accepted.
        assert.is_nil(popup.inviteAccepted)
        env:Advance(1)
        assert.equal(1, popup.inviteAccepted)
        assert.equal("PARTY_INVITE", hidden[#hidden])
        env.control = true
        env:Fire("DUEL_REQUESTED", "Bob")
        assert.equal(6, #actions)
        env:Fire("PARTY_INVITE_REQUEST", "Friend", false, false, false, true, false, "Player-friend", false)
        assert.equal(6, #actions)
        env:Fire("RESURRECT_REQUEST", "Healer")
        assert.equal(6, #actions)
        for _, module in ipairs({ duels, res, invites }) do noResidue(env, module) end
    end)

    it("quick invites the player under the cursor, and nobody else", function()
        local env = base()
        env.alt, env.shift = false, false
        env.IsAltKeyDown = function() return env.alt end
        env.IsShiftKeyDown = function() return env.shift end
        -- One little world: what the cursor is over, what is selected, and what each of
        -- them is. A click is the cursor landing on someone and the selection following.
        local people = {
            rogue = { name = "Rogue", guid = "P-1", player = true, human = true, online = true, friendly = true },
            farseer = { name = "Farseer", realm = "Other Realm", guid = "P-2", player = true, human = true,
                online = true, friendly = true },
            guard = { name = "Guard", guid = "C-1", online = true, friendly = true },
            grunt = { name = "Grunt", guid = "P-3", player = true, human = true, online = true },
            ghost = { name = "Ghost", guid = "P-4", player = true, human = true, friendly = true },
            healer = { name = "Healer", guid = "P-5", player = true, human = true, online = true,
                friendly = true, grouped = true },
            bot = { name = "Bot", guid = "P-6", player = true, online = true, friendly = true },
            me = { name = "Tester", guid = "P-0", player = true, human = true, online = true, friendly = true },
        }
        env.hover, env.selected = nil, nil
        local function unitOf(token)
            if token == "target" then return env.selected end
            if token == "mouseover" then return env.hover end
            if token == "player" then return people.me end
            return nil
        end
        env.UnitExists = function(token) return unitOf(token) ~= nil end
        env.UnitIsUnit = function(a, b) return unitOf(a) ~= nil and unitOf(a) == unitOf(b) end
        env.UnitIsPlayer = function(token) return (unitOf(token) or {}).player == true end
        env.UnitIsHumanPlayer = function(token) return (unitOf(token) or {}).human == true end
        env.UnitIsConnected = function(token) return (unitOf(token) or {}).online == true end
        env.UnitCanCooperate = function(_, token) return (unitOf(token) or {}).friendly == true end
        env.UnitInParty = function(token) return (unitOf(token) or {}).grouped == true end
        env.UnitInRaid = function() return false end
        env.UnitGUID = function(token) return (unitOf(token) or {}).guid end
        env.UnitName = function(token)
            local unit = unitOf(token)
            if not unit then return nil end
            return unit.name, unit.realm
        end
        local invited = {}
        env.C_PartyInfo = { InviteUnit = function(name) invited[#invited + 1] = name end }
        local module = enable(env, "Modules/Chat/QuickInvite.lua", "social.quickInvite")
        local function hover(who)
            env.hover = who
            env:Fire("UPDATE_MOUSEOVER_UNIT")
        end
        local function click(who)
            hover(who)
            env.selected = who
            env:Fire("PLAYER_TARGET_CHANGED")
        end
        click(people.rogue)
        assert.same({}, invited)
        env.alt = true
        click(people.rogue)
        assert.same({ "Rogue" }, invited)
        assert.equal("Party invite sent to Rogue.", env.messages[#env.messages])
        -- Cross-realm needs the realm spelled out; a same-realm name never carries one.
        click(people.farseer)
        assert.equal("Farseer-Other Realm", invited[2])
        -- A client that drops mouseover on the click still leaves the GUID the cursor was
        -- last on, and that is enough to know the selection came from a click.
        hover(people.rogue)
        env.hover = nil
        env.selected = people.rogue
        env:Fire("PLAYER_TARGET_CHANGED")
        assert.equal("Rogue", invited[3])
        assert.equal("hover", module.report.via)
        -- Tab targeting with the key held: the cursor is on nobody and was on nobody.
        hover(nil)
        env.selected = people.farseer
        env:Fire("PLAYER_TARGET_CHANGED")
        assert.equal(3, #invited)
        assert.equal("CURSOR", module.report.verdict)
        -- The cursor on one player while the selection lands on another is not a click either.
        hover(people.farseer)
        env.selected = people.rogue
        env:Fire("PLAYER_TARGET_CHANGED")
        assert.equal(3, #invited)
        for _, who in ipairs({ people.guard, people.grunt, people.ghost, people.healer,
            people.bot, people.me }) do
            env.selected = nil
            click(who)
            assert.equal(3, #invited)
        end
        assert.equal("REFUSED", module.report.verdict)
        -- The pause modifier still wins, and the invite key is the player's to pick.
        env.control = true
        env.selected = nil
        click(people.rogue)
        assert.equal(3, #invited)
        env.control = false
        env.R.Settings:SetOption("inviteModifier", "SHIFT")
        env.selected = nil
        click(people.rogue)
        assert.equal(3, #invited)
        env.alt, env.shift = false, true
        env.selected = nil
        click(people.rogue)
        assert.equal("Rogue", invited[4])
        -- The report is what the in-game session has instead of a debugger.
        env.R.Broker:Emit("REFACTOR_INVITE_TEST")
        assert.matches("Invite sent%.", env.messages[#env.messages - 1])
        noResidue(env, module)
    end)
end)

describe("M4 interface, mail, vendor", function()
    local function cameraEnv()
        local env = base()
        env.cvars, env.console, env.zoom, env.hidden = {}, {}, {}, {}
        env.C_CVar = {
            SetCVar = function(name, value) env.cvars[name] = value end,
            GetCVarDefault = function(name)
                if name == "cameraDistanceMaxZoomFactor" then return "1.9" end
                if name == "CameraKeepCharacterCentered" then return "1" end
                return "0"
            end,
        }
        env.ConsoleExec = function(command) env.console[#env.console + 1] = command end
        env.StaticPopup_Hide = function(which) env.hidden[which] = true end
        -- A distance the calls move and clamp the way the client does, plus a count of
        -- the moves, so a test can say both where the camera ended and that it stayed put.
        env.cameraZoom, env.moves = 20, 0
        env.CameraZoomIn = function(yards)
            env.cameraZoom, env.moves = math.max(0, env.cameraZoom - yards), env.moves + 1
        end
        env.CameraZoomOut = function(yards)
            env.cameraZoom, env.moves = math.min(39, env.cameraZoom + yards), env.moves + 1
        end
        env.GetCameraZoom = function() return env.cameraZoom end
        env.inWorld, env.indoors, env.resting, env.mounted = true, false, false, false
        env.taxi, env.vehicle = false, false
        env.IsPlayerInWorld = function() return env.inWorld end
        env.instanceType = "none"
        env.IsInInstance = function() return env.instanceType ~= "none", env.instanceType end
        env.IsIndoors = function() return env.indoors end
        env.IsResting = function() return env.resting end
        env.IsMounted = function() return env.mounted end
        env.UnitOnTaxi = function() return env.taxi end
        env.UnitInVehicle = function() return env.vehicle end
        return env
    end

    it("camera distance sets its CVar on enable and restores the default on disable", function()
        local env = cameraEnv()
        local camera = enable(env, "Modules/Interface/CameraDistance.lua", "interface.cameraDistance")
        assert.equal("2.60", env.cvars.cameraDistanceMaxZoomFactor)
        -- The slider writes the option; the module follows it without being re-enabled.
        assert.is_true(env.R.Settings:SetOption("cameraMaxZoom", 1.5))
        assert.equal("1.50", env.cvars.cameraDistanceMaxZoomFactor)
        assert.is_false(env.R.Settings:SetOption("cameraMaxZoom", 3))
        assert.is_false(env.R.Settings:SetOption("cameraMaxZoom", 0.5))
        assert.equal("1.50", env.cvars.cameraDistanceMaxZoomFactor)
        -- Another setting changing leaves the CVar unwritten.
        local writes = 0
        local set = env.C_CVar.SetCVar
        env.C_CVar.SetCVar = function(...) writes = writes + 1; set(...) end
        assert.is_true(env.R.Settings:SetOption("farmOpacity", 0.5))
        assert.equal(0, writes)
        env.C_CVar.SetCVar = set
        env.R.Registry:Disable(camera)
        assert.equal("1.9", env.cvars.cameraDistanceMaxZoomFactor)
        -- Off, the option moving changes nothing until the feature is on again.
        assert.is_true(env.R.Settings:SetOption("cameraMaxZoom", 2.2))
        assert.equal("1.9", env.cvars.cameraDistanceMaxZoomFactor)
        noResidue(env, camera)
    end)

    it("ActionCam applies Immersive, follows the situation, gives the wheel back, reverts", function()
        local env = cameraEnv()
        local action = enable(env, "Modules/Interface/ActionCam.lua", "interface.actionCam")
        local cvars = env.cvars
        assert.is_true(env.hidden.EXPERIMENTAL_CVAR_WARNING)
        assert.same({}, env.console)
        assert.equal("1", cvars.test_cameraDynamicPitch)
        assert.equal("0.60", cvars.test_cameraOverShoulder)
        assert.equal("0.30", cvars.test_cameraHeadMovementStrength)
        assert.equal("1", cvars.test_cameraTargetFocusInteractEnable)
        assert.equal("0", cvars.test_cameraTargetFocusEnemyEnable)
        assert.equal("0", cvars.test_cameraTargetFocusEnemyStrengthYaw)
        -- Blizzard's motion sickness guard overrides every ActionCam CVar, so it is off.
        assert.equal("0", cvars.CameraKeepCharacterCentered)
        assert.equal(9, env.cameraZoom)
        -- The player wheels in. Indoors moves the camera; the same situation again does not.
        env.cameraZoom = 4
        env.indoors = true
        env:Fire("ZONE_CHANGED_INDOORS")
        assert.equal(4, env.cameraZoom)
        env:Advance(0)
        assert.equal("0.00", cvars.test_cameraOverShoulder)
        assert.equal(6, env.cameraZoom)
        local moves = env.moves
        env:Fire("ZONE_CHANGED")
        env:Advance(0)
        assert.equal(moves, env.moves)
        -- Mounted wins over indoors. A wheel while mounted is not what comes back later.
        env.mounted = true
        env:Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
        env:Advance(0)
        assert.equal(16, env.cameraZoom)
        env.cameraZoom = 12
        -- Another unit's vehicle event is not ours; the player's is.
        env.mounted, env.indoors, env.resting = false, false, true
        env:Fire("UNIT_EXITED_VEHICLE", "party1")
        env:Advance(0)
        assert.equal("0.00", cvars.test_cameraOverShoulder)
        env:Fire("UNIT_EXITED_VEHICLE", "player")
        env:Advance(0)
        assert.equal("0.30", cvars.test_cameraOverShoulder)
        assert.equal(12, env.cameraZoom)
        -- Combat wins over the rest area and leans into the shoulder.
        env.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        env:Advance(0)
        assert.equal("0.90", cvars.test_cameraOverShoulder)
        assert.equal(9, env.cameraZoom)
        -- Out of every situation: the camera goes back to where the player had it.
        env.combat, env.resting = false, false
        env:Fire("PLAYER_REGEN_ENABLED")
        env:Advance(0)
        assert.equal("0.60", cvars.test_cameraOverShoulder)
        assert.equal(4, env.cameraZoom)
        -- Off: every CVar back to the client's default, the guard back on, the camera left.
        moves = env.moves
        env.R.Registry:Disable(action)
        assert.equal("0", cvars.test_cameraOverShoulder)
        assert.equal("0", cvars.test_cameraDynamicPitch)
        assert.equal("0", cvars.test_cameraTargetFocusInteractEnable)
        assert.equal("0", cvars.test_cameraHeadMovementStrength)
        assert.equal("1", cvars.CameraKeepCharacterCentered)
        assert.equal(moves, env.moves)
        assert.equal(4, env.cameraZoom)
        noResidue(env, action)
    end)

    it("ActionCam on Melee leaves the wheel alone and gives it back when switched off", function()
        local env = cameraEnv()
        env.cameraZoom = 5
        assert.is_true(env.R.Settings:SetOption("cameraProfile", "melee"))
        local action = enable(env, "Modules/Interface/ActionCam.lua", "interface.actionCam")
        local cvars = env.cvars
        assert.equal(5, env.cameraZoom)
        assert.equal("1.00", cvars.test_cameraOverShoulder)
        assert.equal("1", cvars.test_cameraTargetFocusEnemyEnable)
        assert.equal("0.50", cvars.test_cameraTargetFocusEnemyStrengthYaw)
        assert.equal("0.40", cvars.test_cameraTargetFocusEnemyStrengthPitch)
        -- An NPC window changes the shoulder and nothing else.
        env:Fire("GOSSIP_SHOW")
        env:Advance(0)
        assert.equal("0.80", cvars.test_cameraOverShoulder)
        assert.equal(5, env.cameraZoom)
        env:Fire("GOSSIP_CLOSED", false)
        env:Advance(0)
        assert.equal(5, env.cameraZoom)
        -- A mount backs off; riding into a building, which Melee says nothing about,
        -- returns the camera to the pre-mount distance.
        env.mounted = true
        env:Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
        env:Advance(0)
        assert.equal(16, env.cameraZoom)
        env.mounted, env.indoors = false, true
        env:Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
        env:Advance(0)
        assert.equal(5, env.cameraZoom)
        assert.equal("0.60", cvars.test_cameraOverShoulder)
        -- Off while a mount had moved it: back to the player's own distance.
        env.mounted, env.indoors = true, false
        env:Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
        env:Advance(0)
        assert.equal(16, env.cameraZoom)
        env.R.Registry:Disable(action)
        assert.equal(5, env.cameraZoom)
        noResidue(env, action)
    end)

    it("ActionCam settles an NPC window in one tick and lets an instance win", function()
        local env = cameraEnv()
        enable(env, "Modules/Interface/ActionCam.lua", "interface.actionCam")
        local cvars = env.cvars
        env:Fire("GOSSIP_SHOW")
        env:Advance(0)
        assert.equal("0.80", cvars.test_cameraOverShoulder)
        assert.equal(5, env.cameraZoom)
        -- A gossip closing into a quest, and a close and reopen in the same tick, move nothing.
        local moves = env.moves
        env:Fire("GOSSIP_CLOSED", true)
        env:Advance(0)
        env:Fire("GOSSIP_CLOSED", false)
        env:Fire("QUEST_DETAIL")
        env:Advance(0)
        assert.equal(moves, env.moves)
        env:Fire("QUEST_FINISHED")
        env:Advance(0)
        assert.equal("0.60", cvars.test_cameraOverShoulder)
        assert.equal(9, env.cameraZoom)
        -- Inside an instance nothing else counts, combat included.
        env.instanceType = "party"
        env:Fire("ZONE_CHANGED_NEW_AREA")
        env:Advance(0)
        assert.equal("0.30", cvars.test_cameraOverShoulder)
        assert.equal(14, env.cameraZoom)
        moves = env.moves
        env.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        env:Advance(0)
        assert.equal(moves, env.moves)
        for _, case in ipairs({ { "raid", 24, "0.00" }, { "pvp", 16, "0.30" }, { "arena", 12, "0.50" },
            { "scenario", 14, "0.30" } }) do
            env.instanceType = case[1]
            env:Fire("PLAYER_ENTERING_WORLD", false, false)
            env:Advance(0)
            assert.equal(case[2], env.cameraZoom)
            assert.equal(case[3], cvars.test_cameraOverShoulder)
        end
        -- Out again, into combat in the open world: the combat distance, and the wheel
        -- position from before the first instance is still what comes back at the end.
        env.instanceType = "none"
        env:Fire("PLAYER_ENTERING_WORLD", false, false)
        env:Advance(0)
        assert.equal(9, env.cameraZoom)
        env.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        env:Advance(0)
        assert.equal(9, env.cameraZoom)
    end)

    it("ActionCam enabled at login waits for the world, then applies the profile", function()
        local env = cameraEnv()
        env.inWorld = false
        enable(env, "Modules/Interface/ActionCam.lua", "interface.actionCam")
        assert.is_nil(env.cvars.test_cameraDynamicPitch)
        assert.equal(20, env.cameraZoom)
        env:Fire("PLAYER_ENTERING_WORLD", true, false)
        assert.equal("1", env.cvars.test_cameraDynamicPitch)
        assert.equal("0.60", env.cvars.test_cameraOverShoulder)
        assert.equal(9, env.cameraZoom)
        env.indoors = true
        env:Fire("ZONE_CHANGED_INDOORS")
        env:Advance(0)
        assert.equal(6, env.cameraZoom)
        -- A loading screen that is not a login is a zone change: the situation is re-read.
        env.indoors = false
        env:Fire("PLAYER_ENTERING_WORLD", false, false)
        env:Advance(0)
        assert.equal(9, env.cameraZoom)
    end)

    it("ActionCam runs a Blizzard preset by console and switches profiles cleanly", function()
        local env = cameraEnv()
        enable(env, "Modules/Interface/ActionCam.lua", "interface.actionCam")
        local Settings, Profiles = env.R.Settings, env.R.CameraProfiles
        assert.is_true(Settings:SetOption("cameraProfile", "blizzardFull"))
        assert.same({ "actioncam full" }, env.console)
        assert.equal(9, env.cameraZoom)
        -- A preset knows nothing of situations: nothing moves and the shoulder is the
        -- client's own value, not one this module wrote.
        local moves = env.moves
        env.indoors = true
        env:Fire("ZONE_CHANGED_INDOORS")
        env:Advance(0)
        assert.equal(moves, env.moves)
        assert.equal("0", env.cvars.test_cameraOverShoulder)
        -- A switch made indoors: the new profile's indoor distance now, and what the player
        -- had before the building is still what comes back on the way out.
        assert.is_true(Settings:SetOption("cameraProfile", "controllerRanged"))
        assert.equal(8, env.cameraZoom)
        assert.equal("0.20", env.cvars.test_cameraOverShoulder)
        assert.equal("0.00", env.cvars.test_cameraHeadMovementStrength)
        -- A gentle pull: the yaw strength is the slider, the pitch follows at Blizzard's ratio.
        assert.equal("1", env.cvars.test_cameraTargetFocusEnemyEnable)
        assert.equal("0.30", env.cvars.test_cameraTargetFocusEnemyStrengthYaw)
        assert.equal("0.24", env.cvars.test_cameraTargetFocusEnemyStrengthPitch)
        -- A copy edits live: the shoulder reaches the camera at once, a distance for the
        -- situation in play moves it, one for any other situation leaves it alone, and
        -- setting the situation in play to leave the camera gives the wheel back.
        assert.is_true(Profiles:SaveCopy("Mine", Profiles:Active().values))
        assert.equal(8, env.cameraZoom)
        assert.is_true(Profiles:SetField("indoorsShoulder", 1.2))
        assert.equal("1.20", env.cvars.test_cameraOverShoulder)
        moves = env.moves
        assert.is_true(Profiles:SetField("raidDistance", 30))
        assert.equal(moves, env.moves)
        assert.is_true(Profiles:SetField("indoorsDistance", 5))
        assert.equal(5, env.cameraZoom)
        assert.is_true(Profiles:SetField("indoorsDistance", Profiles.LEAVE))
        assert.equal(9, env.cameraZoom)
        env.indoors = false
        env:Fire("ZONE_CHANGED_INDOORS")
        env:Advance(0)
        assert.equal(9, env.cameraZoom)
    end)

    it("screenshots after a delay and cancels the timer on disable", function()
        local env = base()
        local shots = 0
        env.Screenshot = function() shots = shots + 1 end
        local module = enable(env, "Modules/Interface/ScreenshotLevelUp.lua", "interface.screenshotLevelUp")
        env:Fire("PLAYER_LEVEL_UP", 10, 0, 0, 0, 0)
        env:Advance(1)
        assert.equal(0, shots)
        env:Advance(1)
        assert.equal(1, shots)
        env:Fire("PLAYER_LEVEL_UP", 11, 0, 0, 0, 0)
        noResidue(env, module)
        assert.equal(1, shots)
    end)

    local function merchantEnv()
        local env = base(true)
        env:Load("UI/Search.lua")
        env:Load("UI/Widgets/Widgets.lua")
        env:Load("UI/VendorPanel.lua")
        env.MerchantFrame = env.CreateFrame("Frame", "MerchantFrame")
        env.MerchantFrame:Show()
        env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 1
        env.bags = {
            { itemID = 1, quality = 0, stackCount = 3, hyperlink = "item:1" },
            { itemID = 2, quality = 1, stackCount = 1, hyperlink = "item:2" },
            { itemID = 3, quality = 0, stackCount = 1, hyperlink = "item:3", hasNoValue = true },
            { itemID = 4, quality = 0, stackCount = 2, hyperlink = "item:4" },
        }
        env.C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and #env.bags or 0 end,
            GetContainerItemInfo = function(_, slot) return env.bags[slot] end,
        }
        env.C_Item = {
            GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 100 end,
            GetItemQualityByID = function() return 2 end,
            GetItemQualityColor = function() return 0, 1, 0 end,
        }
        return env
    end

    local function gridEnv()
        local env = merchantEnv()
        env:Load("UI/MerchantCosts.lua")
        env:Load("UI/MerchantGrid.lua")
        for index = 1, 12 do
            env.CreateFrame("Frame", "MerchantItem" .. index, env.MerchantFrame)
        end
        env.CreateFrame("Frame", "MerchantBuyBackItem", env.MerchantFrame)
        env.CreateFrame("Button", "MerchantNextPageButton", env.MerchantFrame)
        env.MerchantFrameBottomLeftBorder = env.MerchantFrame:CreateTexture()
        env.MERCHANT_ITEMS_PER_PAGE, env.BUYBACK_ITEMS_PER_PAGE = 10, 12
        env.MerchantFrame.selectedTab, env.MerchantFrame.page = 1, 3
        env.hooks, env.updates = {}, 0
        -- Chained in the order installed, as the client chains them.
        env.hooksecurefunc = function(name, fn)
            local previous = env.hooks[name]
            env.hooks[name] = previous and function() previous() fn() end or fn
        end
        env.MerchantFrame_Update = function()
            env.updates = env.updates + 1
            if env.hooks.MerchantFrame_Update then env.hooks.MerchantFrame_Update() end
        end
        return env
    end

    it("reshapes Blizzard's merchant window from the options and puts it back on disable", function()
        local env = gridEnv()
        local module = enable(env, "Modules/Vendor/ExtendedUI.lua", "vendor.extendedUI")
        local grid = module.grid
        -- Three by six: eighteen a page, one column wider than Blizzard's, a row taller.
        assert.equal(18, env.MERCHANT_ITEMS_PER_PAGE)
        assert.equal(501, grid.width)
        assert.equal(496, grid.height)
        assert.equal("MerchantItemTemplate", env.MerchantItem40.template)
        assert.is_nil(env.MerchantItem41)
        -- Open at enable: back to page one through Blizzard's own update, then the hook.
        assert.equal(1, env.updates)
        assert.equal(1, env.MerchantFrame.page)
        assert.is_true(env.MerchantItem18:IsShown())
        assert.is_false(env.MerchantItem19:IsShown())
        -- The buyback tab fills twelve cells whatever the page size.
        env.MerchantFrame.selectedTab = 2
        env.MerchantFrame_Update()
        assert.is_true(env.MerchantItem12:IsShown())
        assert.is_false(env.MerchantItem13:IsShown())
        env.MerchantFrame.selectedTab = 1
        assert.is_true(env.R.Settings:SetOption("vendorColumns", 2))
        assert.equal(12, env.MERCHANT_ITEMS_PER_PAGE)
        assert.equal(336, grid.width)
        assert.equal(496, grid.height)
        assert.is_true(env.MerchantItem12:IsShown())
        assert.is_false(env.MerchantItem13:IsShown())
        assert.is_false(env.R.Settings:SetOption("vendorColumns", 1))
        assert.is_false(env.R.Settings:SetOption("vendorColumns", 6))
        assert.is_false(env.R.Settings:SetOption("vendorRows", 9))
        assert.is_false(env.R.Settings:SetOption("vendorRows", 2.5))
        env.R.Registry:Disable(module)
        assert.equal(10, env.MERCHANT_ITEMS_PER_PAGE)
        assert.is_false(env.MerchantItem13:IsShown())
        assert.is_false(grid.active)
        -- The hook stays installed and does nothing while the module is off.
        env.MerchantFrame_Update()
        assert.is_false(grid.active)
        noResidue(env, module)
        assert.equal(10, env.MERCHANT_ITEMS_PER_PAGE)
    end)

    it("waits for combat to end before reshaping the merchant window", function()
        local env = gridEnv()
        local module = enable(env, "Modules/Vendor/ExtendedUI.lua", "vendor.extendedUI")
        env.combat = true
        assert.is_true(env.R.Settings:SetOption("vendorRows", 8))
        assert.is_true(env.R.Settings:SetOption("vendorColumns", 4))
        assert.equal(18, env.MERCHANT_ITEMS_PER_PAGE)
        env.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        assert.equal(32, env.MERCHANT_ITEMS_PER_PAGE)
        assert.equal(666, module.grid.width)
        for _, entry in ipairs(env.R.Broker.events.PLAYER_REGEN_ENABLED or {}) do
            assert.is_not.equal(module, entry.owner)
        end
        noResidue(env, module)
    end)
end)

describe("M4 merchant costs", function()
    local Runtime2 = require("Tests.mock.runtime")
    local Widgets2 = require("Tests.mock.widgets")

    local INTEGRATIONS = { "Integrations/Questie.lua", "Integrations/Plater.lua", "Integrations/Plumber.lua" }

    local function costEnv()
        local env = Runtime2.new()
        Widgets2.install(env)
        for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Features.enUS.lua",
            "Locales/Panels.enUS.lua" }) do
            env:Load(path)
        end
        env.R.UI = env.R.UI or {}
        -- The module asks its neighbours before drawing; none are installed unless a spec says so.
        for _, path in ipairs(INTEGRATIONS) do
            env:Load(path)
        end
        env.C_AddOns = { IsAddOnLoaded = function() return false end }
        env:Load("UI/MerchantCosts.lua")
        env.MerchantFrame = env.CreateFrame("Frame", "MerchantFrame")
        env.MerchantFrame:Show()
        env.MerchantFrame.selectedTab, env.MerchantFrame.page = 1, 1
        for index = 1, 12 do
            local cell = env.CreateFrame("Frame", "MerchantItem" .. index, env.MerchantFrame)
            env.CreateFrame("ItemButton", "MerchantItem" .. index .. "ItemButton", cell)
            local alt = env.CreateFrame("Frame", "MerchantItem" .. index .. "AltCurrencyFrame", cell)
            for cost = 1, 3 do
                env.CreateFrame("Button", "MerchantItem" .. index .. "AltCurrencyFrameItem" .. cost, alt)
            end
            env.CreateFrame("Frame", "MerchantItem" .. index .. "MoneyFrame", cell)
        end
        env.MERCHANT_ITEMS_PER_PAGE, env.MAX_ITEM_COST = 10, 3
        env.hooks, env.updates, env.money = {}, 0, 1000
        -- Chained in the order installed, as the client chains them.
        env.hooksecurefunc = function(name, fn)
            local previous = env.hooks[name]
            env.hooks[name] = previous and function() previous() fn() end or fn
        end
        -- Blizzard's pass, reduced to the ids it leaves on the item buttons.
        env.MerchantFrame_Update = function()
            env.updates = env.updates + 1
            for cellIndex = 1, env.MERCHANT_ITEMS_PER_PAGE do
                local button = env["MerchantItem" .. cellIndex .. "ItemButton"]
                local index = (env.MerchantFrame.page - 1) * env.MERCHANT_ITEMS_PER_PAGE + cellIndex
                button:SetID(index)
                button.hasItem = index <= #env.stock or nil
                button:SetShown(button.hasItem == true)
            end
            if env.hooks.MerchantFrame_Update then env.hooks.MerchantFrame_Update() end
        end
        env.currencyUpdates, env.currencyList = 0, {}
        env.MerchantFrame_UpdateCurrencies = function() env.currencyUpdates = env.currencyUpdates + 1 end
        env.MAX_MERCHANT_CURRENCIES = 6
        env.GameTooltip = env.CreateFrame("GameTooltip", "GameTooltip")
        for _, name in ipairs({ "MerchantMoneyFrame", "MerchantMoneyInset", "MerchantMoneyBg",
            "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg" }) do
            env.CreateFrame("Frame", name, env.MerchantFrame)
        end
        env.MerchantMoneyFrame:SetWidth(100)
        env.stock = {}
        env.GetMerchantNumItems = function() return #env.stock end
        env.C_MerchantFrame = {
            GetItemInfo = function(index) return env.stock[index] end,
            GetMerchantCurrencies = function() return env.currencyList end,
        }
        env.CanAffordMerchantItem = function(index) return env.stock[index].canAfford end
        env.GetMerchantItemCostInfo = function(index) return #env.stock[index].costs end
        env.GetMerchantItemCostItem = function(index, cost)
            local entry = env.stock[index].costs[cost]
            if not entry then return nil end
            return entry.texture, entry.value, entry.link, entry.currency
        end
        env.GetMoney = function() return env.money end
        env.currencies, env.items = {}, {}
        env.C_CurrencyInfo = { GetCurrencyInfoFromLink = function(link) return env.currencies[link] end }
        env.C_Item = { GetItemCount = function(link) return env.items[link] or 0 end }
        env.shown, env.moneyColor = {}, {}
        env.AltCurrencyFrame_Update = function(name, _, _, canAfford) env.shown[name] = canAfford end
        env.SetMoneyFrameColor = function(name, color) env.moneyColor[name] = color or "default" end
        env.MoneyFrame_SetMaxDisplayWidth = function() end
        env.MoneyFrame_Update = function() end
        return env
    end

    local function cost(texture, value, link, currency)
        return { texture = texture, value = value, link = link, currency = currency }
    end

    it("greys only the cost that is short and shows a fourth and fifth cost", function()
        local env = costEnv()
        env.currencies["currency:1"] = { quantity = 5 }
        env.currencies["currency:2"] = { quantity = 50 }
        env.items["item:9"] = 3
        env.stock = {
            -- Short of one currency, has the item and the gold: only that currency greys.
            { hasExtendedCost = true, price = 500, canAfford = false,
                costs = { cost(1, 10, "currency:1", "Marks"), cost(2, 2, "item:9") } },
            -- Affordable with five costs: all white, two of them past Blizzard's three.
            { hasExtendedCost = true, price = 0, canAfford = true,
                costs = { cost(1, 1, "currency:2", "Marks"), cost(1, 1, "currency:2", "Marks"),
                    cost(1, 1, "currency:2", "Marks"), cost(2, 1, "item:9"), cost(2, 1, "item:9") } },
            -- Unaffordable and nothing can be told short: everything greys, as Blizzard does.
            { hasExtendedCost = true, price = 0, canAfford = false,
                costs = { cost(3, 1, nil, "Unknown"), cost(2, 1, "item:9") } },
            -- Short of gold only: the currency stays white, the money greys.
            { hasExtendedCost = true, price = 5000, canAfford = false,
                costs = { cost(1, 1, "currency:2", "Marks") } },
            { hasExtendedCost = false, price = 10, canAfford = true, costs = {} },
        }
        env.MerchantFrame_Update()
        local module = enable(env, "Modules/Vendor/ItemCosts.lua", "vendor.itemCosts")
        assert.equal(1, env.updates)
        assert.is_false(env.shown.MerchantItem1AltCurrencyFrameItem1)
        assert.is_true(env.shown.MerchantItem1AltCurrencyFrameItem2)
        assert.equal("default", env.moneyColor.MerchantItem1MoneyFrame)
        assert.is_true(env.shown.MerchantItem2AltCurrencyFrameItem5)
        assert.is_true(env.MerchantItem2AltCurrencyFrameItem5:IsShown())
        assert.equal("SmallDenominationTemplate", env.MerchantItem2AltCurrencyFrameItem5.template)
        assert.equal(2, env.MerchantItem2AltCurrencyFrameItem5.index)
        assert.equal(5, env.MerchantItem2AltCurrencyFrameItem5.item)
        assert.is_false(env.MerchantItem1AltCurrencyFrameItem4:IsShown())
        assert.is_false(env.shown.MerchantItem3AltCurrencyFrameItem1)
        assert.is_false(env.shown.MerchantItem3AltCurrencyFrameItem2)
        assert.is_true(env.shown.MerchantItem4AltCurrencyFrameItem1)
        assert.equal("gray", env.moneyColor.MerchantItem4MoneyFrame)
        assert.is_nil(env.shown.MerchantItem5AltCurrencyFrameItem1)
        -- The one item this merchant takes sits in the strip with the carried count, next
        -- to the money, in the stretched left box; the right box is gone.
        local token = env.RefactorMerchantToken1
        assert.is_true(token:IsShown())
        assert.equal("item:9", token.itemLink)
        assert.equal(1, token.slot)
        assert.equal(3, token.Count.text)
        assert.is_false(env.RefactorMerchantToken2:IsShown())
        assert.is_true(env.MerchantExtraCurrencyInset:IsShown())
        assert.is_false(env.MerchantMoneyInset:IsShown())
        assert.is_true(env.MerchantMoneyFrame:IsShown())
        -- A later page maps cells to the items on it, and the buyback tab is left alone.
        for index = 6, 10 do
            env.stock[index] = env.stock[5]
        end
        env.stock[11] = env.stock[1]
        env.MerchantFrame.page = 2
        env.shown = {}
        env.MerchantFrame_Update()
        assert.is_false(env.shown.MerchantItem1AltCurrencyFrameItem1)
        assert.is_nil(env.shown.MerchantItem2AltCurrencyFrameItem1)
        env.MerchantFrame.selectedTab, env.shown = 2, {}
        env.MerchantFrame_Update()
        assert.same({}, env.shown)
        env.MerchantFrame.selectedTab = 1
        env.R.Registry:Disable(module)
        assert.is_false(env.MerchantItem2AltCurrencyFrameItem5:IsShown())
        assert.is_false(env.RefactorMerchantToken1:IsShown())
        assert.is_true(env.MerchantMoneyInset:IsShown())
        assert.equal(4, env.updates)
        assert.equal(1, env.currencyUpdates)
        noResidue(env, module)
    end)

    it("stands down when Plumber's Merchant Price module is on, and only then", function()
        local env = costEnv()
        env.C_AddOns = { IsAddOnLoaded = function(name) return name == "Plumber" end }
        env.stock = { { hasExtendedCost = false, price = 10, canAfford = true, costs = {} } }
        env.MerchantFrame_Update()
        -- Loaded with the feature off: Refactor draws.
        env.PlumberDB = { MerchantPrice = false }
        local module = enable(env, "Modules/Vendor/ItemCosts.lua", "vendor.itemCosts")
        assert.equal("enabled", module.state)
        assert.is_not_nil(env.RefactorMerchantToken1)
        noResidue(env, module)
        -- The feature on: the module names Plumber and creates nothing.
        env.PlumberDB.MerchantPrice = true
        env.R.Registry:Enable(module)
        assert.equal("unavailable", module.state)
        assert.matches("Plumber", module.unavailableReason)
        env.R.Registry:Disable(module)
    end)

    it("chains item tokens after the money and the merchant's currencies, as many as fit", function()
        local env = costEnv()
        -- Two currency tokens as Blizzard leaves them: shown, 50 wide.
        for slot = 1, 2 do
            local token = env.CreateFrame("Button", "MerchantToken" .. slot, env.MerchantFrame, "BackpackTokenTemplate")
            token:SetWidth(50)
            token:Show()
        end
        env.items["item:1"], env.items["item:2"], env.items["item:3"] = 1, 200000, 0
        env.stock = {
            { hasExtendedCost = true, price = 0, canAfford = true,
                costs = { cost(1, 1, "item:1"), cost(1, 1, "item:2") } },
            { hasExtendedCost = true, price = 0, canAfford = true,
                costs = { cost(1, 1, "item:1"), cost(1, 1, "item:3"), cost(9, 1, "currency:101", "Marks") } },
        }
        env.MerchantFrame_Update()
        local module = enable(env, "Modules/Vendor/ItemCosts.lua", "vendor.itemCosts")
        -- A wide window: money stays, both currencies and all three items follow it.
        assert.is_true(env.MerchantMoneyFrame:IsShown())
        assert.same({ 3, 4, 5 }, { env.RefactorMerchantToken1.slot, env.RefactorMerchantToken2.slot,
            env.RefactorMerchantToken3.slot })
        assert.equal("*", env.RefactorMerchantToken2.Count.text)
        assert.equal(0, env.RefactorMerchantToken3.Count.text)
        assert.is_false(env.RefactorMerchantToken4:IsShown())
        -- Blizzard's stock window: 312 usable, money 100 and its gap, two currencies 100,
        -- room left for two items of the three.
        env.MerchantFrame:SetWidth(336)
        env.MerchantFrame_Update()
        assert.is_true(env.MerchantMoneyFrame:IsShown())
        assert.is_true(env.RefactorMerchantToken2:IsShown())
        assert.is_false(env.RefactorMerchantToken3:IsShown())
        -- Five currencies: money would not fit beside them, so it gives way as it does
        -- in Blizzard's layout, and 62 is left, room for one item.
        for slot = 3, 5 do
            local token = env.CreateFrame("Button", "MerchantToken" .. slot, env.MerchantFrame, "BackpackTokenTemplate")
            token:SetWidth(50)
            token:Show()
        end
        env.MerchantFrame_Update()
        assert.is_false(env.MerchantMoneyFrame:IsShown())
        assert.is_true(env.RefactorMerchantToken1:IsShown())
        assert.is_false(env.RefactorMerchantToken2:IsShown())
        noResidue(env, module)
    end)
end)

describe("M4 merchant filter", function()
    local Runtime3 = require("Tests.mock.runtime")
    local Widgets3 = require("Tests.mock.widgets")

    local MISC, RECIPE, ARMOR, PET = 15, 9, 4, 2
    local function filterEnv(perPage)
        local env = Runtime3.new()
        Widgets3.install(env)
        for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Features.enUS.lua" }) do
            env:Load(path)
        end
        env.R.UI = env.R.UI or {}
        env:Load("UI/MerchantFilter.lua")
        env.MerchantFrame = env.CreateFrame("Frame", "MerchantFrame")
        env.MerchantFrame:Show()
        env.MerchantFrame.selectedTab, env.MerchantFrame.page = 1, 1
        env.MerchantFrame.FilterDropdown = env.CreateFrame("DropdownButton", nil, env.MerchantFrame)
        for index = 1, 12 do
            local cell = env.CreateFrame("Frame", "MerchantItem" .. index, env.MerchantFrame)
            local button = env.CreateFrame("ItemButton", "MerchantItem" .. index .. "ItemButton", cell)
            button.IconQuestTexture = button:CreateTexture()
            env.CreateFrame("Frame", "MerchantItem" .. index .. "MoneyFrame", cell)
            env.CreateFrame("Frame", "MerchantItem" .. index .. "AltCurrencyFrame", cell)
            env["MerchantItem" .. index .. "Name"] = cell:CreateFontString()
        end
        for _, name in ipairs({ "MerchantPrevPageButton", "MerchantNextPageButton" }) do
            env.CreateFrame("Button", name, env.MerchantFrame)
        end
        env.MerchantPageText = env.MerchantFrame:CreateFontString()
        env.MERCHANT_ITEMS_PER_PAGE, env.MERCHANT_PAGE_NUMBER = perPage or 10, "Page %d of %d"
        env.TEXTURE_ITEM_QUEST_BANG, env.ITEM_SPELL_KNOWN = "bang", "Already known"
        env.hooks, env.updates = {}, 0
        -- Chained in the order installed, as the client chains them.
        env.hooksecurefunc = function(name, fn)
            local previous = env.hooks[name]
            env.hooks[name] = previous and function() previous() fn() end or fn
        end
        -- Blizzard's own pass, reduced to what the filter has to undo: cell i shows item
        -- (page - 1) * perPage + i.
        env.MerchantFrame_Update = function()
            env.updates = env.updates + 1
            for cellIndex = 1, env.MERCHANT_ITEMS_PER_PAGE do
                local button = env["MerchantItem" .. cellIndex .. "ItemButton"]
                local index = (env.MerchantFrame.page - 1) * env.MERCHANT_ITEMS_PER_PAGE + cellIndex
                button:SetID(index)
                button.hasItem = index <= env.GetMerchantNumItems() or nil
                button:SetShown(button.hasItem == true)
            end
            if env.hooks.MerchantFrame_Update then env.hooks.MerchantFrame_Update() end
        end
        env.MerchantFrame_UpdateItemQualityBorders = function()
            env.hooks.MerchantFrame_UpdateItemQualityBorders()
        end
        env.Enum = { ItemClass = { Miscellaneous = MISC, Recipe = RECIPE, Armor = ARMOR, Weapon = 2 },
            ItemMiscellaneousSubclass = { CompanionPet = PET } }
        -- itemID: class, subclass, and which collection it belongs to with its state
        env.items = {
            [1] = { class = MISC, sub = 5, mount = 100, owned = true },
            [2] = { class = MISC, sub = 5, mount = 101, owned = false },
            [3] = { class = MISC, sub = PET, species = 7, owned = false },
            [4] = { class = MISC, sub = 0, toy = true, owned = true },
            [5] = { class = RECIPE, sub = 1, known = true },
            [6] = { class = 0, sub = 0 },
            [7] = { class = ARMOR, sub = 1, appearance = true, owned = false },
        }
        env.GetMerchantNumItems = function() return 7 end
        env.GetMerchantItemLink = function(index) return "|Hitem:" .. index .. ":|h" end
        env.GetMerchantItemID = function(index) return index end
        env.C_MerchantFrame = {
            GetItemInfo = function(index)
                return { name = "Item " .. index, texture = index, price = index * 100, stackCount = 1,
                    numAvailable = -1, isPurchasable = true, isUsable = index ~= 7, hasExtendedCost = index == 3 }
            end,
            IsMerchantItemRefundable = function() return true end,
        }
        env.CanAffordMerchantItem = function(index) return index ~= 2 end
        env.CurrencyContainerUtil = { GetCurrencyContainerInfo = function() end }
        env.C_Heirloom = { IsItemHeirloom = function() return false end,
            PlayerHasHeirloom = function() return false end }
        env.tints, env.quality, env.costRows = {}, {}, {}
        for _, name in ipairs({ "SetItemButtonCount", "SetItemButtonStock", "SetItemButtonTexture",
            "SetItemButtonDesaturated", "SetItemButtonSlotVertexColor", "SetItemButtonTextureVertexColor",
            "SetItemButtonNormalTextureVertexColor", "MoneyFrame_SetMaxDisplayWidth", "MoneyFrame_Update",
            "SetMoneyFrameColor" }) do
            env[name] = function() end
        end
        env.SetItemButtonNameFrameVertexColor = function(cell, r, g, b) env.tints[cell.name] = { r, g, b } end
        env.MerchantFrameItem_UpdateQuality = function(cell, link) env.quality[cell.name] = link end
        env.MerchantFrame_UpdateAltCurrency = function(index, cellIndex) env.costRows[cellIndex] = index return 20 end
        env.C_Item = { GetItemInfoInstant = function(itemID)
            local item = env.items[itemID]
            return itemID, "", "", "", 0, item.class, item.sub
        end }
        env.C_MountJournal = {
            GetMountFromItem = function(itemID) return env.items[itemID].mount end,
            GetMountInfoByID = function(mountID)
                for _, item in pairs(env.items) do
                    if item.mount == mountID then
                        return "m", 0, 0, false, true, 0, false, false, nil, false, item.owned, mountID
                    end
                end
            end,
        }
        env.C_PetJournal = {
            GetPetInfoByItemID = function(itemID)
                local item = env.items[itemID]
                if not item.species then return nil end
                return "p", 0, 0, 0, "", "", false, true, true, false, true, 0, item.species
            end,
            GetNumCollectedInfo = function(species)
                for _, item in pairs(env.items) do
                    if item.species == species then return item.owned and 1 or 0, 3 end
                end
            end,
        }
        env.C_ToyBox = { GetToyInfo = function(itemID) return env.items[itemID].toy and itemID or nil end }
        env.PlayerHasToy = function(itemID) return env.items[itemID].owned == true end
        env.C_TransmogCollection = {
            GetItemInfo = function(itemID) return env.items[itemID].appearance and 1 or nil end,
            PlayerHasTransmogByItemInfo = function(link)
                return env.items[tonumber(link:match("item:(%d+)"))].owned == true
            end,
        }
        env.tooltips = 0
        env.C_TooltipInfo = { GetMerchantItem = function(index)
            env.tooltips = env.tooltips + 1
            return { lines = { { leftText = env.items[index].known and "Already known" or "Teaches you" } } }
        end }
        env.filtered = 0
        env.R.Broker:Subscribe("REFACTOR_MERCHANT_FILTERED", function() env.filtered = env.filtered + 1 end, env)
        env.MerchantFrame_Update()
        return env
    end

    -- The merchant index in each cell of the page, 0 for an empty slot.
    local function page(env)
        local result = {}
        for cellIndex = 1, env.MERCHANT_ITEMS_PER_PAGE do
            local button = env["MerchantItem" .. cellIndex .. "ItemButton"]
            result[cellIndex] = button:IsShown() and button.hasItem and button:GetID() or 0
        end
        return result
    end

    local function pick(env, text)
        for _, entry in ipairs(env.R.moduleByID["vendor.filter"].filter.button:OpenMenu()) do
            if entry.text == text then entry.choose() return end
        end
        error("no menu entry " .. text)
    end

    it("lays the matching stock out from the first cell and leaves Blizzard's page alone otherwise", function()
        local env = filterEnv(10)
        local module = enable(env, "Modules/Vendor/Filter.lua", "vendor.filter")
        local filter = module.filter
        assert.is_true(filter.button:IsShown())
        assert.equal("Everything", filter.button:GetDefaultText())
        assert.same({ 1, 2, 3, 4, 5, 6, 7, 0, 0, 0 }, page(env))
        pick(env, "Mounts")
        assert.equal("Mounts", filter.button:GetDefaultText())
        assert.same({ 1, 2, 0, 0, 0, 0, 0, 0, 0, 0 }, page(env))
        pick(env, "Missing")
        assert.equal("Mounts, Missing", filter.button:GetDefaultText())
        assert.same({ 2, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, page(env))
        -- The cell is filled the way Blizzard fills it: name plate tint, quality, costs.
        assert.same({ 0.5, 0.5, 0.5 }, env.tints.MerchantItem1)
        assert.equal("|Hitem:2:|h", env.quality.MerchantItem1)
        assert.equal("", env.MerchantItem2Name:GetText())
        pick(env, "Everything")
        assert.equal("Missing", filter.button:GetDefaultText())
        -- Missing across every kind: the unowned mount, pet and appearance. Food has no
        -- collection to be missing from, and a known recipe is owned.
        assert.same({ 2, 3, 7, 0, 0, 0, 0, 0, 0, 0 }, page(env))
        assert.equal(3, env.costRows[2])
        assert.same({ 1, 0, 0 }, env.tints.MerchantItem3)
        pick(env, "Owned")
        assert.same({ 1, 4, 5, 0, 0, 0, 0, 0, 0, 0 }, page(env))
        -- Late quality data is reapplied to the cells as laid out here.
        env.quality = {}
        env.MerchantFrame_UpdateItemQualityBorders()
        assert.equal("|Hitem:4:|h", env.quality.MerchantItem2)
        assert.is_nil(env.quality.MerchantItem4)
        -- The buyback tab is Blizzard's; back on the merchant tab the layout returns.
        env.MerchantFrame.selectedTab = 2
        env.costRows = {}
        env.MerchantFrame_Update()
        assert.same({}, env.costRows)
        env.MerchantFrame.selectedTab = 1
        env.MerchantFrame_Update()
        assert.same({ 1, 4, 5, 0, 0, 0, 0, 0, 0, 0 }, page(env))
        -- The recipe's tooltip is read once per visit.
        local reads = env.tooltips
        env.MerchantFrame_Update()
        assert.equal(reads, env.tooltips)
        env:Fire("NEW_RECIPE_LEARNED")
        assert.is_true(env.tooltips > reads)
        -- A new merchant starts from everything, through Blizzard's own pass.
        local updates = env.updates
        env:Fire("MERCHANT_SHOW")
        assert.equal("Everything", filter.button:GetDefaultText())
        assert.equal(updates + 1, env.updates)
        assert.same({ 1, 2, 3, 4, 5, 6, 7, 0, 0, 0 }, page(env))
        pick(env, "Toys")
        assert.is_true(env.filtered > 0)
        env.R.Registry:Disable(module)
        assert.same({ 1, 2, 3, 4, 5, 6, 7, 0, 0, 0 }, page(env))
        assert.is_false(filter.button:IsShown())
        noResidue(env, module)
    end)

    -- The costs module on top of the filter: whichever hook Blizzard's pass reaches first,
    -- a filtered page ends with its emptied cells bare and its filled cells recoloured.
    local function withCosts(env)
        env:Load("Locales/Panels.enUS.lua")
        for _, path in ipairs({ "Integrations/Questie.lua", "Integrations/Plater.lua", "Integrations/Plumber.lua" }) do
            env:Load(path)
        end
        env.C_AddOns = { IsAddOnLoaded = function() return false end }
        env:Load("UI/MerchantCosts.lua")
        for index = 1, 12 do
            local alt = env["MerchantItem" .. index .. "AltCurrencyFrame"]
            for cost = 1, 3 do
                env.CreateFrame("Button", "MerchantItem" .. index .. "AltCurrencyFrameItem" .. cost, alt)
            end
        end
        env.MAX_ITEM_COST, env.MAX_MERCHANT_CURRENCIES = 3, 6
        env.GameTooltip = env.CreateFrame("GameTooltip", "GameTooltip")
        for _, name in ipairs({ "MerchantMoneyFrame", "MerchantMoneyInset", "MerchantMoneyBg",
            "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg" }) do
            env.CreateFrame("Frame", name, env.MerchantFrame)
        end
        env.MerchantFrame_UpdateCurrencies = function() end
        env.C_MerchantFrame.GetMerchantCurrencies = function() return {} end
        env.GetMoney = function() return 0 end
        env.GetMerchantItemCostInfo = function(index) return index == 3 and 1 or 0 end
        env.GetMerchantItemCostItem = function(index, cost)
            if index == 3 and cost == 1 then return 77, 2, "|Hitem:9:|h", nil end
        end
        env.C_CurrencyInfo = { GetCurrencyInfoFromLink = function() return nil end }
        env.C_Item.GetItemCount = function() return 1 end
        -- Item 3 costs two of an item the player has one of, so Blizzard calls it unaffordable.
        env.CanAffordMerchantItem = function(index) return index ~= 2 and index ~= 3 end
        env.greys = {}
        env.AltCurrencyFrame_Update = function(name, _, _, white) env.greys[name] = white end
        -- Blizzard's pass shows the cost row of every cell it fills with an extended cost.
        local blizzard = env.MerchantFrame_Update
        env.MerchantFrame_Update = function()
            for cellIndex = 1, env.MERCHANT_ITEMS_PER_PAGE do
                local index = (env.MerchantFrame.page - 1) * env.MERCHANT_ITEMS_PER_PAGE + cellIndex
                env["MerchantItem" .. cellIndex .. "AltCurrencyFrame"]:SetShown(index == 3)
                env["MerchantItem" .. cellIndex .. "AltCurrencyFrameItem1"]:SetShown(index == 3)
            end
            blizzard()
        end
        return env
    end

    local function altShown(env)
        local result = {}
        for cellIndex = 1, env.MERCHANT_ITEMS_PER_PAGE do
            result[cellIndex] = env["MerchantItem" .. cellIndex .. "AltCurrencyFrame"]:IsShown()
        end
        return result
    end

    for _, order in ipairs({ { "costs", "filter" }, { "filter", "costs" } }) do
        it("leaves no cost row on an emptied cell with the " .. order[1] .. " hook first", function()
            local env = withCosts(filterEnv(10))
            local modules = {}
            for _, which in ipairs(order) do
                if which == "costs" then
                    modules[#modules + 1] = enable(env, "Modules/Vendor/ItemCosts.lua", "vendor.itemCosts")
                else
                    modules[#modules + 1] = enable(env, "Modules/Vendor/Filter.lua", "vendor.filter")
                end
            end
            env.MerchantFrame_Update()
            assert.same({ false, false, true, false, false, false, false, false, false, false }, altShown(env))
            pick(env, "Missing")
            -- Items 2, 3 and 7 from the first cell: only the second cell, item 3, has a cost
            -- row, greyed for its own shortfall, and the cells past the third are bare.
            assert.same({ 2, 3, 7, 0, 0, 0, 0, 0, 0, 0 }, page(env))
            assert.same({ false, true, false, false, false, false, false, false, false, false }, altShown(env))
            assert.is_false(env.greys.MerchantItem2AltCurrencyFrameItem1)
            -- An emptied cell hides its cost buttons themselves, not only their row.
            assert.is_false(env.MerchantItem4AltCurrencyFrameItem1:IsShown())
            for _, module in ipairs(modules) do
                env.R.Registry:Disable(module)
            end
        end)
    end

    it("pages the filtered stock by its own count and clamps a page that no longer exists", function()
        local env = filterEnv(2)
        local module = enable(env, "Modules/Vendor/Filter.lua", "vendor.filter")
        env.MerchantFrame.page = 4
        env.MerchantFrame_Update()
        assert.same({ 7, 0 }, page(env))
        assert.equal(4, env.MerchantFrame.page)
        pick(env, "Missing")
        -- Three matches on pages of two: page four becomes page two, the last one.
        assert.equal(2, env.MerchantFrame.page)
        assert.same({ 7, 0 }, page(env))
        assert.equal("Page 2 of 2", env.MerchantPageText:GetText())
        assert.is_true(env.MerchantPrevPageButton:IsEnabled())
        assert.is_false(env.MerchantNextPageButton:IsEnabled())
        env.MerchantFrame.page = 1
        env.MerchantFrame_Update()
        assert.same({ 2, 3 }, page(env))
        assert.is_false(env.MerchantPrevPageButton:IsEnabled())
        assert.is_true(env.MerchantNextPageButton:IsEnabled())
        -- The one toy is owned, so Toys with Missing is an empty page, and Toys alone fits
        -- one page with the paging controls put away.
        pick(env, "Toys")
        assert.same({ 0, 0 }, page(env))
        pick(env, "Owned or not")
        assert.same({ 4, 0 }, page(env))
        assert.is_false(env.MerchantPageText:IsShown())
        noResidue(env, module)
    end)
end)

describe("M4 price providers and bench", function()
    it("registers TSM and Auctionator only when their globals exist, and follows the opt-in options", function()
        local env = base()
        env:Load("Integrations/TSM.lua")
        env:Load("Integrations/Auctionator.lua")
        env:Load("Integrations/Prices.lua")
        env.C_Item = { GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 5 end }
        env.R.Integrations:RegisterPriceProviders()
        assert.is_false(env.R.Integrations.tsmAvailable)
        assert.same({ 5, "vendor" }, { env.R.Price:Get("item:1") })
        env.TSM_API = {
            GetCustomPriceValue = function(price, itemString) return price == "dbMarket" and itemString == "i:1"
                and 900 or nil end,
            ToItemString = function() return "i:1" end,
        }
        env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 700 end } } }
        env.R.Integrations:RegisterPriceProviders()
        assert.is_true(env.R.Integrations.tsmAvailable)
        assert.same({ 5, "vendor" }, { env.R.Price:Get("item:1") })
        env.R.Settings:SetOption("priceAuctionator", true)
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 700, "auctionator" }, { env.R.Price:Get("item:1") })
        env.R.Settings:SetOption("priceTSM", true)
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 900, "tsm" }, { env.R.Price:Get("item:1") })
    end)

    it("bench samples for five seconds and reports every budget line", function()
        local env = base()
        env.GetTimePreciseSec = function() return env.now end
        env.UpdateAddOnMemoryUsage = function() end
        env.GetAddOnMemoryUsage = function() return 900 end
        env.GetAddOnCPUUsage = function() return env.cpu or 0 end
        env.GetFramerate = function() return 100 end
        env.C_CVar = { GetCVarBool = function() return true end }
        env:Load("Core/Bench.lua")
        env:Load("Core/Commands.lua")
        env:Fire("ADDON_LOADED", "Refactor")
        env.now = 0.02
        env:Fire("PLAYER_LOGIN")
        env.R.Commands:Dispatch("bench")
        assert.matches("Sampling", env.messages[1])
        env.cpu = 25
        env:Advance(5)
        assert.matches("Load time.*20.0 ms", env.messages[2])
        assert.matches("Memory: 900 KB", env.messages[3])
        assert.matches("CPU: 0.050 ms", env.messages[5])
        assert.matches("OnUpdate handlers on Refactor frames: 0", env.messages[7])
        assert.equal(0, env:ActiveTimers())
    end)
end)

describe("M4 new ability placement", function()
    local function spellEnv(layout)
        local env = base()
        env:Load("Locales/Visibility.enUS.lua")
        env.slots, env.cursor, env.placed = {}, nil, {}
        env.spells = {
            [1001] = { name = "Frostbolt" },
            [1002] = { name = "Ice Barrier" },
            [1003] = { name = "Permafrost", passive = true },
            [1004] = { name = "Frostbolt Rank 2", base = 1001 },
        }
        env.C_Spell = {
            PickupSpell = function(spellID)
                if not env.refusePickup then env.cursor = spellID end
            end,
            IsSpellPassive = function(spellID) return (env.spells[spellID] or {}).passive == true end,
            GetSpellName = function(spellID) return (env.spells[spellID] or {}).name end,
        }
        env.C_SpellBook = {
            FindBaseSpellByID = function(spellID) return (env.spells[spellID] or {}).base or spellID end,
        }
        env.C_ActionBar = {
            HasAction = function(slot) return env.slots[slot] ~= nil end,
            IsOnBarOrSpecialBar = function(spellID)
                for _, held in pairs(env.slots) do
                    if held == spellID then return true end
                end
                return false
            end,
            PutActionInSlot = function(slot)
                if env.refusePlace or not env.cursor then return end
                env.slots[slot] = env.cursor
                env.placed[#env.placed + 1] = { slot = slot, spell = env.cursor }
                env.cursor = nil
            end,
        }
        env.GetCursorInfo = function()
            if env.cursor == nil then return nil end
            return "spell", env.cursor
        end
        env.ClearCursor = function() env.cursor = nil end
        -- Three of the eight bars, laid out as the client does: the main bar on slots 1 to
        -- 12, and two multibars whose slot ids are nowhere near their position.
        local function bar(first, count, shown, showable)
            local frame = { shown = shown, actionButtons = {} }
            function frame:IsShown() return self.shown end
            for index = 1, count do
                local button = { action = first + index - 1, shown = index <= (showable or count) }
                function button:IsShown() return self.shown end
                frame.actionButtons[index] = button
            end
            return frame
        end
        layout = layout or {}
        env.MainActionBar = bar(1, 12, layout.main ~= false, layout.mainShowable)
        env.MultiBarBottomLeft = bar(61, 12, layout.bottomLeft ~= false)
        env.MultiBarBottomRight = bar(49, 12, layout.bottomRight == true)
        local module = enable(env, "Modules/Interface/PlaceNewSpells.lua", "interface.placeNewSpells")
        function env:Learn(spellID, guildPerk)
            self:Fire("LEARNED_SPELL_IN_SKILL_LINE", spellID, 1, guildPerk == true)
            self:Advance(1)
        end
        return env, module
    end

    it("fills the first free slot on a bar that is on screen and leaves everything else alone", function()
        local env, module = spellEnv()
        for slot = 1, 12 do env.slots[slot] = 900 + slot end
        env.slots[5] = nil
        env:Learn(1001)
        assert.equal(1001, env.slots[5])
        assert.equal("Frostbolt went on Action bar 1 (main).", env.messages[#env.messages])
        assert.equal(1, #env.placed)
        -- Nothing that was already in a slot moved.
        assert.equal(901, env.slots[1])
        assert.is_nil(env.cursor)
        -- The main bar is full now, so the next one walks on to the bar after it.
        env:Learn(1002)
        assert.equal(1002, env.slots[61])
        assert.equal("Ice Barrier went on Action bar 2 (bottom left).", env.messages[#env.messages])
        assert.equal("PLACED", module.report.verdict)
        noResidue(env, module)
    end)

    it("skips passives, guild perks, ranks of something already placed, and repeat events", function()
        local env, module = spellEnv()
        env:Learn(1003)
        assert.equal(0, #env.placed)
        assert.equal("PASSIVE", module.report.verdict)
        env:Learn(1002, true)
        assert.equal(0, #env.placed)
        env:Learn(1001)
        assert.equal(1001, env.slots[1])
        -- A second event for the same spell, and a rank of it, are both already on the bar.
        env:Learn(1001)
        env:Learn(1004)
        assert.equal(1, #env.placed)
        assert.equal("ONBAR", module.report.verdict)
    end)

    it("uses only bars and buttons that are visible", function()
        local env, module = spellEnv({ main = false, mainShowable = 12 })
        env:Learn(1001)
        -- The main bar is hidden, so its empty slots are not somewhere the player can see.
        assert.is_nil(env.slots[1])
        assert.equal(1001, env.slots[61])
        -- A bar showing six of its twelve buttons owns six slots.
        local env2, module2 = spellEnv({ main = true, mainShowable = 6 })
        for slot = 1, 6 do env2.slots[slot] = 900 + slot end
        env2:Learn(1001)
        assert.equal(1001, env2.slots[61])
        assert.equal("Frostbolt went on Action bar 2 (bottom left).", env2.messages[#env2.messages])
        assert.equal("PLACED", module.report.verdict)
        noResidue(env2, module2)
    end)

    it("says so and places nothing when every visible slot is taken", function()
        local env, module = spellEnv()
        for slot = 1, 12 do env.slots[slot] = 900 + slot end
        for slot = 61, 72 do env.slots[slot] = 900 + slot end
        env:Learn(1001)
        assert.equal(0, #env.placed)
        assert.equal("NOSLOT", module.report.verdict)
        env.R.Broker:Emit("REFACTOR_SPELL_TEST")
        assert.matches("2 of 3 action bars on screen", env.messages[#env.messages - 2])
        assert.equal("No free slot on any bar you can see.", env.messages[#env.messages - 1])
        assert.matches("Every slot on the bars you can see is taken", env.messages[#env.messages])
    end)

    it("waits for combat to end and drops the queue when the pause modifier is held", function()
        local env, module = spellEnv()
        env.combat = true
        env:Learn(1001)
        assert.equal(0, #env.placed)
        assert.equal("COMBAT", module.report.verdict)
        env.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        env:Advance(1)
        assert.equal(1001, env.slots[1])
        env.control = true
        env:Learn(1002)
        assert.equal(1, #env.placed)
        assert.equal("PAUSED", module.report.verdict)
        env.control = false
        -- Dropped, not deferred: the next fight ending does not place it after all.
        env:Fire("PLAYER_REGEN_ENABLED")
        env:Advance(1)
        assert.equal(1, #env.placed)
        assert.equal(0, env:ActiveTimers())
    end)

    it("leaves a held cursor alone and places the ability once it is free", function()
        local env, module = spellEnv()
        env.cursor = 77
        env:Learn(1001)
        assert.equal(0, #env.placed)
        assert.equal(77, env.cursor)
        assert.equal("CURSOR", module.report.verdict)
        env.cursor = nil
        env:Advance(2)
        assert.equal(1001, env.slots[1])
        assert.equal(0, env:ActiveTimers())
    end)

    it("gives up on a client that refuses, clears the cursor, and runs again on demand", function()
        local env, module = spellEnv()
        env.refusePlace = true
        env:Learn(1001)
        assert.equal(0, #env.placed)
        assert.equal("BLOCKED", module.report.verdict)
        -- Whatever the refusal was, the cursor is not left holding the spell.
        assert.is_nil(env.cursor)
        -- One attempt, not a retry loop: a client that refuses once refuses every time.
        env:Advance(5)
        assert.equal(0, #env.placed)
        assert.equal(0, env:ActiveTimers())
        env.refusePlace = false
        env.R.Broker:Emit("REFACTOR_SPELL_TEST")
        -- The command says what happened last, then runs the queue again, so the placement
        -- line lands after the verdict it explains.
        assert.matches("The client refused the placement", env.messages[#env.messages - 1])
        assert.equal("Frostbolt went on Action bar 1 (main).", env.messages[#env.messages])
        assert.equal(1001, env.slots[1])
        noResidue(env, module)
    end)

    it("reports nothing learned yet, and the command says when the module is off", function()
        local env, module = spellEnv()
        env:Load("Core/Commands.lua")
        env.R.Broker:Emit("REFACTOR_SPELL_TEST")
        assert.equal("Nothing learned yet this session.", env.messages[#env.messages])
        assert.equal("Next free slot: 1, on Action bar 1 (main).", env.messages[#env.messages - 1])
        env.R.Registry:Disable(module)
        local lines = env.R.Commands:Dispatch("spelltest")
        assert.equal(env.R.L.CMD_SPELL_TEST_OFF, lines[1])
    end)
end)

describe("M4 chat copy", function()
    local function chatEnv(windows)
        local env = base()
        env.shown, env.buttons, env.hidden = {}, {}, 0
        env.R.UI.ShowSessionText = function(_, text, title) env.shown = { text = text, title = title } end
        env.R.UI.ChatCopyButton = function(_, chatFrame, onClick)
            env.buttons[chatFrame] = onClick
            return { chatFrame = chatFrame }
        end
        env.R.UI.HideChatCopyButtons = function() env.hidden = env.hidden + 1 end
        for index = 1, (windows or 1) do
            local frame = { lines = {} }
            function frame:GetNumMessages() return #self.lines end
            function frame:GetMessageInfo(at) return self.lines[at] end
            env["ChatFrame" .. index] = frame
        end
        local module = enable(env, "Modules/Chat/Copy.lua", "chat.copy")
        function env:Click(index)
            self.buttons[self["ChatFrame" .. (index or 1)]]()
        end
        return env, module
    end

    it("copies the window's lines, oldest first, with the escapes the box cannot show removed", function()
        local env, module = chatEnv()
        env.ChatFrame1.lines = {
            "|cffffffffTester|r says hello",
            "You receive loot: |cffa335ee|Hitem:12345::::::::70:::::|h[Thunderfury]|h|r",
            "|TInterface\\Icons\\Spell:16|t |A:atlas-name:12:12|a Kill it",
            "Use || as a bar",
        }
        env:Click()
        assert.equal("Chat text", env.shown.title)
        assert.same({
            "Tester says hello",
            "You receive loot: [Thunderfury]",
            "Kill it",
            "Use | as a bar",
        }, { strsplit_lines(env.shown.text) })
        noResidue(env, module)
    end)

    it("counts the lines the client will not hand over rather than dropping them quietly", function()
        local env = chatEnv()
        local secret = setmetatable({}, { __tostring = function() return "secret" end })
        env.issecretvalue = function(value) return value == secret end
        env.R.Registry:Disable("chat.copy")
        assert.is_true(env.R.Registry:Enable("chat.copy"))
        env.ChatFrame1.lines = { "plain one", secret, "plain two" }
        env:Click()
        assert.matches("1 lines the client would not hand over", env.shown.text)
        assert.matches("plain one\nplain two", env.shown.text)
    end)

    it("says when a window has nothing in it, and keeps only the newest lines of a long one", function()
        local env = chatEnv()
        env:Click()
        assert.equal("This chat window has no lines yet.", env.shown.text)
        for index = 1, 620 do
            env.ChatFrame1.lines[index] = "line " .. index
        end
        env:Click()
        local lines = { strsplit_lines(env.shown.text) }
        assert.equal(500, #lines)
        assert.equal("line 121", lines[1])
        assert.equal("line 620", lines[#lines])
    end)

    it("gives every chat window its own button and takes them all back on disable", function()
        local env, module = chatEnv(3)
        assert.equal(3, #module.windows)
        env.ChatFrame2.lines = { "second window" }
        env.ChatFrame3.lines = { "third window" }
        env:Click(2)
        assert.equal("second window", env.shown.text)
        env:Click(3)
        assert.equal("third window", env.shown.text)
        -- Every button is handed to the Chat buttons group, so the visibility panel can
        -- hide it with Blizzard's own.
        assert.equal(3, #env.R.Visibility:Contributions("chat.buttons"))
        env.R.Registry:Disable(module)
        assert.equal(1, env.hidden)
        assert.equal(0, #env.R.Visibility:Contributions("chat.buttons"))
        assert.is_nil(module.windows)
        -- Enabling again reuses the same buttons rather than leaving a second set behind.
        assert.is_true(env.R.Registry:Enable(module))
        assert.equal(3, #module.windows)
        noResidue(env, module)
    end)
end)

describe("M4 map zone levels", function()
    local RED, ORANGE, YELLOW = { r = 1, g = 0.1, b = 0.1 }, { r = 1, g = 0.5, b = 0.25 }, { r = 1, g = 0.82, b = 0 }
    local GREEN, GREY = { r = 0.25, g = 0.75, b = 0.25 }, { r = 0.5, g = 0.5, b = 0.5 }
    local ID = "interface.mapZoneLevels"

    local function fontString()
        local region = { shown = true, text = "" }
        function region:SetText(text) self.text = text end
        function region:GetText() return self.text end
        function region:SetTextColor(r, g, b) self.color = { r, g, b } end
        function region:SetJustifyH() end
        function region:SetFontObject(font) self.font = font end
        function region:GetFontObject() return "WorldMapTextFont" end
        function region:SetPoint(point, relative, relativePoint, x, y)
            self.point = { point, relative, relativePoint, x, y }
        end
        function region:Show() self.shown = true end
        function region:Hide() self.shown = false end
        return region
    end

    local function mapEnv()
        local env = base()
        env.level, env.mapID, env.hovered, env.levels, env.lookups = 5, 1414, nil, {}, 0
        env.UnitLevel = function() return env.level end
        -- Blizzard's relative difficulty bands, with the trivial range fixed at five levels.
        env.GetQuestDifficultyColor = function(level)
            local diff = level - env.level
            if diff >= 5 then return RED
            elseif diff >= 3 then return ORANGE
            elseif diff >= -4 then return YELLOW
            elseif -diff <= 5 then return GREEN
            else return GREY end
        end
        env.C_Map = {
            GetMapInfoAtPosition = function()
                env.lookups = env.lookups + 1
                return env.hovered
            end,
            GetMapLevels = function(mapID)
                local known = env.levels[mapID]
                if known then return known[1], known[2], 0, 0 end
                return 0, 0, 0, 0
            end,
        }
        env.hooksecurefunc = function(target, name, fn)
            local original = target[name]
            target[name] = function(...) original(...) fn(...) end
        end
        local label = { Name = fontString(), created = 0, evaluated = 0 }
        function label:CreateFontString()
            self.created = self.created + 1
            self.last = fontString()
            return self.last
        end
        function label:EvaluateLabels() self.evaluated = self.evaluated + 1 end
        env.label = label
        env.WorldMapFrame = {
            dataProviders = { [{ pins = {} }] = true, [{ Label = label }] = true },
            GetMapID = function() return env.mapID end,
            GetNormalizedCursorPosition = function() return 0.5, 0.5 end,
        }
        -- Blizzard's label writes its name text and then evaluates; the hook sees the result.
        function env.hover(name, info)
            label.Name:SetText(name)
            env.hovered = info
            label:EvaluateLabels()
        end
        return env
    end

    local function zone(mapID, name) return { mapID = mapID, name = name } end

    it("draws the range in the difficulty colour, only for a hovered zone the client has no levels for", function()
        local env = mapEnv()
        enable(env, "Modules/Interface/MapZoneLevels.lua", ID)
        local label = env.label
        assert.equal(1, label.created)
        assert.equal("WorldMapTextFont", label.last.font)
        assert.same({ "LEFT", label.Name, "RIGHT", 4, 0 }, label.last.point)
        env.hover("Tirisfal Glades", zone(1420, "Tirisfal Glades"))
        assert.equal("(1-10)", label.last.text)
        assert.same({ 1, 0.82, 0 }, label.last.color)
        assert.is_true(label.last.shown)
        env.level = 1
        env.hover("Westfall", zone(1436, "Westfall"))
        assert.equal("(10-20)", label.last.text)
        assert.same({ 1, 0.1, 0.1 }, label.last.color)
        env.level = 12
        env.hover("Redridge Mountains", zone(1433, "Redridge Mountains"))
        assert.same({ 1, 0.5, 0.25 }, label.last.color)
        -- Above the range Blizzard colours two below the top: 30 over a 10-20 zone is twelve
        -- past 18 and grey, 13 over 1-10 is five past 8 and green, and 12 over 1-10 is four
        -- past 8, still yellow.
        env.level = 30
        env.hover("Westfall", zone(1436, "Westfall"))
        assert.same({ 0.5, 0.5, 0.5 }, label.last.color)
        env.level = 13
        env.hover("Durotar", zone(1411, "Durotar"))
        assert.same({ 0.25, 0.75, 0.25 }, label.last.color)
        env.level = 12
        env.hover("Tirisfal Glades", zone(1420, "Tirisfal Glades"))
        assert.same({ 1, 0.82, 0 }, label.last.color)
        -- The article is optional either way round.
        env.hover("Barrens", zone(1413, "Barrens"))
        assert.equal("(10-25)", label.last.text)
        env.hover("The Hinterlands", zone(1425, "The Hinterlands"))
        assert.equal("(40-50)", label.last.text)
        env.hover("The Durotar", zone(1411, "The Durotar"))
        assert.equal("(1-10)", label.last.text)
        -- Forever's own zones, the two with a published range.
        env.hover("Riverglades", zone(16600, "Riverglades"))
        assert.equal("(35-45)", label.last.text)
        env.hover("Zephras Isle", zone(16593, "Zephras Isle"))
        assert.equal("(1-12)", label.last.text)
        -- A client that answers is drawing the range itself.
        env.levels[1436] = { 10, 20 }
        env.hover("Westfall", zone(1436, "Westfall"))
        assert.equal("", label.last.text)
        assert.is_false(label.last.shown)
        -- A subzone of the open map, a label that is not the hovered map's name, a city and
        -- no map under the cursor all draw nothing.
        env.hover("Brill", zone(1414, "Brill"))
        assert.equal("", label.last.text)
        env.hover("Tirisfal Glades", zone(1420, "Tirisfal Glades"))
        assert.equal("(1-10)", label.last.text)
        env.hover("Some banner", zone(1420, "Tirisfal Glades"))
        assert.equal("", label.last.text)
        env.hover("Orgrimmar", zone(1454, "Orgrimmar"))
        assert.equal("", label.last.text)
        env.hover("Tirisfal Glades", zone(1420, "Tirisfal Glades"))
        env.hover("", nil)
        assert.equal("", label.last.text)
        assert.is_false(label.last.shown)
        assert.equal(0, #env.R.errors)
    end)

    it("looks the zone up once per change of the label, again on a level up, never while off", function()
        local env = mapEnv()
        local module = enable(env, "Modules/Interface/MapZoneLevels.lua", ID)
        local label = env.label
        env.hover("Tirisfal Glades", zone(1420, "Tirisfal Glades"))
        assert.equal(1, env.lookups)
        label:EvaluateLabels()
        label:EvaluateLabels()
        assert.equal(1, env.lookups)
        env.level = 20
        label:EvaluateLabels()
        assert.same({ 1, 0.82, 0 }, label.last.color)
        env:Fire("PLAYER_LEVEL_UP", 20)
        label:EvaluateLabels()
        assert.equal(2, env.lookups)
        assert.same({ 0.5, 0.5, 0.5 }, label.last.color)
        env.R.Registry:Disable(module)
        assert.equal("", label.last.text)
        assert.is_false(label.last.shown)
        env.hover("Westfall", zone(1436, "Westfall"))
        assert.equal(2, env.lookups)
        assert.is_false(label.last.shown)
        noResidue(env, module)
        assert.is_true(env.R.Registry:Enable(module))
        env.hover("Westfall", zone(1436, "Westfall"))
        assert.equal("(10-20)", label.last.text)
        assert.equal(1, label.created)
    end)

    it("fails with a reason when the map has no zone label to attach to", function()
        local env = mapEnv()
        env.WorldMapFrame.dataProviders = { [{ pins = {} }] = true }
        env:Load("Modules/Interface/MapZoneLevels.lua")
        assert.is_false(env.R.Registry:Enable(ID))
        local module = env.R.moduleByID[ID]
        assert.equal("failed", module.state)
        assert.matches("zone label", module.failure)
        assert.equal(1, #env.R.errors)
        assert.equal(0, env.label.created)
    end)
end)

describe("M4 map reveal", function()
    local ID = "interface.mapReveal"

    local function texture()
        local region = { shown = false }
        function region:SetSize(width, height) self.width, self.height = width, height end
        function region:SetTexCoord(left, right, top, bottom) self.coords = { left, right, top, bottom } end
        function region:SetPoint(point, relative, relativePoint, x, y)
            self.point = { point, relative, relativePoint, x, y }
        end
        function region:ClearAllPoints() self.point = nil end
        function region:SetTexture(file, _, _, filter) self.file, self.filter = file, filter end
        function region:SetDesaturation(amount) self.desaturation = amount end
        function region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
        function region:Show() self.shown = true end
        function region:Hide() self.shown = false end
        return region
    end

    local function revealEnv()
        local env = base()
        env.R.MapOverlays = { interface = 120100, build = "test", maps = {
            [1244] = { "160:210:382:281:272826", "315:256:101:247:272806,272812" },
            [1300] = { "100:100:0:0:1,2" },
        } }
        env.artID, env.mapID, env.layerIndex, env.created = 1244, 1411, 1, 0
        env.layers = { { tileWidth = 256, tileHeight = 256 } }
        env.C_Map = {
            GetMapArtID = function() return env.artID end,
            GetMapArtLayers = function() return env.layers end,
        }
        env.hooksecurefunc = function(target, name, fn)
            local original = target[name]
            target[name] = function(...) original(...) fn(...) end
        end
        local pin = { alpha = 1, level = 2002, refreshed = 0 }
        function pin:RefreshOverlays() self.refreshed = self.refreshed + 1 end
        function pin:RemoveAllData() end
        function pin:RefreshAlpha() end
        function pin:GetAlpha() return self.alpha end
        function pin:GetFrameLevel() return self.level end
        env.pin = pin
        local canvas = { name = "canvas" }
        env.CreateFrame = function(_, _, parent)
            env.created = env.created + 1
            local frame = { parent = parent, textures = nil, shown = false, count = 0 }
            function frame:SetAllPoints(target) self.fill = target end
            function frame:SetFrameLevel(level) self.level = level end
            function frame:SetAlpha(alpha) self.alpha = alpha end
            function frame:Show() self.shown = true end
            function frame:Hide() self.shown = false end
            function frame:CreateTexture()
                self.count = self.count + 1
                self.last = texture()
                self.all = self.all or {}
                self.all[#self.all + 1] = self.last
                return self.last
            end
            env.frame = frame
            return frame
        end
        env.WorldMapFrame = {
            shown = true, pins = { pin },
            EnumeratePinsByTemplate = function(self, template)
                local list = template == "MapExplorationPinTemplate" and self.pins or {}
                local index = 0
                return function()
                    index = index + 1
                    return list[index]
                end
            end,
            GetCanvas = function() return canvas end,
            GetMapID = function() return env.mapID end,
            GetCanvasContainer = function() return { GetCurrentLayerIndex = function() return env.layerIndex end } end,
            IsShown = function(self) return self.shown end,
        }
        env.canvas = canvas
        return env
    end

    local function drawn(frame)
        local list = {}
        for _, region in ipairs(frame.all or {}) do
            if region.shown then list[#list + 1] = region end
        end
        table.sort(list, function(a, b) return a.file < b.file end)
        return list
    end

    it("draws the open map's overlays as cut tiles under Blizzard's exploration pin", function()
        local env = revealEnv()
        env:Load("UI/MapReveal.lua")
        enable(env, "Modules/Interface/MapReveal.lua", ID)
        local frame = env.frame
        assert.equal(1, env.created)
        assert.equal(env.canvas, frame.parent)
        assert.equal(env.canvas, frame.fill)
        assert.is_true(frame.shown)
        assert.equal(2001, frame.level)
        assert.equal(1, frame.alpha)
        local tiles = drawn(frame)
        assert.equal(3, #tiles)
        -- A 315 by 256 overlay at 101, 247: one whole tile, then a 59 wide strip cut from a
        -- 64 wide file. A 160 by 210 overlay fits one tile, cut both ways from a 256 file.
        assert.equal(272806, tiles[1].file)
        assert.same({ 256, 256 }, { tiles[1].width, tiles[1].height })
        assert.same({ 0, 1, 0, 1 }, tiles[1].coords)
        assert.same({ "TOPLEFT", frame, "TOPLEFT", 101, -247 }, tiles[1].point)
        assert.equal(272812, tiles[2].file)
        assert.same({ 59, 256 }, { tiles[2].width, tiles[2].height })
        assert.same({ 0, 59 / 64, 0, 1 }, tiles[2].coords)
        assert.same({ "TOPLEFT", frame, "TOPLEFT", 357, -247 }, tiles[2].point)
        assert.equal(272826, tiles[3].file)
        assert.same({ 160, 210 }, { tiles[3].width, tiles[3].height })
        assert.same({ 0, 160 / 256, 0, 210 / 256 }, tiles[3].coords)
        assert.same({ "TOPLEFT", frame, "TOPLEFT", 382, -281 }, tiles[3].point)
        assert.equal("TRILINEAR", tiles[3].filter)
        assert.equal(0.6, tiles[3].desaturation)
        assert.same({ 0.72, 0.72, 0.72, 1 }, tiles[3].color)
        assert.equal(0, #env.R.errors)
    end)

    it("follows the pin's refresh, clear and alpha, reuses textures, and skips what it cannot place", function()
        local env = revealEnv()
        env:Load("UI/MapReveal.lua")
        local module = enable(env, "Modules/Interface/MapReveal.lua", ID)
        local frame, pin = env.frame, env.pin
        assert.equal(3, frame.count)
        pin.alpha = 0.4
        pin:RefreshAlpha()
        assert.equal(0.4, frame.alpha)
        pin:RemoveAllData()
        assert.equal(0, #drawn(frame))
        pin.level = 2010
        pin:RefreshOverlays(true)
        assert.equal(3, #drawn(frame))
        assert.equal(3, frame.count)
        assert.equal(2009, frame.level)
        -- A map without data, a layer the client cannot describe, and an overlay whose tile
        -- count does not fit its size all draw nothing.
        env.artID = 9999
        pin:RefreshOverlays()
        assert.equal(0, #drawn(frame))
        env.artID = 1300
        pin:RefreshOverlays()
        assert.equal(0, #drawn(frame))
        env.artID, env.layers = 1244, nil
        pin:RefreshOverlays()
        assert.equal(0, #drawn(frame))
        env.layers = { { tileWidth = 256, tileHeight = 256 } }
        pin:RefreshOverlays()
        assert.equal(3, #drawn(frame))
        env.R.Registry:Disable(module)
        assert.is_false(frame.shown)
        assert.equal(0, #drawn(frame))
        pin:RefreshOverlays()
        assert.equal(0, #drawn(frame))
        noResidue(env, module)
        assert.is_true(env.R.Registry:Enable(module))
        assert.equal(1, env.created)
        assert.equal(3, #drawn(frame))
        assert.equal(3, frame.count)
        assert.equal(0, #env.R.errors)
    end)

    it("is unavailable on a client the data was not made for, and fails without a pin", function()
        local env = revealEnv()
        env.R.MapOverlays.interface = 16001
        env:Load("UI/MapReveal.lua")
        env:Load("Modules/Interface/MapReveal.lua")
        assert.is_false(env.R.Registry:Enable(ID))
        local module = env.R.moduleByID[ID]
        assert.equal("unavailable", module.state)
        assert.matches("another client build", module.unavailableReason)
        assert.equal(0, env.created)

        env = revealEnv()
        env.WorldMapFrame.pins = {}
        env:Load("UI/MapReveal.lua")
        env:Load("Modules/Interface/MapReveal.lua")
        assert.is_false(env.R.Registry:Enable(ID))
        module = env.R.moduleByID[ID]
        assert.equal("failed", module.state)
        assert.matches("exploration layer", module.failure)
        assert.equal(0, env.created)
    end)
end)
