local Runtime = require("Tests.mock.runtime")
local json = require("dkjson")

local MODULE = "interface.visibility"

-- A Blizzard frame as the module sees it: alpha, script hooks, children and a mouse flag.
local function fakeFrame(name, alpha, children)
    local frame = { name = name, alpha = alpha or 1, scripts = {}, children = children or {}, mouseOver = false,
        shown = false, protected = false }
    function frame:IsShown() return self.shown end
    function frame:IsProtected() return self.protected end
    function frame:IsForbidden() return false end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:HookScript(script, fn)
        self.scripts[script] = self.scripts[script] or {}
        table.insert(self.scripts[script], fn)
    end
    function frame:GetChildren() return unpack(self.children) end
    function frame:GetParent() return self.parentFrame end
    function frame:IsMouseOver() return self.mouseOver end
    function frame:GetName() return self.name end
    function frame:Fire(script)
        for _, fn in ipairs(self.scripts[script] or {}) do fn(self) end
    end
    return frame
end

local function base(options)
    options = options or {}
    local env = Runtime.new()
    local R = env.R
    env.loaded = options.loaded or {}
    env.C_AddOns = { IsAddOnLoaded = function(name) return env.loaded[name] == true end }
    env.hooks, env.hookCount = {}, 0
    env.hooksecurefunc = function(target, name, fn)
        env.hookCount = env.hookCount + 1
        if type(target) == "string" then
            env.hooks[target] = name
        else
            env.hooks[target] = env.hooks[target] or {}
            env.hooks[target][name] = fn
        end
    end
    env.world = { combat = false, mounted = false, resting = false }
    env.InCombatLockdown = function() return env.world.combat end
    env.IsMounted = function() return env.world.mounted end
    env.UnitOnTaxi = function() return false end
    env.IsResting = function() return env.world.resting end
    env.UnitExists = function() return false end
    env.IsInGroup = function() return false end
    env.IsInInstance = function() return false, "none" end
    env.IsStealthed = function() return false end
    env.UnitIsDeadOrGhost = function() return false end
    env.FCF_FadeInChatFrame = function() end
    env.GameTooltip = fakeFrame("GameTooltip")
    env.GameTooltip.SetOwner = function(tip, owner) tip.owner, tip.shown = owner, true end
    env.GetCursorInfo = function() return env.cursor end
    env.EventRegistry = { callbacks = {} }
    function env.EventRegistry:RegisterCallback(event, fn) self.callbacks[event] = fn end
    env.fakes = {}
    -- A dotted name is a child by parentKey: the parent is made first and the child hangs off it.
    local function install(name)
        local holder, key = env, name
        for parent, child in name:gmatch("([%w_]+)%.([%w_%.]+)") do
            holder[parent] = holder[parent] or fakeFrame(parent)
            env.fakes[parent] = holder[parent]
            holder, key = holder[parent], child
        end
        holder[key] = holder[key] or fakeFrame(key)
        env.fakes[key] = holder[key]
    end
    for _, group in ipairs(R.Visibility.groups) do
        for _, list in ipairs({ group.frames, group.optional, R.Visibility.systems[group.id] }) do
            for _, name in ipairs(list) do
                if not options.missing or not options.missing[name] then
                    install(name)
                end
            end
        end
    end
    -- Blizzard's Edit Mode dialog, and the companion the module asks the UI layer for.
    env.EditModeSystemSettingsDialog = fakeFrame("EditModeSystemSettingsDialog")
    env.EditModeSystemSettingsDialog.AttachToSystemFrame = function() end
    env.companion = { openCount = 0 }
    function env.companion:Open(dialog, ids)
        self.openCount = self.openCount + 1
        self.dialog, self.ids = dialog, { unpack(ids) }
    end
    function env.companion:Close() self.ids = nil end
    R.UI = { CreateVisibilityCompanion = function() return env.companion end }
    -- The calendar sits inside the minimap cluster, so it belongs to two groups at once.
    env.MinimapCluster.children = { env.GameTimeFrame }
    env.blobs = {}
    for _, entry in ipairs(R.Visibility:Group("hud.minimap").extras) do
        for method in pairs(entry.alphas) do
            env.Minimap[method] = function(_, alpha) env.blobs[method] = alpha end
        end
    end
    if env.ChatFrame1ButtonFrame then env.ChatFrame1ButtonFrame.alpha = 0.2 end
    if env.ChatFrame1 then
        env.ChatFrame1.editBox = fakeFrame("ChatFrame1EditBox")
    end
    if env.MainActionBar then
        -- Action bars and their buttons are protected, as are unit frames: no script goes on them.
        env.MainActionBar.protected = true
        env.MainActionBar.children = { fakeFrame("ActionButton1"), fakeFrame("ActionButton2") }
        for _, button in ipairs(env.MainActionBar.children) do
            button.protected = true
            button.parentFrame = env.MainActionBar
        end
    end
    if env.PlayerFrame then
        for _, name in ipairs({ "PlayerFrame", "TargetFrame", "PartyFrame" }) do env[name].protected = true end
        env.PlayerFrame.children = { fakeFrame("PlayerFrameContent") }
        env.PlayerFrame.children[1].parentFrame = env.PlayerFrame
        -- The pet frame is a secure unit button two levels under the player frame.
        env.PetFrame = fakeFrame("PetFrame")
        env.PetFrame.protected = true
        env.PetFrame.parentFrame = env.PlayerFrame.children[1]
    end
    for _, path in ipairs({ "Integrations/Neighbours.lua", "Integrations/Questie.lua", "Integrations/Plater.lua",
        "Integrations/FrameOwners.lua",
        "Locales/Visibility.enUS.lua", "Modules/Interface/Visibility.lua" }) do
        env:Load(path)
    end
    return env, R, R.moduleByID[MODULE]
end

local function step(R, seconds)
    local handler = R.Fade.driver:GetScript("OnUpdate")
    if handler then handler(R.Fade.driver, seconds) end
end

-- A tooltip naming its owner is what hovering a secure button looks like from outside.
local function tooltipOn(env, owner)
    env.hooks[env.GameTooltip].SetOwner(env.GameTooltip, owner)
    env.GameTooltip.owner, env.GameTooltip.shown = owner, true
end

local function tooltipOff(env)
    env.GameTooltip.shown = false
end

-- One tick of the hover watch, then enough of a fade to land.
local function settle(env, R)
    env:Advance(0.1)
    step(R, 5)
end

describe("visibility rules", function()
    local R, Rules
    before_each(function()
        local env = Runtime.new()
        R, Rules = env.R, env.R.Visibility
    end)

    it("resolves hover, then show, then hide, then the base mode, for every combination", function()
        -- mode, hovered, a show condition holds, a hide condition holds, expected alpha
        local cases = {
            { "always", false, false, false, 1 }, { "always", false, false, true, 0 },
            { "always", false, true, false, 1 }, { "always", false, true, true, 1 },
            { "always", true, false, false, 1 }, { "always", true, false, true, 0 },
            { "always", true, true, false, 1 }, { "always", true, true, true, 1 },
            { "mouseover", false, false, false, 0 }, { "mouseover", false, false, true, 0 },
            { "mouseover", false, true, false, 1 }, { "mouseover", false, true, true, 1 },
            { "mouseover", true, false, false, 1 }, { "mouseover", true, false, true, 1 },
            { "mouseover", true, true, false, 1 }, { "mouseover", true, true, true, 1 },
            { "hidden", false, false, false, 0 }, { "hidden", false, false, true, 0 },
            { "hidden", false, true, false, 1 }, { "hidden", false, true, true, 1 },
            { "hidden", true, false, false, 0 }, { "hidden", true, false, true, 0 },
            { "hidden", true, true, false, 1 }, { "hidden", true, true, true, 1 },
        }
        local state = { combat = true, mounted = true, resting = false }
        -- The answer is the rule's own opacity for that state, not a bare 1 or 0.
        local dimmed = Rules:DefaultRule()
        dimmed.mode, dimmed.shownAlpha, dimmed.hiddenAlpha = "mouseover", 0.7, 0.2
        assert.equal(0.7, Rules:Resolve(dimmed, state, true))
        assert.equal(0.2, Rules:Resolve(dimmed, state, false))
        dimmed.hideWhen = { mounted = true }
        assert.equal(0.7, Rules:Resolve(dimmed, state, true))
        dimmed.mode = "always"
        assert.equal(0.2, Rules:Resolve(dimmed, state, true))
        for _, case in ipairs(cases) do
            local rule = Rules:DefaultRule()
            rule.mode = case[1]
            -- resting never holds, so a set naming only it is a set with no hit.
            rule.showWhen = case[3] and { combat = true } or { resting = true }
            rule.hideWhen = case[4] and { mounted = true } or { resting = true }
            assert.equal(case[5], Rules:Resolve(rule, state, case[2]),
                table.concat({ case[1], tostring(case[2]), tostring(case[3]), tostring(case[4]) }, " "))
        end
    end)

    it("validates a rule and the whole option, and drops a bad saved table on init", function()
        local good = Rules:DefaultRule()
        assert.is_true(Rules:ValidRule(good))
        local function broken(patch)
            local rule = Rules:DefaultRule()
            for key, value in pairs(patch) do rule[key] = value end
            return rule
        end
        assert.is_false(Rules:ValidRule(broken({ mode = "sometimes" })))
        assert.is_false(Rules:ValidRule(broken({ showWhen = { flying = true } })))
        assert.is_false(Rules:ValidRule(broken({ hideWhen = { combat = 1 } })))
        assert.is_false(Rules:ValidRule(broken({ fadeIn = 3 })))
        assert.is_false(Rules:ValidRule(broken({ fadeOut = -1 })))
        assert.is_false(Rules:ValidRule(broken({ fadeOut = 0 / 0 })))
        assert.is_false(Rules:ValidRule(broken({ shownAlpha = 0.05 })))
        assert.is_false(Rules:ValidRule(broken({ shownAlpha = 1.5 })))
        assert.is_false(Rules:ValidRule(broken({ hiddenAlpha = -0.1 })))
        assert.is_true(Rules:ValidRule(broken({ hiddenAlpha = 0.5, shownAlpha = 0.1 })))
        assert.is_false(Rules:ValidRule(broken({ zone = "middle" })))
        assert.is_true(Rules:ValidRule(broken({ zone = "right" })))
        assert.is_false(Rules:ValidRule(broken({ extra = true })))
        local short = Rules:DefaultRule()
        short.fadeIn = nil
        assert.is_false(Rules:ValidRule(short))
        assert.is_true(Rules:ValidSettings({ preset = "off", groups = {} }))
        assert.is_true(Rules:ValidSettings({ preset = "custom", groups = { ["bars.main"] = good } }))
        assert.is_false(Rules:ValidSettings({ preset = "mine", groups = {} }))
        assert.is_false(Rules:ValidSettings({ preset = "off" }))
        assert.is_false(Rules:ValidSettings({ preset = "off", groups = { ["not an id"] = good } }))
        assert.is_false(Rules:ValidSettings({ preset = "off", groups = { ["bars.main"] = { mode = "always" } } }))
        assert.is_false(R.Settings:SetOption("uiVisibility", { preset = "off", groups = { ["bars.main"] = {} } }))
        local account = { options = { uiVisibility = { preset = "immersion", groups = { ["bars.main"] = {} } } } }
        R.Settings:Init(account, {}, "Player-test")
        assert.equal("off", account.options.uiVisibility.preset)
        assert.same({}, account.options.uiVisibility.groups)
    end)

    it("writes a preset into every group and turns the selection custom on a hand edit", function()
        assert.is_false(Rules:ApplyPreset("nope"))
        assert.is_true(Rules:ApplyPreset("combatOnly"))
        local settings = Rules:Settings()
        assert.equal("combatOnly", settings.preset)
        for _, group in ipairs(Rules.groups) do
            local rule = settings.groups[group.id]
            assert.is_table(rule, group.id)
            if group.kind == "bars" or group.kind == "unit" then
                assert.equal("hidden", rule.mode)
                assert.same({ combat = true }, rule.showWhen)
            elseif group.kind == "art" then
                assert.equal("hidden", rule.mode)
                assert.same({}, rule.showWhen)
            else
                assert.equal("mouseover", rule.mode)
                assert.same({}, rule.showWhen)
            end
            assert.same({}, rule.hideWhen)
            assert.equal(0.15, rule.fadeIn)
            assert.equal(0.4, rule.fadeOut)
            assert.equal(Rules.zoneDefaults[group.id] or "none", rule.zone, group.id)
        end
        assert.equal("bottom", Rules:Rule("bars.pet").zone)
        assert.equal("bottom", Rules:Rule("hud.bags").zone)
        assert.equal("left", Rules:Rule("chat.tabs").zone)
        assert.equal("top", Rules:Rule("unit.raid").zone)
        assert.equal("right", Rules:Rule("hud.objectives").zone)
        -- A zone is part of the rule, so changing it is a hand edit.
        assert.is_true(Rules:SetRule("hud.objectives", { zone = "none" }))
        assert.equal("custom", Rules:Settings().preset)
        assert.is_true(Rules:ApplyPreset("combatOnly"))
        assert.is_true(Rules:ApplyPreset("mounted"))
        assert.same({ mounted = true }, Rules:Rule("chat.tabs").hideWhen)
        assert.equal("always", Rules:Rule("chat.tabs").mode)
        -- A fade or an opacity is tuning and keeps the preset; a rule change makes it custom.
        assert.is_true(Rules:SetRule("bars.main", { fadeOut = 1 }))
        assert.is_true(Rules:SetRule("bars.main", { shownAlpha = 0.6, hiddenAlpha = 0.2 }))
        assert.equal("mounted", Rules:Settings().preset)
        assert.equal(1, Rules:Rule("bars.main").fadeOut)
        assert.equal(0.6, Rules:Rule("bars.main").shownAlpha)
        assert.is_true(Rules:SetRule("bars.main", { showWhen = { combat = true, resting = true } }))
        assert.equal("custom", Rules:Settings().preset)
        assert.same({ combat = true, resting = true }, Rules:Rule("bars.main").showWhen)
        assert.same({ mounted = true }, Rules:Rule("bars.main").hideWhen)
        assert.is_false(Rules:SetRule("bars.main", { mode = "gone" }))
        assert.is_false(Rules:SetRule("hud.nothing", { mode = "hidden" }))
        assert.equal("custom", Rules:Settings().preset)
        -- Presets keep the fades and opacities the player chose.
        assert.is_true(Rules:ApplyPreset("off"))
        assert.equal(1, Rules:Rule("bars.main").fadeOut)
        assert.equal(0.2, Rules:Rule("bars.main").hiddenAlpha)
        assert.equal("always", Rules:Rule("bars.main").mode)
        -- What Settings hands out is a copy: editing it changes nothing saved.
        Rules:Rule("bars.main").mode = "hidden"
        assert.equal("always", Rules:Rule("bars.main").mode)
        Rules:Settings().groups["bars.main"].mode = "hidden"
        assert.equal("always", Rules:Rule("bars.main").mode)
    end)

    it("writes one patch onto several groups at once, whole or not at all", function()
        assert.is_true(Rules:ApplyPreset("off"))
        local seen = {}
        R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", function(_, _, key) seen[#seen + 1] = key end, seen)
        local bars = { "bars.main", "bars.bottomLeft", "bars.pet" }
        assert.is_true(Rules:SetRules(bars, { mode = "mouseover", showWhen = { combat = true }, shownAlpha = 0.8 }))
        assert.same({ "uiVisibility" }, seen)
        for _, id in ipairs(bars) do
            local rule = Rules:Rule(id)
            assert.equal("mouseover", rule.mode, id)
            assert.same({ combat = true }, rule.showWhen, id)
            assert.equal(0.8, rule.shownAlpha, id)
        end
        assert.equal("always", Rules:Rule("bars.right").mode)
        assert.equal("custom", Rules:Settings().preset)
        -- Each target gets its own set: editing one later leaves the others alone.
        assert.is_true(Rules:SetRule("bars.main", { showWhen = { resting = true } }))
        assert.same({ combat = true }, Rules:Rule("bars.pet").showWhen)
        -- One bad target or a bad value refuses the whole write; an empty list writes nothing.
        seen = {}
        assert.is_false(Rules:SetRules({ "bars.main", "hud.nothing" }, { mode = "hidden" }))
        assert.is_false(Rules:SetRules(bars, { shownAlpha = 2 }))
        assert.is_false(Rules:SetRules({}, { mode = "hidden" }))
        assert.is_false(Rules:SetRules("bars.main", { mode = "hidden" }))
        assert.equal(0, #seen)
        assert.equal("mouseover", Rules:Rule("bars.main").mode)
    end)

    it("maps an Edit Mode system frame to its groups and a group to its siblings", function()
        local env = Runtime.new()
        local R2 = env.R
        env.ChatFrame1, env.MainActionBar = {}, {}
        env.MainStatusTrackingBarContainer, env.SecondaryStatusTrackingBarContainer = {}, {}
        assert.same({ "chat.frames", "chat.tabs", "chat.buttons", "chat.inputArt" },
            R2.Visibility:GroupsForSystem(env.ChatFrame1))
        assert.same({ "bars.main" }, R2.Visibility:GroupsForSystem(env.MainActionBar))
        assert.same({ "hud.status" }, R2.Visibility:GroupsForSystem(env.SecondaryStatusTrackingBarContainer))
        assert.same({}, R2.Visibility:GroupsForSystem({}))
        assert.same({}, R2.Visibility:GroupsForSystem(nil))
        assert.same({ "bars.bottomLeft", "bars.bottomRight", "bars.right", "bars.left", "bars.five", "bars.six",
            "bars.seven", "bars.pet", "bars.stance" }, R2.Visibility:Siblings("bars.main"))
        assert.same({}, R2.Visibility:Siblings("chat.inputArt"))
        assert.same({}, R2.Visibility:Siblings("hud.nothing"))
    end)

    it("names only frames and functions the API index has evidence for", function()
        local file = assert(io.open("Data/api-retail.json", "r"))
        local index = assert(json.decode(file:read("*a")))
        file:close()
        local names = { "FCF_FadeInChatFrame", "GameTooltip", "GetCursorInfo", "EventRegistry", "hooksecurefunc",
            "EditModeSystemSettingsDialog" }
        for _, group in ipairs(Rules.groups) do
            for _, name in ipairs(group.frames) do names[#names + 1] = name end
            for _, name in ipairs(group.optional or {}) do names[#names + 1] = name end
            for _, entry in ipairs(group.reapply or {}) do
                names[#names + 1] = type(entry) == "string" and entry or entry.frame
            end
        end
        assert.is_true(#names > 20)
        for _, name in ipairs(names) do
            assert.is_table(index.symbols[name], "no source evidence for " .. name)
        end
        for id, systems in pairs(Rules.systems) do
            assert.is_table(Rules:Group(id), id)
            for _, name in ipairs(systems) do
                assert.is_table(index.symbols[name], "no source evidence for " .. name)
            end
        end
        for _, group in ipairs(Rules.groups) do
            assert.is_table(Rules.systems[group.id], group.id .. " has no Edit Mode system")
            for _, entry in ipairs(group.extras or {}) do
                assert.is_table(index.symbols[entry.frame], "no source evidence for " .. entry.frame)
                assert.is_true(Rules.extraOptions[entry.option], entry.option)
                for method in pairs(entry.alphas) do
                    assert.is_table(index.widgetMethods[method], "no widget evidence for " .. method)
                end
            end
        end
    end)
end)

describe("fade driver", function()
    it("tweens toward a target, retargets mid-fade, and goes idle when done", function()
        local env = Runtime.new()
        local Fade = env.R.Fade
        local frame = fakeFrame("Frame", 1)
        assert.is_nil(Fade.driver:GetScript("OnUpdate"))
        Fade:To(frame, 0, 1)
        assert.equal(1, Fade:Active())
        assert.is_function(Fade.driver:GetScript("OnUpdate"))
        step(env.R, 0.25)
        assert.equal(0.75, frame.alpha)
        -- Back the other way from where it is, at the full-swing speed scaled to the distance.
        Fade:To(frame, 1, 1)
        step(env.R, 0.125)
        assert.is_true(math.abs(frame.alpha - 0.875) < 1e-9)
        step(env.R, 0.125)
        assert.equal(1, frame.alpha)
        assert.equal(0, Fade:Active())
        assert.is_nil(Fade.driver:GetScript("OnUpdate"))
        -- Zero seconds and no distance both snap without a record.
        Fade:To(frame, 0.5, 0)
        assert.equal(0.5, frame.alpha)
        assert.equal(0, Fade:Active())
        Fade:To(frame, 0.5, 2)
        assert.equal(0, Fade:Active())
        -- Two frames share the one driver; a snap cancels one without touching the other.
        local other = fakeFrame("Other", 0)
        Fade:To(frame, 0, 1)
        Fade:To(other, 1, 1)
        assert.equal(2, Fade:Active())
        Fade:Snap(frame, 0.3)
        assert.equal(0.3, frame.alpha)
        assert.equal(1, Fade:Active())
        step(env.R, 5)
        assert.equal(1, other.alpha)
        assert.equal(0, Fade:Active())
        assert.is_nil(Fade.driver:GetScript("OnUpdate"))
    end)
end)

describe("interface.visibility", function()
    it("enables on a full client, applies the rule, and follows hover, conditions and settings", function()
        local env, R, module = base()
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("enabled", module.state)
        for _, group in ipairs(R.Visibility.groups) do
            assert.equal("ok", module.groups[group.id].status, group.id)
        end
        -- Off means every frame keeps the alpha it had, including the button frame's 0.2.
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0.2, env.ChatFrame1ButtonFrame.alpha)
        assert.equal(0, R.Fade:Active())

        R.Visibility:ApplyPreset("immersion")
        -- A settings change fades rather than snaps.
        assert.equal(1, env.MainActionBar.alpha)
        assert.is_true(R.Fade:Active() > 0)
        step(R, 5)
        assert.equal(0, env.MainActionBar.alpha)
        assert.equal(0, env.ChatFrame1.alpha)
        assert.equal(0, env.ChatFrame7.alpha)
        assert.equal(0, env.GeneralDockManager.alpha)
        assert.equal(0, env.ChatFrame1ButtonFrame.alpha)
        assert.equal(0, R.Fade:Active())

        -- A button's tooltip is the hover; the bar and its whole zone come back.
        local button = env.MainActionBar.children[1]
        assert.is_nil(button.scripts.OnEnter)
        assert.is_nil(env.MainActionBar.scripts.OnEnter)
        tooltipOn(env, button)
        step(R, 5)
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(1, env.MultiBarRight.alpha)
        assert.equal(1, env.BagsBar.alpha)
        assert.equal(0, env.ChatFrame1.alpha)
        assert.equal(0, env.MinimapCluster.alpha)
        -- Still over a frame of the zone: the watch keeps it. Off everything: one tick drops it.
        tooltipOff(env)
        env.BagsBar.mouseOver = true
        settle(env, R)
        assert.equal(1, env.MainActionBar.alpha)
        env.BagsBar.mouseOver = false
        settle(env, R)
        assert.equal(0, env.MainActionBar.alpha)
        assert.equal(0, env.BagsBar.alpha)
        assert.equal(0, env:ActiveTimers())

        -- Blizzard's chat fade is the chat hover: windows, docked tabs and the rest of the side.
        env.ChatFrame1.hasBeenFaded = true
        env.hooks.FCF_FadeInChatFrame(env.ChatFrame1)
        step(R, 5)
        assert.equal(1, env.ChatFrame1.alpha)
        assert.equal(1, env.ChatFrame7.alpha)
        assert.equal(1, env.GeneralDockManager.alpha)
        -- The chat buttons share the left zone with the windows, so they come along.
        assert.equal(0.2, env.ChatFrame1ButtonFrame.alpha)
        assert.equal(0, env.MainActionBar.alpha)
        env.ChatFrame1.hasBeenFaded = nil
        settle(env, R)
        assert.equal(0, env.ChatFrame1.alpha)
        assert.equal(0, env.GeneralDockManager.alpha)
        -- Typing holds the window open past a Blizzard fade out.
        env.ChatFrame1.editBox:Fire("OnEditFocusGained")
        step(R, 5)
        assert.equal(1, env.ChatFrame1.alpha)
        settle(env, R)
        assert.equal(1, env.ChatFrame1.alpha)
        env.ChatFrame1.editBox:Fire("OnEditFocusLost")
        settle(env, R)
        assert.equal(0, env.ChatFrame1.alpha)

        -- Conditions: hidden bars with a show-in-combat rule.
        R.Visibility:ApplyPreset("combatOnly")
        step(R, 5)
        assert.equal(0, env.MultiBarRight.alpha)
        env.world.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        assert.equal(1, env.MainActionBar.alpha)
        env.world.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        step(R, 5)
        assert.equal(0, env.MultiBarRight.alpha)
        -- A hide condition on a visible rule, and a show condition beating it.
        R.Visibility:ApplyPreset("mounted")
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        env.world.mounted = true
        env:Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
        step(R, 5)
        assert.equal(0, env.MultiBarRight.alpha)
        assert.equal(0, env.ChatFrame1.alpha)
        R.Visibility:SetRule("bars.right", { showWhen = { combat = true } })
        env.world.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        assert.equal(0, env.MainActionBar.alpha)

        -- Edit Mode shows everything at once and hands back on exit.
        env.EventRegistry.callbacks["EditMode.Enter"]()
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(1, env.ChatFrame1.alpha)
        assert.equal(0, R.Fade:Active())
        env.EventRegistry.callbacks["EditMode.Exit"]()
        step(R, 5)
        assert.equal(0, env.MainActionBar.alpha)
        assert.equal(0, #R.errors)
    end)

    it("watches the mouse rather than trusting a leave, so nothing is stranded visible", function()
        local env, R, module = base()
        R.Visibility:ApplyPreset("immersion")
        R.Visibility:SetRule("hud.minimap", { zone = "none" })
        assert.is_true(R.Registry:Enable(MODULE))
        step(R, 5)
        -- A plain frame's own OnEnter, with no OnLeave ever hooked or fired.
        assert.equal(1, #env.MinimapCluster.scripts.OnEnter)
        assert.is_nil(env.MinimapCluster.scripts.OnLeave)
        env.MinimapCluster.mouseOver = true
        env.MinimapCluster:Fire("OnEnter")
        step(R, 5)
        assert.equal(1, env.MinimapCluster.alpha)
        assert.is_true(env:ActiveTimers() > 0)
        settle(env, R)
        assert.equal(1, env.MinimapCluster.alpha)
        env.MinimapCluster.mouseOver = false
        settle(env, R)
        assert.equal(0, env.MinimapCluster.alpha)
        assert.equal(0, env:ActiveTimers())
        -- A frame the client will not measure counts as not under the mouse, and is no error.
        env.MinimapCluster.IsMouseOver = function() error("Can't measure restricted regions") end
        env.MinimapCluster:Fire("OnEnter")
        step(R, 5)
        assert.equal(1, env.MinimapCluster.alpha)
        settle(env, R)
        assert.equal(0, env.MinimapCluster.alpha)
        assert.equal("enabled", module.state)
        assert.equal(0, #R.errors)
    end)

    it("reveals a whole zone from any of its elements and only that element outside one", function()
        local env, R = base()
        R.Visibility:ApplyPreset("immersion")
        assert.is_true(R.Registry:Enable(MODULE))
        step(R, 5)
        -- The bags are in the bottom zone with every bar: their tooltip brings the bars back.
        tooltipOn(env, env.BagsBar)
        step(R, 5)
        assert.equal(1, env.BagsBar.alpha)
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(1, env.MultiBar7.alpha)
        assert.equal(1, env.StatusTrackingBarManager.alpha)
        assert.equal(0, env.PlayerFrame.alpha)
        tooltipOff(env)
        settle(env, R)
        assert.equal(0, env.MainActionBar.alpha)
        -- Taken out of the zone, the main bar answers to its own hover alone.
        R.Visibility:SetRule("bars.main", { zone = "none" })
        step(R, 5)
        tooltipOn(env, env.BagsBar)
        step(R, 5)
        assert.equal(1, env.MultiBar7.alpha)
        assert.equal(0, env.MainActionBar.alpha)
        tooltipOff(env)
        settle(env, R)
        tooltipOn(env, env.MainActionBar.children[2])
        step(R, 5)
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0, env.MultiBar7.alpha)
        tooltipOff(env)
        settle(env, R)
        assert.equal(0, env.MainActionBar.alpha)
        assert.equal(0, env:ActiveTimers())
    end)

    it("shows everything while something is on the cursor", function()
        local env, R = base()
        R.Visibility:ApplyPreset("immersion")
        R.Visibility:SetRule("bars.main", { shownAlpha = 0.7 })
        assert.is_true(R.Registry:Enable(MODULE))
        step(R, 5)
        assert.equal(0, env.MainActionBar.alpha)
        env.cursor = "spell"
        env:Fire("CURSOR_CHANGED")
        step(R, 5)
        assert.equal(0.7, env.MainActionBar.alpha)
        assert.equal(1, env.ChatFrame1.alpha)
        env.cursor = nil
        env:Fire("CURSOR_CHANGED")
        step(R, 5)
        assert.equal(0, env.MainActionBar.alpha)
        assert.equal(0, env.ChatFrame1.alpha)
    end)

    it("fades to the element's own shown and hidden opacity", function()
        local env, R = base()
        R.Visibility:ApplyPreset("immersion")
        R.Visibility:SetRule("bars.main", { shownAlpha = 0.8, hiddenAlpha = 0.3 })
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal(0.3, env.MainActionBar.alpha)
        assert.equal(0, env.MultiBarRight.alpha)
        tooltipOn(env, env.MainActionBar.children[1])
        step(R, 5)
        assert.equal(0.8, env.MainActionBar.alpha)
        -- A share of the frame's own alpha: the button frame ships at 0.2.
        R.Visibility:SetRule("chat.buttons", { mode = "always", shownAlpha = 0.5 })
        step(R, 5)
        assert.is_true(math.abs(env.ChatFrame1ButtonFrame.alpha - 0.1) < 1e-9)
        -- Edit Mode ignores the rule's opacity and shows the frame as the game has it.
        env.EventRegistry.callbacks["EditMode.Enter"]()
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0.2, env.ChatFrame1ButtonFrame.alpha)
        env.EventRegistry.callbacks["EditMode.Exit"]()
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0.2, env.ChatFrame1ButtonFrame.alpha)
    end)

    it("opens the companion beside Blizzard's dialog for the selected system and previews the element", function()
        local env, R = base()
        R.Visibility:ApplyPreset("immersion")
        R.Visibility:SetRule("bars.main", { shownAlpha = 0.8 })
        assert.is_true(R.Registry:Enable(MODULE))
        local dialog = env.EditModeSystemSettingsDialog
        local attach = env.hooks[dialog].AttachToSystemFrame
        assert.is_function(attach)
        env.EventRegistry.callbacks["EditMode.Enter"]()
        assert.equal(1, env.MainActionBar.alpha)
        attach(dialog, env.MainActionBar)
        assert.same({ "bars.main" }, env.companion.ids)
        assert.equal(dialog, env.companion.dialog)
        assert.equal(0.8, env.MainActionBar.alpha)
        assert.equal(1, env.MultiBarRight.alpha)
        -- A slider move while previewing shows at once.
        R.Visibility:SetRule("bars.main", { shownAlpha = 0.5 })
        step(R, 5)
        assert.equal(0.5, env.MainActionBar.alpha)
        attach(dialog, env.ChatFrame1)
        assert.same({ "chat.frames", "chat.tabs", "chat.buttons", "chat.inputArt" }, env.companion.ids)
        assert.equal(1, env.MainActionBar.alpha)
        -- A system with no group of ours closes the companion; so does the dialog hiding.
        attach(dialog, fakeFrame("SomethingElse"))
        assert.is_nil(env.companion.ids)
        attach(dialog, env.MinimapCluster)
        assert.same({ "hud.minimap", "hud.minimapButtons" }, env.companion.ids)
        dialog:Fire("OnHide")
        assert.is_nil(env.companion.ids)
        env.EventRegistry.callbacks["EditMode.Exit"]()
        step(R, 5)
        assert.equal(0, env.MainActionBar.alpha)
        -- Off: the companion closes and the hooks do nothing, and the frame is built once.
        local count = env.companion.openCount
        assert.is_true(R.Registry:Disable(MODULE))
        attach(dialog, env.MainActionBar)
        assert.is_nil(env.companion.ids)
        assert.equal(count, env.companion.openCount)
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal(1, #dialog.scripts.OnHide)
        assert.equal(0, #R.errors)
    end)

    it("hovers unit frames through their tooltip and puts no script on a secure button", function()
        local env, R, module = base()
        R.Visibility:ApplyPreset("immersion")
        assert.is_true(R.Registry:Enable(MODULE))
        for name, id in pairs({ PlayerFrame = "unit.player", TargetFrame = "unit.target", PartyFrame = "unit.party",
            CompactRaidFrameContainer = "unit.raid" }) do
            assert.equal("ok", module.groups[id].status, name)
        end
        for _, name in ipairs({ "PlayerFrame", "TargetFrame", "PartyFrame", "PetFrame" }) do
            assert.is_nil(env[name].scripts.OnEnter, name)
        end
        assert.is_nil(env.PlayerFrame.children[1].scripts.OnEnter)
        -- The raid container and its manager tab are plain frames and do carry the hook.
        assert.equal(1, #env.CompactRaidFrameManager.scripts.OnEnter)
        step(R, 5)
        assert.equal(0, env.PlayerFrame.alpha)
        assert.equal(0, env.PartyFrame.alpha)
        assert.equal(0, env.CompactRaidFrameManager.alpha)
        -- The unit frames share the top zone, so the player's tooltip brings them all.
        tooltipOn(env, env.PlayerFrame)
        step(R, 5)
        assert.equal(1, env.PlayerFrame.alpha)
        assert.equal(1, env.TargetFrame.alpha)
        assert.equal(1, env.PartyFrame.alpha)
        assert.equal(0, env.MainActionBar.alpha)
        tooltipOff(env)
        settle(env, R)
        assert.equal(0, env.PlayerFrame.alpha)
        assert.equal(0, env.TargetFrame.alpha)
        -- The pet frame reaches the player frame's group through its parents.
        R.Visibility:SetRules({ "unit.player", "unit.target", "unit.party", "unit.raid" }, { zone = "none" })
        step(R, 5)
        tooltipOn(env, env.PetFrame)
        step(R, 5)
        assert.equal(1, env.PlayerFrame.alpha)
        assert.equal(0, env.TargetFrame.alpha)
        tooltipOff(env)
        settle(env, R)
        assert.equal(0, env.PlayerFrame.alpha)
        -- A tooltip on a frame of nobody's changes nothing.
        tooltipOn(env, fakeFrame("ArenaEnemy1"))
        step(R, 5)
        assert.equal(0, env.PlayerFrame.alpha)
        tooltipOff(env)
        -- Party and raid are Edit Mode systems of their own.
        assert.same({ "unit.party" }, R.Visibility:GroupsForSystem(env.PartyFrame))
        assert.same({ "unit.raid" }, R.Visibility:GroupsForSystem(env.CompactRaidFrameContainer))
        assert.is_true(R.Registry:Disable(MODULE))
        tooltipOn(env, env.PlayerFrame)
        step(R, 5)
        assert.equal(1, env.PlayerFrame.alpha)
        assert.equal(0, #R.errors)
    end)

    it("restores every frame and leaves every hook inert across enable, disable, enable", function()
        local env, R, module = base()
        R.Visibility:ApplyPreset("immersion")
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal(0, env.MainActionBar.alpha)
        assert.equal(0, env.ChatFrame1ButtonFrame.alpha)
        local hooks = env.hookCount
        assert.is_true(hooks >= 2)
        -- Mid-fade on the way in, so a fade record and the watch are live when the module goes off.
        tooltipOn(env, env.MainActionBar.children[1])
        assert.is_true(R.Fade:Active() > 0)
        assert.is_true(env:ActiveTimers() > 0)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal("disabled", module.state)
        for name, frame in pairs(env.fakes) do
            assert.equal(name == "ChatFrame1ButtonFrame" and 0.2 or 1, frame.alpha, name)
        end
        assert.equal(0, R.Fade:Active())
        assert.is_nil(R.Fade.driver:GetScript("OnUpdate"))
        assert.equal(0, env:ActiveTimers())
        assert.equal(0, R.Conditions.count)
        assert.is_nil(R.Broker.events.PLAYER_REGEN_DISABLED)
        assert.is_nil(R.Broker.events.CURSOR_CHANGED)
        for event, entries in pairs(R.Broker.events) do
            for _, entry in ipairs(entries) do
                assert.is_not.equal(module, entry.owner, event)
            end
        end
        -- The hooks stay installed and do nothing.
        tooltipOn(env, env.MainActionBar.children[1])
        env.GeneralDockManager:Fire("OnEnter")
        env.hooks.FCF_FadeInChatFrame(env.ChatFrame1)
        env.ChatFrame1.editBox:Fire("OnEditFocusGained")
        env.EventRegistry.callbacks["EditMode.Enter"]()
        env:Fire("PLAYER_REGEN_DISABLED")
        env:Advance(1)
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(1, env.ChatFrame1.alpha)
        assert.equal(0, R.Fade:Active())
        assert.equal(0, env:ActiveTimers())
        -- On again: the same hooks serve, nothing is installed twice, and the rule applies.
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal(hooks, env.hookCount)
        assert.equal(1, #env.GeneralDockManager.scripts.OnEnter)
        assert.equal(0, env.MainActionBar.alpha)
        tooltipOn(env, env.MainActionBar.children[1])
        step(R, 5)
        assert.equal(1, env.MainActionBar.alpha)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0, #R.errors)
    end)

    it("marks a group missing when a frame it needs is gone and keeps the rest working", function()
        local env, R, module = base({ missing = { MultiBar7 = true, ChatFrame9 = true } })
        R.Visibility:ApplyPreset("immersion")
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("missing", module.groups["bars.seven"].status)
        assert.equal("MultiBar7", module.groups["bars.seven"].missing)
        assert.equal("ok", module.groups["chat.frames"].status)
        assert.equal(0, env.ChatFrame10.alpha)
        assert.equal(0, env.MultiBar6.alpha)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.MultiBar6.alpha)
    end)

    it("stands down per group behind a bar addon and as a whole behind ElvUI", function()
        local env, R, module = base({ loaded = { Bartender4 = true } })
        R.Visibility:ApplyPreset("immersion")
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("owned", module.groups["bars.main"].status)
        assert.equal("Bartender4", module.groups["bars.main"].owner)
        assert.equal("ok", module.groups["chat.frames"].status)
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0, env.ChatFrame1.alpha)
        assert.is_true(R.Registry:Disable(MODULE))

        local env2, R2, module2 = base({ loaded = { ElvUI = true } })
        R2.Visibility:ApplyPreset("immersion")
        assert.is_false(R2.Registry:Enable(MODULE))
        assert.equal("unavailable", module2.state)
        assert.equal("Handled by ElvUI, which replaces these frames.", module2.unavailableReason)
        assert.equal(1, env2.ChatFrame1.alpha)
        assert.equal(0, env2.hookCount)
        -- The conflict panel lists the three neighbours against this module.
        local found = R2.Integrations:Conflicts()
        assert.equal(1, #found)
        assert.equal("ElvUI", found[1].addon)
        assert.equal(module2, found[1].module)
    end)

    it("fades the minimap's quest areas only when asked, and puts them back at its own strength", function()
        local env, R = base()
        R.Visibility:ApplyPreset("immersion")
        R.Visibility:SetRule("hud.minimap", { zone = "none" })
        assert.is_true(R.Registry:Enable(MODULE))
        step(R, 5)
        assert.equal(0, env.MinimapCluster.alpha)
        -- Off by default: not one setter is called, the client's own values stand.
        assert.same({}, env.blobs)
        R.Settings:SetOption("uiVisibilityBlobs", true)
        step(R, 5)
        assert.equal(0, env.blobs.SetQuestBlobRingAlpha)
        assert.equal(0, env.blobs.SetArchBlobInsideAlpha)
        local count = 0
        for _ in pairs(env.blobs) do count = count + 1 end
        assert.equal(9, count)
        env.MinimapCluster.mouseOver = true
        env.MinimapCluster:Fire("OnEnter")
        step(R, 5)
        assert.equal(1, env.blobs.SetQuestBlobRingAlpha)
        assert.equal(0, env.blobs.SetQuestBlobInsideAlpha)
        assert.equal(1, env.blobs.SetTaskBlobRingAlpha)
        env.MinimapCluster.mouseOver = false
        settle(env, R)
        assert.equal(0, env.blobs.SetQuestBlobRingAlpha)
        -- Opting out again while hidden puts the areas back to shown and leaves them alone after.
        R.Settings:SetOption("uiVisibilityBlobs", false)
        assert.equal(1, env.blobs.SetQuestBlobRingAlpha)
        env.blobs = {}
        env.MinimapCluster.mouseOver = true
        env.MinimapCluster:Fire("OnEnter")
        step(R, 5)
        assert.same({}, env.blobs)
        R.Settings:SetOption("uiVisibilityBlobs", true)
        env.MinimapCluster.mouseOver = false
        settle(env, R)
        assert.equal(0, env.blobs.SetQuestBlobRingAlpha)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.blobs.SetQuestBlobRingAlpha)
        assert.equal(0, env.blobs.SetQuestBlobOutsideAlpha)
        assert.equal(0, R.Fade:Active())
    end)

    it("hooks a Blizzard alpha reset named by a group and snaps the rule back", function()
        local env, R, module = base()
        env.BuffFrame = fakeFrame("BuffFrame")
        env.BuffFrame.UpdateSystemSettingOpacity = function(frame) frame.alpha = 0.5 end
        env.PlayerFrame.UpdateSystemSettingOpacity = function(frame) frame.alpha = 0.5 end
        table.insert(R.Visibility.groups, { id = "hud.buffs", kind = "hud", labelKey = "X", frames = { "BuffFrame" },
            optional = {}, hover = { frames = true }, reapply = { { frame = "BuffFrame",
            method = "UpdateSystemSettingOpacity" }, "MissingGlobal" } })
        R.Visibility:ApplyPreset("immersion")
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("ok", module.groups["hud.buffs"].status)
        assert.equal(0, env.BuffFrame.alpha)
        assert.is_function(env.hooks[env.BuffFrame].UpdateSystemSettingOpacity)
        assert.is_nil(env.hooks.MissingGlobal)
        env.BuffFrame.UpdateSystemSettingOpacity(env.BuffFrame)
        env.hooks[env.BuffFrame].UpdateSystemSettingOpacity(env.BuffFrame)
        assert.equal(0, env.BuffFrame.alpha)
        assert.equal(0, R.Fade:Active())
        -- The player frame's Edit Mode opacity is a baseline: the rule becomes a share of it.
        env.PlayerFrame.UpdateSystemSettingOpacity(env.PlayerFrame)
        env.hooks[env.PlayerFrame].UpdateSystemSettingOpacity(env.PlayerFrame)
        assert.equal(0, env.PlayerFrame.alpha)
        assert.equal(0.5, module.captured[env.PlayerFrame])
        R.Visibility:SetRule("unit.player", { mode = "always" })
        step(R, 5)
        assert.equal(0.5, env.PlayerFrame.alpha)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.BuffFrame.alpha)
        assert.equal(0.5, env.PlayerFrame.alpha)
        table.remove(R.Visibility.groups)
    end)

    it("reveals every group a shared frame belongs to and resolves a child by its parent key", function()
        local env, R, module = base()
        R.Visibility:ApplyPreset("immersion")
        R.Visibility:SetRules({ "hud.minimap", "hud.minimapButtons", "hud.objectives" }, { zone = "none" })
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("ok", module.groups["hud.minimapButtons"].status)
        assert.equal(0, env.MinimapCluster.alpha)
        assert.equal(0, env.GameTimeFrame.alpha)
        assert.equal(0, env.MinimapCluster.Tracking.alpha)
        assert.equal(0, env.Minimap.ZoomIn.alpha)
        -- Chat input art is textures: hidden under the preset, no hover hooks asked of it.
        assert.equal(0, env.ChatFrame1EditBoxLeft.alpha)
        assert.equal(0, env.ChatFrame4EditBoxFocusMid.alpha)
        assert.equal(1, env.ChatFrame1.editBox.alpha)
        env.GameTimeFrame.mouseOver = true
        env.GameTimeFrame:Fire("OnEnter")
        step(R, 5)
        assert.equal(1, env.MinimapCluster.alpha)
        assert.equal(1, env.GameTimeFrame.alpha)
        assert.equal(2, #env.GameTimeFrame.scripts.OnEnter)
        env.GameTimeFrame.mouseOver = false
        settle(env, R)
        assert.equal(0, env.MinimapCluster.alpha)
        assert.equal(0, env.GameTimeFrame.alpha)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.MinimapCluster.Tracking.alpha)
        assert.equal(1, env.ChatFrame1EditBoxLeft.alpha)
    end)
end)
