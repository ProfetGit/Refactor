--- @integration Auctionator
--- Purpose: offer Auctionator's price database as an opt-in provider, labelled as such.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Price = R.Price

R.Integrations = R.Integrations or {}

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
