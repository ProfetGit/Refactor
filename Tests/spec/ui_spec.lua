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

    it("have no empty groups and one entry per category, never a stack of them", function()
        local _, R = loaded()
        local groups, categories = 0, {}
        for _, module in ipairs(R.modules) do categories[R.UI:Category(module)] = true end
        local expected = 0
        for _ in pairs(categories) do expected = expected + 1 end
        for _, entry in ipairs(R.UI.sidebar) do
            if entry.set then
                groups = groups + 1
                local count, listed = 0, 0
                for _ in pairs(entry.set) do listed = listed + 1 end
                assert.equal(1, listed, entry.key .. " stacks categories")
                for _, module in ipairs(R.modules) do
                    if R.UI:Matches(module, "", entry.set) then count = count + 1 end
                end
                assert.is_true(count > 0, entry.key .. " lists nothing")
            end
        end
        assert.equal(expected, groups)
    end)

    it("head every visible block with its category", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        local seen = 0
        for _, category in ipairs(UI.categories) do
            local header, last = UI.sections[category], nil
            assert.is_true(header:IsShown(), category .. " has no heading")
            assert.equal(R.L["UI_" .. category], header.title:GetText())
            for _, row in ipairs(UI.sectionRows[category]) do
                if row:IsShown() then last = row; seen = seen + 1 end
            end
            -- General is the one section carrying settings instead of features, so it is
            -- headed by its own block rather than by rows.
            local block = UI.sectionBlocks[category]
            assert.is_true(last ~= nil or (block ~= nil and block:IsShown()),
                category .. " has a heading but nothing under it")
        end
        assert.equal(#R.modules, seen)
    end)

    it("jump to a section rather than filtering the list down to it", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        for _, entry in ipairs(UI.sidebar) do
            assert.is_not.equal("All", entry.key)
        end
        assert.equal(UI.categories[1], UI.category)
        UI:SelectCategory("Vendor")
        assert.equal("Vendor", UI.category)
        for _, category in ipairs(UI.categories) do
            assert.is_true(UI.sections[category]:IsShown(), category .. " was hidden by a jump")
        end
        -- A jump stops short of the heading by the lead-in, so no heading lands against
        -- the border, and the sidebar still counts the section as arrived at.
        local vendor = UI.scroll.slider:GetValue()
        assert.is_true(vendor < UI.sectionOffset.Vendor)
        UI.scroll.onScroll(vendor)
        assert.equal("Vendor", UI.category)
        -- The tail past the last section is what lets it reach the top of the view: without
        -- it the bottom half of the sidebar would all land on the same scroll position.
        local last = UI.categories[#UI.categories]
        UI:SelectCategory(last)
        assert.is_true(UI.sectionOffset[last] > 0)
        UI.scroll.onScroll(UI.scroll.slider:GetValue())
        assert.equal(last, UI.category)
        -- Scrolling moves the sidebar with the view, not with the last click.
        UI.scroll.onScroll(0)
        assert.equal(UI.categories[1], UI.category)
        UI.scroll.onScroll(UI.sectionOffset.Vendor)
        assert.equal("Vendor", UI.category)
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
    it("selects exactly one sidebar row and keeps the scope switch out of the feature list", function()
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
        assert.equal("character", UI.mode)
        assert.equal("", UI.help:GetText())
        UI:SelectCategory("General")
        assert.equal(1, selectedCount())
        assert.is_true(UI.general:IsShown())
        assert.equal(R.L.UI_SCOPE, UI.scopeDropdown.label:GetText())
        assert.equal(R.L.UI_CHARACTER, UI.scopeDropdown.button:GetDefaultText())
        -- Opening the menu runs the real generator, so the entries and the setter behind
        -- them are exercised rather than assumed.
        local entries = UI.scopeDropdown.button:OpenMenu()
        assert.equal(2, #entries)
        assert.is_true(entries[1].selected)
        for _, entry in ipairs(entries) do
            if entry.value == "account" then entry.choose() end
        end
        assert.equal("account", UI.mode)
        assert.equal(R.L.UI_ACCOUNT, UI.scopeDropdown.button:GetDefaultText())
        UI:SelectCategory("Profiles")
        assert.equal(1, selectedCount())
        assert.is_true(UI.panelTitle:IsShown())
        assert.equal(R.L.UI_PROFILES, UI.panelTitle:GetText())
        UI:SelectCategory("Vendor")
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
        R.Settings:SetOverride(row.module.id, R.Settings:GetInherited(row.module.id))
        UI:Refresh()
        assert.is_false(row.undo:IsShown())
    end)

    it("toggles from the checkbox alone and lights the whole row while hovered", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        local row = UI.rows[1]
        local before = R.Settings:Get(row.module.id)
        -- WoW updates the tick before calling the handler, as the row does on Refresh.
        row.toggle:SetChecked(not before)
        row.toggle:GetScript("OnClick")(row.toggle)
        assert.equal(not before, R.Settings:Get(row.module.id))
        row.toggle:SetChecked(before)
        row.toggle:GetScript("OnClick")(row.toggle)
        assert.equal(before, R.Settings:Get(row.module.id))
        -- The rest of the row opens settings, so it must never flip the feature itself.
        row:GetScript("OnClick")(row)
        assert.equal(before, R.Settings:Get(row.module.id))
        -- The wash is one alpha animation on the row, not a texture per child. Headless
        -- animations never finish on their own, so the spec settles them by hand.
        local function settle(fader)
            fader.group:GetScript("OnFinished")(fader.group)
        end
        row:GetScript("OnEnter")(row)
        assert.equal(1, row.hover.to)
        settle(row.hover)
        -- Crossing into a child of the row is not leaving it: the checkbox now takes a
        -- mouse of its own, so it has to hold the highlight the way undo always did.
        for _, child in ipairs({ row.undo, row.toggle, row.chevron }) do
            child:GetScript("OnEnter")(child)
            assert.equal(1, row.hover.to)
        end
        row:GetScript("OnLeave")(row)
        assert.equal(0, row.hover.to)
        settle(row.hover)
        row.undo:GetScript("OnLeave")(row.undo)
        assert.equal(0, row.hover.to)
    end)

    it("refuses a row click while the toggle is unavailable", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        local row = UI.rows[1]
        local before = R.Settings:Get(row.module.id)
        row.toggle:SetEnabled(false)
        row.toggle:GetScript("OnClick")(row.toggle)
        assert.equal(before, R.Settings:Get(row.module.id))
    end)

    it("opens a feature's settings under its own row, one at a time", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        assert.is_nil(UI.panels.Options)
        assert.is_nil(UI.panels.Display)
        assert.is_nil(UI.panels.TooltipOptions)
        -- Every block that has an owner is reachable from that owner's row.
        for id in pairs(UI.moduleSettings) do
            assert.is_table(R.moduleByID[id], id .. " owns a settings block but is not a module")
        end
        local function rowFor(id)
            for _, row in ipairs(UI.rows) do
                if row.module.id == id then return row end
            end
        end
        -- Headless nothing drives OnUpdate, so the spec runs the animation out by hand:
        -- one step past its 150 ms and the block is wherever it was heading.
        local function settle(block)
            local step = block:GetScript("OnUpdate")
            if step then step(block, 1) end
        end
        local toastRow, gossipRow = rowFor("toasts.loot"), rowFor("quest.autoGossip")
        local toasts, gossip = UI.moduleSettings["toasts.loot"], UI.moduleSettings["quest.autoGossip"]
        assert.is_true(toastRow.chevron:IsShown())
        assert.is_false(toasts:IsShown())
        -- Clicking the row opens the block; only the checkbox flips the feature itself.
        toastRow:GetScript("OnClick")(toastRow)
        assert.equal("toasts.loot", UI.expanded)
        assert.is_true(toasts:IsShown())
        assert.is_table(UI.toastQualityDropdown)
        settle(toasts)
        assert.is_nil(toasts:GetScript("OnUpdate"), "the expand animation left its handler on")
        -- One at a time: the blocks are tall enough that two open leaves nothing scannable.
        gossipRow.chevron:GetScript("OnClick")(gossipRow.chevron)
        assert.equal("quest.autoGossip", UI.expanded)
        assert.is_false(toasts:IsShown())
        assert.is_true(gossip:IsShown())
        settle(gossip)
        -- A collapse keeps the block laid out while it plays, and takes it out at the end.
        gossipRow.chevron:GetScript("OnClick")(gossipRow.chevron)
        assert.is_nil(UI.expanded)
        assert.equal("quest.autoGossip", UI.collapsing)
        assert.is_true(gossip:IsShown())
        settle(gossip)
        assert.is_nil(UI.collapsing)
        assert.is_nil(gossip:GetScript("OnUpdate"), "the collapse animation left its handler on")
        assert.is_false(gossip:IsShown())
        -- A feature with no settings of its own gets no chevron to click.
        assert.is_false(rowFor("loot.fastLoot").chevron:IsShown())
        for _, entry in ipairs(UI.gossipLearnDropdown.button:OpenMenu()) do
            if entry.value == "ALT" then entry.choose() end
        end
        assert.equal("ALT", R.Settings:GetOption("gossipLearnModifier"))
        assert.equal(R.L.UI_ALT, UI.gossipLearnDropdown.button:GetDefaultText())
        R.Settings:SetOption("gossipLearned", { Creature = { [1] = 2 } })
        UI:LoadDisplay()
        assert.is_truthy(UI.gossipForgetButton.label:GetText():find("(1)", 1, true))
        UI.gossipForgetButton:GetScript("OnClick")(UI.gossipForgetButton)
        assert.same({}, R.Settings:GetOption("gossipLearned"))
    end)

    it("camera block lists the profiles, locks the built-in ones, and edits a copy", function()
        local _, R = loaded()
        local UI, Settings, Profiles = R.UI, R.Settings, R.CameraProfiles
        UI:Toggle()
        UI:ToggleExpanded("interface.actionCam")
        assert.is_true(UI.moduleSettings["interface.actionCam"]:IsShown())
        local entries = UI.cameraProfileDropdown.button:OpenMenu()
        assert.equal(#Profiles.builtIn, #entries)
        assert.equal(R.L.CAMERA_PROFILE_IMMERSIVE, UI.cameraProfileDropdown.button:GetDefaultText())
        for _, slider in ipairs(UI.cameraSliders) do
            assert.is_false(slider.slider:IsEnabled(), "a built-in profile's slider is live")
        end
        assert.is_false(UI.cameraDelete:IsEnabled())
        -- A copy under a new name is selected and unlocked.
        UI.cameraName:SetText("Mine")
        UI.cameraSaveCopy:GetScript("OnClick")(UI.cameraSaveCopy)
        assert.equal("custom:Mine", Settings:GetOption("cameraProfile"))
        assert.equal(#Profiles.builtIn + 1, #UI.cameraProfileDropdown.button:OpenMenu())
        assert.equal("Mine", UI.cameraProfileDropdown.button:GetDefaultText())
        assert.is_true(UI.cameraDelete:IsEnabled())
        local shoulder, situationZoom
        for _, slider in ipairs(UI.cameraSliders) do
            assert.is_true(slider.slider:IsEnabled())
            if slider.spec.key == "shoulder" then shoulder = slider end
            if slider.spec.suffix == "Zoom" then situationZoom = slider end
        end
        shoulder.slider:GetScript("OnValueChanged")(shoulder.slider, 1.2)
        assert.equal(1.2, Settings:GetOption("cameraProfiles").Mine.shoulder)
        assert.equal("1.2 right", shoulder.valueText:GetText())
        -- The situation dropdown swaps which field the two sliders under it show.
        assert.equal("3 yards closer", situationZoom.valueText:GetText())
        for _, entry in ipairs(UI.cameraSituationDropdown.button:OpenMenu()) do
            if entry.value == "mounted" then entry.choose() end
        end
        assert.equal("6 yards further", situationZoom.valueText:GetText())
        situationZoom.slider:GetScript("OnValueChanged")(situationZoom.slider, -2)
        assert.equal(-2, Settings:GetOption("cameraProfiles").Mine.mountedZoom)
        -- Export fills the box; importing the same string is a name clash, so it is
        -- imported under the built-in's name instead and selected.
        UI.cameraExport:GetScript("OnClick")(UI.cameraExport)
        assert.is_true(#UI.cameraString:GetText() > 0)
        assert.equal(R.L.UI_CAMERA_EXPORTED, UI.cameraStatus:GetText())
        UI.cameraImport:GetScript("OnClick")(UI.cameraImport)
        assert.equal(R.L.UI_CAMERA_ERR_profile_exists, UI.cameraStatus:GetText())
        Profiles:Select("immersive")
        UI:LoadCamera()
        UI.cameraExport:GetScript("OnClick")(UI.cameraExport)
        UI.cameraImport:GetScript("OnClick")(UI.cameraImport)
        assert.equal("custom:" .. R.L.CAMERA_PROFILE_IMMERSIVE, Settings:GetOption("cameraProfile"))
        assert.equal("", UI.cameraString:GetText())
        UI.cameraDelete:GetScript("OnClick")(UI.cameraDelete)
        assert.equal("immersive", Settings:GetOption("cameraProfile"))
        assert.is_nil(Settings:GetOption("cameraProfiles")[R.L.CAMERA_PROFILE_IMMERSIVE])
        -- Garbage in the box is refused in words.
        UI.cameraString:SetText("not a profile")
        UI.cameraImport:GetScript("OnClick")(UI.cameraImport)
        assert.equal(R.L.UI_CAMERA_ERR_invalid_encoding, UI.cameraStatus:GetText())
    end)

    it("puts every numeric option on a slider the validator accepts end to end", function()
        local _, R = loaded()
        local UI, Settings = R.UI, R.Settings
        UI:Toggle()
        assert.is_true(#UI.optionSliders > 0)
        for _, slider in ipairs(UI.optionSliders) do
            local spec = slider.spec
            local low, high = slider.slider:GetMinMaxValues()
            assert.equal(spec.minimum, low)
            assert.equal(spec.maximum, high)
            -- Every position the track can reach has to be a value Settings will store, or
            -- dragging to one end would silently do nothing.
            local value = low
            while value <= high + 0.000001 do
                local stored = spec.store and spec.store(value) or value
                assert.is_true(Settings:SetOption(spec.key, stored),
                    spec.key .. " refused " .. tostring(stored))
                value = value + spec.step
            end
            -- And what is stored has to come back as the same position on the track.
            local shown = spec.show and spec.show(Settings:GetOption(spec.key))
                or Settings:GetOption(spec.key)
            assert.equal(high, shown)
            Settings:SetOption(spec.key, Settings.optionDefaults[spec.key])
        end
    end)

    it("writes a dragged slider through, and undoes it back to the default", function()
        local _, R = loaded()
        local UI, Settings = R.UI, R.Settings
        UI:Toggle()
        local opacity
        for _, slider in ipairs(UI.optionSliders) do
            if slider.spec.key == "farmOpacity" then opacity = slider end
        end
        assert.is_table(opacity)
        -- Stored as a factor, shown as a percentage, the way Blizzard shows a scale.
        opacity.slider:GetScript("OnValueChanged")(opacity.slider, 50)
        assert.equal(0.5, Settings:GetOption("farmOpacity"))
        assert.equal("50%", opacity.valueText:GetText())
        assert.is_true(opacity.undo:IsShown())
        opacity.onUndo()
        assert.equal(Settings.optionDefaults.farmOpacity, Settings:GetOption("farmOpacity"))
        assert.is_false(opacity.undo:IsShown())
        -- Writing a value back in must not read as the player moving it, or a refresh
        -- would write the setting again on every pass.
        local writes = 0
        local real = Settings.SetOption
        Settings.SetOption = function(...) writes = writes + 1; return real(...) end
        UI:LoadDisplay()
        Settings.SetOption = real
        assert.equal(0, writes)
    end)

    it("puts every named choice on a dropdown that reports and writes its setting", function()
        local _, R = loaded()
        local UI, Settings = R.UI, R.Settings
        UI:Toggle()
        assert.is_true(#UI.optionDropdowns > 0)
        for _, dropdown in ipairs(UI.optionDropdowns) do
            local entries = dropdown.button:OpenMenu()
            assert.equal(#dropdown.entryList, #entries)
            local selected = 0
            for _, entry in ipairs(entries) do
                if entry.selected then selected = selected + 1 end
            end
            assert.equal(1, selected, dropdown.optionKey .. " has no one selected entry")
            -- Every entry the menu offers has to be a value Settings will store.
            for _, entry in ipairs(entries) do
                entry.choose()
                assert.equal(entry.value, Settings:GetOption(dropdown.optionKey),
                    dropdown.optionKey .. " refused " .. tostring(entry.value))
                assert.equal(entry.text, dropdown.button:GetDefaultText())
            end
            Settings:SetOption(dropdown.optionKey, Settings.optionDefaults[dropdown.optionKey])
        end
    end)

    it("falls back to a stepped button when the client has no dropdown template", function()
        local env, R = loaded()
        local Theme = env.LibStub("LibRefactorTheme-1.0")
        local template = Theme.dropdownTemplate
        Theme.dropdownTemplate = nil
        local chosen = "SHIFT"
        local entries = {
            { value = "CTRL", text = "Ctrl" }, { value = "SHIFT", text = "Shift" },
            { value = "ALT", text = "Alt" },
        }
        local dropdown = Theme:Dropdown(env.CreateFrame("Frame"), 380, entries,
            function(value) return chosen == value end,
            function(value) chosen = value end)
        Theme.dropdownTemplate = template
        -- No menu to open, so the same surface has to step through the entries and wrap.
        -- (Every mock frame answers SetupMenu, so the fallback is told apart by behaviour.)
        assert.is_function(dropdown.button:GetScript("OnClick"))
        dropdown.button:GetScript("OnClick")(dropdown.button)
        assert.equal("ALT", chosen)
        dropdown.button:GetScript("OnClick")(dropdown.button)
        assert.equal("CTRL", chosen)
        dropdown:SetValueText("Ctrl")
        assert.equal("Ctrl", dropdown.button:GetDefaultText())
        assert.is_table(R.UI.optionDropdowns)
    end)

    it("swaps the tooltip placement list with the anchor mode", function()
        local _, R = loaded()
        local UI, Settings = R.UI, R.Settings
        UI:Toggle()
        Settings:SetOption("tooltipAnchor", "cursor")
        UI:LoadTooltips()
        assert.equal(R.L.UI_TOOLTIP_CURSOR_SIDE, UI.tooltipPointDropdown.label:GetText())
        assert.equal(3, #UI.tooltipPointDropdown.button:OpenMenu())
        Settings:SetOption("tooltipAnchor", "point")
        UI:LoadTooltips()
        assert.equal(R.L.UI_TOOLTIP_POINT, UI.tooltipPointDropdown.label:GetText())
        local entries = UI.tooltipPointDropdown.button:OpenMenu()
        assert.equal(9, #entries)
        -- The one dropdown writes whichever placement setting the mode is using.
        for _, entry in ipairs(entries) do
            if entry.value == "TOPLEFT" then entry.choose() end
        end
        assert.equal("TOPLEFT", Settings:GetOption("tooltipPoint"))
        assert.equal("RIGHT", Settings:GetOption("tooltipCursorSide"))
    end)

    it("reaches a setting by name and opens the block holding it", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        -- "Repair limit" is on no row: without the block index the only way to it is to
        -- already know Auto repair owns it.
        UI.search:SetText("repair limit")
        UI:Refresh()
        assert.is_true(UI.moduleSettings["vendor.autoRepair"]:IsShown())
        for _, row in ipairs(UI.rows) do
            if row.module.id == "vendor.autoRepair" then assert.is_true(row:IsShown()) end
        end
        -- General is a section of the list, so a query that reaches none of it hides it.
        assert.is_false(UI.general:IsShown())
        UI.search:SetText("")
        UI:Refresh()
        assert.is_true(UI.general:IsShown())
        assert.is_false(UI.moduleSettings["vendor.autoRepair"]:IsShown())
    end)
end)

describe("hairlines", function()
    it("are one physical pixel tall and land on whole pixels", function()
        local env = loaded()
        local Theme = env.LibStub("LibRefactorTheme-1.0")
        local frame = env.CreateFrame("Frame")
        -- 1080 physical rows over the client's 768 unit screen, at scale 1.
        local pixel = Theme:PixelSize(frame)
        assert.is_true(math.abs(pixel - 768 / 1080) < 1e-9)
        for _, value in ipairs({ 0, 17, 34.5, -102, 1093.7 }) do
            local snapped = Theme:Snap(frame, value)
            assert.is_true(math.abs(snapped - value) <= pixel / 2 + 1e-9)
            local steps = snapped / pixel
            assert.is_true(math.abs(steps - math.floor(steps + 0.5)) < 1e-9)
        end
    end)

    it("fall back to one unit when the client cannot say how big a pixel is", function()
        local env = loaded()
        local Theme = env.LibStub("LibRefactorTheme-1.0")
        local frame = env.CreateFrame("Frame")
        local screen = env.GetPhysicalScreenSize
        env.GetPhysicalScreenSize = function() return 0, 0 end
        assert.equal(1, Theme:PixelSize(frame))
        assert.equal(42, Theme:Snap(frame, 42))
        env.GetPhysicalScreenSize = screen
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
