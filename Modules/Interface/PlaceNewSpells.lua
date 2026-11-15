--- @module interface.placeNewSpells
--- Purpose: put a newly learned ability on the first free slot of an action bar you can see, and swap
---     a newly learned rank in for the older rank on the bars.
--- Requires: C_Spell.PickupSpell, C_Spell.IsSpellPassive, C_Spell.GetSpellName, C_Spell.GetSpellSubtext,
---     C_ActionBar.HasAction, C_ActionBar.PutActionInSlot, C_ActionBar.IsOnBarOrSpecialBar,
---     C_SpellBook.FindBaseSpellByID, GetActionInfo, GetCursorInfo, ClearCursor, InCombatLockdown, UnitClass
--- Events: LEARNED_SPELL_IN_SKILL_LINE, PLAYER_REGEN_ENABLED, REFACTOR_SPELL_TEST. The eight player
---     bars are resolved by name at enable, so a client missing one loses that bar, never the module.
--- Hot: no
local _, R = ...
local PlaceNewSpells = R:RegisterModule({
    id = "interface.placeNewSpells", category = "Levelling", nameKey = "PLACE_SPELLS_NAME",
    descriptionKey = "PLACE_SPELLS_DESC", detailKey = "PLACE_SPELLS_DETAIL",
    requires = { "C_Spell.PickupSpell", "C_Spell.IsSpellPassive", "C_Spell.GetSpellName",
        "C_Spell.GetSpellSubtext", "C_ActionBar.HasAction", "C_ActionBar.PutActionInSlot",
        "C_ActionBar.IsOnBarOrSpecialBar", "C_SpellBook.FindBaseSpellByID", "GetActionInfo", "GetCursorInfo",
        "ClearCursor", "InCombatLockdown", "UnitClass" },
    risk = "automation", defaultEnabled = false,
})

-- The eight player bars, in the order a free slot is looked for: the main bar first, then
-- outwards. Names rather than the frames themselves, so a client without one of them costs
-- that bar and nothing else. The labels are the visibility catalogue's: it names the same
-- eight bars, and a second set of names for them would drift from it.
local BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
    "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }
local BAR_LABEL = "VIS_GROUP_BAR_"
-- The learn event arrives while the client is still filling the spellbook, so the pass
-- waits a moment. It also folds a level that teaches several spells into one pass.
local SETTLE = 0.3
-- Retries are for one case only: something already on the cursor. What is held there is
-- the player's, so the queue waits for them to drop it rather than taking the cursor.
local MAX_ATTEMPTS = 3
local EMPTY = {}
-- Every slot a player fills: main bar pages 1 to 6 and the stance and form bars on pages 7 to 10,
-- then the extra bars on pages 13 to 15. Pages 11 and 12 are the possess and override bars,
-- which the client fills for a vehicle or a mind control, so an older rank there is not theirs.
-- A rank swap reads every slot, not only bars on screen: the cat form bar and the second main
-- page hold ranks too, and any bar addon draws these same slots.
local SLOT_RANGES = { { 1, 120 }, { 145, 180 } }

function PlaceNewSpells:Verdict(name, spellID, slot, bar)
    local report = self.report
    report.verdict, report.spell, report.slot, report.bar = name, spellID, slot, bar
    return name
end

function PlaceNewSpells:ResolveBars()
    local bars = {}
    for index, name in ipairs(BARS) do
        local frame = R.Capabilities:Resolve(name)
        if type(frame) == "table" and type(frame.IsShown) == "function"
            and type(frame.actionButtons) == "table" then
            bars[#bars + 1] = { frame = frame, index = index }
        end
    end
    return bars
end

-- A slot is free when the button drawing it is on screen and holds nothing. The slot id is
-- read off the button rather than from a fixed range: the main bar's slots change with the
-- page it is on, and a bar showing six buttons owns six slots, not twelve.
function PlaceNewSpells:FreeSlot()
    for _, bar in ipairs(self.bars or EMPTY) do
        if bar.frame:IsShown() then
            for _, button in ipairs(bar.frame.actionButtons) do
                local slot = button.action
                if type(slot) == "number" and button:IsShown() and not C_ActionBar.HasAction(slot) then
                    return slot, bar.index
                end
            end
        end
    end
    return nil
end

-- A rank or an override of something already placed is not new: the bar holds the base
-- spell, so both ids are asked about.
function PlaceNewSpells:OnBar(spellID)
    if C_ActionBar.IsOnBarOrSpecialBar(spellID) then
        return true
    end
    local base = C_SpellBook.FindBaseSpellByID(spellID)
    return type(base) == "number" and base ~= spellID and C_ActionBar.IsOnBarOrSpecialBar(base) == true
end

-- The "Rank N" the client puts under a spell's name, as a number. Nil for a spell without one.
local function rankNumber(spellID)
    local sub = C_Spell.GetSpellSubtext(spellID)
    return type(sub) == "string" and tonumber(sub:match("%d+")) or nil
end

-- 1 when a is the higher rank, -1 when b is, nil when nothing tells them apart. The rank text
-- first; the level that teaches each is the fallback for a client that leaves the text empty.
function PlaceNewSpells:Compare(a, b)
    local rankA, rankB = rankNumber(a), rankNumber(b)
    if rankA and rankB and rankA ~= rankB then
        return rankA > rankB and 1 or -1
    end
    local levels = self.levels
    local levelA, levelB = levels[a], levels[b]
    if type(levelA) == "number" and type(levelB) == "number" and levelA ~= levelB then
        return levelA > levelB and 1 or -1
    end
    return nil
end

-- Every slot holding another rank of the spell, keyed by that rank's spell id, and whether the
-- spell itself is on a slot already. A rank has its own spell id and shares the name. Only a
-- spell placed as itself counts: a macro that casts an old rank is the player's own text.
function PlaceNewSpells:Ranks(spellID)
    local name = C_Spell.GetSpellName(spellID)
    if type(name) ~= "string" then
        return nil, false
    end
    local ranks, holdsNew
    for _, range in ipairs(SLOT_RANGES) do
        for slot = range[1], range[2] do
            local kind, id = GetActionInfo(slot)
            if kind == "spell" and type(id) == "number" then
                if id == spellID then
                    holdsNew = true
                elseif C_Spell.GetSpellName(id) == name then
                    ranks = ranks or {}
                    ranks[id] = ranks[id] or {}
                    local slots = ranks[id]
                    slots[#slots + 1] = slot
                end
            end
        end
    end
    return ranks, holdsNew == true
end

-- The rank to replace is the highest one below the new rank, which is the one the bars were
-- casting. A lower rank kept beside it is there on purpose, a cheap heal or a slow that costs
-- less mana, so it stays. Two ranks nothing can order mean the module cannot know which one
-- the player plays with, and it touches neither.
function PlaceNewSpells:Older(spellID, ranks)
    local best
    for id in pairs(ranks) do
        if self:Compare(id, spellID) ~= 1 then
            if best == nil then
                best = id
            else
                local order = self:Compare(id, best)
                if order == nil then
                    return nil, "UNSURE"
                elseif order == 1 then
                    best = id
                end
            end
        end
    end
    return best, "ONBAR"
end

-- The two client calls that move the spell, each on its own so a refusal is caught and
-- named rather than thrown out of the event handler.
function PlaceNewSpells:Pickup(spellID)
    C_Spell.PickupSpell(spellID)
end

function PlaceNewSpells:Put(slot)
    C_ActionBar.PutActionInSlot(slot)
end

-- Putting a spell on a slot that holds one hands the old one to the cursor, and dropping it
-- there is what takes the old rank off the bar.
function PlaceNewSpells:Swap(spellID, slot)
    if not R:Try(self, self.Pickup, "pick up a new rank", spellID) or GetCursorInfo() ~= "spell" then
        ClearCursor()
        return false
    end
    local put = R:Try(self, self.Put, "swap in a new rank", slot)
    ClearCursor()
    local kind, id = GetActionInfo(slot)
    return put == true and kind == "spell" and id == spellID
end

function PlaceNewSpells:Upgrade(spellID, ranks)
    local older, why = self:Older(spellID, ranks)
    if not older then
        return self:Verdict(why, spellID)
    end
    if GetCursorInfo() ~= nil then
        return self:Verdict("CURSOR", spellID)
    end
    -- A client that refuses one slot refuses them all, so the first refusal ends the pass.
    local swapped = 0
    for _, slot in ipairs(ranks[older]) do
        if not self:Swap(spellID, slot) then
            break
        end
        swapped = swapped + 1
    end
    if swapped == 0 then
        return self:Verdict("BLOCKED", spellID)
    end
    self:Verdict("UPGRADED", spellID, ranks[older][1])
    local sub = C_Spell.GetSpellSubtext(spellID)
    R:Print(string.format(R.L.PLACE_SPELLS_UPGRADED, C_Spell.GetSpellName(spellID) or tostring(spellID),
        type(sub) == "string" and sub ~= "" and sub or R.L.PLACE_SPELLS_NEW_RANK))
    return "UPGRADED"
end

-- One spell, one attempt. Every exit names what stopped it: in game, "the client refused"
-- and "there was nowhere to put it" look identical unless the module says which it was.
function PlaceNewSpells:Place(spellID)
    if C_Spell.IsSpellPassive(spellID) then
        return self:Verdict("PASSIVE", spellID)
    end
    local ranks, holdsNew = self:Ranks(spellID)
    if ranks and not holdsNew and R.Settings:GetOption("placeSpellsRanks") == true then
        return self:Upgrade(spellID, ranks)
    end
    -- Another rank on a bar means the ability is placed already, swapped or not.
    if holdsNew or ranks or self:OnBar(spellID) then
        return self:Verdict("ONBAR", spellID)
    end
    if #self.bars == 0 then
        return self:Verdict("NOBARS", spellID)
    end
    local slot, bar = self:FreeSlot()
    if not slot then
        return self:Verdict("NOSLOT", spellID)
    end
    if GetCursorInfo() ~= nil then
        return self:Verdict("CURSOR", spellID)
    end
    if not R:Try(self, self.Pickup, "pick up a learned spell", spellID) or GetCursorInfo() ~= "spell" then
        ClearCursor()
        return self:Verdict("BLOCKED", spellID)
    end
    local placed = R:Try(self, self.Put, "place a learned spell", slot)
    ClearCursor()
    if not placed or not C_ActionBar.HasAction(slot) then
        return self:Verdict("BLOCKED", spellID)
    end
    self:Verdict("PLACED", spellID, slot, bar)
    R:Print(string.format(R.L.PLACE_SPELLS_PLACED, C_Spell.GetSpellName(spellID) or tostring(spellID),
        R.L[BAR_LABEL .. bar] or tostring(bar)))
    return "PLACED"
end

function PlaceNewSpells:Schedule()
    if self.scheduled then
        return
    end
    self.scheduled = true
    R:After(self, SETTLE, self.Drain)
end

function PlaceNewSpells:Clear()
    local pending = self.pending
    for index = #pending, 1, -1 do
        pending[index] = nil
    end
end

function PlaceNewSpells:Drain()
    self.scheduled = false
    local pending = self.pending
    if #pending == 0 then
        return
    end
    if InCombatLockdown() then
        -- Putting an action in a slot is protected in combat. The queue waits for the
        -- fight to end rather than erroring once per spell learned.
        return self:Verdict("COMBAT", pending[1])
    end
    if R:Paused() then
        -- The pause modifier means "not this one", so the queue is dropped, not deferred.
        self:Verdict("PAUSED", pending[1])
        return self:Clear()
    end
    -- A held cursor is worth waiting out; a refusal from the client is not, because it
    -- will refuse the next one the same way and each attempt costs an error entry. Both
    -- stay in the queue, so /refactor spelltest can run them again once the cause is gone.
    local waiting, retry = {}, false
    for index = 1, #pending do
        local spellID = pending[index]
        local result = self:Place(spellID)
        if result == "CURSOR" or result == "BLOCKED" then
            waiting[#waiting + 1] = spellID
            retry = retry or result == "CURSOR"
        else
            self.seen[spellID] = true
        end
    end
    self:Clear()
    for index = 1, #waiting do
        pending[index] = waiting[index]
    end
    if retry and self.attempts < MAX_ATTEMPTS then
        self.attempts = self.attempts + 1
        self:Schedule()
    end
end

function PlaceNewSpells:OnLearned(_, spellID, _, isGuildPerkSpell)
    if type(spellID) ~= "number" or isGuildPerkSpell == true or self.seen[spellID] then
        return
    end
    local pending = self.pending
    for index = 1, #pending do
        if pending[index] == spellID then
            return
        end
    end
    pending[#pending + 1] = spellID
    self.attempts = 0
    self:Schedule()
end

function PlaceNewSpells:OnCombatEnd()
    if #self.pending > 0 then
        self:Schedule()
    end
end

-- /refactor spelltest. The placement happens in the second after a level up, with the
-- level up text still on screen, so the only way to see why nothing moved is to ask
-- afterwards. It also runs the queue again, which is the way back from a refusal.
function PlaceNewSpells:Test()
    local L, report = R.L, self.report
    local shown = 0
    for _, bar in ipairs(self.bars) do
        if bar.frame:IsShown() then
            shown = shown + 1
        end
    end
    R:Print(string.format(L.CMD_SPELL_TEST_BARS, shown, #self.bars, #self.pending))
    local slot, bar = self:FreeSlot()
    if slot then
        R:Print(string.format(L.CMD_SPELL_TEST_FREE, slot, L[BAR_LABEL .. bar] or tostring(bar)))
    else
        R:Print(L.CMD_SPELL_TEST_FULL)
    end
    if report.verdict then
        R:Print(string.format(L.CMD_SPELL_TEST_LAST,
            C_Spell.GetSpellName(report.spell) or tostring(report.spell),
            L["CMD_SPELL_VERDICT_" .. report.verdict]))
    else
        R:Print(L.CMD_SPELL_TEST_NONE)
    end
    if #self.pending > 0 then
        self.attempts = 0
        self:Drain()
    end
end

function PlaceNewSpells:OnEnable()
    self.bars, self.pending, self.seen, self.report = self:ResolveBars(), {}, {}, {}
    -- Static, never invalidated: the level each of the class's spells is taught at, by spell id.
    local classSpells = R.ClassSpells and R.ClassSpells.spells
    self.levels = type(classSpells) == "table" and classSpells[select(2, UnitClass("player"))] or EMPTY
    self.attempts, self.scheduled = 0, false
    R.Broker:Subscribe("LEARNED_SPELL_IN_SKILL_LINE", self.OnLearned, self)
    R.Broker:Subscribe("PLAYER_REGEN_ENABLED", self.OnCombatEnd, self)
    R.Broker:Subscribe("REFACTOR_SPELL_TEST", self.Test, self)
end

function PlaceNewSpells:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    self.bars, self.pending, self.seen, self.report, self.levels = nil, nil, nil, nil, nil
    self.attempts, self.scheduled = 0, false
end
