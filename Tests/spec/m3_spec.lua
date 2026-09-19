local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local function tocFiles()
    local files = {}
    for line in assert(io.open("Refactor.toc", "r")):lines() do
        local entry = line:gsub("\\", "/"):gsub("%s+$", "")
        if entry:match("%.lua$") and entry:sub(1, 1) ~= "#" then
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

describe("first run", function()
    it("asks once per account and applies the chosen preset to account defaults", function()
        local _, R = loaded({})
        assert.is_true(R.UI.firstRunFrame:IsShown())
        local standard = R.UI.firstRunFrame.rows[2]
        assert.equal("standard", standard.preset)
        assert.matches("enables", standard.button.label:GetText())

        standard.button:GetScript("OnClick")(standard.button)
        assert.is_false(R.UI.firstRunFrame:IsShown())
        assert.is_false(R.Settings:IsFirstRun())
        assert.is_true(R.Settings:Get("vendor.autoSell"))
        assert.is_false(R.Settings:Get("nameplates.questProgress"))
        assert.equal(0, #R.errors)
    end)

    it("does not ask again once a choice is stored", function()
        local _, R = loaded({})
        R.UI.firstRunFrame.rows[1].button:GetScript("OnClick")()
        R.UI.firstRunFrame:Hide()
        assert.is_false(R.UI:ShowFirstRun())
    end)

    it("turns nothing on when the player chooses to browse", function()
        local _, R = loaded({})
        R.Presets:Apply(nil)
        for _, module in ipairs(R.modules) do
            assert.is_false(R.Settings:Get(module.id))
        end
    end)
end)

describe("automation gate", function()
    local function withAutomation()
        local env, R = loaded({})
        local _ = env
        R.Presets:Apply("full")
        local module = R:RegisterModule({
            id = "quest.testAutomation", category = "Quest", requires = {},
            tier = "standard", risk = "automation",
            name = "Auto turn in", description = "Hands quests in for you.", detail = "Hands quests in.",
        })
        R.UI.mode = "account"
        return env, R, module
    end

    it("cannot be switched on without the dialog", function()
        local _, R, module = withAutomation()
        R.UI:Cycle(module)
        assert.is_false(R.Settings:Get(module.id))
        assert.is_true(R.UI.confirmFrame:IsShown())
        assert.matches("Auto turn in", R.UI.confirmFrame.title:GetText())
        assert.matches("Ctrl", R.UI.confirmFrame.body:GetText())
    end)

    it("stays off when the dialog is cancelled", function()
        local _, R, module = withAutomation()
        R.UI:Cycle(module)
        R.UI.confirmFrame.cancel:GetScript("OnClick")()
        assert.is_false(R.Settings:Get(module.id))
        assert.is_false(R.Settings:IsConfirmed(module.id))
    end)

    it("enables after acceptance and never asks again", function()
        local _, R, module = withAutomation()
        R.UI:Cycle(module)
        R.UI.confirmFrame.accept:GetScript("OnClick")()
        assert.is_true(R.Settings:IsConfirmed(module.id))
        assert.is_true(R.Settings:Get(module.id))
        R.UI:Cycle(module)
        assert.is_false(R.Settings:Get(module.id))
        R.UI:Cycle(module)
        assert.is_true(R.Settings:Get(module.id))
        assert.is_false(R.UI.confirmFrame:IsShown())
    end)

    it("is never a member of any preset", function()
        local _, R, module = withAutomation()
        for _, preset in ipairs(R.Presets.order) do
            assert.is_false(R.Presets:Includes(preset, module))
        end
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
        R.Presets:Apply("full")
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
        R.Presets:Apply("full")
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
        R.Presets:Apply("minimal")
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
