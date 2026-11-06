local Runtime = require("Tests.mock.runtime")

describe("camera profiles", function()
    local env, R, Profiles, Settings
    before_each(function()
        env = Runtime.new()
        R = env.R
        Profiles, Settings = R.CameraProfiles, R.Settings
    end)

    it("ships valid built-ins and refuses a record that is short, wide, or off its range", function()
        local ids = {}
        for _, profile in ipairs(Profiles.builtIn) do
            assert.is_true(Profiles:Valid(profile.values), profile.id)
            ids[#ids + 1] = profile.id
        end
        assert.same({ "immersive", "melee", "ranged", "cinematic", "raider", "comfort", "controllerMelee",
            "controllerRanged", "blizzardBasic", "blizzardOn", "blizzardFull" }, ids)
        -- Every situation says which way it may move the camera, and only the two that exist to
        -- bring it closer bring it closer.
        for _, situation in ipairs(Profiles.situations) do
            local direction = Profiles.directions[situation]
            assert.is_true(direction == "in" or direction == "out", situation)
            assert.equal(situation == "indoors" or situation == "npc", direction == "in", situation)
        end
        -- A mouse never fights a camera turning on its own: only the controller profiles and
        -- Blizzard's own Full pull toward the target.
        for _, profile in ipairs(Profiles.builtIn) do
            local pulls = profile.values.targetPull > 0
            assert.equal(profile.id == "controllerMelee" or profile.id == "controllerRanged"
                or profile.id == "blizzardFull", pulls, profile.id)
        end
        local values = Profiles:Resolve("immersive").values
        values.distance = nil
        assert.is_false(Profiles:Valid(values))
        values = Profiles:Resolve("immersive").values
        values.extra = 1
        assert.is_false(Profiles:Valid(values))
        values = Profiles:Resolve("immersive").values
        values.shoulder = 2.5
        assert.is_false(Profiles:Valid(values))
        values.shoulder = 0 / 0
        assert.is_false(Profiles:Valid(values))
        values.shoulder = "0.5"
        assert.is_false(Profiles:Valid(values))
        values = Profiles:Resolve("immersive").values
        values.swayWhileMoving = 1
        assert.is_false(Profiles:Valid(values))
        values = Profiles:Resolve("immersive").values
        values.tilt = 0.9
        assert.is_false(Profiles:Valid(values))
        -- The old shape is not a profile until it is upgraded.
        values = Profiles:Resolve("immersive").values
        values.tilt, values.swayWhileMoving, values.pitch = nil, nil, true
        assert.is_false(Profiles:Valid(values))
        -- LEAVE is a distance; nothing between it and the floor is, and a shoulder cannot use it.
        values = Profiles:Resolve("immersive").values
        values.indoorsDistance = Profiles.LEAVE
        assert.is_true(Profiles:Valid(values))
        values.indoorsDistance = 2
        assert.is_false(Profiles:Valid(values))
        values.indoorsDistance = 4
        values.indoorsShoulder = 3
        assert.is_false(Profiles:Valid(values))
        assert.is_false(Profiles:Valid("immersive"))
    end)

    it("names a profile by a built-in id or a custom name behind the prefix", function()
        assert.is_true(Profiles:ValidReference("immersive"))
        assert.is_true(Profiles:ValidReference("blizzardFull"))
        assert.is_true(Profiles:ValidReference("custom:Mine"))
        assert.is_false(Profiles:ValidReference("custom:"))
        assert.is_false(Profiles:ValidReference("nope"))
        assert.is_false(Profiles:ValidReference(1))
        assert.equal("Mine", Profiles:CustomName("custom:Mine"))
        assert.is_nil(Profiles:CustomName("immersive"))
        -- Resolving hands out a copy: editing it changes no built-in.
        local resolved = Profiles:Resolve("immersive")
        resolved.values.distance = 30
        assert.equal(9, Profiles:Resolve("immersive").values.distance)
        assert.is_nil(Profiles:Resolve("custom:Mine", {}))
        assert.equal("Mine", Profiles:Resolve("custom:Mine", { Mine = resolved.values }).name)
    end)

    it("round trips a profile through its share string and refuses a tampered one", function()
        -- Melee carries LEAVE in several fields, so the round trip covers it.
        local values = Profiles:Resolve("melee").values
        local encoded = Profiles:Encode("Pad", values)
        assert.is_string(encoded)
        assert.is_nil(encoded:find("[^%w+/=]"))
        local decoded = Profiles:Decode(encoded)
        assert.equal("Pad", decoded.name)
        assert.same(values, decoded.values)
        assert.same({ nil, "invalid_encoding" }, { Profiles:Decode("not base64!") })
        assert.same({ nil, "invalid_encoding" }, { Profiles:Decode(R.Codec:EncodeText("RC1\nPad")) })
        -- The right shape with one number outside its range, one key twice, and one unknown.
        local lines = { "RC4", "Pad" }
        for _, field in ipairs(Profiles.fields) do
            local value = values[field.key]
            local text = field.kind == "boolean" and (value and "1" or "0") or tostring(value)
            lines[#lines + 1] = field.key .. "=" .. text
        end
        local function withLine(replacement, index)
            local copy = {}
            for i, line in ipairs(lines) do copy[i] = line end
            copy[index or #copy + 1] = replacement
            return R.Codec:EncodeText(table.concat(copy, "\n") .. "\n")
        end
        assert.same({ nil, "invalid_profile" }, { Profiles:Decode(withLine("distance=99", 3)) })
        assert.same({ nil, "invalid_profile" }, { Profiles:Decode(withLine("distance=2", 3)) })
        assert.equal(0, Profiles:Decode(withLine("distance=0", 3)).values.distance)
        assert.same({ nil, "invalid_profile" }, { Profiles:Decode(withLine("distance=1")) })
        assert.same({ nil, "invalid_profile" }, { Profiles:Decode(withLine("mystery=1")) })
        assert.same({ nil, "invalid_profile" }, { Profiles:Decode(withLine("swayWhileMoving=yes", 6)) })
        -- pitch is only an RC3 field.
        assert.same({ nil, "invalid_profile" }, { Profiles:Decode(withLine("pitch=1")) })
        assert.same({ nil, "invalid_profile" }, { Profiles:Decode(withLine("RC2", 1)) })
        assert.same({ nil, "invalid_profile" }, { Profiles:Encode("", values) })
    end)

    it("saves, edits, exports, imports and deletes custom profiles through Settings", function()
        assert.equal("immersive", Settings:GetOption("cameraProfile"))
        assert.same({ false, "invalid_profile" }, { Profiles:SaveCopy("", Profiles:Active().values) })
        assert.same({ true, "Mine" }, { Profiles:SaveCopy("Mine", Profiles:Active().values) })
        assert.equal("custom:Mine", Settings:GetOption("cameraProfile"))
        assert.same({ false, "profile_exists" }, { Profiles:SaveCopy("Mine", Profiles:Active().values) })
        assert.is_true(Profiles:SetField("shoulder", 1.5))
        assert.equal(1.5, Settings:GetOption("cameraProfiles").Mine.shoulder)
        assert.is_false(Profiles:SetField("shoulder", 3))
        assert.is_false(Profiles:SetField("mystery", 1))
        -- The stored table is not the caller's: a later change to Active's copy is lost.
        Profiles:Active().values.shoulder = 0
        assert.equal(1.5, Settings:GetOption("cameraProfiles").Mine.shoulder)
        -- A built-in refuses an edit rather than being copied behind the player's back.
        assert.is_true(Profiles:Select("blizzardBasic"))
        assert.is_false(Profiles:SetField("shoulder", 1))
        assert.same({ false, "missing_profile" }, { Profiles:Select("custom:Nope") })
        local encoded = Profiles:Export("custom:Mine")
        assert.is_string(encoded)
        assert.same({ false, "profile_exists" }, { Profiles:Import(encoded) })
        assert.is_true(Profiles:Delete("Mine"))
        assert.same({ true, "Mine" }, { Profiles:Import(encoded) })
        assert.equal(1.5, Settings:GetOption("cameraProfiles").Mine.shoulder)
        assert.equal("custom:Mine", Settings:GetOption("cameraProfile"))
        -- Deleting the active profile lands on the shipped default before it is gone.
        local seen = {}
        R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", function(_, _, key)
            seen[#seen + 1] = key .. "=" .. tostring(Settings:GetOption("cameraProfile"))
        end, seen)
        assert.is_true(Profiles:Delete("Mine"))
        assert.same({ "cameraProfile=immersive", "cameraProfiles=immersive" }, seen)
        assert.is_false(Profiles:Delete("Mine"))
        -- Exporting a built-in names it as the player sees it.
        R.L = { CAMERA_PROFILE_IMMERSIVE = "Immersive" }
        assert.equal("Immersive", Profiles:Decode(Profiles:Export("immersive")).name)
        assert.same({ nil, "missing_profile" }, { Profiles:Export("custom:Gone") })
    end)

    it("caps custom profiles and drops what a saved table cannot hold", function()
        local values = Profiles:Active().values
        for index = 1, 20 do
            assert.is_true(Profiles:SaveCopy("P" .. index, values))
        end
        assert.same({ false, "profile_limit" }, { Profiles:SaveCopy("P21", values) })
        -- A saved table with a bad entry is refused whole, the way every option is.
        assert.is_false(Settings:SetOption("cameraProfiles", { Bad = { distance = 1 } }))
        assert.is_false(Settings:SetOption("cameraProfiles", { [""] = values }))
        assert.is_false(Settings:SetOption("cameraProfile", "custom:"))
        -- Init keeps a good table and resets a selection whose profile is gone.
        local account = { options = { cameraProfile = "custom:Gone", cameraProfiles = { Kept = values } } }
        Settings:Init(account, {}, "Player-test")
        assert.equal("immersive", account.options.cameraProfile)
        assert.same(values, account.options.cameraProfiles.Kept)
        -- A bad record is dropped on its own; the good one and the selection of it stay.
        account = { options = { cameraProfile = "custom:Kept", cameraProfiles = { Kept = values, Bad = {} } } }
        Settings:Init(account, {}, "Player-test")
        assert.same({ Kept = values }, account.options.cameraProfiles)
        assert.equal("custom:Kept", account.options.cameraProfile)
        account = { options = { cameraProfiles = "not a table" } }
        Settings:Init(account, {}, "Player-test")
        assert.same({}, account.options.cameraProfiles)
    end)

    -- The owner's own copy of Melee, exactly as Forever saved it before tilt and sway while
    -- moving existed. It has to come through an upgrade with every number it had.
    local MY_MELEE = {
        pitch = true, indoorsDistance = 0, mountedShoulder = 0, dungeonDistance = 0, mountedDistance = 16,
        combatShoulder = 1, battlegroundDistance = 0, headBob = 0.2, raidDistance = 12, npcDistance = 0,
        indoorsShoulder = 0.6, restingDistance = 0, targetPull = 0, distance = 0, arenaShoulder = 0.9,
        restingShoulder = 0.5, dungeonShoulder = 0.8, raidShoulder = 0.6, npcShoulder = 0.8,
        battlegroundShoulder = 0.8, focusInteract = true, arenaDistance = 0, shoulder = 1, combatDistance = 0,
    }

    it("upgrades a saved profile from before tilt and keeps every value it had", function()
        local account = { options = { cameraProfile = "custom:My Melee",
            cameraProfiles = { ["My Melee"] = MY_MELEE } } }
        Settings:Init(account, {}, "Player-test")
        assert.equal("custom:My Melee", account.options.cameraProfile)
        local upgraded = account.options.cameraProfiles["My Melee"]
        assert.is_true(Profiles:Valid(upgraded))
        assert.is_nil(upgraded.pitch)
        assert.equal(Profiles.tiltDefault, upgraded.tilt)
        assert.is_true(upgraded.swayWhileMoving)
        -- Combat is no longer a situation, so its two fields go; everything else stays.
        assert.is_nil(upgraded.combatDistance)
        assert.is_nil(upgraded.combatShoulder)
        for key, value in pairs(MY_MELEE) do
            if key ~= "pitch" and key ~= "combatDistance" and key ~= "combatShoulder" then
                assert.equal(value, upgraded[key], key)
            end
        end
        -- Once more changes nothing, and no tilt becomes zero tilt.
        Settings:Init(account, {}, "Player-test")
        assert.same(upgraded, account.options.cameraProfiles["My Melee"])
        local flat = {}
        for key, value in pairs(MY_MELEE) do flat[key] = value end
        flat.pitch = false
        assert.equal(0, Profiles:Upgrade(flat).tilt)
        assert.equal("text", Profiles:Upgrade("text"))
    end)

    it("imports a share string from before tilt", function()
        local lines = { "RC3", "Old" }
        for key, value in pairs(MY_MELEE) do
            lines[#lines + 1] = key .. "=" .. (type(value) == "boolean" and (value and "1" or "0") or tostring(value))
        end
        local decoded = Profiles:Decode(R.Codec:EncodeText(table.concat(lines, "\n") .. "\n"))
        assert.equal("Old", decoded.name)
        assert.is_true(Profiles:Valid(decoded.values))
        assert.equal(Profiles.tiltDefault, decoded.values.tilt)
        assert.equal(16, decoded.values.mountedDistance)
        -- An RC3 string never carried the new fields.
        lines[#lines + 1] = "tilt=0.4"
        assert.same({ nil, "invalid_profile" },
            { Profiles:Decode(R.Codec:EncodeText(table.concat(lines, "\n") .. "\n")) })
        -- Exports are RC4 from now on.
        assert.equal("RC4", R.Codec:DecodeText(Profiles:Encode("New", decoded.values)):match("^([^\n]*)"))
    end)
end)
