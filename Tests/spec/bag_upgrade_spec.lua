local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local ID = "items.bagUpgrade"
local OFFSET = 30
local POUCH, LINEN, BACKPACK, MAGEWEAVE, HERB, BIG_HERB, RUNECLOTH = 101, 102, 103, 104, 105, 106, 107
local BAGS = {
    [POUCH] = { name = "Small Pouch", size = 6, kind = 0 },
    [LINEN] = { name = "Linen Bag", size = 10, kind = 0 },
    [BACKPACK] = { name = "Traveler's Backpack", size = 16, kind = 0 },
    [MAGEWEAVE] = { name = "Mageweave Bag", size = 14, kind = 0 },
    [HERB] = { name = "Herb Pouch", size = 12, kind = 2, family = 32 },
    [BIG_HERB] = { name = "Cenarion Herb Bag", size = 20, kind = 2, family = 32 },
    [RUNECLOTH] = { name = "Runecloth Bag", size = 16, kind = 0, boe = true },
}
local GOODS = 200
-- Stackable goods: their largest stack, and the bag family a herb carries.
local CLOTH, WOOL, PEACEBLOOM = 301, 302, 303
local STACKS = {
    [CLOTH] = { name = "Linen Cloth", max = 20 },
    [WOOL] = { name = "Wool Cloth", max = 20 },
    [PEACEBLOOM] = { name = "Peacebloom", max = 20, family = 32 },
}

local function nameOf(id)
    local known = BAGS[id] or STACKS[id]
    return known and known.name or ("Item " .. id)
end

local function link(id)
    return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. nameOf(id) .. "]|h|r"
end

local function item(id, count)
    local bag = BAGS[id]
    return { itemID = id, hyperlink = link(id), quality = 1, iconFileID = 500 + id, stackCount = count or 1,
        isLocked = false, isBound = not (bag and bag.boe) }
end

-- A layout entry is an item ID, or { id, count } for a stack.
local function place(entry)
    if type(entry) == "table" then return item(entry[1], entry[2]) end
    return item(entry)
end

local function said(env, text)
    for _, message in ipairs(env.messages) do
        if message:find(text, 1, true) then return true end
    end
    return false
end

-- A small bag server. The client shows a moved item locked where it was until the server answers,
-- which here is env:Settle(); a bag that binds when equipped waits on its confirmation dialog.
local function world(layout)
    local env = Runtime.new()
    Widgets.install(env)
    for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Toasts.enUS.lua" }) do
        env:Load(path)
    end
    env.control, env.combat = false, false
    env.IsControlKeyDown = function() return env.control end
    env.InCombatLockdown = function() return env.combat end
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    env.R.UI = env.R.UI or {}
    env:Load("UI/UpgradePrompt.lua")

    env.bags = { [0] = { size = layout.backpackSize or 16, family = 0, items = {} } }
    env.equipped = {}
    local goods = GOODS
    local function fill(bag, count)
        for slot = 1, count do
            goods = goods + 1
            env.bags[bag].items[slot] = item(goods)
        end
    end
    fill(0, layout.backpackFill or 0)
    for slot, entry in pairs(layout.backpack or {}) do env.bags[0].items[slot] = place(entry) end
    for bag = 1, 4 do
        local spec = layout.equipped and layout.equipped[bag]
        if spec then
            local info = BAGS[spec.id]
            env.equipped[bag] = item(spec.id)
            env.bags[bag] = { size = info.size, family = info.family or 0, items = {} }
            fill(bag, spec.fill or 0)
            for slot, entry in pairs(spec.items or {}) do env.bags[bag].items[slot] = place(entry) end
        else
            env.bags[bag] = { size = 0, family = 0, items = {} }
        end
    end

    local function slotItem(bag, slot) return env.bags[bag] and env.bags[bag].items[slot] end
    local function numSlots(bag) return (bag == 0 or env.equipped[bag]) and env.bags[bag].size or 0 end
    env.pending, env.reserved, env.tooltipReads = {}, {}, 0
    env.NUM_BAG_SLOTS = 4
    env.CONTAINER_SLOTS = "%d Slot %s"
    env.Enum = { ItemClass = { Container = 1 }, ItemBind = { OnEquip = 2 } }
    env.GetInventoryItemID = function(unit, slot)
        assert.equal("player", unit)
        local bag = env.equipped[slot - OFFSET]
        return bag and bag.itemID
    end
    for _, name in ipairs({ "MerchantFrame", "BankFrame", "MailFrame", "TradeFrame" }) do
        env.CreateFrame("Frame", name)
    end
    env.StaticPopup_FindVisible = function(which) return env.popup == which and {} or nil end
    env.CursorHasItem = function() return env.cursor ~= nil end
    env.GetCursorInfo = function()
        if env.cursor then return "item", env.cursor.item.itemID end
    end
    env.ClearCursor = function()
        if env.cursor then
            env.cursor.item.isLocked = false
            env.cursor = nil
        end
    end
    env.hooks = {}
    env.ContainerFrameItemButton_OnClick = function() end
    env.hooksecurefunc = function(name, fn)
        assert.is_function(env[name])
        env.hooks[name] = fn
    end
    env.C_Container = {
        GetContainerNumSlots = numSlots,
        GetContainerNumFreeSlots = function(bag)
            local free = 0
            for slot = 1, numSlots(bag) do
                if not slotItem(bag, slot) then free = free + 1 end
            end
            return free, env.bags[bag].family
        end,
        GetContainerItemInfo = slotItem,
        ContainerIDToInventoryID = function(bag) return bag + OFFSET end,
        PickupContainerItem = function(bag, slot)
            local here, held = slotItem(bag, slot), env.cursor
            if not held then
                if here and not here.isLocked then
                    here.isLocked = true
                    env.cursor = { item = here, bag = bag, slot = slot }
                end
                return
            end
            env.cursor = nil
            if held.bag == bag and held.slot == slot then
                held.item.isLocked = false
                return
            end
            if here then
                -- Only ever a stack onto a stack of the same item, the two fitting in one slot.
                local fitsStack = here.itemID == held.item.itemID and not here.isLocked
                    and here.stackCount + held.item.stackCount <= env.C_Item.GetItemMaxStackSizeByID(here.itemID)
                assert.is_true(fitsStack, "an item was dropped on an occupied slot")
                here.isLocked = true
                env.pending[#env.pending + 1] = { kind = "merge", item = held.item, fromBag = held.bag,
                    fromSlot = held.slot, into = here }
                return
            end
            local key = bag * 100 + slot
            assert.is_nil(env.reserved[key], "two items were sent to one slot")
            env.reserved[key] = true
            env.pending[#env.pending + 1] = { kind = "move", item = held.item, fromBag = held.bag,
                fromSlot = held.slot, toBag = bag, toSlot = slot }
        end,
    }
    env.PutItemInBag = function(inventory)
        local held = env.cursor
        if not held then return end
        env.cursor = nil
        local target = inventory - OFFSET
        if next(env.bags[target].items) then
            held.item.isLocked = false
            return
        end
        local op = { kind = "equip", item = held.item, bag = held.bag, slot = held.slot, target = target }
        if BAGS[held.item.itemID].boe and not held.item.isBound then
            env.bindOp, env.popup = op, "EQUIP_BIND"
            return
        end
        env.pending[#env.pending + 1] = op
    end
    env.C_Item = {
        GetItemInfoInstant = function(id)
            local bag = BAGS[id]
            return id, nil, nil, nil, nil, bag and 1 or 7, bag and bag.kind or 0
        end,
        GetItemInfo = function(key)
            local id = type(key) == "number" and key or tonumber(tostring(key):match("item:(%d+)"))
            local bag = BAGS[id]
            return nameOf(id), link(id), 1, 1, 1, "", "", 1, "", 500 + id, 10, bag and 1 or 7,
                bag and bag.kind or 0, bag and bag.boe and 2 or 1
        end,
        GetItemQualityColor = function() return 1, 1, 1 end,
        GetItemMaxStackSizeByID = function(id) return STACKS[id] and STACKS[id].max or 1 end,
        GetItemFamily = function(id) return STACKS[id] and STACKS[id].family or 0 end,
    }
    env.C_TooltipInfo = {
        GetBagItem = function(bag, slot)
            env.tooltipReads = env.tooltipReads + 1
            local here = slotItem(bag, slot)
            local info = here and BAGS[here.itemID]
            local lines = { { leftText = here and nameOf(here.itemID) or "" } }
            if info then lines[2] = { leftText = info.size .. " Slot Bag" } end
            return { lines = lines }
        end,
    }

    function env:Settle()
        local ops = self.pending
        self.pending, self.reserved = {}, {}
        for _, op in ipairs(ops) do
            if op.kind == "merge" then
                op.into.stackCount = op.into.stackCount + op.item.stackCount
                self.bags[op.fromBag].items[op.fromSlot] = nil
                op.into.isLocked, op.item.isLocked = false, false
            elseif op.kind == "move" then
                if not self.refuseMoves then
                    self.bags[op.fromBag].items[op.fromSlot] = nil
                    self.bags[op.toBag].items[op.toSlot] = op.item
                end
                op.item.isLocked = false
            else
                local old = self.equipped[op.target]
                self.bags[op.bag].items[op.slot] = old
                if old then old.isLocked = false end
                local info = BAGS[op.item.itemID]
                self.equipped[op.target] = op.item
                self.bags[op.target] = { size = info.size, family = info.family or 0, items = {} }
                op.item.isLocked, op.item.isBound = false, true
            end
        end
        self:Fire("ITEM_LOCK_CHANGED")
        self:Fire("BAG_UPDATE_DELAYED")
        self:Advance(0.2)
    end
    function env:Run()
        for _ = 1, 12 do
            if #self.pending == 0 and not self.module.run then return end
            self:Settle()
        end
        error("the swap never finished")
    end
    function env:AcceptBind()
        self.pending[#self.pending + 1], self.bindOp, self.popup = self.bindOp, nil, nil
        self:Run()
    end
    function env:CancelBind()
        self.bindOp.item.isLocked = false
        self.bindOp, self.popup = nil, nil
        self:Fire("ITEM_LOCK_CHANGED")
        self:Advance(0.2)
    end
    -- Blizzard's click first: a bag goes into an empty bag slot by itself. Then the post-hook.
    function env:RightClick(bag, slot)
        local here = slotItem(bag, slot)
        if here and BAGS[here.itemID] and not here.isLocked then
            for target = 1, 4 do
                if not self.equipped[target] then
                    here.isLocked = true
                    self.pending[#self.pending + 1] = { kind = "equip", item = here, bag = bag, slot = slot,
                        target = target }
                    break
                end
            end
        end
        local button = { GetBagID = function() return bag end, GetID = function() return slot end }
        local hook = self.hooks.ContainerFrameItemButton_OnClick
        if hook then hook(button, "RightButton") end
        self:Advance(0)
    end

    env:Load("Modules/Items/BagUpgrade.lua")
    local module = env.R.moduleByID[ID]
    assert.is_true(env.R.Registry:Enable(ID), tostring(module.failure) .. " "
        .. table.concat(module.missing or {}, ","))
    env.module = module
    env:Advance(0)
    return env, module
end

-- Backpack slots 1 to 10 hold goods and slot 11 a 16-slot backpack; the 6-slot pouch is the smallest bag.
local function standard(extra)
    local layout = {
        backpack = { [11] = BACKPACK }, backpackFill = 10,
        equipped = {
            { id = POUCH, fill = 3 }, { id = LINEN, fill = 10 }, { id = MAGEWEAVE, fill = 2 }, { id = LINEN },
        },
    }
    for key, value in pairs(extra or {}) do layout[key] = value end
    return world(layout)
end

local function noResidue(env, module)
    env.R.Registry:Disable(module)
    assert.equal(0, env:ActiveTimers())
    for _, entries in pairs(env.R.Broker.events) do
        for _, entry in ipairs(entries) do
            assert.is_not.equal(module, entry.owner)
        end
    end
    assert.is_true(env.R.Registry:Enable(module))
    env.R.Registry:Disable(module)
end

describe("bag upgrade", function()
    it("swaps a bigger bag in for the smallest one and carries the contents over", function()
        local env, module = standard()
        local carried = { env.bags[1].items[1], env.bags[1].items[2], env.bags[1].items[3] }
        env:RightClick(0, 11)
        assert.is_table(module.run)
        env:Run()
        assert.equal(BACKPACK, env.equipped[1].itemID)
        assert.equal(16, env.C_Container.GetContainerNumSlots(1))
        for index, goods in ipairs(carried) do
            assert.equal(goods, env.bags[1].items[index])
        end
        assert.equal(POUCH, env.bags[0].items[11].itemID)
        assert.is_nil(env.cursor)
        assert.is_true(said(env, "Swapped " .. link(POUCH) .. " for " .. link(BACKPACK) .. ": 10 more bag slots."))
        assert.is_nil(module.run)
        assert.equal(0, #module.prompt.queue)
        assert.is_false(module.prompt:IsShown())
        assert.equal(0, env:ActiveTimers())
    end)

    it("leaves the moved items in the other bags when carrying is off", function()
        local env, module = standard()
        env.R.Settings:SetOption("bagUpgradeCarry", false)
        env:RightClick(0, 11)
        env:Run()
        assert.equal(BACKPACK, env.equipped[1].itemID)
        assert.is_nil(next(env.bags[1].items))
        assert.equal(GOODS + 11, env.bags[0].items[12].itemID)
        assert.is_nil(module.run)
    end)

    it("moves the new bag out first when it sits in the bag it replaces", function()
        local env = world({
            backpackFill = 10,
            equipped = { { id = POUCH, fill = 2 }, { id = LINEN, fill = 10 }, { id = LINEN, fill = 10 },
                { id = LINEN, fill = 10 } },
        })
        env.bags[1].items[3] = item(BACKPACK)
        env:RightClick(1, 3)
        env:Run()
        assert.equal(BACKPACK, env.equipped[1].itemID)
        assert.equal(POUCH, env.bags[0].items[13].itemID)
        assert.equal(GOODS + 11, env.bags[1].items[1].itemID)
        assert.equal(GOODS + 12, env.bags[1].items[2].itemID)
    end)

    it("replaces the smallest bag of the same kind, the emptier one on a tie, never a profession bag", function()
        local _, module = world({
            backpack = { [1] = BACKPACK, [2] = BIG_HERB, [3] = LINEN },
            equipped = { { id = HERB }, { id = LINEN, fill = 5 }, { id = LINEN, fill = 1 }, { id = MAGEWEAVE } },
        })
        local plain = module:Plan(0, 1)
        assert.equal(3, plain.target)
        assert.equal(10, plain.targetSlots)
        assert.equal(1, module:Plan(0, 2).target)
        assert.is_nil(module:Plan(0, 3))
        assert.is_nil(module:Plan(0, 4))
    end)

    it("leaves an empty bag slot to the client on right-click and fills it from the prompt", function()
        local env, module = world({ backpack = { [1] = BACKPACK }, equipped = { { id = POUCH, fill = 3 } } })
        local prompt = module.prompt
        assert.is_true(prompt:IsShown())
        assert.equal("16 slots, into an empty bag slot", prompt.badge:GetText())
        assert.equal("", prompt.replaces:GetText())
        env:RightClick(0, 1)
        assert.is_nil(module.run)
        env:Settle()
        assert.equal(BACKPACK, env.equipped[2].itemID)

        env, module = world({ backpack = { [1] = BACKPACK }, equipped = { { id = POUCH, fill = 3 } } })
        module.prompt.equip:GetScript("OnClick")(module.prompt.equip)
        env:Run()
        assert.equal(BACKPACK, env.equipped[2].itemID)
        assert.equal(POUCH, env.equipped[1].itemID)
        assert.is_true(said(env, "Equipped " .. link(BACKPACK) .. " in an empty bag slot."))
    end)

    it("moves nothing when the other bags have no room", function()
        local env, module = world({
            backpack = { [4] = BACKPACK }, backpackSize = 4, backpackFill = 3,
            equipped = { { id = POUCH, fill = 6 }, { id = LINEN, fill = 10 }, { id = LINEN, fill = 9 },
                { id = LINEN, fill = 10 } },
        })
        env:RightClick(0, 4)
        assert.is_nil(module.run)
        assert.equal(0, #env.pending)
        assert.is_nil(env.cursor)
        assert.is_true(said(env, "Cannot swap in " .. link(BACKPACK) .. ": everything in Small Pouch needs "
            .. "somewhere to go while the bags change. Free 5 more bag slots first."))
    end)

    it("combines partial stacks when the bags are short, only as many as it needs", function()
        local env, module = world({
            backpackSize = 4,
            backpack = { [1] = { CLOTH, 5 }, [2] = { CLOTH, 7 }, [3] = { WOOL, 3 }, [4] = BACKPACK },
            equipped = { { id = POUCH, items = { [1] = { WOOL, 4 }, [3] = { CLOTH, 2 } } },
                { id = LINEN, fill = 10 }, { id = LINEN, fill = 10 }, { id = LINEN, fill = 10 } },
        })
        env:RightClick(0, 4)
        assert.equal("merge", module.run.phase)
        env:Run()
        assert.equal(BACKPACK, env.equipped[1].itemID)
        assert.equal(POUCH, env.bags[0].items[4].itemID)
        local counts, stacks = {}, 0
        for bag = 0, 1 do
            for _, held in pairs(env.bags[bag].items) do
                counts[held.itemID] = (counts[held.itemID] or 0) + held.stackCount
                if STACKS[held.itemID] then stacks = stacks + 1 end
            end
        end
        assert.equal(14, counts[CLOTH])
        assert.equal(7, counts[WOOL])
        -- Two merges closed a gap of two; the third possible one was left alone.
        assert.equal(3, stacks)
        assert.is_true(said(env, "Swapped"))
    end)

    it("counts a herb bag's room for herbs", function()
        local env = world({
            backpackSize = 2, backpack = { [1] = BACKPACK },
            equipped = { { id = POUCH, items = { [1] = { PEACEBLOOM, 6 }, [2] = { PEACEBLOOM, 20 }, [3] = 250 } },
                { id = HERB, fill = 10 }, { id = LINEN, fill = 10 }, { id = LINEN, fill = 10 } },
        })
        env.R.Settings:SetOption("bagUpgradeCarry", false)
        env:RightClick(0, 1)
        env:Run()
        assert.equal(BACKPACK, env.equipped[1].itemID)
        assert.equal(PEACEBLOOM, env.bags[2].items[11].itemID)
        assert.equal(PEACEBLOOM, env.bags[2].items[12].itemID)
        assert.equal(250, env.bags[0].items[2].itemID)
    end)

    it("says how many slots are still missing after combining what it can", function()
        local env, module = world({
            backpackSize = 3, backpack = { [1] = { CLOTH, 5 }, [2] = { CLOTH, 7 }, [3] = BACKPACK },
            equipped = { { id = POUCH, fill = 4 }, { id = LINEN, fill = 10 }, { id = LINEN, fill = 10 },
                { id = LINEN, fill = 10 } },
        })
        env:RightClick(0, 3)
        assert.is_nil(module.run)
        assert.equal(0, #env.pending)
        assert.is_true(said(env, "Free 3 more bag slots first."))

        env, module = world({
            backpackSize = 2, backpack = { [1] = BACKPACK, [2] = 260 },
            equipped = { { id = POUCH, fill = 1 }, { id = LINEN, fill = 10 }, { id = LINEN, fill = 10 },
                { id = LINEN, fill = 10 } },
        })
        env:RightClick(0, 1)
        assert.is_nil(module.run)
        assert.is_true(said(env, "Free one more bag slot first."))
    end)

    it("stands down at a merchant, in combat, with the pause modifier and with right-click off", function()
        local env, module = standard()
        env.MerchantFrame:Show()
        env:RightClick(0, 11)
        assert.is_nil(module.run)
        env.MerchantFrame:Hide()
        env.combat = true
        env:RightClick(0, 11)
        assert.is_nil(module.run)
        env.combat, env.control = false, true
        env:RightClick(0, 11)
        assert.is_nil(module.run)
        env.control = false
        env.R.Settings:SetOption("bagUpgradeRightClick", false)
        env:RightClick(0, 11)
        assert.is_nil(module.run)
        env.R.Settings:SetOption("bagUpgradeRightClick", true)
        env:RightClick(0, 11)
        assert.is_table(module.run)
    end)

    it("offers each bigger bag biggest first and does not ask again after Not now", function()
        local env, module = world({
            backpack = { [1] = MAGEWEAVE, [2] = BACKPACK },
            equipped = { { id = POUCH, fill = 2 }, { id = LINEN, fill = 10 }, { id = LINEN, fill = 10 },
                { id = LINEN, fill = 10 } },
        })
        local prompt = module.prompt
        assert.is_true(prompt:IsShown())
        assert.equal("Bigger bag (1 more)", prompt.title:GetText())
        assert.equal("Traveler's Backpack", prompt.name:GetText())
        assert.equal("+10 slots", prompt.badge:GetText())
        assert.equal("replaces Small Pouch (6)", prompt.replaces:GetText())
        assert.is_true(prompt.equip:IsEnabled())
        prompt.skip:GetScript("OnClick")(prompt.skip)
        assert.equal("Bigger bag", prompt.title:GetText())
        assert.equal("Mageweave Bag", prompt.name:GetText())
        assert.equal("+8 slots", prompt.badge:GetText())
        env:Fire("BAG_UPDATE_DELAYED")
        env:Advance(0.2)
        assert.equal(1, #prompt.queue)
        assert.equal(link(MAGEWEAVE), prompt.queue[1].link)
        prompt.equip:GetScript("OnClick")(prompt.equip)
        assert.is_false(prompt.equip:IsEnabled() and prompt:IsShown())
        env:Run()
        assert.equal(MAGEWEAVE, env.equipped[1].itemID)
        assert.equal(0, #prompt.queue)
        assert.is_false(prompt:IsShown())
    end)

    it("greys Equip in combat and offers nothing with the prompt off", function()
        local env, module = standard()
        local prompt = module.prompt
        assert.is_true(prompt.equip:IsEnabled())
        env.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        assert.is_false(prompt.equip:IsEnabled())
        env.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(prompt.equip:IsEnabled())
        env.R.Settings:SetOption("bagUpgradePrompt", false)
        assert.equal(0, #prompt.queue)
        assert.is_false(prompt:IsShown())
        assert.is_nil(env.R.Broker.events.BAG_UPDATE_DELAYED)
    end)

    it("leaves the bind confirmation to the client and keeps waiting while it is open", function()
        local env, module = world({
            backpack = { [1] = RUNECLOTH },
            equipped = { { id = POUCH, fill = 2 }, { id = LINEN, fill = 10 }, { id = LINEN, fill = 10 },
                { id = LINEN, fill = 10 } },
        })
        assert.equal("+10 slots, binds", module.prompt.badge:GetText())
        env:RightClick(0, 1)
        env:Settle()
        assert.equal("EQUIP_BIND", env.popup)
        env:Advance(30)
        assert.is_table(module.run)
        assert.is_false(said(env, "did not answer"))
        env:CancelBind()
        assert.is_nil(module.run)
        assert.is_true(said(env, "Bag swap cancelled"))
        assert.equal(POUCH, env.equipped[1].itemID)
        assert.equal(GOODS + 1, env.bags[0].items[2].itemID)

        env:RightClick(0, 1)
        assert.equal("EQUIP_BIND", env.popup)
        env:AcceptBind()
        assert.equal(RUNECLOTH, env.equipped[1].itemID)
        assert.is_true(env.equipped[1].isBound)
        assert.is_nil(module.run)
    end)

    it("stops on a refused move instead of trying again", function()
        local env, module = standard()
        env.refuseMoves = true
        env:RightClick(0, 11)
        env:Settle()
        assert.is_nil(module.run)
        assert.is_true(said(env, "the game refused a move"))
        assert.equal(3, 6 - env.C_Container.GetContainerNumFreeSlots(1))
        assert.is_nil(env.cursor)
        assert.equal(0, #env.pending)
    end)

    it("ends a step the client never answers", function()
        local env, module = standard()
        env:RightClick(0, 11)
        env.pending = {}
        env:Advance(6)
        assert.is_nil(module.run)
        assert.is_true(said(env, "the game did not answer"))
    end)

    it("pauses for combat and carries on after", function()
        local env, module = standard()
        env:RightClick(0, 11)
        env.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(said(env, "paused for combat"))
        env:Settle()
        env:Advance(30)
        assert.is_table(module.run)
        assert.equal(POUCH, env.equipped[1].itemID)
        env.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        env:Run()
        assert.equal(BACKPACK, env.equipped[1].itemID)
        assert.equal(3, 16 - env.C_Container.GetContainerNumFreeSlots(1))
    end)

    it("reads a bag's size from its tooltip once", function()
        local env = standard()
        local reads = env.tooltipReads
        assert.equal(1, reads)
        env:Fire("BAG_UPDATE_DELAYED")
        env:Advance(0.2)
        env:Fire("BAG_UPDATE_DELAYED")
        env:Advance(0.2)
        assert.equal(reads, env.tooltipReads)
    end)

    it("leaves no residue and ignores clicks while off", function()
        local env, module = standard()
        noResidue(env, module)
        assert.is_false(module.prompt:IsShown())
        env:RightClick(0, 11)
        assert.is_nil(module.run)
        assert.equal(0, env:ActiveTimers())
    end)

    it("waits for another owner's prompt to close before showing", function()
        local env, module = world({ equipped = { { id = POUCH, fill = 2 } } })
        local other = env.R.UI:CreateUpgradePrompt({})
        other:Offer({ link = "gear", itemName = "Blue Thing", icon = 1 })
        assert.is_true(other:IsShown())
        env.bags[0].items[5] = item(BACKPACK)
        env:Fire("BAG_UPDATE_DELAYED")
        env:Advance(0.2)
        assert.equal(1, #module.prompt.queue)
        assert.is_false(module.prompt:IsShown())
        other.skip:GetScript("OnClick")(other.skip)
        assert.is_false(other:IsShown())
        assert.is_true(module.prompt:IsShown())
        assert.equal("Bigger bag", module.prompt.title:GetText())
    end)
end)
