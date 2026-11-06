local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local ID = "items.professionPlanner"
local DIFFICULTY = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 }

-- The client's own colour for a recipe, from where it really turns yellow and grey.
local function trueColour(low, high, skill)
    if skill >= high then return DIFFICULTY.Trivial end
    if skill < low then return DIFFICULTY.Optimal end
    if skill < math.floor((low + high) / 2) then return DIFFICULTY.Medium end
    return DIFFICULTY.Easy
end

-- 101 and 102 are in the stand-in table; 103 is not, so it is learned from what the window shows; 104 is not
-- learned yet. Thresholds here are the truth the client colours by.
local function recipes()
    return {
        [101] = { name = "Bolt", low = 50, high = 60, learned = true, reagents = { { 201, 2 } } },
        [102] = { name = "Shirt", low = 20, high = 100, learned = true, reagents = { { 202, 1 }, { 201, 1 } } },
        [103] = { name = "Mystery", low = 40, high = 70, learned = true, reagents = { { 203, 1 } } },
        [104] = { name = "Cloak", low = 110, high = 140, learned = false, reagents = { { 204, 3 } } },
    }
end

local STAND_IN = { build = "test", lines = { [171] = { "101,50,60;102,20,100;104,110,140" } } }

local function world(options)
    options = options or {}
    local env = Runtime.new()
    Widgets.install(env)
    for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Professions.enUS.lua" }) do
        env:Load(path)
    end
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    local Frame = getmetatable(env.CreateFrame("Frame"))
    Frame.SetDesaturated = function(self, value) self.desaturated = value end
    env.UIParent = { name = "UIParent" }
    env.GameTooltip = {
        SetOwner = function(_, owner) env.tipOwner = owner end,
        AddLine = function(_, text) env.tipLines[#env.tipLines + 1] = text end,
        Show = function() end, Hide = function() env.tipOwner = nil end,
        IsOwned = function(_, frame) return env.tipOwner == frame end,
    }
    env.tipLines = {}
    env.Enum = { TradeskillRelativeDifficulty = DIFFICULTY, CraftingReagentType = { Basic = 1, Finishing = 2 } }
    env.shift = false
    env.IsShiftKeyDown = function() return env.shift end
    env.ChatEdit_InsertLink = function(link) env.chatLink = link end

    env.shape = options.shape or "child"
    env.GetProfessions = function() return nil, 3, nil, nil, 7 end
    env.GetProfessionInfo = function(index)
        if index == 7 then return "Cooking", 1, 12, 75, 0, 0, 185 end
        if env.shape ~= "spellbook" then return "Tailoring", 1, 0, 0, 0, 0, 0 end
        return "Tailoring", 1, env.profession.skill, env.profession.cap, 0, 0, 197
    end
    env.recipes = options.recipes or recipes()
    env.profession = { skill = options.skill or 30, cap = options.cap or 150 }
    env.ready, env.linked, env.bags, env.craftable = true, false, options.bags or {}, {}
    local function ids()
        local list = {}
        for id in pairs(env.recipes) do list[#list + 1] = id end
        table.sort(list)
        return list
    end
    env.C_TradeSkillUI = {
        IsTradeSkillReady = function() return env.ready end,
        IsTradeSkillLinked = function() return env.linked end,
        IsTradeSkillGuild = function() return false end,
        IsNPCCrafting = function() return false end,
        -- Retail answers on the child line. Forever answers it with an empty profession (6 Nov 2026), and
        -- options.shape says which of the other sources does answer there.
        GetChildProfessionInfo = function()
            if env.shape ~= "child" then return { professionID = 0, skillLevel = 0, maxSkillLevel = 0 } end
            return { professionID = 2937, professionName = "Tailoring", skillLevel = env.profession.skill,
                maxSkillLevel = env.profession.cap, parentProfessionID = 171 }
        end,
        GetBaseProfessionInfo = function()
            if env.shape == "base" then
                return { professionID = 171, professionName = "Tailoring", skillLevel = env.profession.skill,
                    maxSkillLevel = env.profession.cap }
            end
            if env.shape == "child" then return { professionID = 171 } end
            return { professionID = 0, professionName = "Tailoring", skillLevel = 0, maxSkillLevel = 0 }
        end,
        GetProfessionInfoByRecipeID = function()
            if env.shape ~= "recipe" then return { professionID = 0, skillLevel = 0, maxSkillLevel = 0 } end
            return { professionID = 171, professionName = "Tailoring", skillLevel = env.profession.skill,
                maxSkillLevel = env.profession.cap }
        end,
        GetAllRecipeIDs = ids,
        IsRecipeInSkillLine = function(_, line) return line == 2937 end,
        GetRecipeInfo = function(id)
            local recipe = env.recipes[id]
            if not recipe then return nil end
            local high = recipe.liveHigh or recipe.high
            return { recipeID = id, name = recipe.name, icon = 300 + id, maxTrivialLevel = high,
                relativeDifficulty = trueColour(recipe.low, high, env.profession.skill),
                numSkillUps = recipe.skillUps or 1, learned = recipe.learned }
        end,
        GetRecipeSchematic = function(id)
            local slots = {}
            for index, reagent in ipairs(env.recipes[id].reagents) do
                slots[index] = { reagentType = 1, quantityRequired = reagent[2],
                    reagents = { { itemID = reagent[1] } } }
            end
            slots[#slots + 1] = { reagentType = 2, quantityRequired = 1, reagents = { { itemID = 999 } } }
            return { reagentSlotSchematics = slots }
        end,
        GetCraftableCount = function(id) return env.craftable[id] or 0 end,
        GetRecipeSourceText = function() return "Trainer" end,
        GetRecipeLink = function(id) return "recipe:" .. id end,
        OpenRecipe = function(id) env.opened = id end,
    }
    env.C_Item = {
        GetItemCount = function(id) return env.bags[id] or 0 end,
        GetItemInfo = function(id) return "Item " .. id, "item:" .. id end,
        GetItemIconByID = function(id) return 500 + id end,
        GetItemNameByID = function(id) return "Item " .. id end,
    }
    -- A window whose right edge is at 700. Its children are whatever a test puts in env.edgeFrames.
    env.edgeFrames = {}
    env.ProfessionsFrame = {
        shown = false,
        GetFrameLevel = function() return 10 end, GetFrameStrata = function() return "HIGH" end,
        IsShown = function(self) return self.shown end,
        GetRight = function() return 700 end,
        GetChildren = function() return unpack(env.edgeFrames) end,
    }
    function env:OpenWindow()
        self.ProfessionsFrame.shown = true
        self:Fire("TRADE_SKILL_SHOW")
        self:Advance(0.5)
    end
    function env:CloseWindow()
        self.ProfessionsFrame.shown = false
        self:Fire("TRADE_SKILL_CLOSE")
    end
    function env:SetSkill(skill)
        self.profession.skill = skill
        self:Fire("SKILL_LINES_CHANGED")
        self:Advance(0.5)
    end

    env.R.UI = env.R.UI or {}
    if options.realTable then env:Load("Data/ProfessionThresholds.lua") else env.R.ProfessionThresholds = STAND_IN end
    env:Load("UI/ProfessionPlanner.lua")
    env:Load("Modules/Items/ProfessionPlanner.lua")
    local module = env.R.moduleByID[ID]
    assert.is_true(env.R.Registry:Enable(ID), tostring(module.failure) .. " "
        .. table.concat(module.missing or {}, ","))
    assert.equal("enabled", module.state)
    return env, module
end

local function recipeIDs(plan)
    local list = {}
    for index, step in ipairs(plan.steps) do list[index] = step.recipe.id end
    return list
end

local function entry(low, high, cost, gain)
    return { low = low, high = high, cost = cost or 1, gain = gain or 1 }
end

describe("profession planner", function()
    local Planner
    setup(function()
        local env = world()
        Planner = env.R.moduleByID[ID]
    end)

    describe("colours and chances", function()
        it("splits a recipe into orange, yellow, green and grey the way the game does", function()
            assert.equal("orange", Planner.ColourAt(55, 95, 1))
            assert.equal("orange", Planner.ColourAt(55, 95, 54))
            assert.equal("yellow", Planner.ColourAt(55, 95, 55))
            assert.equal("yellow", Planner.ColourAt(55, 95, 74))
            assert.equal("green", Planner.ColourAt(55, 95, 75))
            assert.equal("grey", Planner.ColourAt(55, 95, 95))
        end)

        it("gives a point for certain while orange and falls to nothing at grey", function()
            assert.equal(1, Planner.ChanceAt(55, 95, 10))
            assert.equal(1, Planner.ChanceAt(55, 95, 55))
            assert.equal(0.5, Planner.ChanceAt(55, 95, 75))
            assert.equal(0, Planner.ChanceAt(55, 95, 95))
            assert.equal(1, Planner.ChanceAt(60, 60, 59))
            assert.equal(0, Planner.ChanceAt(60, 60, 60))
        end)
    end)

    describe("learning a yellow level from sightings", function()
        it("narrows to the exact level from orange, then yellow", function()
            local lo, hi = Planner.Narrow(1, 70, "orange", 30, 70)
            assert.same({ 31, 70 }, { lo, hi })
            lo, hi = Planner.Narrow(lo, hi, "yellow", 45, 70)
            assert.same({ 31, 45 }, { lo, hi })
            lo, hi = Planner.Narrow(lo, hi, "orange", 39, 70)
            assert.same({ 40, 45 }, { lo, hi })
            lo, hi = Planner.Narrow(lo, hi, "yellow", 40, 70)
            assert.same({ 40, 40 }, { lo, hi })
        end)

        it("bounds the yellow level from above with a green sighting", function()
            local lo, hi = Planner.Narrow(1, 70, "green", 60, 70)
            assert.same({ 1, 51 }, { lo, hi })
        end)

        it("starts over when a sighting contradicts what was stored", function()
            local lo, hi = Planner.Narrow(50, 55, "orange", 60, 70)
            assert.same({ 61, 70 }, { lo, hi })
        end)

        it("estimates inside the allowed range", function()
            assert.equal(45, Planner.Estimate(1, 70, 70))
            assert.equal(50, Planner.Estimate(50, 60, 70))
            assert.equal(40, Planner.Estimate(31, 40, 70))
        end)
    end)

    describe("the expected-cost programme", function()
        it("counts orange crafts as one each and yellow and green ones by their chance", function()
            local plan = Planner.Solve({ entry(55, 95) }, 1, 75)
            local expected = 54
            for skill = 55, 74 do expected = expected + 40 / (95 - skill) end
            assert.equal(1, #plan.steps)
            assert.equal(75, plan.reached)
            assert.is_true(math.abs(plan.crafts - expected) < 1e-6)
            assert.is_true(math.abs(plan.total - expected) < 1e-6)
        end)

        it("switches recipe where the other one gives points more often", function()
            local bolt, shirt = entry(50, 60), entry(20, 100)
            bolt.id, shirt.id = 1, 2
            local plan = Planner.Solve({ bolt, shirt }, 30, 100)
            assert.same({ 1, 2 }, recipeIDs(plan))
            assert.equal(30, plan.steps[1].from)
            assert.equal(plan.steps[1].to, plan.steps[2].from)
            assert.equal(100, plan.steps[2].to)
            assert.is_true(plan.steps[1].to > 50 and plan.steps[1].to < 60)
        end)

        it("stops at the highest grey level when nothing known goes further", function()
            local plan = Planner.Solve({ entry(20, 60), entry(30, 80) }, 10, 150)
            assert.equal(80, plan.reached)
            assert.equal(80, plan.steps[#plan.steps].to)
        end)

        it("moves several levels a craft while a recipe gives several points", function()
            local plan = Planner.Solve({ entry(50, 60, 1, 2) }, 1, 11)
            assert.equal(1, #plan.steps)
            assert.equal(5, plan.steps[1].crafts)
            assert.equal(11, plan.steps[1].to)
        end)

        it("does not alternate between two recipes a hair apart", function()
            local plan = Planner.Solve({ entry(40, 80), entry(40, 80) }, 1, 79)
            assert.equal(1, #plan.steps)
        end)

        it("takes the cheaper recipe when planning by gold", function()
            local dear, cheap = entry(50, 60, 1000), entry(20, 100, 10)
            dear.id, cheap.id = 1, 2
            local plan = Planner.Solve({ dear, cheap }, 30, 100)
            assert.same({ 2 }, recipeIDs(plan))
        end)

        it("plans nothing at or above the cap", function()
            local plan = Planner.Solve({ entry(20, 60) }, 75, 75)
            assert.equal(0, #plan.steps)
            assert.equal(75, plan.reached)
        end)
    end)

    describe("stored sightings", function()
        it("are kept for the build they were seen on and dropped for another", function()
            local stored = { build = "b1", recipes = { [103] = { 40, 45, 70 } }, count = 1 }
            assert.same({ 40, 45, 70 }, Planner.CleanSeen(stored, "b1").recipes[103])
            assert.same({}, Planner.CleanSeen(stored, "b2").recipes)
        end)

        it("drop malformed entries", function()
            local stored = { build = "b1", recipes = { [1] = { 50, 40, 70 }, [2] = { 1, 2 }, x = { 1, 1, 1 },
                [3] = { 1, 2, 3 } } }
            assert.same({ [3] = { 1, 2, 3 } }, Planner.CleanSeen(stored, "b1").recipes)
        end)
    end)

    describe("in the profession window", function()
        it("plans from the current skill to as far as the known recipes go", function()
            local env, module = world()
            env:OpenWindow()
            local plan = module.view.plan
            assert.is_true(module.ui.panel:IsShown())
            assert.equal(30, plan.steps[1].from)
            assert.equal(101, plan.steps[1].recipe.id)
            assert.equal(100, plan.reached)
            assert.equal("crafts", plan.goal)
            assert.same({ 104 }, { plan.candidates[1].id })
            assert.equal(1, #plan.candidates)
            assert.is_true(module.ui.steps[1]:IsShown())
            assert.is_true(module.ui.candidates[1]:IsShown())
        end)

        it("plans again from wherever the skill moved, however it got there", function()
            local env, module = world()
            env:OpenWindow()
            env:SetSkill(70)
            local plan = module.view.plan
            assert.equal(70, plan.steps[1].from)
            assert.equal(102, plan.steps[1].recipe.id)
            env:SetSkill(100)
            assert.equal(0, #module.view.plan.steps)
            assert.equal(1, #module.view.plan.candidates)
        end)

        it("keeps the step's starting level so its bar fills as the player crafts", function()
            local env, module = world()
            env:OpenWindow()
            env:SetSkill(35)
            assert.equal(101, module.view.plan.steps[1].recipe.id)
            assert.equal(30, module.view.plan.steps[1].started)
        end)

        it("uses the table where it agrees with the client and learns the rest from sightings", function()
            local env, module = world()
            env:OpenWindow()
            local byID = {}
            for _, each in ipairs(module.view.data.known) do byID[each.id] = each end
            assert.equal("table", byID[101].source)
            assert.equal("estimate", byID[103].source)
            assert.same({ 31, 70, 70 }, env.R.Settings.account.professionSeen.recipes[103])
            env:SetSkill(45)
            env:SetSkill(39)
            env:SetSkill(40)
            for _, each in ipairs(module.view.data.known) do byID[each.id] = each end
            assert.equal("seen", byID[103].source)
            assert.equal(40, byID[103].low)
        end)

        it("stops trusting the table for a recipe whose grey level the client disagrees with", function()
            local list = recipes()
            list[102].liveHigh = 105
            local env, module = world({ recipes = list })
            env:OpenWindow()
            for _, each in ipairs(module.view.data.known) do
                if each.id == 102 then assert.is_not.equal("table", each.source) end
            end
        end)

        it("finds a recipe in the generated table", function()
            local list = { [2330] = { name = "Minor Healing Potion", low = 55, high = 95, learned = true,
                reagents = { { 2447, 1 } } } }
            local env, module = world({ recipes = list, realTable = true, skill = 1, cap = 75 })
            env:OpenWindow()
            assert.equal("table", module.view.data.known[1].source)
            assert.equal(55, module.view.data.known[1].low)
        end)

        it("lists the reagents for the rest of the plan against what the bags hold", function()
            local env, module = world({ bags = { [201] = 10 } })
            env:OpenWindow()
            local reagents = {}
            for _, reagent in ipairs(module.view.plan.reagents) do reagents[reagent.itemID] = reagent end
            assert.equal(10, reagents[201].have)
            assert.is_true(reagents[201].need > 10)
            assert.is_nil(reagents[999])
            assert.is_true(module.ui.reagents[1]:IsShown())
        end)

        it("plans by crafts and says why when least gold has no auction prices", function()
            local env, module = world()
            env.R.Settings:SetOption("plannerGoal", "gold")
            env:OpenWindow()
            assert.equal("crafts", module.view.plan.goal)
            assert.equal("gold", module.view.plan.requested)
            assert.equal("noAuction", module.view.plan.note)
        end)

        it("plans by gold with auction prices, and falls back when a reagent has none", function()
            local env, module = world()
            local prices = { ["item:201"] = 100, ["item:202"] = 50, ["item:203"] = 5000 }
            env.R.Price:RegisterProvider("tsm", 100, function(item) return prices[item] end)
            env.R.Price:SetEnabled("tsm", true)
            env.R.Settings:SetOption("plannerGoal", "gold")
            env:OpenWindow()
            assert.equal("gold", module.view.plan.goal)
            assert.is_nil(module.view.plan.note)
            assert.is_true(module.view.plan.total > 0)
            prices["item:202"] = nil
            env.R.Price:Invalidate()
            env:Fire("BAG_UPDATE_DELAYED")
            env:Advance(0.5)
            assert.equal("crafts", module.view.plan.goal)
            assert.equal("unpriced", module.view.plan.note)
        end)

        it("shows nothing for someone else's profession", function()
            local env, module = world()
            env.linked = true
            env:OpenWindow()
            assert.is_nil(module.view)
            assert.equal("notOwn", module.reason)
            assert.is_false(module.ui.panel:IsShown())
        end)

        for _, shape in ipairs({ "base", "recipe", "spellbook" }) do
            it("reads Forever's profession from the " .. shape .. " when the child line is empty", function()
                local env, module = world({ shape = shape })
                env:OpenWindow()
                assert.equal(shape, module.source)
                assert.equal(30, module.view.data.skill)
                assert.equal(150, module.view.data.cap)
                assert.equal(3, #module.view.data.known)
                assert.equal(101, module.view.plan.steps[1].recipe.id)
                assert.equal("table", module.view.data.known[1].source)
                assert.is_true(module.ui.panel:IsShown())
            end)
        end

        it("says so when no source knows the open profession", function()
            local env, module = world({ shape = "none" })
            env:OpenWindow()
            assert.is_nil(module.view)
            assert.equal("noProfession", module.reason)
            module:Diagnose()
            assert.is_truthy(env.messages[#env.messages]:find("child line 0 skill 0 / 0, base line 0 skill 0 / 0, "
                .. "read from nil line nil", 1, true))
        end)

        it("reports each check the panel depends on in one line", function()
            local env, module = world()
            env:OpenWindow()
            module:Diagnose()
            local line = env.messages[#env.messages]
            assert.is_truthy(line:find("state enabled", 1, true))
            assert.is_truthy(line:find("frame table shown true, attached true, plan true, reason nil", 1, true))
            assert.is_truthy(line:find("child line 2937 skill 30 / 150, base line 171 skill nil / nil, read from "
                .. "child line 2937 skill 30 / 150, recipes 4, plannable 4, in line 4, learned 3, first grey 60, "
                .. "first colour 0", 1, true))
            env.ready = false
            env:Fire("TRADE_SKILL_LIST_UPDATE")
            env:Advance(0.5)
            module:Diagnose()
            assert.is_truthy(env.messages[#env.messages]:find("reason notReady, ready false", 1, true))
        end)

        it("shows the recipe on a click and links it on a Shift-click, and never crafts", function()
            local env, module = world()
            env:OpenWindow()
            local row = module.ui.steps[1]
            row:GetScript("OnClick")(row)
            assert.equal(101, env.opened)
            env.shift = true
            row:GetScript("OnClick")(row)
            assert.equal("recipe:101", env.chatLink)
            env.opened = nil
            local candidate = module.ui.candidates[1]
            env.shift = false
            candidate:GetScript("OnClick")(candidate)
            assert.is_nil(env.opened)
        end)

        it("collapses to the current step and remembers it for the character", function()
            local env, module = world()
            env:OpenWindow()
            assert.is_true(#module.view.plan.steps >= 2)
            assert.is_true(module.ui.steps[2]:IsShown())
            module:OnCollapse()
            assert.is_true(env.R.Settings.character.professionPlannerCollapsed)
            assert.is_true(module.ui.steps[1]:IsShown())
            assert.is_false(module.ui.steps[2]:IsShown())
            assert.is_false(module.ui.goal:IsShown())
        end)

        it("docks past whatever already sits on the window's right edge", function()
            local function frame(left, right, shown, children)
                return { IsShown = function() return shown end, GetLeft = function() return left end,
                    GetRight = function() return right end,
                    GetChildren = function() return unpack(children or {}) end }
            end
            local env, module = world()
            env:OpenWindow()
            assert.equal(3, module.ui.dockX)
            -- Forever's own tabs on the edge, a hidden one further out, and a page inside the window.
            env.edgeFrames = { frame(697, 740, true), frame(697, 900, false), frame(20, 680, true) }
            env:SetSkill(31)
            assert.equal(43, module.ui.dockX)
            -- The shared sidebar moved past another addon's 350 wide window, with its tabs on it.
            env.edgeFrames = { frame(1050, 1051, true, { frame(1050, 1092, true), frame(1050, 1092, false) }) }
            env:SetSkill(32)
            assert.equal(395, module.ui.dockX)
        end)

        it("fits each step's second line beside its ready count, dropping words before cutting it", function()
            local env, module = world()
            env.craftable[101] = 4
            env:OpenWindow()
            local fitted = 0
            for _, row in ipairs(module.ui.steps) do
                if row:IsShown() then
                    local ready = row.ready:GetText() ~= "" and row.ready:GetStringWidth() + 8 or 0
                    assert.is_true(row.sub:GetStringWidth() <= row.barWidth - ready, row.sub:GetText())
                    if row.sub:GetText():find("per point", 1, true) then fitted = fitted + 1 end
                end
            end
            assert.is_true(fitted >= 1)
            assert.equal("x24  Bolt", module.ui.steps[1].name:GetText():gsub("|c%x+", ""):gsub("|r", ""))
        end)

        it("names the colours and their source in the step tooltip", function()
            local env, module = world()
            env:OpenWindow()
            local row = module.ui.steps[1]
            row:GetScript("OnEnter")(row)
            assert.equal(row, env.tipOwner)
            local text = table.concat(env.tipLines, "\n")
            assert.is_truthy(text:find("Yellow at 50, green at 55, grey at 60", 1, true))
            assert.is_truthy(text:find("game's own data", 1, true))
        end)
    end)

    describe("settings", function()
        it("accepts only the two goals", function()
            local env = world()
            assert.is_true(env.R.Settings:SetOption("plannerGoal", "gold"))
            assert.is_false(env.R.Settings:SetOption("plannerGoal", "fast"))
            assert.equal("gold", env.R.Settings:GetOption("plannerGoal"))
        end)
    end)

    describe("residue", function()
        it("holds nothing while the window is closed", function()
            local env, module = world()
            env:OpenWindow()
            env:CloseWindow()
            assert.is_false(module.session)
            assert.is_false(module.ui.panel:IsShown())
            assert.equal(0, env:ActiveTimers())
            for event, entries in pairs(env.R.Broker.events) do
                for _, each in ipairs(entries) do
                    if each.owner == module then assert.equal("TRADE_SKILL_SHOW", event) end
                end
            end
        end)

        it("leaves nothing behind when disabled and works again when re-enabled", function()
            local env, module = world()
            env:OpenWindow()
            env.R.Registry:Disable(module)
            assert.equal(0, env:ActiveTimers())
            assert.is_false(module.ui.panel:IsShown())
            for _, entries in pairs(env.R.Broker.events) do
                for _, each in ipairs(entries) do assert.is_not.equal(module, each.owner) end
            end
            assert.is_true(env.R.Registry:Enable(ID))
            env:Advance(0.5)
            assert.is_true(module.ui.panel:IsShown())
            assert.equal(101, module.view.plan.steps[1].recipe.id)
        end)
    end)
end)
