local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local LINE = { UnitName = 2, QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }

local function title(questID, text)
    return { type = LINE.QuestTitle, id = questID, leftText = text }
end

local function objective(text, fulfilled, required, completed)
    return {
        type = LINE.QuestObjective, leftText = text,
        numFulfilled = fulfilled, numRequired = required, completed = completed,
    }
end

local function base()
    local env = Runtime.new()
    Widgets.install(env)
    env:Load("Locales/Nameplates.enUS.lua")
    env.Enum = { TooltipDataLineType = LINE }
    env.tooltips, env.objectives, env.plates, env.related = {}, {}, {}, true
    env.C_QuestLog = {
        UnitIsRelatedToActiveQuest = function() return env.related end,
        GetQuestObjectives = function(questID) return env.objectives[questID] end,
    }
    env.C_TooltipInfo = { GetUnit = function(unit) return env.tooltips[unit] end }
    -- Deliberately no namePlateUnitToken on the plate: the real client does not set one.
    env.C_NamePlate = { GetNamePlateForUnit = function(unit) return env.plates[unit] end }
    env.UnitGUID = function(unit) return env.guids and env.guids[unit] end
    env.guids = {}
    env:Load("Integrations/Questie.lua")
    env:Load("Integrations/Plater.lua")
    env:Load("Modules_LoD/Nameplates/QuestProgress_Data.lua")
    return env
end

local function withModule(env)
    env:Load("Modules_LoD/Nameplates/QuestProgress.lua")
    local module = env.R.moduleByID["nameplates.questProgress"]
    assert.is_true(env.R.Registry:Enable(module))
    return module
end

local function addPlate(env, unit, guid)
    env.plates[unit] = env.CreateFrame("Frame")
    env.plates[unit].UnitFrame = env.CreateFrame("Frame")
    env.plates[unit].UnitFrame.HealthBarsContainer = env.CreateFrame("Frame")
    env.guids[unit] = guid
end

describe("quest progress resolution", function()
    it("parses counts, percentages and rejects text with no numbers", function()
        local env = base()
        local Data = env.R.QuestData
        assert.same({ 3, 8 }, { Data:ParseObjective("3/8 Gnolls slain") })
        assert.same({ 3, 8 }, { Data:ParseObjective("Gnolls slain: 3 / 8") })
        assert.same({ 45, 100 }, { Data:ParseObjective("45% Complete") })
        assert.is_nil(Data:ParseObjective("Speak with the innkeeper"))
        assert.is_nil(Data:ParseObjective(nil))
    end)

    it("reads an NPC id only from a creature guid", function()
        local Data = base().R.QuestData
        assert.equal(38038, Data:NPCID("Creature-0-3061-1-42177-38038-002FAC4343"))
        assert.is_nil(Data:NPCID("Player-3661-0A5C1D24"))
        assert.is_nil(Data:NPCID("Pet-0-3061-1-42177-38038-012FAC4343"))
        assert.is_nil(Data:NPCID(nil))
    end)

    it("stops at once when the unit serves no active quest", function()
        local env = base()
        env.related = false
        env.tooltips.target = { lines = { objective("0/6 slain", 0, 6) } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.is_false(out.ok)
    end)

    it("picks the objective closest to completion and counts the rest", function()
        local env = base()
        env.objectives[101] = { { type = "monster" } }
        env.objectives[102] = { { type = "item" } }
        env.tooltips.target = { lines = {
            { type = LINE.UnitName, leftText = "Gnoll" },
            title(101, "Culling the Pack"), objective("1/8 Gnolls slain", 1, 8),
            title(102, "Gnoll Pelts"), objective("7/10 Pelts", 7, 10),
        } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.is_true(out.ok)
        assert.equal(7, out.fulfilled)
        assert.equal(10, out.required)
        assert.equal(1, out.plus)
        assert.equal("item", out.kind)
        assert.is_false(out.lastOne)
    end)

    it("flags the last one needed and a completed objective", function()
        local env = base()
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.target = { lines = { title(101, "Culling"), objective("5/6 slain", 5, 6) } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.is_true(out.lastOne)
        assert.is_false(out.complete)
        env.tooltips.target = { lines = { title(101, "Culling"), objective("6/6 slain", 6, 6, true) } }
        out = env.R.QuestData:Resolve("target", {})
        assert.is_true(out.complete)
        assert.is_false(out.lastOne)
    end)

    it("never takes numbers from another player's section of the tooltip", function()
        local env = base()
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.target = { lines = {
            title(101, "Culling"), objective("2/6 slain", 2, 6),
            { type = LINE.QuestPlayer, leftText = "Someone Else" },
            -- No count fields, so only the text parser could reach these numbers.
            { type = LINE.QuestObjective, leftText = "5/6 slain" },
        } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.equal(2, out.fulfilled)
        assert.equal(0, out.plus)
    end)

    it("falls back to parsing only when the line carries no numbers", function()
        local env = base()
        env.tooltips.target = { lines = {
            title(nil, "Unknown quest"), { type = LINE.QuestObjective, leftText = "40% Complete" },
        } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.equal(40, out.fulfilled)
        assert.equal(100, out.required)
        assert.equal("other", out.kind)
    end)

    it("reuses one result table across resolves", function()
        local env = base()
        local out = {}
        env.tooltips.target = { lines = { title(1, "q"), objective("1/2", 1, 2) } }
        assert.equal(out, env.R.QuestData:Resolve("target", out))
    end)
end)

describe("quest progress module", function()
    it("shows the count on a plate and caches by npc id", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("3/8 slain", 3, 8) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.equal("3/8", (module.shown.nameplate1.value:GetText() .. module.shown.nameplate1.total:GetText()))
        assert.is_table(env.R.QuestData:Get(38038))
    end)

    it("clears a recycled indicator instead of showing the previous unit's numbers", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("3/8 slain", 3, 8) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        local indicator = module.shown.nameplate1
        env:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        assert.is_nil(module.shown.nameplate1)
        assert.equal("", indicator.value:GetText() .. indicator.total:GetText())
        assert.is_false(indicator:IsShown())

        env.tooltips.nameplate2 = { lines = { title(101, "Culling"), objective("1/8 slain", 1, 8) } }
        addPlate(env, "nameplate2", "Creature-0-3061-1-42177-55555-002FAC4344")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        env:Advance(0.1)
        assert.equal(indicator, module.shown.nameplate2)
        assert.equal("1/8", indicator.value:GetText() .. indicator.total:GetText())
    end)

    it("redraws visible plates after a quest update, not just the cache", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("3/8 slain", 3, 8) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.equal("3/8", (module.shown.nameplate1.value:GetText() .. module.shown.nameplate1.total:GetText()))

        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("4/8 slain", 4, 8) } }
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.equal("4/8", (module.shown.nameplate1.value:GetText() .. module.shown.nameplate1.total:GetText()))
    end)

    it("hides the indicator when the mob stops counting", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("3/8 slain", 3, 8) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        env.related = false
        env.tooltips.nameplate1 = { lines = {} }
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.is_nil(module.shown.nameplate1)
    end)

    it("stands down completely when a neighbour owns nameplates", function()
        local env = base()
        env.C_AddOns = { IsAddOnLoaded = function(name) return name == "Plater" end }
        env:Load("Modules_LoD/Nameplates/QuestProgress.lua")
        local module = env.R.moduleByID["nameplates.questProgress"]
        env.R.Registry:Enable(module)
        assert.equal("unavailable", module.state)
        assert.matches("Plater", module.unavailableReason)
        assert.is_nil(env.R.Broker.events.NAME_PLATE_UNIT_ADDED)
    end)

    it("redraws plates the player never touched, not only the one that changed", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        local function lines(fulfilled)
            return { lines = { title(101, "Culling"), objective("x", fulfilled, 8) } }
        end
        env.tooltips.nameplate1, env.tooltips.nameplate2 = lines(3), lines(3)
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        addPlate(env, "nameplate2", "Creature-0-3061-1-42177-38038-002FAC4344")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        env:Advance(0.1)
        assert.equal("3/8", (module.shown.nameplate2.value:GetText() .. module.shown.nameplate2.total:GetText()))

        env.tooltips.nameplate1, env.tooltips.nameplate2 = lines(4), lines(4)
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.equal("4/8", (module.shown.nameplate1.value:GetText() .. module.shown.nameplate1.total:GetText()))
        assert.equal("4/8", (module.shown.nameplate2.value:GetText() .. module.shown.nameplate2.total:GetText()))
    end)

    it("colors the count gold on the last mob and shows checkmark on complete", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("4/8", 4, 8) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        local indicator = module.shown.nameplate1
        assert.equal("4", indicator.value:GetText())
        assert.equal("/8", indicator.total:GetText())

        -- The last one needed updates the text count.
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("7/8", 7, 8) } }
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.equal("7", indicator.value:GetText())

        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("8/8", 8, 8, true) } }
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.equal("8", indicator.value:GetText())
        assert.is_true(indicator.check:IsShown())
        assert.is_false(indicator.icon:IsShown())
    end)

    it("shows the bag icon for an item objective and swords for a kill", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "item" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Pelts"), objective("1/5", 1, 5) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.equal("Crosshair_buy_48", module.shown.nameplate1.icon.atlas)
        assert.equal(16, module.shown.nameplate1.value.fontSize)
        assert.equal("OUTLINE", module.shown.nameplate1.value.fontFlags)

        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("1/5", 1, 5) } }
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.equal("Crosshair_Attack_48", module.shown.nameplate1.icon.atlas)
    end)

    it("animates a real progress change and never the first sighting", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("3/8 slain", 3, 8) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        local indicator = module.shown.nameplate1
        local plays = 0
        indicator.pop.Play = function() plays = plays + 1 end
        assert.equal(0, plays)

        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("4/8 slain", 4, 8) } }
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.equal(1, plays)

        env.R.Settings:SetOption("nameplateReduceAnimation", true)
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("5/8 slain", 5, 8) } }
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.equal(1, plays)
    end)

    it("enable, disable, enable leaves no residue", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("3/8 slain", 3, 8) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.is_true(env.R.Registry:Disable(module))
        assert.equal(0, env:ActiveTimers())
        for _, entries in pairs(env.R.Broker.events) do
            for _, entry in ipairs(entries) do
                assert.is_not.equal(module, entry.owner)
            end
        end
        assert.is_nil(env.R.QuestData:Get(38038))
        assert.is_true(env.R.Registry:Enable(module))
        assert.equal("enabled", module.state)
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.equal("3/8", (module.shown.nameplate1.value:GetText() .. module.shown.nameplate1.total:GetText()))
    end)

    it("anchors to whichever level element the plate shows, else the bar background", function()
        local env = base()
        local module = withModule(env)
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        local plate = env.plates.nameplate1
        local unitFrame = plate.UnitFrame
        local container = unitFrame.HealthBarsContainer
        assert.equal(container, module:AnchorFor(plate))
        container.healthBar = env.CreateFrame("Frame")
        container.healthBar.bgTexture = env.CreateFrame("Frame")
        assert.equal(container.healthBar.bgTexture, module:AnchorFor(plate))
        unitFrame.PlayerLevelDiffFrame = env.CreateFrame("Frame")
        unitFrame.LevelFrame = env.CreateFrame("Frame")
        unitFrame.PlayerLevelDiffFrame:Hide()
        unitFrame.LevelFrame:Hide()
        assert.equal(container.healthBar.bgTexture, module:AnchorFor(plate))
        unitFrame.PlayerLevelDiffFrame:Show()
        assert.equal(unitFrame.PlayerLevelDiffFrame, module:AnchorFor(plate))
        unitFrame.LevelFrame:Show()
        assert.equal(unitFrame.LevelFrame, module:AnchorFor(plate))
    end)
end)
