--- @module vendor.summary
--- Purpose: report confirmed Refactor vendor operations in one local chat message.
--- Requires: C_CurrencyInfo.GetCoinTextureString
--- Events: MERCHANT_SHOW, MERCHANT_CLOSED, REFACTOR_VENDOR_SOLD, REFACTOR_VENDOR_REPAIRED
--- Hot: no
local _, R = ...
local Summary = R:RegisterModule({
    id = "vendor.summary", category = "Vendor", nameKey = "VENDOR_SUMMARY_NAME",
    descriptionKey = "VENDOR_SUMMARY_DESC", detailKey = "VENDOR_SUMMARY_DETAIL",
    requires = { "C_CurrencyInfo.GetCoinTextureString" },
    risk = "safe", defaultEnabled = true,
})

-- The client's own coins, as every money line in chat shows them, and no zero denominations.
local function moneyText(amount)
    local coins = C_CurrencyInfo.GetCoinTextureString(amount)
    if type(coins) == "string" and coins ~= "" then
        return coins
    end
    return string.format(R.L.MONEY_TEXT, math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

function Summary:OnOpen()
    self.count, self.sold, self.repaired = 0, 0, 0
    self.active = true
end

function Summary:OnSold(_, count, value)
    if self.active then
        self.count = self.count + count
        self.sold = self.sold + value
    end
end

function Summary:OnRepaired(_, value)
    if self.active then
        self.repaired = self.repaired + value
    end
end

function Summary:OnClose()
    -- Only what happened: a visit that sold nothing does not report a repair beside "0 items".
    if self.active and self.count > 0 and self.repaired > 0 then
        R:Print(string.format(R.L.VENDOR_SUMMARY, self.count, moneyText(self.sold), moneyText(self.repaired)))
    elseif self.active and self.count > 0 then
        R:Print(string.format(R.L.VENDOR_SUMMARY_SOLD, self.count, moneyText(self.sold)))
    elseif self.active and self.repaired > 0 then
        R:Print(string.format(R.L.VENDOR_SUMMARY_REPAIRED, moneyText(self.repaired)))
    end
    self.active = false
end

function Summary:OnEnable()
    R.Broker:Subscribe("MERCHANT_SHOW", self.OnOpen, self, nil, 100)
    R.Broker:Subscribe("MERCHANT_CLOSED", self.OnClose, self, nil, -100)
    R.Broker:Subscribe("REFACTOR_VENDOR_SOLD", self.OnSold, self)
    R.Broker:Subscribe("REFACTOR_VENDOR_REPAIRED", self.OnRepaired, self)
end

function Summary:OnDisable()
    self.active = false
    R.Broker:UnsubscribeAll(self)
end
