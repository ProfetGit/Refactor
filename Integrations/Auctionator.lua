--- @integration Auctionator
--- Purpose: offer Auctionator's price database as an opt-in provider, labelled as such.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Price = R.Price

R.Integrations = R.Integrations or {}
R.Integrations.priceProviders = { "priceTSM", "priceAuctionator" }
local PROVIDER_NAMES = { priceTSM = "tsm", priceAuctionator = "auctionator" }

function R.Integrations:RegisterAuctionator()
    local getPrice = R.Capabilities:Resolve("Auctionator.API.v1.GetAuctionPriceByItemLink")
    if type(getPrice) ~= "function" then
        return false
    end
    Price:RegisterProvider("auctionator", 200, function(item)
        return getPrice(R.name, item)
    end)
    return true
end

-- Providers register at login, after every addon has loaded, and follow the options
-- from then on. Vendor price is always on: it is the only source that exists on day one.
function R.Integrations:ApplyPriceOptions()
    for _, option in ipairs(self.priceProviders) do
        Price:SetEnabled(PROVIDER_NAMES[option], R.Settings:GetOption(option) == true)
    end
    Price:SetEnabled("vendor", true)
end

function R.Integrations:RegisterPriceProviders()
    self.tsmAvailable = self:RegisterTSM()
    self.auctionatorAvailable = self:RegisterAuctionator()
    self:ApplyPriceOptions()
end
