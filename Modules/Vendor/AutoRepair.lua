--- @module vendor.autoRepair
--- Purpose: repair once per merchant visit using only the player's money and a spending cap.
--- Requires: InCombatLockdown, MerchantFrame, CanMerchantRepair, GetRepairAllCost, GetMoney,
---     RepairAllItems
--- Events: MERCHANT_SHOW; MERCHANT_CLOSED, PLAYER_MONEY, UPDATE_INVENTORY_DURABILITY,
---     PLAYER_REGEN_DISABLED (contextual)
--- Hot: no
local _, R = ...
local AutoRepair = R:RegisterModule({
    id = "vendor.autoRepair", category = "Vendor", nameKey = "AUTO_REPAIR_NAME",
    descriptionKey = "AUTO_REPAIR_DESC", detailKey = "AUTO_REPAIR_DETAIL",
    requires = { "InCombatLockdown", "MerchantFrame", "CanMerchantRepair",
        "GetRepairAllCost", "GetMoney", "RepairAllItems" },
    risk = "safe", defaultEnabled = true,
})
-- MERCHANT_SHOW can arrive before Blizzard shows MerchantFrame (see vendor.autoSell), so the
-- window is polled for briefly instead of read once.
local WINDOW_POLL, WINDOW_WAIT = 0.05, 40

function AutoRepair:Stop()
    self.pending, self.waits = nil, 0
    R:CancelTimers(self)
    R.Broker:Unsubscribe("MERCHANT_CLOSED", self)
    R.Broker:Unsubscribe("PLAYER_MONEY", self)
    R.Broker:Unsubscribe("UPDATE_INVENTORY_DURABILITY", self)
    R.Broker:Unsubscribe("PLAYER_REGEN_DISABLED", self)
end

function AutoRepair:Confirm()
    local pending = self.pending
    if pending then
        local remaining = GetRepairAllCost()
        if remaining == 0 and GetMoney() <= pending.money - pending.cost then
            self:Stop()
            R.Broker:Emit("REFACTOR_VENDOR_REPAIRED", pending.cost)
        end
    end
end

function AutoRepair:Attempt()
    if InCombatLockdown() or R:Paused() then
        self:Stop()
        return
    end
    if not MerchantFrame:IsShown() then
        self.waits = self.waits + 1
        if self.waits <= WINDOW_WAIT then
            R:After(self, WINDOW_POLL, self.Attempt)
        else
            self:Stop()
        end
        return
    end
    if not CanMerchantRepair() then
        self:Stop()
        return
    end
    local cap = R.Settings.account.options.repairCapGold
    if cap == nil then
        cap = 100
    end
    if type(cap) ~= "number" or cap ~= cap or cap < 0 or cap > 1000000 then
        self:Stop()
        return
    end
    local cost, canRepair = GetRepairAllCost()
    local money = GetMoney()
    if not canRepair or not cost or cost <= 0 or cost > cap * 10000 or cost > money then
        self:Stop()
        return
    end
    self.pending = { cost = cost, money = money }
    R.Broker:Subscribe("PLAYER_MONEY", self.Confirm, self)
    R.Broker:Subscribe("UPDATE_INVENTORY_DURABILITY", self.Confirm, self)
    RepairAllItems(false)
    self:Confirm()
    if self.pending then
        R:After(self, 3, self.Stop)
    end
end

function AutoRepair:OnMerchantShow()
    self:Stop()
    if InCombatLockdown() or R:Paused() then
        return
    end
    R.Broker:Subscribe("MERCHANT_CLOSED", self.Stop, self)
    R.Broker:Subscribe("PLAYER_REGEN_DISABLED", self.Stop, self)
    self:Attempt()
end

function AutoRepair:OnEnable()
    R.Broker:Subscribe("MERCHANT_SHOW", self.OnMerchantShow, self, nil, 10)
end

function AutoRepair:OnDisable()
    self:Stop()
    R.Broker:UnsubscribeAll(self)
end
