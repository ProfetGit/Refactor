local _, R = ...
local UI, L = R.UI, R.L
local Theme = R.Theme

-- One dialog, reused. Automation is explained once per feature and never bundled, so the
-- claim "nothing decides for you unless you said yes" stays literally true (PRD 6.3).
function UI:BuildConfirm(parent)
    local dialog = CreateFrame("Frame", nil, parent)
    dialog:SetSize(520, 280)
    dialog:SetPoint("CENTER")
    dialog:SetFrameLevel(parent:GetFrameLevel() + 40)
    dialog:EnableMouse(true)
    Theme:Panel(dialog)
    dialog.title = Theme:Text(dialog, "", "title", "TEXT_WARNING")
    dialog.title:SetPoint("TOPLEFT", 26, -26)
    dialog.title:SetPoint("RIGHT", -26, 0)
    dialog.body = Theme:Text(dialog, "", "body", "TEXT_BODY")
    dialog.body:SetPoint("TOPLEFT", 26, -64)
    dialog.body:SetPoint("BOTTOMRIGHT", -26, 70)
    dialog.body:SetJustifyV("TOP")
    dialog.accept = Theme:Button(dialog, 180, L.UI_CONFIRM_ACCEPT, function()
        local accepted = dialog.onAccept
        dialog.onAccept = nil
        dialog:Hide()
        if accepted then accepted() end
    end)
    dialog.accept:SetPoint("BOTTOMLEFT", 26, 24)
    dialog.cancel = Theme:Button(dialog, 140, L.UI_CONFIRM_CANCEL, function()
        dialog.onAccept = nil
        dialog:Hide()
    end)
    dialog.cancel:SetPoint("BOTTOMRIGHT", -26, 24)
    dialog:Hide()
    self.confirmFrame = dialog
end

function UI:Confirm(title, body, onAccept)
    local dialog = self.confirmFrame
    if not dialog then
        if onAccept then onAccept() end
        return
    end
    dialog.title:SetText(title)
    dialog.body:SetText(body)
    dialog.onAccept = onAccept
    dialog:Show()
end

function UI:ConfirmAutomation(module, onAccept)
    local body = string.format(L.UI_AUTOMATION_BODY, self:ModuleText(module, "detail"),
        R.L["UI_" .. (R.Settings:GetOption("killSwitch") or "CTRL")])
    self:Confirm(string.format(L.UI_AUTOMATION_TITLE, self:ModuleText(module, "name")), body, function()
        R.Settings:Confirm(module.id, true)
        if onAccept then onAccept() end
    end)
end
