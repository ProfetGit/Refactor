--- @integration Prices
--- Purpose: the one place the addon asks what an item is worth, and the one plain name for
---     where that number came from.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Price = R.Price

R.Integrations = R.Integrations or {}
local Prices = {}
R.Prices = Prices

-- The two providers with an opt-in of their own (PRD 5.5), in chain order.
R.Integrations.priceProviders = { "priceTSM", "priceAuctionator" }
local PROVIDER_NAMES = { priceTSM = "tsm", priceAuctionator = "auctionator" }

-- Other price addons, in one place, each asked for by its own published entry point and
-- never by an internal. A name that does not resolve is simply not a provider: nothing is
-- printed, nothing warns, and the chain falls through to vendor price. These sit between
-- Auctionator and vendor, so an addon the player configured deliberately still wins.
--
-- Unverified: neither addon is installed on this machine, so the call shapes come from
-- each addon's own published API and have not been seen to answer on a live client. The
-- cost of being wrong is one provider that never registers.
local OTHER_PROVIDERS = {
    { name = "recrystallize", order = 240, symbol = "RECrystallize_PriceCheck" },
    { name = "auctioneer", order = 250, symbol = "AucAdvanced.API.GetMarketValue" },
}

local SOURCE_KEYS = {
    tsm = "PRICE_SOURCE_TSM",
    auctionator = "PRICE_SOURCE_AUCTIONATOR",
    recrystallize = "PRICE_SOURCE_RECRYSTALLIZE",
    auctioneer = "PRICE_SOURCE_AUCTIONEER",
    vendor = "PRICE_SOURCE_VENDOR",
}
Prices.sourceKeys = SOURCE_KEYS

-- A provider id never reaches the player. Anything the chain answers with that this table
-- has not heard of is reported as the vendor fallback's name rather than as a raw id.
function Prices.Label(source)
    return R.L[SOURCE_KEYS[source] or "PRICE_SOURCE_UNKNOWN"] or R.L.PRICE_SOURCE_VENDOR
end

-- "auto" means the chain decides. Anything else names one provider, and a named provider
-- that is not installed quietly goes back to the chain rather than reporting no price.
function Prices.Override()
    local choice = R.Settings:GetOption("priceSource")
    if choice == nil or choice == "auto" or not Price:Has(choice) or not Price:IsEnabled(choice) then
        return nil
    end
    return choice
end

-- The friendly name, never the provider id: nothing downstream has to know one exists.
function Prices.Get(itemLink, quantity)
    local value, source = Price:Get(itemLink, quantity, Prices.Override())
    if not value then
        return nil
    end
    return value, Prices.Label(source)
end

function Prices.CurrentSource()
    return Prices.Label(Prices.Override() or Price:Top() or "vendor")
end

function R.Integrations:RegisterOtherPrices()
    local found = {}
    for _, entry in ipairs(OTHER_PROVIDERS) do
        local resolve = R.Capabilities:Resolve(entry.symbol)
        if type(resolve) == "function" then
            Price:RegisterProvider(entry.name, entry.order, function(item) return resolve(item) end)
            Price:SetEnabled(entry.name, true)
            found[#found + 1] = entry.name
        end
    end
    return found
end

-- Providers register at login, after every addon has loaded, and follow the options from
-- then on. Vendor price is always on: it is the only source that exists on day one.
function R.Integrations:ApplyPriceOptions()
    for _, option in ipairs(self.priceProviders) do
        Price:SetEnabled(PROVIDER_NAMES[option], R.Settings:GetOption(option) == true)
    end
    Price:SetEnabled("vendor", true)
    -- The override is not a provider, so changing it changes no enabled flag and nothing
    -- else would invalidate the cache that was filled under the previous choice.
    local override = R.Settings:GetOption("priceSource")
    if override ~= self.appliedPriceSource then
        self.appliedPriceSource = override
        Price:Invalidate()
    end
end

function R.Integrations:RegisterPriceProviders()
    self.tsmAvailable = self:RegisterTSM()
    self.auctionatorAvailable = self:RegisterAuctionator()
    self.otherPriceAddons = self:RegisterOtherPrices()
    self:ApplyPriceOptions()
end
