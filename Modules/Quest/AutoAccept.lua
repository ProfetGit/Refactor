--- @module quest.autoAccept
--- Purpose: accept a quest when its detail dialog opens, and open an NPC's offers one at a
---     time so a list of several quests does not stop where a single one would not.
--- Requires: InCombatLockdown, AcceptQuest, QuestGetAutoAccept, QuestFlagsPVP, GetQuestID,
---     QuestIsFromAdventureMap, GetNumAvailableQuests, GetAvailableQuestInfo, SelectAvailableQuest,
---     UnitGUID, C_QuestLog.IsRepeatableQuest, C_QuestLog.GetNumQuestLogEntries,
---     C_QuestLog.GetMaxNumQuestsCanAccept, C_GossipInfo.GetAvailableQuests,
---     C_GossipInfo.SelectAvailableQuest
--- Events: QUEST_DETAIL, QUEST_GREETING, GOSSIP_SHOW, REFACTOR_GOSSIP_HANDLED
--- Hot: no
local _, R = ...
local AutoAccept = R:RegisterModule({
    id = "quest.autoAccept", category = "Quest", nameKey = "QUEST_ACCEPT_NAME",
    descriptionKey = "QUEST_ACCEPT_DESC", detailKey = "QUEST_ACCEPT_DETAIL",
    requires = { "InCombatLockdown", "AcceptQuest", "QuestGetAutoAccept", "QuestFlagsPVP", "GetQuestID",
        "QuestIsFromAdventureMap", "GetNumAvailableQuests", "GetAvailableQuestInfo", "SelectAvailableQuest",
        "UnitGUID", "C_QuestLog.IsRepeatableQuest", "C_QuestLog.GetNumQuestLogEntries",
        "C_QuestLog.GetMaxNumQuestsCanAccept", "C_GossipInfo.GetAvailableQuests",
        "C_GossipInfo.SelectAvailableQuest" },
    risk = "automation", defaultEnabled = false,
})

-- Offers opened at one NPC before the player takes over. More than this on a single unit is
-- a menu worth reading, and the cap is what ends a quest the server keeps re-listing.
local MAX_OFFERS = 10

-- Second return of GetNumQuestLogEntries is the quest count without the log's headers, which
-- is what the accept limit counts (Blizzard_StaticPopup_Game/GameDialogDefs.lua).
local function logIsFull()
    local questCount = select(2, C_QuestLog.GetNumQuestLogEntries())
    local limit = C_QuestLog.GetMaxNumQuestsCanAccept()
    return type(questCount) == "number" and type(limit) == "number" and limit > 0 and questCount >= limit
end

-- Per-NPC state lives on the module table the registry and window read, so it keeps clear of
-- the definition's own field names.
function AutoAccept:Reset()
    self.visitGUID, self.tried, self.offers, self.warned, self.claimed = nil, {}, 0, nil, nil
end

-- Offers already opened are remembered until the player talks to a different unit: a quest
-- the exclusions refuse leaves its dialog open, and re-opening it on the next page would loop.
function AutoAccept:Visit(unit)
    local guid = UnitGUID(unit)
    if guid ~= self.visitGUID then
        self.visitGUID, self.tried, self.offers, self.warned = guid, {}, 0, nil
    end
end

function AutoAccept:LogFull()
    if not logIsFull() then
        return false
    end
    if not self.warned then
        self.warned = true
        R:Print(R.L.QUEST_ACCEPT_LOG_FULL)
    end
    return true
end

function AutoAccept:CanOpen()
    if InCombatLockdown() or R:Paused() then
        return false
    end
    if not R.Settings:GetOption("questAcceptLists") then
        return false
    end
    -- Limited to quests started from items, an NPC's own list is not this module's business.
    if R.Settings:GetOption("questAcceptItemsOnly") then
        return false
    end
    return self.offers < MAX_OFFERS and not self:LogFull()
end

-- Ignored is the player's own filter, and a repeatable quest is refused on the detail side
-- too, so neither is worth opening.
function AutoAccept:Take(key, isIgnored, isRepeatable)
    if key == nil or self.tried[key] or isIgnored or isRepeatable then
        return false
    end
    self.tried[key], self.offers = true, self.offers + 1
    return true
end

-- The gossip list: one offer per page, because selecting it replaces the page with the quest
-- detail and the rest of the list comes back when that closes.
function AutoAccept:OnGossip()
    local claimed = self.claimed
    self.claimed = nil
    self:Visit("npc")
    -- The gossip module already acted on this page; its pick is about to replace the list.
    if claimed or not self:CanOpen() then
        return
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
        if self:Take(quest.questID, quest.isIgnored, quest.repeatable) then
            C_GossipInfo.SelectAvailableQuest(quest.questID)
            return
        end
    end
end

-- The greeting panel, which lists quests without gossip options and is what a multi-quest
-- NPC shows once its first quest is handed in.
function AutoAccept:OnGreeting()
    self:Visit("questnpc")
    if not self:CanOpen() then
        return
    end
    for index = 1, GetNumAvailableQuests() do
        -- isTrivial, frequency, isRepeatable, isLegendary, questID (Mainline/QuestFrame.lua).
        local _, _, isRepeatable, _, questID = GetAvailableQuestInfo(index)
        -- A server that sends no ID still gives a stable slot for the length of the page.
        if self:Take(questID or -index, false, isRepeatable) then
            SelectAvailableQuest(index)
            return
        end
    end
end

function AutoAccept:OnClaim()
    self.claimed = true
end

function AutoAccept:OnDetail(_, questStartItemID)
    if InCombatLockdown() or R:Paused() then
        return
    end
    -- The game accepts these itself; a second call would be a duplicate.
    if QuestGetAutoAccept() or QuestFlagsPVP() then
        return
    end
    -- An adventure map offer never opens the detail panel, so accepting one here is not the
    -- dialog the player is looking at (Mainline/QuestFrame.lua, QUEST_DETAIL).
    if QuestIsFromAdventureMap() then
        return
    end
    if R.Settings:GetOption("questAcceptItemsOnly") and not (questStartItemID and questStartItemID > 0) then
        return
    end
    local questID = GetQuestID()
    if questID and questID > 0 and C_QuestLog.IsRepeatableQuest(questID) then
        return
    end
    -- Accepting into a full log is refused by the server and answered with a popup.
    if self:LogFull() then
        return
    end
    AcceptQuest()
end

function AutoAccept:OnEnable()
    self:Reset()
    R.Broker:Subscribe("QUEST_DETAIL", self.OnDetail, self)
    R.Broker:Subscribe("QUEST_GREETING", self.OnGreeting, self)
    -- Below the gossip module, so that module's claim for the page arrives before this runs.
    R.Broker:Subscribe("GOSSIP_SHOW", self.OnGossip, self, nil, -10)
    R.Broker:Subscribe("REFACTOR_GOSSIP_HANDLED", self.OnClaim, self)
end

function AutoAccept:OnDisable()
    R.Broker:UnsubscribeAll(self)
    self:Reset()
end
