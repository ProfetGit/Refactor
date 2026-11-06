--- @module items.sendToAlts
--- Purpose: at the mailbox, list the bag items that belong with the player's other characters and attach them
---     on a click, a whole mail at a time if asked. The player always presses Send.
--- Requires: hooksecurefunc, UnitGUID, UnitName, GetRealmName, GetMoney, MailFrame, SendMailFrame,
---     SendMailNameEditBox, SendMailMoney, SendMail, ClickSendMailItemButton, HasSendMailItem, GetSendMailItem,
---     GetSendMailItemLink, GetSendMailPrice, ATTACHMENTS_MAX_SEND, MoneyInputFrame_SetCopper, CursorHasItem,
---     ClearCursor, IsShiftKeyDown, GameTooltip, MenuUtil.CreateContextMenu, NUM_TOTAL_EQUIPPED_BAG_SLOTS,
---     C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_Container.GetContainerItemQuestInfo,
---     C_Container.PickupContainerItem, C_Item.GetItemInfoInstant, C_Item.GetItemInfo, C_Item.GetItemQualityColor,
---     GetProfessions, GetProfessionInfo, C_TradeSkillUI.GetProfessionSkillLineID, Enum.Profession.Alchemy,
---     Enum.Profession.Blacksmithing, Enum.Profession.Engineering, Enum.Profession.Tailoring,
---     Enum.Profession.Leatherworking, Enum.Profession.Enchanting, Enum.Profession.Jewelcrafting,
---     Enum.Profession.Inscription, Enum.Profession.Cooking, Enum.ItemClass.Tradegoods, Enum.ItemClass.Gem,
---     Enum.ItemClass.Reagent, Enum.ItemClass.Recipe, Enum.ItemClass.Armor, Enum.ItemClass.Weapon,
---     Enum.ItemQuality.Uncommon, Enum.ItemBind.OnEquip
--- Events: MAIL_SHOW; MAIL_CLOSED, BAG_UPDATE_DELAYED, ITEM_LOCK_CHANGED, MAIL_SEND_INFO_UPDATE, MAIL_SEND_SUCCESS,
---     MAIL_FAILED, REFACTOR_SETTINGS_CHANGED (contextual, while the mailbox is open); a hooked SendMail and the
---     send tab's OnShow and OnHide
--- Hot: no
local _, R = ...
local SendToAlts = R:RegisterModule({
    id = "items.sendToAlts", category = "Items", nameKey = "MAIL_ALTS_NAME",
    descriptionKey = "MAIL_ALTS_DESC", detailKey = "MAIL_ALTS_DETAIL",
    requires = { "hooksecurefunc", "UnitGUID", "UnitName", "GetRealmName", "GetMoney", "MailFrame",
        "SendMailFrame", "SendMailNameEditBox", "SendMailMoney", "SendMail", "ClickSendMailItemButton",
        "HasSendMailItem", "GetSendMailItem", "GetSendMailItemLink", "GetSendMailPrice", "ATTACHMENTS_MAX_SEND",
        "MoneyInputFrame_SetCopper", "CursorHasItem", "ClearCursor", "IsShiftKeyDown", "GameTooltip",
        "MenuUtil.CreateContextMenu", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "C_Container.GetContainerNumSlots",
        "C_Container.GetContainerItemInfo", "C_Container.GetContainerItemQuestInfo",
        "C_Container.PickupContainerItem", "C_Item.GetItemInfoInstant", "C_Item.GetItemInfo",
        "C_Item.GetItemQualityColor", "GetProfessions", "GetProfessionInfo",
        "C_TradeSkillUI.GetProfessionSkillLineID", "Enum.Profession.Alchemy", "Enum.Profession.Blacksmithing",
        "Enum.Profession.Engineering", "Enum.Profession.Tailoring", "Enum.Profession.Leatherworking",
        "Enum.Profession.Enchanting", "Enum.Profession.Jewelcrafting", "Enum.Profession.Inscription",
        "Enum.Profession.Cooking", "Enum.ItemClass.Tradegoods", "Enum.ItemClass.Gem", "Enum.ItemClass.Reagent",
        "Enum.ItemClass.Recipe", "Enum.ItemClass.Armor", "Enum.ItemClass.Weapon", "Enum.ItemQuality.Uncommon",
        "Enum.ItemBind.OnEquip" },
    risk = "visible", defaultEnabled = true,
})

local REFRESH_DELAY = 0.1
local COPPER_PER_GOLD = 10000
-- The order the panel lists categories in, and the keys routes are stored under.
local KINDS = { "herb", "ore", "cloth", "leather", "enchanting", "gems", "cooking", "elemental", "inscription",
    "reagents", "recipes", "gear" }
local KIND_ORDER = {}
for index, kind in ipairs(KINDS) do KIND_ORDER[kind] = index end
-- Tradegoods subclass numbers from the item data. The client has no enum for them, so the
-- in-game checklist confirms each one with C_Item.GetItemSubClassInfo (PRD 7.6.2).
local TRADEGOODS = { [4] = "gems", [5] = "cloth", [6] = "leather", [7] = "ore", [8] = "cooking", [9] = "herb",
    [10] = "elemental", [12] = "enchanting", [16] = "inscription" }
-- What each crafting profession works with. Gathering professions keep nothing: what they
-- gather is what gets mailed.
local CRAFTS = {
    Alchemy = { "herb" }, Blacksmithing = { "ore" }, Engineering = { "ore" }, Tailoring = { "cloth" },
    Leatherworking = { "leather" }, Enchanting = { "enchanting" }, Jewelcrafting = { "gems", "ore" },
    Inscription = { "inscription", "herb" }, Cooking = { "cooking" },
}

-- What kind of thing an item ID is never changes, so this cache is permanent on purpose. False
-- marks an item that belongs to no category; an item the client has not loaded yet is not cached.
local kinds = {}

local function classify(itemID)
    local known = kinds[itemID]
    if known ~= nil then return known or nil end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return nil end
    local kind
    if classID == Enum.ItemClass.Tradegoods then
        kind = TRADEGOODS[subclassID] or "reagents"
    elseif classID == Enum.ItemClass.Gem then
        kind = "gems"
    elseif classID == Enum.ItemClass.Reagent then
        kind = "reagents"
    elseif classID == Enum.ItemClass.Recipe then
        kind = "recipes"
    else
        local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType, _, _, crafting = C_Item.GetItemInfo(itemID)
        if not name then return nil end
        if classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon then
            kind = bindType == Enum.ItemBind.OnEquip and "gear" or false
        else
            kind = crafting and "reagents" or false
        end
    end
    kinds[itemID] = kind
    return kind or nil
end

-- Lowercase and without a realm, so "Bankalt", "bankalt" and "Bankalt-Realm" are one recipient.
local function normal(name)
    if type(name) ~= "string" then return nil end
    return (name:lower():gsub("%-.*$", ""))
end

local function option(key)
    return R.Settings:GetOption(key)
end

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function attachedCount()
    local count = 0
    for index = 1, ATTACHMENTS_MAX_SEND do
        if HasSendMailItem(index) then count = count + 1 end
    end
    return count
end

function SendToAlts:Kinds()
    return KINDS
end

function SendToAlts:IsActive()
    return self.state == "enabled" and self.session == true
end

-- Forever's To field takes the whole name, surname and all, or the mail goes nowhere.
local function fullName(entry)
    if entry.surname then return entry.name .. " " .. entry.surname end
    return entry.name
end

-- Each character is remembered the first time it logs in with the module on, so the panel can
-- offer it as a recipient from any other character afterwards.
function SendToAlts:Remember()
    local guid = UnitGUID("player")
    local name, surname = UnitName("player")
    if type(guid) ~= "string" or type(name) ~= "string" or name == "" then return end
    if surname == "" then surname = nil end
    local realm = GetRealmName() or ""
    local roster = option("mailRoster") or {}
    local known = roster[guid]
    if known and known.name == name and known.surname == surname and known.realm == realm then return end
    local updated = copy(roster)
    updated[guid] = { name = name, surname = surname, realm = realm }
    R.Settings:SetOption("mailRoster", updated)
end

-- Names saved before surnames were written out read as the first name alone. A name that is
-- exactly one character's first name becomes that character's whole name.
function SendToAlts:CompleteNames()
    local roster = option("mailRoster") or {}
    local function complete(name)
        if type(name) ~= "string" then return name end
        for _, entry in pairs(roster) do
            if entry.surname and normal(entry.name) == normal(name) then return fullName(entry) end
        end
        return name
    end
    local bankAlt = option("mailBankAlt")
    if bankAlt and bankAlt ~= "" and complete(bankAlt) ~= bankAlt then
        R.Settings:SetOption("mailBankAlt", complete(bankAlt))
    end
    for _, key in ipairs({ "mailRoutes", "mailItemRoutes", "mailLearning" }) do
        local values, changed = copy(option(key)), false
        for id, name in pairs(values) do
            local whole = complete(name)
            if whole ~= name then values[id], changed = whole, true end
        end
        if changed then R.Settings:SetOption(key, values) end
    end
end

local function rosterMatches(entry, key)
    if normal(entry.name) == key then return true end
    return entry.surname ~= nil and normal(entry.name .. " " .. entry.surname) == key
end

function SendToAlts:IsMe(recipient)
    local key = normal(recipient)
    if not key then return false end
    local name, surname = UnitName("player")
    if normal(name) == key then return true end
    return type(surname) == "string" and surname ~= "" and normal(name .. " " .. surname) == key
end

-- Only the player's own characters teach a route. A friend mailed twice is still a friend.
function SendToAlts:IsOwn(recipient)
    local key = normal(recipient)
    if not key then return false end
    for _, entry in pairs(option("mailRoster") or {}) do
        if rosterMatches(entry, key) then return true end
    end
    return false
end

-- The characters on this realm the player could mail, without the one logged in, by name.
function SendToAlts:Characters()
    local realm, list, seen = GetRealmName() or "", {}, {}
    for _, entry in pairs(option("mailRoster") or {}) do
        local key = normal(entry.name)
        if entry.realm == realm and not seen[key] and not self:IsMe(entry.name) then
            seen[key] = true
            list[#list + 1] = fullName(entry)
        end
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

-- Every name a choice can be routed to: the characters, plus anyone a route already names.
function SendToAlts:Recipients()
    local list, seen = {}, {}
    local function add(name)
        local key = normal(name)
        if key and key ~= "" and not seen[key] and not self:IsMe(name) then
            seen[key] = true
            list[#list + 1] = name
        end
    end
    add(option("mailBankAlt"))
    for _, name in ipairs(self:Characters()) do add(name) end
    for _, name in pairs(option("mailRoutes") or {}) do
        if name then add(name) end
    end
    for _, name in pairs(option("mailItemRoutes") or {}) do add(name) end
    return list
end

-- Categories a crafting profession of this character works with, read once per mailbox visit.
function SendToAlts:ReadCrafts()
    local crafts = {}
    local skillLines = {}
    for profession, used in pairs(CRAFTS) do
        local id = Enum.Profession[profession]
        local skillLine = id and C_TradeSkillUI.GetProfessionSkillLineID(id)
        if skillLine then skillLines[skillLine] = used end
    end
    local first, second, _, _, cooking = GetProfessions()
    for _, index in ipairs({ first or false, second or false, cooking or false }) do
        if index then
            local _, _, _, _, _, _, skillLine = GetProfessionInfo(index)
            for _, kind in ipairs(skillLines[skillLine] or {}) do crafts[kind] = true end
        end
    end
    self.crafts = crafts
end

-- Where the rules send an item, ignoring this character's crafts and the item's quality: what
-- learning compares against.
function SendToAlts:RuleRecipient(itemID)
    local item = (option("mailItemRoutes") or {})[itemID]
    if item then return item, "item" end
    local kind = classify(itemID)
    if not kind then return nil end
    local route = (option("mailRoutes") or {})[kind]
    if route == false then return nil end
    local recipient = route or option("mailBankAlt")
    if not recipient or recipient == "" then return nil end
    return recipient, kind
end

-- Where this stack goes, or nil when it stays. The first rule that answers wins (PRD 7.6.2).
function SendToAlts:RouteFor(info)
    local itemID = info.itemID
    if info.isBound or info.hasLoot or (option("mailNeverIDs") or {})[itemID] then return nil end
    local recipient, reason = self:RuleRecipient(itemID)
    if not recipient or self:IsMe(recipient) then return nil end
    if reason ~= "item" then
        if reason == "gear" and (info.quality or 0) < Enum.ItemQuality.Uncommon then return nil end
        if option("mailKeepCrafts") and self.crafts and self.crafts[reason] then return nil end
    end
    return recipient, reason
end

local function sortEntries(a, b)
    local ka, kb = KIND_ORDER[a.kind] or 99, KIND_ORDER[b.kind] or 99
    if ka ~= kb then return ka < kb end
    if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

function SendToAlts:Scan()
    local groups, byKey = {}, {}
    local prices = R.Prices
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked then
                local recipient, reason = self:RouteFor(info)
                local quest = recipient and C_Container.GetContainerItemQuestInfo(bag, slot)
                if quest and not quest.isQuestItem and not quest.questID then
                    local key = normal(recipient)
                    local group = byKey[key]
                    if not group then
                        group = { key = key, recipient = recipient, entries = {} }
                        byKey[key] = group
                        groups[#groups + 1] = group
                    end
                    local count = info.stackCount or 1
                    group.entries[#group.entries + 1] = {
                        bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                        icon = info.iconFileID, count = count, quality = info.quality,
                        reason = reason, kind = classify(info.itemID),
                        value = prices and info.hyperlink and prices.Get(info.hyperlink, count) or nil,
                    }
                end
            end
        end
    end
    local bankAlt = normal(option("mailBankAlt"))
    for _, group in ipairs(groups) do table.sort(group.entries, sortEntries) end
    table.sort(groups, function(a, b)
        if (a.key == bankAlt) ~= (b.key == bankAlt) then return a.key == bankAlt end
        return a.key < b.key
    end)
    self.groups, self.groupsByKey = groups, byKey
    if not (self.selected and byKey[self.selected]) then
        self.selected = groups[1] and groups[1].key or nil
    end
end

function SendToAlts:Groups()
    return self.groups or {}
end

function SendToAlts:SelectedGroup()
    return self.selected and self.groupsByKey and self.groupsByKey[self.selected] or nil
end

-- The panel stands aside for a player with no other character to mail.
function SendToAlts:HasRecipients()
    return #self:Recipients() > 0
end

-- Attachments belong to whoever is in To. A mail already holding items for someone else is
-- never readdressed: the panel says so and attaches nothing.
function SendToAlts:Address(recipient, quiet)
    local current = SendMailNameEditBox:GetText() or ""
    if normal(current) == normal(recipient) then return true end
    if current ~= "" and attachedCount() > 0 then
        if not quiet then R:Print(string.format(R.L.MAIL_ALTS_OTHER_RECIPIENT, current)) end
        return false
    end
    SendMailNameEditBox:SetText(recipient)
    return true
end

-- Picked up and dropped on the attachments, as a drag would. Never by using the item: if the
-- client did not think the send tab was open, that would use or equip it.
function SendToAlts:AttachEntry(entry)
    local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
    if not info or info.itemID ~= entry.itemID or info.isLocked then return false end
    C_Container.PickupContainerItem(entry.bag, entry.slot)
    ClickSendMailItemButton()
    if CursorHasItem() then
        ClearCursor()
        return false
    end
    return true
end

-- Every attach starts here: a mailbox that is open, a hand that is empty, room in the mail, and
-- a To that is this recipient's. Returns the number of free attachment slots.
function SendToAlts:Prepare(group)
    if not self:IsActive() or not group then return 0 end
    if CursorHasItem() then
        R:Print(R.L.MAIL_ALTS_CURSOR)
        return 0
    end
    local free = ATTACHMENTS_MAX_SEND - attachedCount()
    if free <= 0 then
        R:Print(R.L.MAIL_ALTS_FULL)
        return 0
    end
    if not self:Address(group.recipient) then return 0 end
    return free
end

function SendToAlts:Click(entry)
    local group = self:SelectedGroup()
    if self:Prepare(group) > 0 then
        self.batch = nil
        self:AttachEntry(entry)
        self:QueueRefresh()
    end
end

function SendToAlts:ClickAll(itemID)
    local group = self:SelectedGroup()
    local free = self:Prepare(group)
    if free <= 0 then return end
    self.batch = nil
    for _, entry in ipairs(group.entries) do
        if free <= 0 then break end
        if entry.itemID == itemID and self:AttachEntry(entry) then free = free - 1 end
    end
    self:QueueRefresh()
end

-- As many as the mail has room for, in the panel's order. A mail sent after this one brings the
-- next batch for the same recipient.
function SendToAlts:Fill()
    local group = self:SelectedGroup()
    local free = self:Prepare(group)
    if free <= 0 then return end
    self.batch = group.recipient
    for _, entry in ipairs(group.entries) do
        if free <= 0 then break end
        if self:AttachEntry(entry) then free = free - 1 end
    end
    self:QueueRefresh()
end

function SendToAlts:Select(key)
    local group = self.groupsByKey and self.groupsByKey[key]
    if not group then return end
    self.selected, self.batch = key, nil
    if self:IsActive() then self:Address(group.recipient) end
    self:Render()
end

function SendToAlts:SetBankAlt(name)
    if R.Settings:SetOption("mailBankAlt", name or "") then self:Refresh() end
end

-- A category goes to a named character, to the bank alt (nil), or stays (false).
function SendToAlts:RouteKind(kind, recipient)
    if not KIND_ORDER[kind] then return end
    local routes = copy(option("mailRoutes"))
    routes[kind] = recipient
    if R.Settings:SetOption("mailRoutes", routes) then self:Refresh() end
end

-- An item goes to a named character from now on, or back to its category's rule (nil).
function SendToAlts:RouteItem(itemID, recipient)
    local routes, learning = copy(option("mailItemRoutes")), copy(option("mailLearning"))
    routes[itemID], learning[itemID] = recipient, nil
    R.Settings:SetOption("mailLearning", learning)
    if R.Settings:SetOption("mailItemRoutes", routes) then self:Refresh() end
end

function SendToAlts:Never(itemID)
    local never = copy(option("mailNeverIDs"))
    never[itemID] = true
    if R.Settings:SetOption("mailNeverIDs", never) then self:Refresh() end
end

function SendToAlts:ClearNever()
    R.Settings:SetOption("mailNeverIDs", {})
    if self:IsActive() then self:Refresh() end
end

function SendToAlts:NeverCount()
    local count = 0
    for _ in pairs(option("mailNeverIDs") or {}) do count = count + 1 end
    return count
end

-- The gold above what the player keeps, less postage, goes in Blizzard's money field.
function SendToAlts:GoldAmount()
    local keep = option("mailKeepGold") or 0
    if keep <= 0 then return nil end
    return GetMoney() - keep * COPPER_PER_GOLD - GetSendMailPrice()
end

function SendToAlts:AddGold()
    local amount = self:GoldAmount()
    if not amount or not self:IsActive() then return end
    if amount <= 0 then
        R:Print(R.L.MAIL_ALTS_NO_GOLD)
        return
    end
    local group = self:SelectedGroup()
    if group and not self:Address(group.recipient) then return end
    MoneyInputFrame_SetCopper(SendMailMoney, amount)
end

-- What the footer reads: stacks left for this recipient after what is attached, the mails
-- they need, the postage now, and what the attached items are worth.
function SendToAlts:Summary()
    local group = self:SelectedGroup()
    local attached, value = 0, 0
    local prices = R.Prices
    for index = 1, ATTACHMENTS_MAX_SEND do
        if HasSendMailItem(index) then
            attached = attached + 1
            local link = GetSendMailItemLink(index)
            local _, _, _, count = GetSendMailItem(index)
            local worth = prices and link and prices.Get(link, count or 1)
            if worth then value = value + worth end
        end
    end
    local left = group and #group.entries or 0
    local room = ATTACHMENTS_MAX_SEND - attached
    local mails = 0
    if left > room then
        mails = math.ceil((left - room) / ATTACHMENTS_MAX_SEND)
    end
    if left > 0 then mails = mails + 1 end
    return { left = left, mails = mails, attached = attached, postage = GetSendMailPrice(), value = value,
        gold = self:GoldAmount() }
end

-- What SendMail was called with is the To the client accepted, and the attachments are still
-- in place while the hook runs.
function SendToAlts:Snapshot(recipient)
    if not self:IsActive() then return end
    local items, seen = {}, {}
    for index = 1, ATTACHMENTS_MAX_SEND do
        if HasSendMailItem(index) then
            local _, itemID = GetSendMailItem(index)
            if itemID and not seen[itemID] then
                seen[itemID] = true
                items[#items + 1] = itemID
            end
        end
    end
    self.sending = { recipient = recipient, items = items }
end

-- An item mailed by hand to the same own character twice goes there from then on. Once is a
-- one-off; a different character the second time starts the count again.
function SendToAlts:Learn(recipient, items)
    if not self:IsOwn(recipient) or self:IsMe(recipient) then return end
    local key = normal(recipient)
    local routes, learning = copy(option("mailItemRoutes")), copy(option("mailLearning"))
    local changed = false
    for _, itemID in ipairs(items) do
        if normal(self:RuleRecipient(itemID)) ~= key then
            if normal(learning[itemID]) == key then
                routes[itemID], learning[itemID] = recipient, nil
            else
                learning[itemID] = recipient
            end
            changed = true
        end
    end
    if changed then
        R.Settings:SetOption("mailLearning", learning)
        R.Settings:SetOption("mailItemRoutes", routes)
    end
end

function SendToAlts:OnSendSuccess()
    local sending = self.sending
    self.sending = nil
    if not sending then return end
    self:Learn(sending.recipient, sending.items)
    if self.batch and normal(self.batch) == normal(sending.recipient) and not R:Paused() then
        self.continuing = self.batch
    end
    self.batch = nil
end

function SendToAlts:OnSendFailed()
    self.sending, self.continuing, self.batch = nil, nil, nil
end

-- The next batch waits for the bags to drop what was sent, which is also after Blizzard has
-- emptied the To field for the next mail.
function SendToAlts:OnBagsChanged()
    local recipient = self.continuing
    if not recipient then
        self:QueueRefresh()
        return
    end
    self.continuing = nil
    self:Refresh()
    local key = normal(recipient)
    if self.groupsByKey and self.groupsByKey[key] and SendMailFrame:IsShown() then
        self.selected = key
        self:Fill()
    end
end

function SendToAlts:QueueRefresh()
    if self.refreshTimer or not self:IsActive() then return end
    self.refreshTimer = R:After(self, REFRESH_DELAY, function(owner)
        owner.refreshTimer = nil
        owner:Refresh()
    end)
end

function SendToAlts:Refresh()
    if not self:IsActive() then
        self:Render()
        return
    end
    self:Scan()
    self:Render()
end

function SendToAlts:Render()
    local panel = self.panel
    if not panel then return end
    if self:IsActive() and SendMailFrame:IsShown() and self:HasRecipients() then
        panel:Render(self)
    else
        panel:Hide()
    end
end

-- Blizzard's own OnShow may clear To, so the fill waits a tick.
function SendToAlts:FillRecipient()
    if not self:IsActive() or not option("mailFillRecipient") or R:Paused() then return end
    local group = self:SelectedGroup()
    if group and (SendMailNameEditBox:GetText() or "") == "" and attachedCount() == 0 then
        SendMailNameEditBox:SetText(group.recipient)
    end
end

function SendToAlts:OnSendShown()
    if not self:IsActive() then return end
    self:Refresh()
    R:After(self, 0, self.FillRecipient)
end

function SendToAlts:OnMailShow()
    self:Stop()
    self.session = true
    self:ReadCrafts()
    R.Broker:Subscribe("MAIL_CLOSED", self.Stop, self)
    R.Broker:Subscribe("BAG_UPDATE_DELAYED", self.OnBagsChanged, self, REFRESH_DELAY)
    R.Broker:Subscribe("ITEM_LOCK_CHANGED", self.QueueRefresh, self, REFRESH_DELAY)
    R.Broker:Subscribe("MAIL_SEND_INFO_UPDATE", self.QueueRefresh, self, REFRESH_DELAY)
    R.Broker:Subscribe("MAIL_SEND_SUCCESS", self.OnSendSuccess, self)
    R.Broker:Subscribe("MAIL_FAILED", self.OnSendFailed, self)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.QueueRefresh, self)
    if SendMailFrame:IsShown() then self:OnSendShown() end
end

function SendToAlts:Stop()
    self.session, self.sending, self.continuing, self.batch = false, nil, nil, nil
    self.refreshTimer, self.groups, self.groupsByKey, self.selected = nil, nil, nil, nil
    R:CancelTimers(self)
    for _, event in ipairs({ "MAIL_CLOSED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "MAIL_SEND_INFO_UPDATE",
        "MAIL_SEND_SUCCESS", "MAIL_FAILED", "REFACTOR_SETTINGS_CHANGED" }) do
        R.Broker:Unsubscribe(event, self)
    end
    if self.panel then self.panel:Hide() end
end

-- Hooks cannot be taken back, so they are installed once and do nothing while disabled.
function SendToAlts:InstallHooks()
    if self.hooked then return end
    self.hooked = true
    hooksecurefunc("SendMail", function(recipient)
        if self:IsActive() then self:Snapshot(recipient) end
    end)
    SendMailFrame:HookScript("OnShow", function()
        if self:IsActive() then self:OnSendShown() end
    end)
    SendMailFrame:HookScript("OnHide", function()
        if self.panel then self.panel:Hide() end
    end)
end

function SendToAlts:OnEnable()
    self.panel = R.UI:CreateMailAltsPanel(self)
    self:InstallHooks()
    self:Remember()
    self:CompleteNames()
    R.Broker:Subscribe("MAIL_SHOW", self.OnMailShow, self)
end

function SendToAlts:OnDisable()
    self:Stop()
    R.Broker:UnsubscribeAll(self)
end
