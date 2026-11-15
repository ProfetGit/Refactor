local Runtime = require("Tests.mock.runtime")

local function register(R)
    R:RegisterModule({ id = "loot.fast", requires = {}, risk = "safe", defaultEnabled = true })
    R:RegisterModule({ id = "quest.autoAccept", requires = {}, risk = "automation" })
end

describe("one profile per character", function()
    local env, R, settings
    before_each(function()
        env = Runtime.new()
        R, settings = env.R, env.R.Settings
        register(R)
    end)

    it("starts every character on Default with each module's own default", function()
        assert.equal("Default", settings:ActiveProfile())
        assert.same({ "Default" }, settings:ProfileNames())
        assert.is_true(settings:Get("loot.fast"))
        assert.is_false(settings:Get("quest.autoAccept"))
        assert.equal(100, settings:GetOption("repairCapGold"))
    end)

    it("writes switches and options into the active profile, shared by every character on it", function()
        assert.is_true(settings:Set("quest.autoAccept", true))
        assert.is_true(settings:SetOption("repairCapGold", 5))
        settings:Init(settings.account, {}, "Player-second", "Second")
        assert.is_true(settings:Get("quest.autoAccept"))
        assert.equal(5, settings:GetOption("repairCapGold"))
        assert.is_true(settings:Set("quest.autoAccept", nil))
        assert.is_nil(settings:Stored("quest.autoAccept"))
        assert.is_false(settings:Get("quest.autoAccept"))
    end)

    it("keeps profiles apart and shares account data across all of them", function()
        settings:SetOption("repairCapGold", 5)
        settings:SetOption("neverSellIDs", { [123] = true })
        assert.is_true(settings:CreateProfile("Alt", "Default"))
        assert.is_true(settings:AssignProfile("Alt"))
        assert.equal("Alt", settings:ActiveProfile())
        assert.equal(5, settings:GetOption("repairCapGold"))
        settings:SetOption("repairCapGold", 9)
        settings:SetOption("neverSellIDs", { [456] = true })
        settings:Set("loot.fast", false)
        settings:AssignProfile("Default")
        assert.equal(5, settings:GetOption("repairCapGold"))
        assert.is_true(settings:Get("loot.fast"))
        assert.same({ [456] = true }, settings:GetOption("neverSellIDs"))
        assert.is_true(settings:IsAccountOption("neverSellIDs"))
        assert.is_false(settings:IsAccountOption("repairCapGold"))
    end)

    it("copies a profile without sharing a table with its source", function()
        settings:SetOption("neverSellIDs", { [1] = true })
        settings:SetOption("uiVisibility", R.Visibility:Default())
        settings:CreateProfile("Copy", "Default")
        local copied = settings:GetProfile("Copy")
        local source = settings.account.profiles.Default
        assert.are_not.equal(source.options.uiVisibility, settings.account.profiles.Copy.options.uiVisibility)
        assert.same(source.options.uiVisibility, copied.options.uiVisibility)
        copied.options.toastOpacity = 0.3
        assert.are_not.equal(0.3, settings.account.profiles.Copy.options.toastOpacity)
        assert.is_nil(settings.account.profiles.Copy.options.neverSellIDs)
    end)

    it("refuses bad names, duplicates and deleting Default, and moves a deleted profile's users", function()
        assert.is_false(settings:CreateProfile("", "Default"))
        assert.is_false(settings:CreateProfile("Default", "Default"))
        assert.is_false(settings:DeleteProfile("Default"))
        settings:CreateProfile("Gone", "Default")
        settings:AssignProfile("Gone")
        settings:AssignProfile("Gone", "Player-other")
        assert.is_true(settings:DeleteProfile("Gone"))
        assert.equal("Default", settings:ActiveProfile())
        assert.same({}, settings.account.assignments)
        assert.is_false(settings:AssignProfile("Gone"))
    end)

    it("announces each option that differs when the character changes profile", function()
        settings:CreateProfile("Other", "Default")
        settings.account.profiles.Other.options.toastOpacity = 0.4
        settings.account.profiles.Other.modules["quest.autoAccept"] = true
        local seen, owner = {}, {}
        R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", function(_, _, key)
            seen[#seen + 1] = key == nil and "*" or key
        end, owner)
        settings:AssignProfile("Other")
        assert.same({ "toastOpacity", "*" }, seen)
        assert.is_true(settings:Get("quest.autoAccept"))
        R.Broker:UnsubscribeAll(owner)
    end)

    it("does not announce option changes when another character changes profile", function()
        settings:CreateProfile("Other", "Default")
        settings.account.profiles.Other.options.toastOpacity = 0.4
        local seen, owner = {}, {}
        R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", function(_, _, key)
            seen[#seen + 1] = key == nil and "*" or key
        end, owner)
        settings:AssignProfile("Other", "Player-other")
        assert.same({ "*" }, seen)
        R.Broker:UnsubscribeAll(owner)
    end)
end)

describe("migration from the layered settings", function()
    local env, R, settings
    before_each(function()
        env = Runtime.new()
        R, settings = env.R, env.R.Settings
        register(R)
    end)

    it("keeps what every character resolves, across all 54 legacy combinations", function()
        local states = { "inherit", true, false }
        local checked = 0
        for _, default in ipairs({ true, false }) do
            for _, accountValue in ipairs(states) do
                for _, profileValue in ipairs(states) do
                    for _, overrideValue in ipairs(states) do
                        local account = {
                            version = 1,
                            modules = accountValue ~= "inherit" and { ["test.setting"] = accountValue } or {},
                            profiles = {
                                Test = profileValue ~= "inherit" and { ["test.setting"] = profileValue } or {},
                            },
                            assignments = { ["Player-test"] = "Test" },
                            options = {},
                        }
                        local character = {
                            overrides = overrideValue ~= "inherit" and { ["test.setting"] = overrideValue } or {},
                            scope = "character",
                        }
                        settings:RegisterDefaults("test.setting", default)
                        settings:Init(account, character, "Player-test", "Kengken")
                        local expected = default
                        if accountValue ~= "inherit" then expected = accountValue end
                        if profileValue ~= "inherit" then expected = profileValue end
                        if overrideValue ~= "inherit" then expected = overrideValue end
                        assert.equal(expected, settings:Get("test.setting"))
                        assert.is_nil(character.overrides)
                        assert.is_nil(character.scope)
                        checked = checked + 1
                    end
                end
            end
        end
        assert.equal(54, checked)
    end)

    it("turns the account layer into Default and keeps account data out of profiles", function()
        local account = {
            version = 1,
            modules = { ["loot.fast"] = false },
            options = { repairCapGold = 7, neverSellIDs = { [5] = true }, killSwitch = "ALT", toastOpacity = 0.5 },
            profiles = { Levelling = { ["quest.autoAccept"] = true } },
            assignments = { ["Player-alt"] = "Levelling" },
            classSpells = { MAGE = { 1 } },
        }
        settings:Init(account, {}, "Player-test", "Main")
        assert.equal(2, account.version)
        assert.is_nil(account.modules)
        assert.same({ "Default", "Levelling" }, settings:ProfileNames())
        assert.is_false(settings:Get("loot.fast"))
        assert.equal(7, settings:GetOption("repairCapGold"))
        assert.equal(0.5, settings:GetOption("toastOpacity"))
        assert.same({ [5] = true }, settings:GetOption("neverSellIDs"))
        assert.equal("ALT", settings:GetOption("killSwitch"))
        assert.is_nil(account.options.repairCapGold)
        assert.is_nil(account.profiles.Default.options.neverSellIDs)
        assert.same({ MAGE = { 1 } }, account.classSpells)
        settings:Init(account, {}, "Player-alt", "Alt")
        assert.equal("Levelling", settings:ActiveProfile())
        assert.is_false(settings:Get("loot.fast"))
        assert.is_true(settings:Get("quest.autoAccept"))
        assert.equal(7, settings:GetOption("repairCapGold"))
    end)

    it("renames an old profile called Default and keeps its characters on it", function()
        local account = {
            version = 1, modules = {}, options = {},
            profiles = { Default = { ["quest.autoAccept"] = true } },
            assignments = { ["Player-alt"] = "Default" },
        }
        settings:Init(account, {}, "Player-test")
        assert.same({ "Default", "Default 2" }, settings:ProfileNames())
        assert.is_false(settings:Get("quest.autoAccept"))
        settings:Init(account, {}, "Player-alt")
        assert.equal("Default 2", settings:ActiveProfile())
        assert.is_true(settings:Get("quest.autoAccept"))
    end)

    it("gives a character with its own switches a profile of its own, once", function()
        local account = {
            version = 1, modules = { ["quest.autoAccept"] = true }, options = { repairCapGold = 3 },
            profiles = {}, assignments = {},
        }
        local character = { overrides = { ["loot.fast"] = false, ["quest.autoAccept"] = true } }
        settings:Init(account, character, "Player-test", "Kengken")
        assert.equal("Kengken", settings:ActiveProfile())
        assert.is_false(settings:Get("loot.fast"))
        assert.is_true(settings:Get("quest.autoAccept"))
        assert.equal(3, settings:GetOption("repairCapGold"))
        settings:Init(account, character, "Player-test", "Kengken")
        assert.same({ "Default", "Kengken" }, settings:ProfileNames())
        settings:Init(account, {}, "Player-other", "Other")
        assert.equal("Default", settings:ActiveProfile())
        assert.is_true(settings:Get("loot.fast"))
    end)

    it("drops switches a character set to what it already had", function()
        local account = {
            version = 1, modules = { ["loot.fast"] = true }, options = {}, profiles = {}, assignments = {},
        }
        local character = { overrides = { ["loot.fast"] = true, ["quest.autoAccept"] = false } }
        settings:Init(account, character, "Player-test", "Same")
        assert.equal("Default", settings:ActiveProfile())
        assert.same({ "Default" }, settings:ProfileNames())
    end)

    it("finds a free name when the character's name is taken", function()
        local account = {
            version = 1, modules = {}, options = {}, profiles = { Kengken = {} }, assignments = {},
        }
        settings:Init(account, { overrides = { ["quest.autoAccept"] = true } }, "Player-test", "Kengken")
        assert.equal("Kengken 2", settings:ActiveProfile())
        R.L = R.L or {}
        R.L.UI_PROFILE_CHARACTER = "Character"
        settings:Init(account, { overrides = { ["quest.autoAccept"] = true } }, "Player-nameless")
        assert.equal("Character", settings:ActiveProfile())
    end)
end)

describe("profile share strings", function()
    local env, R, settings
    before_each(function()
        env = Runtime.new()
        R, settings = env.R, env.R.Settings
        register(R)
    end)

    it("carries switches and settings, nested ones included, and never account data", function()
        settings:Set("quest.autoAccept", true)
        settings:SetOption("toastOpacity", 0.35)
        settings:SetOption("tsmPriceString", "dbMarket")
        settings:SetOption("neverSellIDs", { [99] = true })
        local visibility = R.Visibility:Default()
        settings:SetOption("uiVisibility", visibility)
        local encoded = settings:ExportProfile("Default")
        assert.matches("^[A-Za-z0-9+/=]+$", encoded)
        local taken, numbered = settings:ImportProfile(encoded)
        assert.is_true(taken)
        assert.equal("Default 2", numbered)
        local ok, name = settings:ImportProfile(encoded, "Shared")
        assert.is_true(ok)
        assert.equal("Shared", name)
        local imported = settings:GetProfile("Shared")
        assert.is_true(imported.modules["quest.autoAccept"])
        assert.equal(0.35, imported.options.toastOpacity)
        assert.same(settings:GetOption("uiVisibility"), imported.options.uiVisibility)
        assert.is_nil(imported.options.neverSellIDs)
        assert.equal(encoded, settings:ExportProfile("Default"))
    end)

    it("still imports a switches-only string from 0.1.0, with default settings", function()
        local legacy = R.Codec:EncodeProfile("Old", { ["quest.autoAccept"] = true, ["loot.fast"] = false })
        settings:SetOption("repairCapGold", 5)
        local ok, name = settings:ImportProfile(legacy)
        assert.is_true(ok)
        assert.equal("Old", name)
        local imported = settings:GetProfile("Old")
        assert.same({ ["quest.autoAccept"] = true, ["loot.fast"] = false }, imported.modules)
        assert.equal(100, imported.options.repairCapGold)
    end)

    it("drops settings that fail validation and keeps the rest", function()
        local body = R.Codec:EncodeProfileData("Odd", {
            modules = { ["quest.autoAccept"] = true },
            options = { repairCapGold = -5, toastOpacity = 0.5, killSwitch = "ALT", unknownKey = 1 },
        })
        assert.is_truthy(body)
        local ok = settings:ImportProfile(body)
        assert.is_true(ok)
        local imported = settings:GetProfile("Odd")
        assert.equal(100, imported.options.repairCapGold)
        assert.equal(0.5, imported.options.toastOpacity)
        assert.is_nil(imported.options.killSwitch)
        assert.is_nil(imported.options.unknownKey)
    end)

    it("rejects malformed share strings without creating anything", function()
        local codec = R.Codec
        local bad = {
            codec:EncodeText("RF2\nX\nt1:s7:modulesb1"),
            codec:EncodeText("RF2\nX\nt9999:"),
            codec:EncodeText("RF2\nX\ns999:abc"),
            codec:EncodeText("RF2\nX\nnnan"),
            codec:EncodeText("RF2\nX\n" .. string.rep("t1:s1:a", 40) .. "b1"),
        }
        for _, payload in ipairs(bad) do
            assert.is_false(settings:ImportProfile(payload))
        end
        assert.same({ "Default" }, settings:ProfileNames())
    end)
end)
