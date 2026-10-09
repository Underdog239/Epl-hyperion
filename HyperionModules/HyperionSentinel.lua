-- HyperionSentinel — self-wiring, language-aware static analysis + a
-- conservative auto-patcher that runs continuously in the background.
--
-- Drop this in as a child ModuleScript of the main Hyperion LocalScript, named
-- "HyperionSentinel". Hyperion requires it, adds a Sentinel panel, and starts a
-- background loop that scans and auto-applies safe fixes without any button
-- press.
--
-- DESIGN CONTRACT (read before changing anything here):
--   * The Sentinel NEVER regenerates a file. Every fix is a small, span-based
--     text substitution over the developer's original source. If a span cannot
--     be located exactly, the fix is dropped.
--   * Only rules flagged `autoSafe = true` may ever be applied automatically.
--     Everything else is report-only.
--   * Every apply() run must pass the hard budget guards in DEFAULT_LIMITS.
--     If any guard trips, apply() returns nil + a reason and the caller keeps
--     the ORIGINAL source untouched. This is what stops it "optimising" a
--     6000-line script down to 500 lines.
--   * Language-aware: comment syntax, block closers and foldable operators are
--     driven by LANG_PROFILES, so EPL / Lua / Luau / English / Python /
--     C / C+ / C++ / Java / Bytecode are all handled correctly.
--   * Pure Lua: no Roblox APIs, no io, no loadstring.

local Sentinel = {}
Sentinel.VERSION = "2.0.0"

-- Absolute ceilings. The caller may LOWER the limits but never raise them.
Sentinel.ABSOLUTE_CEILINGS = {
    maxChangedLines     = 40,
    maxChangedPercent   = 5.0,
    maxNetDeletedLines  = 8,
    maxHunks            = 25,
    minRetainedFraction = 0.95,
    maxFileLines        = 20000,
    maxBlockCompletion  = 6,
}

Sentinel.DEFAULT_LIMITS = {
    maxChangedLines     = 25,
    maxChangedPercent   = 2.0,
    maxNetDeletedLines  = 5,
    maxHunks            = 20,
    minRetainedFraction = 0.98,
    maxFileLines        = 20000,
    maxBlockCompletion  = 4,
}

-- ---------------------------------------------------------------------------
-- Language profiles
-- ---------------------------------------------------------------------------
local LANG_PROFILES = {
    EPL      = { family = "lua",      lineComments = { "--" }, blockComments = { { "--[[", "]]" } }, foldOps = "+-*/%^", closer = "end", closerDiag = "end" },
    English  = { family = "lua",      lineComments = { "--" }, blockComments = { { "--[[", "]]" } }, foldOps = "+-*/%^", closer = "end", closerDiag = "end" },
    Lua      = { family = "lua",      lineComments = { "--" }, blockComments = { { "--[[", "]]" } }, foldOps = "+-*/%^", closer = "end", closerDiag = "end" },
    Luau     = { family = "lua",      lineComments = { "--" }, blockComments = { { "--[[", "]]" } }, foldOps = "+-*/%^", closer = "end", closerDiag = "end" },
    Python   = { family = "python",   lineComments = { "#" },  blockComments = {},                    foldOps = "+-*/%^", closer = nil,   closerDiag = nil },
    ["C"]    = { family = "c",        lineComments = { "//" }, blockComments = { { "/*", "*/" } },    foldOps = "+-*",    closer = "}",   closerDiag = "}" },
    ["C+"]   = { family = "c",        lineComments = { "//" }, blockComments = { { "/*", "*/" } },    foldOps = "+-*",    closer = "}",   closerDiag = "}" },
    ["C++"]  = { family = "c",        lineComments = { "//" }, blockComments = { { "/*", "*/" } },    foldOps = "+-*",    closer = "}",   closerDiag = "}" },
    Java     = { family = "c",        lineComments = { "//" }, blockComments = { { "/*", "*/" } },    foldOps = "+-*",    closer = "}",   closerDiag = "}" },
    Bytecode = { family = "bytecode", lineComments = { ";" },  blockComments = {},                    foldOps = "",       closer = nil,   closerDiag = nil },
}

local DEFAULT_PROFILE = LANG_PROFILES.EPL

function Sentinel.profile(lang)
    return LANG_PROFILES[lang] or DEFAULT_PROFILE
end

Sentinel.LANG_PROFILES = LANG_PROFILES

local function clampNumber(v, lo, hi)
    if type(v) ~= "number" then return lo end
    if v < lo then return lo elseif v > hi then return hi else return v end
end

function Sentinel.resolveLimits(overrides)
    local limits = {}
    for k, v in pairs(Sentinel.DEFAULT_LIMITS) do limits[k] = v end
    if type(overrides) == "table" then
        for k, v in pairs(overrides) do
            if limits[k] ~= nil and type(v) == "number" then limits[k] = v end
        end
    end
    local ceil = Sentinel.ABSOLUTE_CEILINGS
    limits.maxChangedLines     = clampNumber(limits.maxChangedLines, 1, ceil.maxChangedLines)
    limits.maxChangedPercent   = clampNumber(limits.maxChangedPercent, 0.1, ceil.maxChangedPercent)
    limits.maxNetDeletedLines  = clampNumber(limits.maxNetDeletedLines, 0, ceil.maxNetDeletedLines)
    limits.maxHunks            = clampNumber(limits.maxHunks, 1, ceil.maxHunks)
    limits.minRetainedFraction = clampNumber(limits.minRetainedFraction, ceil.minRetainedFraction, 1.0)
    limits.maxFileLines        = clampNumber(limits.maxFileLines, 1, ceil.maxFileLines)
    limits.maxBlockCompletion  = clampNumber(limits.maxBlockCompletion, 0, ceil.maxBlockCompletion)
    return limits
end

local function countLines(s)
    return 1 + select(2, (s or ""):gsub("\n", "\n"))
end

-- Replace strings and comments with spaces while preserving length and line
-- breaks. Language-aware: `--[[ ]]`, `--`, `#`, `//`, `/* */` and `;` are all
-- recognised according to the active profile, so span offsets always line up
-- with the original source and rules can never match inside a literal.
local function maskSource(src, lang)
    local profile = Sentinel.profile(lang)
    local lineComments = profile.lineComments or {}
    local blockComments = profile.blockComments or {}
    local out = {}
    local i, n = 1, #src
    local function put(ch) out[#out + 1] = ch end
    local function matchBlock(pos)
        for _, pair in ipairs(blockComments) do
            if src:sub(pos, pos + #pair[1] - 1) == pair[1] then return pair end
        end
        return nil
    end
    local function matchLine(pos)
        for _, prefix in ipairs(lineComments) do
            if src:sub(pos, pos + #prefix - 1) == prefix then return true end
        end
        return false
    end
    while i <= n do
        local c = src:sub(i, i)
        local block = matchBlock(i)
        if block then
            local close = src:find(block[2], i + #block[1], true)
            local stop = close and (close + #block[2] - 1) or n
            for k = i, stop do
                if src:sub(k, k) == "\n" then put("\n") else put(" ") end
            end
            i = stop + 1
        elseif matchLine(i) then
            while i <= n and src:sub(i, i) ~= "\n" do put(" "); i = i + 1 end
        elseif c == '"' or c == "'" then
            local quote = c
            put(" "); i = i + 1
            while i <= n do
                local ch = src:sub(i, i)
                if ch == "\\" then put(" "); put(" "); i = i + 2
                elseif ch == quote then put(" "); i = i + 1; break
                elseif ch == "\n" then break
                else put(" "); i = i + 1 end
            end
        else
            put(c); i = i + 1
        end
    end
    return table.concat(out)
end

Sentinel.maskSource = maskSource
Sentinel.countLines = countLines


-- ---------------------------------------------------------------------------
-- Language-aware numeric constant evaluator
-- ---------------------------------------------------------------------------
local function allowedCharSet(profile)
    local set = { ["."] = true, [" "] = true, ["("] = true, [")"] = true }
    for ch in (profile.foldOps or ""):gmatch(".") do set[ch] = true end
    for d = 0, 9 do set[tostring(d)] = true end
    return set
end

local function hasFoldOp(text, profile)
    local ops = profile.foldOps or ""
    for ch in text:gmatch(".") do
        if ch ~= "." and ops:find(ch, 1, true) then return true end
    end
    return false
end

-- Strict evaluator for *pure numeric literal* arithmetic. `ops` is the set of
-- operators the active language actually supports (e.g. C-family excludes `^`,
-- where `^` means XOR). Returns nil unless the whole string evaluates cleanly.
local function evalNumeric(expr, ops)
    ops = ops or "+-*/%^"
    local pos, n = 1, #expr
    local function skipWs()
        while pos <= n and expr:sub(pos, pos):match("%s") do pos = pos + 1 end
    end
    local function supported(op) return ops:find(op, 1, true) ~= nil end
    local parseExpr, parseTerm, parseFactor, parseUnary, parsePrimary
    parsePrimary = function()
        skipWs()
        local c = expr:sub(pos, pos)
        if c == "(" then
            pos = pos + 1
            local v = parseExpr()
            skipWs()
            if expr:sub(pos, pos) ~= ")" then return nil end
            pos = pos + 1
            return v
        end
        local s, e = expr:find("^%d+%.?%d*", pos)
        if not s then return nil end
        local num = tonumber(expr:sub(s, e))
        if num == nil then return nil end
        pos = e + 1
        return num
    end
    parseUnary = function()
        skipWs()
        if expr:sub(pos, pos) == "-" then
            pos = pos + 1
            local v = parseUnary()
            if v == nil then return nil end
            return -v
        end
        return parsePrimary()
    end
    parseFactor = function()
        local base = parseUnary()
        if base == nil then return nil end
        skipWs()
        if expr:sub(pos, pos) == "^" then
            if not supported("^") then return nil end
            pos = pos + 1
            local exp = parseFactor() -- right associative
            if exp == nil then return nil end
            return base ^ exp
        end
        return base
    end
    parseTerm = function()
        local left = parseFactor()
        if left == nil then return nil end
        while true do
            skipWs()
            local op = expr:sub(pos, pos)
            if op == "*" or op == "/" or op == "%" then
                if not supported(op) then return nil end
                pos = pos + 1
                local right = parseFactor()
                if right == nil then return nil end
                if op == "*" then left = left * right
                elseif op == "/" then if right == 0 then return nil end left = left / right
                else if right == 0 then return nil end left = left % right end
            else
                break
            end
        end
        return left
    end
    parseExpr = function()
        local left = parseTerm()
        if left == nil then return nil end
        while true do
            skipWs()
            local op = expr:sub(pos, pos)
            if op == "+" or op == "-" then
                if not supported(op) then return nil end
                pos = pos + 1
                local right = parseTerm()
                if right == nil then return nil end
                if op == "+" then left = left + right else left = left - right end
            else
                break
            end
        end
        return left
    end
    local value = parseExpr()
    skipWs()
    if pos <= n then return nil end
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

Sentinel.evalNumeric = evalNumeric


-- ---------------------------------------------------------------------------
-- Rules. Each returns findings:
--   { rule, severity, autoSafe, message, start, finish, replacement, line }
-- start/finish are 1-based inclusive byte offsets into the ORIGINAL source.
-- A finding with autoSafe=true and a `replacement` becomes an applicable patch.
-- Every rule is language-aware via Sentinel.profile(lang).
-- ---------------------------------------------------------------------------
local RULES = {}

local function eachLine(text, fn)
    local pos, lineNo = 1, 1
    while true do
        local nl = text:find("\n", pos, true)
        local stop = nl and (nl - 1) or #text
        fn(lineNo, text:sub(pos, stop), pos)
        if not nl then break end
        pos = nl + 1
        lineNo = lineNo + 1
    end
end

-- Trailing whitespace (auto-safe, cosmetic, every language).
RULES.trailingWhitespace = function(src)
    local findings = {}
    local lineNo = 1
    local pos = 1
    while true do
        local nl = src:find("\n", pos, true)
        local stop = nl and (nl - 1) or #src
        local line = src:sub(pos, stop)
        local stripped = line:gsub("[ \t]+$", "")
        if #stripped ~= #line then
            findings[#findings + 1] = {
                rule = "SEN-WS-001", severity = "INFO", autoSafe = true,
                message = string.format("Trailing whitespace on line %d", lineNo),
                line = lineNo, start = pos + #stripped, finish = stop, replacement = "",
            }
        end
        if not nl then break end
        pos = nl + 1
        lineNo = lineNo + 1
    end
    return findings
end

-- Missing final newline (auto-safe, cosmetic, every language).
RULES.finalNewline = function(src)
    if #src == 0 or src:sub(-1) == "\n" then return {} end
    return { {
        rule = "SEN-WS-003", severity = "INFO", autoSafe = true,
        message = "File does not end with a newline",
        start = #src + 1, finish = #src, replacement = "\n",
    } }
end

-- Numeric constant folding. Conservative: only folds spans that are *entirely*
-- numeric literal arithmetic using operators the language actually supports,
-- produce a finite integer, and are not adjacent to an identifier character
-- (so `x1 + 2` is never touched). Division/modulo that is not exact yields a
-- non-integer and is therefore never folded, which keeps C-family integer
-- division safe.
RULES.constantFolding = function(src, lang)
    local profile = Sentinel.profile(lang)
    if (profile.foldOps or "") == "" then return {} end
    local masked = maskSource(src, lang)
    local allowed = allowedCharSet(profile)
    local findings = {}
    local i, n = 1, #masked
    while i <= n do
        local c = masked:sub(i, i)
        if c:match("[%d%(]") then
            local before = (i > 1) and masked:sub(i - 1, i - 1) or ""
            if not (before:match("[%w_]") or before == ".") then
                local e = i
                local limit = math.min(n, i + 160)
                while e < limit and allowed[masked:sub(e + 1, e + 1)] do
                    e = e + 1
                end
                while e > i and masked:sub(e, e) == " " do e = e - 1 end
                local candidate = masked:sub(i, e)
                local after = masked:sub(e + 1, e + 1)
                if #candidate > 0 and hasFoldOp(candidate, profile)
                    and not (after:match("[%w_]") or after == ".") then
                    local value = evalNumeric(candidate, profile.foldOps)
                    if value and value == math.floor(value) and math.abs(value) < 1e15 then
                        local replacement = tostring(math.floor(value))
                        if replacement ~= candidate then
                            findings[#findings + 1] = {
                                rule = "SEN-OPT-001", severity = "INFO", autoSafe = true,
                                message = string.format("Constant expression '%s' on line %d folds to %s",
                                    candidate, countLines(src:sub(1, i - 1)), replacement),
                                line = countLines(src:sub(1, i - 1)),
                                start = i, finish = e, replacement = replacement,
                            }
                        end
                    end
                end
                i = e + 1
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return findings
end


-- `a and b or c` — the classic false/nil-swallowing ternary. Lua-family and
-- Python only (C-family uses `?:`). Report only: the correct rewrite depends on
-- the intended types.
RULES.andOrTernary = function(src, lang)
    local profile = Sentinel.profile(lang)
    if profile.family == "c" or profile.family == "bytecode" then return {} end
    local masked = maskSource(src, lang)
    local findings = {}
    eachLine(masked, function(lineNo, line, offset)
        if line:find(" and ") and line:find(" or ") then
            findings[#findings + 1] = {
                rule = "SEN-LOGIC-001", severity = "WARNING", autoSafe = false,
                message = string.format("'and/or' ternary on line %d can mis-handle a false/nil middle value", lineNo),
                line = lineNo, start = offset, finish = offset,
            }
        end
    end)
    return findings
end

-- Literal division / modulo by zero (report only, every language).
RULES.divByZero = function(src, lang)
    local masked = maskSource(src, lang)
    local findings = {}
    eachLine(masked, function(lineNo, line, offset)
        if line:find("[%/%%]%s*0[^%d%.]") or line:match("[%/%%]%s*0%s*$") then
            findings[#findings + 1] = {
                rule = "SEN-MATH-002", severity = "ERROR", autoSafe = false,
                message = string.format("Literal division/modulo by zero on line %d", lineNo),
                line = lineNo, start = offset, finish = offset,
            }
        end
    end)
    return findings
end

-- string.rep with an enormous literal count (allocation guard). Lua-family and
-- Python only, since `string.rep` is a Lua/Python-library construct.
RULES.hugeRepeat = function(src, lang)
    local profile = Sentinel.profile(lang)
    if profile.family == "c" or profile.family == "bytecode" then return {} end
    local masked = maskSource(src, lang)
    local findings = {}
    eachLine(masked, function(lineNo, line, offset)
        for count in line:gmatch("string%.rep%s*%(%s*[^,]-,%s*(%d%d%d%d%d%d%d+)") do
            findings[#findings + 1] = {
                rule = "SEN-DOS-003", severity = "ERROR", autoSafe = false,
                message = string.format("string.rep count %s on line %d is very large", count, lineNo),
                line = lineNo, start = offset, finish = offset,
            }
        end
    end)
    return findings
end

-- `while true` / `while (true)` / `while True:` with no yield/wait nearby.
RULES.whileTrueNoYield = function(src, lang)
    local profile = Sentinel.profile(lang)
    if profile.family == "bytecode" then return {} end
    local masked = maskSource(src, lang)
    local lines = {}
    eachLine(masked, function(lineNo, line) lines[lineNo] = line end)
    local findings = {}
    for lineNo, line in pairs(lines) do
        local isForever = line:find("while%s+true%s+do")
            or line:find("while%s*%(?%s*true%s*%)?%s*:")
            or line:find("while%s*%(?%s*true%s*%)?%s*{")
            or line:find("while%s*%(?%s*1%s*%)?%s*{")
        if isForever then
            local guarded = false
            for k = lineNo, math.min(lineNo + 12, #lines) do
                local probe = lines[k] or ""
                if probe:find("wait") or probe:find("task%.") or probe:find("yield")
                    or probe:find("sleep") or probe:find("break") or probe:find("return") then
                    guarded = true
                    break
                end
            end
            if not guarded then
                findings[#findings + 1] = {
                    rule = "SEN-LOOP-004", severity = "WARNING", autoSafe = false,
                    message = string.format("'while true' on line %d has no visible wait/yield/break", lineNo),
                    line = lineNo,
                }
            end
        end
    end
    return findings
end


-- Unfinished code: when the host parser reports that a block closer is missing
-- at end-of-file ("Expected 'end', got ''"), the file is genuinely truncated.
-- We can then safely append the missing closers. Language-aware via the profile
-- closer (`end` for Lua-family, `}` for C-family). Capped so a badly broken file
-- is reported rather than "fixed".
RULES.unfinishedBlocks = function(src, lang, ctx)
    local profile = Sentinel.profile(lang)
    if not profile.closer or not profile.closerDiag then return {} end
    local diagnostics = (ctx and ctx.diagnostics) or {}
    local pattern = "Expected '" .. profile.closerDiag .. "', got ''"
    local missing = 0
    for _, d in ipairs(diagnostics) do
        if type(d.message) == "string" and d.message:find(pattern, 1, true) then
            missing = missing + 1
        end
    end
    if missing == 0 then return {} end
    local cap = (ctx and ctx.limits and ctx.limits.maxBlockCompletion) or 4
    if missing > cap then
        return { {
            rule = "SEN-UNFIN-005", severity = "WARNING", autoSafe = false,
            message = string.format("%d unclosed block(s) detected - too many to complete automatically", missing),
            line = countLines(src),
        } }
    end
    local suffix = ""
    for _ = 1, missing do suffix = suffix .. profile.closer .. "\n" end
    return { {
        rule = "SEN-UNFIN-005", severity = "WARNING", autoSafe = true,
        message = string.format("File is missing %d closing '%s' - completing it", missing, profile.closer),
        line = countLines(src),
        start = #src + 1, finish = #src, replacement = "\n" .. suffix,
    } }
end

-- Unbalanced brackets (report only, every language) - catches truncation the
-- parser diagnostics may not describe.
RULES.unbalancedBrackets = function(src, lang)
    local masked = maskSource(src, lang)
    local round, square, curly = 0, 0, 0
    for i = 1, #masked do
        local c = masked:sub(i, i)
        if c == "(" then round = round + 1
        elseif c == ")" then round = round - 1
        elseif c == "[" then square = square + 1
        elseif c == "]" then square = square - 1
        elseif c == "{" then curly = curly + 1
        elseif c == "}" then curly = curly - 1 end
    end
    local findings = {}
    local function add(msg)
        findings[#findings + 1] = {
            rule = "SEN-UNFIN-006", severity = "WARNING", autoSafe = false,
            message = msg, line = countLines(src),
        }
    end
    if round > 0 then add(string.format("%d unclosed '(' - the file looks unfinished", round)) end
    if square > 0 then add(string.format("%d unclosed '[' - the file looks unfinished", square)) end
    if curly > 0 and Sentinel.profile(lang).family ~= "c" then
        add(string.format("%d unclosed '{' - the file looks unfinished", curly))
    end
    return findings
end

-- Complexity / structure metrics (report only). One INFO finding with a summary
-- so the Sentinel panel doubles as a small metrics view.
RULES.complexity = function(src, lang)
    local profile = Sentinel.profile(lang)
    local masked = maskSource(src, lang)
    local lines = 0
    local maxIndent = 0
    local branches = 0
    local functions = 0
    eachLine(masked, function(_, line)
        lines = lines + 1
        local indent = #(line:match("^[ \t]*") or "")
        if indent > maxIndent then maxIndent = indent end
    end)
    for _ in masked:gmatch("%f[%a]function%f[%A]") do functions = functions + 1 end
    for _ in masked:gmatch("%f[%a]def%f[%A]") do functions = functions + 1 end
    for _, word in ipairs({ "if", "elseif", "elif", "else", "while", "for", "case", "and", "or" }) do
        for _ in masked:gmatch("%f[%a]" .. word .. "%f[%A]") do branches = branches + 1 end
    end
    local depth = math.floor(maxIndent / 4)
    local cyclomatic = branches + 1
    return { {
        rule = "SEN-METRIC-001", severity = "INFO", autoSafe = false,
        message = string.format("Metrics: %d lines, %d function(s), ~%d branch(es), cyclomatic ~%d, max nesting ~%d (%s)",
            lines, functions, branches, cyclomatic, depth, profile.family),
        line = 1,
    } }
end


-- Performance hints (report only): long lines, deep nesting and string
-- concatenation accumulated inside a loop body.
RULES.perfHints = function(src, lang)
    local profile = Sentinel.profile(lang)
    local masked = maskSource(src, lang)
    local findings = {}
    local lines = {}
    eachLine(masked, function(lineNo, line) lines[lineNo] = line end)
    local concatOp = (profile.family == "lua") and "%.%." or "+"
    for lineNo = 1, #lines do
        local line = lines[lineNo]
        if #line > 160 then
            findings[#findings + 1] = {
                rule = "SEN-PERF-001", severity = "INFO", autoSafe = false,
                message = string.format("Line %d is %d characters long - consider splitting it", lineNo, #line),
                line = lineNo,
            }
        end
        local indent = #(line:match("^[ \t]*") or "")
        if indent >= 20 then
            findings[#findings + 1] = {
                rule = "SEN-PERF-002", severity = "INFO", autoSafe = false,
                message = string.format("Line %d is deeply nested (indent %d) - consider extracting a function", lineNo, indent),
                line = lineNo,
            }
        end
        local isLoop = line:find("for%s") or line:find("while%s")
        if isLoop then
            for k = lineNo + 1, math.min(lineNo + 15, #lines) do
                local body = lines[k] or ""
                if body:find(concatOp) then
                    findings[#findings + 1] = {
                        rule = "SEN-PERF-003", severity = "WARNING", autoSafe = false,
                        message = string.format("String concatenation inside the loop starting on line %d (line %d) - consider collecting into a table/list", lineNo, k),
                        line = k,
                    }
                    break
                end
            end
        end
    end
    return findings
end

Sentinel.RULES = RULES

-- Run every rule (plus any host diagnostics) and return the findings list.
-- opts = { hostDiagnostics = function(source, lang) -> list, limits = {...} }
function Sentinel.scan(source, lang, opts)
    opts = opts or {}
    local ctx = { limits = Sentinel.resolveLimits(opts.limits), diagnostics = {} }
    if type(opts.hostDiagnostics) == "function" then
        local ok, hostList = pcall(opts.hostDiagnostics, source, lang)
        if ok and type(hostList) == "table" then ctx.diagnostics = hostList end
    end
    local findings = {}
    if type(source) ~= "string" then return findings end
    for _, rule in pairs(RULES) do
        local ok, produced = pcall(rule, source, lang, ctx)
        if ok and type(produced) == "table" then
            for _, f in ipairs(produced) do findings[#findings + 1] = f end
        end
    end
    for _, d in ipairs(ctx.diagnostics) do
        findings[#findings + 1] = {
            rule = d.code or "SEN-HOST-000",
            severity = d.severity or "WARNING",
            autoSafe = false,
            message = d.message or "host diagnostic",
            line = d.line,
        }
    end
    return findings
end


-- ---------------------------------------------------------------------------
-- Patch layer + the hard safety guards
-- ---------------------------------------------------------------------------

-- Keep only findings that are safe to auto-apply and carry a concrete span.
function Sentinel.collectPatches(findings)
    local patches = {}
    for _, f in ipairs(findings or {}) do
        if f.autoSafe and type(f.replacement) == "string"
            and type(f.start) == "number" and type(f.finish) == "number"
            and f.finish >= f.start - 1 then
            patches[#patches + 1] = {
                rule = f.rule, start = f.start, finish = f.finish,
                replacement = f.replacement, message = f.message,
            }
        end
    end
    table.sort(patches, function(a, b)
        if a.start == b.start then return a.finish < b.finish end
        return a.start < b.start
    end)
    return patches
end

local function lineDelta(text)
    return select(2, (text or ""):gsub("\n", "\n"))
end

function Sentinel.diffStats(src, patches)
    local stats = { hunks = 0, added = 0, removed = 0, netDeleted = 0, overlapping = false }
    local lastFinish = -1
    for _, p in ipairs(patches) do
        stats.hunks = stats.hunks + 1
        local removedSpan = src:sub(p.start, math.max(p.start - 1, p.finish))
        stats.removed = stats.removed + lineDelta(removedSpan)
        stats.added = stats.added + lineDelta(p.replacement)
        if p.start <= lastFinish then stats.overlapping = true end
        lastFinish = math.max(lastFinish, p.finish)
    end
    stats.netDeleted = stats.removed - stats.added
    return stats
end

-- Apply span replacements from last to first so offsets stay valid. This is the
-- ONLY way the Sentinel ever produces new source: it never regenerates a file.
function Sentinel.applyPatches(src, patches)
    local ordered = {}
    for _, p in ipairs(patches) do ordered[#ordered + 1] = p end
    table.sort(ordered, function(a, b) return a.start > b.start end)
    local out = src
    for _, p in ipairs(ordered) do
        local head = out:sub(1, p.start - 1)
        local tail = out:sub(math.max(p.start, p.finish + 1))
        out = head .. p.replacement .. tail
    end
    return out
end

-- Propose auto-safe patches for a source buffer (never mutates anything).
function Sentinel.proposeFixes(source, lang, opts)
    local findings = Sentinel.scan(source, lang, opts)
    return Sentinel.collectPatches(findings), findings
end


-- The gate. Returns newSource, stats on success; nil, reason on refusal.
function Sentinel.apply(source, lang, patches, opts)
    opts = opts or {}
    local limits = Sentinel.resolveLimits(opts.limits)
    if type(source) ~= "string" then return nil, "no source" end
    if type(patches) ~= "table" or #patches == 0 then return nil, "nothing to apply" end

    local fileLines = countLines(source)
    if fileLines > limits.maxFileLines then
        return nil, string.format("file too large to patch safely (%d lines > %d)", fileLines, limits.maxFileLines)
    end

    local stats = Sentinel.diffStats(source, patches)
    if stats.overlapping then return nil, "refused: patches overlap" end
    if stats.hunks > limits.maxHunks then
        return nil, string.format("refused: %d edits exceeds the %d-edit budget", stats.hunks, limits.maxHunks)
    end

    local changedLines = stats.added + stats.removed
    local percentCap = math.max(10, math.floor(fileLines * limits.maxChangedPercent / 100))
    local lineCap = math.min(limits.maxChangedLines, percentCap)
    if changedLines > lineCap then
        return nil, string.format("refused: %d changed lines exceeds the %d-line budget", changedLines, lineCap)
    end
    if stats.netDeleted > limits.maxNetDeletedLines then
        return nil, string.format("refused: would net-remove %d lines (limit %d)", stats.netDeleted, limits.maxNetDeletedLines)
    end

    local newSource = Sentinel.applyPatches(source, patches)
    local removedBytes = #source - #newSource
    local allowedBytes = math.max(64, #source * (1.0 - limits.minRetainedFraction))
    if removedBytes > allowedBytes then
        return nil, string.format("refused: result removes %d bytes (limit %d, %.1f%% retained)",
            removedBytes, math.floor(allowedBytes), (#newSource / math.max(1, #source)) * 100)
    end
    if type(opts.parseFn) == "function" then
        local okParse, parsed = pcall(opts.parseFn, newSource, lang)
        if not okParse or not parsed then
            return nil, "refused: patched result does not parse"
        end
    end

    stats.retainedPercent = (#newSource / math.max(1, #source)) * 100
    return newSource, stats
end

function Sentinel.autoFix(source, lang, opts)
    local patches = Sentinel.proposeFixes(source, lang, opts)
    if #patches == 0 then return nil, "no auto-safe fixes found" end
    return Sentinel.apply(source, lang, patches, opts)
end

-- 0-100 health score derived from the findings, for the panel/status badge.
function Sentinel.health(findings)
    local score = 100
    for _, f in ipairs(findings or {}) do
        local rule = tostring(f.rule or "")
        if not rule:find("SEN-METRIC") then
            if f.severity == "ERROR" then score = score - 12
            elseif f.severity == "WARNING" then score = score - 5
            elseif f.severity == "INFO" then score = score - 1 end
        end
    end
    if score < 0 then score = 0 end
    return score
end

function Sentinel.summaryText(findings)
    local counts, autoSafe = {}, 0
    for _, f in ipairs(findings or {}) do
        counts[f.severity or "INFO"] = (counts[f.severity or "INFO"] or 0) + 1
        if f.autoSafe then autoSafe = autoSafe + 1 end
    end
    return string.format("health %d/100 - %d finding(s) (%d error, %d warning, %d info) - %d auto-safe",
        Sentinel.health(findings), #(findings or {}),
        counts.ERROR or 0, counts.WARNING or 0, counts.INFO or 0, autoSafe)
end

return Sentinel

