local _, R = ...
local Registry = {}
R.Registry = Registry

local function resolve(module)
    return type(module) == "string" and R.moduleByID[module] or module
end

function R:RegisterModule(definition)
    assert(type(definition) == "table", "module definition required")
    assert(type(definition.id) == "string" and definition.id:match("^[a-z][%w]*%.[%w]+$"), "invalid module id")
    assert(not self.moduleByID[definition.id], "duplicate module id")
    assert(type(definition.requires) == "table", "module requires list required")
    definition.state = "disabled"
    definition.defaultEnabled = definition.defaultEnabled == true
    self.modules[#self.modules + 1] = definition
    self.moduleByID[definition.id] = definition
    if self.Settings then
        self.Settings:RegisterDefaults(definition.id, definition.defaultEnabled)
    end
    return definition
end

function Registry:Fail(module, reason)
    module = resolve(module)
    if type(module) ~= "table" then
        return
    end
    if module._failing then
        return
    end
    module._failing = true
    module.state = "failed"
    module.failure = tostring(reason)
    if module.OnDisable then
        R:Try(module, module.OnDisable, "OnDisable after failure")
    end
    R.Broker:UnsubscribeAll(module)
    R:CancelTimers(module)
    module._failing = nil
    R.Broker:Emit("REFACTOR_MODULE_CHANGED", module.id)
end

function Registry:Enable(module)
    module = resolve(module)
    if not module then
        return false
    end
    if module.state == "enabled" then
        return true
    end
    if module.unavailableReasonKey then
        module.state = "unavailable"
        -- A module that filled in its own reason (naming the addon deferring to, say) keeps
        -- it; re-reading the locale key here would replace the text with its format string.
        module.unavailableReason = module.unavailableReason
            or (R.L and R.L[module.unavailableReasonKey]) or module.unavailableReasonKey
        R.Broker:Emit("REFACTOR_MODULE_CHANGED", module.id)
        return false
    end
    if module.risk == "automation" and not R.Settings:IsConfirmed(module.id) then
        -- Not a failure and not unavailable: it is waiting for the player to read the
        -- dialog. "No automation is on unless you turned it on" stays literally true.
        module.state = "unconfirmed"
        R.Broker:Emit("REFACTOR_MODULE_CHANGED", module.id)
        return false
    end
    local available, missing = R.Capabilities:Check(module.requires)
    module.missing = missing
    if not available then
        module.state = "unavailable"
        R.Broker:Emit("REFACTOR_MODULE_CHANGED", module.id)
        return false
    end
    module.failure = nil
    module.state = "enabled"
    if module.OnEnable then
        local ok, err = R:Try(module, module.OnEnable, "OnEnable")
        if not ok then
            self:Fail(module, err)
            return false
        end
    end
    R.Broker:Emit("REFACTOR_MODULE_CHANGED", module.id)
    return module.state == "enabled"
end

function Registry:Disable(module)
    module = resolve(module)
    if not module then
        return false
    end
    local ok, err = true, nil
    if module.state == "enabled" and module.OnDisable then
        ok, err = R:Try(module, module.OnDisable, "OnDisable")
    end
    R.Broker:UnsubscribeAll(module)
    R:CancelTimers(module)
    module.unavailableReason = nil
    module.state = ok and "disabled" or "failed"
    module.failure = err
    R.Broker:Emit("REFACTOR_MODULE_CHANGED", module.id)
    return ok
end

function Registry:Reconcile(module)
    module = resolve(module)
    if not module then
        return false
    end
    if module.unavailableReasonKey then
        return self:Enable(module)
    end
    if not R.Capabilities:Check(module.requires) then
        return self:Enable(module)
    end
    if R.Settings:Get(module.id) then
        -- Failed callbacks stay disabled until the user explicitly cycles the setting.
        if module.state == "failed" then
            return false
        end
        return self:Enable(module)
    end
    if module.state == "unconfirmed" then
        module.state = "disabled"
    end
    return self:Disable(module)
end

function Registry:ReconcileAll()
    for _, module in ipairs(R.modules) do
        self:Reconcile(module)
    end
end
