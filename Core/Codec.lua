local _, R = ...
local Codec = {}
R.Codec = Codec
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local reverse = {}
for i = 1, #alphabet do
    reverse[alphabet:sub(i, i)] = i - 1
end
local MAX_ENCODED, MAX_ENTRIES = 32768, 256

function Codec:ValidName(name)
    return type(name) == "string" and #name > 0 and #name <= 64 and not name:find("[%c]")
end

function Codec:ValidID(id)
    return type(id) == "string" and #id <= 80 and id:match("^[a-z][%w]*%.[%w]+$") ~= nil
end

function Codec:ValidateValues(values)
    if type(values) ~= "table" then
        return false
    end
    local count = 0
    for key, value in pairs(values) do
        count = count + 1
        if count > MAX_ENTRIES or not self:ValidID(key) or type(value) ~= "boolean" then
            return false
        end
    end
    return true
end

local function encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local value = a * 65536 + (b or 0) * 256 + (c or 0)
        local p = math.floor(value / 262144) % 64
        local q = math.floor(value / 4096) % 64
        local r = math.floor(value / 64) % 64
        local s = value % 64
        out[#out + 1] = alphabet:sub(p + 1, p + 1) .. alphabet:sub(q + 1, q + 1)
            .. (b and alphabet:sub(r + 1, r + 1) or "=")
            .. (c and alphabet:sub(s + 1, s + 1) or "=")
    end
    return table.concat(out)
end

local function decode(data)
    if type(data) ~= "string" or #data == 0 or #data > MAX_ENCODED or #data % 4 ~= 0 then
        return nil
    end
    local out = {}
    for i = 1, #data, 4 do
        local a, b, c, d = data:sub(i, i), data:sub(i + 1, i + 1), data:sub(i + 2, i + 2), data:sub(i + 3, i + 3)
        local p, q, r, s = reverse[a], reverse[b], reverse[c], reverse[d]
        if not p or not q or (c ~= "=" and not r) or (d ~= "=" and not s) then
            return nil
        end
        if (c == "=" or d == "=") and i ~= #data - 3 then
            return nil
        end
        if c == "=" and (d ~= "=" or q % 16 ~= 0) or d == "=" and c ~= "=" and r % 4 ~= 0 then
            return nil
        end
        local value = p * 262144 + q * 4096 + (r or 0) * 64 + (s or 0)
        out[#out + 1] = string.char(math.floor(value / 65536) % 256)
        if c ~= "=" then
            out[#out + 1] = string.char(math.floor(value / 256) % 256)
        end
        if d ~= "=" then
            out[#out + 1] = string.char(value % 256)
        end
    end
    return table.concat(out)
end

-- The same base64 the feature profiles use, for anything else that has to survive a chat
-- paste: a camera profile carries numbers, so it cannot go through EncodeProfile.
function Codec:EncodeText(text)
    return encode(text)
end

function Codec:DecodeText(data)
    return decode(data)
end

function Codec:EncodeProfile(name, values)
    if not self:ValidName(name) or not self:ValidateValues(values) then
        return nil, "invalid_profile"
    end
    local keys, lines = {}, { "RF1", name }
    for key in pairs(values) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        lines[#lines + 1] = key .. "=" .. (values[key] and "1" or "0")
    end
    return encode(table.concat(lines, "\n") .. "\n")
end

function Codec:DecodeProfile(data)
    local payload = decode(data)
    if not payload or payload:sub(-1) ~= "\n" then
        return nil, "invalid_encoding"
    end
    local version, name, body = payload:match("^([^\n]*)\n([^\n]*)\n(.*)$")
    if version ~= "RF1" or not self:ValidName(name) then
        return nil, "invalid_profile"
    end
    local values, count = {}, 0
    for line in body:gmatch("([^\n]*)\n") do
        count = count + 1
        local key, value = line:match("^([^=]+)=([01])$")
        if count > MAX_ENTRIES or not self:ValidID(key) or values[key] ~= nil then
            return nil, "invalid_profile"
        end
        values[key] = value == "1"
    end
    return { name = name, values = values }
end
