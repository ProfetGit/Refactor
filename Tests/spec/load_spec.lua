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

describe("the real load sequence", function()
    it("loads every TOC file, logs in, and opens the window", function()
        local env = Runtime.new()
        Widgets.install(env)
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
        assert.is_table(env.LibStub)
        assert.equal(21, #R.modules)
        env:Fire("PLAYER_LOGIN")
        assert.is_function(env.SlashCmdList.REFACTOR)
        assert.is_table(R.UI.frame)
        assert.is_false(R.UI.frame:IsShown())
        env.SlashCmdList.REFACTOR("")
        assert.is_true(R.UI.frame:IsShown())
        env.SlashCmdList.REFACTOR("")
        assert.is_false(R.UI.frame:IsShown())
    end)

    it("walks every category, detail panel and option without an error", function()
        local env = Runtime.new()
        Widgets.install(env)
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
        local UI = R.UI
        UI:Toggle()
        local optionsButton
        for _, button in ipairs(UI.categoryButtons) do
            button:GetScript("OnClick")(button)
            if button.category == "Options" then optionsButton = button end
        end
        assert.is_true(UI.panels.Diagnostics:IsShown())
        optionsButton:GetScript("OnClick")(optionsButton)
        assert.is_true(UI.options:IsShown())
        UI:SaveOptions()
        UI.modifierButton:GetScript("OnClick")(UI.modifierButton)
        -- No GameTooltip in this environment, so the hover detail must degrade to a no-op
        -- while the text it would show is still built for every module.
        for _, module in ipairs(R.modules) do
            local title, body = UI:DetailText(module)
            assert.is_string(title)
            assert.is_true(#body > #title)
            UI:ShowDetails(module)
        end
        -- WoW updates the checkbox state before invoking its click handler.
        for _, row in ipairs(UI.rows) do
            row.toggle:SetChecked(true)
            row.toggle:GetScript("OnClick")(row.toggle)
        end
        assert.is_true(R.Settings:Get("loot.fastLoot"))
        -- This environment stubs no gameplay API, so turning everything on must end in
        -- "unavailable" with the missing symbols named, never in "failed".
        for _, module in ipairs(R.modules) do
            assert.is_not.equal("failed", module.state)
        end
        assert.equal("unavailable", R.moduleByID["loot.fastLoot"].state)
        assert.same({ "C_CVar.GetCVarBool", "C_CVar.SetCVar", "C_CVar.GetCVarDefault", "IsModifiedClick",
            "GetNumLootItems", "GetLootSlotInfo", "LootSlot" }, R.moduleByID["loot.fastLoot"].missing)
        assert.equal(0, #R.errors)
    end)
end)
