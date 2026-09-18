--- @integration Plater
--- Purpose: report whether Plater owns the nameplates, so Refactor does not draw on them.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...

R.Integrations = R.Integrations or {}
R.Integrations.providers = R.Integrations.providers or {}
R.Integrations.providers["Plater"] = "nameplates.questProgress"

-- One question for every module: is a neighbour already doing this job? Deference is
-- decided once at enable, never per plate, so it costs nothing while deferring.
function R.Integrations:Owner(moduleID)
    for addon, owned in pairs(self.providers) do
        if owned == moduleID and self:IsLoaded(addon) then
            return addon
        end
    end
end
