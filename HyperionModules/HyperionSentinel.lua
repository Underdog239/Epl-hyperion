-- HyperionSentinel — self-wiring static analysis + conservative auto-patcher.
--
-- Drop this in as a child ModuleScript of the main Hyperion LocalScript, named
-- "HyperionSentinel". Hyperion requires it and wires it into the IDE (Sentinel
-- toolbar button + background scan loop).
--
-- DESIGN CONTRACT (read before changing anything here):
--   * The Sentinel NEVER regenerates a file. Every fix is a small, span-based
--     text substitution over the developer's original source. If a span cannot
--     be located exactly, the fix is dropped.
--   * Only rules flagged `autoSafe = true` may ever be applied automatically.
--     Everything else is report-only and requires the developer to act.
--   * Every apply() run must pass the hard budget guards in DEFAULT_LIMITS.
--     If any guard trips, apply() returns nil + a reason and the caller keeps
--     the ORIGINAL source untouched. This is what stops it "optimising" a
--     6000-line script down to 500 lines.
--   * The module is pure Lua: no Roblox APIs, no io, no loadstring.

local Sentinel = {}
Sentinel.VERSION = "1.0.0"

-- Absolute ceilings. The caller may LOWER the limits but never raise them past
-- these values.
Sentinel.ABSOLUTE_CEILINGS = {
    maxChangedLines     = 40,
    maxChangedPercent   = 5.0,
    maxNetDeletedLines  = 8,
    maxHunks            = 25,
    minRetainedFraction = 0.95,
    maxFileLines        = 20000,
}

Sentinel.DEFAULT_LIMITS = {
    maxChangedLines     = 25,    -- absolute cap on added + removed lines
    maxChangedPercent   = 2.0,   -- ... and at most this % of the file
    maxNetDeletedLines  = 5,     -- never net-remove more than this many lines
    maxHunks            = 20,    -- distinct edited regions
    minRetainedFraction = 0.98,  -- refuse if the result shrinks below 98%
    maxFileLines        = 20000, -- don't attempt gigantic files
}

local function clampNumber(v, lo, hi)
    if type(v) ~= "number" then return lo end
    if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Merge caller limits with the defaults, clamped so they can only ever be made
-- stricter than the absolute ceilings.
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
    return limits
end

local function countLines(s)
    return 1 + select(2, (s or ""):gsub("\n", "\n"))
end

-- Replace strings and comments with spaces while preserving length and line
-- breaks, so text rules can never match inside a literal/comment and span
-- offsets still line up with the original source.
local function maskSource(src)
    local out = {}
    local i, n = 1, #src
    local function put(ch) out[#out + 1] = ch end
    while i <= n do
        local c = src:sub(i, i)
        local c2 = src:sub(i + 1, i + 1)
        if c == "-" and c2 == "-" then
            if src:sub(i + 2, i + 3) == "[[" then
                local close = src:find("]]", i + 4, true)
                local stop = close and (close + 1) or n
                for k = i, stop do
                    if src:sub(k, k) == "\n" then put("\n") else put(" ") end
                end
                i = stop + 1
            else
                while i <= n and src:sub(i, i) ~= "\n" do put(" "); i = i + 1 end
            end
        elseif c == "#" then
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

-- A tiny, strict evaluator for *pure numeric literal* arithmetic. Returns nil
-- unless the whole string is numbers/operators/parens that evaluate cleanly.
local function evalNumeric(expr)
    local pos, n = 1, #expr
    local function skipWs()
        while pos <= n and expr:sub(pos, pos):match("%s") do pos = pos + 1 end
    end
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
-- Rules. Each rule returns a list of findings:
--   { rule, severity, autoSafe, message, start, finish, replacement }
-- start/finish are 1-based inclusive byte offsets into the ORIGINAL source.
-- A finding with autoSafe=true and a `replacement` becomes an applicable patch.
-- ---------------------------------------------------------------------------

local RULES = {}

-- Trailing whitespace (safe, cosmetic).
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
                start = pos + #stripped, finish = stop, replacement = "",
            }
        end
        if not nl then break end
        pos = nl + 1
        lineNo = lineNo + 1
    end
    return findings
end

-- Missing final newline (safe, cosmetic).
RULES.finalNewline = function(src)
    if #src == 0 or src:sub(-1) == "\n" then return {} end
    return { {
        rule = "SEN-WS-003", severity = "INFO", autoSafe = true,
        message = "File does not end with a newline",
        start = #src + 1, finish = #src, replacement = "\n",
    } }
end

-- Numeric constant folding. Conservative: only folds spans that are *entirely*
-- numeric literal arithmetic, produce a finite integer, and are not adjacent to
-- an identifier character (so `x1 + 2` is never touched).
RULES.constantFolding = function(src)
    local masked = maskSource(src)
    local findings = {}
    local i, n = 1, #masked
    local allowed = "[%d%.%+%-%*/%%%^%(%) ]"
    while i <= n do
        local c = masked:sub(i, i)
        if c:match("[%d%(]") then
            local before = (i > 1) and masked:sub(i - 1, i - 1) or ""
            if not (before:match("[%w_]") or before == ".") then
                local e = i
                local limit = math.min(n, i + 160)
                while e < limit and masked:sub(e + 1, e + 1):match(allowed) do
                    e = e + 1
                end
                while e > i and masked:sub(e, e) == " " do e = e - 1 end
                local candidate = masked:sub(i, e)
                local after = masked:sub(e + 1, e + 1)
                if #candidate > 0 and candidate:find("[%+%-%*/%%%^]")
                    and not (after:match("[%w_]") or after == ".") then
                    local value = evalNumeric(candidate)
                    if value and value == math.floor(value) and math.abs(value) < 1e15 then
                        local replacement = tostring(math.floor(value))
                        if replacement ~= candidate then
                            findings[#findings + 1] = {
                                rule = "SEN-OPT-001", severity = "INFO", autoSafe = true,
                                message = string.format("Constant expression '%s' on line %d folds to %s",
                                    candidate, countLines(src:sub(1, i - 1)), replacement),
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

local function lineOf(src, offset)
    return countLines(src:sub(1, math.max(0, offset - 1)))
end

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

-- `a and b or c` — the classic false/nil-swallowing ternary (report only; the
-- correct rewrite depends on the intended types, so it is never auto-applied).
RULES.andOrTernary = function(src)
    local masked = maskSource(src)
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

-- Literal division / modulo by zero (report only: the intent is unclear).
RULES.divByZero = function(src)
    local masked = maskSource(src)
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

-- string.rep with an enormous literal count (allocation guard).
RULES.hugeRepeat = function(src)
    local masked = maskSource(src)
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


-- `while true` with no yield/wait in the loop body (watchdog risk).
RULES.whileTrueNoYield = function(src)
    local masked = maskSource(src)
    local lines = {}
    eachLine(masked, function(lineNo, line) lines[lineNo] = line end)
    local findings = {}
    for lineNo, line in pairs(lines) do
        if line:find("while%s+true%s+do") then
            local guarded = false
            for k = lineNo, math.min(lineNo + 12, #lines) do
                local probe = lines[k] or ""
                if probe:find("wait") or probe:find("task%.") or probe:find("yield") then
                    guarded = true
                    break
                end
            end
            if not guarded then
                findings[#findings + 1] = {
                    rule = "SEN-LOOP-004", severity = "WARNING", autoSafe = false,
                    message = string.format("'while true' on line %d has no visible wait/yield", lineNo),
                    line = lineNo,
                }
            end
        end
    end
    return findings
end

-- Unbalanced brackets: "unfinished code" detector.
RULES.unfinished = function(src)
    local masked = maskSource(src)
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
            rule = "SEN-UNFIN-005", severity = "WARNING", autoSafe = false,
            message = msg, line = countLines(src),
        }
    end
    if round > 0 then add(string.format("%d unclosed '(' - the file looks unfinished", round)) end
    if square > 0 then add(string.format("%d unclosed '[' - the file looks unfinished", square)) end
    if curly > 0 then add(string.format("%d unclosed '{' - the file looks unfinished", curly)) end
    return findings
end

Sentinel.RULES = RULES

-- Run every rule (plus any host diagnostics) and return the findings list.
-- opts = { hostDiagnostics = function(source, lang) -> list }
function Sentinel.scan(source, lang, opts)
    opts = opts or {}
    local findings = {}
    if type(source) ~= "string" then return findings end
    for _, rule in pairs(RULES) do
        local ok, produced = pcall(rule, source, lang)
        if ok and type(produced) == "table" then
            for _, f in ipairs(produced) do findings[#findings + 1] = f end
        end
    end
    if type(opts.hostDiagnostics) == "function" then
        local ok, hostList = pcall(opts.hostDiagnostics, source, lang)
        if ok and type(hostList) == "table" then
            for _, d in ipairs(hostList) do
                findings[#findings + 1] = {
                    rule = d.code or "SEN-HOST-000",
                    severity = d.severity or "WARNING",
                    autoSafe = false,
                    message = d.message or "host diagnostic",
                    line = d.line,
                }
            end
        end
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

-- Count how many lines a patch adds/removes (by newline content).
local function lineDelta(text)
    return select(2, text:gsub("\n", "\n"))
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

-- Apply span replacements from last to first so offsets stay valid. This is
-- the ONLY way the Sentinel ever produces new source: it never regenerates.
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
    local percentCap = math.max(1, math.floor(fileLines * limits.maxChangedPercent / 100))
    local lineCap = math.min(limits.maxChangedLines, percentCap)
    if changedLines > lineCap then
        return nil, string.format("refused: %d changed lines exceeds the %d-line budget", changedLines, lineCap)
    end
    if stats.netDeleted > limits.maxNetDeletedLines then
        return nil, string.format("refused: would net-remove %d lines (limit %d)", stats.netDeleted, limits.maxNetDeletedLines)
    end

    local newSource = Sentinel.applyPatches(source, patches)
    -- Shrink guard: small fixes always pass (a 64-byte floor), but a result that
    -- loses a large fraction of the file is refused outright. This is the second
    -- net that stops a runaway "optimiser" collapsing a big script.
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

-- One-shot convenience: propose + apply. Returns nil, reason if nothing safe
-- or if any guard refuses. The caller must treat nil as "keep the original".
function Sentinel.autoFix(source, lang, opts)
    local patches = Sentinel.proposeFixes(source, lang, opts)
    if #patches == 0 then return nil, "no auto-safe fixes found" end
    return Sentinel.apply(source, lang, patches, opts)
end

function Sentinel.summaryText(findings)
    local counts, autoSafe = {}, 0
    for _, f in ipairs(findings or {}) do
        counts[f.severity or "INFO"] = (counts[f.severity or "INFO"] or 0) + 1
        if f.autoSafe then autoSafe = autoSafe + 1 end
    end
    return string.format("%d finding(s) (%d error, %d warning, %d info) - %d auto-safe",
        #(findings or {}),
        counts.ERROR or 0, counts.WARNING or 0, counts.INFO or 0, autoSafe)
end

return Sentinel

