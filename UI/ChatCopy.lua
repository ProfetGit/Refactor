local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")
local L = R.L

local BUTTON_WIDTH, BUTTON_HEIGHT, INSET = 52, 18, -4

local function buttonEnter(button)
    if not GameTooltip then
        return
    end
    local r, g, b = unpack(Theme.colors.TEXT_BODY)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.CHAT_COPY_TIP_TITLE)
    GameTooltip:AddLine(L.CHAT_COPY_TIP, r, g, b, true)
    GameTooltip:Show()
end

local function buttonLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

-- One button per chat window, made once and kept. It is parented to the window, so it
-- moves with it and a tab the player is not looking at hides its button along with the
-- text, which is the whole reason it is not one button somewhere on the screen.
--
-- No fade of its own: the button joins the Chat buttons visibility group, and a frame with
-- two things writing its alpha flickers. Whatever the group's rule says is the whole answer,
-- and with that feature off the button simply sits there like Blizzard's own chat buttons.
function R.UI:ChatCopyButton(chatFrame, onClick)
    self.chatCopyButtons = self.chatCopyButtons or {}
    local button = self.chatCopyButtons[chatFrame]
    if not button then
        button = Theme:Button(chatFrame, BUTTON_WIDTH, L.CHAT_COPY_BUTTON, nil, BUTTON_HEIGHT)
        button:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", INSET, INSET)
        button:SetScript("OnEnter", buttonEnter)
        button:SetScript("OnLeave", buttonLeave)
        R:OwnFrame(button)
        self.chatCopyButtons[chatFrame] = button
    end
    button:SetScript("OnClick", onClick)
    button:SetAlpha(1)
    button:Show()
    return button
end

function R.UI:HideChatCopyButtons()
    for _, button in pairs(self.chatCopyButtons or {}) do
        button:Hide()
    end
end
