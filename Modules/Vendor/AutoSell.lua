--- @module vendor.autoSell
--- Purpose: sell a bounded number of verified grey stacks, preserving buyback capacity.
--- Requires: InCombatLockdown, MerchantFrame, GetMoney, NUM_TOTAL_EQUIPPED_BAG_SLOTS,
---     C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_Container.GetContainerItemQuestInfo,
---     C_Container.GetContainerItemPurchaseInfo, C_Container.UseContainerItem, C_Item.GetItemInfo,
---     C_TooltipInfo.GetBagItem, Enum.TooltipDataLineType.TradeTimeRemaining
--- Events: MERCHANT_SHOW; MERCHANT_CLOSED, BAG_UPDATE_DELAYED, PLAYER_MONEY, PLAYER_REGEN_DISABLED (contextual)
--- Hot: no
local _, R = ...
local AutoSell = R:RegisterModule({
    id = "vendor.autoSell", category = "Vendor", nameKey = "AUTO_SELL_NAME",
    descriptionKey = "AUTO_SELL_DESC", detailKey = "AUTO_SELL_DETAIL",
    requires = { "InCombatLockdown", "MerchantFrame", "GetMoney",
        "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo",
        "C_Container.GetContainerItemQuestInfo", "C_Container.GetContainerItemPurchaseInfo",
        "C_Container.UseContainerItem", "C_Item.GetItemInfo", "C_TooltipInfo.GetBagItem",
        "Enum.TooltipDataLineType.TradeTimeRemaining" },
    tier = "standard", risk = "safe", defaultEnabled = false,
})
local MAX_SALES, SALE_DELAY, CONFIRM_TIMEOUT = 12, 0.2, 3

function AutoSell:IsSafeContext()
    return self.active and MerchantFrame:IsShown() and not InCombatLockdown() and not R:Paused()
end

function AutoSell:GetCandidate(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.quality ~= 0 or info.isLocked or info.hasNoValue or info.hasLoot or info.isReadable then
        return nil
    end
    local neverSell = R.Settings.account.options.neverSellIDs or {}
    if neverSell[info.itemID] or neverSell[tostring(info.itemID)] then
        return nil
    end
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    if not quest or quest.isQuestItem or quest.questID then
        return nil
    end
    local purchase = C_Container.GetContainerItemPurchaseInfo(bag, slot, false)
    if purchase and purchase.refundSeconds and purchase.refundSeconds > 0 then
        return nil
    end
    local tooltip = C_TooltipInfo.GetBagItem(bag, slot)
    if not tooltip or not tooltip.lines then
        return nil
    end
    for _, line in ipairs(tooltip.lines) do
        if line.type == Enum.TooltipDataLineType.TradeTimeRemaining then
            return nil
        end
    end
    local price = select(11, C_Item.GetItemInfo(info.hyperlink))
    if type(price) ~= "number" or price <= 0 then
        return nil
    end
    return info, price * info.stackCount
end

function AutoSell:Stop()
    self.active, self.pending = false, nil
    R:CancelTimers(self)
    R.Broker:Unsubscribe("MERCHANT_CLOSED", self)
    R.Broker:Unsubscribe("BAG_UPDATE_DELAYED", self)
    R.Broker:Unsubscribe("PLAYER_MONEY", self)
    R.Broker:Unsubscribe("PLAYER_REGEN_DISABLED", self)
end

function AutoSell:Next()
    if not self:IsSafeContext() or self.attempts >= MAX_SALES then
        self:Stop()
        return
    end
    -- Scan current bag contents every time. Never replay a queue of stale slots.
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info, value = self:GetCandidate(bag, slot)
            if info then
                self.attempts = self.attempts + 1
                self.pending = {
                    bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount,
                    money = GetMoney(), value = value,
                }
                C_Container.UseContainerItem(bag, slot)
                if self.pending then
                    R:After(self, CONFIRM_TIMEOUT, self.Stop)
                end
                return
            end
        end
    end
    self:Stop()
end

function AutoSell:OnUpdate()
    if not self:IsSafeContext() then
        self:Stop()
        return
    end
    local pending = self.pending
    if not pending then
        return
    end
    local info = C_Container.GetContainerItemInfo(pending.bag, pending.slot)
    local removed = not info or info.itemID ~= pending.itemID or info.stackCount < pending.count
    if removed and GetMoney() >= pending.money + pending.value then
        self.pending = nil
        R:CancelTimers(self)
        R.Broker:Emit("REFACTOR_VENDOR_SOLD", pending.count, pending.value)
        R:After(self, SALE_DELAY, self.Next)
    end
end

function AutoSell:OnMerchantShow()
    self:Stop()
    self.active, self.attempts = true, 0
    if not self:IsSafeContext() then
        self:Stop()
        return
    end
    R.Broker:Subscribe("MERCHANT_CLOSED", self.Stop, self)
    R.Broker:Subscribe("BAG_UPDATE_DELAYED", self.OnUpdate, self, 0.05)
    R.Broker:Subscribe("PLAYER_MONEY", self.OnUpdate, self)
    R.Broker:Subscribe("PLAYER_REGEN_DISABLED", self.Stop, self)
    R:After(self, SALE_DELAY, self.Next)
end

function AutoSell:OnEnable()
    R.Broker:Subscribe("MERCHANT_SHOW", self.OnMerchantShow, self)
end

function AutoSell:OnDisable()
    self:Stop()
    R.Broker:UnsubscribeAll(self)
end
