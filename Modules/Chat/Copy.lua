--- @module chat.copy
--- Purpose: hand over the text of a chat window as plain text you can select and copy.
--- Requires: ChatFrame1
--- Events: none. The chat windows, and the client's own test for a secret value, are resolved
---     by name at enable, so a client with fewer windows loses those windows, not the module.
---     Lines are read with the frame's own GetNumMessages and GetMessageInfo, which are widget
---     methods and out of scope for the requires check (PRD 10.4). Each button is handed to the
---     Chat buttons visibility group through Core, so it fades with Blizzard's chat buttons.
--- Hot: no
local _, R = ...
local Copy = R:RegisterModule({
    id = "chat.copy", category = "Chat", nameKey = "CHAT_COPY_NAME",
    descriptionKey = "CHAT_COPY_DESC", detailKey = "CHAT_COPY_DETAIL",
    requires = { "ChatFrame1" },
    risk = "visible", defaultEnabled = true,
})

local WINDOW_NAME, MAX_WINDOWS = "ChatFrame", 10
-- The group the button belongs to on the UI visibility panel. Blizzard's chat buttons sit
-- in the same corner of the same window, so they are the same element to a player.
local VISIBILITY_GROUP = "chat.buttons"
-- The client keeps a few hundred lines a window at most, and a box past this is not
-- something anyone reads. The newest lines are the ones kept.
local MAX_LINES = 500
-- 12.0 can hand a tainted addon a secret value instead of a string. Where the client has
-- no such test, nothing it gives us is secret.
local SECRET_TEST = "issecretvalue"

-- What the client draws and a text box cannot: colour, textures, atlases, and the
-- battle.net name tokens. A hyperlink keeps the words in its brackets, because that is
-- what the line reads as on screen. The literal bar is last, or it would eat the escapes
-- before they are matched.
local PATTERNS = {
    { "|cn.-:", "" },
    { "|c%x%x%x%x%x%x%x%x", "" },
    { "|r", "" },
    { "|H.-|h(.-)|h", "%1" },
    { "|T.-|t", "" },
    { "|A.-|a", "" },
    { "|K.-|k", "" },
    { "||", "|" },
    -- An icon at the head of a line leaves its space behind when it goes.
    { "^%s+", "" },
    { "%s+$", "" },
}

function Copy:Plain(text)
    for _, rule in ipairs(PATTERNS) do
        text = text:gsub(rule[1], rule[2])
    end
    return text
end

-- Oldest line first, which is the order they were read in. A line the client will not hand
-- over is counted rather than guessed at, so the box never quietly drops something.
function Copy:Lines(chatFrame)
    local lines, skipped = {}, 0
    local count = chatFrame:GetNumMessages() or 0
    for index = math.max(1, count - MAX_LINES + 1), count do
        local text = chatFrame:GetMessageInfo(index)
        if (self.isSecret and self.isSecret(text)) or type(text) ~= "string" then
            skipped = skipped + 1
        else
            lines[#lines + 1] = self:Plain(text)
        end
    end
    return lines, skipped
end

function Copy:Show(chatFrame)
    local lines, skipped = self:Lines(chatFrame)
    local text = #lines > 0 and table.concat(lines, "\n") or R.L.CHAT_COPY_EMPTY
    if skipped > 0 then
        text = string.format(R.L.CHAT_COPY_SKIPPED, skipped) .. "\n" .. text
    end
    R.UI:ShowSessionText(text, R.L.CHAT_COPY_TITLE)
end

function Copy:OnEnable()
    self.isSecret = R.Capabilities:Resolve(SECRET_TEST)
    self.windows, self.buttons = {}, {}
    for index = 1, MAX_WINDOWS do
        local frame = R.Capabilities:Resolve(WINDOW_NAME .. index)
        if type(frame) == "table" and type(frame.GetNumMessages) == "function"
            and type(frame.GetMessageInfo) == "function" then
            self.windows[#self.windows + 1] = frame
            local button = R.UI:ChatCopyButton(frame, function()
                R:Try(self, self.Show, "copy a chat window", frame)
            end)
            self.buttons[#self.buttons + 1] = button
            R.Visibility:Contribute(VISIBILITY_GROUP, button)
        end
    end
end

function Copy:OnDisable()
    for _, button in ipairs(self.buttons or {}) do
        R.Visibility:Withdraw(VISIBILITY_GROUP, button)
    end
    R.UI:HideChatCopyButtons()
    R.Broker:UnsubscribeAll(self)
    self.windows, self.buttons, self.isSecret = nil, nil, nil
end
