--- @module toasts.loot
--- Purpose: show what the player just looted as one anchored rolling feed of fading rows.
--- Requires: UnitGUID, GetMoney, InCombatLockdown, C_Item.GetItemQualityByID, C_Item.GetItemIconByID,
---     C_Item.GetItemQualityColor, C_CurrencyInfo.GetCurrencyInfo
--- Events: CHAT_MSG_LOOT, CURRENCY_DISPLAY_UPDATE, LOOT_OPENED; LOOT_CLOSED, PLAYER_MONEY (contextual);
---     GET_ITEM_INFO_RECEIVED, PLAYER_EQUIPMENT_CHANGED, PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED
---     (contextual, only while item rows or the upgrade prompt are on screen and Gear Refactor is loaded)
--- Hot: no, loot arrives at human speed and the animation runs in the client
local _, R = ...
local Price = R.Price
local Loot = R:RegisterModule({
    id = "toasts.loot", category = "Loot", nameKey = "TOAST_LOOT_NAME",
    descriptionKey = "TOAST_LOOT_DESC", detailKey = "TOAST_LOOT_DETAIL",
    requires = { "UnitGUID", "GetMoney", "InCombatLockdown", "C_Item.GetItemQualityByID",
        "C_Item.GetItemIconByID", "C_Item.GetItemQualityColor", "C_CurrencyInfo.GetCurrencyInfo" },
    risk = "visible", defaultEnabled = false,
})

local MONEY_GRACE = 0.5
local GEAR_EVENTS = { "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED" }
-- inv_misc_coin_01: the coin-pile icon, so the looted-gold row reads like the currency rows.
local GOLD_ICON = 133784
-- A multi-slot loot arrives as one burst of messages. Everything inside this window is one
-- group; the next click of a manual loot window lands after it and gets its own row.
local GROUP_WINDOW = 0.35
local TEXTURE_KEYS = { "lootRow", "lootRowHover", "lootIconFrame", "lootUnderline", "coinGold", "coinSilver",
    "coinCopper" }
-- Real item ids so /refactor loottest shows real icons. Names are in the locale file.
local TEST_ITEMS = { 2589, 2770, 1210, 4306, 858, 6948 }
-- inv_belt_03, for the test upgrade: it has no item behind it, only a picture.
local TEST_UPGRADE_ICON = 132492

-- The row draws money as coin textures of its own (row:SetMoney), so a line that carries an
-- amount is formatted around a marker and split there: the words stay in the locale file,
-- in whatever order a language puts them.
local MONEY_SLOT = "\001"
local function around(pattern, ...)
    local text = string.format(pattern, ...)
    local prefix, suffix = text:match("^(.-)\001(.*)$")
    return prefix or text, suffix or ""
end

local function goldEntry(key, total)
    local prefix, suffix = around(R.L.TOAST_GOLD_DETAIL, MONEY_SLOT)
    return {
        key = key, count = total, name = R.L.TOAST_GOLD, icon = GOLD_ICON, framed = false,
        detail = prefix, money = total, moneyLine = "detail", moneySuffix = suffix,
    }
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

-- The price line as the text before the coins, the amount, and the text after them. A vendor
-- price is the unmarked default; only a price from an auction addon names where it came
-- from (PRD 5.5), so a row of greys does not repeat "(vendor)" down the whole feed.
function Loot:Detail(value, source)
    if not value then
        return nil
    end
    if not source or source == "vendor" or R.Settings:GetOption("toastShowSource") == false then
        return "", value, ""
    end
    local prefix, suffix = around(R.L.TOAST_PRICE, MONEY_SLOT, R.L["TOAST_SOURCE_" .. tostring(source)] or source)
    return prefix, value, suffix
end

function Loot:Describe(entry)
    entry.name = self:Label(entry.itemName, entry.count)
    entry.detail, entry.money, entry.moneySuffix = self:Detail(entry.value, entry.source)
    entry.moneyLine = "detail"
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

-- Gear Refactor's verdict on each looted item (its PRD 5.3): with this feed on, its own
-- upgrade popup stands down. The row carries the badge and the upgrade prompt asks.
local function magnitude(badge)
    return tonumber(badge.text:match("%-?%d+")) or 0
end

-- Integrations/GearRefactor.lua, or nil while Gear Refactor is not there to ask.
local function gear()
    local integration = R.Integrations and R.Integrations.gear
    return integration and integration:Available() and integration or nil
end

-- A collapsed group would hide an upgrade inside it, so the group's row wears the best
-- upgrade it holds; every upgrade inside is offered in the prompt on its own. A row with no
-- link (gold, currency, a test row) has nothing for Gear Refactor to judge.
function Loot:Assess(entry)
    if entry.children then
        local best
        for _, child in ipairs(entry.children) do
            self:Assess(child)
            local badge = child.badge
            if badge and badge.state == "upgrade" and (not best or magnitude(badge) > magnitude(best)) then
                best = badge
            end
        end
        entry.badge = best
        return
    end
    if not entry.link then
        return
    end
    local integration = gear()
    entry.badge = integration and integration:Badge(entry.link) or nil
    self:Consider(entry)
end

-- Each upgrade is offered once: Not now, Equip, or equipping it some other way is final for
-- that drop. One that stops being an upgrade while it waits leaves the queue.
function Loot:Consider(entry)
    local upgrade = entry.badge ~= nil and entry.badge.state == "upgrade" and not entry.equipped
    if upgrade and not entry.offered then
        entry.offered = true
        entry.replacesName = gear():ReplacedName(entry.link)
        self.prompt:Offer(entry)
    elseif not upgrade then
        self.prompt:Withdraw(entry)
    end
end

function Loot:CanEquip()
    local integration = gear()
    return not self.inCombat and integration ~= nil and integration:CanEquip()
end

-- True once the item is on: the prompt moves on to the next upgrade. A test row has no item
-- behind it, so there is nothing to equip and the prompt simply closes.
function Loot:Equip(entry)
    if not entry.link then
        return true
    end
    if not self:CanEquip() then
        return false
    end
    if gear():Equip(entry.link) then
        entry.equipped = true
        return true
    end
    R:Print(R.L.TOAST_EQUIP_FAILED)
    return false
end

-- Held only while an item row or the prompt is on screen: nothing needs a verdict
-- refreshed otherwise.
function Loot:WatchGear(on)
    if on == (self.watchingGear == true) then
        return
    end
    self.watchingGear = on
    if not on then
        for _, event in ipairs(GEAR_EVENTS) do
            R.Broker:Unsubscribe(event, self)
        end
        return
    end
    self.inCombat = InCombatLockdown()
    R.Broker:Subscribe("GET_ITEM_INFO_RECEIVED", self.QueueBadges, self)
    R.Broker:Subscribe("PLAYER_EQUIPMENT_CHANGED", self.QueueBadges, self)
    R.Broker:Subscribe("PLAYER_REGEN_DISABLED", self.OnCombat, self)
    R.Broker:Subscribe("PLAYER_REGEN_ENABLED", self.OnCombat, self)
end

-- The event is the answer: PLAYER_REGEN_DISABLED fires before lockdown begins, so asking
-- InCombatLockdown inside it would still say no.
function Loot:OnCombat(event)
    self.inCombat = event == "PLAYER_REGEN_DISABLED"
    self.prompt:Refresh()
end

function Loot:SettleGear()
    if #self.host.items == 0 and #self.prompt.queue == 0 then
        self:WatchGear(false)
    end
end

-- Next frame, once per frame: Gear Refactor drops its scores on the same events, and asking
-- before it has would read the old verdict. A burst of item loads costs one refresh.
function Loot:QueueBadges()
    if not self.badgeTimer then
        self.badgeTimer = R:After(self, 0, self.RefreshBadges)
    end
end

function Loot:RefreshBadges()
    self.badgeTimer = nil
    for _, item in ipairs(self.host.items) do
        self:Assess(item.entry)
    end
    -- An upgrade still waiting may have left the feed already. Backwards, because one that
    -- is no longer an upgrade is withdrawn from the queue while it is walked.
    local queue = self.prompt.queue
    for index = #queue, 1, -1 do
        if queue[index] then self:Assess(queue[index]) end
    end
    self.host:RefreshAccessories()
    self.prompt:Refresh()
end

function Loot:Push(entry)
    self:Assess(entry)
    self.host:Push(entry)
    if gear() and (#self.host.items > 0 or #self.prompt.queue > 0) then
        self:WatchGear(true)
    end
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
    self:Describe(entry)
    self:Push(entry)
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
            self:Describe(entry)
            children[#children + 1] = entry
        end
    end
    if total > 0 then
        local label, suffix = around(R.L.TOAST_GROUP_PRICED, count, MONEY_SLOT)
        self:Push({ name = label, money = total, moneyLine = "name", moneySuffix = suffix, children = children })
    else
        self:Push({ name = string.format(R.L.TOAST_GROUP, count), children = children })
    end
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
    self.host:Push(goldEntry(self, (existing and existing.entry.count or 0) + delta))
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
-- uncommon upgrade with its prompt, gold, and a four-item group, so the feed can be judged on screen.
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
    -- The uncommon row is an upgrade as Gear Refactor would badge one, so the badge and the
    -- prompt can be judged without Gear Refactor or a real upgrade to loot.
    local upgrade = row(3, "TOAST_TEST_UPGRADE", 2, 1, 41500)
    local tint = R.Theme.colors.RING_DONE
    upgrade.icon, upgrade.offered = TEST_UPGRADE_ICON, true
    upgrade.badge = { state = "upgrade", text = R.L.TOAST_TEST_BADGE, r = tint[1], g = tint[2], b = tint[3] }
    upgrade.replacesName = R.L.TOAST_TEST_REPLACED
    self:PushItem(upgrade)
    self.prompt:Offer(upgrade)
    self.host:Push(goldEntry("refactor-test-gold", 32000))
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
    self.prompt = R.UI:CreateUpgradePrompt(self)
    self.prompt.onEquip = function(entry) return self:Equip(entry) end
    self.prompt.canEquip = function() return self:CanEquip() end
    self.prompt.onEmpty = function() self:SettleGear() end
    self.host.onEmpty = function() self:SettleGear() end
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
    self.watchingGear, self.badgeTimer, self.inCombat = nil, nil, nil
    if self.host then
        self.host:SetEditing(false)
        self.host:Clear()
        self.host.onEmpty = nil
    end
    if self.prompt then
        self.prompt:Clear()
        self.prompt.onEquip, self.prompt.canEquip, self.prompt.onEmpty = nil, nil, nil
    end
end
