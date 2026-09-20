--- @core fade
--- Purpose: the one OnUpdate driver in the addon, tweening frame alpha and going idle when nothing moves.
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
    for frame, record in pairs(Fade.records) do
        record.elapsed = record.elapsed + elapsed
        local progress = min(1, record.elapsed / record.duration)
        frame:SetAlpha(record.from + (record.to - record.from) * progress)
        if progress >= 1 then
            finish(Fade, frame)
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
