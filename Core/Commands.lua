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
    if command == "bench" and R.Bench then
        R.Bench:Start(function(line) R:Print(line) end)
        return nil
    end
    return { R.L.CMD_HELP_HEADER, R.L.CMD_HELP_OPEN, R.L.CMD_HELP_ERRORS, R.L.CMD_HELP_ERRORS_CLEAR,
        R.L.CMD_HELP_BENCH }
end
