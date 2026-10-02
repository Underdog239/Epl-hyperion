-- EPL Hyperion - HyperionBase64
-- Reusable Base64 codec for share/import payloads.
-- Intended to be placed as a ModuleScript beside the main Hyperion client script.

local Base64 = {}

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local MAX_BYTES = 120000

local function validate(data)
    if type(data) ~= "string" then
        return false, "Base64 payload must be a string"
    end
    if #data > MAX_BYTES then
        return false, string.format("Base64 payload exceeds %d bytes", MAX_BYTES)
    end
    return true
end

function Base64.encode(data)
    local ok, err = validate(data)
    if not ok then
        error("[Hyperion Share] " .. err, 0)
    end

    local result = {}
    for i = 1, #data, 3 do
        local b1, b2, b3 = string.byte(data, i, i + 2)
        local n = (b1 or 0) * 65536 + (b2 or 0) * 256 + (b3 or 0)

        local c1 = math.floor(n / 262144) % 64 + 1
        local c2 = math.floor(n / 4096) % 64 + 1
        local c3 = math.floor(n / 64) % 64 + 1
        local c4 = n % 64 + 1

        result[#result + 1] = CHARS:sub(c1, c1)
        result[#result + 1] = CHARS:sub(c2, c2)
        result[#result + 1] = b2 and CHARS:sub(c3, c3) or "="
        result[#result + 1] = b3 and CHARS:sub(c4, c4) or "="
    end

    return table.concat(result)
end

function Base64.decode(data)
    local ok, err = validate(data)
    if not ok then
        return nil, err
    end
    if #data % 4 ~= 0 then
        return nil, "Invalid Base64 length"
    end
    if data:find("[^" .. CHARS .. "=]") then
        return nil, "Invalid Base64 character"
    end

    local firstPadding = data:find("=", 1, true)
    if firstPadding and firstPadding <= #data - 2 then
        return nil, "Invalid Base64 padding"
    end

    local lookup = {}
    for i = 1, #CHARS do
        lookup[CHARS:sub(i, i)] = i - 1
    end

    local bytes = {}
    for i = 1, #data, 4 do
        local c1 = lookup[data:sub(i, i)]
        local c2 = lookup[data:sub(i + 1, i + 1)]
        local c3c = data:sub(i + 2, i + 2)
        local c4c = data:sub(i + 3, i + 3)
        local c3 = lookup[c3c]
        local c4 = lookup[c4c]

        if not c1 or not c2 then
            return nil, "Invalid Base64 quartet"
        end
        if c3c == "=" and c4c ~= "=" then
            return nil, "Invalid Base64 padding"
        end

        local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        bytes[#bytes + 1] = string.char(math.floor(n / 65536) % 256)

        if c3c ~= "=" then
            bytes[#bytes + 1] = string.char(math.floor(n / 256) % 256)
        end
        if c4c ~= "=" then
            bytes[#bytes + 1] = string.char(n % 256)
        end
    end

    return table.concat(bytes)
end

return Base64
