--- @module mail.takeAll
--- Purpose: provide a cancellable, manual and rate-limited mail collection queue.
--- Requires: InCombatLockdown, GetInboxNumItems, GetInboxHeaderInfo, HasInboxItem, TakeInboxMoney,
---     TakeInboxItem, ATTACHMENTS_MAX, C_Mail.IsCommandPending
--- Events: MAIL_SHOW; MAIL_CLOSED, MAIL_INBOX_UPDATE, MAIL_FAILED, UI_ERROR_MESSAGE, PLAYER_REGEN_DISABLED (contextual)
--- Hot: no
local _, R = ...
local TakeAll = R:RegisterModule({
    id = "mail.takeAll", category = "Mail", nameKey = "MAIL_TAKE_ALL_NAME",
    descriptionKey = "MAIL_TAKE_ALL_DESC", detailKey = "MAIL_TAKE_ALL_DETAIL",
    requires = { "InCombatLockdown", "GetInboxNumItems", "GetInboxHeaderInfo",
        "HasInboxItem", "TakeInboxMoney", "TakeInboxItem", "ATTACHMENTS_MAX", "C_Mail.IsCommandPending" },
    tier = "standard", risk = "safe", defaultEnabled = false,
})
local RETRIEVAL_DELAY, RESPONSE_TIMEOUT = 0.2, 5

local function inboxTotals()
    local items, money = 0, 0
    local count = GetInboxNumItems()
    for index = 1, count do
        local _, _, _, _, value, _, _, attachments = GetInboxHeaderInfo(index)
        items = items + (attachments or 0)
        money = money + (value or 0)
    end
    return count, items, money
end

function TakeAll:Stop(reasonKey)
    self.running, self.pending = false, nil
    R:CancelTimers(self)
    R.Broker:Unsubscribe("MAIL_INBOX_UPDATE", self)
    R.Broker:Unsubscribe("MAIL_FAILED", self)
    R.Broker:Unsubscribe("UI_ERROR_MESSAGE", self)
    R.Broker:Unsubscribe("PLAYER_REGEN_DISABLED", self)
    if self.controls then
        self.controls:SetRunning(false)
        self.controls:SetProgress(R.L[reasonKey or "MAIL_STOPPED"] or R.L.MAIL_STOPPED)
    end
end

function TakeAll:OnClosed()
    self.open = false
    self:Stop()
    self.controls:Hide()
    R.Broker:Unsubscribe("MAIL_CLOSED", self)
end

function TakeAll:OnShown()
    self:Stop()
    self.open = true
    self.controls:SetProgress(R.L.MAIL_READY)
    self.controls:Show()
    R.Broker:Subscribe("MAIL_CLOSED", self.OnClosed, self)
end

function TakeAll:OnFailed()
    self:Stop("MAIL_FAILED")
end

function TakeAll:OnCombat()
    self:Stop("MAIL_PAUSED")
end

function TakeAll:OnTimeout()
    self:Stop("MAIL_TIMEOUT")
end

function TakeAll:TryConfirm()
    if not self.running or not self.pending or C_Mail.IsCommandPending() then
        return
    end
    local count, items, money = inboxTotals()
    local pending = self.pending
    if count < pending.count or items < pending.items or money < pending.money then
        self.pending = nil
        R:CancelTimers(self)
        self.completed = self.completed + 1
        self.controls:SetProgress(string.format(R.L.MAIL_PROGRESS, self.completed))
        R:After(self, RETRIEVAL_DELAY, self.Next)
    end
end

function TakeAll:OnInboxUpdate()
    -- Events acknowledge progress; the timer only gives the server state time to settle.
    if self.running and self.pending then
        R:After(self, RETRIEVAL_DELAY, self.TryConfirm)
    end
end

function TakeAll:Next()
    if not self.running or not self.open then
        return
    end
    if InCombatLockdown() or R:Paused() then
        self:Stop("MAIL_PAUSED")
        return
    end
    if C_Mail.IsCommandPending() then
        self:Stop("MAIL_BUSY")
        return
    end
    -- The inbox can shrink and reorder after every request. Resolve a fresh index each time.
    for index = 1, GetInboxNumItems() do
        local _, _, _, _, money, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(index)
        if not isGM and (cod or 0) == 0 then
            local attachment
            if (money or 0) == 0 and (itemCount or 0) > 0 then
                for slot = 1, ATTACHMENTS_MAX do
                    if HasInboxItem(index, slot) then
                        attachment = slot
                        break
                    end
                end
            end
            if (money or 0) > 0 or attachment then
                local count, items, totalMoney = inboxTotals()
                self.pending = { count = count, items = items, money = totalMoney }
                R:After(self, RESPONSE_TIMEOUT, self.OnTimeout)
                if (money or 0) > 0 then
                    TakeInboxMoney(index)
                else
                    TakeInboxItem(index, attachment)
                end
                return
            end
        end
    end
    self:Stop()
    self.controls:SetProgress(string.format(R.L.MAIL_DONE, self.completed))
end

function TakeAll:Start()
    if self.running or not self.open then
        return
    end
    if InCombatLockdown() or R:Paused() then
        self:Stop("MAIL_PAUSED")
        return
    end
    self.running, self.completed = true, 0
    self.controls:SetRunning(true)
    self.controls:SetProgress(string.format(R.L.MAIL_PROGRESS, 0))
    R.Broker:Subscribe("MAIL_INBOX_UPDATE", self.OnInboxUpdate, self, 0.1)
    R.Broker:Subscribe("MAIL_FAILED", self.OnFailed, self)
    R.Broker:Subscribe("UI_ERROR_MESSAGE", self.OnFailed, self)
    R.Broker:Subscribe("PLAYER_REGEN_DISABLED", self.OnCombat, self)
    self:Next()
end

function TakeAll:OnEnable()
    self.controls = R.UI:CreateMailControls(self)
    self.controls:Hide()
    R.Broker:Subscribe("MAIL_SHOW", self.OnShown, self)
end

function TakeAll:OnDisable()
    self.open = false
    self:Stop()
    if self.controls then
        self.controls:Hide()
    end
    R.Broker:UnsubscribeAll(self)
end
