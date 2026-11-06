local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local ID = "interface.allSpells"

local NAMES = {
    [1953] = "Blink", [133] = "Fireball", [11366] = "Pyroblast", [2948] = "Scorch", [11129] = "Combustion",
    [7302] = "Frost Armor", [99999] = "Mystery",
}

local function frameStub(level)
    return { GetFrameLevel = function() return level end, GetFrameStrata = function() return "HIGH" end }
end

local PLAYER_LEVEL = 6

-- The client surface the module reads, stubbed one call at a time. Trainer services carry the type
-- they filter under, so a read that left a filter off really does miss them.
local function world()
    local env = Runtime.new()
    Widgets.install(env)
    env:Load("Locales/Modules.enUS.lua")
    env.R.UI = env.R.UI or {}
    env:Load("UI/Widgets/Widgets.lua")
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    local Frame = getmetatable(env.CreateFrame("Frame"))
    Frame.SetDesaturated = function(self, value) self.desaturated = value end
    Frame.SetTextColor = function(self, r, g, b) self.textColor = { r, g, b } end
    env.UIParent = { name = "UIParent" }
    env.GameTooltip = {
        SetOwner = function(_, owner) env.tipOwner = owner end,
        SetSpellByID = function(_, spellID) env.tipSpell = spellID end,
        Show = function() end, Hide = function() env.tipOwner = nil end,
        IsOwned = function(_, frame) return env.tipOwner == frame end,
    }
    env.Enum = {
        TrainerType = { General = 0, Tradeskills = 1, Pet = 2 },
        SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
        SpellBookSpellBank = { Player = 0, Pet = 1 },
    }
    env.UnitClass = function() return "Mage", "MAGE", 8 end
    env.UnitLevel = function() return PLAYER_LEVEL end

    local trainer = { services = {}, sets = {}, tradeskill = false, kind = env.Enum.TrainerType.General,
        filters = { available = true, unavailable = false, used = false } }
    local function visible()
        local list = {}
        for _, service in ipairs(trainer.services) do
            if trainer.filters[service.status] then list[#list + 1] = service end
        end
        return list
    end
    env.trainer = trainer
    env.IsTradeskillTrainer = function() return trainer.tradeskill end
    env.GetTrainerServiceTypeFilter = function(filter) return trainer.filters[filter] end
    env.SetTrainerServiceTypeFilter = function(filter, on)
        trainer.sets[#trainer.sets + 1] = { filter, on }
        trainer.filters[filter] = on
    end
    env.GetNumTrainerServices = function() return #visible() end
    env.GetTrainerServiceInfo = function(index)
        local service = visible()[index]
        if not service then return nil end
        return service.name, service.status, 100, service.level
    end
    env.GetTrainerServiceSkillLine = function(index) return visible()[index].line end
    env.GetTrainerServiceItemLink = function(index) return visible()[index].link end
    env.C_TooltipInfo = { GetTrainerService = function(index)
        local service = visible()[index]
        return service.spellID and { id = service.spellID } or nil
    end }
    env.C_Trainer = { GetTrainerType = function() return trainer.kind end }

    local book = { lines = {}, items = {}, known = {}, levels = {} }
    env.book = book
    env.C_Spell = {
        GetSpellTexture = function(spellID) return 1000 + spellID end,
        GetSpellName = function(spellID) return NAMES[spellID] end,
        GetSpellSubtext = function(spellID) return spellID == 133 and "Rank 1" or "" end,
    }
    env.C_SpellBook = {
        GetNumSpellBookSkillLines = function() return #book.lines end,
        GetSpellBookSkillLineInfo = function(index) return book.lines[index] end,
        GetSpellBookItemInfo = function(slot, bank)
            assert.equals(0, bank)
            return book.items[slot]
        end,
        GetSpellBookItemLevelLearned = function(slot) return book.levels[slot] or 0 end,
        IsSpellKnown = function(spellID) return book.known[spellID] == true end,
    }
    env.addonLoaded = true
    env.C_AddOns = { IsAddOnLoaded = function() return env.addonLoaded end }
    return env
end

local function spellbook(env, withBook, withSearch)
    local window = frameStub(8)
    if withBook then
        window.SpellBookFrame = frameStub(10)
        if withSearch then window.SpellBookFrame.SearchBox = frameStub(11) end
    end
    env.PlayerSpellsFrame = window
    return window
end

local function fill(env)
    local book = env.book
    book.lines = {
        { name = "General", itemIndexOffset = 0, numSpellBookItems = 2 },
        { name = "Fire", itemIndexOffset = 2, numSpellBookItems = 3 },
        { name = "Hidden", itemIndexOffset = 5, numSpellBookItems = 1, shouldHide = true },
        { name = "Other spec", itemIndexOffset = 6, numSpellBookItems = 1, offSpecID = 62 },
        { name = "Guild", itemIndexOffset = 7, numSpellBookItems = 1, isGuild = true },
    }
    book.items = {
        { actionID = 1953, itemType = 1, name = "Blink" },
        { actionID = 77, itemType = 4, name = "A flyout" },
        { actionID = 133, itemType = 1, name = "Fireball" },
        { actionID = 2948, itemType = 1, name = "Scorch" },
        { actionID = 11129, itemType = 2, name = "Combustion" },
        { actionID = 555, itemType = 1, name = "Hidden spell" },
        { actionID = 556, itemType = 1, name = "Off spec spell" },
        { actionID = 557, itemType = 1, name = "Guild spell" },
    }
    book.levels = { [3] = 1, [4] = 22, [5] = 28 }
    book.known = { [1953] = true, [133] = true, [2948] = true }
    env.R.Settings.account.classSpells = {
        MAGE = {
            [1953] = { level = 10, line = "Arcane" },
            [133] = { level = 1, line = "Fire" },
            [11366] = { level = 20, line = "Fire" },
            [7302] = { level = 5, line = "Frost" },
            [99999] = { level = 0, line = "" },
        },
    }
end

local function enable(env)
    env:Load("UI/AllSpells.lua")
    env:Load("Modules/Interface/AllSpells.lua")
    assert.is_true(env.R.Registry:Enable(ID), tostring(env.R.moduleByID[ID].failure)
        .. table.concat(env.R.moduleByID[ID].missing or {}, ","))
    return env.R.moduleByID[ID]
end

-- The mock never fires a frame's own show and hide, so the spellbook opening is done by hand.
local function open(module)
    module.ui.panel:Show()
    module.ui.panel.scripts.OnShow(module.ui.panel)
end

local function close(module)
    module.ui.panel:Hide()
    module.ui.panel.scripts.OnHide(module.ui.panel)
end

local function typeSearch(module, text)
    module.ui.search:SetText(text)
    module.ui.search.scripts.OnTextChanged(module.ui.search)
end

local function shownRows(ui)
    local out = {}
    for _, row in ipairs(ui.pool) do
        if row:IsShown() then out[#out + 1] = row end
    end
    return out
end

local function owned(env, module)
    local count = 0
    for _, entries in pairs(env.R.Broker.events) do
        for _, entry in ipairs(entries) do
            if entry.owner == module then count = count + 1 end
        end
    end
    return count
end

local function shape(list)
    local out = {}
    for _, entry in ipairs(list) do
        if entry.header then
            out[#out + 1] = "# " .. entry.header
        else
            out[#out + 1] = string.format("%s %d %s", entry.name, entry.level, entry.known and "known" or "unknown")
        end
    end
    return out
end

describe("interface.allSpells", function()
    describe("recording at the trainer", function()
        local function services(env)
            env.trainer.services = {
                { name = "Fireball", status = "available", spellID = 133, level = 1, line = "Fire" },
                { name = "Pyroblast", status = "unavailable", spellID = 11366, level = 20, line = "Fire" },
                { name = "Frost Armor", status = "used", spellID = 7302, level = 5, line = "Frost" },
                { name = "Blink", status = "unavailable", level = 10, line = "Arcane",
                    link = "|cff71d5ff|Hspell:1953|h[Blink]|h|r" },
                { name = "No spell", status = "available", level = 3, line = "Fire" },
                { name = "Fire", status = "available", level = 0, line = "Fire", spellID = 0 },
            }
        end

        it("reads every service, stores id, level and line for the class, and restores the filters", function()
            local env = world()
            services(env)
            local module = enable(env)
            env:Fire("TRAINER_SHOW")
            assert.same({
                [133] = { level = 1, line = "Fire" }, [11366] = { level = 20, line = "Fire" },
                [7302] = { level = 5, line = "Frost" }, [1953] = { level = 10, line = "Arcane" },
            }, env.R.Settings.account.classSpells.MAGE)
            assert.same({ available = true, unavailable = false, used = false }, env.trainer.filters)
            assert.same({ { "unavailable", true }, { "used", true }, { "unavailable", false }, { "used", false } },
                env.trainer.sets)
            assert.is_false(module.recording)
            assert.equals(0, #env.R.errors)
        end)

        it("leaves filters alone that were already on and replaces the class record each visit", function()
            local env = world()
            services(env)
            env.trainer.filters = { available = true, unavailable = true, used = true }
            env.R.Settings.account.classSpells = { MAGE = { [5] = { level = 4, line = "Old" } },
                WARRIOR = { [6] = { level = 2, line = "Arms" } } }
            enable(env)
            env:Fire("TRAINER_SHOW")
            assert.same({}, env.trainer.sets)
            local stored = env.R.Settings.account.classSpells
            assert.is_nil(stored.MAGE[5])
            assert.equals(4, (function() local n = 0 for _ in pairs(stored.MAGE) do n = n + 1 end return n end)())
            assert.same({ [6] = { level = 2, line = "Arms" } }, stored.WARRIOR)
        end)

        it("skips tradeskill and pet trainers", function()
            local env = world()
            services(env)
            enable(env)
            env.trainer.tradeskill = true
            env:Fire("TRAINER_SHOW")
            env.trainer.tradeskill = false
            env.trainer.kind = env.Enum.TrainerType.Pet
            env:Fire("TRAINER_SHOW")
            assert.same({}, env.R.Settings.account.classSpells)
            assert.same({}, env.trainer.sets)
        end)

        it("keeps the old record when the trainer shows no services", function()
            local env = world()
            enable(env)
            env.R.Settings.account.classSpells.MAGE = { [133] = { level = 1, line = "Fire" } }
            env:Fire("TRAINER_SHOW")
            assert.same({ [133] = { level = 1, line = "Fire" } }, env.R.Settings.account.classSpells.MAGE)
            assert.same({ available = true, unavailable = false, used = false }, env.trainer.filters)
        end)

        it("records on a later refresh when the list was empty at TRAINER_SHOW, then stops trying", function()
            local env = world()
            enable(env)
            env:Fire("TRAINER_SHOW")
            assert.is_nil(env.R.Settings.account.classSpells.MAGE)
            services(env)
            env:Advance(1)
            env:Fire("TRAINER_UPDATE")
            assert.equals(20, env.R.Settings.account.classSpells.MAGE[11366].level)
            assert.same({ available = true, unavailable = false, used = false }, env.trainer.filters)
            local calls = #env.trainer.sets
            env:Advance(1)
            env:Fire("TRAINER_UPDATE")
            assert.equals(calls, #env.trainer.sets)
        end)

        it("gives up switching filters after a few empty refreshes", function()
            local env = world()
            enable(env)
            env:Fire("TRAINER_SHOW")
            for _ = 1, 6 do
                env:Advance(1)
                env:Fire("TRAINER_UPDATE")
            end
            assert.equals(3 * 4, #env.trainer.sets)
        end)

        it("follows TRAINER_UPDATE only while a trainer is open, and never fights the player's filters", function()
            local env = world()
            services(env)
            local module = enable(env)
            assert.is_nil(env.R.Broker.events.TRAINER_UPDATE)
            env:Fire("TRAINER_SHOW")
            assert.is_not_nil(env.R.Broker.events.TRAINER_UPDATE)
            local calls = #env.trainer.sets
            env:Advance(1)
            env:Fire("TRAINER_UPDATE")
            assert.equals(calls, #env.trainer.sets)
            -- The player switches every filter on themselves: that list is complete, so it is read as is.
            env.trainer.filters = { available = true, unavailable = true, used = true }
            env.trainer.services[1].level = 2
            env:Advance(1)
            env:Fire("TRAINER_UPDATE")
            assert.equals(calls, #env.trainer.sets)
            assert.equals(2, env.R.Settings.account.classSpells.MAGE[133].level)
            env:Fire("TRAINER_CLOSED")
            assert.is_nil(env.R.Broker.events.TRAINER_UPDATE)
            assert.is_true(owned(env, module) > 0)
        end)
    end)

    describe("saved data", function()
        it("drops what is malformed and never errors on it", function()
            local env = world()
            env.R.Settings.account.classSpells = {
                MAGE = {
                    [133] = { level = 1, line = "Fire" }, [-5] = { level = 1 }, [1.5] = { level = 1 },
                    bad = { level = 1 }, [7] = { level = "x" }, [8] = "text", [9] = { level = 2, line = 5 },
                    [10] = { level = 9999 },
                },
                [5] = { [1] = { level = 1 } }, WARRIOR = "nope", ROGUE = {}, PRIEST = { [1] = { level = -1 } },
            }
            env.R.Settings.character.allSpellsShown = "yes"
            enable(env)
            assert.same({ MAGE = { [133] = { level = 1, line = "Fire" }, [9] = { level = 2, line = "" } } },
                env.R.Settings.account.classSpells)
            assert.is_nil(env.R.Settings.character.allSpellsShown)
            assert.equals(0, #env.R.errors)
        end)

        it("turns a saved value that is not a table into an empty record", function()
            local env = world()
            env.R.Settings.account.classSpells = "garbage"
            enable(env)
            assert.same({}, env.R.Settings.account.classSpells)
        end)
    end)

    describe("the list", function()
        it("is the spellbook joined with the recorded trainer list, grouped and sorted", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            local module = enable(env)
            local list, recorded = module:BuildList()
            assert.is_true(recorded)
            assert.same({
                "# General", "Blink 10 known",
                "# Fire", "Fireball 1 known", "Pyroblast 20 unknown", "Scorch 22 known", "Combustion 28 unknown",
                "# Frost", "Frost Armor 5 unknown",
                "# Other", "Mystery 0 unknown",
            }, shape(list))
            assert.equals(1133, list[4].icon)
            assert.equals("Rank 1", list[4].sub)
        end)

        it("flags what the player can train and counts each group", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            local module = enable(env)
            local list = module:BuildList()
            local byName = {}
            for _, entry in ipairs(list) do byName[entry.name or entry.header] = entry end
            assert.is_false(byName.Blink.trainable)
            assert.is_false(byName.Fireball.trainable)
            assert.is_false(byName.Pyroblast.trainable)
            assert.same({ header = "Fire", learned = 2, total = 4 }, byName.Fire)
            assert.same({ header = "Other", learned = 0, total = 1 }, byName.Other)
            assert.same({ header = "Frost", learned = 0, total = 1 }, byName.Frost)
            assert.is_true(byName["Frost Armor"].trainable)
            local learned, total, upcoming = module:Summary(list)
            assert.equals(3, learned)
            assert.equals(7, total)
            assert.equals("Pyroblast", upcoming.name)
            assert.equals(20, upcoming.level)
        end)

        it("shows the record note only until the class has a record", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            local module = enable(env)
            open(module)
            assert.is_false(module.ui.note:IsShown())
            close(module)
            env.R.Settings.account.classSpells = {}
            open(module)
            assert.is_true(module.ui.note:IsShown())
            assert.equals(env.R.L.ALL_SPELLS_NO_DATA, module.ui.note.text.text)
        end)

        it("writes the summary lines", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            local module = enable(env)
            open(module)
            assert.equals("3 of 7 learned", module.ui.summary.text)
            assert.equals("Next: Pyroblast at level 20", module.ui.upcoming.text)
            env.book.known[11366] = true
            env.R.Settings.account.classSpells.MAGE[7302].level = 99
            module:Refresh()
            assert.equals("4 of 7 learned", module.ui.summary.text)
            assert.equals("Next: Combustion at level 28", module.ui.upcoming.text)
        end)

        it("draws learned, trainable and future rows apart, with the level label and a spell tooltip", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            local module = enable(env)
            open(module)
            local rows = module.ui.pool
            assert.equals("General", rows[1].title.text)
            assert.equals("1/1", rows[1].count.text)
            assert.is_true(rows[1].title:IsShown())
            assert.is_false(rows[1].name:IsShown())
            assert.equals("Blink", rows[2].name.text)
            assert.equals("Level 10", rows[2].label.text)
            assert.is_false(rows[2].icon.desaturated)
            assert.is_false(rows[2].accent:IsShown())
            assert.equals("Fire", rows[3].title.text)
            assert.equals("2/4", rows[3].count.text)
            assert.equals("Fireball", rows[4].name.text)
            assert.equals("Rank 1", rows[4].sub.text)
            assert.equals("Pyroblast", rows[5].name.text)
            assert.is_true(rows[5].icon.desaturated)
            assert.equals("Level 20", rows[5].label.text)
            assert.is_false(rows[5].accent:IsShown())
            assert.is_not.same(rows[4].name.textColor, rows[5].name.textColor)
            local frost = rows[9]
            assert.equals("Frost Armor", frost.name.text)
            assert.is_true(frost.icon.desaturated)
            assert.equals("Trainable", frost.label.text)
            assert.is_true(frost.accent:IsShown())
            rows[5].scripts.OnEnter(rows[5])
            assert.equals(11366, env.tipSpell)
            assert.equals(rows[5], env.tipOwner)
            rows[5].scripts.OnLeave(rows[5])
            assert.is_nil(env.tipOwner)
            local mystery = rows[11]
            assert.equals("Mystery", mystery.name.text)
            assert.equals("", mystery.label.text)
            assert.is_false(rows[12]:IsShown())
        end)

        it("filters by tab and by name, and drops headers that end up empty", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            local module = enable(env)
            open(module)
            local ui = module.ui
            local function titles()
                local out = {}
                for _, row in ipairs(shownRows(ui)) do
                    out[#out + 1] = row.title:IsShown() and "# " .. row.title.text or row.name.text
                end
                return out
            end
            ui.tabs[2].scripts.OnClick(ui.tabs[2])
            assert.equals("toLearn", env.R.Settings.character.allSpellsTab)
            assert.same({ "# Fire", "Pyroblast", "Combustion", "# Frost", "Frost Armor", "# Other", "Mystery" },
                titles())
            ui.tabs[3].scripts.OnClick(ui.tabs[3])
            assert.same({ "# General", "Blink", "# Fire", "Fireball", "Scorch" }, titles())
            ui.tabs[1].scripts.OnClick(ui.tabs[1])
            typeSearch(module, "FIRE")
            assert.same({ "# Fire", "Fireball" }, titles())
            typeSearch(module, "o")
            assert.same({ "# Fire", "Pyroblast", "Scorch", "Combustion", "# Frost", "Frost Armor" }, titles())
            typeSearch(module, "zzz")
            assert.same({}, titles())
            assert.is_true(ui.empty:IsShown())
            typeSearch(module, "")
            assert.is_false(ui.empty:IsShown())
            assert.is_true(#titles() > 0)
        end)

        it("restores the saved tab and falls back to All for a bad one", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            env.R.Settings.character.allSpellsTab = "learned"
            local module = enable(env)
            open(module)
            assert.is_true(module.ui.tabs[3].selected)
            assert.equals(5, #shownRows(module.ui))
            env.R.Registry:Disable(module)
            env.R.Settings.character.allSpellsTab = "nope"
            assert.is_true(env.R.Registry:Enable(module))
            assert.equals("all", env.R.Settings.character.allSpellsTab)
            assert.is_true(module.ui.tabs[1].selected)
        end)

        it("recycles a fixed pool of rows and scrolls three rows a wheel tick", function()
            local env = world()
            fill(env)
            env.book.lines = { { name = "Big", itemIndexOffset = 0, numSpellBookItems = 60 } }
            env.book.items = {}
            for slot = 1, 60 do
                env.book.items[slot] = { actionID = 2000 + slot, itemType = 1,
                    name = string.format("Spell %02d", slot) }
                env.book.levels[slot] = slot
                env.book.known[2000 + slot] = slot <= 3
            end
            env.R.Settings.account.classSpells = { MAGE = { [1] = { level = 1, line = "Z" } } }
            spellbook(env, true, true)
            local module = enable(env)
            local frames = #env.frames
            open(module)
            local ui = module.ui
            assert.equals(frames, #env.frames)
            assert.equals(24, #ui.pool)
            assert.equals("Big", ui.pool[1].title.text)
            assert.equals("Spell 01", ui.pool[2].name.text)
            assert.is_true(ui.maxOffset > 0)
            assert.equals(ui.maxOffset, ui.slider.maximum)
            assert.is_true(ui.slider:IsShown())
            ui.panel.scripts.OnMouseWheel(ui.panel, -1)
            assert.equals(3, ui.offset)
            assert.equals("Spell 03", ui.pool[1].name.text)
            ui.list.scripts.OnMouseWheel(ui.list, 1)
            assert.equals(0, ui.offset)
            ui.list.scripts.OnMouseWheel(ui.list, 1)
            assert.equals(0, ui.offset)
            ui.slider.scripts.OnValueChanged(ui.slider, ui.maxOffset)
            local last = ui.pool[#shownRows(ui)]
            assert.equals("1", last.name.text)
            ui.panel.scripts.OnMouseWheel(ui.panel, -1)
            assert.equals(ui.maxOffset, ui.offset)
            ui.down.scripts.OnClick(ui.down)
            assert.equals(ui.maxOffset, ui.offset)
            ui.up.scripts.OnClick(ui.up)
            assert.equals(ui.maxOffset - 1, ui.offset)
            typeSearch(module, "spell 4")
            assert.equals(0, ui.offset)
            assert.is_false(ui.slider:IsShown())
        end)
    end)

    describe("the spellbook", function()
        it("docks the panel to the window, shown whenever the feature is on, with no control in the book", function()
            local env = world()
            fill(env)
            local window = spellbook(env, true, true)
            local book = window.SpellBookFrame
            local module = enable(env)
            local ui = module.ui
            assert.equals(book, ui.panel.parent)
            assert.is_true(ui.panel:IsShown())
            assert.is_nil(ui.button)
            assert.is_nil(ui.close)
            for _, frame in ipairs(env.frames) do
                if frame ~= ui.panel then
                    assert.is_not.equal(book, frame.parent)
                end
            end
            env.R.Registry:Disable(module)
            assert.equals(env.UIParent, ui.panel.parent)
            assert.is_false(ui.panel:IsShown())
        end)

        it("falls back to the window when it has no book", function()
            local env = world()
            fill(env)
            local window = spellbook(env, false, false)
            local module = enable(env)
            assert.equals(window, module.ui.panel.parent)
            assert.is_true(module.ui.panel:IsShown())
        end)

        it("waits for the spellbook to load, then attaches once", function()
            local env = world()
            fill(env)
            env.addonLoaded = false
            local module = enable(env)
            assert.is_false(module.ui.panel:IsShown())
            assert.is_not_nil(env.R.Broker.events.ADDON_LOADED)
            env:Fire("ADDON_LOADED", "Something_Else")
            assert.is_false(module.ui.panel:IsShown())
            local window = spellbook(env, true, true)
            env.addonLoaded = true
            env:Fire("ADDON_LOADED", "Blizzard_PlayerSpells")
            assert.is_true(module.ui.panel:IsShown())
            assert.equals(window.SpellBookFrame, module.ui.panel.parent)
            assert.is_nil(env.R.Broker.events.ADDON_LOADED)
        end)

        it("stays enabled with nothing shown when the window is not what it expects", function()
            local env = world()
            fill(env)
            env.PlayerSpellsFrame = "not a frame"
            local module = enable(env)
            assert.equals("enabled", module.state)
            assert.is_false(module.ui.panel:IsShown())
            assert.equals(0, #env.R.errors)
        end)
    end)

    describe("lifecycle", function()
        it("holds the list events only while the panel is shown, and refreshes on them", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            local module = enable(env)
            assert.is_nil(env.R.Broker.events.SPELLS_CHANGED)
            assert.is_nil(env.R.Broker.events.LEARNED_SPELL_IN_SKILL_LINE)
            open(module)
            assert.is_not_nil(env.R.Broker.events.SPELLS_CHANGED)
            assert.is_not_nil(env.R.Broker.events.LEARNED_SPELL_IN_SKILL_LINE)
            assert.is_true(module.ui.pool[5].icon.desaturated)
            env.book.known[11366] = true
            env:Fire("SPELLS_CHANGED")
            assert.is_false(module.ui.pool[5].icon.desaturated)
            close(module)
            assert.is_nil(env.R.Broker.events.SPELLS_CHANGED)
            assert.is_nil(env.R.Broker.events.LEARNED_SPELL_IN_SKILL_LINE)
        end)

        it("refreshes the open panel after a trainer record", function()
            local env = world()
            fill(env)
            env.R.Settings.account.classSpells = {}
            spellbook(env, true, true)
            local module = enable(env)
            open(module)
            assert.is_true(module.ui.note:IsShown())
            env.trainer.services = {
                { name = "Pyroblast", status = "unavailable", spellID = 11366, level = 20, line = "Fire" },
            }
            env:Fire("TRAINER_SHOW")
            assert.is_false(module.ui.note:IsShown())
            assert.equals("Pyroblast", module.ui.pool[5].name.text)
        end)

        it("enable, disable, enable leaves no subscriptions, no timers and no extra frames", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            local module = enable(env)
            open(module)
            env:Fire("TRAINER_SHOW")
            env:Fire("SPELLS_CHANGED")
            env:Fire("SPELLS_CHANGED")
            local ui, frames = module.ui, #env.frames
            env.R.Registry:Disable(module)
            assert.equals(0, owned(env, module))
            assert.equals(0, env:ActiveTimers())
            assert.is_false(ui.panel:IsShown())
            assert.equals(env.UIParent, ui.panel.parent)
            assert.is_true(env.R.Registry:Enable(module))
            assert.equals(ui, module.ui)
            assert.equals(frames, #env.frames)
            assert.is_true(ui.panel:IsShown())
            assert.is_not_nil(env.R.Broker.events.TRAINER_SHOW)
            env.R.Registry:Disable(module)
            assert.equals(0, owned(env, module))
            assert.equals(0, env:ActiveTimers())
            assert.equals(0, #env.R.errors)
        end)

        it("registers no OnUpdate handler", function()
            local env = world()
            fill(env)
            spellbook(env, true, true)
            enable(env)
            for _, frame in ipairs(env.frames) do
                assert.is_nil(frame.scripts.OnUpdate)
            end
        end)
    end)
end)
