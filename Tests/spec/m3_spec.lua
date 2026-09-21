local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local function tocFiles()
    local files = {}
    for line in assert(io.open("Refactor.toc", "r")):lines() do
        local entry = line:gsub("\\", "/"):gsub("%s+$", "")
        -- Restore.lua is a local capture of one client's saved variables, not addon code.
        if entry:match("%.lua$") and entry:sub(1, 1) ~= "#" and entry ~= "Restore.lua" then
            files[#files + 1] = entry
        end
    end
    return files
end

local function loaded(addons)
    local env = Runtime.new()
    Widgets.install(env)
    env.C_AddOns = { IsAddOnLoaded = function(name) return addons[name] == true end }
    env.C_QuestLog = { UnitIsRelatedToActiveQuest = function() return false end }
    env.C_TooltipInfo = { GetUnit = function() return nil end }
    env.C_NamePlate = { GetNamePlateForUnit = function() return nil end }
    env.Enum = { TooltipDataLineType = { QuestTitle = 17, QuestObjective = 8, QuestPlayer = 18 } }
    local R
    for _, path in ipairs(tocFiles()) do
        if path:match("^Libs/LibStub/") then
            local chunk = assert(loadfile(path))
            setfenv(chunk, env)
            chunk()
        else
            R = env:Load(path)
        end
    end
    env:Fire("PLAYER_LOGIN")
    return env, R
end

local function enableAll(R)
    for _, module in ipairs(R.modules) do
        R.Settings:SetAccount(module.id, true)
    end
end

describe("defaults", function()
    it("starts with no first-run screen and the declared defaults on", function()
        local _, R = loaded({})
        assert.is_nil(R.UI.firstRunFrame)
        assert.is_true(R.Settings:Get("vendor.autoSell"))
        assert.is_false(R.Settings:Get("quest.autoAccept"))
        assert.equal(0, #R.errors)
    end)

    it("never turns automation on by default", function()
        local _, R = loaded({})
        for _, module in ipairs(R.modules) do
            if module.risk == "automation" then
                assert.is_false(R.Settings:Get(module.id), module.id)
            end
        end
    end)
end)

describe("automation gate", function()
    local function withAutomation()
        local env, R = loaded({})
        local _ = env
        local module = R:RegisterModule({
            id = "quest.testAutomation", category = "Quest", requires = {},
            risk = "automation",
            name = "Auto turn in", description = "Hands quests in for you.", detail = "Hands quests in.",
        })
        R.UI.mode = "account"
        return env, R, module
    end

    it("switches on and off without a dialog", function()
        local _, R, module = withAutomation()
        R.UI:Cycle(module)
        assert.is_true(R.Settings:Get(module.id))
        R.UI:Cycle(module)
        assert.is_false(R.Settings:Get(module.id))
    end)

    it("lists under its own category, not a separate Automation one", function()
        local _, R, module = withAutomation()
        assert.equal("Quest", R.UI:Category(module))
        assert.is_true(R.UI:Matches(module, "", "Quest"))
        assert.is_false(R.UI:Matches(module, "", "Automation"))
        for _, entry in ipairs(R.UI.sidebar) do
            assert.is_not.equal("Automation", entry.key)
        end
    end)
end)

describe("conflict panel", function()
    it("names the neighbour, the feature, and offers to switch ours off", function()
        local _, R = loaded({ Leatrix_Plus = true })
        enableAll(R)
        R.UI.category = "Conflicts"
        R.UI:LoadConflicts()
        local row = R.UI.conflictRows[1]
        assert.is_true(row:IsShown())
        assert.matches("Leatrix Plus", row.title:GetText())
        assert.is_true(R.Settings:Get(row.moduleID))
        row.resolve:GetScript("OnClick")(row.resolve)
        assert.is_false(R.Settings:Get(row.moduleID))
    end)

    it("lists Plumber against the merchant costs module", function()
        local _, R = loaded({ Plumber = true })
        R.UI:LoadConflicts()
        local row = R.UI.conflictRows[1]
        assert.is_true(row:IsShown())
        assert.matches("Plumber", row.title:GetText())
        assert.equal("vendor.itemCosts", row.moduleID)
    end)

    it("shows nothing when no neighbour is installed", function()
        local _, R = loaded({})
        R.UI:LoadConflicts()
        assert.is_true(R.UI.conflictEmpty:IsShown())
        assert.is_false(R.UI.conflictRows[1]:IsShown())
    end)

    it("reports a nameplate neighbour as already handling it", function()
        local _, R = loaded({ Plater = true })
        enableAll(R)
        R.Registry:ReconcileAll()
        R.UI:LoadConflicts()
        local module = R.moduleByID["nameplates.questProgress"]
        -- Deference happens at enable, so the panel can quote the module's own reason.
        assert.equal("unavailable", module.state)
        assert.matches("Plater", R.UI.conflictRows[1].detail:GetText())
        assert.matches("Plater", R.UI.conflictRows[1].title:GetText())
    end)
end)

describe("settings blocks", function()
    it("use checkboxes that reflect and write the stored option", function()
        local _, R = loaded({})
        R.UI:RefreshNameplateOptions()
        local box = R.UI.nameplateButtons[1]
        assert.equal("nameplateShowRing", box.optionKey)
        assert.is_true(box:GetChecked())

        box:SetChecked(false)
        box:GetScript("OnClick")(box)
        assert.is_false(R.Settings:GetOption("nameplateShowRing"))

        box:SetChecked(true)
        box:GetScript("OnClick")(box)
        assert.is_true(R.Settings:GetOption("nameplateShowRing"))
    end)

    it("reports art the client did not recognise", function()
        local _, R = loaded({})
        R.Theme.missingAtlases["not-a-real-atlas"] = true
        R.UI:LoadDiagnostics()
        assert.matches("not%-a%-real%-atlas", R.UI.diagArt:GetText())
        R.Theme.missingAtlases["not-a-real-atlas"] = nil
    end)
end)

describe("diagnostics panel", function()
    it("shows a state for every module and counts recorded errors", function()
        local _, R = loaded({})
        R.Registry:ReconcileAll()
        R:RecordError({ id = "loot.fastLoot" }, "boom", "OnEnable")
        R.UI:LoadDiagnostics()
        assert.equal(#R.modules, #R.UI.statusRows)
        assert.matches("Recorded errors: 1", R.UI.errorCount:GetText())
        for _, row in ipairs(R.UI.statusRows) do
            assert.is_true(#row.state:GetText() > 0)
        end
    end)
end)
