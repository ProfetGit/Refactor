--- @integration FrameOwners
--- Purpose: report which addon already owns a group of Blizzard frames, so UI visibility leaves it alone.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...

R.Integrations = R.Integrations or {}
R.Integrations.providers = R.Integrations.providers or {}
R.Integrations.neighbours = R.Integrations.neighbours or {}

-- ElvUI replaces the chat and the bars alike, so it owns the whole module. Bartender4 and
-- Dominos hide Blizzard's bars and draw their own; fading a bar nobody sees is not a
-- feature, so those groups stand down while the chat groups keep working.
R.Integrations.providers["ElvUI"] = "interface.visibility"
local BAR_GROUPS = { "bars.main", "bars.bottomLeft", "bars.bottomRight", "bars.right", "bars.left", "bars.five",
    "bars.six", "bars.seven" }
R.Integrations.frameOwners = {
    { addon = "Bartender4", labelKey = "NEIGHBOUR_BARTENDER", groups = BAR_GROUPS },
    { addon = "Dominos", labelKey = "NEIGHBOUR_DOMINOS", groups = BAR_GROUPS },
}
local neighbours = R.Integrations.neighbours
neighbours[#neighbours + 1] = { addon = "ElvUI", labelKey = "NEIGHBOUR_ELVUI", modules = { "interface.visibility" } }
neighbours[#neighbours + 1] = { addon = "Bartender4", labelKey = "NEIGHBOUR_BARTENDER",
    modules = { "interface.visibility" } }
neighbours[#neighbours + 1] = { addon = "Dominos", labelKey = "NEIGHBOUR_DOMINOS",
    modules = { "interface.visibility" } }

-- The addon folder that owns a frame group, or nil. Decided at enable, like every deference.
function R.Integrations:FrameGroupOwner(groupID)
    for _, owner in ipairs(self.frameOwners) do
        if self:IsLoaded(owner.addon) then
            for _, id in ipairs(owner.groups) do
                if id == groupID then
                    return owner.addon
                end
            end
        end
    end
    return nil
end
