--- @module interface.screenshotLevelUp
--- Purpose: take a screenshot shortly after a level up.
--- Requires: Screenshot
--- Events: PLAYER_LEVEL_UP
--- Hot: no
local _, R = ...
local ScreenshotLevelUp = R:RegisterModule({
    id = "interface.screenshotLevelUp", category = "Interface", nameKey = "SCREENSHOT_NAME",
    descriptionKey = "SCREENSHOT_DESC", detailKey = "SCREENSHOT_DETAIL",
    requires = { "Screenshot" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

local DELAY = 1.5

function ScreenshotLevelUp:Take()
    Screenshot()
end

function ScreenshotLevelUp:OnLevelUp()
    R:CancelTimers(self)
    R:After(self, DELAY, self.Take)
end

function ScreenshotLevelUp:OnEnable()
    R.Broker:Subscribe("PLAYER_LEVEL_UP", self.OnLevelUp, self)
end

function ScreenshotLevelUp:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
end
