--- @module items.professionPlanner
--- Purpose: beside the profession window, the path from the current skill to the rank's cap in the fewest crafts
---     or for the least gold, as steps with progress, replanned whenever the skill, the recipes, the bags or the
---     prices change.
--- Requires: C_TradeSkillUI.GetAllRecipeIDs, C_TradeSkillUI.GetRecipeInfo, C_TradeSkillUI.GetRecipeSchematic,
---     C_TradeSkillUI.GetChildProfessionInfo, C_TradeSkillUI.GetBaseProfessionInfo,
---     C_TradeSkillUI.GetProfessionInfoByRecipeID, GetProfessions, GetProfessionInfo,
---     C_TradeSkillUI.IsRecipeInSkillLine, C_TradeSkillUI.GetCraftableCount, C_TradeSkillUI.GetRecipeSourceText,
---     C_TradeSkillUI.GetRecipeLink, C_TradeSkillUI.OpenRecipe, C_TradeSkillUI.IsTradeSkillReady,
---     C_TradeSkillUI.IsTradeSkillLinked, C_TradeSkillUI.IsTradeSkillGuild, C_TradeSkillUI.IsNPCCrafting,
---     C_Item.GetItemCount, C_Item.GetItemInfo, C_Item.GetItemIconByID, C_Item.GetItemNameByID, GetBuildInfo,
---     Enum.TradeskillRelativeDifficulty, Enum.CraftingReagentType, ChatEdit_InsertLink, IsShiftKeyDown,
---     GameTooltip
--- Events: TRADE_SKILL_SHOW; TRADE_SKILL_CLOSE, TRADE_SKILL_LIST_UPDATE, TRADE_SKILL_DATA_SOURCE_CHANGED,
---     SKILL_LINES_CHANGED, NEW_RECIPE_LEARNED, BAG_UPDATE_DELAYED, REFACTOR_SETTINGS_CHANGED (contextual, while
---     the profession window is open)
--- Hot: no
-- luacheck: read globals ChatEdit_InsertLink
local _, R = ...
local Planner = R:RegisterModule({
    id = "items.professionPlanner", category = "Items", nameKey = "PLANNER_NAME",
    descriptionKey = "PLANNER_DESC", detailKey = "PLANNER_DETAIL",
    requires = { "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo",
        "C_TradeSkillUI.GetRecipeSchematic", "C_TradeSkillUI.GetChildProfessionInfo",
        "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetProfessionInfoByRecipeID", "GetProfessions",
        "GetProfessionInfo", "C_TradeSkillUI.IsRecipeInSkillLine",
        "C_TradeSkillUI.GetCraftableCount", "C_TradeSkillUI.GetRecipeSourceText", "C_TradeSkillUI.GetRecipeLink",
        "C_TradeSkillUI.OpenRecipe", "C_TradeSkillUI.IsTradeSkillReady", "C_TradeSkillUI.IsTradeSkillLinked",
        "C_TradeSkillUI.IsTradeSkillGuild", "C_TradeSkillUI.IsNPCCrafting", "C_Item.GetItemCount",
        "C_Item.GetItemInfo", "C_Item.GetItemIconByID", "C_Item.GetItemNameByID", "GetBuildInfo",
        "Enum.TradeskillRelativeDifficulty", "Enum.CraftingReagentType", "ChatEdit_InsertLink", "IsShiftKeyDown",
        "GameTooltip" },
    risk = "visible", defaultEnabled = true,
})

local REFRESH_DELAY = 0.2
-- Half the recipes in the generated table for build 1.60.1.70009 turn grey within 25 points of turning
-- yellow. A recipe the table lacks is planned from that guess until the window narrows it down.
local DEFAULT_GAP = 25
-- Within this share of a level's own cost the plan stays on the recipe it was already on, so two recipes a
-- hair apart do not alternate a level at a time. The plan is that much worse at most and reads as steps.
local STICKY = 0.05
-- A recipe the bags can make now wins a near tie by this much, so what is held gets used before buying more.
local HELD_BONUS = 0.01
local EPSILON = 1e-9
local MAX_SEEN, MAX_CANDIDATES = 5000, 3
local MAX_LEVEL = 1000
local CONTEXT_EVENTS = { "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "BAG_UPDATE_DELAYED", "REFACTOR_SETTINGS_CHANGED" }
local ORANGE, YELLOW, GREEN, GREY = "orange", "yellow", "green", "grey"

-- Yellow from low, green from halfway to grey, grey from high: the split the game has used since Classic.
local function colourAt(low, high, skill)
    if skill >= high then return GREY end
    if skill < low then return ORANGE end
    if skill < math.floor((low + high) / 2) then return YELLOW end
    return GREEN
end
Planner.ColourAt = colourAt

-- The chance a craft gives a point: certain while orange, then falling in a line to nothing at grey.
-- Unverified on Forever (PRD 7.9.1).
local function chanceAt(low, high, skill)
    if skill >= high then return 0 end
    if skill < low then return 1 end
    return (high - skill) / (high - low)
end
Planner.ChanceAt = chanceAt

-- What one sighting says about the level a recipe turns yellow at. Orange puts it above this skill. Yellow
-- puts it at or below, and close enough to grey that the halfway point is still ahead. Green puts the halfway
-- point behind.
local function sighting(lo, hi, colour, skill, high)
    if colour == ORANGE then return math.max(lo, skill + 1), hi end
    if colour == YELLOW then return math.max(lo, 2 * skill + 2 - high), math.min(hi, skill) end
    if colour == GREEN then return lo, math.min(hi, 2 * skill + 1 - high) end
    return lo, hi
end

-- A sighting that contradicts the stored range means the recipe changed, so it starts over from this one.
local function narrow(lo, hi, colour, skill, high)
    local newLo, newHi = sighting(lo, hi, colour, skill, high)
    if newLo <= newHi then return newLo, newHi end
    newLo, newHi = sighting(1, high, colour, skill, high)
    if newLo <= newHi then return newLo, newHi end
    return 1, high
end
Planner.Narrow = narrow

local function estimate(lo, hi, high)
    return math.max(lo, math.min(hi, high - DEFAULT_GAP))
end
Planner.Estimate = estimate

local function valueAt(recipe, level, best, target)
    local chance = chanceAt(recipe.low, recipe.high, level)
    if chance <= 0 then return nil end
    local gain = level < recipe.low and recipe.gain or 1
    local marginal = recipe.cost / chance
    return marginal + best[math.min(target, level + gain)], marginal
end

-- The expected-cost programme (PRD 7.9.1). Each recipe is { low, high, gain, cost }, cost per craft in crafts
-- or copper. best[level] is the expected cost from that level to the end and choice[level] the recipe that
-- gets it. Past the highest grey level nothing known gives a point, so the plan stops there short of the cap.
function Planner.Solve(all, skill, cap)
    -- A recipe grey now stays grey all the way up, so the levels below never need to look at it.
    local recipes, top = {}, skill
    for _, recipe in ipairs(all) do
        if recipe.high > skill then
            recipes[#recipes + 1] = recipe
            if recipe.high > top then top = recipe.high end
        end
    end
    local target = math.min(cap, top)
    local plan = { steps = {}, skill = skill, cap = cap, reached = math.max(skill, target), total = 0, crafts = 0 }
    if target <= skill then return plan end
    local best, choice = { [target] = 0 }, {}
    for level = target - 1, skill, -1 do
        local bestValue, bestRecipe, bestMarginal
        for _, recipe in ipairs(recipes) do
            local value, marginal = valueAt(recipe, level, best, target)
            if value and (not bestValue or value < bestValue - EPSILON) then
                bestValue, bestRecipe, bestMarginal = value, recipe, marginal
            end
        end
        local previous = choice[level + 1]
        if previous and previous ~= bestRecipe then
            local value = valueAt(previous, level, best, target)
            if value and value <= bestValue + STICKY * bestMarginal then
                bestValue, bestRecipe = value, previous
            end
        end
        best[level], choice[level] = bestValue, bestRecipe
    end
    local level = skill
    while level < target do
        local recipe = choice[level]
        local step = { recipe = recipe, from = level, crafts = 0 }
        while level < target and choice[level] == recipe do
            step.crafts = step.crafts + 1 / chanceAt(recipe.low, recipe.high, level)
            level = math.min(target, level + (level < recipe.low and recipe.gain or 1))
        end
        step.to = level
        plan.crafts = plan.crafts + step.crafts
        plan.steps[#plan.steps + 1] = step
    end
    plan.total = best[skill]
    return plan
end

local function wholeCrafts(crafts)
    return math.ceil(crafts - EPSILON)
end
Planner.WholeCrafts = wholeCrafts

-- The generated table, unpacked one profession at a time the first time its window opens. It is static data
-- for the build it was generated from, so the unpacked copy is kept for the session.
local tableLow, tableHigh, unpacked = {}, {}, {}

local function unpackLine(lines, lineID)
    unpacked[lineID] = true
    for _, chunk in ipairs(lines[lineID] or {}) do
        for spell, low, high in chunk:gmatch("(%d+),(%d+),(%d+)") do
            spell = tonumber(spell)
            tableLow[spell], tableHigh[spell] = tonumber(low), tonumber(high)
        end
    end
end

-- A profession the table files under another line is found by unpacking the rest, once.
function Planner:FromTable(lineID, recipeID)
    local data = R.ProfessionThresholds
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    if lineID and data.lines[lineID] then
        if not unpacked[lineID] then unpackLine(data.lines, lineID) end
    elseif not unpacked.all then
        unpacked.all = true
        for id in pairs(data.lines) do
            if not unpacked[id] then unpackLine(data.lines, id) end
        end
    end
    return tableLow[recipeID], tableHigh[recipeID]
end

local function validLevel(value)
    return type(value) == "number" and value >= 1 and value <= MAX_LEVEL and value % 1 == 0
end

local function buildKey()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- Sightings hold for the build they were seen on. A different build at login is the invalidation event.
local function cleanSeen(stored, key)
    local recipes, count = {}, 0
    if type(stored) == "table" and stored.build == key and type(stored.recipes) == "table" then
        for id, entry in pairs(stored.recipes) do
            if count < MAX_SEEN and type(id) == "number" and id > 0 and id % 1 == 0 and type(entry) == "table"
                and validLevel(entry[1]) and validLevel(entry[2]) and validLevel(entry[3])
                and entry[1] <= entry[2] and entry[2] <= entry[3] then
                recipes[id], count = { entry[1], entry[2], entry[3] }, count + 1
            end
        end
    end
    return { build = key, recipes = recipes, count = count }
end
Planner.CleanSeen = cleanSeen

-- Where a recipe turns yellow, and how sure the plan is of it: the table when it agrees with the client, the
-- window's own sightings when they pin it down, an estimate inside what they allow otherwise.
function Planner:Threshold(recipeID, lineID, high, colour, skill)
    local low, highFromTable = self:FromTable(lineID, recipeID)
    if low and highFromTable == high and (colour == nil or colourAt(low, high, skill) == colour) then
        return low, "table"
    end
    local seen = self.seen
    local entry = seen.recipes[recipeID]
    local lo, hi = 1, high
    if entry and entry[3] == high then lo, hi = entry[1], entry[2] end
    if colour then lo, hi = narrow(lo, hi, colour, skill, high) end
    if lo > 1 or hi < high then
        if entry then
            entry[1], entry[2], entry[3] = lo, hi, high
        elseif seen.count < MAX_SEEN then
            seen.recipes[recipeID], seen.count = { lo, hi, high }, seen.count + 1
        end
    end
    if lo == hi then return lo, "seen" end
    return estimate(lo, hi, high), "estimate"
end

-- A recipe's reagents never change for its ID within a build, so they are kept for the session.
local reagentCache = {}

local function basicReagents(recipeID)
    local cached = reagentCache[recipeID]
    if cached then return cached end
    local list = {}
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    local basic = Enum.CraftingReagentType.Basic
    if type(schematic) == "table" and type(schematic.reagentSlotSchematics) == "table" then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local reagent = type(slot.reagents) == "table" and slot.reagents[1]
            if slot.reagentType == basic and type(reagent) == "table" and type(reagent.itemID) == "number" then
                list[#list + 1] = { itemID = reagent.itemID, quantity = slot.quantityRequired or 1 }
            end
        end
    end
    reagentCache[recipeID] = list
    return list
end

local function plannable(recipe)
    return type(recipe) == "table" and type(recipe.recipeID) == "number"
        and type(recipe.maxTrivialLevel) == "number" and recipe.maxTrivialLevel > 0
        and not recipe.isDummyRecipe and not recipe.isRecraft and not recipe.isSalvageRecipe
        and not recipe.isGatheringRecipe
end

function Planner:Entry(recipe, lineID, skill)
    local high = recipe.maxTrivialLevel
    local colour = self.colourOf[recipe.relativeDifficulty]
    local low, source = self:Threshold(recipe.recipeID, lineID, high, colour, skill)
    local gain = 1
    if colour == ORANGE and type(recipe.numSkillUps) == "number" and recipe.numSkillUps > 1 then
        gain = recipe.numSkillUps
    end
    return { id = recipe.recipeID, name = recipe.name or "", icon = recipe.icon, low = low, high = high,
        gain = gain, source = source, learned = recipe.learned == true }
end

local function validInfo(info)
    return type(info) == "table" and type(info.professionID) == "number" and info.professionID > 0
        and type(info.skillLevel) == "number" and type(info.maxSkillLevel) == "number" and info.maxSkillLevel > 0
end

local MAX_PROFESSION_SLOTS = 5

-- The spellbook's own list, the last source: the slot whose line or name is the open profession's.
local function fromSpellbook(lineID, name)
    local slots = { GetProfessions() }
    for slot = 1, MAX_PROFESSION_SLOTS do
        local index = slots[slot]
        if index then
            local slotName, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
            if (lineID and skillLine == lineID or name and name ~= "" and slotName == name)
                and type(rank) == "number" and type(maxRank) == "number" and maxRank > 0 then
                return { professionID = skillLine or lineID or 0, professionName = slotName, skillLevel = rank,
                    maxSkillLevel = maxRank }
            end
        end
    end
    return nil
end

-- Forever answers GetChildProfessionInfo with an empty profession (line 0, skill 0 of 0, seen 6 Nov 2026), so
-- the open profession comes from the first source that answers: the child line, the base line, the line of a
-- recipe the player knows, then the spellbook. The second value names the source, for Diagnose.
function Planner:Profession(recipes)
    local child = C_TradeSkillUI.GetChildProfessionInfo()
    if validInfo(child) then return child, "child" end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    if validInfo(base) then return base, "base" end
    for _, recipe in ipairs(recipes) do
        if recipe.learned then
            local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipe.recipeID)
            if validInfo(info) then return info, "recipe" end
            break
        end
    end
    local lineID = type(base) == "table" and type(base.professionID) == "number" and base.professionID > 0
        and base.professionID or nil
    local name = type(base) == "table" and base.professionName or type(child) == "table" and child.professionName
    local info = fromSpellbook(lineID, name)
    if info then return info, "spellbook" end
    return nil, nil
end

-- Retail lists every expansion's recipes and the line picks the open one out. A line that keeps none of the
-- player's recipes is not the one the list is for, so then the whole list stands.
local function inLine(recipes, lineID)
    local kept, learned = {}, false
    for _, recipe in ipairs(recipes) do
        if C_TradeSkillUI.IsRecipeInSkillLine(recipe.recipeID, lineID) then
            kept[#kept + 1] = recipe
            if recipe.learned then learned = true end
        end
    end
    return learned and kept or recipes
end

-- Nil when there is nothing of the player's own to plan: someone else's profession, a guild's, an NPC's, or
-- data the client has not finished sending. The second value says which, for Diagnose.
function Planner:Read()
    if not C_TradeSkillUI.IsTradeSkillReady() then return nil, "notReady" end
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
        or C_TradeSkillUI.IsNPCCrafting() then
        return nil, "notOwn"
    end
    local recipes = {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if plannable(recipe) then recipes[#recipes + 1] = recipe end
    end
    local info, source = self:Profession(recipes)
    self.source = source
    if not info then return nil, "noProfession" end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local baseID = type(base) == "table" and type(base.professionID) == "number" and base.professionID > 0
        and base.professionID or nil
    local lineID = info.parentProfessionID or baseID or info.professionID
    local skill = info.skillLevel
    local known, unknown = {}, {}
    for _, recipe in ipairs(inLine(recipes, info.professionID)) do
        local entry = self:Entry(recipe, lineID, skill)
        if entry.learned then
            known[#known + 1] = entry
        else
            unknown[#unknown + 1] = entry
        end
    end
    return { name = info.professionName or "", professionID = info.professionID, skill = skill,
        cap = info.maxSkillLevel, known = known, unknown = unknown }
end

function Planner:GoldAvailable()
    local top = R.Price:Top()
    return top ~= nil and top ~= "vendor"
end

-- Auction prices only. A vendor price is what a merchant pays for the reagent, not what it costs to buy.
local function auctionPrice(itemID, quantity)
    local _, link = C_Item.GetItemInfo(itemID)
    if not link then return nil end
    local value, source = R.Price:Get(link, quantity)
    if not value or source == "vendor" then return nil end
    return value
end

function Planner:Held(itemID)
    local held = self.held[itemID]
    if held == nil then
        held = C_Item.GetItemCount(itemID, true, false, true, false) or 0
        self.held[itemID] = held
    end
    return held
end

-- Cost per craft for the goal: one craft, a little less when the bags can make it now, or the auction value
-- of its reagents. Nil leaves the recipe out of a gold plan.
function Planner:Cost(entry, goal)
    local reagents = basicReagents(entry.id)
    entry.reagents = reagents
    local ready = true
    for _, reagent in ipairs(reagents) do
        if self:Held(reagent.itemID) < reagent.quantity then ready = false end
    end
    if goal ~= "gold" then return ready and 1 - HELD_BONUS or 1 end
    local total = 0
    for _, reagent in ipairs(reagents) do
        local value = auctionPrice(reagent.itemID, reagent.quantity)
        if not value then return nil end
        total = total + value
    end
    return math.max(1, total)
end

local function topOf(recipes, skill)
    local top = skill
    for _, recipe in ipairs(recipes) do
        if recipe.high > top then top = recipe.high end
    end
    return top
end

function Planner:Priced(known, goal)
    local eligible = {}
    for _, entry in ipairs(known) do
        entry.cost = self:Cost(entry, goal)
        if entry.cost then eligible[#eligible + 1] = entry end
    end
    return eligible
end

-- Recipes not yet learned that would carry the plan on from where it stops, nearest first.
local function candidates(unknown, level)
    local list = {}
    for _, entry in ipairs(unknown) do
        if entry.high > level then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        if a.low ~= b.low then return a.low < b.low end
        return a.id < b.id
    end)
    for index = #list, MAX_CANDIDATES + 1, -1 do list[index] = nil end
    return list
end

function Planner:ShoppingList(plan)
    local need, order = {}, {}
    for _, step in ipairs(plan.steps) do
        local crafts = wholeCrafts(step.crafts)
        for _, reagent in ipairs(step.recipe.reagents or {}) do
            local itemID = reagent.itemID
            if not need[itemID] then order[#order + 1] = itemID end
            need[itemID] = (need[itemID] or 0) + reagent.quantity * crafts
        end
    end
    local list = {}
    for _, itemID in ipairs(order) do
        list[#list + 1] = { itemID = itemID, need = need[itemID], have = self:Held(itemID),
            name = C_Item.GetItemNameByID(itemID) or "", icon = C_Item.GetItemIconByID(itemID) }
    end
    table.sort(list, function(a, b)
        local shortA, shortB = math.max(0, a.need - a.have), math.max(0, b.need - b.have)
        if shortA ~= shortB then return shortA > shortB end
        return a.itemID < b.itemID
    end)
    return list
end

-- The current step keeps the level it was first seen at, so its bar fills as the player crafts rather than
-- starting over at every replan.
function Planner:TrackStep(data, step)
    local current = self.current
    if not step then
        self.current = nil
        return
    end
    if not current or current.recipeID ~= step.recipe.id or current.professionID ~= data.professionID
        or current.from > data.skill then
        self.current = { recipeID = step.recipe.id, professionID = data.professionID, from = step.from }
    end
    step.started = self.current.from
end

function Planner:Plan(data)
    local requested = R.Settings:GetOption("plannerGoal")
    local goal, note = requested, nil
    if goal == "gold" and not self:GoldAvailable() then goal, note = "crafts", "noAuction" end
    local eligible = self:Priced(data.known, goal)
    if goal == "gold" and math.min(data.cap, topOf(eligible, data.skill)) < math.min(data.cap,
        topOf(data.known, data.skill)) then
        goal, note = "crafts", "unpriced"
        eligible = self:Priced(data.known, goal)
    end
    local plan = Planner.Solve(eligible, data.skill, data.cap)
    plan.goal, plan.requested, plan.note = goal, requested, note
    plan.candidates = plan.reached < data.cap and candidates(data.unknown, plan.reached) or {}
    plan.reagents = self:ShoppingList(plan)
    for _, step in ipairs(plan.steps) do
        step.whole = wholeCrafts(step.crafts)
    end
    self:TrackStep(data, plan.steps[1])
    return plan
end

function Planner:Ready(recipeID)
    return C_TradeSkillUI.GetCraftableCount(recipeID) or 0
end

function Planner:SourceText(recipeID)
    return C_TradeSkillUI.GetRecipeSourceText(recipeID)
end

-- Selecting goes through the client's own call, never through Blizzard's frames, and crafting stays the
-- player's press on Create (G7). Shift puts the recipe in the chat line instead.
function Planner:OnStep(recipeID)
    if IsShiftKeyDown() then
        local link = C_TradeSkillUI.GetRecipeLink(recipeID)
        if link then ChatEdit_InsertLink(link) end
        return
    end
    C_TradeSkillUI.OpenRecipe(recipeID)
end

function Planner:OnGoal(value)
    R.Settings:SetOption("plannerGoal", value)
end

function Planner:OnCollapse()
    local character = R.Settings.character
    character.professionPlannerCollapsed = not character.professionPlannerCollapsed
    self:Render()
end

function Planner:Refresh()
    self.refreshTimer = nil
    if not self.session then return end
    self.held = {}
    local data, reason = self:Read()
    if data and #data.known > 0 then
        self.view, self.reason = { data = data, plan = self:Plan(data) }, nil
    else
        self.view, self.reason = nil, reason or "noRecipes"
    end
    self:Render()
end

local function count(list, test)
    local total = 0
    for _, value in ipairs(list) do
        if test(value) then total = total + 1 end
    end
    return total
end

-- For /run when the panel does not show: what the client answered at each step the panel depends on,
-- read fresh, beside what the last refresh decided.
function Planner:Diagnose()
    local window = R.Capabilities:Resolve("ProfessionsFrame")
    local child = C_TradeSkillUI.GetChildProfessionInfo() or {}
    local base = C_TradeSkillUI.GetBaseProfessionInfo() or {}
    local recipes = {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        recipes[#recipes + 1] = C_TradeSkillUI.GetRecipeInfo(recipeID) or false
    end
    local usable = {}
    for _, recipe in ipairs(recipes) do
        if plannable(recipe) then usable[#usable + 1] = recipe end
    end
    local info, source = self:Profession(usable)
    info = info or {}
    local kept = type(info.professionID) == "number" and #inLine(usable, info.professionID) or 0
    local learned = count(recipes, function(recipe) return recipe and recipe.learned end)
    local first = recipes[1] or {}
    local shown = type(window) == "table" and type(window.IsShown) == "function" and window:IsShown()
    -- Built with explicit indexes: most of these can be nil, which a list constructor would leave as holes.
    local values = {}
    local function add(value) values[#values + 1] = tostring(value) end
    add(self.state) add(self.failure) add(self.session) add(type(window)) add(shown)
    add(self.ui and self.ui.attached) add(self.view ~= nil) add(self.reason)
    add(C_TradeSkillUI.IsTradeSkillReady()) add(C_TradeSkillUI.IsTradeSkillLinked())
    add(child.professionID) add(child.skillLevel) add(child.maxSkillLevel)
    add(base.professionID) add(base.skillLevel) add(base.maxSkillLevel)
    add(source) add(info.professionID) add(info.skillLevel) add(info.maxSkillLevel)
    add(#recipes) add(#usable) add(kept) add(learned) add(first.maxTrivialLevel) add(first.relativeDifficulty)
    R:Print(string.format(R.L.PLANNER_DIAGNOSE, unpack(values)))
end

function Planner:QueueRefresh()
    if self.refreshTimer or not self.session then return end
    self.refreshTimer = R:After(self, REFRESH_DELAY, function(owner) owner:Refresh() end)
end

function Planner:Render()
    local ui = self.ui
    if not ui then return end
    if self.session and self.view and ui.attached then
        R.UI:PlannerRender(ui, self.view, R.Settings.character.professionPlannerCollapsed == true)
    else
        R.UI:PlannerHide(ui)
    end
end

-- The window belongs to a load-on-demand addon that loads on this same event, so it is looked for a tick later.
function Planner:Attach()
    local window = R.Capabilities:Resolve("ProfessionsFrame")
    if type(window) == "table" and type(window.GetFrameLevel) == "function" then
        R.UI:PlannerAttach(self.ui, window)
    end
end

function Planner:OnShow()
    self:Stop()
    self.session = true
    R.Broker:Subscribe("TRADE_SKILL_CLOSE", self.Stop, self)
    R.Broker:Subscribe("TRADE_SKILL_LIST_UPDATE", self.QueueRefresh, self, REFRESH_DELAY)
    R.Broker:Subscribe("TRADE_SKILL_DATA_SOURCE_CHANGED", self.QueueRefresh, self)
    R.Broker:Subscribe("SKILL_LINES_CHANGED", self.QueueRefresh, self)
    R.Broker:Subscribe("NEW_RECIPE_LEARNED", self.QueueRefresh, self)
    R.Broker:Subscribe("BAG_UPDATE_DELAYED", self.QueueRefresh, self, REFRESH_DELAY)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.QueueRefresh, self)
    R:After(self, 0, function(owner)
        owner:Attach()
        owner:Refresh()
    end)
end

function Planner:Stop()
    self.session, self.view, self.refreshTimer, self.held = false, nil, nil, {}
    R:CancelTimers(self)
    for _, event in ipairs(CONTEXT_EVENTS) do
        R.Broker:Unsubscribe(event, self)
    end
    if self.ui then R.UI:PlannerDetach(self.ui) end
end

function Planner:OnEnable()
    local account, character = R.Settings.account, R.Settings.character
    account.professionSeen = cleanSeen(account.professionSeen, buildKey())
    self.seen = account.professionSeen
    if type(character.professionPlannerCollapsed) ~= "boolean" then character.professionPlannerCollapsed = false end
    local enum = Enum.TradeskillRelativeDifficulty
    self.colourOf = { [enum.Optimal] = ORANGE, [enum.Medium] = YELLOW, [enum.Easy] = GREEN, [enum.Trivial] = GREY }
    self.held = {}
    if not self.ui then
        local function handler(method, context)
            return function(...) R:SafeCall(self, method, context, ...) end
        end
        self.ui = R.UI:PlannerCreate({
            onStep = handler(self.OnStep, "planner step"),
            onGoal = handler(self.OnGoal, "planner goal"),
            onCollapse = handler(self.OnCollapse, "planner collapse"),
            ready = function(recipeID) return self:Ready(recipeID) end,
            sourceText = function(recipeID) return self:SourceText(recipeID) end,
            goldAvailable = function() return self:GoldAvailable() end,
        })
    end
    R.Broker:Subscribe("TRADE_SKILL_SHOW", self.OnShow, self)
    local window = R.Capabilities:Resolve("ProfessionsFrame")
    if type(window) == "table" and type(window.IsShown) == "function" and window:IsShown() then self:OnShow() end
end

function Planner:OnDisable()
    self:Stop()
    R.Broker:UnsubscribeAll(self)
end
