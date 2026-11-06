--- @core fade
--- Purpose: the one OnUpdate driver in the addon, tweening frame alpha and other values, idle when nothing moves.
--- Requires: CreateFrame
--- Events: none
--- Hot: no
local _, R = ...
local Fade = { records = {}, active = 0 }
R.Fade = Fade
local pairs, min, abs = pairs, math.min, math.abs

-- Blizzard's UIFrameFade writes into the faded frame's own table and keeps a list of every
-- frame it touches; this driver keeps its records to itself, so a Blizzard frame carries
-- nothing of Refactor's after a fade ends.
local driver = CreateFrame("Frame")
R:OwnFrame(driver)
Fade.driver = driver
local pool = R.Pools:CreateTablePool()

local function finish(self, frame)
    local record = self.records[frame]
    if not record then
        return
    end
    self.records[frame] = nil
    pool:Release(record)
    self.active = self.active - 1
    if self.active == 0 then
        driver:SetScript("OnUpdate", nil)
    end
end

local function step(_, elapsed)
    for key, record in pairs(Fade.records) do
        record.elapsed = record.elapsed + elapsed
        local progress = min(1, record.elapsed / record.duration)
        local apply = record.apply
        if apply then
            local eased = progress * progress * (3 - 2 * progress)
            local value = record.from + (record.to - record.from) * eased
            record.value = value
            -- An error in the caller's write ends this tween rather than leaving the driver
            -- running with a record that can never finish.
            if not R:SafeCall(key, apply, "fade", value) then
                progress = 1
            end
        else
            key:SetAlpha(record.from + (record.to - record.from) * progress)
        end
        if progress >= 1 then
            finish(Fade, key)
        end
    end
end

-- seconds is the time for a full swing from 0 to 1; a shorter move takes its share of it, so a
-- fade interrupted halfway comes back at the same speed it left. A retarget mid-fade starts
-- from wherever the frame is now.
function Fade:To(frame, alpha, seconds)
    local current = frame:GetAlpha()
    local duration = seconds and seconds * abs(alpha - current) or 0
    if duration <= 0 then
        self:Snap(frame, alpha)
        return
    end
    local record = self.records[frame]
    if not record then
        record = pool:Acquire()
        self.records[frame] = record
        self.active = self.active + 1
        if self.active == 1 then
            driver:SetScript("OnUpdate", step)
        end
    end
    record.from, record.to, record.duration, record.elapsed = current, alpha, duration, 0
end

-- A number that is not a frame's alpha, a camera CVar say. apply(key, value) writes it, and
-- key is the caller's own table, so a second call for the same key retargets the tween from
-- the value last written. A fresh tween writes from before returning, so a reset of the same
-- value earlier in the frame never reaches the screen. Eased at both ends: a camera that
-- starts and stops on a straight line reads as a jolt. Without a from, a zero duration, or
-- nowhere to go, the value is written once and no record is kept.
function Fade:Value(key, to, seconds, apply, from)
    local record = self.records[key]
    local current = record and record.value or from
    if current == nil or not seconds or seconds <= 0 or current == to then
        finish(self, key)
        R:SafeCall(key, apply, "fade", to)
        return
    end
    if not record then
        record = pool:Acquire()
        self.records[key] = record
        self.active = self.active + 1
        if self.active == 1 then
            driver:SetScript("OnUpdate", step)
        end
        R:SafeCall(key, apply, "fade", current)
    end
    record.from, record.to, record.duration, record.elapsed = current, to, seconds, 0
    record.apply, record.value = apply, current
end

function Fade:Snap(frame, alpha)
    finish(self, frame)
    frame:SetAlpha(alpha)
end

function Fade:Cancel(frame)
    finish(self, frame)
end

function Fade:Active()
    return self.active
end
