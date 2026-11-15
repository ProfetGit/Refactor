local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

-- env.people plays who each plate unit is: { player, party, raid, friend, bnet, guid }.
local function base()
    local env = Runtime.new()
    Widgets.install(env)
    env:Load("Locales/Nameplates.enUS.lua")
    env.plates, env.people, env.secrets, env.raid = {}, {}, {}, false
    env.C_NamePlate = { GetNamePlateForUnit = function(unit) return env.plates[unit] end }
    local function person(unit) return env.people[unit] or {} end
    env.UnitIsPlayer = function(unit) return person(unit).player == true end
    env.UnitIsUnit = function(a, b) return a == b end
    env.UnitInParty = function(unit) return person(unit).party == true end
    env.UnitInRaid = function(unit) if person(unit).raid then return 3 end return nil end
    env.IsInRaid = function() return env.raid end
    env.UnitGUID = function(unit) return person(unit).guid end
    env.issecretvalue = function(value) return env.secrets[value] == true end
    local function byGUID(guid, field)
        for _, entry in pairs(env.people) do
            if entry.guid == guid then return entry[field] == true end
        end
        return false
    end
    env.C_FriendList = { IsFriend = function(guid) return byGUID(guid, "friend") end }
    env.C_BattleNet = { GetAccountInfoByGUID = function(guid)
        if byGUID(guid, "bnet") then return { isFriend = true } end
        return nil
    end }
    return env
end

local function addPlate(env, unit, who, healthBar)
    local plate = env.CreateFrame("Frame")
    plate.UnitFrame = env.CreateFrame("Frame")
    plate.UnitFrame:Show()
    plate.UnitFrame.name = plate.UnitFrame:CreateFontString()
    plate.UnitFrame.name:Show()
    local container = env.CreateFrame("Frame")
    container:Show()
    container.healthBar = env.CreateFrame("Frame")
    container.healthBar:SetShown(healthBar == true)
    plate.UnitFrame.HealthBarsContainer = container
    env.plates[unit] = plate
    env.people[unit] = who
    return plate
end

local function withModule(env)
    env:Load("Modules_LoD/Nameplates/FriendTags.lua")
    local module = env.R.moduleByID["nameplates.friendTags"]
    assert.is_true(env.R.Registry:Enable(module), tostring(module.failure))
    return module
end

local function show(env, unit)
    env:Fire("NAME_PLATE_UNIT_ADDED", unit)
    env:Advance(0.1)
end

local function tagText(module, unit)
    local tag = module.tags[unit]
    return tag and tag:IsShown() and tag.label:GetText() or nil
end

describe("friend and group tags on nameplates", function()
    it("tags party, raid and friends, and leaves strangers and NPCs alone", function()
        local env = base()
        local module = withModule(env)
        addPlate(env, "nameplate1", { player = true, party = true, guid = "Player-1" })
        addPlate(env, "nameplate2", { player = true, friend = true, guid = "Player-2" })
        addPlate(env, "nameplate3", { player = true, bnet = true, guid = "Player-3" })
        addPlate(env, "nameplate4", { player = true, guid = "Player-4" })
        addPlate(env, "nameplate5", { player = false, guid = "Creature-0-1-1-1-1-1" })
        for index = 1, 5 do
            env:Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. index)
        end
        -- Nothing before the next frame: Blizzard's own handler decides name-only mode first.
        assert.is_nil(tagText(module, "nameplate1"))
        env:Advance(0.1)
        assert.equal("Party", tagText(module, "nameplate1"))
        assert.equal("Friend", tagText(module, "nameplate2"))
        assert.equal("Friend", tagText(module, "nameplate3"))
        assert.is_nil(tagText(module, "nameplate4"))
        assert.is_nil(tagText(module, "nameplate5"))
    end)

    it("calls a raid a raid only while the player is in one", function()
        local env = base()
        local module = withModule(env)
        addPlate(env, "nameplate1", { player = true, raid = true, party = true, guid = "Player-1" })
        show(env, "nameplate1")
        assert.equal("Party", tagText(module, "nameplate1"))
        env.raid = true
        env:Fire("GROUP_ROSTER_UPDATE")
        env:Advance(0.5)
        assert.equal("Raid", tagText(module, "nameplate1"))
    end)

    it("puts the tag under the name when the health bar is hidden and above it when shown", function()
        local env = base()
        local module = withModule(env)
        local points = {}
        addPlate(env, "nameplate1", { player = true, party = true, guid = "Player-1" })
        addPlate(env, "nameplate2", { player = true, party = true, guid = "Player-2" }, true)
        local function record(unit)
            local tag = module.pool.free[#module.pool.free]
            tag.SetPoint = function(_, point) points[unit] = point end
        end
        record("nameplate1")
        show(env, "nameplate1")
        record("nameplate2")
        show(env, "nameplate2")
        assert.equal("TOP", points.nameplate1)
        assert.equal("BOTTOM", points.nameplate2)
    end)

    it("follows the group and friends list, and lets go of a removed plate", function()
        local env = base()
        local module = withModule(env)
        local who = { player = true, guid = "Player-1" }
        addPlate(env, "nameplate1", who)
        show(env, "nameplate1")
        assert.is_nil(tagText(module, "nameplate1"))
        who.friend = true
        env:Fire("FRIENDLIST_UPDATE")
        env:Advance(0.5)
        assert.equal("Friend", tagText(module, "nameplate1"))
        who.party = true
        env:Fire("GROUP_ROSTER_UPDATE")
        env:Advance(0.5)
        assert.equal("Party", tagText(module, "nameplate1"))
        local free = #module.pool.free
        env:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        assert.is_nil(module.tags.nameplate1)
        assert.equal(free + 1, #module.pool.free)
    end)

    it("skips a secret GUID or answer, and a plate whose Blizzard frame is hidden", function()
        local env = base()
        local module = withModule(env)
        addPlate(env, "nameplate1", { player = true, friend = true, guid = "secret-guid" })
        env.secrets["secret-guid"] = true
        local hidden = addPlate(env, "nameplate2", { player = true, party = true, guid = "Player-2" })
        hidden.UnitFrame:Hide()
        show(env, "nameplate1")
        show(env, "nameplate2")
        assert.is_nil(tagText(module, "nameplate1"))
        assert.is_nil(tagText(module, "nameplate2"))
        assert.equal(0, #env.R.errors)
    end)

    it("tags plates already up when turned on, and leaves nothing behind when off", function()
        local env = base()
        addPlate(env, "nameplate1", { player = true, party = true, guid = "Player-1" })
        local module = withModule(env)
        env:Advance(0.1)
        local tag = module.tags.nameplate1
        assert.equal("Party", tagText(module, "nameplate1"))
        local pool = module.pool
        env.R.Registry:Disable(module)
        assert.is_false(tag:IsShown())
        assert.is_nil(module.tags)
        assert.equals(0, env:ActiveTimers())
        for _, entries in pairs(env.R.Broker.events) do
            for _, entry in ipairs(entries) do
                assert.is_not.equal(module, entry.owner)
            end
        end
        assert.is_true(env.R.Registry:Enable(module))
        env:Advance(0.1)
        assert.equal(pool, module.pool)
        assert.equal("Party", tagText(module, "nameplate1"))
        env.R.Registry:Disable(module)
    end)
end)

describe("class coloured names on nameplates", function()
    it("turns Blizzard's class colour name setting on, and back to its default when off", function()
        local env = base()
        env.cvars = {}
        env.C_CVar = {
            SetCVar = function(name, value) env.cvars[name] = value end,
            GetCVarDefault = function() return "0" end,
        }
        env:Load("Modules/Interface/NameplateClassNames.lua")
        local module = env.R.moduleByID["interface.nameplateClassNames"]
        assert.is_false(module.defaultEnabled)
        assert.is_true(env.R.Registry:Enable(module))
        assert.equal("1", env.cvars.nameplateUseClassColorForFriendlyPlayerUnitNames)
        env.R.Registry:Disable(module)
        assert.equal("0", env.cvars.nameplateUseClassColorForFriendlyPlayerUnitNames)
    end)
end)
