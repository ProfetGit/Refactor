local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local LINK = "|cff0070dd|Hitem:2000:0:0:0:0:0:0:0:60:0:0:0:0|h[Blue Thing]|h|r"

local function itemLink(id, name)
    return string.format("|cffffffff|Hitem:%d:0:0:0:0:0:0:0:60:0:0:0:0|h[%s]|h|r", id, name or "Thing")
end

local function base()
    local env = Runtime.new()
    Widgets.install(env)
    for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Commands.enUS.lua",
        "Locales/Tooltips.enUS.lua", "Locales/Toasts.enUS.lua", "Locales/Features.enUS.lua",
        "Locales/Prices.enUS.lua", "Locales/Farm.enUS.lua" }) do
        env:Load(path)
    end
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    env.R.UI = env.R.UI or {}
    env.vendorPrices = { [2000] = 30 }
    env.C_Item = {
        GetItemQualityByID = function(id) return env.qualities and env.qualities[id] or 1 end,
        GetItemIconByID = function(id) return 100 + id end,
        GetItemQualityColor = function(q) return q / 10, q / 10, q / 10 end,
        GetItemInfo = function(link)
            local id = tonumber(tostring(link):match("|Hitem:(%d+)")) or 0
            return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, env.vendorPrices[id]
        end,
    }
    env.money = 1000
    env.GetMoney = function() return env.money end
    env.C_CurrencyInfo = {
        GetCoinTextureString = function(amount) return tostring(amount) .. "c" end,
    }
    env.GameTooltip = {
        -- SetOwner is what starts a tooltip over, exactly as the client's own does, so a
        -- second tooltip cannot be read as lines appended to the first.
        SetOwner = function(tip, owner, anchor) tip.owner, tip.anchor, tip.lines = owner, anchor, nil end,
        AddLine = function(tip, text) tip.lines = tip.lines or {}; tip.lines[#tip.lines + 1] = text end,
        Show = function(tip) tip.shown = true end,
        Hide = function(tip) tip.shown, tip.lines = false, nil end,
    }
    -- The context menu is Blizzard's; the spec records what the addon puts into it.
    env.menuEntries = {}
    env.UIDropDownMenu_CreateInfo = function() return {} end
    env.UIDropDownMenu_AddButton = function(info) env.menuEntries[#env.menuEntries + 1] = info end
    env.UIDropDownMenu_Initialize = function(_, initialize) initialize() end
    env.ToggleDropDownMenu = function() env.menuToggled = (env.menuToggled or 0) + 1 end
    return env
end

local function prices(env)
    for _, path in ipairs({ "Integrations/TSM.lua", "Integrations/Auctionator.lua",
        "Integrations/Prices.lua" }) do
        env:Load(path)
    end
    env.R.Integrations:RegisterPriceProviders()
    return env.R.Prices
end

local function farmEnv()
    local env = base()
    env:Load("UI/FarmHud.lua")
    env:Load("UI/SessionSummary.lua")
    prices(env)
    function env:Loot(text, guid)
        self:Fire("CHAT_MSG_LOOT", text, "Me", "", "", "Me", "", 0, 0, "", 0, 1, guid or "Player-test")
    end
    return env
end

local function enable(env)
    env:Load("Modules/Loot/FarmSession.lua")
    assert.is_true(env.R.Registry:Enable("loot.farmSession"),
        tostring(env.R.moduleByID["loot.farmSession"].failure)
            .. table.concat(env.R.moduleByID["loot.farmSession"].missing or {}, ","))
    return env.R.moduleByID["loot.farmSession"]
end

describe("price provider chain", function()
    it("falls back to vendor silently when no price addon is installed", function()
        local env = base()
        local Prices = prices(env)
        assert.same({ 30, "Vendor" }, { Prices.Get(LINK) })
        assert.equal("Vendor", Prices.CurrentSource())
        assert.is_false(env.R.Integrations.tsmAvailable)
        assert.is_false(env.R.Integrations.auctionatorAvailable)
        assert.equal(0, #env.messages)
    end)

    it("resolves TSM, then Auctionator, then another price addon, then vendor", function()
        local env = base()
        env.TSM_API = {
            GetCustomPriceValue = function(price, item) return price == "dbMarket" and item == "i:2000" and 900 end,
            ToItemString = function() return "i:2000" end,
        }
        env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 700 end } } }
        env.RECrystallize_PriceCheck = function() return 500 end
        local Prices = prices(env)
        -- Auction providers are opt in, so an installed one changes nothing until asked for.
        assert.same({ 500, "RECrystallize" }, { Prices.Get(LINK) })
        env.R.Settings:SetOption("priceAuctionator", true)
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 700, "Auctionator" }, { Prices.Get(LINK) })
        env.R.Settings:SetOption("priceTSM", true)
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 900, "TradeSkillMaster" }, { Prices.Get(LINK) })
        assert.equal("TradeSkillMaster", Prices.CurrentSource())
    end)

    it("never lets a provider error reach the player, and skips to the next one", function()
        local env = base()
        env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() error("boom") end } } }
        local Prices = prices(env)
        env.R.Settings:SetOption("priceAuctionator", true)
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 30, "Vendor" }, { Prices.Get(LINK) })
        assert.equal(0, #env.R.errors)
    end)

    it("pins one provider when the source is overridden, and goes back to the chain if it is gone", function()
        local env = base()
        env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 700 end } } }
        local Prices = prices(env)
        env.R.Settings:SetOption("priceAuctionator", true)
        env.R.Integrations:ApplyPriceOptions()
        env.R.Settings:SetOption("priceSource", "vendor")
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 30, "Vendor" }, { Prices.Get(LINK) })
        assert.equal("Vendor", Prices.CurrentSource())
        -- TSM is not installed, so naming it is not an error and not a missing price.
        env.R.Settings:SetOption("priceSource", "tsm")
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 700, "Auctionator" }, { Prices.Get(LINK) })
    end)

    it("answers from the cache until the chain changes, and never caches a missing price", function()
        local env = base()
        local answers, calls = { 700 }, 0
        env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function()
            calls = calls + 1
            return answers[1]
        end } } }
        local Prices = prices(env)
        env.R.Settings:SetOption("priceAuctionator", true)
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 700, "Auctionator" }, { Prices.Get(LINK) })
        answers[1] = 12345
        assert.same({ 700, "Auctionator" }, { Prices.Get(LINK) })
        assert.equal(1, calls)
        -- Turning a provider off is the named invalidation. Nothing here expires on a clock.
        env.R.Settings:SetOption("priceAuctionator", false)
        env.R.Integrations:ApplyPriceOptions()
        assert.same({ 30, "Vendor" }, { Prices.Get(LINK) })
        -- An item the client has not cached yet has no price, and that must not be recorded.
        local unknown = itemLink(4242)
        assert.is_nil(Prices.Get(unknown))
        env.vendorPrices[4242] = 55
        assert.same({ 55, "Vendor" }, { Prices.Get(unknown) })
    end)

    it("multiplies by the stack size and reports the same source", function()
        local env = base()
        local Prices = prices(env)
        assert.same({ 150, "Vendor" }, { Prices.Get(LINK, 5) })
    end)
end)

describe("farm session", function()
    it("starts on the first loot and counts gold only around a loot window", function()
        local env = farmEnv()
        local module = enable(env)
        assert.equal(0, module:Elapsed())
        env.now = 10
        env:Loot("You receive loot: " .. LINK .. "x3.")
        assert.is_true(module:IsRunning())
        assert.equal(3, module.session.itemCount)
        assert.equal(90, module.session.itemValue)
        -- Money outside a loot window is a vendor sale or mail, never farmed gold.
        env.money = 1500
        env:Fire("PLAYER_MONEY")
        assert.equal(0, module.session.gold)
        env:Fire("LOOT_OPENED")
        env.money = 1800
        env:Fire("PLAYER_MONEY")
        assert.equal(300, module.session.gold)
        assert.equal(1, module.session.mobs)
        assert.equal(390, module:Total())
    end)

    it("ignores another player's loot", function()
        local env = farmEnv()
        local module = enable(env)
        env:Loot("You receive loot: " .. LINK .. ".", "Player-other")
        assert.equal(0, module.session.itemCount)
        assert.is_false(module:IsRunning())
    end)

    it("pauses itself after the idle timeout and leaves that time out of the rate", function()
        local env = farmEnv()
        env.R.Settings:SetOption("farmIdleSeconds", 60)
        local module = enable(env)
        env:Loot("loot " .. LINK)
        env:Advance(30)
        assert.is_true(module:IsRunning())
        env:Advance(40)
        assert.is_true(module:IsPaused())
        local active = module:Elapsed()
        assert.equal(60, active)
        env:Advance(120)
        -- Paused time is excluded: the clock has not moved while nothing was dropping.
        assert.equal(active, module:Elapsed())
        assert.is_true(module:PausedSeconds() >= 120)
        env:Loot("loot " .. LINK)
        assert.is_true(module:IsRunning())
    end)

    it("keeps a manual pause through a loot, and only the pause icon lifts it", function()
        local env = farmEnv()
        local module = enable(env)
        env:Loot("loot " .. LINK)
        module:ToggleManualPause()
        assert.is_true(module:IsPaused())
        env:Advance(5)
        env:Loot("loot " .. LINK)
        assert.is_true(module:IsPaused())
        -- Looting while paused still records the drop; it is the clock that is stopped.
        assert.equal(2, module.session.itemCount)
        module.host.pause:GetScript("OnClick")(module.host.pause)
        assert.is_true(module:IsRunning())
    end)

    it("hides the meter with no goal and fills it against one", function()
        local env = farmEnv()
        local module = enable(env)
        assert.is_nil(module:GoalProgress())
        assert.is_false(module.host.track:IsShown())
        env.R.Settings:SetOption("farmGoalGold", 100)
        env.now = 10
        env:Loot("loot " .. itemLink(3000, "Rich Thing"))
        env.vendorPrices[3000] = 10000000
        module:Reset()
        env:Loot("loot " .. itemLink(3000, "Rich Thing"))
        env:Advance(3600)
        module:Refresh()
        assert.is_true(module.host.track:IsShown())
        assert.is_true(module:GoalProgress() > 0)
    end)

    it("holds the reset icon to confirm, and a short press cancels", function()
        local env = farmEnv()
        local module = enable(env)
        env:Loot("loot " .. LINK)
        assert.equal(1, module.session.itemCount)
        local reset = module.host.reset
        reset:GetScript("OnMouseDown")(reset)
        assert.is_function(reset:GetScript("OnUpdate"))
        reset:GetScript("OnUpdate")(reset, 0.4)
        assert.is_true(module.host.holding)
        -- Released early: the session survives and the meter goes back to the goal.
        reset:GetScript("OnMouseUp")(reset)
        assert.is_nil(reset:GetScript("OnUpdate"))
        assert.is_nil(module.host.holding)
        assert.equal(1, module.session.itemCount)
        reset:GetScript("OnMouseDown")(reset)
        reset:GetScript("OnUpdate")(reset, 0.6)
        reset:GetScript("OnUpdate")(reset, 0.6)
        assert.is_nil(reset:GetScript("OnUpdate"))
        assert.equal(0, module.session.itemCount)
        assert.is_false(module:IsRunning())
    end)

    it("shows its controls on hover, and never the details panel", function()
        local env = farmEnv()
        local module = enable(env)
        local host = module.host
        env:Loot("loot " .. LINK)
        assert.is_false(host.expand:IsShown())
        host:GetScript("OnEnter")(host)
        assert.is_true(host.hovered)
        assert.equal("Farm session", env.GameTooltip.lines[1])
        -- Hover shows the grip and the icon row. What the HUD reports never moves with it.
        assert.is_false(host.expand:IsShown())
        host:GetScript("OnLeave")(host)
        assert.is_false(host.expand:IsShown())
    end)

    it("opens and closes the details panel from one button", function()
        local env = farmEnv()
        local module = enable(env)
        local host = module.host
        assert.is_false(host:Expanded())
        assert.is_false(host.expand:IsShown())
        assert.equal("Show the details", host.collapse.tipTitle)
        host.collapse:GetScript("OnClick")(host.collapse)
        assert.is_true(host:Expanded())
        assert.is_true(host.expand:IsShown())
        assert.equal(1, host.panelOpenGroup:GetPlayCount())
        assert.equal("Hide the details", host.collapse.tipTitle)
        -- The panel is not hover driven, so it stays open with the pointer nowhere near it.
        host:GetScript("OnLeave")(host)
        assert.is_true(host.expand:IsShown())
        host.collapse:GetScript("OnClick")(host.collapse)
        -- It leaves on the close animation, not on the click, so it is still up until the
        -- group finishes. The spec drives that finish the way the client would.
        assert.equal(1, host.panelCloseGroup:GetPlayCount())
        host.panelCloseGroup:GetScript("OnFinished")(host.panelCloseGroup)
        assert.is_false(host.expand:IsShown())
        assert.equal("Show the details", host.collapse.tipTitle)
    end)

    it("slides the panel down and turns the caret over, with no overshoot either side", function()
        local env = farmEnv()
        local module = enable(env)
        local host = module.host
        -- Collapsed points down, which is where the panel will come from.
        local down = host.collapse.art:GetRotation()
        assert.is_true(down > 3.1 and down < 3.2)
        host.collapse:GetScript("OnClick")(host.collapse)
        -- Exactly the half turn it owes. Nothing past the mark, nothing to come back from.
        assert.equal(-180, host.spinAnim:GetDegrees())
        -- The turn only lands on the target angle when the group finishes.
        host.spin:GetScript("OnFinished")(host.spin)
        assert.equal(0, host.collapse.art:GetRotation())
        -- One leg down, the exact distance it started above its anchor.
        local _, slideY = host.panelOpenSlide:GetOffset()
        assert.equal(-11, slideY)
        -- Closing is one leg upward, out of the way.
        host.collapse:GetScript("OnClick")(host.collapse)
        local _, riseY = host.panelCloseRise:GetOffset()
        assert.is_true(riseY > 0)
    end)

    it("drops the rates row out of the layout instead of leaving a gap where it was", function()
        local env = farmEnv()
        local module = enable(env)
        local host = module.host
        env:Loot("loot " .. LINK)
        local shortHeight = host.expand.contentHeight
        assert.is_false(host.expand.stats[2].icon:IsShown())
        env.R.Settings:SetOption("farmShowRates", true)
        module:Refresh()
        assert.is_true(host.expand.stats[2].icon:IsShown())
        -- Exactly one row taller, so the rows under it moved rather than a hole appearing.
        assert.equal(shortHeight + 17, host.expand.contentHeight)
        env.R.Settings:SetOption("farmShowRates", false)
        module:Refresh()
        assert.equal(shortHeight, host.expand.contentHeight)
    end)

    it("parks the panel on its anchor when a press interrupts the last animation", function()
        local env = farmEnv()
        local module = enable(env)
        local host = module.host
        host.collapse:GetScript("OnClick")(host.collapse)
        local stopped = host.panelOpenGroup.stopCount
        -- Pressed again mid-flight: both groups are stopped and the panel is put back on
        -- its resting anchor, so a half finished slide can never leave it adrift.
        host.collapse:GetScript("OnClick")(host.collapse)
        assert.equal(stopped + 1, host.panelOpenGroup.stopCount)
        assert.equal(stopped + 1, host.panelCloseGroup.stopCount)
        -- Reopening from that interrupted state still runs the whole opening move.
        host.collapse:GetScript("OnClick")(host.collapse)
        assert.is_true(host.expand:IsShown())
        assert.equal(2, host.panelOpenGroup:GetPlayCount())
    end)

    it("lands the panel and the caret if the HUD is hidden mid animation", function()
        local env = farmEnv()
        local module = enable(env)
        local host = module.host
        host.collapse:GetScript("OnClick")(host.collapse)
        local stopped = host.panelOpenGroup.stopCount
        host:GetScript("OnHide")(host)
        -- Stopped where it was, then put exactly where it belongs: open, on its anchor,
        -- with the caret on the angle the open state owns.
        assert.is_true(host.expand:IsShown())
        assert.equal(0, host.collapse.art:GetRotation())
        assert.equal(stopped + 1, host.panelOpenGroup.stopCount)
    end)

    it("remembers the panel state across a disable and enable", function()
        local env = farmEnv()
        local module = enable(env)
        module.host.collapse:GetScript("OnClick")(module.host.collapse)
        assert.is_true(module.host.expand:IsShown())
        env.R.Registry:Disable(module)
        assert.is_true(env.R.Registry:Enable(module))
        assert.is_true(module.host:Expanded())
        assert.is_true(module.host.expand:IsShown())
    end)

    it("treats its own buttons as part of itself, so reaching for one keeps the hover", function()
        local env = farmEnv()
        local module = enable(env)
        local host = module.host
        host:GetScript("OnEnter")(host)
        assert.is_true(host.hovered)
        -- The pointer is on the pause icon now, which took the mouse off the HUD itself.
        -- The hover state is what the grip and the icon row follow, so it must survive that.
        host.pause:GetScript("OnEnter")(host.pause)
        assert.is_true(host.hovered)
        assert.equal("Pause", env.GameTooltip.lines[1])
        -- Nothing is under the pointer any more, and the mock reports no frame as hovered.
        host.pause:GetScript("OnLeave")(host.pause)
        assert.is_false(host.hovered)
    end)

    it("says where the HUD went when the menu hides it", function()
        local env = farmEnv()
        local module = enable(env)
        module.host:ToggleMenu()
        env.menuEntries[5].func()
        assert.is_false(module.host:IsShown())
        assert.matches("Show it again under Options", table.concat(env.messages, "\n"))
    end)

    it("fills every expanded line and the five most valuable stacks", function()
        local env = farmEnv()
        local module = enable(env)
        env.vendorPrices = { [1] = 10, [2] = 20, [3] = 30, [4] = 40, [5] = 50, [6] = 60 }
        env.now = 10
        for id = 1, 6 do
            env:Loot("loot " .. itemLink(id, "Item " .. id))
        end
        env:Advance(3590)
        module:Refresh()
        local host = module.host
        host.collapse:GetScript("OnClick")(host.collapse)
        assert.is_true(host.expand:IsShown())
        -- One fact per icon: clock, rates, looted gold, item value. No bags, no paused time.
        -- The clock stopped at the idle timeout, which is why it reads three minutes and
        -- not the sixty the spec advanced through.
        assert.equal("Farming 3m 0s", host.expand.stats[1].text:GetText())
        assert.matches("items/hr", host.expand.stats[2].text:GetText())
        assert.matches("^Gold ", host.expand.stats[3].text:GetText())
        assert.matches("^Items ", host.expand.stats[4].text:GetText())
        -- Rates are opt in, so that row is not on screen unless it was asked for.
        assert.is_false(host.expand.stats[2].icon:IsShown())
        assert.is_false(host.expand.stats[2].text:IsShown())
        assert.matches("Best drop: Item 6", host.expand.best:GetText())
        -- Five rows for six items, the least valuable one left off, most valuable first.
        assert.equal("Item 6", host.expand.rows[1].name:GetText())
        assert.equal("Item 2", host.expand.rows[5].name:GetText())
        assert.is_false(host.expand.rows[5].shown == false)
    end)

    it("builds a summary with totals, a sorted list and a plain text block", function()
        local env = farmEnv()
        local module = enable(env)
        env.vendorPrices = { [7] = 100, [8] = 900 }
        env:Loot("loot " .. itemLink(7, "Cheap"))
        env:Loot("loot " .. itemLink(8, "Dear"))
        env:Fire("LOOT_OPENED")
        env.money = env.money + 250
        env:Fire("PLAYER_MONEY")
        local report = module:BuildReport()
        assert.equal("Dear", report.rows[1].name)
        assert.equal("Cheap", report.rows[2].name)
        assert.matches("Session value: 0g 12s 50c", table.concat(report.lines, "\n"))
        assert.matches("Mobs looted: 1, items looted: 2", table.concat(report.lines, "\n"))
        assert.matches("Prices from: Vendor", table.concat(report.lines, "\n"))
        -- The copy block is plain text: no texture escapes, nothing to strip by hand.
        assert.is_nil(report.text:find("|T", 1, true))
        assert.matches("Refactor farm session", report.text)
        module:OpenSummary()
        assert.is_true(env.R.UI.sessionSummary:IsShown())
        assert.equal("Dear", env.R.UI.sessionSummary.rows[1].name:GetText())
        env.R.UI.sessionSummary.copy:GetScript("OnClick")()
        assert.is_true(env.R.UI.sessionTextFrame:IsShown())
        assert.matches("Refactor farm session", env.R.UI.sessionTextFrame.box:GetText())
    end)

    it("says in the summary when the price source moved under a running session", function()
        local env = farmEnv()
        env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 700 end } } }
        env.R.Integrations:RegisterPriceProviders()
        local module = enable(env)
        env:Loot("loot " .. LINK)
        env.R.Settings:SetOption("priceAuctionator", true)
        env.R.Integrations:ApplyPriceOptions()
        env:Loot("loot " .. itemLink(9, "Later"))
        local text = table.concat(module:BuildReport().lines, "\n")
        assert.matches("price source changed", text)
        -- The session itself is intact: both drops are still in it.
        assert.equal(2, #module.session.order)
    end)

    it("offers the whole right click menu", function()
        local env = farmEnv()
        local module = enable(env)
        module.host:ToggleMenu()
        local labels = {}
        for _, entry in ipairs(env.menuEntries) do labels[#labels + 1] = entry.text end
        assert.same({ "Farm session", "Reset session", "Set goal", "Lock position", "Hide HUD",
            "Open session summary" }, labels)
        assert.equal(1, env.menuToggled)
        env.menuEntries[5].func()
        assert.is_false(env.R.Settings:GetOption("farmShowHud"))
        assert.is_false(module.host:IsShown())
    end)

    it("fills a fake session on command, names the provider and mentions the restart", function()
        local env = farmEnv()
        env:Load("Core/Commands.lua")
        assert.same({ env.R.L.CMD_FARM_TEST_OFF }, env.R.Commands:Dispatch("farmtest"))
        local module = enable(env)
        assert.is_nil(env.R.Commands:Dispatch("farmtest"))
        assert.is_true(module:Total() > 0)
        assert.equal(148, module.session.mobs)
        assert.equal(5, #module.session.order)
        local printed = table.concat(env.messages, "\n")
        assert.matches("Price provider detected: Vendor", printed)
        assert.matches("quit the game and start it again", printed)
        -- The rare drop is the best one, and the HUD is showing a rate.
        assert.matches("Best drop: Blue Sapphire", module.host.expand.best:GetText())
        assert.matches("/ hr", module.host.rate:GetText())
    end)

    it("leaves no timer, no subscription and no session behind when it is switched off", function()
        local env = farmEnv()
        local module = enable(env)
        env:Loot("loot " .. LINK)
        env:Fire("LOOT_OPENED")
        assert.is_true(env:ActiveTimers() > 0)
        env.R.Registry:Disable(module)
        assert.equal(0, env:ActiveTimers())
        for _, entries in pairs(env.R.Broker.events) do
            for _, entry in ipairs(entries) do
                assert.is_not.equal(module, entry.owner)
            end
        end
        assert.is_false(module.host:IsShown())
        assert.equal(0, module.session.itemCount)
        assert.is_nil(module.host.onReset)
        assert.is_true(env.R.Registry:Enable(module))
        assert.is_true(module.host:IsShown())
        env.R.Registry:Disable(module)
        assert.equal(0, env:ActiveTimers())
        assert.equal(0, #env.R.errors)
    end)
end)
