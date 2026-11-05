--- @module quest.autoTurnIn
--- Purpose: hand in a quest when it is completable, offers at most one reward and costs no gold.
--- Requires: InCombatLockdown, IsQuestCompletable, CompleteQuest, GetNumQuestChoices, GetQuestReward,
---     GetQuestMoneyToGet
--- Events: QUEST_PROGRESS, QUEST_COMPLETE
--- Hot: no
local _, R = ...
local AutoTurnIn = R:RegisterModule({
    id = "quest.autoTurnIn", category = "Quest", nameKey = "QUEST_TURNIN_NAME",
    descriptionKey = "QUEST_TURNIN_DESC", detailKey = "QUEST_TURNIN_DETAIL",
    requires = { "InCombatLockdown", "IsQuestCompletable", "CompleteQuest", "GetNumQuestChoices",
        "GetQuestReward", "GetQuestMoneyToGet" },
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

-- A lone reward is not a choice: Blizzard's own Complete button takes it as choice 1
-- (QuestRewardCompleteButton_OnClick, 12.1.0). Two or more stay open, because choosing is the
-- player's decision (PRD 7.1), and so does a hand-in that costs gold, which Blizzard confirms
-- with the player before paying.
function AutoTurnIn:OnComplete()
    if InCombatLockdown() or R:Paused() then
        return
    end
    local choices, money = GetNumQuestChoices(), GetQuestMoneyToGet()
    if choices <= 1 and not (money and money > 0) then
        GetQuestReward(choices)
    end
end

function AutoTurnIn:OnEnable()
    R.Broker:Subscribe("QUEST_PROGRESS", self.OnProgress, self)
    R.Broker:Subscribe("QUEST_COMPLETE", self.OnComplete, self)
end

function AutoTurnIn:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
