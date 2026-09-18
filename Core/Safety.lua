--- @core safety
--- Purpose: resolve the shared pause modifier so every automatic action honours one key.
--- Requires: IsControlKeyDown, IsShiftKeyDown, IsAltKeyDown
--- Events: none
--- Hot: no
local _, R = ...

local modifierChecks = { CTRL = "IsControlKeyDown", SHIFT = "IsShiftKeyDown", ALT = "IsAltKeyDown" }

-- Holding the configured modifier skips the next automatic action. Modules ask here
-- rather than naming a key, so changing the option changes every module at once.
function R:Paused()
    local modifier = self.Settings:GetOption("killSwitch")
    local check = self.Capabilities:Resolve(modifierChecks[modifier] or modifierChecks.CTRL)
    return type(check) == "function" and check() == true
end
