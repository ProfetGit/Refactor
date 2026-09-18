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
    env:Load("UI/Toasts.lua")
    env.GetMoney = function() return env.money or 0 end
    env.money = 1000
    env.C_Item = {
        GetItemQualityByID = function(id) return env.qualities and env.qualities[id] or 1 end,
        GetItemIconByID = function(id) return 100 + id end,
        GetItemQualityColor = function(q) return q, q, q end,
        GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 30 end,
    }
    env.C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = "Marks", iconFileID = 5, quality = 2,
        currencyID = id } end }
    function env:Loot(text, guid)
        self:Fire("CHAT_MSG_LOOT", text, "Me", "", "", "Me", "", 0, 0, "", 0, 1, guid or "Player-test")
    end
    return env
end

local LINK = "|cff0070dd|Hitem:2000:0:0:0:0:0:0:0:60:0:0:0:0|h[Blue Thing]|h|r"

describe("M4 loot toasts", function()
    it("parses links locale-free and toasts only the player's own loot", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env:Loot("You receive loot: " .. LINK .. "x3.", "Player-other")
        assert.equal(0, #module.host.visible)
        env:Loot("You receive loot: " .. LINK .. "x3.")
        assert.equal(1, #module.host.visible)
        local toast = module.host.visible[1]
        assert.equal("Blue Thing x3", toast.name:GetText())
        assert.equal("0g 0s 90c (vendor)", toast.detail:GetText())
        assert.equal(2100, toast.icon.texture)
        env:Loot("Vous recevez: " .. LINK .. ".")
        assert.equal(1, #module.host.visible)
        assert.equal("Blue Thing x4", toast.name:GetText())
        noResidue(env, module)
    end)

    it("respects the quality threshold and the price toggle", function()
        local env = toastEnv()
        env.qualities = { [2000] = 1 }
        env.R.Settings:SetOption("toastMinQuality", 2)
        env.R.Settings:SetOption("toastShowPrice", false)
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env:Loot("loot " .. LINK)
        assert.equal(0, #module.host.visible)
        env.qualities[2000] = 2
        env:Loot("loot " .. LINK)
        assert.equal(1, #module.host.visible)
        assert.equal("", module.host.visible[1].detail:GetText())
        noResidue(env, module)
    end)

    it("toasts gold only around a loot window, and currency on gain", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        env.money = 1500
        env:Fire("PLAYER_MONEY")
        assert.equal(0, #module.host.visible)
        env:Fire("LOOT_OPENED", true, false)
        env.money = 1650
        env:Fire("PLAYER_MONEY")
        assert.equal(1, #module.host.visible)
        assert.equal("+0g 1s 50c", module.host.visible[1].detail:GetText())
        env:Fire("LOOT_CLOSED")
        env:Advance(0.6)
        assert.is_nil(env.R.Broker.events.PLAYER_MONEY)
        env:Fire("CURRENCY_DISPLAY_UPDATE", 42, 10, 5)
        assert.equal(2, #module.host.visible)
        assert.equal("+5", module.host.visible[2].detail:GetText())
        env:Fire("CURRENCY_DISPLAY_UPDATE", 42, 10, -5)
        assert.equal(2, #module.host.visible)
        env.R.Registry:Disable(module)
        assert.equal(0, #module.host.visible)
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

    it("drops overflow instead of creating frames during a burst", function()
        local env = toastEnv()
        local module = enable(env, "Modules_LoD/Toasts/Loot.lua", "toasts.loot")
        local frames = #env.frames
        for index = 1, 8 do
            env:Loot("loot |cff0070dd|Hitem:" .. index .. ":0|h[Item " .. index .. "]|h|r")
        end
        assert.equal(5, #module.host.visible)
        assert.equal(frames, #env.frames)
        noResidue(env, module)
    end)
end)

describe("M4 quest automation", function()
    it("accepts unless flagged, repeatable, paused, or limited to item quests", function()
        local env = base()
        local accepted = 0
        env.AcceptQuest = function() accepted = accepted + 1 end
        env.QuestGetAutoAccept = function() return env.autoAccept == true end
        env.QuestFlagsPVP = function() return env.pvp == true end
        env.GetQuestID = function() return 500 end
        env.C_QuestLog = { IsRepeatableQuest = function() return env.repeatable == true end }
        local module = enable(env, "Modules/Quest/AutoAccept.lua", "quest.autoAccept")
        env:Fire("QUEST_DETAIL")
        assert.equal(1, accepted)
        env.autoAccept = true
        env:Fire("QUEST_DETAIL")
        env.autoAccept, env.pvp = false, true
        env:Fire("QUEST_DETAIL")
        env.pvp, env.repeatable = false, true
        env:Fire("QUEST_DETAIL")
        env.repeatable, env.control = false, true
        env:Fire("QUEST_DETAIL")
        assert.equal(1, accepted)
        env.control = false
        env.R.Settings:SetOption("questAcceptItemsOnly", true)
        env:Fire("QUEST_DETAIL", nil)
        assert.equal(1, accepted)
        env:Fire("QUEST_DETAIL", 4321)
        assert.equal(2, accepted)
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

    it("extended vendor list filters stock and buys one or a stack", function()
        local env = merchantEnv()
        env.stock = {
            { name = "Bread", texture = 1, price = 50, stackCount = 5, numAvailable = -1, isUsable = true },
            { name = "Plate Helm", texture = 2, price = 5000, stackCount = 1, numAvailable = -1, isUsable = false },
            { name = "Badge Thing", texture = 3, price = 0, hasExtendedCost = true, isUsable = true },
        }
        env.GetMerchantNumItems = function() return #env.stock end
        env.C_MerchantFrame = { GetItemInfo = function(index) return env.stock[index] end }
        env.GetMerchantItemLink = function(index) return "|Hitem:" .. index .. ":|h" end
        env.GetMerchantItemMaxStack = function() return 20 end
        env.purchases = {}
        env.BuyMerchantItem = function(index, quantity) env.purchases[#env.purchases + 1] = { index, quantity } end
        env.GetNumBuybackItems = function() return 2 end
        env.GetBuybackItemInfo = function(index) return "Sold " .. index, 9, 10 * index, 1 end
        env.bought = {}
        env.BuybackItem = function(index) env.bought[#env.bought + 1] = index end
        env.IsShiftKeyDown = function() return env.shift == true end
        local module = enable(env, "Modules/Vendor/ExtendedUI.lua", "vendor.extendedUI")
        env:Fire("MERCHANT_SHOW")
        assert.is_true(module.panel:IsShown())
        assert.equal(2, #module.items)
        assert.equal("Sold 2", module.buyback[1].name)
        module.panel.usable:SetChecked(true)
        module:Refresh()
        assert.equal(1, #module.items)
        assert.equal("Bread", module.items[1].name)
        module.panel.rows[1]:GetScript("OnClick")(module.panel.rows[1])
        env.shift = true
        module.panel.rows[1]:GetScript("OnClick")(module.panel.rows[1])
        assert.same({ { 1, 1 }, { 1, 20 } }, env.purchases)
        module.panel.buybackRows[1]:GetScript("OnClick")(module.panel.buybackRows[1])
        assert.same({ 2 }, env.bought)
        env:Fire("MERCHANT_CLOSED")
        assert.is_false(module.panel:IsShown())
        assert.is_nil(env.R.Broker.events.MERCHANT_UPDATE)
        noResidue(env, module)
    end)
end)

describe("M4 price providers and bench", function()
    it("registers TSM and Auctionator only when their globals exist, and follows the opt-in options", function()
        local env = base()
        env:Load("Integrations/TSM.lua")
        env:Load("Integrations/Auctionator.lua")
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
