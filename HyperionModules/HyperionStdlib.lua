-- HyperionStdlib — optional standard-library ModuleScript for EPL Hyperion.
-- Place this as a child of the main Hyperion LocalScript and name it
-- "HyperionStdlib"; Hyperion will require() it and expose it to every program
-- as the global `std`. If it is absent, Hyperion uses its own embedded copy.
--
-- Everything here is pure and side-effect free so it is safe inside the VM
-- sandbox (no io / os / loadstring / network).

local std = {}
std.VERSION = "1.0.0"

local function num(v) return tonumber(v) or 0 end
local function isTable(v) return type(v) == "table" end

std.math = {
    gcd = function(a, b)
        a, b = math.abs(math.floor(num(a))), math.abs(math.floor(num(b)))
        while b ~= 0 do a, b = b, a % b end
        return a
    end,
    lcm = function(a, b)
        a, b = math.abs(math.floor(num(a))), math.abs(math.floor(num(b)))
        if a == 0 or b == 0 then return 0 end
        local x, y = a, b
        while y ~= 0 do x, y = y, x % y end
        return math.floor(a / x) * b
    end,
    clamp = function(v, lo, hi)
        v, lo, hi = num(v), num(lo), num(hi)
        if lo > hi then lo, hi = hi, lo end
        if v < lo then return lo elseif v > hi then return hi else return v end
    end,
    round = function(v, places)
        local p = 10 ^ math.floor(num(places))
        if p <= 0 then return num(v) end
        return math.floor(num(v) * p + 0.5) / p
    end,
    sign = function(v)
        v = num(v)
        if v > 0 then return 1 elseif v < 0 then return -1 else return 0 end
    end,
    factorial = function(n)
        n = math.floor(num(n))
        if n < 0 then return 0 end
        local r = 1
        for i = 2, n do r = r * i end
        return r
    end,
    isPrime = function(n)
        n = math.floor(num(n))
        if n < 2 then return false end
        if n % 2 == 0 then return n == 2 end
        local i = 3
        while i * i <= n do
            if n % i == 0 then return false end
            i = i + 2
        end
        return true
    end,
    sum = function(t)
        if not isTable(t) then return 0 end
        local s = 0
        for _, v in ipairs(t) do s = s + num(v) end
        return s
    end,
    product = function(t)
        if not isTable(t) then return 0 end
        local s = 1
        for _, v in ipairs(t) do s = s * num(v) end
        return s
    end,
    average = function(t)
        if not isTable(t) or #t == 0 then return 0 end
        return std.math.sum(t) / #t
    end
}

std.list = {
    new = function(...) return { ... } end,
    push = function(t, v)
        if not isTable(t) then return t end
        table.insert(t, v)
        return t
    end,
    pop = function(t)
        if not isTable(t) or #t == 0 then return nil end
        return table.remove(t)
    end,
    map = function(t, fn)
        local out = {}
        if not isTable(t) or type(fn) ~= "function" then return out end
        for i, v in ipairs(t) do out[i] = fn(v) end
        return out
    end,
    filter = function(t, fn)
        local out = {}
        if not isTable(t) or type(fn) ~= "function" then return out end
        for _, v in ipairs(t) do if fn(v) then table.insert(out, v) end end
        return out
    end,
    reduce = function(t, fn, acc)
        if not isTable(t) or type(fn) ~= "function" then return acc end
        for _, v in ipairs(t) do acc = fn(acc, v) end
        return acc
    end,
    sort = function(t, cmp)
        if not isTable(t) then return t end
        table.sort(t, type(cmp) == "function" and cmp or nil)
        return t
    end,
    reverse = function(t)
        local out = {}
        if not isTable(t) then return out end
        for i = #t, 1, -1 do table.insert(out, t[i]) end
        return out
    end,
    contains = function(t, v)
        if not isTable(t) then return false end
        for _, x in ipairs(t) do if x == v then return true end end
        return false
    end,
    indexOf = function(t, v)
        if not isTable(t) then return -1 end
        for i, x in ipairs(t) do if x == v then return i end end
        return -1
    end,
    slice = function(t, from, to)
        local out = {}
        if not isTable(t) then return out end
        from = math.max(1, math.floor(num(from)))
        to = math.min(#t, math.floor(num(to)))
        for i = from, to do table.insert(out, t[i]) end
        return out
    end,
    join = function(t, sep)
        if not isTable(t) then return "" end
        local parts = {}
        for _, v in ipairs(t) do table.insert(parts, tostring(v)) end
        return table.concat(parts, sep == nil and "," or tostring(sep))
    end,
    sum = function(t) return std.math.sum(t) end,
    range = function(a, b, step)
        a, b = math.floor(num(a)), math.floor(num(b))
        step = math.floor(num(step))
        if step == 0 then step = 1 end
        local out = {}
        for i = a, b, step do table.insert(out, i) end
        return out
    end
}

std.string = {
    trim = function(s)
        s = tostring(s or "")
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end,
    split = function(s, sep)
        s = tostring(s or "")
        sep = sep == nil and "," or tostring(sep)
        local out = {}
        if sep == "" then
            for i = 1, #s do out[i] = s:sub(i, i) end
            return out
        end
        local pattern = "([^" .. sep:gsub("(%W)", "%%%1") .. "]+)"
        for part in s:gmatch(pattern) do table.insert(out, part) end
        if #s > 0 and s:sub(-#sep) == sep then table.insert(out, "") end
        return out
    end,
    join = function(t, sep) return std.list.join(t, sep) end,
    startsWith = function(s, prefix)
        s, prefix = tostring(s or ""), tostring(prefix or "")
        return s:sub(1, #prefix) == prefix
    end,
    endsWith = function(s, suffix)
        s, suffix = tostring(s or ""), tostring(suffix or "")
        if #suffix == 0 then return true end
        return s:sub(-#suffix) == suffix
    end,
    contains = function(s, needle)
        return tostring(s or ""):find(tostring(needle or ""), 1, true) ~= nil
    end,
    ["repeat"] = function(s, n)
        n = math.max(0, math.floor(num(n)))
        return string.rep(tostring(s or ""), n)
    end,
    capitalize = function(s)
        s = tostring(s or "")
        if #s == 0 then return s end
        return s:sub(1, 1):upper() .. s:sub(2)
    end,
    reverse = function(s) return tostring(s or ""):reverse() end,
    replace = function(s, from, to)
        s = tostring(s or "")
        from = tostring(from or "")
        to = tostring(to or "")
        if from == "" then return s end
        return (s:gsub(from:gsub("(%W)", "%%%1"), to:gsub("%%", "%%%%")))
    end,
    lines = function(s)
        local out = {}
        for line in (tostring(s or "") .. "\n"):gmatch("([^\n]*)\n") do table.insert(out, line) end
        return out
    end,
    padStart = function(s, len, ch)
        s = tostring(s or ""); ch = tostring(ch or " "); len = math.floor(num(len))
        while #s < len do s = ch .. s end
        return s
    end,
    padEnd = function(s, len, ch)
        s = tostring(s or ""); ch = tostring(ch or " "); len = math.floor(num(len))
        while #s < len do s = s .. ch end
        return s
    end
}

std.table = {
    keys = function(t)
        local out = {}
        if not isTable(t) then return out end
        for k in pairs(t) do table.insert(out, k) end
        return out
    end,
    values = function(t)
        local out = {}
        if not isTable(t) then return out end
        for _, v in pairs(t) do table.insert(out, v) end
        return out
    end,
    merge = function(a, b)
        local out = {}
        if isTable(a) then for k, v in pairs(a) do out[k] = v end end
        if isTable(b) then for k, v in pairs(b) do out[k] = v end end
        return out
    end,
    copy = function(t)
        local out = {}
        if isTable(t) then for k, v in pairs(t) do out[k] = v end end
        return out
    end,
    size = function(t)
        if not isTable(t) then return 0 end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end,
    isEmpty = function(t)
        if not isTable(t) then return true end
        return next(t) == nil
    end
}

std.util = {
    range = function(a, b, step) return std.list.range(a, b, step) end,
    identity = function(v) return v end,
    noop = function() end
}

return std

