-- Refactor Addon - Base Module System
-- Provides automated lifecycle and event management for all features

local addonName, addon = ...

-- Expose module mixin globally for the addon table
addon.ModuleMixin = {}
local ModuleMixin = addon.ModuleMixin

----------------------------------------------
-- Module Lifecycle Management
----------------------------------------------

-- Should be called during AddonLoaded by Init.lua
function ModuleMixin:Initialize()
    -- Initialize cached settings if a mapper exists
    if self.UpdateCachedSettings then
        self:UpdateCachedSettings()
    end

    -- Call custom initialization logic for the module
    if self.OnInitialize then
        self:OnInitialize()
    end

    local mainSetting = self.settingKey
    if mainSetting then
        -- Listen for setting changes to toggle the module
        addon.CallbackRegistry:Register("SettingChanged." .. mainSetting, function(value)
            if value then
                self:Enable()
            else
                self:Disable()
            end
        end)

        -- Enable immediately if the setting is true
        if addon.GetDBBool(mainSetting) then
            self:Enable()
        end
    end

    self.isInitialized = true
end

function ModuleMixin:Enable()
    if self.isEnabled then return end
    self.isEnabled = true

    -- Hook up events if eventMap exists
    if self.eventMap then
        if not self.eventFrame then
            self.eventFrame = CreateFrame("Frame")
            self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
                if self.eventMap[event] then
                    self.eventMap[event](self, event, ...)
                elseif type(self.OnEvent) == "function" then
                    self:OnEvent(event, ...)
                end
            end)
        end
        for event, handler in pairs(self.eventMap) do
            if type(event) == "string" then
                self.eventFrame:RegisterEvent(event)
            end
        end
    end

    if self.OnEnable then
        self:OnEnable()
    end
end

function ModuleMixin:Disable()
    if not self.isEnabled then return end
    self.isEnabled = false

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.OnDisable then
        self:OnDisable()
    end
end

----------------------------------------------
-- Module Registration Helper
----------------------------------------------
-- Creates a new module with the given name and options
-- @param name (string) The name of the module
-- @param options (table) Configuration: { settingKey = "MySetting", eventMap = { ["EVENT"] = func }, ... }
function addon:NewModule(name, options)
    local module = {}
    Mixin(module, ModuleMixin)

    module.name = name
    module.isEnabled = false
    module.isInitialized = false

    if options then
        for k, v in pairs(options) do
            module[k] = v
        end
    end

    addon.RegisterModule(name, module)
    return module
end
