--- @module items.bagUpgrade
--- Purpose: put a bigger bag in place of the smallest equipped bag of its kind with the old bag's items carried
---     over, on a right-click in the default bags or from a prompt when one lands in the bags.
--- Requires: InCombatLockdown, hooksecurefunc, ContainerFrameItemButton_OnClick, GetInventoryItemID,
---     MerchantFrame, BankFrame, MailFrame, TradeFrame, StaticPopup_FindVisible, CursorHasItem, ClearCursor,
---     GetCursorInfo, PutItemInBag, CONTAINER_SLOTS, NUM_BAG_SLOTS, Enum.ItemClass.Container, Enum.ItemBind.OnEquip,
---     C_Container.GetContainerNumSlots, C_Container.GetContainerNumFreeSlots, C_Container.GetContainerItemInfo,
---     C_Container.PickupContainerItem, C_Container.ContainerIDToInventoryID, C_Item.GetItemInfoInstant,
---     C_Item.GetItemInfo, C_Item.GetItemQualityColor, C_Item.GetItemFamily, C_Item.GetItemMaxStackSizeByID,
---     C_TooltipInfo.GetBagItem
--- Events: BAG_UPDATE_DELAYED (while the prompt option is on or a swap runs), REFACTOR_SETTINGS_CHANGED;
---     ITEM_LOCK_CHANGED, PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED (contextual, while a swap runs or the
---     prompt holds an offer)
--- Hot: no
local _, R = ...
local BagUpgrade = R:RegisterModule({
    id = "items.bagUpgrade", category = "Items", nameKey = "BAG_UPGRADE_NAME",
    descriptionKey = "BAG_UPGRADE_DESC", detailKey = "BAG_UPGRADE_DETAIL",
    requires = { "InCombatLockdown", "hooksecurefunc", "ContainerFrameItemButton_OnClick", "GetInventoryItemID",
        "MerchantFrame", "BankFrame", "MailFrame", "TradeFrame", "StaticPopup_FindVisible", "CursorHasItem",
        "ClearCursor", "GetCursorInfo", "PutItemInBag", "CONTAINER_SLOTS", "NUM_BAG_SLOTS",
        "Enum.ItemClass.Container", "Enum.ItemBind.OnEquip", "C_Container.GetContainerNumSlots",
        "C_Container.GetContainerNumFreeSlots", "C_Container.GetContainerItemInfo",
        "C_Container.PickupContainerItem", "C_Container.ContainerIDToInventoryID", "C_Item.GetItemInfoInstant",
        "C_Item.GetItemInfo", "C_Item.GetItemQualityColor", "C_Item.GetItemFamily",
        "C_Item.GetItemMaxStackSizeByID", "C_TooltipInfo.GetBagItem" },
    risk = "visible", defaultEnabled = true,
})

-- The backpack is never replaced and the reagent bag slot only takes reagent bags, so only the
-- four ordinary bag slots are ever targets. The backpack still takes moved items.
local FIRST_BAG = 1
-- A step the client never answers ends the run instead of leaving it waiting for good.
local STEP_TIMEOUT = 5
local THROTTLE = 0.1
local OPTIONS = { bagUpgradeRightClick = true, bagUpgradePrompt = true, bagUpgradeCarry = true }

-- A bag's size never changes for its item ID, so this cache is permanent by design. The client
-- has no API for the size of a bag that is not equipped; it comes from the tooltip line.
local slotsByItem = {}
local slotPattern

-- CONTAINER_SLOTS is the client's "%d Slot %s"; the pattern follows whatever it says.
local function buildPattern(format)
    local escaped = format:gsub("[%(%)%.%[%]%*%+%-%?%^%$]", "%%%0")
    escaped = escaped:gsub("%%d", "(%%d+)"):gsub("%%s", ".+")
    return "^" .. escaped .. "$"
end

local function bagKind(itemID)
    if not itemID then
        return nil
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID == Enum.ItemClass.Container then
        return subclassID
    end
end

local function holds(bag, slot, itemID)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info and info.itemID == itemID then
        return info
    end
end

-- The new bag itself may be one of the items moved out, and is in flight until the server answers.
local function present(run)
    return holds(run.bag, run.slot, run.itemID) or run.fromBag and holds(run.fromBag, run.fromSlot, run.itemID)
end

local function ordinary(bag)
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    return family == 0
end

-- Bag families are bit flags and Lua 5.1 has no bitwise operators, so a shared bit is found by arithmetic.
local function fits(itemFamily, bagFamily)
    local bit = 1
    while bit <= bagFamily do
        if bagFamily % (bit * 2) >= bit and itemFamily % (bit * 2) >= bit then
            return true
        end
        bit = bit * 2
    end
    return false
end

-- A profession bag takes its own trade's goods, and never a bag.
local function accepts(bag, itemID)
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    if family == 0 then
        return true
    end
    return not bagKind(itemID) and fits(C_Item.GetItemFamily(itemID) or 0, family)
end

local function cursorItem()
    local kind, itemID = GetCursorInfo()
    return kind == "item" and itemID or nil
end

local function binding()
    return StaticPopup_FindVisible("EQUIP_BIND") or StaticPopup_FindVisible("EQUIP_BIND_REFUNDABLE")
        or StaticPopup_FindVisible("EQUIP_BIND_TRADEABLE")
end

local function nameOf(itemID)
    local name, link = C_Item.GetItemInfo(itemID)
    return name or R.L.BAG_UPGRADE_OLD_BAG, link or name or R.L.BAG_UPGRADE_OLD_BAG
end

function BagUpgrade:SlotsOf(bag, slot, itemID)
    local known = slotsByItem[itemID]
    if known then
        return known
    end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    if not data or not data.lines then
        return nil
    end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        local count = type(text) == "string" and text:match(slotPattern)
        if count then
            slotsByItem[itemID] = tonumber(count)
            return slotsByItem[itemID]
        end
    end
end

-- The equipped bag this one should replace: an empty bag slot first, then the smallest bag of
-- the same subclass, so a herb bag only ever replaces a herb bag; on a tie, the one with fewer
-- items to move.
function BagUpgrade:Plan(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local kind = info and bagKind(info.itemID)
    if not kind then
        return nil
    end
    local slots = self:SlotsOf(bag, slot, info.itemID)
    if not slots then
        return nil
    end
    local plan = { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, info = info, slots = slots }
    for candidate = FIRST_BAG, NUM_BAG_SLOTS do
        local equipped = GetInventoryItemID("player", C_Container.ContainerIDToInventoryID(candidate))
        if not equipped then
            plan.target, plan.targetSlots, plan.used, plan.empty = candidate, 0, 0, true
            return plan
        end
        if bagKind(equipped) == kind then
            local size = C_Container.GetContainerNumSlots(candidate)
            local used = size - (C_Container.GetContainerNumFreeSlots(candidate))
            if size < slots and (not plan.target or size < plan.targetSlots
                or size == plan.targetSlots and used < plan.used) then
                plan.target, plan.targetSlots, plan.used, plan.targetItemID = candidate, size, used, equipped
            end
        end
    end
    return plan.target and plan or nil
end

-- Reserved slots are the ones this burst already sent an item to: the client still shows them
-- empty until the server answers.
function BagUpgrade:FreeIn(bag, reserved)
    local taken = reserved[bag]
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
        if not (taken and taken[slot]) and not C_Container.GetContainerItemInfo(bag, slot) then
            if not taken then
                taken = {}
                reserved[bag] = taken
            end
            taken[slot] = true
            return bag, slot
        end
    end
end

-- A bag named alone takes back what came out of it, whatever its kind. Otherwise a profession
-- bag that takes the item comes first, which keeps ordinary room for everything else.
function BagUpgrade:NextFree(only, except, reserved, itemID)
    if only then
        return self:FreeIn(only, reserved)
    end
    for pass = 1, 2 do
        for bag = 0, NUM_BAG_SLOTS do
            if bag ~= except then
                local plain = ordinary(bag)
                if pass == 2 and plain or pass == 1 and not plain and itemID and accepts(bag, itemID) then
                    local found, slot = self:FreeIn(bag, reserved)
                    if found then
                        return found, slot
                    end
                end
            end
        end
    end
end

-- How many of the outgoing bag's items would find no slot, placed exactly as Empty places them.
-- No order of the other bags beats this: a swap needs as many free slots in all as the outgoing
-- bag has, so only combining stacks or a profession bag's room can close the gap.
function BagUpgrade:Shortfall(target)
    local reserved, short = {}, 0
    for slot = 1, C_Container.GetContainerNumSlots(target) do
        local info = C_Container.GetContainerItemInfo(target, slot)
        if info and not self:NextFree(nil, target, reserved, info.itemID) then
            short = short + 1
        end
    end
    return short
end

-- Partial stacks of one item that fit in one slot, smallest into largest, at most `wanted` of
-- them. Only ordinary bags and the outgoing one, so every slot a merge frees takes anything. A
-- burst gives each stack one part, since the client locks a stack until the server answers.
function BagUpgrade:Merges(target, wanted, attempted, burst)
    local groups, merges = {}, {}
    for bag = 0, NUM_BAG_SLOTS do
        if bag == target or ordinary(bag) then
            local tried = attempted[bag]
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local max = info and not info.isLocked and not (tried and tried[slot])
                    and C_Item.GetItemMaxStackSizeByID(info.itemID) or 1
                if max > 1 and info.stackCount < max then
                    local group = groups[info.itemID]
                    if not group then
                        group = {}
                        groups[info.itemID] = group
                    end
                    group[#group + 1] = { bag = bag, slot = slot, count = info.stackCount, max = max,
                        link = info.hyperlink, bound = info.isBound }
                end
            end
        end
    end
    for _, stacks in pairs(groups) do
        table.sort(stacks, function(a, b) return a.count < b.count end)
        local low, high = 1, #stacks
        while low < high and #merges < wanted do
            local from, to = stacks[low], stacks[high]
            if from.count + to.count <= to.max and from.link == to.link and from.bound == to.bound then
                merges[#merges + 1] = { from = from, to = to }
                to.count = to.count + from.count
                low = low + 1
                if burst then
                    high = high - 1
                end
            else
                high = high - 1
            end
        end
    end
    return merges
end

function BagUpgrade:NoRoom(run, short)
    local L = R.L
    return string.format(short == 1 and L.BAG_UPGRADE_NO_ROOM_ONE or L.BAG_UPGRADE_NO_ROOM, run.link,
        (nameOf(run.targetItemID)), short)
end

local function anyLocked()
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.isLocked then
                return true
            end
        end
    end
    return false
end

-- The client swaps whatever is in the slot clicked second; only an empty slot is ever clicked,
-- so anything left on the cursor is a refused move and goes straight back.
function BagUpgrade:Move(fromBag, fromSlot, toBag, toSlot)
    if CursorHasItem() then
        return false
    end
    C_Container.PickupContainerItem(fromBag, fromSlot)
    if not CursorHasItem() then
        return false
    end
    C_Container.PickupContainerItem(toBag, toSlot)
    if CursorHasItem() then
        ClearCursor()
        return false
    end
    return true
end

function BagUpgrade:Start(plan)
    if self.run or InCombatLockdown() then
        return false
    end
    if CursorHasItem() then
        R:Print(R.L.BAG_UPGRADE_CURSOR)
        return false
    end
    plan.phase = plan.empty and "equip" or "empty"
    if not plan.empty then
        local short = self:Shortfall(plan.target)
        if short > 0 then
            local merges = #self:Merges(plan.target, short, {}, false)
            if merges < short then
                R:Print(self:NoRoom(plan, short - merges))
                return false
            end
            plan.phase = "merge"
        end
    end
    plan.moved, plan.pending, plan.attempted = {}, {}, {}
    self.run = plan
    self:Hold()
    self:Step()
    return true
end

-- Every step reads the bags again before it acts, so a run can stop anywhere and carry on from
-- what it finds.
function BagUpgrade:Step()
    local run = self.run
    if not run then
        return
    end
    if InCombatLockdown() then
        self:Arm(false)
        return
    end
    if run.phase == "merge" then
        return self:Merge(run)
    elseif run.phase == "empty" then
        return self:Empty(run)
    elseif run.phase == "equip" then
        return self:Equip(run)
    end
    return self:Carry(run)
end

-- Only as many stacks are combined as the swap is short of, so the bags change no more than they
-- must. A stack the client would not combine is never tried again.
function BagUpgrade:Merge(run)
    if not present(run) then
        return self:Stop(R.L.BAG_UPGRADE_GONE)
    end
    if anyLocked() then
        return self:Arm(true)
    end
    local short = self:Shortfall(run.target)
    if short == 0 then
        run.phase = "empty"
        return self:Empty(run)
    end
    local merges = self:Merges(run.target, short, run.attempted, true)
    if #merges == 0 then
        return self:Stop(self:NoRoom(run, short))
    end
    for _, merge in ipairs(merges) do
        local from, to = merge.from, merge.to
        local tried = run.attempted[from.bag]
        if not tried then
            tried = {}
            run.attempted[from.bag] = tried
        end
        tried[from.slot] = true
        if not self:Move(from.bag, from.slot, to.bag, to.slot) then
            return self:Stop(R.L.BAG_UPGRADE_FAILED)
        end
    end
    return self:Arm(true)
end

-- The whole bag goes in one burst: each item to its own empty slot, reconciled when the bags settle.
function BagUpgrade:Empty(run)
    if not present(run) then
        return self:Stop(R.L.BAG_UPGRADE_GONE)
    end
    local target, waiting, reserved = run.target, false, {}
    for slot = 1, C_Container.GetContainerNumSlots(target) do
        local info = C_Container.GetContainerItemInfo(target, slot)
        if info and info.isLocked then
            waiting = true
        elseif info then
            -- Back and unlocked after it was sent: the client refused the move.
            if run.pending[slot] == info.itemID then
                return self:Stop(R.L.BAG_UPGRADE_FAILED)
            end
            local bag, free = self:NextFree(nil, target, reserved, info.itemID)
            if not bag then
                return self:Stop(self:NoRoom(run, 1))
            end
            if not self:Move(target, slot, bag, free) then
                return self:Stop(R.L.BAG_UPGRADE_FAILED)
            end
            run.pending[slot] = info.itemID
            if slot == run.slot and target == run.bag then
                run.fromBag, run.fromSlot, run.bag, run.slot = target, slot, bag, free
            else
                run.moved[#run.moved + 1] = { bag = bag, slot = free, itemID = info.itemID }
            end
            waiting = true
        end
    end
    if waiting then
        return self:Arm(true)
    end
    run.phase = "equip"
    return self:Equip(run)
end

function BagUpgrade:Equip(run)
    local inventory = C_Container.ContainerIDToInventoryID(run.target)
    if GetInventoryItemID("player", inventory) == run.itemID then
        run.phase = "carry"
        return self:Carry(run)
    end
    -- Binding is the one part of a swap that cannot be undone, so it stays the client's question.
    if binding() then
        run.bound = true
        return self:Arm(true)
    end
    local info = holds(run.bag, run.slot, run.itemID)
    if run.sent then
        if info and not info.isLocked then
            return self:Stop(run.bound and R.L.BAG_UPGRADE_CANCELLED or R.L.BAG_UPGRADE_FAILED)
        end
        return self:Arm(true)
    end
    if not info then
        return self:Stop(R.L.BAG_UPGRADE_GONE)
    end
    if info.isLocked then
        return self:Arm(true)
    end
    -- Something went into the bag after it was emptied: empty it again.
    local size = C_Container.GetContainerNumSlots(run.target)
    if size > 0 and (C_Container.GetContainerNumFreeSlots(run.target)) < size then
        run.phase = "empty"
        return self:Empty(run)
    end
    if CursorHasItem() then
        return self:Stop(R.L.BAG_UPGRADE_FAILED)
    end
    C_Container.PickupContainerItem(run.bag, run.slot)
    PutItemInBag(inventory)
    run.sent = true
    -- Should the client hand the old bag back on the cursor rather than swap, it goes into the
    -- slot the new one just left. The new bag still on the cursor is an equip waiting on its
    -- bind confirmation, and stays.
    local held = cursorItem()
    if held and held == run.targetItemID then
        C_Container.PickupContainerItem(run.bag, run.slot)
        held = cursorItem()
    end
    if held and held ~= run.itemID then
        ClearCursor()
        return self:Stop(R.L.BAG_UPGRADE_FAILED)
    end
    return self:Arm(true)
end

-- Best effort: whatever cannot be carried back stays in the bag it was moved to.
function BagUpgrade:Carry(run)
    if #run.moved == 0 or not R.Settings:GetOption("bagUpgradeCarry") then
        return self:Finish(run)
    end
    for _, entry in ipairs(run.moved) do
        local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
        if info and info.isLocked then
            return self:Arm(true)
        end
    end
    if run.carried then
        return self:Finish(run)
    end
    run.carried = true
    local reserved, sent = {}, 0
    for _, entry in ipairs(run.moved) do
        if holds(entry.bag, entry.slot, entry.itemID) then
            local bag, free = self:NextFree(run.target, nil, reserved)
            if not bag or not self:Move(entry.bag, entry.slot, bag, free) then
                break
            end
            sent = sent + 1
        end
    end
    if sent == 0 then
        return self:Finish(run)
    end
    return self:Arm(true)
end

function BagUpgrade:Finish(run)
    if run.empty then
        R:Print(string.format(R.L.BAG_UPGRADE_DONE_EMPTY, run.link))
    else
        local _, oldLink = nameOf(run.targetItemID)
        R:Print(string.format(R.L.BAG_UPGRADE_DONE, oldLink, run.link, run.slots - run.targetSlots))
    end
    self:Stop()
end

function BagUpgrade:Stop(message)
    if message then
        R:Print(message)
    end
    local run = self.run
    if run and cursorItem() == run.itemID then
        ClearCursor()
    end
    self.run = nil
    self:Arm(false)
    self:Hold()
    self:Scan()
end

function BagUpgrade:Arm(on)
    if self.timeout then
        self.timeout:Cancel()
        self.timeout = nil
    end
    if on then
        self.timeout = R:After(self, STEP_TIMEOUT, self.TimedOut)
    end
end

-- A bind confirmation waits on the player for as long as it is open.
function BagUpgrade:TimedOut()
    self.timeout = nil
    if not self.run then
        return
    end
    if binding() then
        self:Arm(true)
        return
    end
    self:Stop(R.L.BAG_UPGRADE_STUCK)
end

function BagUpgrade:Locate(link)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink == link and not info.isLocked then
                return bag, slot
            end
        end
    end
end

function BagUpgrade:Entry(plan)
    local info = plan.info
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(plan.link)
    local binds = not info.isBound and bindType == Enum.ItemBind.OnEquip
    local r, g, b = C_Item.GetItemQualityColor(info.quality or 1)
    local L = R.L
    local text
    if plan.empty then
        text = string.format(binds and L.BAG_UPGRADE_FILLS_BINDS or L.BAG_UPGRADE_FILLS, plan.slots)
    else
        text = string.format(binds and L.BAG_UPGRADE_GAIN_BINDS or L.BAG_UPGRADE_GAIN, plan.slots - plan.targetSlots)
    end
    return {
        link = plan.link, icon = info.iconFileID, itemName = name or plan.link, r = r, g = g, b = b,
        badge = { text = text, token = binds and "TEXT_WARNING" or "TEXT_ACTIVE" },
        replacesName = not plan.empty
            and string.format(L.BAG_UPGRADE_BAG, (nameOf(plan.targetItemID)), plan.targetSlots) or nil,
    }
end

-- Offers every upgrade in the bags, biggest first, and takes back the ones that stopped being one.
function BagUpgrade:Scan()
    local prompt = self.prompt
    if self.run or not prompt or InCombatLockdown() then
        return
    end
    local plans, seen = {}, {}
    if R.Settings:GetOption("bagUpgradePrompt") then
        for bag = 0, NUM_BAG_SLOTS do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local link = info and info.hyperlink
                if link and not seen[link] and not self.declined[link] and bagKind(info.itemID) then
                    local plan = self:Plan(bag, slot)
                    if plan then
                        seen[link] = true
                        plans[#plans + 1] = plan
                    end
                end
            end
        end
    end
    for link, entry in pairs(self.offers) do
        if not seen[link] then
            self.offers[link] = nil
            prompt:Withdraw(entry)
        end
    end
    table.sort(plans, function(a, b) return a.slots > b.slots end)
    for _, plan in ipairs(plans) do
        local entry = self:Entry(plan)
        self.offers[plan.link] = entry
        prompt:Offer(entry)
    end
    self:Hold()
end

function BagUpgrade:OnEquip(entry)
    local bag, slot = self:Locate(entry.link)
    local plan = bag and self:Plan(bag, slot)
    if not plan then
        self:Scan()
        return false
    end
    if self:Start(plan) then
        self.offers[entry.link] = nil
        return true
    end
    return false
end

function BagUpgrade:OnSkip(entry)
    self.declined[entry.link] = true
    self.offers[entry.link] = nil
    self:Hold()
end

function BagUpgrade:CanEquip()
    return not self.run and not InCombatLockdown()
end

-- Blizzard's own click has already run: with a merchant, bank, mailbox or trade open it sold,
-- stored or handed over the bag, and with an empty bag slot the client equips it by itself.
function BagUpgrade:OnBagClick(button, mouseButton)
    if mouseButton ~= "RightButton" or not R.Settings:GetOption("bagUpgradeRightClick") then
        return
    end
    if self.run or InCombatLockdown() or R:Paused() or CursorHasItem() then
        return
    end
    if MerchantFrame:IsShown() or BankFrame:IsShown() or MailFrame:IsShown() or TradeFrame:IsShown() then
        return
    end
    -- Bag addons that call Blizzard's click with buttons of their own may not carry the mixin.
    if type(button) ~= "table" or type(button.GetBagID) ~= "function" or type(button.GetID) ~= "function" then
        return
    end
    local bag, slot = button:GetBagID(), button:GetID()
    local plan = bag and slot and self:Plan(bag, slot)
    if plan and not plan.empty then
        self.clicked = plan
        R:After(self, 0, self.AfterClick)
    end
end

-- One frame later, so whatever the client did with the click has shown in the bags.
function BagUpgrade:AfterClick()
    local clicked = self.clicked
    self.clicked = nil
    local info = clicked and holds(clicked.bag, clicked.slot, clicked.itemID)
    if not info or info.isLocked or self.run then
        return
    end
    local plan = self:Plan(clicked.bag, clicked.slot)
    if plan and not plan.empty then
        self:Start(plan)
    end
end

function BagUpgrade:OnBags()
    if self.run then
        self:Step()
    else
        self:Scan()
    end
end

function BagUpgrade:OnCombat(event)
    local run = self.run
    if event == "PLAYER_REGEN_DISABLED" then
        if run and not run.paused then
            run.paused = true
            R:Print(R.L.BAG_UPGRADE_PAUSED)
        end
        self:Arm(false)
    elseif run then
        run.paused = nil
        self:Step()
    else
        self:Scan()
    end
    if self.prompt then
        self.prompt:Refresh()
    end
end

function BagUpgrade:OnSettings(_, key)
    if OPTIONS[key] then
        self:Hold()
        self:Scan()
    end
end

-- Lock changes and combat matter only while a swap runs or an offer waits on Equip.
function BagUpgrade:Hold()
    local Broker = R.Broker
    local busy = self.run ~= nil
    local offering = self.prompt ~= nil and #self.prompt.queue > 0
    if busy then
        Broker:Subscribe("ITEM_LOCK_CHANGED", self.OnBags, self, THROTTLE)
    else
        Broker:Unsubscribe("ITEM_LOCK_CHANGED", self)
    end
    if busy or offering then
        Broker:Subscribe("PLAYER_REGEN_DISABLED", self.OnCombat, self)
        Broker:Subscribe("PLAYER_REGEN_ENABLED", self.OnCombat, self)
    else
        Broker:Unsubscribe("PLAYER_REGEN_DISABLED", self)
        Broker:Unsubscribe("PLAYER_REGEN_ENABLED", self)
    end
    if busy or R.Settings:GetOption("bagUpgradePrompt") then
        Broker:Subscribe("BAG_UPDATE_DELAYED", self.OnBags, self, THROTTLE)
    else
        Broker:Unsubscribe("BAG_UPDATE_DELAYED", self)
    end
end

-- A post-hook cannot be removed, so it is installed once and does nothing while the module is off.
local hooked
local function onBagClick(button, mouseButton)
    if BagUpgrade.listening then
        R:SafeCall(BagUpgrade, BagUpgrade.OnBagClick, "bag click", button, mouseButton)
    end
end

function BagUpgrade:OnEnable()
    slotPattern = slotPattern or buildPattern(CONTAINER_SLOTS)
    self.offers, self.declined = {}, {}
    local prompt = R.UI:CreateUpgradePrompt(self)
    prompt.titleKey, prompt.titleMoreKey = "BAG_UPGRADE_TITLE", "BAG_UPGRADE_TITLE_MORE"
    prompt.onEquip = function(entry) return self:OnEquip(entry) end
    prompt.onSkip = function(entry) self:OnSkip(entry) end
    prompt.canEquip = function() return self:CanEquip() end
    prompt.onEmpty = function() self:Hold() end
    self.prompt = prompt
    if not hooked then
        hooked = true
        hooksecurefunc("ContainerFrameItemButton_OnClick", onBagClick)
    end
    self.listening = true
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettings, self)
    self:Hold()
    R:After(self, 0, self.Scan)
end

function BagUpgrade:OnDisable()
    self.listening = false
    self.run, self.clicked, self.timeout = nil, nil, nil
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    local prompt = self.prompt
    if prompt then
        prompt:Clear()
        prompt.onEquip, prompt.onSkip, prompt.canEquip, prompt.onEmpty = nil, nil, nil, nil
    end
    self.offers, self.declined = nil, nil
end
