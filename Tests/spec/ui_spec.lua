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
    -- The one symbol the vendor summary asks for, so at least one row is plainly available:
    -- the scope specs need a row with nothing in its warning slot.
    env.C_CurrencyInfo = { GetCoinTextureString = function(amount) return tostring(amount) end }
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
        assert.equal("account", UI.mode)
        assert.equal("", UI.help:GetText())
        UI:SelectCategory("General")
        assert.equal(1, selectedCount())
        assert.is_true(UI.general:IsShown())
        assert.equal(R.L.UI_SCOPE, UI.scopeDropdown.label:GetText())
        assert.equal(R.L.UI_ACCOUNT, UI.scopeDropdown.button:GetDefaultText())
        -- Opening the menu runs the real generator, so the entries and the setter behind
        -- them are exercised rather than assumed.
        -- With no profile assigned there are two layers, and the account one is selected.
        local entries = UI.scopeDropdown.button:OpenMenu()
        assert.equal(2, #entries)
        assert.equal("account", entries[1].value)
        assert.is_true(entries[1].selected)
        for _, entry in ipairs(entries) do
            if entry.value == "character" then entry.choose() end
        end
        assert.equal("character", UI.mode)
        assert.equal(R.L.UI_CHARACTER, UI.scopeDropdown.button:GetDefaultText())
        -- The switch heads the list, so it is there whenever the list is unfiltered.
        assert.is_true(UI.scopeBar:IsShown())
        UI.search:SetText("loot")
        UI.search:GetScript("OnTextChanged")(UI.search)
        assert.is_false(UI.scopeBar:IsShown())
        UI.search:SetText("")
        UI.search:GetScript("OnTextChanged")(UI.search)
        UI:SelectCategory("Profiles")
        assert.equal(1, selectedCount())
        assert.is_true(UI.panelTitle:IsShown())
        assert.equal(R.L.UI_PROFILES, UI.panelTitle:GetText())
        UI:SelectCategory("Vendor")
        assert.is_false(UI.panelTitle:IsShown())
    end)

    it("keeps a dropped item off the sell list and gives it back to the bag", function()
        local env, R = loaded()
        local UI = R.UI
        UI:Toggle()
        UI:OpenModule("vendor.autoSell")
        local cleared = 0
        env.GetCursorInfo = function() return "item", 6948, "item:6948" end
        env.ClearCursor = function() cleared = cleared + 1 end
        UI.neverSellSlot:GetScript("OnReceiveDrag")(UI.neverSellSlot)
        assert.is_true(R.Settings:GetOption("neverSellIDs")[6948])
        assert.equal(1, cleared)
        -- The list is drawn as icons, one per item, and the block grows to hold them.
        assert.is_true(UI.neverSellChips[1]:IsShown())
        assert.equal(6948, UI.neverSellChips[1].itemID)
        assert.is_false(UI.neverSellEmpty:IsShown())
        -- Nothing on the cursor, or not an item: nothing happens.
        env.GetCursorInfo = function() return "spell", 133 end
        UI.neverSellSlot:GetScript("OnClick")(UI.neverSellSlot)
        assert.equal(1, cleared)
        -- A right click on the icon takes it off again.
        UI.neverSellChips[1]:GetScript("OnClick")(UI.neverSellChips[1], "RightButton")
        assert.is_nil(R.Settings:GetOption("neverSellIDs")[6948])
        assert.is_true(UI.neverSellEmpty:IsShown())
        -- An ID typed or pasted as a link goes on too, and nonsense says why it did not.
        assert.is_true(UI:AddNeverSell("|cff9d9d9d|Hitem:2589::::::::1:::::|h[Linen Cloth]|h|r"))
        assert.is_true(R.Settings:GetOption("neverSellIDs")[2589])
        assert.is_false(UI:AddNeverSell("linen"))
        assert.equal(R.L.UI_NEVER_SELL_INVALID, UI.sellStatus:GetText())
    end)

    it("treats a slash word it does not know as a search", function()
        local env, R = loaded()
        local UI = R.UI
        assert.is_nil(env.SlashCmdList.REFACTOR("junk"))
        assert.is_true(UI.frame:IsShown())
        assert.equal("junk", UI.search:GetText())
        assert.is_true(R.moduleByID["vendor.autoSell"] and true)
        local shown = 0
        for _, row in ipairs(UI.rows) do
            if row:IsShown() then shown = shown + 1 end
        end
        assert.is_true(shown > 0 and shown < #UI.rows)
        -- "help" is still help.
        local lines = R.Commands:Dispatch("help")
        assert.equal(R.L.CMD_HELP_HEADER, lines[1])
    end)

    it("opens Diagnostics on a right click of the launcher, and joins a broker when one is loaded", function()
        local env, R = loaded()
        local UI = R.UI
        UI:LauncherClick("RightButton")
        assert.is_true(UI.frame:IsShown())
        assert.is_true(UI.panels.Diagnostics:IsShown())
        UI:LauncherClick("LeftButton")
        assert.is_false(UI.frame:IsShown())
        local lines = {}
        UI:LauncherTooltip({ AddLine = function(_, text) lines[#lines + 1] = text end })
        assert.equal(R.L.UI_TITLE, lines[1])
        assert.equal(R.L.UI_MINIMAP_HINT, lines[#lines])
        -- No broker library, no object; with one, a launcher under the addon's own name.
        assert.is_nil(UI.brokerObject)
        local objects = {}
        local broker = env.LibStub:NewLibrary("LibDataBroker-1.1", 1)
        function broker:NewDataObject(name, data) objects[name] = data return data end
        UI:RegisterBroker()
        assert.equal("launcher", objects.Refactor.type)
        objects.Refactor.OnClick(nil, "RightButton")
        assert.is_true(UI.panels.Diagnostics:IsShown())
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

    it("lays nothing out while hidden and catches up when shown", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        local row = UI.rows[1]
        UI:Toggle()
        UI.mode = "character"
        R.Settings:SetOverride(row.module.id, not UI:DisplayedValue(row.module))
        assert.is_not.equal(UI:DisplayedValue(row.module), row.toggle:GetChecked())
        UI:Toggle()
        assert.equal(UI:DisplayedValue(row.module), row.toggle:GetChecked())
    end)

    it("shows undo only while the value differs from what it would inherit", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        UI.mode = "character"
        local row = UI.rows[1]
        assert.is_false(row.undo:IsShown())
        R.Settings:SetOverride(row.module.id, not R.Settings:GetInherited(row.module.id))
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
        for _, box in ipairs(UI.cameraBoxes) do
            assert.is_false(box:IsEnabled(), "a built-in profile's checkbox is live")
        end
        -- Remembering the wheel is the player's option, not a profile field, so it stays live.
        local learn
        for _, box in ipairs(UI.displayToggles) do
            if box.optionKey == "cameraLearnZoom" then learn = box end
        end
        assert.is_truthy(learn)
        assert.is_true(learn:IsEnabled())
        assert.is_true(learn:GetChecked())
        learn:SetChecked(false)
        learn:GetScript("OnClick")(learn)
        assert.is_false(Settings:GetOption("cameraLearnZoom"))
        learn:SetChecked(true)
        learn:GetScript("OnClick")(learn)
        assert.is_true(Settings:GetOption("cameraLearnZoom"))
        -- Each situation lists what the profile does there, and which way it moves the camera.
        local entryByValue = {}
        for _, entry in ipairs(UI.cameraSituationEntries) do entryByValue[entry.value] = entry.text end
        assert.equal("Indoors: at most 6 yd, centred", entryByValue.indoors)
        assert.equal("Mounted or flying: at least 16 yd, centred", entryByValue.mounted)
        -- A fight holds the camera still, so it is not a situation to tune.
        assert.is_nil(entryByValue.combat)
        -- A built-in offers Customize in the slot beside it, never Delete.
        assert.is_true(UI.cameraCustomize:IsShown())
        assert.is_false(UI.cameraDelete:IsShown())
        -- Customize copies the built-in under the player's own name, selects and unlocks it.
        UI.cameraCustomize:GetScript("OnClick")(UI.cameraCustomize)
        local mine = string.format(R.L.UI_CAMERA_COPY_NAME, R.L.CAMERA_PROFILE_IMMERSIVE)
        assert.equal("custom:" .. mine, Settings:GetOption("cameraProfile"))
        assert.equal(#Profiles.builtIn + 1, #UI.cameraProfileDropdown.button:OpenMenu())
        assert.equal(mine, UI.cameraProfileDropdown.button:GetDefaultText())
        assert.is_true(UI.cameraDelete:IsShown())
        assert.is_false(UI.cameraCustomize:IsShown())
        local shoulder, situationDistance
        for _, slider in ipairs(UI.cameraSliders) do
            assert.is_true(slider.slider:IsEnabled())
            if slider.spec.key == "shoulder" then shoulder = slider end
            if slider.spec.suffix == "Distance" then situationDistance = slider end
        end
        local tilt, swayBox
        for _, slider in ipairs(UI.cameraSliders) do
            if slider.spec.key == "tilt" then tilt = slider end
        end
        for _, box in ipairs(UI.cameraBoxes) do
            assert.is_true(box:IsEnabled())
            if box.fieldKey == "swayWhileMoving" then swayBox = box end
        end
        assert.is_truthy(tilt)
        assert.is_truthy(swayBox)
        tilt.slider:GetScript("OnValueChanged")(tilt.slider, 0.35)
        assert.equal(0.35, Settings:GetOption("cameraProfiles")[mine].tilt)
        assert.equal("35%", tilt.valueText:GetText())
        tilt.slider:GetScript("OnValueChanged")(tilt.slider, 0)
        assert.equal(R.L.UI_CAMERA_OFF, tilt.valueText:GetText())
        swayBox:SetChecked(not Settings:GetOption("cameraProfiles")[mine].swayWhileMoving)
        local before = Settings:GetOption("cameraProfiles")[mine].swayWhileMoving
        swayBox:GetScript("OnClick")(swayBox)
        assert.equal(not before, Settings:GetOption("cameraProfiles")[mine].swayWhileMoving)
        shoulder.slider:GetScript("OnValueChanged")(shoulder.slider, 1.2)
        assert.equal(1.2, Settings:GetOption("cameraProfiles")[mine].shoulder)
        assert.equal("1.2 right", shoulder.valueText:GetText())
        -- The situation dropdown swaps which field the two sliders under it show.
        assert.equal("comes in to 6 yards", situationDistance.valueText:GetText())
        for _, entry in ipairs(UI.cameraSituationDropdown.button:OpenMenu()) do
            if entry.value == "mounted" then entry.choose() end
        end
        assert.equal("backs off to 16 yards", situationDistance.valueText:GetText())
        for _, entry in ipairs(UI.cameraSituationDropdown.button:OpenMenu()) do
            if entry.value == "indoors" then entry.choose() end
        end
        assert.equal("comes in to 6 yards", situationDistance.valueText:GetText())
        for _, entry in ipairs(UI.cameraSituationDropdown.button:OpenMenu()) do
            if entry.value == "mounted" then entry.choose() end
        end
        situationDistance.slider:GetScript("OnValueChanged")(situationDistance.slider, 20)
        assert.equal(20, Settings:GetOption("cameraProfiles")[mine].mountedDistance)
        -- The leftmost stop sits one under the smallest distance and stores "leave it".
        local low = situationDistance.slider:GetMinMaxValues()
        assert.equal(3, low)
        situationDistance.slider:GetScript("OnValueChanged")(situationDistance.slider, 3)
        assert.equal(Profiles.LEAVE, Settings:GetOption("cameraProfiles")[mine].mountedDistance)
        assert.equal(R.L.UI_CAMERA_LEAVE, situationDistance.valueText:GetText())
        UI:LoadCamera()
        assert.equal(3, situationDistance.slider:GetValue())
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

    it("camera block reports the live situation, warns about reduced movement, follows only on open", function()
        local _, R = loaded()
        local UI = R.UI
        local L = R.L
        UI:Toggle()
        assert.equal(L.UI_CAMERA_NOW_OFF, UI.cameraNow:GetText())
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", { active = true, situation = "indoors", target = 6,
            direction = "in", learned = false, shoulder = 0 })
        assert.equal("Right now: indoors, coming in to 6 yards, centred", UI.cameraNow:GetText())
        local status = { active = true, situation = "mounted", target = 22, direction = "out", learned = true,
            shoulder = 0, reduceMovement = true }
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", status)
        -- The warning rides under the status in the warning colour, only while the option is on.
        local text = UI.cameraNow:GetText()
        assert.equal("Right now: mounted, backing off to 22 yards from your wheel, centred",
            text:match("^([^\n]*)\n"))
        assert.is_truthy(text:find(L.UI_CAMERA_REDUCE_WARNING, 1, true))
        assert.is_truthy(text:find("|c" .. R.Theme:Hex("TEXT_WARNING"), 1, true))
        status.reduceMovement = false
        status.situation, status.target, status.direction, status.shoulder = "resting", nil, nil, 1
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", status)
        assert.equal("Right now: in a city or inn, your distance, 1.0 right", UI.cameraNow:GetText())
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", { active = true, preset = true })
        assert.equal(L.UI_CAMERA_NOW_PRESET, UI.cameraNow:GetText())
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", { active = true })
        assert.equal(L.UI_CAMERA_NOW_NOWHERE, UI.cameraNow:GetText())
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", { active = false, reduceMovement = true })
        assert.equal(L.UI_CAMERA_NOW_OFF, UI.cameraNow:GetText())
        -- The dropdown is not dragged along by the status: only opening the block moves it.
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", { active = true, situation = "raid", target = 30,
            direction = "out" })
        assert.equal("indoors", UI.cameraSituation)
        UI:ToggleExpanded("interface.actionCam")
        assert.equal("raid", UI.cameraSituation)
        assert.equal(L.UI_CAMERA_SITUATION_RAID, UI.cameraSituationDropdown.button:GetDefaultText())
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", { active = true, situation = "combat" })
        UI:LoadCamera()
        assert.equal("raid", UI.cameraSituation)
        -- Closing and opening again with no situation keeps the current selection.
        UI:ToggleExpanded("interface.actionCam")
        R.Broker:Emit("REFACTOR_CAMERA_SITUATION", { active = true })
        UI:ToggleExpanded("interface.actionCam")
        assert.equal("raid", UI.cameraSituation)
    end)

    it("visibility block hands behaviours out per setup and edits a behaviour in one place", function()
        local _, R = loaded()
        local UI, Rules, L = R.UI, R.Visibility, R.L
        UI:Toggle()
        UI:ToggleExpanded("interface.visibility")
        assert.is_true(UI.moduleSettings["interface.visibility"]:IsShown())
        -- One row per element, and a fresh install gives none of them a behaviour.
        assert.equal(#Rules.groups, #UI.visRows)
        local main
        for _, row in ipairs(UI.visRows) do
            assert.equal(L.VIS_BEHAVIOUR_NONE, row.button:GetDefaultText(), row.groupId)
            if row.groupId == "bars.main" then main = row end
        end
        local entries = main.button:OpenMenu()
        assert.equal(#Rules.starters + 1, #entries)
        assert.is_true(entries[1].selected)
        assert.equal(L.VIS_BEHAVIOUR_combatHud, entries[3].text)
        entries[3].choose()
        assert.equal("combatHud", Rules:BehaviourFor("bars.main", "world").id)
        assert.equal(L.VIS_BEHAVIOUR_combatHud, main.button:GetDefaultText())
        -- A place with no setup of its own shows World's choices and takes no clicks there.
        local places = UI.visSetupDropdown.button:OpenMenu()
        assert.equal(#Rules.places, #places)
        assert.equal(string.format(L.UI_VIS_SETUP_USES_WORLD, L.VIS_PLACE_city), places[2].text)
        places[2].choose()
        assert.equal("city", UI.visPlace)
        assert.is_false(main.button:IsEnabled())
        assert.equal(L.VIS_BEHAVIOUR_combatHud, main.button:GetDefaultText())
        assert.is_true(UI.visOwnSetup:IsEnabled())
        UI.visOwnSetup:SetChecked(true)
        UI.visOwnSetup:GetScript("OnClick")(UI.visOwnSetup)
        assert.is_true(Rules:HasOwnSetup("city"))
        assert.is_true(main.button:IsEnabled())
        main.button:OpenMenu()[1].choose()
        assert.is_nil(Rules:BehaviourFor("bars.main", "city"))
        assert.equal("combatHud", Rules:BehaviourFor("bars.main", "world").id)
        -- World is always a setup of its own.
        UI.visSetupDropdown.button:OpenMenu()[1].choose()
        assert.is_false(UI.visOwnSetup:IsEnabled())

        -- The editor opens on the first behaviour; one change reaches every element with it.
        assert.equal("fadeAway", UI.visBehaviour)
        UI.visBehaviourDropdown.button:OpenMenu()[2].choose()
        assert.equal("combatHud", UI.visBehaviour)
        assert.equal(L.UI_VIS_USES_ONE, UI.visUses:GetText())
        local resting
        for _, slider in ipairs(UI.visSliders) do
            if slider.field == "resting" then resting = slider end
        end
        resting.slider:GetScript("OnValueChanged")(resting.slider, 0.35)
        assert.equal(0.35, Rules:Behaviour("combatHud").resting)
        assert.equal("35%", resting.valueText:GetText())
        -- Each condition is listed once; ticking Hide on a revealing one moves it across.
        local combat
        for _, row in ipairs(UI.visConditions) do
            if row.condition == "combat" then combat = row end
        end
        assert.is_true(combat.reveal:GetChecked())
        combat.hide:SetChecked(true)
        combat.hide:GetScript("OnClick")(combat.hide)
        assert.equal("hide", Rules:ConditionRole(Rules:Behaviour("combatHud"), "combat"))
        assert.is_false(combat.reveal:GetChecked())
        combat.hide:SetChecked(false)
        combat.hide:GetScript("OnClick")(combat.hide)
        assert.is_nil(Rules:ConditionRole(Rules:Behaviour("combatHud"), "combat"))
        -- Copy as new selects the copy; a name takes on Enter, and a taken one is refused and said so.
        UI.visCopy:GetScript("OnClick")(UI.visCopy)
        local copy = UI.visBehaviour
        assert.is_not.equal("combatHud", copy)
        assert.equal(L.UI_VIS_COPIED, UI.visStatus:GetText())
        assert.equal(L.UI_VIS_USES_NONE, UI.visUses:GetText())
        UI.visName:SetText("Raid bars")
        UI.visName:GetScript("OnEnterPressed")(UI.visName)
        assert.equal("Raid bars", Rules:Name(Rules:Behaviour(copy)))
        UI.visName:SetText("Fade away")
        UI.visName:GetScript("OnEnterPressed")(UI.visName)
        assert.equal("Raid bars", Rules:Name(Rules:Behaviour(copy)))
        assert.equal(L.UI_VIS_ERR_name_taken, UI.visStatus:GetText())
        -- Deleted, its elements go back to the game's look and the editor moves on.
        UI.visBehaviourDropdown.button:OpenMenu()[2].choose()
        UI.visDelete:GetScript("OnClick")(UI.visDelete)
        assert.is_nil(Rules:Behaviour("combatHud"))
        assert.equal(L.VIS_BEHAVIOUR_NONE, main.button:GetDefaultText())
        assert.equal(L.UI_VIS_DELETED, UI.visStatus:GetText())
        assert.equal("fadeAway", UI.visBehaviour)

        -- The Edit Mode companion is one picker, writing to the setup in use where the player is.
        local module = { place = "world", groups = {} }
        local companion = UI:CreateVisibilityCompanion(module)
        companion:Open(UI.frame, { "bars.main" })
        assert.equal(L.VIS_BEHAVIOUR_NONE, companion.behaviour.button:GetDefaultText())
        assert.equal(string.format(L.UI_VIS_COMPANION_SETUP, L.VIS_PLACE_world), companion.setup:GetText())
        local picks = companion.behaviour.button:OpenMenu()
        assert.equal(#Rules:Behaviours() + 1, #picks)
        picks[2].choose()
        assert.equal(Rules:Behaviours()[1].id, Rules:BehaviourFor("bars.main", "world").id)
        assert.equal(Rules:Name(Rules:Behaviours()[1]), companion.behaviour.button:GetDefaultText())
        module.place = "city"
        companion:Load()
        assert.equal(string.format(L.UI_VIS_COMPANION_SETUP, L.VIS_PLACE_city), companion.setup:GetText())
        companion.behaviour.button:OpenMenu()[1].choose()
        assert.is_nil(Rules:BehaviourFor("bars.main", "city"))
        assert.is_table(Rules:BehaviourFor("bars.main", "world"))
        companion:Close()
        assert.equal(0, #R.errors)
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

    it("re-reads controls on a slider step without laying the list out or reconciling", function()
        local _, R = loaded()
        local UI, Settings = R.UI, R.Settings
        UI:Toggle()
        local opacity
        for _, slider in ipairs(UI.optionSliders) do
            if slider.spec.key == "farmOpacity" then opacity = slider end
        end
        local placed, reconciled = 0, 0
        local place, reconcile = UI.Place, R.Registry.ReconcileAll
        UI.Place = function(...) placed = placed + 1; return place(...) end
        R.Registry.ReconcileAll = function(...) reconciled = reconciled + 1; return reconcile(...) end
        opacity.slider:GetScript("OnValueChanged")(opacity.slider, 50)
        assert.equal(0.5, Settings:GetOption("farmOpacity"))
        assert.is_true(opacity.undo:IsShown())
        assert.equal(0, placed)
        assert.equal(0, reconciled)
        -- A feature switched on or off still lays the list out and reconciles.
        R.Settings:SetAccount(UI.rows[1].module.id, true)
        assert.is_true(placed > 0)
        assert.equal(1, reconciled)
        UI.Place, R.Registry.ReconcileAll = place, reconcile
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

describe("editing scope", function()
    -- A row with nothing in its meta slot: no warning state to compete with the marker.
    local function plainRow(UI)
        for _, row in ipairs(UI.rows) do
            if row.meta:GetText() == "" then return row end
        end
    end

    it("opens on the account layer and keeps the choice for the character", function()
        local _, R = loaded()
        assert.equal("account", R.UI.mode)
        assert.is_true(R.Settings:SetScope("character"))
        R.UI.frame = nil
        R.UI:Initialize()
        assert.equal("character", R.UI.mode)
    end)

    it("clears this character's override when the account layer is edited", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        UI.mode = "character"
        local module = plainRow(UI).module
        UI:SetModuleEnabled(module, true)
        assert.is_true(R.Settings:GetOverride(module.id))
        UI.mode = "account"
        -- Without the clear this writes false behind an override that is still true, and
        -- the click changes nothing the player can see.
        UI:SetModuleEnabled(module, false)
        assert.is_nil(R.Settings:GetOverride(module.id))
        assert.is_false(R.Settings:Get(module.id))
        UI:SetModuleEnabled(module, true)
        assert.is_true(R.Settings:Get(module.id))
    end)

    it("drops the override when undo runs on the account layer", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        UI.mode = "character"
        local module = plainRow(UI).module
        UI:SetModuleEnabled(module, true)
        UI.mode = "account"
        UI:ResetModule(module)
        assert.is_nil(R.Settings:GetOverride(module.id))
        assert.is_nil(R.Settings.account.modules[module.id])
        assert.equal(R.Settings.defaults[module.id] == true, R.Settings:Get(module.id))
    end)

    it("names a character override while the account layer is on screen", function()
        local _, R = loaded()
        local UI = R.UI
        UI:Toggle()
        UI.mode = "character"
        local row = plainRow(UI)
        R.Settings:SetOverride(row.module.id, true)
        UI:Refresh()
        assert.equal("", row.meta:GetText())
        UI.mode = "account"
        UI:Refresh()
        assert.equal(R.L.UI_SCOPE_PINNED, row.meta:GetText())
    end)

    it("edits the assigned profile, since the account layer no longer reaches the character", function()
        local _, R = loaded()
        local UI, Settings = R.UI, R.Settings
        UI:Toggle()
        local module = plainRow(UI).module
        local before = Settings:Get(module.id)
        assert.is_true(Settings:CreateProfile("Alts", { [module.id] = before }))
        -- No profile, no profile layer: the scope refuses it.
        assert.is_false(Settings:SetScope("profile"))
        assert.is_true(Settings:AssignProfile("Alts"))
        UI:Refresh()
        -- Account defaults say, in words, that they do not reach this character any more.
        assert.equal(string.format(R.L.UI_ACCOUNT_HELP_PROFILE, "Alts"), UI.scopeHelp:GetText())
        local entries = UI.scopeDropdown.button:OpenMenu()
        assert.equal(3, #entries)
        assert.equal("profile", entries[2].value)
        entries[2].choose()
        assert.equal("profile", UI.mode)
        assert.equal("profile", Settings:GetScope())
        -- A click writes into the profile, never the account, and clears an override.
        Settings:SetOverride(module.id, before)
        UI:SetModuleEnabled(module, not before)
        assert.equal(not before, Settings:GetProfile("Alts")[module.id])
        assert.is_nil(Settings.account.modules[module.id])
        assert.is_nil(Settings:GetOverride(module.id))
        assert.equal(not before, Settings:Get(module.id))
        assert.equal(not before, UI:DisplayedValue(module))
        -- Undo takes the feature out of the profile, so it follows the account again.
        assert.is_true(UI:IsModified(module))
        UI:ResetModule(module)
        assert.is_nil(Settings:GetProfile("Alts")[module.id])
        assert.equal(Settings.defaults[module.id] == true, Settings:Get(module.id))
        -- Unassigned, the stored scope falls back to the account layer.
        assert.is_true(Settings:AssignProfile(nil))
        UI:Refresh()
        assert.equal("account", UI.mode)
        assert.equal("account", Settings:GetScope())
        assert.equal(2, #UI.scopeDropdown.button:OpenMenu())
    end)
end)
