--- @library LibRefactorPrice-1.0
--- Purpose: one price for an item, from the first provider in the chain that answers.
--- Requires: C_Item.GetItemInfo
--- Events: none
--- Hot: no
local Price = LibStub:NewLibrary("LibRefactorPrice-1.0", 1)
if not Price then return end

Price.providers = Price.providers or {}
Price.enabled = Price.enabled or { vendor = true }

-- A price whose source the player cannot see is worse than no price (PRD 5.5), so every
-- answer carries the provider that produced it.
function Price:RegisterProvider(name, order, resolve)
    assert(type(name) == "string" and type(order) == "number" and type(resolve) == "function")
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
    self.enabled[name] = enabled == true
end

function Price:IsEnabled(name)
    return self.enabled[name] == true
end

-- Returns the value in copper and the provider name, or nil when nothing answers.
function Price:Get(item, quantity)
    quantity = quantity or 1
    if item == nil or quantity <= 0 then
        return nil
    end
    for _, provider in ipairs(self.providers) do
        if self:IsEnabled(provider.name) then
            local ok, value = pcall(provider.resolve, item)
            if ok and type(value) == "number" and value > 0 then
                return value * quantity, provider.name
            end
        end
    end
    return nil
end

-- Vendor sell price is the only provider that always exists, and on launch day it is the
-- only honest one: no realm has auction data yet.
Price:RegisterProvider("vendor", 300, function(item)
    if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then
        return nil
    end
    return select(11, C_Item.GetItemInfo(item))
end)
