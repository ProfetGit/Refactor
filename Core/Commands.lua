--- @core commands
--- Purpose: turn slash input into printable lines, so the dispatch itself stays testable.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Commands = {}
R.Commands = Commands

local MAX_REPORTED, MAX_TRACE_LINES = 5, 8

function Commands:ErrorLines()
    local errors, lines = R.errors, {}
    if #errors == 0 then
        return { R.L.CMD_NO_ERRORS }
    end
    lines[1] = string.format(R.L.CMD_ERRORS_HEADER, #errors)
    local first = math.max(1, #errors - MAX_REPORTED + 1)
    for index = first, #errors do
        local record = errors[index]
        lines[#lines + 1] = string.format(R.L.CMD_ERROR_ENTRY, index, record.module,
            record.context or R.L.CMD_ERROR_NO_CONTEXT)
        local traceLines = 0
        for line in tostring(record.message):gmatch("[^\n]+") do
            traceLines = traceLines + 1
            if traceLines > MAX_TRACE_LINES then
                break
            end
            lines[#lines + 1] = "    " .. line
        end
    end
    lines[#lines + 1] = R.L.CMD_ERRORS_FOOTER
    return lines
end

-- Whether the client handed the saved variables back at all. Only interesting while
-- Forever loses them; the numbers are counts of top level keys, so "table:0" is a DB the
-- client created empty rather than one it restored.
function Commands:SavedLines()
    local probe = R.loadProbe or {}
    local restored = probe.clientGave == true
    return {
        string.format(R.L.CMD_SAVED_ACCOUNT, tostring(probe.atFile), tostring(probe.atLogin),
            tostring(probe.firstRun)),
        string.format(R.L.CMD_SAVED_CHARACTER, tostring(probe.atFileChar), tostring(probe.atLoginChar)),
        restored and R.L.CMD_SAVED_VERDICT_OK
            or probe.restored and R.L.CMD_SAVED_VERDICT_RESTORE_FILE
            or R.L.CMD_SAVED_VERDICT_LOST,
    }
end

function Commands:Clear()
    local errors = R.errors
    for index = #errors, 1, -1 do
        errors[index] = nil
    end
    return { R.L.CMD_ERRORS_CLEARED }
end

function Commands:Dispatch(input)
    local text = tostring(input or ""):lower():match("^%s*(.-)%s*$")
    if text == "" then
        if R.UI and R.UI.Toggle then
            R.UI:Toggle()
        end
        return nil
    end
    local command, argument = text:match("^(%S+)%s*(.-)$")
    if command == "errors" then
        if argument == "clear" then
            return self:Clear()
        end
        return self:ErrorLines()
    end
    if command == "saved" then
        return self:SavedLines()
    end
    -- The feed belongs to a module, so the command asks the broker rather than reaching
    -- into the module itself. No subscriber means the module is off.
    if command == "loottest" then
        if not R.Broker.events.REFACTOR_LOOT_TEST then
            return { R.L.CMD_LOOT_TEST_OFF }
        end
        R.Broker:Emit("REFACTOR_LOOT_TEST")
        return nil
    end
    if command == "farmtest" then
        if not R.Broker.events.REFACTOR_FARM_TEST then
            return { R.L.CMD_FARM_TEST_OFF }
        end
        R.Broker:Emit("REFACTOR_FARM_TEST")
        return nil
    end
    if command == "invitetest" then
        if not R.Broker.events.REFACTOR_INVITE_TEST then
            return { R.L.CMD_INVITE_TEST_OFF }
        end
        R.Broker:Emit("REFACTOR_INVITE_TEST")
        return nil
    end
    if command == "spelltest" then
        if not R.Broker.events.REFACTOR_SPELL_TEST then
            return { R.L.CMD_SPELL_TEST_OFF }
        end
        R.Broker:Emit("REFACTOR_SPELL_TEST")
        return nil
    end
    if command == "changelog" then
        if R.UI and R.UI.OpenPanel then
            R.UI:OpenPanel("Changelog")
        end
        return nil
    end
    if command == "update" then
        if not R.Broker.events.REFACTOR_UPDATE_REPORT then
            return { R.L.CMD_UPDATE_OFF }
        end
        R.Broker:Emit("REFACTOR_UPDATE_REPORT")
        return nil
    end
    if command == "bench" and R.Bench then
        R.Bench:Start(function(line) R:Print(line) end)
        return nil
    end
    return { R.L.CMD_HELP_HEADER, R.L.CMD_HELP_OPEN, R.L.CMD_HELP_CHANGELOG, R.L.CMD_HELP_ERRORS,
        R.L.CMD_HELP_ERRORS_CLEAR, R.L.CMD_HELP_SAVED, R.L.CMD_HELP_BENCH, R.L.CMD_HELP_LOOT_TEST,
        R.L.CMD_HELP_FARM_TEST, R.L.CMD_HELP_INVITE_TEST, R.L.CMD_HELP_SPELL_TEST, R.L.CMD_HELP_UPDATE }
end
