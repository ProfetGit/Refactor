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
    env.R.Settings:Confirm(id, true)
    assert.is_true(env.R.Registry:Enable(id), id .. " did not enable: "
        .. tostring(env.R.moduleByID[id].failure) .. " " .. table.concat(env.R.moduleByID[id].missing or {}, ","))
    return env.R.moduleByID[id]
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
    env.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) env.postCalls[#env.postCalls + 1] = fn end }
    env.Enum = { TooltipDataType = { Item = 0 } }
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
    env.TooltipUtil = { GetDisplayedItem = function() return "Sword", env.link, 7 end }
    env.link = "|cffffffff|Hitem:7::::::::1:::::|h[Sword]|h|r"
    env.qualities = { [7] = 3 }
    env.C_Item = {
        GetItemInfo = function() return "Sword", env.link, 3, 1, 1, "", "", env.stack or 1, "", 1, 25 end,
        GetItemQualityByID = function(id) return env.qualities[id] end,
        GetItemQualityColor = function(q) return q / 10, q / 20, q / 40, "hex" end,
    }
    function env:PostCall(tip, data)
        for _, fn in ipairs(self.postCalls) do fn(tip, data or { id = 7 }) end
    end
    return env
end

describe("M4 tooltips", function()
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
        env.hooksecurefunc = function(name, fn) env.hooks[name] = fn end
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
        local duels = enable(env, "Modules/Chat/DeclineDuels.lua", "social.declineDuels")
        local res = enable(env, "Modules/Chat/AcceptResurrect.lua", "social.acceptResurrect")
        env:Load("Modules/Chat/AcceptInvites.lua")
        env.R.Settings:Confirm("social.acceptInvites", true)
        -- Unavailable until AcceptGroup is verified unprotected in game; the trust check is
        -- still exercised directly.
        assert.is_false(env.R.Registry:Enable("social.acceptInvites"))
        local invites = env.R.moduleByID["social.acceptInvites"]
        assert.equal("unavailable", invites.state)
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
        env:Fire("PARTY_INVITE_REQUEST", "Friend", false, false, false, true, false, "Player-friend", false)
        assert.same({ "duel", "res" }, actions)
        env.control = true
        env:Fire("DUEL_REQUESTED", "Bob")
        assert.equal(2, #actions)
        for _, module in ipairs({ duels, res }) do noResidue(env, module) end
    end)
end)

describe("M4 interface, mail, vendor", function()
    it("camera modules set CVars on enable and restore defaults on disable", function()
        local env = base()
        local cvars = {}
        env.C_CVar = {
            SetCVar = function(name, value) cvars[name] = value end,
            GetCVarDefault = function(name) return name == "cameraDistanceMaxZoomFactor" and "1.9" or "0" end,
        }
        local hidden = {}
        local console = {}
        env.ConsoleExec = function(command) console[#console + 1] = command end
        env.StaticPopup_Hide = function(which) hidden[which] = true end
        local camera = enable(env, "Modules/Interface/CameraDistance.lua", "interface.cameraDistance")
        local action = enable(env, "Modules/Interface/ActionCam.lua", "interface.actionCam")
        assert.equal("2.6", cvars.cameraDistanceMaxZoomFactor)
        assert.is_true(hidden.EXPERIMENTAL_CVAR_WARNING)
        assert.same({ "actioncam basic" }, console)
        env.R.Registry:Disable(camera)
        env.R.Registry:Disable(action)
        assert.equal("1.9", cvars.cameraDistanceMaxZoomFactor)
        -- The preset is the client's, so disable restores every test_camera CVar it could touch.
        assert.equal("0", cvars.test_cameraOverShoulder)
        assert.equal("0", cvars.test_cameraTargetFocusEnemyEnable)
        assert.equal("0", cvars.test_cameraHeadMovementStrength)
        noResidue(env, camera)
        noResidue(env, action)
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
        env.hooksecurefunc = function(name, fn) env.hooks[name] = fn end
        env.MerchantFrame_Update = function()
            env.updates = env.updates + 1
            env.hooks.MerchantFrame_Update()
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

    local function costEnv()
        local env = Runtime2.new()
        Widgets2.install(env)
        for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Features.enUS.lua" }) do
            env:Load(path)
        end
        env.R.UI = env.R.UI or {}
        env:Load("UI/MerchantCosts.lua")
        env.MerchantFrame = env.CreateFrame("Frame", "MerchantFrame")
        env.MerchantFrame:Show()
        env.MerchantFrame.selectedTab, env.MerchantFrame.page = 1, 1
        for index = 1, 12 do
            local cell = env.CreateFrame("Frame", "MerchantItem" .. index, env.MerchantFrame)
            local alt = env.CreateFrame("Frame", "MerchantItem" .. index .. "AltCurrencyFrame", cell)
            for cost = 1, 3 do
                env.CreateFrame("Button", "MerchantItem" .. index .. "AltCurrencyFrameItem" .. cost, alt)
            end
            env.CreateFrame("Frame", "MerchantItem" .. index .. "MoneyFrame", cell)
        end
        env.MERCHANT_ITEMS_PER_PAGE, env.MAX_ITEM_COST = 10, 3
        env.hooks, env.updates, env.money = {}, 0, 1000
        env.hooksecurefunc = function(name, fn) env.hooks[name] = fn end
        env.MerchantFrame_Update = function()
            env.updates = env.updates + 1
            env.hooks.MerchantFrame_Update()
        end
        env.currencyUpdates, env.currencyList = 0, {}
        env.MerchantFrame_UpdateCurrencies = function() env.currencyUpdates = env.currencyUpdates + 1 end
        env.MAX_MERCHANT_CURRENCIES = 6
        env.GameTooltip = env.CreateFrame("GameTooltip", "GameTooltip")
        for _, name in ipairs({ "MerchantMoneyFrame", "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg" }) do
            env.CreateFrame("Frame", name, env.MerchantFrame)
        end
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
        local module = enable(env, "Modules/Vendor/ItemCosts.lua", "vendor.itemCosts")
        assert.equal(0, env.updates)
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
        -- The one item this merchant takes sits in the coin box with the carried count,
        -- in Blizzard's first slot, and the money frame moves over to share the row.
        local token = env.RefactorMerchantToken1
        assert.is_true(token:IsShown())
        assert.equal("item:9", token.itemLink)
        assert.equal(1, token.slot)
        assert.equal(3, token.Count.text)
        assert.is_false(env.RefactorMerchantToken2:IsShown())
        assert.is_true(env.MerchantExtraCurrencyInset:IsShown())
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
        assert.equal(3, env.updates)
        assert.equal(1, env.currencyUpdates)
        noResidue(env, module)
    end)

    it("chains item tokens after the merchant's currencies and gives the money frame way past three", function()
        local env = costEnv()
        env.currencyList = { 101, 102 }
        env.CreateFrame("Button", "MerchantToken1", env.MerchantFrame)
        env.CreateFrame("Button", "MerchantToken2", env.MerchantFrame)
        env.items["item:1"], env.items["item:2"], env.items["item:3"] = 1, 200000, 0
        env.stock = {
            { hasExtendedCost = true, price = 0, canAfford = true,
                costs = { cost(1, 1, "item:1"), cost(1, 1, "item:2") } },
            { hasExtendedCost = true, price = 0, canAfford = true,
                costs = { cost(1, 1, "item:1"), cost(1, 1, "item:3"), cost(9, 1, "currency:101", "Marks") } },
        }
        local module = enable(env, "Modules/Vendor/ItemCosts.lua", "vendor.itemCosts")
        assert.same({ 3, 4, 5 }, { env.RefactorMerchantToken1.slot, env.RefactorMerchantToken2.slot,
            env.RefactorMerchantToken3.slot })
        assert.equal("*", env.RefactorMerchantToken2.Count.text)
        assert.equal(0, env.RefactorMerchantToken3.Count.text)
        assert.is_false(env.RefactorMerchantToken4:IsShown())
        assert.is_false(env.MerchantMoneyFrame:IsShown())
        -- Six currencies leave no slot, and Blizzard's own layout is left standing.
        env.currencyList = { 1, 2, 3, 4, 5, 6 }
        env.MerchantMoneyFrame:Show()
        env.MerchantFrame_Update()
        assert.is_false(env.RefactorMerchantToken1:IsShown())
        assert.is_true(env.MerchantMoneyFrame:IsShown())
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
