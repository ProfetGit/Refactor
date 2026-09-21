--- @module toasts.loot
--- Purpose: show what the player just looted as one anchored rolling feed of fading rows.
--- Requires: UnitGUID, GetMoney, C_Item.GetItemQualityByID, C_Item.GetItemIconByID, C_Item.GetItemQualityColor,
---     C_CurrencyInfo.GetCurrencyInfo, C_CurrencyInfo.GetCoinTextureString
--- Events: CHAT_MSG_LOOT, CURRENCY_DISPLAY_UPDATE, LOOT_OPENED; LOOT_CLOSED, PLAYER_MONEY (contextual)
--- Hot: no, loot arrives at human speed and the animation runs in the client
local _, R = ...
local Price = R.Price
local Loot = R:RegisterModule({
    id = "toasts.loot", category = "Toasts", nameKey = "TOAST_LOOT_NAME",
    descriptionKey = "TOAST_LOOT_DESC", detailKey = "TOAST_LOOT_DETAIL",
    requires = { "UnitGUID", "GetMoney", "C_Item.GetItemQualityByID", "C_Item.GetItemIconByID",
        "C_Item.GetItemQualityColor", "C_CurrencyInfo.GetCurrencyInfo",
        "C_CurrencyInfo.GetCoinTextureString" },
    risk = "visible", defaultEnabled = false,
})

local MONEY_GRACE = 0.5
local COIN_FONT_HEIGHT = 12
-- inv_misc_coin_01: the coin-pile icon, so the looted-gold row reads like the currency rows.
local GOLD_ICON = 133784
-- A multi-slot loot arrives as one burst of messages. Everything inside this window is one
-- group; the next click of a manual loot window lands after it and gets its own row.
local GROUP_WINDOW = 0.35
local TEXTURE_KEYS = { "lootRow", "lootRowHover", "lootIconFrame", "lootUnderline" }
-- Real item ids so /refactor loottest shows real icons. Names are in the locale file.
local TEST_ITEMS = { 2589, 2770, 1210, 4306, 858, 6948 }

-- The client's own coin icons, at the size of the row's second line, rather than the
-- letters g, s and c. It also drops denominations that are zero, so a grey sells for "8c"
-- and not "0g 0s 8c". The text form stays as the answer for a client without it.
local function moneyText(amount)
    local coins = C_CurrencyInfo.GetCoinTextureString(amount, COIN_FONT_HEIGHT)
    if type(coins) == "string" and coins ~= "" then
        return coins
    end
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

function Loot:PriceOf(link, count)
    if R.Settings:GetOption("toastShowPrice") == false then
        return nil
    end
    return Price:Get(link, count)
end

function Loot:Detail(value, source)
    if not value then
        return nil
    end
    if not source or R.Settings:GetOption("toastShowSource") == false then
        return moneyText(value)
    end
    return string.format(R.L.TOAST_PRICE, moneyText(value), R.L["TOAST_SOURCE_" .. tostring(source)] or source)
end

function Loot:Label(name, count)
    if count and count > 1 then
        return string.format(R.L.TOAST_COUNT, name, count)
    end
    return name
end

-- One pending entry per item, keyed by link so a burst that drops the same item twice reads
-- as one line with a count rather than two rows.
function Loot:Collect(entry)
    local pending = self.pending
    if not pending then
        pending = {}
        self.pending = pending
        self.flush = R:After(self, GROUP_WINDOW, self.Flush)
    end
    local existing = pending.byLink and pending.byLink[entry.key]
    if existing then
        existing.count = existing.count + entry.count
        existing.value = self:PriceOf(existing.link, existing.count)
        return
    end
    pending.byLink = pending.byLink or {}
    pending.byLink[entry.key] = entry
    pending[#pending + 1] = entry
end

-- A row already on screen for this item takes the new drop as a higher count rather than a
-- second row, which is what makes "x2" appear on a repeat drop.
function Loot:PushItem(entry)
    local existing = self.host.byKey[entry.key]
    if existing then
        entry.count = entry.count + (existing.entry.count or 0)
        if entry.link then
            entry.value, entry.source = self:PriceOf(entry.link, entry.count)
        end
    end
    entry.name = self:Label(entry.itemName, entry.count)
    entry.detail = self:Detail(entry.value, entry.source)
    self.host:Push(entry)
end

function Loot:Flush()
    local pending = self.pending
    if self.flush then
        self.flush:Cancel()
    end
    self.pending, self.flush = nil, nil
    if not pending or #pending == 0 then
        return
    end
    if #pending == 1 or R.Settings:GetOption("toastAggregate") == false then
        for _, entry in ipairs(pending) do
            self:PushItem(entry)
        end
        return
    end
    local children, count, total = {}, 0, 0
    for index, entry in ipairs(pending) do
        count = count + entry.count
        total = total + (entry.value or 0)
        if index <= R.UI.lootFeedMaxGroupRows then
            entry.name = self:Label(entry.itemName, entry.count)
            entry.detail = self:Detail(entry.value, entry.source)
            children[#children + 1] = entry
        end
    end
    local label = total > 0 and string.format(R.L.TOAST_GROUP_PRICED, count, moneyText(total))
        or string.format(R.L.TOAST_GROUP, count)
    self.host:Push({ name = label, children = children })
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
    local r, g, b = C_Item.GetItemQualityColor(quality)
    local value, source = self:PriceOf(link, count)
    local entry = {
        key = link, link = link, itemName = name, count = count, value = value, source = source,
        icon = C_Item.GetItemIconByID(itemID), r = r, g = g, b = b,
    }
    -- A group is only ever collected while a loot window is what produced the message.
    if self.grouping then
        self:Collect(entry)
    else
        self:PushItem(entry)
    end
end

function Loot:OnCurrency(_, currencyType, _, quantityChange)
    if R.Settings:GetOption("toastCurrency") == false or type(quantityChange) ~= "number" or quantityChange <= 0 then
        return
    end
    local info = currencyType and C_CurrencyInfo.GetCurrencyInfo(currencyType)
    if not info then
        return
    end
    local existing = self.host.byKey[currencyType]
    local total = (existing and existing.entry.count or 0) + quantityChange
    local r, g, b = C_Item.GetItemQualityColor(info.quality or 1)
    self.host:Push({
        key = currencyType, count = total, name = info.name,
        detail = string.format(R.L.TOAST_CURRENCY_DETAIL, total),
        icon = info.iconFileID, framed = false, r = r, g = g, b = b,
    })
end

function Loot:OnMoney()
    local money = GetMoney()
    local delta = money - (self.money or money)
    self.money = money
    if delta <= 0 or R.Settings:GetOption("toastGold") == false then
        return
    end
    local existing = self.host.byKey[self]
    local total = (existing and existing.entry.count or 0) + delta
    self.host:Push({
        key = self, count = total, name = R.L.TOAST_GOLD,
        detail = string.format(R.L.TOAST_GOLD_DETAIL, moneyText(total)),
        icon = GOLD_ICON, framed = false,
    })
end

function Loot:StopMoney()
    R.Broker:Unsubscribe("PLAYER_MONEY", self)
    R.Broker:Unsubscribe("LOOT_CLOSED", self)
    self.grouping = nil
end

-- Money is watched only around a loot window, so vendor sales and mail never show a row.
function Loot:OnLootOpened()
    R:CancelTimers(self)
    self.money = GetMoney()
    self.grouping = true
    R.Broker:Subscribe("PLAYER_MONEY", self.OnMoney, self)
    R.Broker:Subscribe("LOOT_CLOSED", self.OnLootClosed, self)
end

function Loot:OnLootClosed()
    R:After(self, MONEY_GRACE, self.StopMoney)
end

-- Only the feed's own options, or a change with no key (a profile), lay the feed out again:
-- the size sliders write on every step of a drag.
function Loot:OnSettingsChanged(_, key)
    if key ~= nil and string.sub(key, 1, 5) ~= "toast" then
        return
    end
    self.host:ApplySettings()
end

-- /refactor loottest. Fake rows through the real path: one common item, a stack, an
-- uncommon item, gold, and a four-item group, so the feed can be judged on screen.
function Loot:Test()
    local missing = {}
    for _, key in ipairs(TEXTURE_KEYS) do
        if R.Theme.missingFiles[key] then
            missing[#missing + 1] = key
        end
    end
    if #missing > 0 then
        R:Print(string.format(R.L.CMD_LOOT_TEST_MISSING, table.concat(missing, ", ")))
    else
        R:Print(R.L.CMD_LOOT_TEST_TEXTURES)
    end
    local function icon(index)
        local id = TEST_ITEMS[index]
        return C_Item.GetItemIconByID(id), id
    end
    local function row(index, nameKey, quality, count, value)
        local r, g, b = C_Item.GetItemQualityColor(quality)
        return {
            key = "refactor-test-" .. index, itemName = R.L[nameKey], count = count, value = value,
            source = "vendor", icon = icon(index), r = r, g = g, b = b,
        }
    end
    self:PushItem(row(1, "TOAST_TEST_COMMON", 1, 1, 89))
    self:PushItem(row(2, "TOAST_TEST_STACK", 1, 20, 2400))
    self:PushItem(row(3, "TOAST_TEST_UNCOMMON", 2, 1, 41500))
    self.host:Push({ key = "refactor-test-gold", count = 32000, name = R.L.TOAST_GOLD,
        detail = string.format(R.L.TOAST_GOLD_DETAIL, moneyText(32000)),
        icon = GOLD_ICON, framed = false })
    self.pending = nil
    for index = 3, 6 do
        self:Collect(row(index, "TOAST_TEST_GROUP_" .. (index - 2), index - 2, 1, 1200 * index))
    end
    self:Flush()
    R:Print(R.L.CMD_LOOT_TEST_PUSHED)
end

function Loot:OnEnable()
    self.playerGUID = UnitGUID("player")
    self.host = R.UI:CreateLootFeed(self)
    self.host:ApplySettings()
    R.Broker:Subscribe("CHAT_MSG_LOOT", self.OnLoot, self)
    R.Broker:Subscribe("CURRENCY_DISPLAY_UPDATE", self.OnCurrency, self)
    R.Broker:Subscribe("LOOT_OPENED", self.OnLootOpened, self)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
    R.Broker:Subscribe("REFACTOR_LOOT_TEST", self.Test, self)
end

function Loot:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    self.pending, self.flush, self.grouping = nil, nil, nil
    if self.host then
        self.host:SetEditing(false)
        self.host:Clear()
    end
end
