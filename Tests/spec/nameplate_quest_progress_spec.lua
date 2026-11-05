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
    env.offQuests, env.secrets, env.grouped = {}, {}, false
    env.C_QuestLog = {
        UnitIsRelatedToActiveQuest = function() return env.related end,
        GetQuestObjectives = function(questID) return env.objectives[questID] end,
        IsOnQuest = function(questID) return env.offQuests[questID] ~= true end,
    }
    env.IsInGroup = function() return env.grouped end
    env.issecretvalue = function(value) return env.secrets[value] == true end
    env.C_TooltipInfo = { GetUnit = function(unit) return env.tooltips[unit] end }
    -- Deliberately no namePlateUnitToken on the plate: the real client does not set one.
    env.C_NamePlate = { GetNamePlateForUnit = function(unit) return env.plates[unit] end }
    env.UnitGUID = function(unit) return env.guids and env.guids[unit] end
    env.guids = {}
    -- A group tooltip heads each player's objectives with their name, the player's own too.
    -- Forever's UnitName gives the surname as a second value; env.surname plays that.
    env.UnitName = function(unit)
        if unit == "player" then return "Me", env.surname end
        return nil
    end
    env:Load("Integrations/Questie.lua")
    env:Load("Integrations/Plater.lua")
    env:Load("Modules_LoD/Nameplates/QuestProgress_Data.lua")
    env.R.QuestData:SetPlayerNames("Me", nil)
    return env
end

local function player(name)
    return { type = LINE.QuestPlayer, leftText = name }
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

    -- Seen on Forever: a Rot Hide Graverobber at 8/8 slain still drops Embalming Ichor. The
    -- finished kill ranked highest, the plate read complete and faded out.
    it("shows an open objective over a finished one on the same mob", function()
        local env = base()
        env.objectives[201] = { { type = "monster" }, { type = "item" } }
        env.tooltips.target = { lines = {
            title(201, "Graverobbers"),
            objective("8/8 Rot Hide Graverobber slain", 8, 8, true), objective("3/8 Embalming Ichor", 3, 8, false),
        } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.is_true(out.ok)
        assert.equal(3, out.fulfilled)
        assert.equal(8, out.required)
        assert.is_false(out.complete)
        assert.equal("item", out.kind)
        assert.equal(0, out.plus)
        -- With everything finished the plate still says so.
        env.tooltips.target = { lines = {
            title(201, "Graverobbers"),
            objective("8/8 Rot Hide Graverobber slain", 8, 8, true), objective("8/8 Embalming Ichor", 8, 8, true),
        } }
        out = env.R.QuestData:Resolve("target", out)
        assert.is_true(out.complete)
        assert.equal(0, out.plus)
    end)

    -- Seen on Forever: a Rot Hide Gnoll drops Embalming Ichor but is not the kill target, so
    -- its tooltip lists only the Ichor line. By position that read the quest's first
    -- objective, the kill, and the plate showed a sword on a loot objective.
    it("finds the objective's kind by its text, not its place in the tooltip", function()
        local env = base()
        env.objectives[201] = {
            { type = "monster", text = "8/8 Rot Hide Graverobber slain", numFulfilled = 8, numRequired = 8 },
            { type = "item", text = "7/8 Embalming Ichor", numFulfilled = 7, numRequired = 8 },
        }
        env.tooltips.target = { lines = { title(201, "Graverobbers"), objective("7/8 Embalming Ichor", 7, 8, false) } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.equal(7, out.fulfilled)
        assert.equal("item", out.kind)
        -- Worded differently from the log, the counts still find it.
        env.tooltips.target = { lines = { title(201, "Graverobbers"), objective("Embalming Ichor: 7/8", 7, 8, false) } }
        out = env.R.QuestData:Resolve("target", out)
        assert.equal("item", out.kind)
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

    -- The live client puts every player under their own name in a group, the player too, and
    -- a party member's objective lines carry real counts. Those once counted as a second match
    -- and, being further along, replaced the player's own number.
    it("reads only the player's own section when grouped", function()
        local env = base()
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.target = { lines = {
            title(101, "Culling"),
            { type = LINE.QuestPlayer, leftText = "Me" }, objective("2/6 slain", 2, 6),
            { type = LINE.QuestPlayer, leftText = "Friend" }, objective("5/6 slain", 5, 6),
        } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.equal(2, out.fulfilled)
        assert.equal(0, out.plus)
        assert.is_false(out.lastOne)
        -- A party member listed first does not hide the player's own section after it.
        env.tooltips.target = { lines = {
            title(101, "Culling"),
            { type = LINE.QuestPlayer, leftText = "Friend" }, objective("5/6 slain", 5, 6),
            { type = LINE.QuestPlayer, leftText = "Me" }, objective("2/6 slain", 2, 6),
        } }
        out = env.R.QuestData:Resolve("target", out)
        assert.equal(2, out.fulfilled)
        assert.equal(0, out.plus)
        assert.equal("kill", out.kind)
    end)

    -- Seen on Forever, 5 Nov 2026, in a party of four: the tooltip heads the player's own
    -- section "Profet Ashbringer", name and surname, while UnitName's first value is "Profet".
    -- Read as someone else's section, the player's 1/12 was dropped and the plate stayed blank
    -- on every quest a party member shared. Rascally Rodents is not in the player's log.
    it("reads the player's own section when the tooltip writes name and surname", function()
        local env = base()
        env.grouped = true
        env.R.QuestData:SetPlayerNames("Profet", "Profet Ashbringer")
        env.objectives[301] = { { type = "monster", text = "1/12 Kobold Laborer slain" } }
        env.offQuests[302] = true
        env.tooltips.target = { lines = {
            { type = LINE.UnitName, leftText = "Kobold Laborer" },
            title(301, "Skirmish at Echo Ridge"),
            player("Profet Ashbringer"), objective("1/12 Kobold Laborer slain", 1, 12),
            player("Azhue Azhue"), objective("2/12 Kobold Laborer slain", 2, 12),
            player("Ghost Type"), objective("5/12 Kobold Laborer slain", 5, 12),
            title(302, "Rascally Rodents"),
            player("Goobie Patootie"), objective("2/8 Stolen Book", 2, 8),
            player("Ghost Type"), objective("7/8 Stolen Book", 7, 8),
        } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.is_true(out.ok)
        assert.equal(1, out.fulfilled)
        assert.equal(12, out.required)
        assert.equal(0, out.plus)
        assert.equal("kill", out.kind)
    end)

    it("knows the player's lines by their quest log text when no name matches", function()
        local env = base()
        env.grouped = true
        env.R.QuestData:SetPlayerNames("Someone", nil)
        env.objectives[301] = { { type = "monster", text = "1/12 Kobold Laborer slain" } }
        env.tooltips.target = { lines = {
            title(301, "Skirmish"),
            player("Friend"), objective("5/12 Kobold Laborer slain", 5, 12),
            player("Unknown Format"), objective("1/12 Kobold Laborer slain", 1, 12),
            -- A party member exactly as far along: same numbers, and still one objective.
            player("Twin"), objective("1/12 Kobold Laborer slain", 1, 12),
        } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.equal(1, out.fulfilled)
        assert.equal(0, out.plus)
        assert.equal("kill", out.kind)
        -- Nothing of the player's at all: a party member's numbers are never shown instead.
        env.objectives[301] = { { type = "monster", text = "0/12 Kobold Laborer slain" } }
        out = env.R.QuestData:Resolve("target", out)
        assert.is_false(out.ok)
    end)

    it("ignores a bare quest block in a group unless the quest is the player's", function()
        local env = base()
        env.grouped = true
        env.offQuests[302] = true
        env.tooltips.target = { lines = { title(302, "Rascally Rodents"), objective("2/8 Stolen Book", 2, 8) } }
        local out = env.R.QuestData:Resolve("target", {})
        assert.is_false(out.ok)
        -- Solo every line is the player's, even for a quest the log does not call "on", the
        -- way a bonus objective can read.
        env.grouped = false
        out = env.R.QuestData:Resolve("target", out)
        assert.is_true(out.ok)
        assert.equal(2, out.fulfilled)
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

    it("shows the count of other objectives only when the player asks for it", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.objectives[102] = { { type = "item" } }
        env.tooltips.nameplate1 = { lines = {
            title(101, "Culling"), objective("3/8 slain", 3, 8),
            title(102, "Pelts"), objective("1/10 Pelts", 1, 10),
        } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        assert.is_false(env.R.Settings:GetOption("nameplateShowMore"))
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.equal("3/8", module.shown.nameplate1.value:GetText() .. module.shown.nameplate1.total:GetText())

        assert.is_true(env.R.Settings:SetOption("nameplateShowMore", true))
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.equal("3/8 +1", module.shown.nameplate1.value:GetText() .. module.shown.nameplate1.total:GetText())
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
        assert.is_true(module.dimmed.nameplate1:IsShown())

        -- Any later quest log update leaves the finished plate dimmed and quiet, rather than
        -- playing the checkmark again.
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.is_nil(module.shown.nameplate1)
        assert.is_true(module.dimmed.nameplate1:IsShown())
    end)

    it("dims a mob already finished when its plate appears, with no checkmark", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("8/8", 8, 8, true) } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.is_nil(module.shown.nameplate1)
        assert.is_true(module.dimmed.nameplate1:IsShown())
        env.R.Settings:SetOption("nameplateDimCompleted", false)
        env:Advance(0.1)
        assert.is_nil(module.dimmed.nameplate1)
    end)

    it("resolves a plate whose GUID is missing or secret, without caching it", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = { title(101, "Culling"), objective("3/8 slain", 3, 8) } }
        env.tooltips.nameplate2 = env.tooltips.nameplate1
        addPlate(env, "nameplate1", nil)
        addPlate(env, "nameplate2", "SecretGUID")
        env.secrets.SecretGUID = true
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        env:Advance(0.1)
        assert.equal("3", module.shown.nameplate1.value:GetText())
        assert.equal("3", module.shown.nameplate2.value:GetText())
        assert.is_nil(next(env.R.QuestData.cache))
    end)

    it("keeps every other plate going when one cannot be read", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.tooltips.nameplate2 = { lines = { title(101, "Culling"), objective("3/8 slain", 3, 8) } }
        local getUnit = env.C_TooltipInfo.GetUnit
        env.C_TooltipInfo.GetUnit = function(unit)
            if unit == "nameplate1" then error("secret value") end
            return getUnit(unit)
        end
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-11111-002FAC4343")
        addPlate(env, "nameplate2", "Creature-0-3061-1-42177-38038-002FAC4344")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        env:Advance(0.1)
        assert.equal("enabled", module.state)
        assert.is_nil(module.shown.nameplate1)
        assert.equal("3", module.shown.nameplate2.value:GetText())
        assert.equal(1, #env.R.errors)
        assert.matches("secret value", env.R.errors[1].message)
        -- Later plates still resolve: the queue never stalls on the failure.
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(0.5)
        assert.equal("3", module.shown.nameplate2.value:GetText())
        assert.equal(1, #env.R.errors)
    end)

    it("applies a changed setting to the plates already up", function()
        local env = base()
        local module = withModule(env)
        env.objectives[101] = { { type = "monster" } }
        env.objectives[102] = { { type = "item" } }
        env.tooltips.nameplate1 = { lines = {
            title(101, "Culling"), objective("3/8 slain", 3, 8),
            title(102, "Pelts"), objective("1/10 Pelts", 1, 10),
        } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.equal("/8", module.shown.nameplate1.total:GetText())
        env.R.Settings:SetOption("nameplateShowMore", true)
        env:Advance(0.1)
        assert.equal("/8 +1", module.shown.nameplate1.total:GetText())
    end)

    it("reads the player's section by full name once enabled on Forever", function()
        local env = base()
        env.surname = "Ashbringer"
        env.grouped = true
        local module = withModule(env)
        env.objectives[301] = { { type = "monster" } }
        env.tooltips.nameplate1 = { lines = {
            title(301, "Skirmish"),
            player("Ghost Type"), objective("Kobold Laborer slain: 5/12", 5, 12),
            player("Me Ashbringer"), objective("Kobold Laborer slain: 1/12", 1, 12),
        } }
        addPlate(env, "nameplate1", "Creature-0-3061-1-42177-38038-002FAC4343")
        env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env:Advance(0.1)
        assert.equal("1", module.shown.nameplate1.value:GetText())
        env.R.Registry:Disable(module)
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
