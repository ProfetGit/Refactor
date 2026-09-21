local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")
local Changelog = require("Tools.changelog")

local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function tocFiles()
    local files = {}
    for line in assert(io.open("Refactor.toc", "r")):lines() do
        local entry = line:gsub("\\", "/"):gsub("%s+$", "")
        if entry:match("%.lua$") and entry:sub(1, 1) ~= "#" and entry ~= "Restore.lua" then
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

describe("changelog generator", function()
    it("keeps the shipped locale file in step with CHANGELOG.md", function()
        -- Compared as a boolean so a stale file fails with one line, not two dumps of it.
        local current = Changelog.generate(read("CHANGELOG.md")) == read("Locales/Changelog.enUS.lua")
        assert.is_true(current, "Locales/Changelog.enUS.lua is behind CHANGELOG.md: run make changelog")
    end)

    it("reads headings, bullets with continuation lines, paragraphs and group breaks", function()
        local versions = Changelog.parse(table.concat({
            "# Changelog", "", "## 0.2.0 (2026-10-01)", "", "Built against `Retail` 12.1.0:", "",
            "- First entry wraps", "  onto a second line.", '- Second entry, with "quotes" and a | pipe.', "",
            "- After a blank line.", "", "## 0.1.0", "- Older.",
        }, "\n"))
        assert.equal(2, #versions)
        assert.equal("0.2.0 (2026-10-01)", versions[1].title)
        local entries = versions[1].entries
        assert.equal(4, #entries)
        assert.same({ text = "Built against Retail 12.1.0:" }, entries[1])
        assert.same({ text = "First entry wraps onto a second line.", bullet = true, gap = true }, entries[2])
        assert.same({ text = 'Second entry, with "quotes" and a | pipe.', bullet = true }, entries[3])
        assert.same({ text = "After a blank line.", bullet = true, gap = true }, entries[4])
        assert.same({ { text = "Older.", bullet = true } }, versions[2].entries)
    end)

    it("refuses text that belongs to no version", function()
        assert.has_error(function() Changelog.parse("# Changelog\n\nLoose line\n") end)
        assert.has_error(function() Changelog.parse("# Changelog\n") end)
    end)

    it("emits Lua the client reads back as written, escaped, and inside the line limit", function()
        local long = string.rep("word ", 60) .. "end."
        local source = Changelog.generate('## v\n- Say "hi" to C:\\path and a | pipe, ' .. long .. "\n"
            .. "- " .. string.rep("x", 200) .. "\n")
        for line in source:gmatch("[^\n]+") do
            assert.is_true(#line <= 120, line)
        end
        local env = Runtime.new()
        local chunk = assert(loadstring(source))
        setfenv(chunk, env)
        chunk("Refactor", env.R)
        local entries = env.R.L.CHANGELOG[1].entries
        assert.equal('Say "hi" to C:\\path and a || pipe, ' .. long, entries[1][1])
        assert.is_true(entries[1].bullet)
        assert.equal(string.rep("x", 200), entries[2][1])
    end)
end)

describe("what's new page", function()
    it("lists every version and entry of the generated changelog, and opens from the slash command", function()
        local env, R = loaded()
        local UI = R.UI
        env.SlashCmdList.REFACTOR("changelog")
        assert.is_true(UI.frame:IsShown())
        assert.is_true(UI.panels.Changelog:IsShown())
        assert.equal("Changelog", UI.category)
        local versions = R.L.CHANGELOG
        assert.is_true(#versions > 0)
        assert.equal(#versions, #UI.changelogVersions)
        local entries = 0
        for index, version in ipairs(versions) do
            local block = UI.changelogVersions[index]
            assert.equal(version.title, block.header.title:GetText())
            assert.equal(#version.entries, #block.lines)
            for entryIndex, entry in ipairs(version.entries) do
                local line = block.lines[entryIndex]
                assert.equal(entry[1], line.text:GetText())
                assert.equal(entry.bullet == true, line.mark ~= nil)
                -- No markdown survives into the page.
                assert.is_nil(entry[1]:find("`", 1, true))
                assert.is_nil(entry[1]:match("^%- "))
                entries = entries + 1
            end
        end
        assert.is_true(entries > 0)
        -- The scroll extent is the laid-out height, so the page can be scrolled to its end.
        local _, maximum = UI.changelogList.slider:GetMinMaxValues()
        assert.is_true(maximum > 0)
        assert.equal(0, #R.errors)
    end)
end)
