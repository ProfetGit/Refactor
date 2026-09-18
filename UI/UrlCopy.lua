local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

-- One small box with the address selected, so Ctrl C works. The client cannot open a
-- browser, and Refactor sends nothing anywhere.
function R.UI:ShowUrl(url)
    if not self.urlFrame then
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(460, 118)
        frame:SetPoint("CENTER", 0, 120)
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        Theme:Panel(frame, true)
        R:OwnFrame(frame)
        local title = Theme:Text(frame, R.L.CHAT_URL_TITLE, "body", "TEXT_TITLE")
        title:SetPoint("TOPLEFT", 24, -20)
        frame.input = self.Widgets:Input(frame, 412, 30)
        frame.input:SetPoint("TOPLEFT", 24, -44)
        frame.input:SetScript("OnEscapePressed", function() frame:Hide() end)
        local hint = Theme:Text(frame, R.L.CHAT_URL_HINT, "small", "TEXT_MUTED")
        hint:SetPoint("BOTTOMLEFT", 24, 18)
        local close = Theme:Button(frame, 72, R.L.UI_CLOSE, function() frame:Hide() end)
        close:SetPoint("BOTTOMRIGHT", -20, 12)
        self.urlFrame = frame
    end
    self.urlFrame.input:SetText(url or "")
    self.urlFrame:Show()
    self.urlFrame.input:SetFocus()
    self.urlFrame.input:HighlightText()
end
