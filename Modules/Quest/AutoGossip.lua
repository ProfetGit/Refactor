--- @module quest.autoGossip
--- Purpose: pick the gossip option the player would have picked: a remembered choice, the
---     only quest, the one service among small talk, and on request a lone line of dialogue.
--- Requires: InCombatLockdown, IsInInstance, UnitGUID, hooksecurefunc, GossipOptionButtonMixin, IsControlKeyDown,
---     IsShiftKeyDown, IsAltKeyDown, C_GossipInfo.GetOptions, C_GossipInfo.GetAvailableQuests,
---     C_GossipInfo.GetActiveQuests, C_GossipInfo.ForceGossip, C_GossipInfo.SelectOptionByIndex,
---     C_GossipInfo.SelectAvailableQuest, C_GossipInfo.SelectActiveQuest, Enum.GossipOptionStatus.Available,
---     Enum.GossipOptionRecFlags.QuestLabelPrepend, Enum.GossipOptionRecFlags.PlayMovieLabelPrepend
--- Events: GOSSIP_SHOW, GOSSIP_CLOSED, a post-hook on the gossip option button click, and
---     REFACTOR_GOSSIP_HANDLED emitted for whichever module reads the page next
--- Hot: no
local _, R = ...
local AutoGossip = R:RegisterModule({
    id = "quest.autoGossip", category = "Quest", nameKey = "QUEST_GOSSIP_NAME",
    descriptionKey = "QUEST_GOSSIP_DESC", detailKey = "QUEST_GOSSIP_DETAIL",
    requires = { "InCombatLockdown", "IsInInstance", "UnitGUID", "hooksecurefunc", "GossipOptionButtonMixin",
        "IsControlKeyDown", "IsShiftKeyDown", "IsAltKeyDown", "C_GossipInfo.GetOptions",
        "C_GossipInfo.GetAvailableQuests", "C_GossipInfo.GetActiveQuests", "C_GossipInfo.ForceGossip",
        "C_GossipInfo.SelectOptionByIndex", "C_GossipInfo.SelectAvailableQuest", "C_GossipInfo.SelectActiveQuest",
        "Enum.GossipOptionStatus.Available", "Enum.GossipOptionRecFlags.QuestLabelPrepend",
        "Enum.GossipOptionRecFlags.PlayMovieLabelPrepend" },
    risk = "safe", defaultEnabled = false,
})

-- Gossip icon file IDs from Interface/GossipFrame. A service opens a window the player can
-- close again. Everything else with an icon of its own (binder, unlearn, tabard, spirit
-- healer, battlemaster, petition) commits to something, so no rule ever picks it.
local SERVICE_ICONS = {
    [132060] = true, -- VendorGossipIcon
    [132058] = true, -- TrainerGossipIcon
    [132057] = true, -- TaxiGossipIcon
    [132050] = true, -- BankerGossipIcon
    [528409] = true, -- AuctioneerGossipIcon
    [1673939] = true, -- TransmogrifyGossipIcon
}
local DIALOGUE_ICONS = {
    [132053] = true, -- GossipGossipIcon
    [1019848] = true, -- ChatBubbleGossipIcon
}
-- Picks per visit before the player takes over: enough for a run of hand-ins or a long
-- dialogue, and the end of a menu that keeps leading back to itself.
local MAX_STEPS = 8
local MODIFIER_CHECKS = { CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown, ALT = IsAltKeyDown }
-- Players and pets carry an individual's ID, not a kind of NPC, so they get no memory.
local UNIT_KINDS = { Creature = true, GameObject = true, Vehicle = true }

-- "Creature-0-3061-1-42177-38038-002FAC4343": the kind comes first, the ID is the sixth field.
local function unitKey(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind and UNIT_KINDS[kind] then
        return kind, tonumber(id)
    end
    return nil
end

local function hasFlag(flags, flag)
    return type(flags) == "number" and math.floor(flags / flag) % 2 == 1
end

-- Plain means selecting it commits to nothing the client can see: selectable now, no
-- spell, no reward, no quest or movie label, no designer icon.
local function isPlain(option)
    if option.status ~= Enum.GossipOptionStatus.Available or option.spellID or option.overrideIconID then
        return false
    end
    if type(option.rewards) == "table" and #option.rewards > 0 then
        return false
    end
    return not hasFlag(option.flags, Enum.GossipOptionRecFlags.QuestLabelPrepend)
        and not hasFlag(option.flags, Enum.GossipOptionRecFlags.PlayMovieLabelPrepend)
end

local function kindOf(option)
    if not isPlain(option) then
        return "other"
    elseif SERVICE_ICONS[option.icon] then
        return "service"
    elseif DIALOGUE_ICONS[option.icon] then
        return "dialogue"
    end
    return "other"
end

-- One visit can show several pages. A page is recorded when a rule acts on it, so the same
-- page coming back (a menu that loops) is left to the player rather than clicked forever.
local function signature(options, available, active)
    local page = {}
    for _, option in ipairs(options) do
        page[#page + 1] = option.gossipOptionID or option.name
    end
    page[#page + 1] = "available"
    for _, quest in ipairs(available) do
        page[#page + 1] = quest.questID
    end
    page[#page + 1] = "active"
    for _, quest in ipairs(active) do
        page[#page + 1] = quest.isComplete and -quest.questID or quest.questID
    end
    return page
end

local function samePage(a, b)
    if #a ~= #b then
        return false
    end
    for index = 1, #a do
        if a[index] ~= b[index] then
            return false
        end
    end
    return true
end

local function copyLearned(learned)
    local result = {}
    if type(learned) == "table" then
        for kind, entries in pairs(learned) do
            local copy = {}
            for id, optionID in pairs(entries) do
                copy[id] = optionID
            end
            result[kind] = copy
        end
    end
    return result
end

function AutoGossip:Learned(kind, id)
    local learned = R.Settings:GetOption("gossipLearned")
    local entries = type(learned) == "table" and learned[kind]
    return entries and entries[id] or nil
end

function AutoGossip:Remember(kind, id, optionID)
    local learned = copyLearned(R.Settings:GetOption("gossipLearned"))
    learned[kind] = learned[kind] or {}
    learned[kind][id] = optionID
    if next(learned[kind]) == nil then
        learned[kind] = nil
    end
    return R.Settings:SetOption("gossipLearned", learned)
end

-- Per-visit state lives on the module table the registry and window read, so it keeps
-- clear of the definition's field names: `id` is what every settings lookup keys on.
function AutoGossip:Reset()
    self.options, self.npcKind, self.npcID, self.steps, self.pages = nil, nil, nil, 0, {}
end

function AutoGossip:Seen(page)
    for _, previous in ipairs(self.pages) do
        if samePage(previous, page) then
            return true
        end
    end
    return false
end

function AutoGossip:Act(page)
    self.steps = self.steps + 1
    self.pages[#self.pages + 1] = page
    -- Announced because the pick replaces this page: a module still to read it would be
    -- acting on a list the server is already taking away.
    R.Broker:Emit("REFACTOR_GOSSIP_HANDLED")
end

function AutoGossip:Pick(page, option)
    self:Act(page)
    C_GossipInfo.SelectOptionByIndex(option.orderIndex)
end

-- A finished quest is what the player came to hand in. A single offer with nothing else on
-- the list opens its detail, which still asks the player to accept.
function AutoGossip:OpenQuest(page, available, active)
    for _, quest in ipairs(active) do
        if quest.isComplete and not quest.isIgnored then
            self:Act(page)
            C_GossipInfo.SelectActiveQuest(quest.questID)
            return
        end
    end
    if #active > 0 then
        return
    end
    local offer, count = nil, 0
    for _, quest in ipairs(available) do
        if not quest.isIgnored then
            offer, count = quest, count + 1
        end
    end
    if count == 1 then
        self:Act(page)
        C_GossipInfo.SelectAvailableQuest(offer.questID)
    end
end

function AutoGossip:OnShow(_, textureKit)
    local options = C_GossipInfo.GetOptions()
    local kind, id = unitKey(UnitGUID("npc"))
    if kind ~= self.npcKind or id ~= self.npcID then
        self.npcKind, self.npcID, self.steps, self.pages = kind, id, 0, {}
    end
    self.options = options
    -- A texture kit means a custom frame (the new player guide, Torghast's level picker)
    -- whose choices are not this module's business. ForceGossip is the server insisting.
    if textureKit ~= nil or C_GossipInfo.ForceGossip() or InCombatLockdown() or R:Paused() then
        return
    end
    local available, active = C_GossipInfo.GetAvailableQuests(), C_GossipInfo.GetActiveQuests()
    local page = signature(options, available, active)
    if self.steps >= MAX_STEPS or self:Seen(page) then
        return
    end
    if kind then
        local learnedID = self:Learned(kind, id)
        if learnedID then
            for _, option in ipairs(options) do
                if option.gossipOptionID == learnedID then
                    -- Locked or already done: show the player why rather than guess.
                    if option.status == Enum.GossipOptionStatus.Available then
                        self:Pick(page, option)
                    end
                    return
                end
            end
        end
    end
    -- Dungeon NPCs start fights and skip bosses. Only a choice the player taught applies.
    if IsInInstance() and not R.Settings:GetOption("gossipInInstances") then
        return
    end
    if #options == 0 then
        if R.Settings:GetOption("gossipOpenQuests") then
            self:OpenQuest(page, available, active)
        end
        return
    end
    -- A quest next to gossip options is a real choice.
    if #available > 0 or #active > 0 then
        return
    end
    -- The client selects a flagged only option itself (GossipFrameShared.lua, HandleShow).
    if #options == 1 and options[1].selectOptionWhenOnlyOption then
        return
    end
    local service, services, dialogue = nil, 0, 0
    for _, option in ipairs(options) do
        local optionKind = kindOf(option)
        if optionKind == "service" then
            service, services = option, services + 1
        elseif optionKind == "dialogue" then
            dialogue = dialogue + 1
        else
            return
        end
    end
    if services == 1 and R.Settings:GetOption("gossipOpenServices") then
        self:Pick(page, service)
    elseif services == 0 and dialogue == 1 and R.Settings:GetOption("gossipSkipDialogue") then
        self:Pick(page, options[1])
    end
end

function AutoGossip:OnClosed(_, interactionIsContinuing)
    self.options = nil
    -- A page change closes with the flag set. A real close ends the visit and its budget.
    if not interactionIsContinuing then
        self.npcKind, self.npcID, self.steps, self.pages = nil, nil, 0, {}
    end
end

-- Runs after a click on one of Blizzard's gossip option buttons, whose ID is the option's
-- order index. Only a real click lands here, never one of the module's own picks.
function AutoGossip:OnPlayerClick(orderIndex)
    if self.state ~= "enabled" or not self.options or not self.npcKind then
        return
    end
    local check = MODIFIER_CHECKS[R.Settings:GetOption("gossipLearnModifier")] or IsShiftKeyDown
    if not check() then
        return
    end
    local chosen
    for _, option in ipairs(self.options) do
        if option.orderIndex == orderIndex then
            chosen = option
            break
        end
    end
    -- An option whose ID the server hides cannot be told apart next visit.
    if not chosen or not chosen.gossipOptionID then
        return
    end
    if self:Learned(self.npcKind, self.npcID) == chosen.gossipOptionID then
        self:Remember(self.npcKind, self.npcID, nil)
        R:Print(string.format(R.L.QUEST_GOSSIP_FORGOTTEN, chosen.name))
    else
        self:Remember(self.npcKind, self.npcID, chosen.gossipOptionID)
        R:Print(string.format(R.L.QUEST_GOSSIP_LEARNED, chosen.name))
    end
end

function AutoGossip:OnEnable()
    self:Reset()
    R.Broker:Subscribe("GOSSIP_SHOW", self.OnShow, self)
    R.Broker:Subscribe("GOSSIP_CLOSED", self.OnClosed, self)
end

function AutoGossip:OnDisable()
    R.Broker:UnsubscribeAll(self)
    self:Reset()
end

-- The mixin is copied onto each option button when the gossip list first builds it, which
-- happens after addons load, so the hook has to be in place now rather than at enable. It
-- is inert until the module is enabled and stays out of OnEnable, so there is nothing for
-- OnDisable to undo. A failed install is recorded, never fatal: the rules still work. A
-- client without the mixin is a missing capability, reported at enable, not an error.
if type(hooksecurefunc) == "function" and type(GossipOptionButtonMixin) == "table" then
    local hooked, hookError = pcall(hooksecurefunc, GossipOptionButtonMixin, "OnClick", function(button)
        if AutoGossip.state == "enabled" then
            R:SafeCall(AutoGossip, AutoGossip.OnPlayerClick, "gossip learn", button:GetID())
        end
    end)
    if not hooked then
        R:RecordError(AutoGossip, hookError, "gossip learn hook")
    end
end
