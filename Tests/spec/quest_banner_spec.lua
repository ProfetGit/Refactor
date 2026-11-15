local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local ID = "quest.progressBanner"
local KILL, PLAYERS, ITEM, FOUND, OBJECTIVE, UNKNOWN, TURNIN = 301, 302, 303, 304, 305, 306, 307
local ACCEPTED = 290

local function world(formats)
    local env = Runtime.new()
    Widgets.install(env)
    env:Load("Locales/Modules.enUS.lua")
    env:Load("Locales/Features.enUS.lua")
    env:Load("Locales/Commands.enUS.lua")
    env.R.UI = env.R.UI or {}
    env:Load("UI/Widgets/Widgets.lua")
    env.messages = {}
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    env.LE_GAME_ERR_QUEST_ADD_KILL_SII, env.LE_GAME_ERR_QUEST_ADD_PLAYER_KILL_SII = KILL, PLAYERS
    env.LE_GAME_ERR_QUEST_ADD_ITEM_SII, env.LE_GAME_ERR_QUEST_ADD_FOUND_SII = ITEM, FOUND
    env.LE_GAME_ERR_QUEST_OBJECTIVE_COMPLETE_S, env.LE_GAME_ERR_QUEST_UNKNOWN_COMPLETE = OBJECTIVE, UNKNOWN
    env.LE_GAME_ERR_QUEST_COMPLETE_S = TURNIN
    formats = formats or {}
    env.ERR_QUEST_ADD_KILL_SII = formats.kill or "%s slain: %d/%d"
    env.ERR_QUEST_ADD_PLAYER_KILL_SII = "Players slain: %d/%d"
    env.ERR_QUEST_ADD_ITEM_SII = formats.item or "%s: %d/%d"
    env.ERR_QUEST_ADD_FOUND_SII = "%s: %d/%d"
    env.ERR_QUEST_OBJECTIVE_COMPLETE_S = "%s (Complete)"
    env.ERR_QUEST_UNKNOWN_COMPLETE = "Objective Complete."
    env.ERR_QUEST_COMPLETE_S = "%s completed."
    env.UIErrorsFrame = env.CreateFrame("MessageFrame", "UIErrorsFrame")
    env.UIErrorsFrame.blocked = {}
    env.UIErrorsFrame.SetMessageTypeEnabled = function(self, messageType, enabled)
        self.blocked[messageType] = not enabled
    end
    env.UIErrorsFrame.GetMessagesSuppressed = function(self) return self.suppressed == true end
    env.UIErrorsFrame.GetBottom = function() return 600 end
    env.sounds, env.voices = {}, {}
    env.GetGameMessageInfo = function(messageType) return "ERR_" .. messageType, messageType + 1000, nil end
    env.PlaySound = function(id) env.sounds[#env.sounds + 1] = id end
    env.C_Sound = { PlayVocalErrorSound = function(id) env.voices[#env.voices + 1] = id end }
    env.log = {
        { questID = 10, title = "Tiger Hunt", objectives = { { text = "2/4 Durotar Tiger Fur", numRequired = 4,
            type = "item" } } },
        { questID = 11, title = "Boar Trouble", objectives = {
            { text = "3/10 Bristleback Quilboar slain", numRequired = 10, type = "monster" },
            { text = "0/1 Scout the camp", numRequired = 1, type = "event" } } },
        { questID = 12, title = "Fur for the Shaman", objectives = { { text = "1/8 Durotar Tiger Fur",
            numRequired = 8, type = "item" } } },
    }
    env.complete = {}
    env.C_QuestLog = {
        GetNumQuestLogEntries = function() return #env.log + 1 end,
        GetInfo = function(index)
            if index == 1 then return { title = "Durotar", isHeader = true } end
            local quest = env.log[index - 1]
            return quest and { questID = quest.questID, title = quest.title, isHeader = false }
        end,
        GetQuestObjectives = function(questID)
            for _, quest in ipairs(env.log) do
                if quest.questID == questID then return quest.objectives end
            end
            return {}
        end,
        IsComplete = function(questID) return env.complete[questID] == true end,
        GetTitleForQuestID = function(questID)
            for _, quest in ipairs(env.log) do
                if quest.questID == questID then return quest.title end
            end
        end,
    }
    return env
end

local function enable(env)
    env:Load("UI/QuestBanner.lua")
    env:Load("Modules/Quest/ProgressBanner.lua")
    local module = env.R.moduleByID[ID]
    assert.is_true(env.R.Registry:Enable(ID), tostring(module.failure) .. table.concat(module.missing or {}, ","))
    return module
end

local function held(env, event)
    local entries = env.R.Broker.events[event]
    return entries and #entries or 0
end

-- Runs Core/Fade's driver the way the client's frames would, in 50 ms steps.
local function tick(env, seconds)
    local driver = env.R.Fade.driver
    for _ = 1, math.floor(seconds / 0.05 + 0.5) do
        local step = driver.scripts.OnUpdate
        if not step then return end
        step(driver, 0.05)
    end
end

local function near(expected, actual)
    assert.is_true(math.abs(expected - actual) < 1e-9, tostring(actual) .. " is not " .. tostring(expected))
end

local function rows(module)
    local out = {}
    for _, row in ipairs(module.ui.active) do
        local entry = row.entry
        out[#out + 1] = { kind = entry.kind, title = entry.title, label = entry.label, have = entry.have,
            need = entry.need }
    end
    return out
end

describe("quest.progressBanner", function()
    it("stops Blizzard drawing only the quest lines, and gives them back on disable", function()
        local env = world()
        local module = enable(env)
        for _, messageType in ipairs({ KILL, PLAYERS, ITEM, FOUND, OBJECTIVE, UNKNOWN, TURNIN }) do
            assert.is_true(env.UIErrorsFrame.blocked[messageType], tostring(messageType))
        end
        assert.is_nil(env.UIErrorsFrame.blocked[ACCEPTED])
        env.R.Registry:Disable(ID)
        for messageType, blocked in pairs(env.UIErrorsFrame.blocked) do
            assert.is_false(blocked, tostring(messageType))
        end
        assert.equals("disabled", module.state)
    end)

    it("turns an item line into the quest's name, the objective and its count, with Blizzard's sound", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 3/4")
        assert.same({ { kind = "progress", title = "Tiger Hunt", label = "Durotar Tiger Fur", have = 3, need = 4 } },
            rows(module))
        assert.same({ ITEM + 1000 }, env.sounds)
        local row = module.ui.active[1]
        assert.equals("3", row.value:GetText())
        assert.equals("/4", row.total:GetText())
        assert.is_true(module.ui.frame:IsShown())
    end)

    it("keeps the kill wording and picks the quest asking for the count the line names", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", KILL, "Bristleback Quilboar slain: 4/10")
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 2/8")
        local shown = rows(module)
        assert.equals(2, #shown)
        assert.same({ kind = "progress", title = "Fur for the Shaman", label = "Durotar Tiger Fur", have = 2,
            need = 8 }, shown[1])
        assert.same({ kind = "progress", title = "Boar Trouble", label = "Bristleback Quilboar slain", have = 4,
            need = 10 }, shown[2])
    end)

    it("updates one objective in place instead of stacking it", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 2/4")
        local row = module.ui.active[1]
        env:Advance(1)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 3/4")
        assert.equals(1, #module.ui.active)
        assert.equals(row, module.ui.active[1])
        assert.equals("3", row.value:GetText())
        assert.equals("2", row.valueOld:GetText())
        assert.equals(1, row.rollIn:GetPlayCount())
        assert.equals(1, row.rollOut:GetPlayCount())
    end)

    it("grows the bar in one motion from where it is, never to the new length first", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 2/4")
        local fill = module.ui.active[1].fill
        near(0.25, fill.value)
        tick(env, 1)
        near(0.5, fill.value)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 3/4")
        near(0.5, fill.value)
        -- Eased out: the first frame already covers a good share of the way, so nothing waits.
        tick(env, 0.05)
        assert.is_true(fill.value > 0.55, tostring(fill.value))
        local last = fill.value
        for _ = 1, 4 do
            tick(env, 0.05)
            assert.is_true(fill.value > last and fill.value < 0.75, tostring(fill.value))
            last = fill.value
        end
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 4/4")
        near(last, fill.value)
        tick(env, 0.05)
        assert.is_true(fill.value > last)
        tick(env, 1)
        near(1, fill.value)
        assert.equals(0, env.R.Fade:Active())
    end)

    it("opens the rule under a ready banner from the middle out", function()
        local env = world()
        local module = enable(env)
        env.complete[11] = true
        env:Fire("UI_INFO_MESSAGE", OBJECTIVE, "Boar Trouble (Complete)")
        env:Advance(0.9)
        local rule = module.ui.active[1].rule
        assert.is_true(rule:IsShown())
        assert.is_true(rule.width < rule.span)
        tick(env, 1)
        assert.equals(rule.span, rule.width)
    end)

    it("leaves after its hold and hides the banner once nothing is left", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 2/4")
        env:Advance(3.5)
        assert.equals(1, #module.ui.active)
        env:Advance(2)
        assert.equals(0, #module.ui.active)
        assert.is_false(module.ui.frame:IsShown())
        assert.equals(0, env:ActiveTimers())
    end)

    it("holds the log only after an objective finishes, and turns its row into a ready banner", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 3/4")
        assert.equals(0, held(env, "QUEST_LOG_UPDATE"))
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 4/4")
        assert.equals(1, held(env, "QUEST_LOG_UPDATE"))
        local row = module.ui.active[1]
        assert.is_true(row.entry.done)
        env.complete[10] = true
        env:Fire("QUEST_LOG_UPDATE")
        assert.equals(0, held(env, "QUEST_LOG_UPDATE"))
        assert.equals("progress", module.ui.active[1].entry.kind)
        env:Advance(0.9)
        assert.same({ { kind = "ready", title = "Tiger Hunt", label = "Ready to turn in" } }, rows(module))
        assert.equals(row, module.ui.active[1])
    end)

    it("stops holding the log when the quest is not finished by then", function()
        local env = world()
        enable(env)
        env:Fire("UI_INFO_MESSAGE", KILL, "Bristleback Quilboar slain: 10/10")
        assert.equals(1, held(env, "QUEST_LOG_UPDATE"))
        env:Advance(3.1)
        assert.equals(0, held(env, "QUEST_LOG_UPDATE"))
    end)

    it("reads a quest title in a completion line as that quest being ready", function()
        local env = world()
        local module = enable(env)
        env.complete[11] = true
        env:Fire("UI_INFO_MESSAGE", OBJECTIVE, "Boar Trouble (Complete)")
        env:Advance(0.9)
        assert.same({ { kind = "ready", title = "Boar Trouble", label = "Ready to turn in" } }, rows(module))
    end)

    it("shows a completed objective without a count as done", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", OBJECTIVE, "Scout the camp (Complete)")
        assert.same({ { kind = "progress", title = "Boar Trouble", label = "Scout the camp" } }, rows(module))
        assert.is_true(module.ui.active[1].entry.done)
        assert.is_false(module.ui.active[1].track:IsShown())
        env:Advance(5.5)
        env:Fire("UI_INFO_MESSAGE", UNKNOWN, "Objective Complete.")
        assert.same({ { kind = "progress", label = "Objective Complete." } }, rows(module))
    end)

    it("says a finished quest is complete once, whichever line comes first", function()
        local env = world()
        local module = enable(env)
        env.complete[10] = true
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 4/4")
        env:Fire("UI_INFO_MESSAGE", UNKNOWN, "Objective Complete.")
        assert.same({ ITEM + 1000, UNKNOWN + 1000 }, env.sounds)
        env:Advance(0.9)
        assert.same({ { kind = "ready", title = "Tiger Hunt", label = "Ready to turn in" } }, rows(module))

        env = world()
        module = enable(env)
        env.complete[10] = true
        env:Fire("UI_INFO_MESSAGE", UNKNOWN, "Objective Complete.")
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 4/4")
        assert.equals(2, #module.ui.active)
        env:Advance(0.9)
        env:Advance(1.1)
        assert.same({ { kind = "ready", title = "Tiger Hunt", label = "Ready to turn in" } }, rows(module))
    end)

    it("shows a hand-in as a banner with the quest's name", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", TURNIN, "Tiger Hunt completed.")
        assert.same({ { kind = "turnin", title = "Tiger Hunt", label = "Quest complete" } }, rows(module))
    end)

    it("still shows a line it cannot read back, word for word", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Something else entirely")
        assert.same({ { kind = "progress", label = "Something else entirely" } }, rows(module))
    end)

    it("reads positional formats", function()
        local env = world({ item = "%2$d/%3$d : %1$s" })
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "3/4 : Durotar Tiger Fur")
        assert.same({ { kind = "progress", title = "Tiger Hunt", label = "Durotar Tiger Fur", have = 3, need = 4 } },
            rows(module))
    end)

    it("shows nothing while Blizzard holds its messages back", function()
        local env = world()
        local module = enable(env)
        env.UIErrorsFrame.suppressed = true
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 3/4")
        assert.same({}, rows(module))
        assert.same({}, env.sounds)
    end)

    it("never shows more than its pool of rows, newest on top", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 3/4")
        env:Fire("UI_INFO_MESSAGE", KILL, "Bristleback Quilboar slain: 4/10")
        env:Fire("UI_INFO_MESSAGE", FOUND, "Scout the camp: 0/1")
        env:Fire("UI_INFO_MESSAGE", TURNIN, "Fur for the Shaman completed.")
        local shown = rows(module)
        assert.equals(env.R.UI.QUEST_BANNER_ROWS, #shown)
        assert.equals("Fur for the Shaman", shown[1].title)
        assert.equals("Bristleback Quilboar slain", shown[3].label)
    end)

    it("plays the test sequence from the log", function()
        local env = world()
        local module = enable(env)
        env.R.Broker:Emit("REFACTOR_QUEST_BANNER_TEST")
        assert.same({ { kind = "progress", title = "Tiger Hunt", label = "Durotar Tiger Fur", have = 1, need = 4 } },
            rows(module))
        env:Advance(2.5)
        assert.equals(4, module.ui.active[1].entry.have)
        env:Advance(1)
        assert.equals("ready", module.ui.active[1].entry.kind)
        env:Advance(7)
        assert.equals("turnin", module.ui.active[1].entry.kind)
        assert.equals("Showing quest progress for Tiger Hunt.", env.messages[1])
    end)

    it("steps down under the level-up toast at once and back up only once it is empty", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", TURNIN, "Tiger Hunt completed.")
        env:Fire("PLAYER_LEVEL_UP", 8)
        assert.is_true(module.ui.lowered)
        env:Advance(7.6)
        assert.equals(0, #module.ui.active)
        assert.is_false(module.ui.lowered)
        env:Fire("PLAYER_LEVEL_UP", 9)
        env:Advance(6)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 3/4")
        env:Advance(1.6)
        assert.equals(1, #module.ui.active)
        assert.is_true(module.ui.lowered)
        env:Advance(3.5)
        assert.equals(0, #module.ui.active)
        assert.is_false(module.ui.lowered)
    end)

    it("leaves no residue across enable, disable, enable", function()
        local env = world()
        local module = enable(env)
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 4/4")
        env.R.Registry:Disable(ID)
        assert.equals(0, env.R.Fade:Active())
        assert.equals(0, #module.ui.active)
        assert.is_false(module.ui.frame:IsShown())
        assert.equals(0, env:ActiveTimers())
        for event, entries in pairs(env.R.Broker.events) do
            for _, entry in ipairs(entries) do
                assert.are_not.equal(module, entry.owner, event)
            end
        end
        local ui = module.ui
        assert.is_true(env.R.Registry:Enable(ID))
        assert.equals(ui, module.ui)
        assert.is_false(ui.lowered)
        assert.is_true(env.UIErrorsFrame.blocked[ITEM])
        env:Fire("UI_INFO_MESSAGE", ITEM, "Durotar Tiger Fur: 3/4")
        assert.equals(1, #module.ui.active)
    end)
end)
