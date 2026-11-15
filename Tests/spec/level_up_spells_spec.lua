local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local ID = "interface.levelUpSpells"

local NAMES = { [133] = "Fireball", [1953] = "Blink", [5504] = "Conjure Water", [11366] = "Pyroblast",
    [2948] = "Scorch", [100] = "Charge" }

local function world()
    local env = Runtime.new()
    Widgets.install(env)
    env:Load("Locales/Modules.enUS.lua")
    env:Load("Locales/Features.enUS.lua")
    env:Load("Locales/Commands.enUS.lua")
    env.R.UI = env.R.UI or {}
    env:Load("UI/Widgets/Widgets.lua")
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    env.messages = {}
    env.UIParent = { name = "UIParent" }
    env.Enum = {
        SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2 },
        SpellBookSpellBank = { Player = 0, Pet = 1 },
    }
    env.UnitClass = function() return "Mage", "MAGE", 8 end
    env.UnitFactionGroup = function() return "Alliance", "Alliance" end
    env.playerLevel = 4
    env.UnitLevel = function() return env.playerLevel end
    local book = { lines = {}, items = {}, known = {}, levels = {} }
    env.book = book
    env.C_Spell = {
        GetSpellTexture = function(spellID) return 1000 + spellID end,
        GetSpellName = function(spellID) return NAMES[spellID] end,
        GetSpellSubtext = function(spellID) return spellID == 133 and "Rank 2" or "" end,
    }
    env.C_SpellBook = {
        GetNumSpellBookSkillLines = function() return #book.lines end,
        GetSpellBookSkillLineInfo = function(index) return book.lines[index] end,
        GetSpellBookItemInfo = function(slot) return book.items[slot] end,
        GetSpellBookItemLevelLearned = function(slot) return book.levels[slot] or 0 end,
        IsSpellKnown = function(spellID) return book.known[spellID] == true end,
    }
    env.LevelUpDisplay = env.CreateFrame("Frame", "LevelUpDisplay")
    env.LevelUpDisplay.GetBottom = function() return 400 end
    return env
end

local function enable(env)
    env:Load("UI/LevelUpSpells.lua")
    env:Load("Modules/Interface/LevelUpSpells.lua")
    assert.is_true(env.R.Registry:Enable(ID), tostring(env.R.moduleByID[ID].failure)
        .. table.concat(env.R.moduleByID[ID].missing or {}, ","))
    return env.R.moduleByID[ID]
end

local function shownCells(module)
    local out = {}
    for _, cell in ipairs(module.ui.cells) do
        if cell:IsShown() then out[#out + 1] = cell.name:GetText() end
    end
    return out
end

describe("interface.levelUpSpells", function()
    it("shows the spellbook abilities of the new level and nothing else", function()
        local env = world()
        env.book.lines = { { name = "Fire", itemIndexOffset = 0, numSpellBookItems = 3 } }
        env.book.items = {
            { actionID = 133, itemType = 1 }, { actionID = 2948, itemType = 1 }, { actionID = 11366, itemType = 2 },
        }
        env.book.levels = { [1] = 4, [2] = 5, [3] = 20 }
        env.book.known = { [133] = true, [2948] = true }
        local module = enable(env)
        env:Fire("PLAYER_LEVEL_UP", 5)
        assert.same({}, shownCells(module))
        env:Advance(2.3)
        assert.same({ "Scorch" }, shownCells(module))
        assert.is_true(module.ui.frame:IsShown())
        assert.equals("Learned", module.ui.cells[1].detail:GetText())
    end)

    it("adds trainer-only abilities from the recorded list, marked as ready to train", function()
        local env = world()
        env.R.Settings.account.classSpells = { MAGE = {
            [1953] = { level = 5, line = "Arcane" }, [133] = { level = 4, line = "Fire" },
            [5504] = { level = 6, line = "General" }, [100] = "junk",
        }, WARRIOR = { [100] = { level = 5, line = "Arms" } } }
        local module = enable(env)
        env:Fire("PLAYER_LEVEL_UP", 5)
        env:Advance(2.3)
        assert.same({ "Blink" }, shownCells(module))
        assert.equals("Ready to train", module.ui.cells[1].detail:GetText())
    end)

    it("covers every level of a jump and shows nothing when no ability fits", function()
        local env = world()
        env.R.Settings.account.classSpells = { MAGE = {
            [133] = { level = 4, line = "Fire" }, [1953] = { level = 5, line = "Arcane" },
            [2948] = { level = 7, line = "Fire" },
        } }
        env.playerLevel = 3
        local module = enable(env)
        env:Fire("PLAYER_LEVEL_UP", 7)
        env:Advance(2.3)
        assert.same({ "Fireball", "Blink", "Scorch" }, shownCells(module))
        env:Advance(10)
        assert.is_false(module.ui.frame:IsShown())
        env:Fire("PLAYER_LEVEL_UP", 8)
        env:Advance(2.3)
        assert.same({}, shownCells(module))
        assert.is_false(module.ui.frame:IsShown())
    end)

    it("folds two quick level ups into one strip", function()
        local env = world()
        env.R.Settings.account.classSpells = { MAGE = {
            [133] = { level = 6, line = "Fire" }, [1953] = { level = 7, line = "Arcane" },
        } }
        env.playerLevel = 5
        local module = enable(env)
        env:Fire("PLAYER_LEVEL_UP", 6)
        env:Advance(1)
        env:Fire("PLAYER_LEVEL_UP", 7)
        env:Advance(2.3)
        assert.same({ "Fireball", "Blink" }, shownCells(module))
    end)

    it("caps the strip and counts what did not fit", function()
        local env = world()
        local list = {}
        for id = 1, 8 do
            NAMES[200 + id] = "Spell " .. id
            list[200 + id] = { level = 5, line = "Fire" }
        end
        env.R.Settings.account.classSpells = { MAGE = list }
        local module = enable(env)
        env:Fire("PLAYER_LEVEL_UP", 5)
        env:Advance(2.3)
        assert.equals(5, #shownCells(module))
        assert.equals("and 3 more", module.ui.more:GetText())
        for id = 1, 8 do NAMES[200 + id] = nil end
    end)

    it("fades out after the hold and hangs under the banner", function()
        local env = world()
        env.R.Settings.account.classSpells = { MAGE = { [133] = { level = 5, line = "Fire" } } }
        local module = enable(env)
        local points = {}
        module.ui.frame.SetPoint = function(_, ...) points[#points + 1] = { ... } end
        env:Fire("PLAYER_LEVEL_UP", 5)
        env:Advance(2.3)
        local point = points[1]
        assert.equals("TOP", point[1])
        assert.equals(env.LevelUpDisplay, point[2])
        assert.equals("BOTTOM", point[3])
        env:Advance(4.3)
        env:Advance(1)
        assert.is_false(module.ui.frame:IsShown())
    end)

    it("falls back to the screen when the banner is not there", function()
        local env = world()
        env.LevelUpDisplay = nil
        env.R.Settings.account.classSpells = { MAGE = { [133] = { level = 5, line = "Fire" } } }
        local module = enable(env)
        local points = {}
        module.ui.frame.SetPoint = function(_, ...) points[#points + 1] = { ... } end
        env:Fire("PLAYER_LEVEL_UP", 5)
        env:Advance(2.3)
        assert.equals(env.UIParent, points[1][2])
    end)

    it("the test command shows the latest level with abilities, or says there are none", function()
        local env = world()
        local module = enable(env)
        env.R.Broker:Emit("REFACTOR_LEVELUP_TEST")
        assert.equals(env.R.L.CMD_LEVELUP_TEST_NONE, env.messages[1])
        env.R.Settings.account.classSpells = { MAGE = { [133] = { level = 3, line = "Fire" } } }
        env.R.Broker:Emit("REFACTOR_LEVELUP_TEST")
        assert.same({ "Fireball" }, shownCells(module))
        assert.equals(string.format(env.R.L.CMD_LEVELUP_TEST_SHOWN, 3), env.messages[2])
    end)

    it("falls back to the shipped table when no trainer list was recorded, held to the player's faction", function()
        local env = world()
        env.R.ClassSpells = {
            spells = { MAGE = { [133] = 5, [1953] = 5, [5504] = 5, [11366] = 6 }, WARRIOR = { [100] = 5 } },
            faction = { [1953] = "Alliance", [5504] = "Horde" },
        }
        local module = enable(env)
        env:Fire("PLAYER_LEVEL_UP", 5)
        env:Advance(2.3)
        assert.same({ "Blink", "Fireball" }, shownCells(module))
        assert.equals("Ready to train", module.ui.cells[1].detail:GetText())
    end)

    it("prefers a whole recorded trainer list over the shipped table", function()
        local env = world()
        env.R.ClassSpells = { spells = { MAGE = { [133] = 5, [1953] = 5 } }, faction = {} }
        env.R.Settings.account.classSpells = { MAGE = { [5504] = { level = 5, line = "General" },
            [2948] = { level = 5, line = "Fire" } } }
        local module = enable(env)
        env:Fire("PLAYER_LEVEL_UP", 5)
        env:Advance(2.3)
        assert.same({ "Conjure Water", "Scorch" }, shownCells(module))
    end)

    it("leaves no residue when disabled and enabled again", function()
        local env = world()
        env.R.Settings.account.classSpells = { MAGE = { [133] = { level = 5, line = "Fire" } } }
        local module = enable(env)
        env:Fire("PLAYER_LEVEL_UP", 5)
        env:Advance(2.3)
        env.R.Registry:Disable(module)
        assert.equals(0, env:ActiveTimers())
        assert.is_false(module.ui.frame:IsShown())
        for _, entries in pairs(env.R.Broker.events) do
            for _, entry in ipairs(entries) do assert.is_not.equal(module, entry.owner) end
        end
        assert.is_true(env.R.Registry:Enable(module))
        env:Fire("PLAYER_LEVEL_UP", 5)
        env:Advance(2.3)
        assert.same({ "Fireball" }, shownCells(module))
    end)
end)
