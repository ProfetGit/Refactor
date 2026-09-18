--- @module mail.lastRecipient
--- Purpose: remember who this character last mailed and prefill an empty To field.
--- Requires: SendMailNameEditBox, SendMailFrame
--- Events: MAIL_SEND_SUCCESS; a hooked OnShow on the send tab
--- Hot: no
local _, R = ...
local LastRecipient = R:RegisterModule({
    id = "mail.lastRecipient", category = "Mail", nameKey = "MAIL_RECIPIENT_NAME",
    descriptionKey = "MAIL_RECIPIENT_DESC", detailKey = "MAIL_RECIPIENT_DETAIL",
    requires = { "SendMailNameEditBox", "SendMailFrame" },
    tier = "standard", risk = "safe", defaultEnabled = false,
})

local MAX_NAME = 80

function LastRecipient:OnSent()
    local name = SendMailNameEditBox:GetText()
    local character = R.Settings.character
    if character and type(name) == "string" and #name > 0 and #name <= MAX_NAME then
        character.lastMailRecipient = name
    end
end

function LastRecipient:Fill()
    local character = R.Settings.character
    local name = character and character.lastMailRecipient
    if self.state == "enabled" and type(name) == "string" and SendMailNameEditBox:GetText() == "" then
        SendMailNameEditBox:SetText(name)
    end
end

function LastRecipient:OnShow()
    -- Blizzard's own OnShow runs first and may clear the field; fill on the next tick.
    R:CancelTimers(self)
    R:After(self, 0, self.Fill)
end

function LastRecipient:OnEnable()
    R.Broker:Subscribe("MAIL_SEND_SUCCESS", self.OnSent, self)
    if not self.installed then
        self.installed = true
        SendMailFrame:HookScript("OnShow", function()
            if self.state == "enabled" then
                self:OnShow()
            end
        end)
    end
end

function LastRecipient:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
end
