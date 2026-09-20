local Runtime = require("Tests.mock.runtime")

local READERS = {
    IsMounted = "mounted", UnitOnTaxi = "taxi", IsResting = "resting", UnitExists = "target",
    IsInGroup = "group", IsStealthed = "stealth", UnitIsDeadOrGhost = "dead",
}

local function base()
    local env = Runtime.new()
    env.world = { combat = false, mounted = false, taxi = false, resting = false, target = false, group = false,
        instance = false, stealth = false, dead = false }
    env.InCombatLockdown = function() return env.world.combat end
    for name, key in pairs(READERS) do
        env[name] = function() return env.world[key] end
    end
    env.IsInInstance = function() return env.world.instance, env.world.instance and "party" or "none" end
    env.seen = {}
    local owner = {}
    env.R.Broker:Subscribe("REFACTOR_CONDITIONS_CHANGED", function(_, _, flags)
        local snapshot = {}
        for key, value in pairs(flags) do snapshot[key] = value end
        env.seen[#env.seen + 1] = snapshot
    end, owner)
    return env, env.R.Conditions
end

describe("conditions", function()
    it("reads every flag silently on the first start and holds the events only while started", function()
        local env, Conditions = base()
        env.world.resting, env.world.group = true, true
        local consumer = {}
        assert.is_nil(env.R.Broker.events.PLAYER_REGEN_DISABLED)
        local flags = Conditions:Start(consumer)
        assert.is_true(flags.resting)
        assert.is_true(flags.inGroup)
        assert.is_false(flags.combat)
        assert.equal(0, #env.seen)
        assert.is_table(env.R.Broker.events.PLAYER_REGEN_DISABLED)
        assert.is_true(env.R.Broker.frame:IsEventRegistered("PLAYER_ENTERING_WORLD"))
        for _, name in ipairs(Conditions.names) do
            assert.is_true(Conditions:Supported(name), name)
        end
        -- A second consumer shares the subscription; the last one out drops it.
        local other = {}
        Conditions:Start(other)
        Conditions:Stop(consumer)
        assert.is_table(env.R.Broker.events.PLAYER_REGEN_DISABLED)
        Conditions:Stop(other)
        assert.is_nil(env.R.Broker.events.PLAYER_REGEN_DISABLED)
        assert.is_false(env.R.Broker.frame:IsEventRegistered("PLAYER_ENTERING_WORLD"))
        assert.is_false(Conditions:State().resting)
        Conditions:Stop(other)
        assert.equal(0, Conditions.count)
    end)

    it("announces exactly one change per event that moved a flag", function()
        local env, Conditions = base()
        Conditions:Start({})
        env.world.combat = true
        env:Fire("PLAYER_REGEN_DISABLED")
        assert.equal(1, #env.seen)
        assert.is_true(env.seen[1].combat)
        -- The same event again with nothing changed says nothing.
        env:Fire("PLAYER_REGEN_DISABLED")
        assert.equal(1, #env.seen)
        env.world.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        assert.equal(2, #env.seen)
        assert.is_false(env.seen[2].combat)
        -- An event for one flag never reads another: the target changed but only resting's event fired.
        env.world.target = true
        env:Fire("PLAYER_UPDATE_RESTING")
        assert.equal(2, #env.seen)
        env:Fire("PLAYER_TARGET_CHANGED")
        assert.equal(3, #env.seen)
        assert.is_true(env.seen[3].hasTarget)
        -- A taxi reads as mounted, through the control events a flight raises.
        env.world.taxi = true
        env:Fire("PLAYER_CONTROL_LOST")
        assert.equal(4, #env.seen)
        assert.is_true(env.seen[4].mounted)
        env.world.taxi = false
        env:Fire("PLAYER_CONTROL_GAINED")
        assert.is_false(env.seen[5].mounted)
        env.world.dead = true
        env:Fire("PLAYER_DEAD")
        assert.is_true(env.seen[6].dead)
        env.world.dead = false
        env:Fire("PLAYER_UNGHOST")
        assert.is_false(env.seen[7].dead)
        env.world.stealth = true
        env:Fire("UPDATE_STEALTH")
        assert.is_true(env.seen[8].stealthed)
        env.world.group = true
        env:Fire("GROUP_ROSTER_UPDATE")
        assert.is_true(env.seen[9].inGroup)
        assert.equal(9, #env.seen)
    end)

    it("folds a world change that moves several flags into one announcement", function()
        local env, Conditions = base()
        Conditions:Start({})
        env.world.instance, env.world.mounted, env.world.resting = true, true, true
        env:Fire("PLAYER_ENTERING_WORLD")
        assert.equal(1, #env.seen)
        assert.is_true(env.seen[1].inInstance)
        assert.is_true(env.seen[1].mounted)
        assert.is_true(env.seen[1].resting)
        env:Fire("PLAYER_ENTERING_WORLD")
        assert.equal(1, #env.seen)
    end)

    it("treats a reader this client lacks as unsupported and false, and keeps the rest", function()
        local env, Conditions = base()
        env.IsStealthed = nil
        env.world.stealth, env.world.resting = true, true
        local flags = Conditions:Start({})
        assert.is_false(Conditions:Supported("stealthed"))
        assert.is_true(Conditions:Supported("resting"))
        assert.is_false(flags.stealthed)
        assert.is_true(flags.resting)
        env:Fire("UPDATE_STEALTH")
        assert.equal(0, #env.seen)
    end)
end)
