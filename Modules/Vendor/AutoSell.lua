--- @module vendor.autoSell
--- Purpose: sell every verified grey stack the moment a merchant window opens.
--- Requires: InCombatLockdown, MerchantFrame, GetMoney, NUM_TOTAL_EQUIPPED_BAG_SLOTS,
---     C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_Container.GetContainerItemQuestInfo,
---     C_Container.GetContainerItemPurchaseInfo, C_Container.UseContainerItem,
---     C_TooltipInfo.GetBagItem, Enum.TooltipDataLineType.TradeTimeRemaining
--- Events: MERCHANT_SHOW; MERCHANT_CLOSED, BAG_UPDATE_DELAYED, PLAYER_REGEN_DISABLED (contextual)
--- Hot: no
local _, R = ...
local AutoSell = R:RegisterModule({
    id = "vendor.autoSell", category = "Vendor", nameKey = "AUTO_SELL_NAME",
    descriptionKey = "AUTO_SELL_DESC", detailKey = "AUTO_SELL_DETAIL",
    requires = { "InCombatLockdown", "MerchantFrame", "GetMoney",
        "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo",
        "C_Container.GetContainerItemQuestInfo", "C_Container.GetContainerItemPurchaseInfo",
        "C_Container.UseContainerItem", "C_TooltipInfo.GetBagItem",
        "Enum.TooltipDataLineType.TradeTimeRemaining" },
    risk = "safe", defaultEnabled = true,
})
-- MERCHANT_SHOW is the merchant data arriving, not the window opening: Blizzard shows
-- MerchantFrame from PLAYER_INTERACTION_MANAGER_FRAME_SHOW, a separate event with no
-- guaranteed order against this one. Poll for the window rather than reading it too early.
local WINDOW_POLL, WINDOW_WAIT = 0.05, 40
-- Every candidate is sent in one burst, then reconciled against the bags. A slot that
-- survives two bursts is a stack this merchant will not take, so it is dropped.
local MAX_PASSES, PASS_TIMEOUT, MAX_SLOT_TRIES = 6, 0.5, 2

function AutoSell:IsSessionOpen()
    return self.active and not InCombatLockdown() and not R:Paused()
end

function AutoSell:GetCandidate(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.quality ~= 0 or info.hasNoValue then
        return nil, false
    end
    -- Past this point the slot holds a grey worth money, so every rejection is a guard
    -- firing and is worth counting: that is what turns a silent visit into a reason.
    if info.isLocked or info.hasLoot or info.isReadable then
        return nil, true
    end
    local neverSell = R.Settings:GetOption("neverSellIDs")
    if neverSell and (neverSell[info.itemID] or neverSell[tostring(info.itemID)]) then
        return nil, true
    end
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    if not quest or quest.isQuestItem or quest.questID then
        return nil, true
    end
    local purchase = C_Container.GetContainerItemPurchaseInfo(bag, slot, false)
    if purchase and purchase.refundSeconds and purchase.refundSeconds > 0 then
        return nil, true
    end
    local tooltip = C_TooltipInfo.GetBagItem(bag, slot)
    if not tooltip or not tooltip.lines then
        return nil, true
    end
    for _, line in ipairs(tooltip.lines) do
        if line.type == Enum.TooltipDataLineType.TradeTimeRemaining then
            return nil, true
        end
    end
    return info
end

function AutoSell:Stop()
    self.active, self.sent, self.waits = false, nil, 0
    R:CancelTimers(self)
    R.Broker:Unsubscribe("MERCHANT_CLOSED", self)
    R.Broker:Unsubscribe("BAG_UPDATE_DELAYED", self)
    R.Broker:Unsubscribe("PLAYER_REGEN_DISABLED", self)
end

function AutoSell:Survey()
    local sellable, protected = 0, 0
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info, grey = self:GetCandidate(bag, slot)
            if info then
                sellable = sellable + 1
            elseif grey then
                protected = protected + 1
            end
        end
    end
    return sellable, protected
end

-- Silence after a visit that sold nothing reads as a broken addon, so every outcome that
-- is not "the bags are clean" says what stopped it, once.
function AutoSell:Finish(message)
    if not message then
        local sellable, protected = self:Survey()
        if sellable > 0 then
            message = R.L.AUTO_SELL_UNCONFIRMED
        elseif self.sold == 0 and protected > 0 then
            message = string.format(R.L.AUTO_SELL_PROTECTED, protected)
        end
    end
    if message then
        R:Print(message)
    end
    self:Stop()
end

function AutoSell:Gone(entry)
    local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
    return not info or info.itemID ~= entry.itemID or info.stackCount < entry.count
end

-- One burst per pass: selling a slot never moves another slot, so the whole scan can be
-- sent in a single frame and reconciled afterwards.
function AutoSell:Pass()
    if not self:IsSessionOpen() then
        self:Stop()
        return
    end
    if not MerchantFrame:IsShown() then
        self.waits = self.waits + 1
        if self.waits <= WINDOW_WAIT then
            R:After(self, WINDOW_POLL, self.Pass)
        else
            self:Finish(R.L.AUTO_SELL_NO_WINDOW)
        end
        return
    end
    self.passes = self.passes + 1
    if self.passes > MAX_PASSES then
        self:Finish()
        return
    end
    local sent, money = {}, GetMoney()
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local failed = self.failed[bag]
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if not (failed and failed[slot]) then
                local info = self:GetCandidate(bag, slot)
                if info then
                    sent[#sent + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount }
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end
    end
    if #sent == 0 then
        self:Finish()
        return
    end
    self.sent, self.money = sent, money
    self.timeout = R:After(self, PASS_TIMEOUT, self.Reconcile)
end

function AutoSell:Reconcile()
    local sent = self.sent
    if not sent then
        return
    end
    self.sent = nil
    if self.timeout then
        self.timeout:Cancel()
        self.timeout = nil
    end
    local items = 0
    for _, entry in ipairs(sent) do
        if self:Gone(entry) then
            items = items + entry.count
            self.sold = self.sold + 1
        else
            local tries = (self.tries[entry.bag] and self.tries[entry.bag][entry.slot] or 0) + 1
            local bag = self.tries[entry.bag]
            if not bag then
                bag = {}
                self.tries[entry.bag] = bag
            end
            bag[entry.slot] = tries
            if tries >= MAX_SLOT_TRIES then
                local failed = self.failed[entry.bag]
                if not failed then
                    failed = {}
                    self.failed[entry.bag] = failed
                end
                failed[entry.slot] = true
            end
        end
    end
    if items > 0 then
        -- The money delta is the price actually paid, so an item whose sell price the
        -- client has not cached yet still reports a real number.
        local value = GetMoney() - self.money
        R.Broker:Emit("REFACTOR_VENDOR_SOLD", items, value > 0 and value or 0)
    end
    self:Pass()
end

function AutoSell:OnChange()
    if not self:IsSessionOpen() then
        self:Stop()
        return
    end
    local sent = self.sent
    if not sent then
        return
    end
    for _, entry in ipairs(sent) do
        if not self:Gone(entry) then
            return
        end
    end
    -- Everything the burst sent is out of the bags: reconcile now instead of waiting out
    -- the timeout, which is what makes a full load of junk sell in one blink.
    self:Reconcile()
end

function AutoSell:OnMerchantShow()
    self:Stop()
    self.active, self.passes, self.sold, self.waits = true, 0, 0, 0
    self.failed, self.tries = {}, {}
    R.Broker:Subscribe("MERCHANT_CLOSED", self.Stop, self)
    R.Broker:Subscribe("BAG_UPDATE_DELAYED", self.OnChange, self, 0.05)
    R.Broker:Subscribe("PLAYER_REGEN_DISABLED", self.Stop, self)
    self:Pass()
end

function AutoSell:OnEnable()
    R.Broker:Subscribe("MERCHANT_SHOW", self.OnMerchantShow, self)
end

function AutoSell:OnDisable()
    self:Stop()
    R.Broker:UnsubscribeAll(self)
end
