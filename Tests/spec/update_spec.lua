local Runtime = require("Tests.mock.runtime")

local PATH, ID = "Modules/Chat/UpdateNotice.lua", "social.updateNotice"

local function base(version)
    local env = Runtime.new()
    for _, path in ipairs({ "Locales/Commands.enUS.lua", "Locales/Features.enUS.lua" }) do
        env:Load(path)
    end
    env.R.Print = function(_, message) env.messages[#env.messages + 1] = message end
    env.sent, env.prefixes = {}, {}
    env.guild, env.home, env.raid, env.instance = false, false, false, false
    env.C_AddOns = { GetAddOnMetadata = function(name, field)
        assert.equal("Refactor", name)
        assert.equal("Version", field)
        return version
    end }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix)
            env.prefixes[#env.prefixes + 1] = prefix
            return 0
        end,
        SendAddonMessage = function(prefix, text, channel)
            env.sent[#env.sent + 1] = { prefix = prefix, text = text, channel = channel, at = env.now }
            return 0
        end,
    }
    env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE = 1, 2
    env.IsInGuild = function() return env.guild end
    env.IsInGroup = function(category)
        if category == 1 then return env.home end
        if category == 2 then return env.instance end
        return env.home or env.instance
    end
    env.IsInRaid = function(category)
        if category == 2 then return false end
        return env.raid
    end
    env:Load(PATH)
    return env
end

local function enable(env)
    local module = env.R.moduleByID[ID]
    assert.is_true(env.R.Registry:Enable(ID), ID .. " did not enable: " .. tostring(module.failure)
        .. " " .. table.concat(module.missing or {}, ","))
    return module
end

local function channels(env)
    local list = {}
    for _, message in ipairs(env.sent) do
        assert.equal("Refactor", message.prefix)
        list[#list + 1] = message.channel
    end
    return list
end

local function hear(env, text, channel, sender)
    env:Fire("CHAT_MSG_ADDON", "Refactor", text, channel or "GUILD", sender or "Bob-Realm")
end

describe("social.updateNotice", function()
    it("announces its version to the guild and the group ten seconds after enable", function()
        local env = base("0.1.0")
        env.guild, env.home = true, true
        enable(env)
        assert.same({ "Refactor" }, env.prefixes)
        env:Advance(9)
        assert.same({}, channels(env))
        env:Advance(1)
        assert.same({ "GUILD", "PARTY" }, channels(env))
        assert.equal("V0.1.0", env.sent[1].text)
        assert.equal(0, #env.messages)
    end)

    it("names the channel the client's chat box would use for each kind of group", function()
        local env = base("0.1.0")
        env.home, env.raid = true, true
        enable(env)
        env:Advance(10)
        assert.same({ "RAID" }, channels(env))
        env = base("0.1.0")
        env.home, env.instance = true, true
        enable(env)
        env:Advance(10)
        assert.same({ "INSTANCE_CHAT", "PARTY" }, channels(env))
        env = base("0.1.0")
        enable(env)
        env:Advance(10)
        assert.same({}, channels(env))
    end)

    it("reduces the TOC version to its three numbers before sending it", function()
        local env = base("v0.1.0-3-gabcdef")
        env.guild = true
        enable(env)
        env:Advance(10)
        assert.equal("V0.1.0", env.sent[1].text)
    end)

    it("speaks to a group once, on joining it, not on every roster change", function()
        local env = base("0.1.0")
        enable(env)
        env:Advance(10)
        assert.same({}, channels(env))
        env.home = true
        env:Fire("GROUP_ROSTER_UPDATE")
        assert.same({ "PARTY" }, channels(env))
        env:Fire("GROUP_ROSTER_UPDATE")
        env:Advance(6)
        assert.same({ "PARTY" }, channels(env))
        env.home = false
        env:Fire("GROUP_ROSTER_UPDATE")
        env:Advance(6)
        env.home = true
        env:Fire("GROUP_ROSTER_UPDATE")
        env:Advance(6)
        assert.same({ "PARTY", "PARTY" }, channels(env))
    end)

    it("says once when a newer version is heard, and again only for a newer one still", function()
        local env = base("0.1.0")
        enable(env)
        hear(env, "V0.2.0", "GUILD", "Bob-Realm")
        assert.equal(1, #env.messages)
        assert.truthy(env.messages[1]:find("0.2.0", 1, true))
        assert.truthy(env.messages[1]:find("Bob-Realm", 1, true))
        assert.truthy(env.messages[1]:find("0.1.0", 1, true))
        hear(env, "V0.2.0")
        hear(env, "V0.1.5")
        hear(env, "V0.1.0")
        hear(env, "V0.0.9")
        hear(env, "hello")
        hear(env, "V1.2")
        hear(env, "V99999.0.0")
        env:Fire("CHAT_MSG_ADDON", "DBMv4", "V9.9.9", "GUILD", "Eve-Realm")
        assert.equal(1, #env.messages)
        hear(env, "V0.3.0", "PARTY", "Cid-Realm")
        assert.equal(2, #env.messages)
        assert.truthy(env.messages[2]:find("0.3.0", 1, true))
    end)

    it("answers an older copy after a short wait, unless a copy at least as new spoke first", function()
        local env = base("0.1.0")
        enable(env)
        env:Advance(10)
        hear(env, "V0.0.9", "GUILD", "Old-Realm")
        assert.same({}, channels(env))
        env:Advance(4)
        assert.same({ "GUILD" }, channels(env))
        assert.is_true(env.sent[1].at > 10 and env.sent[1].at < 14)
        -- Two asks at once get one answer.
        env:Advance(10)
        hear(env, "V0.0.9")
        hear(env, "V0.0.9")
        env:Advance(4)
        assert.same({ "GUILD", "GUILD" }, channels(env))
        -- A copy on our own build answering first makes ours redundant.
        env:Advance(10)
        hear(env, "V0.0.9")
        hear(env, "V0.1.0", "GUILD", "Peer-Realm")
        env:Advance(4)
        assert.same({ "GUILD", "GUILD" }, channels(env))
        -- So does a newer one, which is also the notice.
        env:Advance(10)
        hear(env, "V0.0.9")
        hear(env, "V0.2.0")
        env:Advance(4)
        assert.same({ "GUILD", "GUILD" }, channels(env))
        assert.equal(1, #env.messages)
        -- A whisper is nobody's channel to answer on.
        env:Advance(10)
        hear(env, "V0.0.9", "WHISPER", "Old-Realm")
        env:Advance(4)
        assert.same({ "GUILD", "GUILD" }, channels(env))
        assert.equal(0, env:ActiveTimers())
    end)

    it("neither speaks nor compares when this copy has no version number", function()
        local env = base("@project-version@")
        env.guild = true
        enable(env)
        env:Advance(10)
        assert.same({}, env.prefixes)
        assert.same({}, channels(env))
        hear(env, "V9.0.0")
        assert.equal(0, #env.messages)
        env.R.Broker:Emit("REFACTOR_UPDATE_REPORT")
        assert.same({ env.R.L.CMD_UPDATE_NO_VERSION }, env.messages)
    end)

    it("reports and asks again from /refactor update", function()
        local env = base("0.1.0")
        env:Load("Core/Commands.lua")
        local L = env.R.L
        assert.same({ L.CMD_UPDATE_OFF }, env.R.Commands:Dispatch("update"))
        enable(env)
        env.guild = true
        env:Advance(10)
        hear(env, "V0.2.0", "GUILD", "Bob-Realm")
        assert.is_nil(env.R.Commands:Dispatch("update"))
        assert.same({
            string.format(L.SOCIAL_UPDATE_AVAILABLE, "0.2.0", "Bob-Realm", "0.1.0"),
            string.format(L.CMD_UPDATE_RUNNING, "0.1.0"),
            string.format(L.CMD_UPDATE_NEWEST, "0.2.0", "Bob-Realm"),
            L.CMD_UPDATE_ASKED,
        }, env.messages)
        -- The burst gap does not hold a deliberate ask back.
        assert.same({ "GUILD", "GUILD" }, channels(env))
        env.guild = false
        env.R.Commands:Dispatch("update")
        assert.equal(L.CMD_UPDATE_NOBODY, env.messages[#env.messages])
        assert.same({ "GUILD", "GUILD" }, channels(env))
    end)

    it("leaves nothing behind on disable, mid-wait or not", function()
        local env = base("0.1.0")
        local module = enable(env)
        env.R.Registry:Disable(module)
        assert.equal(0, env:ActiveTimers())
        assert.is_true(env.R.Registry:Enable(module))
        env:Advance(10)
        hear(env, "V0.0.9")
        assert.equal(1, env:ActiveTimers())
        env.R.Registry:Disable(module)
        assert.equal(0, env:ActiveTimers())
        for _, entries in pairs(env.R.Broker.events) do
            for _, entry in ipairs(entries) do
                assert.is_not.equal(module, entry.owner)
            end
        end
        assert.is_nil(env.R.Broker.events.CHAT_MSG_ADDON)
        assert.is_nil(env.R.Broker.events.GROUP_ROSTER_UPDATE)
        env:Advance(10)
        hear(env, "V0.2.0")
        assert.equal(0, #env.messages)
        assert.same({}, channels(env))
    end)
end)
