--- @module quest.autoAccept
--- Purpose: accept a quest when its detail dialog opens, with the PRD exclusions.
--- Requires: InCombatLockdown, AcceptQuest, QuestGetAutoAccept, QuestFlagsPVP, GetQuestID,
---     C_QuestLog.IsRepeatableQuest
--- Events: QUEST_DETAIL
--- Hot: no
local _, R = ...
local AutoAccept = R:RegisterModule({
    id = "quest.autoAccept", category = "Quest", nameKey = "QUEST_ACCEPT_NAME",
    descriptionKey = "QUEST_ACCEPT_DESC", detailKey = "QUEST_ACCEPT_DETAIL",
    requires = { "InCombatLockdown", "AcceptQuest", "QuestGetAutoAccept", "QuestFlagsPVP", "GetQuestID",
        "C_QuestLog.IsRepeatableQuest" },
    tier = "manual", risk = "automation", defaultEnabled = false,
})

function AutoAccept:OnDetail(_, questStartItemID)
    if InCombatLockdown() or R:Paused() then
        return
    end
    -- The game accepts these itself; a second call would be a duplicate.
    if QuestGetAutoAccept() or QuestFlagsPVP() then
        return
    end
    if R.Settings:GetOption("questAcceptItemsOnly") and not (questStartItemID and questStartItemID > 0) then
        return
    end
    local questID = GetQuestID()
    if questID and questID > 0 and C_QuestLog.IsRepeatableQuest(questID) then
        return
    end
    AcceptQuest()
end

function AutoAccept:OnEnable()
    R.Broker:Subscribe("QUEST_DETAIL", self.OnDetail, self)
end

function AutoAccept:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
