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

-- RF2 carries a profile's settings as well as its switches, and settings nest. Each value is
-- a tag and its content: b1 or b0, n<number>; s<length>:<bytes>, t<count>: then that many
-- key and value pairs. Length prefixes mean no byte inside a string ever needs escaping, and
-- the reader below builds tables only, so nothing in a pasted string can run.
local MAX_DEPTH, MAX_NODES, MAX_STRING = 12, 4096, 4096

local function keyOrder(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
        return ta == "number"
    end
    return a < b
end

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function serialize(value, out, depth)
    local kind = type(value)
    if kind == "boolean" then
        out[#out + 1] = value and "b1" or "b0"
    elseif kind == "number" then
        if not finite(value) then
            return false
        end
        out[#out + 1] = "n" .. string.format("%.17g", value) .. ";"
    elseif kind == "string" then
        if #value > MAX_STRING then
            return false
        end
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif kind == "table" then
        if depth >= MAX_DEPTH then
            return false
        end
        local keys = {}
        for key in pairs(value) do
            local keyKind = type(key)
            if keyKind ~= "string" and (keyKind ~= "number" or not finite(key)) then
                return false
            end
            keys[#keys + 1] = key
        end
        table.sort(keys, keyOrder)
        out[#out + 1] = "t" .. #keys .. ":"
        for _, key in ipairs(keys) do
            if not serialize(key, out, depth + 1) or not serialize(value[key], out, depth + 1) then
                return false
            end
        end
    else
        return false
    end
    return true
end

-- Returns the value and the position after it, or nil and nil on anything malformed.
local function parse(data, position, depth, state)
    state.nodes = state.nodes + 1
    if state.nodes > MAX_NODES then
        return nil, nil
    end
    local tag = data:sub(position, position)
    if tag == "b" then
        local flag = data:sub(position + 1, position + 1)
        if flag == "1" or flag == "0" then
            return flag == "1", position + 2
        end
    elseif tag == "n" then
        local text, after = data:match("^([%-%+%d%.eE]+);()", position + 1)
        local number = text and tonumber(text)
        if number and finite(number) then
            return number, after
        end
    elseif tag == "s" then
        local length, start = data:match("^(%d+):()", position + 1)
        length = tonumber(length)
        if length and length <= MAX_STRING and start + length - 1 <= #data then
            return data:sub(start, start + length - 1), start + length
        end
    elseif tag == "t" and depth < MAX_DEPTH then
        local count, cursor = data:match("^(%d+):()", position + 1)
        count = tonumber(count)
        if not count or count > MAX_NODES then
            return nil, nil
        end
        local result = {}
        for _ = 1, count do
            local key, value
            key, cursor = parse(data, cursor, depth + 1, state)
            if not cursor or type(key) ~= "string" and type(key) ~= "number" or result[key] ~= nil then
                return nil, nil
            end
            value, cursor = parse(data, cursor, depth + 1, state)
            if not cursor then
                return nil, nil
            end
            result[key] = value
        end
        return result, cursor
    end
    return nil, nil
end

-- data is { modules = id to boolean, options = key to value }.
function Codec:EncodeProfileData(name, data)
    if not self:ValidName(name) or type(data) ~= "table" or not self:ValidateValues(data.modules or {}) then
        return nil, "invalid_profile"
    end
    local out = { "RF2\n", name, "\n" }
    if not serialize({ modules = data.modules or {}, options = data.options or {} }, out, 0) then
        return nil, "invalid_profile"
    end
    local encoded = encode(table.concat(out))
    if #encoded > MAX_ENCODED then
        return nil, "invalid_profile"
    end
    return encoded
end

local function decodeLegacy(self, name, body)
    if body:sub(-1) ~= "\n" and body ~= "" then
        return nil, "invalid_encoding"
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
    return { name = name, modules = values, options = {} }
end

-- Both formats come back as { name, modules, options }. An RF1 string from 0.1.0 has no
-- settings, so its options are empty and the importer fills them from the defaults.
function Codec:DecodeProfile(data)
    local payload = decode(data)
    if not payload then
        return nil, "invalid_encoding"
    end
    local version, name, body = payload:match("^([^\n]*)\n([^\n]*)\n(.*)$")
    if not self:ValidName(name) then
        return nil, "invalid_profile"
    end
    if version == "RF1" then
        return decodeLegacy(self, name, body)
    elseif version ~= "RF2" then
        return nil, "invalid_profile"
    end
    local value, after = parse(body, 1, 0, { nodes = 0 })
    if not after or after ~= #body + 1 or type(value) ~= "table" or type(value.modules) ~= "table"
        or type(value.options) ~= "table" or not self:ValidateValues(value.modules) then
        return nil, "invalid_profile"
    end
    return { name = name, modules = value.modules, options = value.options }
end
