local _, R = ...
R.L = R.L or {}
local L = R.L
L.UI_Nameplates = "Nameplates"
L.NAMEPLATE_QUEST_NAME = "Quest progress on nameplates"
L.NAMEPLATE_QUEST_DESC = "Show how close each mob is to finishing your objective."
L.NAMEPLATE_QUEST_DETAIL = "Reads your own quest progress only, never another player's. Defers to Questie "
    .. "and Plater when either is loaded. Turn it off if your nameplates feel crowded."
L.NAMEPLATE_QUEST_DEFERRED = "%s already shows quest progress on nameplates."
L.NAMEPLATE_TOTAL = "/%d"
L.NAMEPLATE_TOTAL_PLUS = "/%d +%d"
