local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local ID = "items.sendToAlts"
local MAX_SEND = 12
local HERB, ORE, CLOTH, POTION, FLASK, BLUE_BOE, GREY_BOE, EPIC_BOP = 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008
local ITEMS = {
    [HERB] = { name = "Peacebloom", class = 7, sub = 9 },
    [ORE] = { name = "Copper Ore", class = 7, sub = 7 },
    [CLOTH] = { name = "Linen Cloth", class = 7, sub = 5 },
    [POTION] = { name = "Healing Potion", class = 0, sub = 1 },
    [FLASK] = { name = "Crafting Flask", class = 0, sub = 3, crafting = true },
    [BLUE_BOE] = { name = "Blue Helm", class = 4, sub = 1, bind = 2, quality = 3 },
    [GREY_BOE] = { name = "Grey Helm", class = 4, sub = 1, bind = 2, quality = 0 },
    [EPIC_BOP] = { name = "Epic Helm", class = 4, sub = 1, bind = 1, quality = 4 },
}
local PROFESSION_LINE = { Alchemy = 2000, Blacksmithing = 2001, Cooking = 2002 }

local function nameOf(id)
    return ITEMS[id] and ITEMS[id].name or ("Item " .. id)
end

local function link(id)
    return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. nameOf(id) .. "]|h|r"
end

local function said(env, text)
    for _, message in ipairs(env.messages) do
        if message:find(text, 1, true) then return true end
    end
    return false
end

-- A mailbox and a bag server. A stack picked up is locked where it was; a stack attached stays locked
-- there until the mail is sent, which env:Complete() does the way the server answers.
local function world(options)
    options = options or {}
    local env = Runtime.new()
    Widgets.install(env)
    for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Mail.enUS.lua" }) do
        env:Load(path)
    end
    env.control, env.shift, env.money, env.postage = false, false, 0, 30
    env.IsControlKeyDown = function() return env.control end
    env.IsShiftKeyDown = function() return env.shift end
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end

    env.pname, env.psurname, env.realm = options.name or "Mainchar", options.surname or "", "Realm"
    env.UnitGUID = function() return "Player-main" end
    env.UnitName = function() return env.pname, env.psurname end
    env.GetRealmName = function() return env.realm end
    env.GetMoney = function() return env.money end
    env.GetSendMailPrice = function() return env.postage end
    env.ATTACHMENTS_MAX_SEND = MAX_SEND
    env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
    env.GameTooltip = { GetOwner = function() end, Hide = function() end }
    env.MenuUtil = { CreateContextMenu = function() end }
    env.MoneyInputFrame_SetCopper = function(frame, copper) frame.copper = copper end
    env.SendMailMoney = env.CreateFrame("Frame", "SendMailMoney")

    env.Enum = {
        ItemClass = { Tradegoods = 7, Gem = 3, Reagent = 5, Recipe = 9, Armor = 4, Weapon = 2 },
        ItemQuality = { Uncommon = 2 },
        ItemBind = { OnEquip = 2 },
        Profession = { Alchemy = 1, Blacksmithing = 2, Engineering = 3, Tailoring = 4, Leatherworking = 5,
            Enchanting = 6, Jewelcrafting = 7, Inscription = 8, Cooking = 9 },
    }
    env.C_TradeSkillUI = {
        GetProfessionSkillLineID = function(id) return 2000 + id end,
    }
    env.professions = options.professions or {}
    env.GetProfessions = function() return env.professions[1], env.professions[2], nil, nil, env.professions[3] end
    env.GetProfessionInfo = function(index) return "Profession", 1, 1, 1, 0, 0, 2000 + index end
    env.PROFESSION_LINE = PROFESSION_LINE

    env.C_Item = {
        GetItemInfoInstant = function(id)
            local item = ITEMS[id]
            if not item then return nil end
            return id, "", "", "", 1, item.class, item.sub
        end,
        GetItemInfo = function(id)
            local item = ITEMS[id]
            if not item then return nil end
            return item.name, link(id), item.quality or 1, 1, 1, "", "", 1, "", 1, 1, item.class, item.sub,
                item.bind or 1, 0, 0, item.crafting or false
        end,
        GetItemQualityColor = function() return 1, 1, 1 end,
    }

    env.bag = { size = 16, items = {} }
    env.attachments = {}
    env.cursor = nil
    env.questItems = {}
    function env:Put(slot, id, extra)
        local info = { itemID = id, hyperlink = link(id), iconFileID = 500 + id, stackCount = 5,
            quality = ITEMS[id] and ITEMS[id].quality or 1, isLocked = false, isBound = false, hasLoot = false }
        for key, value in pairs(extra or {}) do info[key] = value end
        self.bag.items[slot] = info
        return info
    end
    env.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and env.bag.size or 0 end,
        GetContainerItemInfo = function(bag, slot) return bag == 0 and env.bag.items[slot] or nil end,
        GetContainerItemQuestInfo = function(_, slot)
            local info = env.bag.items[slot]
            return { isQuestItem = info ~= nil and env.questItems[info.itemID] == true }
        end,
        PickupContainerItem = function(bag, slot)
            local info = bag == 0 and env.bag.items[slot]
            if not env.cursor and info and not info.isLocked then
                info.isLocked = true
                env.cursor = { info = info, slot = slot }
            end
        end,
    }
    env.CursorHasItem = function() return env.cursor ~= nil end
    env.ClearCursor = function()
        if env.cursor then
            env.cursor.info.isLocked = false
            env.cursor = nil
        end
    end
    env.ClickSendMailItemButton = function()
        local held = env.cursor
        if not held then return end
        for index = 1, MAX_SEND do
            if not env.attachments[index] then
                env.attachments[index] = held
                env.cursor = nil
                return
            end
        end
    end
    env.HasSendMailItem = function(index) return env.attachments[index] ~= nil end
    env.GetSendMailItem = function(index)
        local held = env.attachments[index]
        if not held then return nil end
        return nameOf(held.info.itemID), held.info.itemID, held.info.iconFileID, held.info.stackCount
    end
    env.GetSendMailItemLink = function(index)
        local held = env.attachments[index]
        return held and held.info.hyperlink
    end

    env.MailFrame = env.CreateFrame("Frame", "MailFrame")
    env.SendMailFrame = env.CreateFrame("Frame", "SendMailFrame")
    env.hookedScripts = { OnShow = {}, OnHide = {} }
    env.hookScriptCalls = 0
    env.SendMailFrame.HookScript = function(_, name, fn)
        env.hookScriptCalls = env.hookScriptCalls + 1
        table.insert(env.hookedScripts[name], fn)
    end
    env.SendMailNameEditBox = env.CreateFrame("EditBox", "SendMailNameEditBox")
    env.SendMail = function() end
    env.sendHooks = {}
    env.hooksecurefunc = function(name, fn)
        assert.is_function(env[name])
        table.insert(env.sendHooks, fn)
    end

    function env:OpenMailbox()
        self:Fire("MAIL_SHOW")
        self:Advance(0.5)
    end
    function env:ShowSend()
        self.SendMailFrame:Show()
        for _, fn in ipairs(self.hookedScripts.OnShow) do fn(self.SendMailFrame) end
        self:Advance(0.5)
    end
    function env:HideSend()
        self.SendMailFrame:Hide()
        for _, fn in ipairs(self.hookedScripts.OnHide) do fn(self.SendMailFrame) end
    end
    function env:Open()
        self:OpenMailbox()
        self:ShowSend()
    end
    -- Attaches the way a hand would, to whoever is in To.
    function env:Attach(slot)
        self.C_Container.PickupContainerItem(0, slot)
        self.ClickSendMailItemButton()
    end
    function env:AttachedCount()
        local count = 0
        for index = 1, MAX_SEND do
            if self.attachments[index] then count = count + 1 end
        end
        return count
    end
    function env:PressSend(recipient)
        for _, fn in ipairs(self.sendHooks) do fn(recipient, "subject", "body") end
    end
    -- The server's answer: attachments leave the mail and the bags, To empties, the bags report it.
    function env:Complete()
        for index = 1, MAX_SEND do
            local held = self.attachments[index]
            if held then
                self.bag.items[held.slot] = nil
                self.attachments[index] = nil
            end
        end
        self.SendMailNameEditBox:SetText("")
        self:Fire("MAIL_SEND_SUCCESS")
        self:Fire("BAG_UPDATE_DELAYED")
        self:Advance(0.5)
    end

    env.R.UI = env.R.UI or {}
    env:Load("UI/MailAlts.lua")
    env:Load("Modules/Items/SendToAlts.lua")
    local module = env.R.moduleByID[ID]
    for guid, entry in pairs(options.roster or {}) do
        local roster = env.R.Settings:GetOption("mailRoster")
        roster[guid] = entry
        assert.is_true(env.R.Settings:SetOption("mailRoster", roster))
    end
    if options.bankAlt then env.R.Settings:SetOption("mailBankAlt", options.bankAlt) end
    env.module = module
    return env, module
end

local function enable(env, module)
    assert.is_true(env.R.Registry:Enable(ID), tostring(module.failure) .. " "
        .. table.concat(module.missing or {}, ","))
    assert.equal("enabled", module.state)
    env:Advance(0)
end

local ALT = { ["Player-alt"] = { name = "Bankalt", realm = "Realm" } }

local function ready(options)
    options = options or {}
    options.roster = options.roster or ALT
    options.bankAlt = options.bankAlt or "Bankalt"
    local env, module = world(options)
    enable(env, module)
    return env, module
end

local function suggested(module)
    local ids = {}
    for _, group in ipairs(module:Groups()) do
        for _, entry in ipairs(group.entries) do ids[#ids + 1] = entry.itemID end
    end
    table.sort(ids)
    return ids
end

describe("send to alts", function()
    describe("precedence", function()
        after_each(function()
            ITEMS[2001], ITEMS[2002] = nil, nil
        end)

        it("never suggests bound, quest, locked, looted or never-listed items", function()
            local env, module = ready()
            ITEMS[2001] = { name = "Kept Herb", class = 7, sub = 9 }
            ITEMS[2002] = { name = "Never Herb", class = 7, sub = 9 }
            env:Put(1, HERB, { isBound = true })
            env:Put(2, ORE)
            env.questItems[ORE] = true
            env:Put(3, CLOTH, { isLocked = true })
            env:Put(4, 2001)
            env:Put(5, HERB, { hasLoot = true })
            env:Put(6, 2002)
            env.R.Settings:SetOption("mailNeverIDs", { [2002] = true })
            env:Open()
            assert.same({ 2001 }, suggested(module))
        end)

        it("lets an item route beat the category route", function()
            local env, module = ready({ roster = {
                ["Player-alt"] = { name = "Bankalt", realm = "Realm" },
                ["Player-herbs"] = { name = "Herbalt", realm = "Realm" },
                ["Player-item"] = { name = "Itemalt", realm = "Realm" },
            } })
            env.R.Settings:SetOption("mailRoutes", { herb = "Herbalt" })
            env.R.Settings:SetOption("mailItemRoutes", { [HERB] = "Itemalt" })
            env:Put(1, HERB)
            env:Open()
            local groups = module:Groups()
            assert.equal(1, #groups)
            assert.equal("Itemalt", groups[1].recipient)
            assert.equal("item", groups[1].entries[1].reason)
        end)

        it("keeps a category whose route is false", function()
            local env, module = ready()
            env.R.Settings:SetOption("mailRoutes", { herb = false })
            env:Put(1, HERB)
            env:Put(2, ORE)
            env:Open()
            assert.same({ ORE }, suggested(module))
        end)

        it("sends a category without a route to the bank alt", function()
            local env, module = ready()
            env:Put(1, CLOTH)
            env:Open()
            local groups = module:Groups()
            assert.equal(1, #groups)
            assert.equal("Bankalt", groups[1].recipient)
            assert.equal("cloth", groups[1].entries[1].reason)
        end)

        it("suggests nothing without a bank alt and without a route", function()
            local env, module = world({ roster = ALT })
            enable(env, module)
            env:Put(1, CLOTH)
            env:Put(2, HERB)
            env:Open()
            assert.same({}, suggested(module))
            env.R.Settings:SetOption("mailRoutes", { herb = "Bankalt" })
            module:Refresh()
            assert.same({ HERB }, suggested(module))
        end)

        it("suggests gear only when it binds on equip and is at least uncommon", function()
            local env, module = ready()
            env:Put(1, BLUE_BOE)
            env:Put(2, GREY_BOE)
            env:Put(3, EPIC_BOP)
            env:Open()
            assert.same({ BLUE_BOE }, suggested(module))
            assert.equal("gear", module:Groups()[1].entries[1].reason)
        end)

        it("leaves a consumable alone and sends a crafting reagent to reagents", function()
            local env, module = ready()
            env:Put(1, POTION)
            env:Put(2, FLASK)
            env:Open()
            assert.same({ FLASK }, suggested(module))
            assert.equal("reagents", module:Groups()[1].entries[1].reason)
        end)
    end)

    describe("own crafts", function()
        it("keeps herbs for an alchemist, unless an item route names the herb", function()
            local env, module = world({ roster = ALT, bankAlt = "Bankalt", professions = { 1 } })
            enable(env, module)
            env:Put(1, HERB)
            env:Put(2, ORE)
            env:Open()
            assert.same({ ORE }, suggested(module))
            env.R.Settings:SetOption("mailItemRoutes", { [HERB] = "Bankalt" })
            module:Refresh()
            assert.same({ HERB, ORE }, suggested(module))
        end)

        it("suggests herbs for an alchemist when keeping crafts is off", function()
            local env, module = world({ roster = ALT, bankAlt = "Bankalt", professions = { 1 } })
            enable(env, module)
            env.R.Settings:SetOption("mailKeepCrafts", false)
            env:Put(1, HERB)
            env:Open()
            assert.same({ HERB }, suggested(module))
        end)
    end)

    describe("roster", function()
        it("records the logged in character by GUID with its surname", function()
            local env, module = world({ surname = "Wanderer" })
            enable(env, module)
            local entry = env.R.Settings:GetOption("mailRoster")["Player-main"]
            assert.same({ name = "Mainchar", surname = "Wanderer", realm = "Realm" }, entry)
            assert.is_true(module:IsMe("Mainchar"))
            assert.is_true(module:IsMe("mainchar wanderer"))
            assert.is_false(module:IsMe("Bankalt"))
        end)

        it("lists other characters on this realm only, never the current one", function()
            local env, module = world({ roster = {
                ["Player-a"] = { name = "Zeta", realm = "Realm" },
                ["Player-b"] = { name = "Alpha", realm = "Realm" },
                ["Player-c"] = { name = "Faraway", realm = "Other" },
                ["Player-main"] = { name = "Mainchar", realm = "Realm" },
            } })
            enable(env, module)
            assert.same({ "Alpha", "Zeta" }, module:Characters())
        end)

        it("offers and writes the whole name when a character has a surname", function()
            local env, module = world({ bankAlt = "Mel", roster = {
                ["Player-mel"] = { name = "Mel", surname = "Fortune", realm = "Realm" },
            } })
            env.R.Settings:SetOption("mailRoutes", { herb = "Mel" })
            enable(env, module)
            assert.same({ "Mel Fortune" }, module:Characters())
            assert.equal("Mel Fortune", env.R.Settings:GetOption("mailBankAlt"))
            assert.same({ herb = "Mel Fortune" }, env.R.Settings:GetOption("mailRoutes"))
            env:Put(1, CLOTH)
            env:Open()
            module:Click(module:SelectedGroup().entries[1])
            assert.equal("Mel Fortune", env.SendMailNameEditBox:GetText())
        end)

        it("never suggests the current character as the recipient", function()
            local env, module = world({ surname = "Wanderer", bankAlt = "Mainchar Wanderer", roster = ALT })
            enable(env, module)
            env:Put(1, CLOTH)
            env:Open()
            assert.same({}, suggested(module))
            env.R.Settings:SetOption("mailBankAlt", "mainchar")
            module:Refresh()
            assert.same({}, suggested(module))
            assert.same({ "Bankalt" }, module:Recipients())
        end)
    end)

    describe("panel", function()
        it("stays hidden when the player has no other known character", function()
            local env, module = world()
            enable(env, module)
            env:Put(1, CLOTH)
            env:Open()
            assert.is_false(module:HasRecipients())
            assert.is_false(module.panel:IsShown())
        end)

        it("shows on the send tab once there is another character", function()
            local env, module = ready()
            env:Put(1, CLOTH)
            env:OpenMailbox()
            assert.is_false(module.panel:IsShown())
            env:ShowSend()
            assert.is_true(module.panel:IsShown())
            env:HideSend()
            assert.is_false(module.panel:IsShown())
        end)
    end)

    describe("attaching", function()
        it("attaches one stack and fills To with the group's recipient", function()
            local env, module = ready()
            env:Put(1, CLOTH)
            env:Put(2, CLOTH)
            env:Open()
            local cell = module.panel.cells[1]
            assert.is_table(cell.entry)
            cell.scripts.OnClick(cell, "LeftButton")
            assert.equal(1, env:AttachedCount())
            assert.equal("Bankalt", env.SendMailNameEditBox:GetText())
            assert.is_nil(env.cursor)
        end)

        it("refuses when the mail holds items for someone else", function()
            local env, module = ready()
            env:Put(1, CLOTH)
            env:Put(2, ORE)
            env:Open()
            env.SendMailNameEditBox:SetText("Stranger")
            env:Attach(2)
            assert.equal(1, env:AttachedCount())
            module:Click(module:SelectedGroup().entries[1])
            assert.equal(1, env:AttachedCount())
            assert.equal("Stranger", env.SendMailNameEditBox:GetText())
            assert.is_true(said(env, string.format(env.R.L.MAIL_ALTS_OTHER_RECIPIENT, "Stranger")))
        end)

        it("refuses while the cursor holds an item", function()
            local env, module = ready()
            env:Put(1, CLOTH)
            env:Put(2, POTION)
            env:Open()
            env.C_Container.PickupContainerItem(0, 2)
            assert.is_true(env.CursorHasItem())
            module:Click(module:SelectedGroup().entries[1])
            assert.equal(0, env:AttachedCount())
            assert.is_true(said(env, env.R.L.MAIL_ALTS_CURSOR))
        end)
    end)

    describe("fill", function()
        local function manyHerbs(env, count)
            for slot = 1, count do env:Put(slot, HERB) end
        end

        it("attaches at most the free slots, then the rest after the send", function()
            local env, module = ready({ bankAlt = "Bankalt" })
            env.R.Settings:SetOption("mailKeepCrafts", false)
            manyHerbs(env, 15)
            env:Open()
            assert.equal(15, #module:SelectedGroup().entries)
            module:Fill()
            assert.equal(MAX_SEND, env:AttachedCount())
            assert.equal("Bankalt", env.SendMailNameEditBox:GetText())
            env:PressSend("Bankalt")
            env:Complete()
            assert.equal(3, env:AttachedCount())
            assert.equal("Bankalt", env.SendMailNameEditBox:GetText())
            assert.equal(0, #module:Groups())
        end)

        it("brings no next batch while the pause modifier is held", function()
            local env, module = ready({ bankAlt = "Bankalt" })
            manyHerbs(env, 15)
            env:Open()
            module:Fill()
            assert.equal(MAX_SEND, env:AttachedCount())
            env:PressSend("Bankalt")
            env.control = true
            env:Complete()
            assert.equal(0, env:AttachedCount())
            assert.equal("", env.SendMailNameEditBox:GetText())
        end)
    end)

    describe("learning", function()
        local function twoAlts()
            return ready({ roster = {
                ["Player-alt"] = { name = "Bankalt", realm = "Realm" },
                ["Player-other"] = { name = "Otheralt", realm = "Realm" },
            } })
        end

        it("records a hand-mailed item once and promotes it to a route the second time", function()
            local env = twoAlts()
            env:Put(1, HERB)
            env:Open()
            env.SendMailNameEditBox:SetText("Otheralt")
            env:Attach(1)
            env:PressSend("Otheralt")
            env:Complete()
            assert.same({ [HERB] = "Otheralt" }, env.R.Settings:GetOption("mailLearning"))
            assert.same({}, env.R.Settings:GetOption("mailItemRoutes"))
            env:Put(2, HERB)
            env.SendMailNameEditBox:SetText("Otheralt")
            env:Attach(2)
            env:PressSend("Otheralt")
            env:Complete()
            assert.same({}, env.R.Settings:GetOption("mailLearning"))
            assert.same({ [HERB] = "Otheralt" }, env.R.Settings:GetOption("mailItemRoutes"))
        end)

        it("teaches nothing when the recipient is not one of the player's characters", function()
            local env = twoAlts()
            env:Put(1, HERB)
            env:Put(2, HERB)
            env:Open()
            for slot = 1, 2 do
                env.SendMailNameEditBox:SetText("Stranger")
                env:Attach(slot)
                env:PressSend("Stranger")
                env:Complete()
            end
            assert.same({}, env.R.Settings:GetOption("mailLearning"))
            assert.same({}, env.R.Settings:GetOption("mailItemRoutes"))
        end)

        it("drops the snapshot when the mail fails", function()
            local env, module = twoAlts()
            env:Put(1, HERB)
            env:Open()
            env.SendMailNameEditBox:SetText("Otheralt")
            env:Attach(1)
            env:PressSend("Otheralt")
            assert.is_table(module.sending)
            env:Fire("MAIL_FAILED")
            assert.is_nil(module.sending)
            env:Complete()
            assert.same({}, env.R.Settings:GetOption("mailLearning"))
        end)
    end)

    describe("fill recipient", function()
        it("fills an empty To with the first group on the next tick", function()
            local env, module = ready()
            env:Put(1, CLOTH)
            env:OpenMailbox()
            env.SendMailFrame:Show()
            for _, fn in ipairs(env.hookedScripts.OnShow) do fn(env.SendMailFrame) end
            assert.equal("", env.SendMailNameEditBox:GetText())
            env:Advance(0.1)
            assert.equal("Bankalt", env.SendMailNameEditBox:GetText())
            assert.equal("bankalt", module.selected)
        end)

        it("leaves To empty when the option is off", function()
            local env = ready()
            env.R.Settings:SetOption("mailFillRecipient", false)
            env:Put(1, CLOTH)
            env:Open()
            assert.equal("", env.SendMailNameEditBox:GetText())
        end)
    end)

    describe("gold", function()
        it("puts the gold above what is kept, less postage, in the money field", function()
            local env, module = ready()
            env.R.Settings:SetOption("mailKeepGold", 100)
            env.money = 250 * 10000
            env:Put(1, CLOTH)
            env:Open()
            module:AddGold()
            assert.equal(250 * 10000 - 100 * 10000 - 30, env.SendMailMoney.copper)
        end)

        it("says so when there is no gold above what is kept", function()
            local env, module = ready()
            env.R.Settings:SetOption("mailKeepGold", 100)
            env.money = 50 * 10000
            env:Put(1, CLOTH)
            env:Open()
            module:AddGold()
            assert.is_nil(env.SendMailMoney.copper)
            assert.is_true(said(env, env.R.L.MAIL_ALTS_NO_GOLD))
        end)
    end)

    describe("settings", function()
        it("rejects malformed mail options and accepts good ones", function()
            local env = ready()
            local Settings = env.R.Settings
            assert.is_false(Settings:SetOption("mailRoutes", { herb = 5 }))
            assert.is_false(Settings:SetOption("mailRoutes", { herb = true }))
            assert.is_true(Settings:SetOption("mailRoutes", { herb = "Bankalt", ore = false }))
            assert.is_false(Settings:SetOption("mailItemRoutes", { herb = "Bankalt" }))
            assert.is_false(Settings:SetOption("mailItemRoutes", { [0] = "Bankalt" }))
            assert.is_false(Settings:SetOption("mailItemRoutes", { [HERB] = false }))
            assert.is_true(Settings:SetOption("mailItemRoutes", { [HERB] = "Bankalt" }))
            assert.is_false(Settings:SetOption("mailRoster", { ["Player-x"] = { name = "", realm = "Realm" } }))
            assert.is_false(Settings:SetOption("mailRoster", { ["Player-x"] = { name = "Alt" } }))
            assert.is_false(Settings:SetOption("mailRoster", { ["Player-x"] = "Alt" }))
            assert.is_true(Settings:SetOption("mailRoster", {
                ["Player-x"] = { name = "Alt", surname = "Sur", realm = "Realm" } }))
        end)
    end)

    describe("residue", function()
        it("leaves nothing behind when disabled and works again when re-enabled", function()
            local env, module = ready()
            env:Put(1, CLOTH)
            env:Open()
            assert.is_true(module.panel:IsShown())
            local hooksAfterFirstEnable = #env.sendHooks
            env.R.Registry:Disable(module)
            assert.equal(0, env:ActiveTimers())
            assert.is_false(module.panel:IsShown())
            for _, entries in pairs(env.R.Broker.events) do
                for _, entry in ipairs(entries) do
                    assert.is_not.equal(module, entry.owner)
                end
            end
            assert.is_true(env.R.Registry:Enable(ID))
            assert.equal(hooksAfterFirstEnable, #env.sendHooks)
            assert.equal(1, #env.sendHooks)
            assert.equal(2, env.hookScriptCalls)
            env:HideSend()
            env:Open()
            assert.is_true(module.panel:IsShown())
            assert.same({ CLOTH }, suggested(module))
            env:PressSend("Bankalt")
            assert.is_table(module.sending)
        end)

        it("ignores the hooks while disabled", function()
            local env, module = ready()
            env.R.Registry:Disable(module)
            env:ShowSend()
            env:PressSend("Bankalt")
            assert.is_nil(module.sending)
            assert.is_false(module.panel:IsShown())
        end)
    end)
end)
