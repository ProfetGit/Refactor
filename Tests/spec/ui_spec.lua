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

local function loaded()
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
    return env, R
end

describe("sidebar groups", function()
    it("cover every category a module can be listed under", function()
        local _, R = loaded()
        local covered = {}
        for _, entry in ipairs(R.UI.sidebar) do
            for category in pairs(entry.set or {}) do covered[category] = true end
        end
        for _, module in ipairs(R.modules) do
            assert.is_true(covered[R.UI:Category(module)], module.id .. " is in no sidebar group")
        end
    end)

    it("list every module of their categories and nothing else", function()
        local _, R = loaded()
        local total = 0
        for _, entry in ipairs(R.UI.sidebar) do
            if entry.set then
                for _, module in ipairs(R.modules) do
                    local listed = R.UI:Matches(module, "", entry.set)
                    assert.equal(entry.set[R.UI:Category(module)] == true, listed)
                    if listed then total = total + 1 end
                end
            end
        end
        assert.equal(#R.modules, total)
    end)

    it("have no empty groups and fewer entries than categories", function()
        local _, R = loaded()
        local groups = 0
        for _, entry in ipairs(R.UI.sidebar) do
            if entry.set then
                groups = groups + 1
                local count = 0
                for _, module in ipairs(R.modules) do
                    if R.UI:Matches(module, "", entry.set) then count = count + 1 end
                end
                assert.is_true(count > 0, entry.key .. " lists nothing")
            end
        end
        assert.is_true(#R.UI.sidebar <= 10)
        assert.is_true(groups >= 3)
    end)

    it("keep search global regardless of the selected group", function()
        local _, R = loaded()
        local module = R.moduleByID["loot.fastLoot"]
        assert.is_true(R.UI:Matches(module, "fast", { Tooltips = true }))
        assert.is_false(R.UI:Matches(module, "", { Tooltips = true }))
        assert.is_true(R.UI:Matches(module, "", "Loot"))
    end)
end)

describe("window chrome", function()
    it("selects exactly one sidebar row and shows the tabs only on the feature list", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        local function selectedCount()
            local count = 0
            for _, button in ipairs(UI.categoryButtons) do
                if button.selected then count = count + 1 end
            end
            return count
        end
        assert.equal(1, selectedCount())
        assert.is_true(UI.modeCharacter.selected)
        assert.is_false(UI.modeAccount.selected)
        assert.is_true(UI.modeCharacter:IsShown())
        UI.modeAccount:GetScript("OnClick")(UI.modeAccount)
        assert.is_true(UI.modeAccount.selected)
        assert.is_false(UI.modeCharacter.selected)
        UI:SelectCategory("Profiles")
        assert.equal(1, selectedCount())
        assert.is_false(UI.modeCharacter:IsShown())
        assert.is_true(UI.panelTitle:IsShown())
        assert.equal(R.L.UI_PROFILES, UI.panelTitle:GetText())
        UI:SelectCategory("All")
        assert.is_true(UI.modeCharacter:IsShown())
        assert.is_false(UI.panelTitle:IsShown())
    end)

    it("reports only warning states in the meta slot, never Active or a category", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        for _, row in ipairs(UI.rows) do
            local text = row.meta:GetText()
            assert.is_not.equal("Active", text)
            assert.is_not.equal("Vendor", text)
        end
    end)

    it("shows undo only while the value differs from what it would inherit", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        local row = UI.rows[1]
        assert.is_false(row.undo:IsShown())
        R.Settings:SetOverride(row.module.id, true)
        UI:Refresh()
        assert.is_true(row.undo:IsShown())
        row.undo:GetScript("OnClick")(row.undo)
        assert.is_nil(R.Settings:GetOverride(row.module.id))
        assert.is_false(row.undo:IsShown())
    end)

    it("stacks every options section on one page with a known height", function()
        local _, R = loaded()
        local UI = R.UI
        UI:SelectCategory("Options")
        assert.is_true(UI.options:IsShown())
        assert.is_nil(UI.panels.Display)
        assert.is_nil(UI.panels.TooltipOptions)
        assert.is_true(UI.options.contentHeight > 600)
        assert.is_table(UI.toastQualityButton)
        assert.is_table(UI.tooltipModeButton)
        assert.is_table(UI.nameplateButtons[1])
    end)
end)

describe("three-slice buttons", function()
    local Theme
    before_each(function()
        local _, R = loaded()
        Theme = R.Theme
    end)

    it("scale the caps by height and keep their aspect when they fit", function()
        local left, right, leftKept, rightKept = Theme:SliceWidths(200, 32,
            { width = 114, height = 128 }, { width = 292, height = 128 })
        assert.equal(28.5, left)
        assert.equal(73, right)
        assert.equal(1, leftKept)
        assert.equal(1, rightKept)
    end)

    it("trim the wider cap first when both cannot fit", function()
        local left, right, leftKept, rightKept = Theme:SliceWidths(44, 22,
            { width = 114, height = 128 }, { width = 292, height = 128 })
        assert.is_true(math.abs(left + right - 44) < 0.001)
        assert.equal(1, leftKept)
        assert.is_true(rightKept < 1 and rightKept > 0)
    end)

    it("fall back to fixed caps without atlas information", function()
        local left, right, leftKept, rightKept = Theme:SliceWidths(72, 22, nil, nil)
        assert.equal(8, left)
        assert.equal(8, right)
        assert.equal(1, leftKept)
        assert.equal(1, rightKept)
    end)
end)

describe("smooth scrolling", function()
    local function scroller()
        local env, R = loaded()
        local parent = env.CreateFrame("Frame")
        return R.UI.Widgets:Scroll(parent)
    end

    it("closes the gap to the target and then stops running", function()
        local scroll = scroller()
        scroll:ScrollTo(200)
        local step = scroll:GetScript("OnUpdate")
        assert.is_function(step)
        local previous = 0
        for _ = 1, 60 do
            if not scroll:GetScript("OnUpdate") then break end
            step(scroll, 1 / 60)
            assert.is_true(scroll.offset > previous)
            assert.is_true(scroll.offset <= 200)
            previous = scroll.offset
        end
        assert.are.equal(200, scroll.offset)
        assert.is_nil(scroll:GetScript("OnUpdate"))
    end)

    it("retargets mid-glide instead of queueing a second scroll", function()
        local scroll = scroller()
        scroll:ScrollTo(200)
        local step = scroll:GetScript("OnUpdate")
        step(scroll, 1 / 60)
        scroll:ScrollTo(80)
        assert.are.equal(80, scroll.target)
        for _ = 1, 60 do
            if not scroll:GetScript("OnUpdate") then break end
            scroll:GetScript("OnUpdate")(scroll, 1 / 60)
        end
        assert.are.equal(80, scroll.offset)
    end)

    it("snaps without animating when the move is direct manipulation", function()
        local scroll = scroller()
        scroll:ScrollTo(140, true)
        assert.are.equal(140, scroll.offset)
        assert.is_nil(scroll:GetScript("OnUpdate"))
    end)
end)
