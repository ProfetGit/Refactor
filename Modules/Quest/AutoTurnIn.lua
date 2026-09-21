--- @module quest.autoTurnIn
--- Purpose: hand in a quest when it is completable and offers no reward choice.
--- Requires: InCombatLockdown, IsQuestCompletable, CompleteQuest, GetNumQuestChoices, GetQuestReward
--- Events: QUEST_PROGRESS, QUEST_COMPLETE
--- Hot: no
local _, R = ...
local AutoTurnIn = R:RegisterModule({
    id = "quest.autoTurnIn", category = "Quest", nameKey = "QUEST_TURNIN_NAME",
    descriptionKey = "QUEST_TURNIN_DESC", detailKey = "QUEST_TURNIN_DETAIL",
    requires = { "InCombatLockdown", "IsQuestCompletable", "CompleteQuest", "GetNumQuestChoices",
        "GetQuestReward" },
    risk = "automation", defaultEnabled = false,
})

function AutoTurnIn:OnProgress()
    if InCombatLockdown() or R:Paused() then
        return
    end
    if IsQuestCompletable() then
        CompleteQuest()
    end
end

-- A quest with a choice is left open on purpose: choosing is the player's decision (PRD 7.1).
function AutoTurnIn:OnComplete()
    if InCombatLockdown() or R:Paused() then
        return
    end
    if GetNumQuestChoices() == 0 then
        GetQuestReward(0)
    end
end

function AutoTurnIn:OnEnable()
    R.Broker:Subscribe("QUEST_PROGRESS", self.OnProgress, self)
    R.Broker:Subscribe("QUEST_COMPLETE", self.OnComplete, self)
end

function AutoTurnIn:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
