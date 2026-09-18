local Runtime = require("Tests.mock.runtime")

local function base()
    local env = Runtime.new()
    env:Load("Locales/Modules.enUS.lua")
    env.control, env.combat = false, false
    env.IsControlKeyDown = function() return env.control end
    env.InCombatLockdown = function() return env.combat end
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    return env
end

local function enable(env, path, id)
    env:Load(path)
    assert.is_true(env.R.Registry:Enable(id))
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
end

local function vendor()
    local env = base()
    env.bags, env.money, env.sales = {}, 10000000, {}
    env.MerchantFrame = { IsShown = function() return env.merchantOpen end }
    env.merchantOpen = true
    env.GetMoney = function() return env.money end
    env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    env.Enum = { TooltipDataLineType = { TradeTimeRemaining = 36 } }
    env.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 30 or 0 end,
        GetContainerItemInfo = function(bag, slot) return bag == 0 and env.bags[slot] or nil end,
        GetContainerItemQuestInfo = function(_, slot) return env.bags[slot].quest or {} end,
        GetContainerItemPurchaseInfo = function(_, slot) return env.bags[slot].purchase end,
        UseContainerItem = function(bag, slot)
            env.sales[#env.sales + 1] = { bag = bag, slot = slot, itemID = env.bags[slot].itemID }
            env.lastSale = { slot = slot, info = env.bags[slot] }
        end,
    }
    env.C_Item = { GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 50 end }
    env.C_TooltipInfo = { GetBagItem = function(_, slot)
        local info = env.bags[slot]
        if info.noTooltip then return nil end
        return { lines = info.tradeTimer and { { type = 36 } } or {} }
    end }
    function env:AddItem(slot, changes)
        local info = { itemID = slot, quality = 0, stackCount = 1, hyperlink = "item:" .. slot }
        for key, value in pairs(changes or {}) do info[key] = value end
        self.bags[slot] = info
        return info
    end
    function env:ConfirmSale()
        local sale = self.lastSale
        self.bags[sale.slot] = nil
        self.money = self.money + sale.info.stackCount * 50
        self:Fire("BAG_UPDATE_DELAYED")
    end
    return env
end

local function mail()
    local env = base()
    env.inbox, env.requests = {}, {}
    env.ATTACHMENTS_MAX = 16
    env.C_Mail = { IsCommandPending = function() return env.commandPending or false end }
    env.GetInboxNumItems = function() return #env.inbox end
    env.GetInboxHeaderInfo = function(index)
        local info = env.inbox[index]
        return nil, nil, nil, nil, info.money or 0, info.cod or 0, nil, info.items or 0,
            nil, nil, nil, nil, info.gm or false
    end
    env.HasInboxItem = function(index, slot) return slot <= (env.inbox[index].items or 0) end
    env.TakeInboxMoney = function(index) env.requests[#env.requests + 1] = { index = index, money = true } end
    env.TakeInboxItem = function(index, slot) env.requests[#env.requests + 1] = { index = index, slot = slot } end
    local controls = {
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetRunning = function(self, running) self.running = running end,
        SetProgress = function(self, text) self.text = text end,
    }
    env.R.UI = { CreateMailControls = function() return controls end }
    env.controls = controls
    return env
end

describe("M2 Retail modules", function()
    it("fast loot respects all auto-loot modifier combinations and skips locked slots", function()
        local env = base()
        local looted = {}
        local rates = {}
        env.C_CVar = {
            GetCVarBool = function() return env.autoLoot end,
            SetCVar = function(name, value) rates[name] = value end,
            GetCVarDefault = function() return "150" end,
        }
        env.IsModifiedClick = function(action) assert.equals("AUTOLOOTTOGGLE", action) return env.modified end
        env.GetNumLootItems = function() return 3 end
        env.GetLootSlotInfo = function(slot) return nil, nil, nil, nil, nil, slot == 2 end
        env.LootSlot = function(slot) looted[#looted + 1] = slot end
        local module = enable(env, "Modules/Loot/FastLoot.lua", "loot.fastLoot")
        assert.equal("0", rates.autoLootRate)
        -- LOOT_READY's own answer wins over the CVar and modifier pair.
        env.autoLoot, env.modified, looted = false, false, {}
        env:Fire("LOOT_READY", true)
        assert.same({ 3, 1 }, looted)
        looted = {}
        env:Fire("LOOT_READY", false)
        assert.same({}, looted)
        for _, autoLoot in ipairs({ false, true }) do
            for _, modified in ipairs({ false, true }) do
                env.autoLoot, env.modified, looted = autoLoot, modified, {}
                env:Fire("LOOT_OPENED")
                assert.same(autoLoot ~= modified and { 3, 1 } or {}, looted)
            end
        end
        env.autoLoot, env.modified, env.control, looted = true, false, true, {}
        env:Fire("LOOT_OPENED")
        assert.same({}, looted)
        env.control, env.combat = false, true
        env:Fire("LOOT_OPENED")
        assert.same({}, looted)
        env.R.Registry:Disable(module)
        assert.equal("150", rates.autoLootRate)
        noResidue(env, module)
        assert.is_true(env.R.Registry:Enable(module))
    end)

    it("marks automatic standing unavailable even when API names exist", function()
        local env = base()
        env.SitStandOrDescendStart = function() error("protected action called") end
        env:Load("Modules/Interface/AutoStand.lua")
        assert.is_false(env.R.Registry:Enable("interface.autoStand"))
        assert.equals("unavailable", env.R.moduleByID["interface.autoStand"].state)
    end)

    it("fills only the unprotected deletion edit box after Blizzard's event", function()
        local env = base()
        local editBox = {
            text = "", IsProtected = function(self) return self.protected end,
            GetText = function(self) return self.text end,
            SetText = function(self, text) self.text = text end,
        }
        local dialog = {
            IsProtected = function(self) return self.protected end,
            GetEditBox = function() return editBox end,
        }
        env.DELETE_ITEM_CONFIRM_STRING = "DELETE"
        env.StaticPopup_FindVisible = function(which)
            assert.equals("DELETE_GOOD_ITEM", which)
            return env.popupVisible and dialog
        end
        local module = enable(env, "Modules/Items/DeleteFill.lua", "items.deleteFill")
        env:Fire("DELETE_ITEM_CONFIRM")
        env.popupVisible = true
        env:Advance(0)
        assert.equals("DELETE", editBox.text)
        editBox.text, dialog.protected = "", true
        env:Fire("DELETE_ITEM_CONFIRM")
        env:Advance(0)
        assert.equals("", editBox.text)
        dialog.protected, editBox.protected = false, true
        env:Fire("DELETE_ITEM_CONFIRM")
        env:Advance(0)
        assert.equals("", editBox.text)
        editBox.protected, editBox.text = false, "user text"
        env:Fire("DELETE_ITEM_CONFIRM")
        env:Advance(0)
        assert.equals("user text", editBox.text)
        env:Fire("DELETE_ITEM_CONFIRM")
        noResidue(env, module)
        assert.is_true(env.R.Registry:Enable(module))
    end)

    it("never-sell, quest, lock, refund and trade restrictions override grey quality", function()
        local env = vendor()
        env.R.Settings.account.options.neverSellIDs = { [1] = true, ["2"] = true }
        env:AddItem(1)
        env:AddItem(2)
        env:AddItem(3, { quality = 1 })
        env:AddItem(4, { quest = { isQuestItem = true } })
        env:AddItem(5, { isLocked = true })
        env:AddItem(6, { purchase = { refundSeconds = 100 } })
        env:AddItem(7, { tradeTimer = true })
        env:AddItem(8, { noTooltip = true })
        env:AddItem(9, { quest = { questID = 123 } })
        env:AddItem(10, { hasNoValue = true })
        env:AddItem(11)
        local module = enable(env, "Modules/Vendor/AutoSell.lua", "vendor.autoSell")
        env:Fire("MERCHANT_SHOW")
        env:Advance(0.2)
        assert.equals(11, env.sales[1].itemID)
        noResidue(env, module)
        assert.is_true(env.R.Registry:Enable(module))
    end)

    it("rescans changed slots and stops at twelve confirmed stack sales per visit", function()
        local env = vendor()
        for slot = 1, 15 do env:AddItem(slot) end
        local module = enable(env, "Modules/Vendor/AutoSell.lua", "vendor.autoSell")
        env:Fire("MERCHANT_SHOW")
        env.bags[1].quality = 4
        for _ = 1, 12 do
            env:Advance(0.21)
            env:ConfirmSale()
        end
        env:Advance(1)
        assert.equals(12, #env.sales)
        assert.equals(2, env.sales[1].itemID)
        assert.is_not_nil(env.bags[1])
        assert.is_false(module.active)
        noResidue(env, module)
    end)

    it("waits for money and bag confirmation, cancels on close, combat and Ctrl", function()
        local env = vendor()
        env:AddItem(1)
        local module = enable(env, "Modules/Vendor/AutoSell.lua", "vendor.autoSell")
        env:Fire("MERCHANT_SHOW")
        env:Advance(0.2)
        env:Fire("BAG_UPDATE_DELAYED")
        env:Advance(1)
        assert.equals(1, #env.sales)
        env:Fire("MERCHANT_CLOSED")
        assert.equals(0, env:ActiveTimers())
        env:Fire("MERCHANT_SHOW")
        env.control = true
        env:Advance(1)
        assert.equals(1, #env.sales)
        env.control = false
        env:Fire("MERCHANT_SHOW")
        env:Fire("PLAYER_REGEN_DISABLED")
        env:Advance(1)
        assert.equals(1, #env.sales)
        noResidue(env, module)
    end)

    it("repairs only within cap and own balance, never using guild funds", function()
        local env = vendor()
        local repairs = 0
        env.repairCost = 500000
        env.CanMerchantRepair = function() return true end
        env.GetRepairAllCost = function() return env.repairCost, env.repairCost > 0 end
        env.RepairAllItems = function(guild)
            assert.is_false(guild)
            repairs = repairs + 1
            env.money, env.repairCost = env.money - env.repairCost, 0
        end
        local module = enable(env, "Modules/Vendor/AutoRepair.lua", "vendor.autoRepair")
        env:Fire("MERCHANT_SHOW")
        assert.equals(1, repairs)
        env.repairCost = 1000001
        env:Fire("MERCHANT_SHOW")
        assert.equals(1, repairs)
        env.R.Settings.account.options.repairCapGold = 0
        env.repairCost = 1
        env:Fire("MERCHANT_SHOW")
        assert.equals(1, repairs)
        env.R.Settings.account.options.repairCapGold = 100
        env.money = 0
        env:Fire("MERCHANT_SHOW")
        assert.equals(1, repairs)
        noResidue(env, module)
        assert.is_true(env.R.Registry:Enable(module))
    end)

    it("summarizes only confirmed vendor events and resets each visit", function()
        local env = base()
        local module = enable(env, "Modules/Vendor/Summary.lua", "vendor.summary")
        env:Fire("MERCHANT_SHOW")
        env.R.Broker:Emit("REFACTOR_VENDOR_SOLD", 3, 150)
        env.R.Broker:Emit("REFACTOR_VENDOR_REPAIRED", 10000)
        env:Fire("MERCHANT_CLOSED")
        assert.equals("Sold 3 items for 0g 1s 50c; repaired for 1g 0s 0c.", env.messages[1])
        env:Fire("MERCHANT_SHOW")
        env:Fire("MERCHANT_CLOSED")
        assert.equals(1, #env.messages)
        noResidue(env, module)
        assert.is_true(env.R.Registry:Enable(module))
    end)

    it("mail waits for explicit start, skips COD/GM/text and follows inbox reindexing", function()
        local env = mail()
        env.inbox = { { cod = 20, items = 1 }, { gm = true, items = 1 }, {}, { money = 200 }, { items = 1 } }
        local module = enable(env, "Modules/Mail/TakeAll.lua", "mail.takeAll")
        env:Fire("MAIL_SHOW")
        assert.equals(0, #env.requests)
        assert.is_true(env.controls.shown)
        module:Start()
        assert.same({ index = 4, money = true }, env.requests[1])
        table.remove(env.inbox, 4)
        env:Fire("MAIL_INBOX_UPDATE")
        env:Advance(0.19)
        assert.equals(1, #env.requests)
        env:Advance(0.22)
        assert.same({ index = 4, slot = 1 }, env.requests[2])
        table.remove(env.inbox, 4)
        env:Fire("MAIL_INBOX_UPDATE")
        env:Advance(0.5)
        assert.is_false(module.running)
        assert.equals(2, module.completed)
        assert.equals(3, #env.inbox)
        noResidue(env, module)
        assert.is_true(env.R.Registry:Enable(module))
    end)

    it("mail never repeats a stale request without acknowledged progress", function()
        local env = mail()
        env.inbox = { { items = 1 } }
        local module = enable(env, "Modules/Mail/TakeAll.lua", "mail.takeAll")
        env:Fire("MAIL_SHOW")
        module:Start()
        env:Fire("MAIL_INBOX_UPDATE")
        env:Advance(6)
        assert.equals(1, #env.requests)
        assert.is_false(module.running)
        assert.equals(env.R.L.MAIL_TIMEOUT, env.controls.text)
        noResidue(env, module)
    end)

    it("mail stops pending work on button, failure, combat and mailbox close", function()
        local env = mail()
        env.inbox = { { money = 100 } }
        local module = enable(env, "Modules/Mail/TakeAll.lua", "mail.takeAll")
        env:Fire("MAIL_SHOW")
        module:Start()
        module:Stop()
        env:Advance(6)
        assert.equals(1, #env.requests)
        module:Start()
        env:Fire("MAIL_FAILED")
        assert.is_false(module.running)
        module:Start()
        env:Fire("PLAYER_REGEN_DISABLED")
        assert.is_false(module.running)
        module:Start()
        env:Fire("MAIL_CLOSED")
        assert.is_false(module.running)
        assert.is_false(env.controls.shown)
        assert.equals(0, env:ActiveTimers())
        noResidue(env, module)
    end)
end)
