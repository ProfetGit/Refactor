--- @library LibRefactorPrice-1.0
--- Purpose: one price for an item, from the first provider in the chain that answers.
--- Requires: C_Item.GetItemInfo
--- Events: none
--- Hot: no
local Price = LibStub:NewLibrary("LibRefactorPrice-1.0", 2)
if not Price then return end

Price.providers = Price.providers or {}
Price.enabled = Price.enabled or { vendor = true }
-- One answer per item for as long as the chain stays the same. There is no time-based
-- expiry anywhere in this project: the only thing that can change an answer inside a
-- session is the chain itself, and every call that changes it invalidates here by name.
Price.values = Price.values or {}
Price.sources = Price.sources or {}
Price.cacheCount = Price.cacheCount or 0

-- A farming session can see a few thousand distinct links. Past the bound the cache stops
-- growing rather than starts evicting: an unbounded table is the leak, a stale one is not.
local CACHE_LIMIT = 4000

-- A price whose source the player cannot see is worse than no price (PRD 5.5), so every
-- answer carries the provider that produced it.
function Price:RegisterProvider(name, order, resolve)
    assert(type(name) == "string" and type(order) == "number" and type(resolve) == "function")
    self:Invalidate()
    for index, provider in ipairs(self.providers) do
        if provider.name == name then
            self.providers[index] = { name = name, order = order, resolve = resolve }
            return
        end
    end
    self.providers[#self.providers + 1] = { name = name, order = order, resolve = resolve }
    table.sort(self.providers, function(a, b) return a.order < b.order end)
end

function Price:SetEnabled(name, enabled)
    enabled = enabled == true
    if self.enabled[name] ~= enabled then
        self:Invalidate()
    end
    self.enabled[name] = enabled
end

function Price:IsEnabled(name)
    return self.enabled[name] == true
end

function Price:Invalidate()
    for key in pairs(self.values) do
        self.values[key] = nil
    end
    for key in pairs(self.sources) do
        self.sources[key] = nil
    end
    self.cacheCount = 0
end

-- The name of the provider at the head of the enabled chain. It is what the player is
-- told the session is priced with; an item the head cannot price still falls through.
function Price:Top()
    for _, provider in ipairs(self.providers) do
        if self:IsEnabled(provider.name) then
            return provider.name
        end
    end
    return nil
end

function Price:Has(name)
    for _, provider in ipairs(self.providers) do
        if provider.name == name then
            return true
        end
    end
    return false
end

-- Every provider is another addon's code: it is asked through pcall and a provider that
-- errors is simply the provider that did not answer.
function Price:Resolve(item, only)
    for _, provider in ipairs(self.providers) do
        if only == nil and self:IsEnabled(provider.name) or provider.name == only then
            local ok, value = pcall(provider.resolve, item)
            if ok and type(value) == "number" and value > 0 then
                return value, provider.name
            end
            if only then
                return nil
            end
        end
    end
    return nil
end

-- Returns the value in copper and the provider name, or nil when nothing answers.
-- `only` asks one named provider instead of the chain, which is what a source override is.
function Price:Get(item, quantity, only)
    quantity = quantity or 1
    if item == nil or quantity <= 0 then
        return nil
    end
    local cached = self.values[item]
    if cached then
        return cached * quantity, self.sources[item]
    end
    local value, source = self:Resolve(item, only)
    if not value then
        -- Item info arrives asynchronously, so "no price yet" must never become "no price".
        return nil
    end
    if self.cacheCount < CACHE_LIMIT then
        self.values[item], self.sources[item] = value, source
        self.cacheCount = self.cacheCount + 1
    end
    return value * quantity, source
end

-- Vendor sell price is the only provider that always exists, and on launch day it is the
-- only honest one: no realm has auction data yet.
Price:RegisterProvider("vendor", 300, function(item)
    if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then
        return nil
    end
    return select(11, C_Item.GetItemInfo(item))
end)
