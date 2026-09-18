local _, R = ...
local Pools = {}
R.Pools = Pools

function Pools:Create(factory, reset)
    assert(type(factory) == "function", "pool factory required")
    local pool = { free = {}, active = {}, count = 0 }
    function pool:Acquire()
        local object = table.remove(self.free)
        if not object then
            object = factory()
            assert(object ~= nil, "pool factory returned nil")
            self.count = self.count + 1
        end
        self.active[object] = true
        return object
    end
    function pool:Release(object)
        if not self.active[object] then
            return false
        end
        if reset then
            reset(object)
        end
        self.active[object] = nil
        self.free[#self.free + 1] = object
        return true
    end
    function pool:ReleaseAll()
        for object in pairs(self.active) do
            self:Release(object)
        end
    end
    return pool
end

function Pools:CreateTablePool()
    return self:Create(function() return {} end, function(object)
        for key in pairs(object) do
            object[key] = nil
        end
    end)
end
