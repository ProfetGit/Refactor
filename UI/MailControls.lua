local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

function R.UI:CreateMailControls(owner)
    if owner.refactorMailControls then return owner.refactorMailControls end
    local controls = CreateFrame("Frame", nil, UIParent)
    controls:SetSize(470, 142)
    controls:SetPoint("BOTTOM", 0, 190)
    controls:SetFrameStrata("DIALOG")
    controls:EnableMouse(true)
    controls:SetMovable(true)
    controls:SetClampedToScreen(true)
    controls:RegisterForDrag("LeftButton")
    controls:SetScript("OnDragStart", function(widget) widget:StartMoving() end)
    controls:SetScript("OnDragStop", function(widget) widget:StopMovingOrSizing() end)
    Theme:Panel(controls)
    local title = Theme:Text(controls, R.L.UI_MAIL_TITLE, "body", "TEXT_TITLE")
    title:SetPoint("TOPLEFT", 24, -20)
    local progress = Theme:Text(controls, R.L.UI_MAIL_IDLE, "small", "TEXT_BODY")
    progress:SetPoint("TOPLEFT", 24, -48)
    progress:SetPoint("RIGHT", -24, 0)
    local take = Theme:Button(controls, 172, R.L.UI_MAIL_TAKE, function() owner:Start() end)
    take:SetPoint("BOTTOMLEFT", 24, 22)
    local stop = Theme:Button(controls, 80, R.L.UI_MAIL_STOP, function() owner:Stop() end)
    stop:SetPoint("LEFT", take, "RIGHT", 12, 0)
    function controls:SetProgress(text) progress:SetText(text) end
    function controls:SetRunning(running)
        take:SetEnabled(not running)
        stop:SetEnabled(running == true)
    end
    controls:SetRunning(false)
    controls:Hide()
    owner.refactorMailControls = controls
    return controls
end
