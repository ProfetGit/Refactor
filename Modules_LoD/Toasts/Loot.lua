--- @module toasts.loot
--- Purpose: show a fading toast for each item, currency and gold amount the player loots.
--- Requires: UnitGUID, GetMoney, C_Item.GetItemQualityByID, C_Item.GetItemIconByID, C_Item.GetItemQualityColor,
---     C_CurrencyInfo.GetCurrencyInfo
--- Events: CHAT_MSG_LOOT, CURRENCY_DISPLAY_UPDATE, LOOT_OPENED; LOOT_CLOSED, PLAYER_MONEY (contextual)
--- Hot: no, loot arrives at human speed and the animation runs in the client
local _, R = ...
local Price = R.Price
local Loot = R:RegisterModule({
    id = "toasts.loot", category = "Toasts", nameKey = "TOAST_LOOT_NAME",
    descriptionKey = "TOAST_LOOT_DESC", detailKey = "TOAST_LOOT_DETAIL",
    requires = { "UnitGUID", "GetMoney", "C_Item.GetItemQualityByID", "C_Item.GetItemIconByID",
        "C_Item.GetItemQualityColor", "C_CurrencyInfo.GetCurrencyInfo" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

local MONEY_GRACE = 0.5

local function moneyText(amount)
    return string.format(R.L.MONEY_TEXT, math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

-- Locale independent: the link and the trailing "x3" are the same in every language.
-- Global loot strings are not in Blizzard's interface source, so they are never matched.
function Loot:Parse(text)
    if type(text) ~= "string" then
        return nil
    end
    local link = text:match("(|c[^|]*|Hitem:[^|]+|h%[[^%]]*%]|h|r)")
    if not link then
        return nil
    end
    local count = tonumber(text:match("|h|rx(%d+)", 1) or "") or 1
    local itemID = tonumber(link:match("|Hitem:(%d+)"))
    local name = link:match("%[(.-)%]")
    return link, itemID, name, count
end

function Loot:Detail(link, count)
    if R.Settings:GetOption("toastShowPrice") == false then
        return nil
    end
    local value, source = Price:Get(link, count)
    if not value then
        return nil
    end
    return string.format(R.L.TOAST_PRICE, moneyText(value), R.L["TOAST_SOURCE_" .. tostring(source)] or source)
end

function Loot:OnLoot(_, text, _, _, _, _, _, _, _, _, _, _, guid)
    if guid ~= self.playerGUID then
        return
    end
    local ok, link, itemID, name, count = pcall(self.Parse, self, text)
    if not ok or not link then
        return
    end
    local quality = C_Item.GetItemQualityByID(itemID) or 0
    if quality < (R.Settings:GetOption("toastMinQuality") or 0) then
        return
    end
    local toast, existing = self.host:Acquire(link)
    if not toast then
        return
    end
    toast.count = existing and (toast.count or 1) + count or count
    toast:SetIcon(C_Item.GetItemIconByID(itemID))
    toast:SetQualityColor(C_Item.GetItemQualityColor(quality))
    local label = toast.count > 1 and string.format(R.L.TOAST_COUNT, name, toast.count) or name
    toast:SetLines(label, self:Detail(link, toast.count))
    toast:Present()
end

function Loot:OnCurrency(_, currencyType, _, quantityChange)
    if R.Settings:GetOption("toastCurrency") == false or type(quantityChange) ~= "number" or quantityChange <= 0 then
        return
    end
    local info = currencyType and C_CurrencyInfo.GetCurrencyInfo(currencyType)
    if not info then
        return
    end
    local toast, existing = self.host:Acquire(currencyType)
    if not toast then
        return
    end
    toast.count = existing and (toast.count or 0) + quantityChange or quantityChange
    toast:SetIcon(info.iconFileID)
    toast:SetQualityColor(C_Item.GetItemQualityColor(info.quality or 1))
    toast:SetLines(info.name, string.format(R.L.TOAST_CURRENCY_DETAIL, toast.count))
    toast:Present()
end

function Loot:OnMoney()
    local money = GetMoney()
    local delta = money - (self.money or money)
    self.money = money
    if delta <= 0 or R.Settings:GetOption("toastGold") == false then
        return
    end
    local toast, existing = self.host:Acquire(self)
    if not toast then
        return
    end
    toast.count = existing and (toast.count or 0) + delta or delta
    toast:SetIcon(R.Theme.assets.toastGold.file)
    toast:SetQualityColor(1, 1, 1)
    toast:SetLines(R.L.TOAST_GOLD, string.format(R.L.TOAST_GOLD_DETAIL, moneyText(toast.count)))
    toast:Present()
end

function Loot:StopMoney()
    R.Broker:Unsubscribe("PLAYER_MONEY", self)
    R.Broker:Unsubscribe("LOOT_CLOSED", self)
end

-- Money is watched only around a loot window, so vendor sales and mail never toast.
function Loot:OnLootOpened()
    R:CancelTimers(self)
    self.money = GetMoney()
    R.Broker:Subscribe("PLAYER_MONEY", self.OnMoney, self)
    R.Broker:Subscribe("LOOT_CLOSED", self.OnLootClosed, self)
end

function Loot:OnLootClosed()
    R:After(self, MONEY_GRACE, self.StopMoney)
end

function Loot:OnEnable()
    self.playerGUID = UnitGUID("player")
    self.host = R.UI:CreateToastHost(self)
    R.Broker:Subscribe("CHAT_MSG_LOOT", self.OnLoot, self)
    R.Broker:Subscribe("CURRENCY_DISPLAY_UPDATE", self.OnCurrency, self)
    R.Broker:Subscribe("LOOT_OPENED", self.OnLootOpened, self)
end

function Loot:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    if self.host then
        self.host:Clear()
    end
end
