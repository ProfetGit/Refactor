local Runtime = require("Tests.mock.runtime")
local json = require("dkjson")

local MODULE = "interface.visibility"

-- A Blizzard frame as the module sees it: alpha, script hooks, children and a mouse flag.
local function fakeFrame(name, alpha, children)
    local frame = { name = name, alpha = alpha or 1, scripts = {}, children = children or {}, mouseOver = false,
        shown = false, protected = false, mouse = true }
    function frame:IsShown() return self.shown end
    function frame:IsMouseMotionEnabled() return self.mouse end
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
    env.IsInInstance = function() return env.world.instance ~= nil, env.world.instance or "none" end
    env.IsStealthed = function() return false end
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitCastingInfo = function() end
    env.UnitChannelInfo = function() end
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
    -- The module asks it to reread when the setup in use changes, since it names that setup.
    function env.companion:Load() self.loads = (self.loads or 0) + 1 end
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

-- A behaviour with every field, for the resolver and the validator.
local function behaviourOf(patch)
    local entry = { id = "test", resting = 0.2, revealed = 0.9, mouseover = true, reveal = {}, hide = {},
        together = false, fadeIn = 0.15, fadeOut = 0.4 }
    for key, value in pairs(patch or {}) do entry[key] = value end
    return entry
end

-- A whole option written at once: these behaviours, and assign(group) naming each group's.
local function apply(R, behaviours, assign)
    local settings = { behaviours = behaviours, setups = { world = {} } }
    for _, group in ipairs(R.Visibility.groups) do
        settings.setups.world[group.id] = assign(group)
    end
    assert.is_true(R.Settings:SetOption("uiVisibility", settings))
end

local function fadeAway(id, patch)
    local entry = behaviourOf({ id = id, resting = 0, revealed = 1, together = true })
    for key, value in pairs(patch or {}) do entry[key] = value end
    return entry
end

-- The first version's immersion preset rebuilt from behaviours: everything fades away and
-- comes back under the mouse a whole side of the screen at a time, each side a behaviour that
-- reveals together. The chat input art takes no mouse, so it simply stays faded. overrides
-- gives single groups another behaviour: "alone" comes back by itself, and extra adds more.
local SIDES = {
    ["chat.frames"] = "left", ["chat.tabs"] = "left", ["chat.buttons"] = "left",
    ["unit.player"] = "top", ["unit.target"] = "top", ["unit.party"] = "top", ["unit.raid"] = "top",
    ["hud.status"] = "bottom", ["hud.microMenu"] = "bottom", ["hud.bags"] = "bottom",
    ["hud.objectives"] = "right", ["hud.minimap"] = "right", ["hud.minimapButtons"] = "right",
}
local function immersion(R, overrides, extra)
    local behaviours = { fadeAway("left"), fadeAway("top"), fadeAway("bottom"), fadeAway("right"),
        fadeAway("alone", { together = false }), fadeAway("art", { mouseover = false, together = false }) }
    for _, entry in ipairs(extra or {}) do behaviours[#behaviours + 1] = entry end
    overrides = overrides or {}
    apply(R, behaviours, function(group)
        if overrides[group.id] ~= nil then
            return overrides[group.id] or nil
        end
        return group.kind == "bars" and "bottom" or SIDES[group.id] or "art"
    end)
end

describe("visibility rules", function()
    local env, R, Rules
    before_each(function()
        env = Runtime.new()
        R, Rules = env.R, env.R.Visibility
    end)

    it("resolves mouseover, then a hide, then a reveal, then rest, for every combination", function()
        -- mouseover on, hovered, a reveal condition holds, a hide condition holds, expected opacity
        local cases = {
            { true, true, true, true, 0.9 }, { true, true, true, false, 0.9 },
            { true, true, false, true, 0.9 }, { true, true, false, false, 0.9 },
            { true, false, true, true, 0 }, { true, false, true, false, 0.9 },
            { true, false, false, true, 0 }, { true, false, false, false, 0.2 },
            { false, true, true, true, 0 }, { false, true, true, false, 0.9 },
            { false, true, false, true, 0 }, { false, true, false, false, 0.2 },
            { false, false, true, true, 0 }, { false, false, true, false, 0.9 },
            { false, false, false, true, 0 }, { false, false, false, false, 0.2 },
        }
        local state = { combat = true, mounted = true, resting = false, dead = false }
        for _, case in ipairs(cases) do
            -- resting and dead never hold, so a set naming only one of them has no hit.
            local entry = behaviourOf({ mouseover = case[1],
                reveal = case[3] and { combat = true } or { resting = true },
                hide = case[4] and { mounted = true } or { dead = true } })
            assert.equal(case[5], Rules:Resolve(entry, state, case[2]),
                table.concat({ tostring(case[1]), tostring(case[2]), tostring(case[3]), tostring(case[4]) }, " "))
        end
    end)

    it("validates a behaviour and the whole option, and keeps the good parts of a bad saved table", function()
        assert.is_true(Rules:ValidSettings(Rules:Default()))
        for _, starter in ipairs(Rules.starters) do
            assert.is_true(Rules:ValidBehaviour(starter), starter.id)
        end
        assert.is_true(Rules:ValidBehaviour(behaviourOf()))
        assert.is_true(Rules:ValidBehaviour(behaviourOf({ name = "Raid bars", resting = 0, revealed = 0.1 })))
        local broken = {
            { resting = -0.1 }, { revealed = 0.05 }, { revealed = 1.5 }, { fadeIn = 3 }, { fadeOut = 0 / 0 },
            { mouseover = "yes" }, { together = 1 }, { reveal = { flying = true } }, { hide = { combat = 1 } },
            -- The instance kinds pick a setup; they are not triggers.
            { reveal = { raid = true } },
            -- One condition cannot both reveal and hide.
            { reveal = { combat = true }, hide = { combat = true } },
            { extra = true }, { id = "1x" }, { id = "a b" }, { id = 7 },
            { name = "" }, { name = "two\nlines" }, { name = string.rep("x", 33) }, { name = " lead" },
        }
        for index, patch in ipairs(broken) do
            assert.is_false(Rules:ValidBehaviour(behaviourOf(patch)), "case " .. index)
        end
        local missing = behaviourOf()
        missing.fadeIn = nil
        assert.is_false(Rules:ValidBehaviour(missing))

        local function settings(patch)
            local value = { behaviours = { behaviourOf() }, setups = { world = { ["bars.main"] = "test" } } }
            for key, part in pairs(patch or {}) do value[key] = part end
            return value
        end
        assert.is_true(Rules:ValidSettings(settings()))
        assert.is_true(Rules:ValidSettings(settings({ setups = { world = {}, raid = { ["hud.gone"] = "test" } } })))
        assert.is_false(Rules:ValidSettings(settings({ setups = { raid = {} } })))
        assert.is_false(Rules:ValidSettings(settings({ setups = { world = {}, moon = {} } })))
        assert.is_false(Rules:ValidSettings(settings({ setups = { world = { ["bars.main"] = "nope" } } })))
        assert.is_false(Rules:ValidSettings(settings({ setups = { world = { ["not an id"] = "test" } } })))
        assert.is_false(Rules:ValidSettings(settings({ behaviours = { behaviourOf(), behaviourOf() } })))
        assert.is_false(Rules:ValidSettings(settings({ behaviours = { [2] = behaviourOf() } })))
        assert.is_false(Rules:ValidSettings(settings({ preset = "off" })))
        assert.is_false(R.Settings:SetOption("uiVisibility", settings({ setups = {} })))

        -- At login one bad behaviour costs itself and its assignments, not everything else.
        local account = { options = { uiVisibility = {
            behaviours = { behaviourOf(), behaviourOf({ id = "bad", resting = 4 }) },
            setups = { world = { ["bars.main"] = "test", ["bars.right"] = "bad" }, moon = {},
                city = { ["hud.bags"] = "test" } },
        } } }
        R.Settings:Init(account, {}, "Player-test")
        local value = account.options.uiVisibility
        assert.equal(1, #value.behaviours)
        assert.same({ ["bars.main"] = "test" }, value.setups.world)
        assert.same({ ["hud.bags"] = "test" }, value.setups.city)
        assert.is_nil(value.setups.moon)
        -- Something that is not a table at all is replaced by the default.
        account = { options = { uiVisibility = "everything" } }
        R.Settings:Init(account, {}, "Player-test")
        assert.same(Rules:Default(), account.options.uiVisibility)
    end)

    it("converts the first version's rules, one behaviour per distinct rule and zone", function()
        env:Load("Locales/Visibility.enUS.lua")
        local function rule(patch)
            local old = { mode = "mouseover", showWhen = { combat = true },
                hideWhen = { combat = true, mounted = true }, fadeIn = 0.2, fadeOut = 0.5, shownAlpha = 0.8,
                hiddenAlpha = 0.1, zone = "bottom" }
            for key, value in pairs(patch or {}) do old[key] = value end
            return old
        end
        local account = { options = { uiVisibility = { preset = "custom", groups = {
            ["bars.main"] = rule(), ["bars.right"] = rule(),
            -- The same rule in another zone stays apart, so two sides never merge.
            ["hud.bags"] = rule({ zone = "right" }),
            -- Always visible with nothing hiding it is the game's own look: no behaviour.
            ["chat.frames"] = rule({ mode = "always", showWhen = {}, hideWhen = {}, shownAlpha = 1, zone = "left" }),
            ["chat.tabs"] = rule({ mode = "always", showWhen = { resting = true }, hideWhen = { mounted = true },
                shownAlpha = 0.6, zone = "none" }),
            ["unit.player"] = rule({ mode = "hidden", hideWhen = {}, hiddenAlpha = 0.3, zone = "top" }),
            ["hud.gone"] = rule({ zone = "none" }),
            ["bad id"] = rule(),
        } } } }
        R.Settings:Init(account, {}, "Player-test")
        local value = account.options.uiVisibility
        assert.is_true(Rules:ValidSettings(value))
        for index, starter in ipairs(Rules.starters) do
            assert.equal(starter.id, value.behaviours[index].id)
        end
        assert.equal(#Rules.starters + 5, #value.behaviours)
        local main = Rules:BehaviourFor("bars.main", "world")
        assert.equal(main, Rules:BehaviourFor("bars.right", "world"))
        -- A show condition beat a hide on the same condition, so combat stays a reveal.
        assert.same({ id = main.id, name = main.name, resting = 0.1, revealed = 0.8, mouseover = true,
            reveal = { combat = true }, hide = { mounted = true }, together = true, fadeIn = 0.2, fadeOut = 0.5 }, main)
        assert.truthy(main.name:match("^Imported %d$"))
        assert.is_not.equal(main.id, Rules:BehaviourFor("hud.bags", "world").id)
        assert.is_nil(Rules:BehaviourFor("chat.frames", "world"))
        local tabs = Rules:BehaviourFor("chat.tabs", "world")
        assert.same({ 0.6, 0.6, false, {}, { mounted = true }, false },
            { tabs.resting, tabs.revealed, tabs.mouseover, tabs.reveal, tabs.hide, tabs.together })
        local player = Rules:BehaviourFor("unit.player", "world")
        assert.same({ 0.3, 0.8, false, { combat = true }, true },
            { player.resting, player.revealed, player.mouseover, player.reveal, player.together })
        assert.is_string(value.setups.world["hud.gone"])
        assert.is_nil(value.setups.world["bad id"])
        -- Converted once: a second login changes nothing.
        assert.same(value, Rules:Clean(value))
    end)

    it("edits, copies, renames and deletes behaviours, and every element that has one follows", function()
        env:Load("Locales/Visibility.enUS.lua")
        local seen = {}
        R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", function(_, _, key) seen[#seen + 1] = key end, seen)
        assert.is_true(Rules:Assign({ "bars.main", "bars.right" }, "world", "combatHud"))
        assert.same({ "uiVisibility" }, seen)
        assert.equal(2, Rules:Uses("combatHud"))
        assert.is_true(Rules:UpdateBehaviour("combatHud", { resting = 0.4, together = true }))
        assert.equal(0.4, Rules:BehaviourFor("bars.right", "world").resting)
        assert.is_true(Rules:BehaviourFor("bars.main", "world").together)
        seen = {}
        assert.is_false(Rules:UpdateBehaviour("combatHud", { resting = 2 }))
        assert.is_false(Rules:UpdateBehaviour("combatHud", { reveal = {} }))
        assert.is_false(Rules:UpdateBehaviour("combatHud", { id = "other" }))
        assert.is_false(Rules:UpdateBehaviour("nope", { resting = 0.1 }))
        assert.equal(0, #seen)

        -- A condition reveals, hides or neither; moving it to one takes it out of the other.
        assert.is_true(Rules:SetCondition("combatHud", "combat", "hide"))
        local entry = Rules:Behaviour("combatHud")
        assert.is_nil(entry.reveal.combat)
        assert.equal("hide", Rules:ConditionRole(entry, "combat"))
        assert.equal("reveal", Rules:ConditionRole(entry, "hasTarget"))
        assert.is_true(Rules:SetCondition("combatHud", "combat", nil))
        assert.is_nil(Rules:ConditionRole(Rules:Behaviour("combatHud"), "combat"))
        assert.is_false(Rules:SetCondition("combatHud", "raid", "reveal"))
        assert.is_false(Rules:SetCondition("combatHud", "combat", "both"))

        -- A copy sits right after its source and has no elements; the source keeps its own.
        local copy = Rules:CopyBehaviour("combatHud")
        assert.equal("Combat HUD copy", Rules:Name(Rules:Behaviour(copy)))
        assert.equal(copy, Rules:Behaviours()[3].id)
        assert.equal(0.4, Rules:Behaviour(copy).resting)
        assert.equal(0, Rules:Uses(copy))
        assert.equal(2, Rules:Uses("combatHud"))
        assert.equal("Combat HUD copy 2", Rules:Name(Rules:Behaviour(Rules:CopyBehaviour("combatHud"))))
        local fresh = Rules:CopyBehaviour(nil)
        assert.equal(fresh, Rules:Behaviours()[#Rules:Behaviours()].id)
        assert.equal("New behaviour", Rules:Name(Rules:Behaviour(fresh)))

        assert.same({ true }, { Rules:RenameBehaviour(copy, "  Raid bars  ") })
        assert.equal("Raid bars", Rules:Name(Rules:Behaviour(copy)))
        assert.same({ false, "name_taken" }, { Rules:RenameBehaviour(fresh, "raid BARS") })
        -- A starter's name is taken too, though it is only a locale key.
        assert.same({ false, "name_taken" }, { Rules:RenameBehaviour(fresh, "Fade away") })
        assert.same({ false, "invalid_name" }, { Rules:RenameBehaviour(fresh, "   ") })
        assert.same({ false, "invalid_name" }, { Rules:RenameBehaviour(fresh, string.rep("x", 33)) })
        assert.same({ false, "missing" }, { Rules:RenameBehaviour("nope", "Name") })

        -- Deleted, its elements go back to the game's own look.
        assert.is_true(Rules:DeleteBehaviour("combatHud"))
        assert.is_nil(Rules:BehaviourFor("bars.main", "world"))
        assert.equal(0, Rules:Uses("combatHud"))
        assert.is_false(Rules:DeleteBehaviour("combatHud"))

        -- What Settings hands out is a copy: editing it changes nothing saved.
        Rules:Settings().behaviours[1].resting = 0.99
        assert.equal(0, Rules:Behaviours()[1].resting)
        -- There is a ceiling, and a copy past it is refused rather than dropped later.
        local last
        repeat last = Rules:CopyBehaviour("fadeAway") until not last
        assert.same({ nil, "full" }, { Rules:CopyBehaviour("fadeAway") })
        assert.is_true(Rules:ValidSettings(R.Settings:GetOption("uiVisibility")))
    end)

    it("hands behaviours out per setup, a place without its own following World's", function()
        assert.same({}, R.Settings:GetOption("uiVisibility").setups.world)
        assert.is_true(Rules:Assign({ "bars.main" }, "world", "fadeAway"))
        assert.is_false(Rules:HasOwnSetup("city"))
        assert.is_false(Rules:Assign({ "bars.main" }, "city", "combatHud"))
        assert.equal("fadeAway", Rules:BehaviourFor("bars.main", "city").id)
        -- Its own setup starts as a copy of World's and then goes its own way.
        assert.is_true(Rules:SetOwnSetup("city", true))
        assert.equal("fadeAway", Rules:BehaviourFor("bars.main", "city").id)
        assert.is_true(Rules:Assign({ "bars.main" }, "city", nil))
        assert.is_nil(Rules:BehaviourFor("bars.main", "city"))
        assert.equal("fadeAway", Rules:BehaviourFor("bars.main", "world").id)
        assert.is_false(Rules:SetOwnSetup("world", false))
        assert.is_false(Rules:SetOwnSetup("moon", true))
        assert.is_false(Rules:Assign({ "bars.main", "hud.nothing" }, "world", "combatHud"))
        assert.is_false(Rules:Assign({ "bars.main" }, "world", "nope"))
        assert.is_false(Rules:Assign({}, "world", "fadeAway"))
        assert.is_false(Rules:Assign("bars.main", "world", "fadeAway"))
        assert.equal("fadeAway", Rules:BehaviourFor("bars.main", "world").id)

        -- An instance says more than a rest area inside it; a place without a setup uses World's.
        assert.equal("world", Rules:PlaceOf({}))
        assert.equal("city", Rules:PlaceOf({ resting = true }))
        assert.equal("dungeon", Rules:PlaceOf({ dungeon = true, resting = true }))
        assert.equal("raid", Rules:PlaceOf({ raid = true }))
        assert.equal("pvp", Rules:PlaceOf({ pvp = true }))
        assert.equal("city", Rules:SetupPlace({ resting = true }))
        assert.equal("world", Rules:SetupPlace({ raid = true }))
        -- Giving the setup up goes back to World's.
        assert.is_true(Rules:SetOwnSetup("city", false))
        assert.equal("fadeAway", Rules:BehaviourFor("bars.main", "city").id)
        assert.equal("world", Rules:SetupPlace({ resting = true }))
    end)

    it("maps an Edit Mode system frame to its groups", function()
        local R2 = env.R
        env.ChatFrame1, env.MainActionBar = {}, {}
        env.MainStatusTrackingBarContainer, env.SecondaryStatusTrackingBarContainer = {}, {}
        assert.same({ "chat.frames", "chat.tabs", "chat.buttons", "chat.inputArt" },
            R2.Visibility:GroupsForSystem(env.ChatFrame1))
        assert.same({ "bars.main" }, R2.Visibility:GroupsForSystem(env.MainActionBar))
        assert.same({ "hud.status" }, R2.Visibility:GroupsForSystem(env.SecondaryStatusTrackingBarContainer))
        assert.same({}, R2.Visibility:GroupsForSystem({}))
        assert.same({}, R2.Visibility:GroupsForSystem(nil))
        -- Every group is listed under one of the setup list's headings.
        local kinds = {}
        for _, kind in ipairs(Rules.kinds) do kinds[kind] = true end
        for _, group in ipairs(Rules.groups) do
            assert.is_true(kinds[group.kind], group.id)
        end
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

describe("fade driver values", function()
    it("eases a value through its writer, retargets from where it is, and goes idle", function()
        local env = Runtime.new()
        local Fade = env.R.Fade
        local owner, writes = {}, {}
        local function write(key, value)
            assert.equal(owner, key)
            writes[#writes + 1] = value
        end
        -- A fresh tween writes its start at once, so the frame never shows a reset value.
        Fade:Value(owner, 1, 0.5, write, 0)
        assert.same({ 0 }, writes)
        assert.equal(1, Fade:Active())
        step(env.R, 0.25)
        assert.is_true(math.abs(writes[#writes] - 0.5) < 1e-9)
        -- Eased: a quarter of the way in time is well short of a quarter of the distance.
        Fade:Value(owner, 0, 0.5, write, 99)
        step(env.R, 0.125)
        assert.is_true(math.abs(writes[#writes] - 0.5 * (1 - 0.15625)) < 1e-9)
        step(env.R, 1)
        assert.equal(0, writes[#writes])
        assert.equal(0, Fade:Active())
        assert.is_nil(Fade.driver:GetScript("OnUpdate"))
        -- Nowhere to go, no start, or no time: one write and no record.
        local count = #writes
        Fade:Value(owner, 0.4, 0.5, write, 0.4)
        Fade:Value(owner, 0.6, 0.5, write)
        Fade:Value(owner, 0.8, 0, write, 0)
        assert.same({ 0.4, 0.6, 0.8 }, { writes[count + 1], writes[count + 2], writes[count + 3] })
        assert.equal(0, Fade:Active())
        -- Cancel stops it where it is; an error in the writer ends the tween instead of the driver
        -- running forever.
        Fade:Value(owner, 1, 1, write, 0)
        Fade:Cancel(owner)
        assert.equal(0, Fade:Active())
        assert.is_nil(Fade.driver:GetScript("OnUpdate"))
        local broken = {}
        Fade:Value(broken, 1, 1, function(_, value) if value > 0 then error("boom") end end, 0)
        step(env.R, 0.1)
        assert.equal(0, Fade:Active())
        assert.is_nil(Fade.driver:GetScript("OnUpdate"))
        -- A value and a frame share the driver without one writing to the other.
        local frame = fakeFrame("Frame", 1)
        Fade:To(frame, 0, 1)
        Fade:Value(owner, 1, 1, write, 0)
        assert.equal(2, Fade:Active())
        step(env.R, 2)
        assert.equal(0, frame.alpha)
        assert.equal(1, writes[#writes])
        assert.equal(0, Fade:Active())
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
        -- A fresh install gives no element a behaviour, so every frame keeps the alpha it had,
        -- including the button frame's 0.2.
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0.2, env.ChatFrame1ButtonFrame.alpha)
        assert.equal(0, R.Fade:Active())

        immersion(R)
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

        -- A button's tooltip is the hover; the bar and everything sharing its behaviour come back.
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
        -- Still over one of them: the watch keeps it. Off everything: one tick drops it.
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
        -- The chat buttons share the windows' behaviour, so they come along.
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

        -- Conditions: bars and unit frames gone until combat reveals them, the rest at rest.
        apply(R, { behaviourOf({ id = "combat", resting = 0, revealed = 1, mouseover = false,
            reveal = { combat = true } }), fadeAway("rest", { together = false }) }, function(group)
            return (group.kind == "bars" or group.kind == "unit") and "combat" or "rest"
        end)
        step(R, 5)
        assert.equal(0, env.MultiBarRight.alpha)
        env.world.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0, env.ChatFrame1.alpha)
        env.world.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        step(R, 5)
        assert.equal(0, env.MultiBarRight.alpha)
        -- A hide beats a reveal: mounted in combat stays clean. Mouseover still reaches it.
        apply(R, { behaviourOf({ id = "clean", resting = 1, revealed = 1, reveal = { combat = true },
            hide = { mounted = true } }) }, function() return "clean" end)
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        assert.equal(1, env.ChatFrame1.alpha)
        env.world.mounted = true
        env:Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
        step(R, 5)
        assert.equal(0, env.MultiBarRight.alpha)
        assert.equal(0, env.ChatFrame1.alpha)
        env.world.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        step(R, 5)
        assert.equal(0, env.MultiBarRight.alpha)
        tooltipOn(env, env.MultiBarRight)
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        assert.equal(0, env.MainActionBar.alpha)
        tooltipOff(env)
        settle(env, R)
        assert.equal(0, env.MultiBarRight.alpha)
        -- Casting is a condition like the rest: a bar can step aside while a cast runs, and
        -- only the player's own cast counts.
        apply(R, { behaviourOf({ id = "cast", resting = 1, revealed = 1, mouseover = false,
            hide = { casting = true } }) }, function() return "cast" end)
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        env:Fire("UNIT_SPELLCAST_START", "party1")
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        env:Fire("UNIT_SPELLCAST_START", "player")
        step(R, 5)
        assert.equal(0, env.MultiBarRight.alpha)
        env:Fire("UNIT_SPELLCAST_STOP", "player")
        step(R, 5)
        assert.equal(1, env.MultiBarRight.alpha)
        immersion(R)
        step(R, 5)

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
        immersion(R, { ["hud.minimap"] = "alone" })
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

    it("never hooks a frame that takes no mouse, so nothing under it loses its tooltip", function()
        local env, R = base()
        local overlay, blip = fakeFrame("MinimapBackdrop"), fakeFrame("MinimapPin")
        overlay.mouse = false
        env.MinimapCluster.children = { env.GameTimeFrame, overlay, blip }
        immersion(R)
        assert.is_true(R.Registry:Enable(MODULE))
        assert.is_nil(overlay.scripts.OnEnter)
        assert.equal(1, #blip.scripts.OnEnter)
        assert.equal(0, #R.errors)
    end)

    it("reveals every element of a together behaviour from any one of them, and only itself otherwise", function()
        local env, R = base()
        immersion(R)
        assert.is_true(R.Registry:Enable(MODULE))
        step(R, 5)
        -- The bags share the bars' behaviour: their tooltip brings the bars back.
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
        -- Given a behaviour of its own, the main bar answers to its own hover alone.
        R.Visibility:Assign({ "bars.main" }, "world", "alone")
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
        immersion(R, { ["bars.main"] = "dim" }, { fadeAway("dim", { revealed = 0.7 }) })
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

    it("fades to the behaviour's own resting and revealed opacity", function()
        local env, R = base()
        immersion(R, { ["bars.main"] = "dim", ["chat.buttons"] = "half" }, {
            fadeAway("dim", { resting = 0.3, revealed = 0.8, together = false }),
            behaviourOf({ id = "half", resting = 0.5, revealed = 0.5 }) })
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal(0.3, env.MainActionBar.alpha)
        assert.equal(0, env.MultiBarRight.alpha)
        tooltipOn(env, env.MainActionBar.children[1])
        step(R, 5)
        assert.equal(0.8, env.MainActionBar.alpha)
        -- A share of the frame's own alpha: the button frame ships at 0.2.
        step(R, 5)
        assert.is_true(math.abs(env.ChatFrame1ButtonFrame.alpha - 0.1) < 1e-9)
        -- Edit Mode ignores the behaviour and shows the frame as the game has it.
        env.EventRegistry.callbacks["EditMode.Enter"]()
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0.2, env.ChatFrame1ButtonFrame.alpha)
        env.EventRegistry.callbacks["EditMode.Exit"]()
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0.2, env.ChatFrame1ButtonFrame.alpha)
    end)

    it("opens the companion beside Blizzard's dialog for the selected system", function()
        local env, R = base()
        immersion(R)
        assert.is_true(R.Registry:Enable(MODULE))
        local dialog = env.EditModeSystemSettingsDialog
        local attach = env.hooks[dialog].AttachToSystemFrame
        assert.is_function(attach)
        env.EventRegistry.callbacks["EditMode.Enter"]()
        assert.equal(1, env.MainActionBar.alpha)
        attach(dialog, env.MainActionBar)
        assert.same({ "bars.main" }, env.companion.ids)
        assert.equal(dialog, env.companion.dialog)
        -- Nothing previews: what is being moved stays as the game has it.
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(1, env.MultiBarRight.alpha)
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
        immersion(R)
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
        -- The unit frames share a behaviour, so the player's tooltip brings them all.
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
        R.Visibility:Assign({ "unit.player", "unit.target", "unit.party", "unit.raid" }, "world", "alone")
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
        immersion(R)
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
        immersion(R)
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("missing", module.groups["bars.seven"].status)
        assert.equal("MultiBar7", module.groups["bars.seven"].missing)
        assert.equal("ok", module.groups["chat.frames"].status)
        assert.equal(0, env.ChatFrame10.alpha)
        assert.equal(0, env.MultiBar6.alpha)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.MultiBar6.alpha)
    end)

    it("fades a frame another feature hands to a group, and gives it back when it leaves", function()
        local env, R, module = base()
        local copy = fakeFrame("RefactorChatCopy")
        assert.is_false(R.Visibility:Contribute("chat.nosuchgroup", copy))
        assert.is_true(R.Visibility:Contribute("chat.buttons", copy))
        -- Twice is once: a second enable of the owning module must not double the group.
        assert.is_true(R.Visibility:Contribute("chat.buttons", copy))
        assert.equal(1, #R.Visibility:Contributions("chat.buttons"))
        immersion(R)
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal(0, copy.alpha)
        -- It hovers like any other frame in the group, so reaching for it reveals it.
        copy.mouseOver = true
        copy:Fire("OnEnter")
        settle(env, R)
        assert.equal(1, copy.alpha)
        assert.equal(1, env.ChatFrame1ButtonFrame.alpha / 0.2)
        copy.mouseOver = false
        settle(env, R)
        assert.equal(0, copy.alpha)
        -- Handed over while the module is already running, a frame joins there and then.
        local second = fakeFrame("RefactorChatCopy2")
        assert.is_true(R.Visibility:Contribute("chat.buttons", second))
        settle(env, R)
        assert.equal(0, second.alpha)
        -- Withdrawn, it goes back to the alpha the group found it at rather than staying faded.
        assert.is_true(R.Visibility:Withdraw("chat.buttons", second))
        assert.equal(1, second.alpha)
        assert.is_false(R.Visibility:Withdraw("chat.buttons", second))
        local frames = module.groups["chat.buttons"].frames
        local held = false
        for _, frame in ipairs(frames) do
            held = held or frame == second
        end
        assert.is_false(held)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, copy.alpha)
        assert.is_true(R.Visibility:Withdraw("chat.buttons", copy))
        assert.equal(0, #R.Visibility:Contributions("chat.buttons"))
    end)

    it("stands down per group behind a bar addon and as a whole behind ElvUI", function()
        local env, R, module = base({ loaded = { Bartender4 = true } })
        immersion(R)
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("owned", module.groups["bars.main"].status)
        assert.equal("Bartender4", module.groups["bars.main"].owner)
        assert.equal("ok", module.groups["chat.frames"].status)
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0, env.ChatFrame1.alpha)
        assert.is_true(R.Registry:Disable(MODULE))

        local env2, R2, module2 = base({ loaded = { ElvUI = true } })
        immersion(R2)
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
        immersion(R, { ["hud.minimap"] = "alone" })
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
        immersion(R)
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("ok", module.groups["hud.buffs"].status)
        assert.equal(0, env.BuffFrame.alpha)
        assert.is_function(env.hooks[env.BuffFrame].UpdateSystemSettingOpacity)
        assert.is_nil(env.hooks.MissingGlobal)
        env.BuffFrame.UpdateSystemSettingOpacity(env.BuffFrame)
        env.hooks[env.BuffFrame].UpdateSystemSettingOpacity(env.BuffFrame)
        assert.equal(0, env.BuffFrame.alpha)
        assert.equal(0, R.Fade:Active())
        -- The player frame's Edit Mode opacity is a baseline: the behaviour becomes a share of it.
        env.PlayerFrame.UpdateSystemSettingOpacity(env.PlayerFrame)
        env.hooks[env.PlayerFrame].UpdateSystemSettingOpacity(env.PlayerFrame)
        assert.equal(0, env.PlayerFrame.alpha)
        assert.equal(0.5, module.captured[env.PlayerFrame])
        R.Visibility:Assign({ "unit.player" }, "world", nil)
        step(R, 5)
        assert.equal(0.5, env.PlayerFrame.alpha)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.BuffFrame.alpha)
        assert.equal(0.5, env.PlayerFrame.alpha)
        table.remove(R.Visibility.groups)
    end)

    it("reveals every group a shared frame belongs to and resolves a child by its parent key", function()
        local env, R, module = base()
        immersion(R, { ["hud.minimap"] = "alone", ["hud.minimapButtons"] = "alone", ["hud.objectives"] = "alone" })
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("ok", module.groups["hud.minimapButtons"].status)
        assert.equal(0, env.MinimapCluster.alpha)
        assert.equal(0, env.GameTimeFrame.alpha)
        assert.equal(0, env.MinimapCluster.Tracking.alpha)
        assert.equal(0, env.Minimap.ZoomIn.alpha)
        -- Chat input art is textures: faded with no mouseover, no hover hooks asked of it.
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

    it("switches to the setup of the place the player is in, and back to World's", function()
        local env, R, module = base()
        local Rules = R.Visibility
        assert.is_true(Rules:Assign({ "bars.main", "bars.right" }, "world", "fadeAway"))
        assert.is_true(Rules:SetOwnSetup("city", true))
        assert.is_true(Rules:Assign({ "bars.main" }, "city", nil))
        assert.is_true(R.Registry:Enable(MODULE))
        assert.equal("world", module.place)
        assert.equal(0, env.MainActionBar.alpha)
        assert.equal(1, env.MultiBar5.alpha)
        -- A city with a setup of its own: the main bar is left as the game has it there.
        env.world.resting = true
        env:Fire("PLAYER_UPDATE_RESTING")
        step(R, 5)
        assert.equal("city", module.place)
        assert.is_true((env.companion.loads or 0) > 0)
        assert.equal(1, env.MainActionBar.alpha)
        assert.equal(0, env.MultiBarRight.alpha)
        env.world.resting = false
        env:Fire("PLAYER_UPDATE_RESTING")
        step(R, 5)
        assert.equal("world", module.place)
        assert.equal(0, env.MainActionBar.alpha)
        -- A raid with no setup of its own follows World's, until it gets one.
        env.world.instance = "raid"
        env:Fire("PLAYER_ENTERING_WORLD")
        step(R, 5)
        assert.equal("world", module.place)
        assert.equal(0, env.MainActionBar.alpha)
        assert.is_true(Rules:SetOwnSetup("raid", true))
        assert.equal("raid", module.place)
        assert.is_true(Rules:Assign({ "bars.main" }, "raid", "combatHud"))
        step(R, 5)
        assert.is_true(math.abs(env.MainActionBar.alpha - 0.2) < 1e-9)
        -- Raid to delve is one loading screen with an instance on both sides: still a change.
        env.world.instance = "scenario"
        env:Fire("PLAYER_ENTERING_WORLD")
        step(R, 5)
        assert.equal("world", module.place)
        assert.equal(0, env.MainActionBar.alpha)
        assert.is_true(R.Registry:Disable(MODULE))
        assert.equal(1, env.MainActionBar.alpha)
        assert.is_nil(module.place)
        assert.equal(0, #R.errors)
    end)
end)
