local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

-- A one-line readout under the merchant window. Refactor's own frame, anchored to
-- Blizzard's, never a change to it.
function R.UI:CreateJunkReadout(owner)
    if owner.refactorJunkReadout then return owner.refactorJunkReadout end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(300, 26)
    frame:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 8, -2)
    frame:SetFrameStrata("HIGH")
    Theme:Panel(frame, true)
    R:OwnFrame(frame)
    frame.text = Theme:Text(frame, "", "small", "TEXT_BODY")
    frame.text:SetPoint("LEFT", 10, 0)
    frame.text:SetPoint("RIGHT", -10, 0)
    function frame:SetText(text) self.text:SetText(text) end
    frame:Hide()
    owner.refactorJunkReadout = frame
    return frame
end
