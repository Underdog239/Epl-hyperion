-- EPL Hyperion 3.0.0 - single LocalScript
-- Subtitle: Debugger & IDE Edition
-- Place in StarterPlayer > StarterPlayerScripts
-- Fully client-side and self-contained: no server, no remotes, no DataStore.
-- Client-side IDE, compiler, VM sandbox, translator & step debugger.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local player = Players.LocalPlayer

-- ============================================================================
-- 1. HARDENED CONFIGURATION & RESOURCE LIMITS
-- ============================================================================
local CONFIG = {
    VERSION               = "3.0.0",
    SUBTITLE              = "Polyglot Compiler & IDE Edition",
    MAX_SOURCE_BYTES      = 100000,   -- 100 KB max source code
    MAX_TOKEN_COUNT       = 20000,    -- 20,000 tokens limit
    MAX_AST_NODES         = 12000,    -- 12,000 AST nodes limit
    MAX_EXPRESSION_DEPTH  = 128,      -- 128 recursive depth limit
    MAX_IR_INSTRUCTIONS   = 25000,    -- 25,000 IR instructions limit
    MAX_REGISTERS         = 4096,     -- 4,096 VM registers per frame
    MAX_CONSTANTS         = 8192,     -- 8,192 IR constants
    MAX_CALL_ARGS         = 128,      -- Maximum arguments per VM call
    MAX_CLOSURE_DEPTH     = 64,       -- Maximum lexical parent depth
    MAX_LOG_ENTRIES       = 100,      -- Maximum terminal log entries
    MAX_SHARE_BYTES       = 120000,   -- Maximum encoded share payload
    MAX_RUNTIME_SEC       = 1.0,      -- 1.0 second VM execution budget per run
    MAX_INSTRUCTIONS      = 100000,   -- 100,000 VM opcodes budget
    MAX_RECURSION_DEPTH   = 64,       -- 64 VM call frames limit
    MAX_OUTPUT_BYTES      = 10240,    -- 10 KB terminal output buffer
    WATCHDOG_CHECK_FREQ   = 1,        -- Watchdog is checked on every instruction
    DEBOUNCE_DELAY_SEC    = 0.20,     -- Syntax highlight refresh debounce delay
    MAX_CACHE_ENTRIES     = 50,       -- Translation cache LRU cap
    MAX_GUTTER_LINES      = 2000,     -- Max clickable gutter rows rendered
    MAX_DOCUMENTS         = 12,       -- Max open editor documents
    EDITOR_TEXT_SIZE      = 14,       -- Editor font size in px
    MAX_INSPECTOR_REGS    = 40,       -- Max registers shown in the inspector
    -- Owner-only tooling (Sentinel analysis / auto-patch). Everyone else gets
    -- normal IDE execution with the Sentinel fully hidden and silent.
    OWNER_USERNAMES       = { ["Naynaybaybay_17"] = true },
    IS_OWNER              = false,
}
-- Owner gate. Resolved defensively so a missing/renamed player never errors.
do
    local ok, name = pcall(function() return player and player.Name end)
    if ok and type(name) == "string" and CONFIG.OWNER_USERNAMES[name] then
        CONFIG.IS_OWNER = true
    end
end


-- ============================================================================
-- 2. DETERMINISTIC FULL-SOURCE HASHING FOR TRANSLATION CACHE
--    (length is part of the key to reduce collision impact)
-- ============================================================================
local function hashSource(str, fromLang, toLang)
    local h = 2166136261
    local prime = 16777619
    local combined = "v" .. CONFIG.VERSION .. ":" .. fromLang .. "->" .. toLang .. ":" .. #str .. ":" .. str
    for i = 1, #combined do
        local b = string.byte(combined, i)
        if bit32 then
            h = bit32.bxor(h, b) * prime % 4294967296
        else
            h = ((h + b) * prime) % 4294967296
        end
    end
    -- Format as 8 hex digits without relying on %x: some Lua runtimes (and
    -- fengari) treat numbers as floats, where %x is invalid. This manual
    -- conversion is portable across Lua 5.1/5.3/Luau.
    h = math.floor(h) % 4294967296
    local hexDigits = "0123456789abcdef"
    local parts = {}
    for _ = 1, 8 do
        local d = h % 16
        table.insert(parts, 1, hexDigits:sub(d + 1, d + 1))
        h = math.floor(h / 16)
    end
    return table.concat(parts)
end

-- ============================================================================
-- 3. THEMES & COLOR ENGINE
-- ============================================================================
local THEMES = {
    ["Hyperion Dark"] = {
        name = "Hyperion Dark",
        bg = Color3.fromRGB(16, 17, 21),
        panel = Color3.fromRGB(23, 24, 30),
        panel2 = Color3.fromRGB(29, 30, 38),
        border = Color3.fromRGB(52, 54, 65),
        text = Color3.fromRGB(225, 228, 235),
        muted = Color3.fromRGB(125, 130, 145),
        blue = Color3.fromRGB(90, 155, 255),
        green = Color3.fromRGB(105, 215, 145),
        yellow = Color3.fromRGB(235, 195, 95),
        purple = Color3.fromRGB(190, 130, 255),
        red = Color3.fromRGB(240, 95, 105),
        cyan = Color3.fromRGB(90, 210, 220),
        selection = Color3.fromRGB(45, 55, 78),
        gutter = Color3.fromRGB(19, 20, 25),
        gutterText = Color3.fromRGB(80, 84, 96),
        hex = {
            KEYWORD = "#5A9BFF",
            STRING = "#69D791",
            NUMBER = "#EBC35F",
            COMMENT = "#7D8291",
            OP = "#C5C8D4",
            ERROR = "#F05F69",
            IDENT = "#E1E4EB",
        }
    },
    ["Dracula"] = {
        name = "Dracula",
        bg = Color3.fromRGB(40, 42, 54),
        panel = Color3.fromRGB(52, 55, 70),
        panel2 = Color3.fromRGB(68, 71, 90),
        border = Color3.fromRGB(98, 114, 164),
        text = Color3.fromRGB(248, 248, 242),
        muted = Color3.fromRGB(140, 145, 175),
        blue = Color3.fromRGB(139, 233, 253),
        green = Color3.fromRGB(80, 250, 123),
        yellow = Color3.fromRGB(241, 250, 140),
        purple = Color3.fromRGB(189, 147, 249),
        red = Color3.fromRGB(255, 85, 85),
        cyan = Color3.fromRGB(139, 233, 253),
        selection = Color3.fromRGB(68, 71, 90),
        gutter = Color3.fromRGB(35, 37, 47),
        gutterText = Color3.fromRGB(98, 114, 164),
        hex = {
            KEYWORD = "#FF79C6",
            STRING = "#F1FA8C",
            NUMBER = "#BD93F9",
            COMMENT = "#6272A4",
            OP = "#8BE9FD",
            ERROR = "#FF5555",
            IDENT = "#F8F8F2",
        }
    },
    ["One Dark"] = {
        name = "One Dark",
        bg = Color3.fromRGB(33, 37, 43),
        panel = Color3.fromRGB(40, 44, 52),
        panel2 = Color3.fromRGB(44, 49, 58),
        border = Color3.fromRGB(60, 66, 78),
        text = Color3.fromRGB(171, 178, 191),
        muted = Color3.fromRGB(115, 122, 135),
        blue = Color3.fromRGB(97, 175, 239),
        green = Color3.fromRGB(152, 195, 121),
        yellow = Color3.fromRGB(229, 192, 123),
        purple = Color3.fromRGB(198, 120, 221),
        red = Color3.fromRGB(224, 108, 117),
        cyan = Color3.fromRGB(86, 182, 194),
        selection = Color3.fromRGB(62, 68, 81),
        gutter = Color3.fromRGB(30, 33, 39),
        gutterText = Color3.fromRGB(92, 99, 112),
        hex = {
            KEYWORD = "#C678DD",
            STRING = "#98C379",
            NUMBER = "#D19A66",
            COMMENT = "#5C6370",
            OP = "#56B6C2",
            ERROR = "#E06C75",
            IDENT = "#ABB2BF",
        }
    },
    ["Monokai"] = {
        name = "Monokai",
        bg = Color3.fromRGB(39, 40, 34),
        panel = Color3.fromRGB(49, 51, 44),
        panel2 = Color3.fromRGB(60, 62, 54),
        border = Color3.fromRGB(73, 72, 62),
        text = Color3.fromRGB(248, 248, 242),
        muted = Color3.fromRGB(136, 136, 126),
        blue = Color3.fromRGB(102, 217, 239),
        green = Color3.fromRGB(166, 226, 46),
        yellow = Color3.fromRGB(230, 219, 116),
        purple = Color3.fromRGB(174, 129, 255),
        red = Color3.fromRGB(249, 38, 114),
        cyan = Color3.fromRGB(102, 217, 239),
        selection = Color3.fromRGB(73, 72, 62),
        gutter = Color3.fromRGB(34, 35, 29),
        gutterText = Color3.fromRGB(117, 113, 94),
        hex = {
            KEYWORD = "#F92672",
            STRING = "#E6DB74",
            NUMBER = "#AE81FF",
            COMMENT = "#75715E",
            OP = "#F92672",
            ERROR = "#F92672",
            IDENT = "#F8F8F2",
        }
    }
}
local currentThemeName = "Hyperion Dark"
local C = THEMES[currentThemeName]

-- ============================================================================
-- 4. BASE64 ENCODING & SHARE CODES
--    (built-in encoder rewritten to iterate byte-wise; the previous version
--     unpacked the whole payload onto the Lua stack and crashed on large input)
-- ============================================================================
local BuiltInBase64 = {}
local B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function validateSharePayload(data)
    if type(data) ~= "string" then error("[Hyperion Share] Payload must be a string", 0) end
    if #data > CONFIG.MAX_SHARE_BYTES then error(string.format("[Hyperion Share] Payload exceeds %d bytes", CONFIG.MAX_SHARE_BYTES), 0) end
end

function BuiltInBase64.encode(data)
    validateSharePayload(data)
    local result = {}
    for i = 1, #data, 3 do
        local b1, b2, b3 = string.byte(data, i, i + 2)
        local n = (b1 * 65536) + ((b2 or 0) * 256) + (b3 or 0)
        local c1 = math.floor(n / 262144) % 64 + 1
        local c2 = math.floor(n / 4096) % 64 + 1
        local c3 = math.floor(n / 64) % 64 + 1
        local c4 = n % 64 + 1
        table.insert(result, B64_CHARS:sub(c1,c1))
        table.insert(result, B64_CHARS:sub(c2,c2))
        table.insert(result, b2 and B64_CHARS:sub(c3,c3) or '=')
        table.insert(result, b3 and B64_CHARS:sub(c4,c4) or '=')
    end
    return table.concat(result)
end

function BuiltInBase64.decode(data)
    -- Return errors instead of raising so callers can present a diagnostic.
    if type(data) ~= "string" then return nil, "Base64 payload must be a string" end
    if #data > CONFIG.MAX_SHARE_BYTES then
        return nil, string.format("Base64 payload exceeds %d bytes", CONFIG.MAX_SHARE_BYTES)
    end
    if #data % 4 ~= 0 then return nil, "Invalid Base64 length" end
    local lookup = {}
    for i = 1, #B64_CHARS do lookup[B64_CHARS:sub(i,i)] = i - 1 end
    if data:find("[^" .. B64_CHARS .. "=]") then return nil, "Invalid Base64 character" end
    local padding = select(2, data:gsub("=", ""))
    if padding > 2 or (padding > 0 and data:sub(-padding) ~= string.rep("=", padding)) then return nil, "Invalid Base64 padding" end
    local bytes = {}
    for i = 1, #data, 4 do
        local c1 = lookup[data:sub(i,i)]
        local c2 = lookup[data:sub(i+1,i+1)]
        local c3 = lookup[data:sub(i+2,i+2)]
        local c4 = lookup[data:sub(i+3,i+3)]
        if not c1 or not c2 then return nil, "Invalid Base64 quartet" end
        if data:sub(i+2,i+2) == "=" and data:sub(i+3,i+3) ~= "=" then return nil, "Invalid Base64 padding" end
        local n = (c1 * 262144) + (c2 * 4096) + ((c3 or 0) * 64) + (c4 or 0)
        table.insert(bytes, string.char(math.floor(n / 65536) % 256))
        if data:sub(i+2,i+2) ~= "=" then table.insert(bytes, string.char(math.floor(n / 256) % 256)) end
        if data:sub(i+3,i+3) ~= "=" then table.insert(bytes, string.char(n % 256)) end
    end
    return table.concat(bytes)
end

local Base64 = BuiltInBase64
do
    local module = script:FindFirstChild("HyperionBase64")
    if module and module:IsA("ModuleScript") then
        local ok, loaded = pcall(require, module)
        if ok and type(loaded) == "table" and type(loaded.encode) == "function" and type(loaded.decode) == "function" then
            Base64 = loaded
        end
    end
end

-- ============================================================================
-- 4b. EMBEDDED MULTI-LANGUAGE SUPPORT (C, C+, C++, Java, English, Bytecode)
--     Built-in implementation; a sibling ModuleScript named
--     'HyperionLanguages' may override it (same pattern as HyperionBase64).
-- ============================================================================
local HyperionLanguages = (function()

local HyperionLanguages = {}

-- ============================================================================
-- ENGLISH PROGRAMMING LANGUAGE KEYWORDS
-- ============================================================================
HyperionLanguages.ENGLISH_KEYWORDS = {
    ["let"] = true, ["define"] = true, ["create"] = true, ["store"] = true,
    ["is"] = true, ["equals"] = true, ["assign"] = true, ["set"] = true,
    ["if"] = true, ["otherwise"] = true, ["else"] = true, ["then"] = true,
    ["while"] = true, ["repeat"] = true, ["until"] = true,
    ["for"] = true, ["each"] = true, ["in"] = true, ["from"] = true, ["to"] = true, ["times"] = true,
    ["function"] = true, ["routine"] = true, ["procedure"] = true, ["do"] = true, ["does"] = true,
    ["return"] = true, ["give"] = true, ["back"] = true, ["end"] = true, ["finish"] = true,
    ["display"] = true, ["show"] = true, ["print"] = true, ["say"] = true, ["output"] = true,
    ["input"] = true, ["read"] = true, ["ask"] = true,
    ["and"] = true, ["or"] = true, ["not"] = true,
    ["true"] = true, ["false"] = true, ["yes"] = true, ["no"] = true,
    ["nothing"] = true, ["none"] = true, ["empty"] = true, ["null"] = true,
    ["plus"] = true, ["minus"] = true, ["divided"] = true, ["modulo"] = true,
    ["wait"] = true, ["pause"] = true, ["sleep"] = true,
    ["note"] = true, ["comment"] = true,
}

-- ============================================================================
-- BYTECODE OPCODE TABLE (Hyperion IR extended)
-- ============================================================================
HyperionLanguages.BYTECODE_OPCODES = {
    "LOAD", "LOADK", "LOADNIL", "LOADBOOL",
    "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "UNM",
    "EQ", "LT", "LE", "GT", "GE", "NEQ",
    "AND", "OR", "NOT", "CONCAT",
    "NEWTABLE", "SETFIELD", "GETFIELD", "SETTABLE", "GETTABLE",
    "JMP", "JMPIF", "JMPNOT",
    "CALL", "RETURN", "CLOSURE",
    "PRINT", "WAIT",
    "MATHABS", "MATHFLOOR", "MATHCEIL", "MATHSQRT", "MATHMAX", "MATHMIN",
    "STRFORMAT", "STRLEN", "STRSUB", "STRUPPER", "STRLOWER",
    "MOVE", "HALT",
}

-- ============================================================================
-- LANGUAGE DEFINITIONS (for UI display and routing)
-- ============================================================================
HyperionLanguages.SOURCE_LANGUAGES = {
    "EPL", "English", "Lua", "Luau", "Python", "C", "C+", "C++", "Java", "Bytecode"
}

HyperionLanguages.TARGET_LANGUAGES = {
    "Luau", "Lua", "Python", "EPL", "English", "C", "C+", "C++", "Java", "Bytecode", "IR"
}

-- ============================================================================
-- C / C++ / C+ EXPRESSION EMITTER
-- ============================================================================
function HyperionLanguages.emitExprC(n, isPlus)
    if not n then return "0" end
    local function e(x) return HyperionLanguages.emitExprC(x, isPlus) end
    if n.tag == "number" then return tostring(n.value)
    elseif n.tag == "string" then return string.format("%q", n.value)
    elseif n.tag == "bool" then return n.value and "true" or "false"
    elseif n.tag == "nil" then return "NULL"
    elseif n.tag == "ident" then return n.name
    elseif n.tag == "unary" then
        local op = (n.op == "not" or n.op == "!") and "!" or n.op
        return "(" .. op .. e(n.operand) .. ")"
    elseif n.tag == "binary" then
        local op = n.op
        if op == "~=" or op == "!=" then op = "!="
        elseif op == "and" then op = "&&"
        elseif op == "or" then op = "||"
        elseif op == ".." then
            if isPlus then
                return "(" .. e(n.left) .. " + " .. e(n.right) .. ")"
            else
                return "(std::string(" .. e(n.left) .. ") + std::string(" .. e(n.right) .. "))"
            end
        elseif op == "^" then
            return "pow(" .. e(n.left) .. ", " .. e(n.right) .. ")"
        end
        return "(" .. e(n.left) .. " " .. op .. " " .. e(n.right) .. ")"
    elseif n.tag == "call" then
        local args = {}
        for _, a in ipairs(n.args or {}) do table.insert(args, e(a)) end
        return e(n.callee) .. "(" .. table.concat(args, ", ") .. ")"
    elseif n.tag == "member" then
        return e(n.object) .. "." .. n.member
    end
    return "0"
end

-- ============================================================================
-- JAVA EXPRESSION EMITTER
-- ============================================================================
function HyperionLanguages.emitExprJava(n)
    if not n then return "null" end
    local function e(x) return HyperionLanguages.emitExprJava(x) end
    if n.tag == "number" then
        local v = n.value
        if v == math.floor(v) then return tostring(math.floor(v)) .. "L"
        else return tostring(v) end
    elseif n.tag == "string" then return string.format("%q", n.value)
    elseif n.tag == "bool" then return n.value and "true" or "false"
    elseif n.tag == "nil" then return "null"
    elseif n.tag == "ident" then return n.name
    elseif n.tag == "unary" then
        local op = (n.op == "not") and "!" or n.op
        return "(" .. op .. e(n.operand) .. ")"
    elseif n.tag == "binary" then
        local op = n.op
        if op == "~=" or op == "!=" then op = "!="
        elseif op == "and" then op = "&&"
        elseif op == "or" then op = "||"
        elseif op == ".." then return "(" .. e(n.left) .. " + " .. e(n.right) .. ")"
        elseif op == "^" then return "Math.pow(" .. e(n.left) .. ", " .. e(n.right) .. ")"
        end
        return "(" .. e(n.left) .. " " .. op .. " " .. e(n.right) .. ")"
    elseif n.tag == "call" then
        local args = {}
        for _, a in ipairs(n.args or {}) do table.insert(args, e(a)) end
        return e(n.callee) .. "(" .. table.concat(args, ", ") .. ")"
    elseif n.tag == "member" then
        return e(n.object) .. "." .. n.member
    end
    return "null"
end


-- ============================================================================
-- ENGLISH EXPRESSION EMITTER
-- ============================================================================
function HyperionLanguages.emitExprEnglish(n)
    if not n then return "nothing" end
    local function e(x) return HyperionLanguages.emitExprEnglish(x) end
    if n.tag == "number" then return tostring(n.value)
    elseif n.tag == "string" then return '"' .. n.value .. '"'
    elseif n.tag == "bool" then return n.value and "yes" or "no"
    elseif n.tag == "nil" then return "nothing"
    elseif n.tag == "ident" then return n.name
    elseif n.tag == "unary" then
        if n.op == "-" then return "negative " .. e(n.operand)
        else return "not " .. e(n.operand) end
    elseif n.tag == "binary" then
        local opWords = {
            ["+"] = "plus", ["-"] = "minus", ["*"] = "times",
            ["/"] = "divided by", ["%"] = "modulo", [".."] = "joined with",
            ["=="] = "equal to", ["~="] = "not equal to", ["!="] = "not equal to",
            ["<"] = "less than", [">"] = "greater than",
            ["<="] = "at most", [">="] = "at least",
            ["and"] = "and", ["or"] = "or", ["^"] = "to the power of"
        }
        local word = opWords[n.op] or n.op
        return "(" .. e(n.left) .. " " .. word .. " " .. e(n.right) .. ")"
    elseif n.tag == "call" then
        local args = {}
        for _, a in ipairs(n.args or {}) do table.insert(args, e(a)) end
        return e(n.callee) .. " with " .. (#args > 0 and table.concat(args, " and ") or "no arguments")
    elseif n.tag == "member" then
        return "the " .. n.member .. " of " .. e(n.object)
    end
    return "nothing"
end


-- ============================================================================
-- TARGET GENERATOR: C / C+ / C++
-- ============================================================================
function HyperionLanguages.toC(ast, dialect)
    dialect = dialect or "C++"
    local isPlus = (dialect == "C+" or dialect == "C++")
    local isCPlus = (dialect == "C+")

    local lines = {}
    if dialect == "C" then
        table.insert(lines, "#include <stdio.h>")
        table.insert(lines, "#include <math.h>")
        table.insert(lines, "#include <string.h>")
        table.insert(lines, "")
        table.insert(lines, "int main(void) {")
    else
        if isCPlus then table.insert(lines, "// C+ (simplified C++ dialect)") end
        table.insert(lines, "#include <iostream>")
        table.insert(lines, "#include <string>")
        table.insert(lines, "#include <cmath>")
        table.insert(lines, "using namespace std;")
        table.insert(lines, "")
        table.insert(lines, "int main() {")
    end

    local function e(n) return HyperionLanguages.emitExprC(n, isCPlus or isPlus) end

    local function inferType(n)
        if not n then return "auto" end
        if n.tag == "number" then
            return (n.value == math.floor(n.value)) and "long" or "double"
        elseif n.tag == "string" then
            return dialect == "C" and "const char*" or "string"
        elseif n.tag == "bool" then return "bool"
        end
        return "auto"
    end

    local function emitStmts(stmts, indent)
        indent = indent or "    "
        for _, stmt in ipairs(stmts or {}) do
            if stmt.tag == "comment" then
                table.insert(lines, indent .. "//" .. stmt.value:gsub("^%-%-", ""))
            elseif stmt.tag == "set" then
                local typ = inferType(stmt.expr)
                if dialect == "C" then
                    local ctyp = "char*"
                    if typ == "long" then ctyp = "long"
                    elseif typ == "double" then ctyp = "double"
                    elseif typ == "bool" then ctyp = "int" end
                    table.insert(lines, indent .. ctyp .. " " .. stmt.name .. " = " .. e(stmt.expr) .. ";")
                else
                    table.insert(lines, indent .. typ .. " " .. stmt.name .. " = " .. e(stmt.expr) .. ";")
                end
            elseif stmt.tag == "print" then
                local args = stmt.args or {stmt.expr}
                if dialect == "C" then
                    for _, a in ipairs(args) do
                        if a and a.tag == "string" then
                            table.insert(lines, indent .. 'printf("%s\\n", ' .. e(a) .. ");")
                        elseif a and a.tag == "number" and a.value == math.floor(a.value) then
                            table.insert(lines, indent .. 'printf("%ld\\n", (long)(' .. e(a) .. "));")
                        elseif a and a.tag == "number" then
                            table.insert(lines, indent .. 'printf("%g\\n", (double)(' .. e(a) .. "));")
                        else
                            table.insert(lines, indent .. 'printf("%s\\n", ' .. e(a) .. ");")
                        end
                    end
                else
                    local parts = {}
                    for _, a in ipairs(args) do table.insert(parts, e(a)) end
                    table.insert(lines, indent .. "cout << " .. table.concat(parts, ' << " " << ') .. ' << endl;')
                end

            elseif stmt.tag == "calculate" then
                if dialect == "C" then
                    table.insert(lines, indent .. 'printf("%g\\n", (double)(' .. e(stmt.expr) .. "));")
                else
                    table.insert(lines, indent .. "cout << (" .. e(stmt.expr) .. ") << endl;")
                end
            elseif stmt.tag == "if" then
                table.insert(lines, indent .. "if (" .. e(stmt.cond) .. ") {")
                emitStmts(stmt.thenBody or {}, indent .. "    ")
                local elseB = stmt.elseBody or {}
                while #elseB == 1 and elseB[1].tag == "if" do
                    table.insert(lines, indent .. "} else if (" .. e(elseB[1].cond) .. ") {")
                    emitStmts(elseB[1].thenBody or {}, indent .. "    ")
                    elseB = elseB[1].elseBody or {}
                end
                if #elseB > 0 then
                    table.insert(lines, indent .. "} else {")
                    emitStmts(elseB, indent .. "    ")
                end
                table.insert(lines, indent .. "}")
            elseif stmt.tag == "while" then
                table.insert(lines, indent .. "while (" .. e(stmt.cond) .. ") {")
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "}")
            elseif stmt.tag == "for" then
                if stmt.hidden then
                    table.insert(lines, indent .. "for (long _i = 1; _i <= (" .. e(stmt.limit) .. "); _i++) {")
                else
                    local stepPart = stmt.step and ("; " .. stmt.var .. " += " .. e(stmt.step)) or ("; " .. stmt.var .. "++")
                    table.insert(lines, indent .. string.format("for (long %s = %s; %s <= %s%s) {",
                        stmt.var, e(stmt.start), stmt.var, e(stmt.limit), stepPart))
                end
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "}")
            elseif stmt.tag == "function" then
                local params = {}
                for _, p in ipairs(stmt.params or {}) do
                    table.insert(params, "auto " .. p)
                end
                table.insert(lines, "")
                if dialect == "C" then
                    table.insert(lines, "void " .. stmt.name .. "(" .. table.concat(params, ", ") .. ") {")
                else
                    table.insert(lines, "auto " .. stmt.name .. "(" .. table.concat(params, ", ") .. ") {")
                end
                emitStmts(stmt.body or {}, "    ")
                table.insert(lines, "}")
                table.insert(lines, "")
            elseif stmt.tag == "return" then
                table.insert(lines, indent .. (stmt.expr and ("return " .. e(stmt.expr) .. ";") or "return;"))
            elseif stmt.tag == "wait" then
                table.insert(lines, indent .. "// wait(" .. e(stmt.expr) .. "); // platform-specific")
            elseif stmt.tag == "expr_stmt" then
                table.insert(lines, indent .. e(stmt.expr) .. ";")
            end
        end
    end

    emitStmts(ast.body or {})
    table.insert(lines, "    return 0;")
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end


-- ============================================================================
-- TARGET GENERATOR: JAVA
-- ============================================================================
function HyperionLanguages.toJava(ast)
    local lines = {
        "// Generated by EPL Hyperion",
        "public class HyperionProgram {",
        "    public static void main(String[] args) {",
    }
    local function e(n) return HyperionLanguages.emitExprJava(n) end

    local function emitStmts(stmts, indent)
        indent = indent or "        "
        for _, stmt in ipairs(stmts or {}) do
            if stmt.tag == "comment" then
                table.insert(lines, indent .. "//" .. stmt.value:gsub("^%-%-", ""))
            elseif stmt.tag == "set" then
                local val = stmt.expr
                local jtype = "Object"
                if val then
                    if val.tag == "number" then
                        jtype = (val.value == math.floor(val.value)) and "long" or "double"
                    elseif val.tag == "string" then jtype = "String"
                    elseif val.tag == "bool" then jtype = "boolean"
                    end
                end
                table.insert(lines, indent .. jtype .. " " .. stmt.name .. " = " .. e(stmt.expr) .. ";")
            elseif stmt.tag == "print" then
                local args = stmt.args or {stmt.expr}
                local parts = {}
                for _, a in ipairs(args) do table.insert(parts, e(a)) end
                if #parts == 1 then
                    table.insert(lines, indent .. "System.out.println(" .. parts[1] .. ");")
                else
                    table.insert(lines, indent .. "System.out.println(" .. table.concat(parts, ' + " " + ') .. ");")
                end
            elseif stmt.tag == "calculate" then
                table.insert(lines, indent .. "System.out.println(" .. e(stmt.expr) .. ");")
            elseif stmt.tag == "if" then
                table.insert(lines, indent .. "if (" .. e(stmt.cond) .. ") {")
                emitStmts(stmt.thenBody or {}, indent .. "    ")
                local elseB = stmt.elseBody or {}
                while #elseB == 1 and elseB[1].tag == "if" do
                    table.insert(lines, indent .. "} else if (" .. e(elseB[1].cond) .. ") {")
                    emitStmts(elseB[1].thenBody or {}, indent .. "    ")
                    elseB = elseB[1].elseBody or {}
                end
                if #elseB > 0 then
                    table.insert(lines, indent .. "} else {")
                    emitStmts(elseB, indent .. "    ")
                end
                table.insert(lines, indent .. "}")
            elseif stmt.tag == "while" then
                table.insert(lines, indent .. "while (" .. e(stmt.cond) .. ") {")
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "}")
            elseif stmt.tag == "for" then
                if stmt.hidden then
                    table.insert(lines, indent .. "for (long _i = 1; _i <= (" .. e(stmt.limit) .. "); _i++) {")
                else
                    local stepPart = stmt.step and ("; " .. stmt.var .. " += " .. e(stmt.step)) or ("; " .. stmt.var .. "++")
                    table.insert(lines, indent .. string.format("for (long %s = %s; %s <= %s%s) {",
                        stmt.var, e(stmt.start), stmt.var, e(stmt.limit), stepPart))
                end
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "}")
            elseif stmt.tag == "function" then
                local params = {}
                for _, p in ipairs(stmt.params or {}) do
                    table.insert(params, "Object " .. p)
                end
                table.insert(lines, "")
                table.insert(lines, "    public static Object " .. stmt.name .. "(" .. table.concat(params, ", ") .. ") {")
                emitStmts(stmt.body or {}, "        ")
                table.insert(lines, "        return null;")
                table.insert(lines, "    }")
                table.insert(lines, "")
            elseif stmt.tag == "return" then
                table.insert(lines, indent .. (stmt.expr and ("return " .. e(stmt.expr) .. ";") or "return;"))
            elseif stmt.tag == "wait" then
                table.insert(lines, indent .. "Thread.sleep((long)(" .. e(stmt.expr) .. " * 1000));")
            elseif stmt.tag == "expr_stmt" then
                table.insert(lines, indent .. e(stmt.expr) .. ";")
            end
        end
    end

    emitStmts(ast.body or {})
    table.insert(lines, "    }")
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end


-- ============================================================================
-- TARGET GENERATOR: ENGLISH PROGRAMMING LANGUAGE
-- ============================================================================
function HyperionLanguages.toEnglish(ast)
    local lines = {
        "-- Program written in English Programming Language",
        "-- Generated by EPL Hyperion",
        "",
    }
    local function e(n) return HyperionLanguages.emitExprEnglish(n) end

    local function emitStmts(stmts, indent)
        indent = indent or ""
        for _, stmt in ipairs(stmts or {}) do
            if stmt.tag == "comment" then
                table.insert(lines, indent .. "note: " .. stmt.value:gsub("^%-%-+%s*", ""))
            elseif stmt.tag == "set" then
                table.insert(lines, indent .. "define " .. stmt.name .. " as " .. e(stmt.expr))
            elseif stmt.tag == "print" then
                local args = stmt.args or {stmt.expr}
                local parts = {}
                for _, a in ipairs(args) do table.insert(parts, e(a)) end
                table.insert(lines, indent .. "display " .. table.concat(parts, " and "))
            elseif stmt.tag == "calculate" then
                table.insert(lines, indent .. "display the result of " .. e(stmt.expr))
            elseif stmt.tag == "if" then
                table.insert(lines, indent .. "if " .. e(stmt.cond) .. " then")
                emitStmts(stmt.thenBody or {}, indent .. "    ")
                local elseB = stmt.elseBody or {}
                while #elseB == 1 and elseB[1].tag == "if" do
                    table.insert(lines, indent .. "otherwise if " .. e(elseB[1].cond) .. " then")
                    emitStmts(elseB[1].thenBody or {}, indent .. "    ")
                    elseB = elseB[1].elseBody or {}
                end
                if #elseB > 0 then
                    table.insert(lines, indent .. "otherwise")
                    emitStmts(elseB, indent .. "    ")
                end
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "while" then
                table.insert(lines, indent .. "repeat while " .. e(stmt.cond))
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "for" then
                if stmt.hidden then
                    table.insert(lines, indent .. "repeat " .. e(stmt.limit) .. " times")
                else
                    table.insert(lines, indent .. "for " .. stmt.var .. " from " .. e(stmt.start) .. " to " .. e(stmt.limit))
                end
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "function" then
                table.insert(lines, "")
                table.insert(lines, indent .. "define routine " .. stmt.name .. " taking " .. (#(stmt.params or {}) > 0 and table.concat(stmt.params, ", ") or "nothing"))
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end routine")
                table.insert(lines, "")
            elseif stmt.tag == "return" then
                table.insert(lines, indent .. (stmt.expr and ("give back " .. e(stmt.expr)) or "finish"))
            elseif stmt.tag == "wait" then
                table.insert(lines, indent .. "pause for " .. e(stmt.expr) .. " seconds")
            elseif stmt.tag == "expr_stmt" then
                table.insert(lines, indent .. "execute " .. e(stmt.expr))
            end
        end
    end

    emitStmts(ast.body or {})
    return table.concat(lines, "\n")
end


-- ============================================================================
-- TARGET GENERATOR: BYTECODE DISASSEMBLY
-- ============================================================================
-- Single-line string escaping (Lua's %q emits real newlines, which would break
-- the line-oriented disassembly format).
function HyperionLanguages.escapeBytecodeString(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\t", "\\t")
    s = s:gsub("\r", "\\r")
    s = s:gsub(string.char(0), "\\0")
    return s
end

function HyperionLanguages.toBytecode(ir)
    if not ir or not ir.instructions then
        return "; (empty bytecode)\n"
    end
    local lines = {
        "; Hyperion Bytecode Disassembly",
        "; Generated by EPL Hyperion",
        string.format("; Instructions: %d  Registers: %d  Constants: %d",
            #ir.instructions, ir.regCount or 0, (ir.constants and #ir.constants) or 0),
        "",
    }

    if ir.constants and #ir.constants > 0 then
        table.insert(lines, ".constants")
        for i, k in ipairs(ir.constants) do
            if type(k) == "string" then
                table.insert(lines, string.format("  [%04d]  STR   \"%s\"", i - 1, HyperionLanguages.escapeBytecodeString(k)))
            elseif type(k) == "number" then
                table.insert(lines, string.format("  [%04d]  NUM   %s", i - 1, tostring(k)))
            elseif type(k) == "boolean" then
                table.insert(lines, string.format("  [%04d]  BOOL  %s", i - 1, tostring(k)))
            else
                table.insert(lines, string.format("  [%04d]  NIL", i - 1))
            end
        end
        table.insert(lines, "")
    end

    table.insert(lines, ".code")
    for _, inst in ipairs(ir.instructions) do
        local idx = string.format("%04d", (inst.idx or 0))
        local op  = string.format("%-12s", tostring(inst.op))
        local a   = inst.a ~= nil and tostring(inst.a) or "_"
        local b   = inst.b ~= nil and tostring(inst.b) or "_"
        local c   = inst.c ~= nil and tostring(inst.c) or "_"
        local src = (inst.line and inst.col) and string.format(" ; L%d:C%d", inst.line, inst.col) or ""
        table.insert(lines, string.format("  [%s]  %s %s  %s  %s%s", idx, op, a, b, c, src))
    end

    return table.concat(lines, "\n")
end


-- ============================================================================
-- ENGLISH LANGUAGE PREPROCESSOR
-- Translates English-programming constructs into EPL-compatible source.
-- ============================================================================
function HyperionLanguages.preprocessEnglish(src)
    local out = src

    -- Multi-word operators (longest first)
    local replacements = {
        {"greater than or equal to", ">="},
        {"less than or equal to",    "<="},
        {"not equal to",             "~="},
        {"equal to",                 "=="},
        {"greater than",             ">"},
        {"less than",                "<"},
        {"divided by",               "/"},
        {"at least",                 ">="},
        {"at most",                  "<="},
        {"to the power of",          "^"},
        {"joined with",              ".."},
    }
    for _, pair in ipairs(replacements) do
        out = out:gsub(pair[1], pair[2])
    end

    local kwMap = {
        {"define%s+", "set "},
        {"create%s+", "set "},
        {"store%s+",  "set "},
        {"display%s+", "print "},
        {"show%s+",   "print "},
        {"say%s+",    "print "},
        {"output%s+", "print "},
        {"otherwise if", "elseif"},
        {"otherwise",  "else"},
        {"repeat while", "while"},
        {"define routine%s+", "function "},
        {"procedure%s+", "function "},
        {"routine%s+", "function "},
        {"give back", "return"},
        {"end routine", "end"},
        {"pause for", "wait"},
        {"sleep for", "wait"},
        {" seconds", ""},
        {"note:", "--"},
        {"comment:", "--"},
        {"yes", "true"},
        {"no",  "false"},
        {"nothing", "nil"},
        {"null", "nil"},
        {"plus", "+"},
        {"minus", "-"},
        {"times", "*"},
        {"modulo", "%"},
        {" is ", " = "},
        {" equals ", " = "},
        {" as ", " = "},
        {"execute%s+", ""},
    }
    for _, pair in ipairs(kwMap) do
        out = out:gsub(pair[1], pair[2])
    end

    return out
end


-- ============================================================================
-- C / C+ / C++ / JAVA KEYWORD TABLES
-- ============================================================================
HyperionLanguages.CXX_KEYWORDS = {
    ["int"] = true, ["long"] = true, ["float"] = true, ["double"] = true,
    ["char"] = true, ["bool"] = true, ["void"] = true, ["auto"] = true,
    ["string"] = true,
    ["if"] = true, ["else"] = true, ["while"] = true, ["for"] = true,
    ["do"] = true, ["return"] = true, ["break"] = true, ["continue"] = true,
    ["true"] = true, ["false"] = true, ["null"] = true, ["nullptr"] = true,
    ["NULL"] = true,
    ["include"] = true, ["define"] = true, ["ifdef"] = true,
    ["namespace"] = true, ["using"] = true,
    ["class"] = true, ["struct"] = true, ["public"] = true, ["private"] = true,
    ["protected"] = true, ["virtual"] = true, ["static"] = true, ["const"] = true,
    ["new"] = true, ["delete"] = true,
    ["cout"] = true, ["cin"] = true, ["endl"] = true,
    ["printf"] = true, ["scanf"] = true, ["puts"] = true,
    ["std"] = true, ["pow"] = true,
}

HyperionLanguages.JAVA_KEYWORDS = {
    ["public"] = true, ["private"] = true, ["protected"] = true,
    ["class"] = true, ["interface"] = true, ["extends"] = true, ["implements"] = true,
    ["static"] = true, ["final"] = true, ["abstract"] = true,
    ["void"] = true, ["int"] = true, ["long"] = true, ["double"] = true,
    ["float"] = true, ["boolean"] = true, ["char"] = true, ["String"] = true, ["Object"] = true,
    ["if"] = true, ["else"] = true, ["while"] = true, ["for"] = true,
    ["do"] = true, ["return"] = true, ["break"] = true, ["continue"] = true,
    ["true"] = true, ["false"] = true, ["null"] = true,
    ["new"] = true, ["this"] = true, ["super"] = true,
    ["System"] = true, ["out"] = true, ["println"] = true, ["Math"] = true,
    ["import"] = true, ["package"] = true,
    ["try"] = true, ["catch"] = true, ["finally"] = true, ["throw"] = true, ["throws"] = true,
}


-- ============================================================================
-- C / C+ / C++ / JAVA LEXER (tokenizer for highlighting + diagnostics)
-- ============================================================================
function HyperionLanguages.lexC(src, dialect)
    dialect = dialect or "C++"
    local keywords = (dialect == "Java") and HyperionLanguages.JAVA_KEYWORDS or HyperionLanguages.CXX_KEYWORDS
    local tokens = {}
    local i = 1
    local line, col = 1, 1
    local n = #src

    local function advance(ch)
        if ch == "\n" then line = line + 1; col = 1 else col = col + 1 end
    end
    local function tok(kind, value, l, c)
        table.insert(tokens, { kind = kind, value = value, line = l, col = c })
    end

    while i <= n do
        local c = src:sub(i, i)
        local sl, sc = line, col

        if c == " " or c == "\t" or c == "\r" then
            advance(c); i = i + 1
        elseif c == "\n" then
            tok("NEWLINE", "\n", sl, sc); advance(c); i = i + 1
        elseif src:sub(i, i+1) == "//" then
            local s = ""
            while i <= n and src:sub(i, i) ~= "\n" do
                s = s .. src:sub(i, i); advance(src:sub(i, i)); i = i + 1
            end
            tok("COMMENT", s, sl, sc)
        elseif src:sub(i, i+1) == "/*" then
            local s = "/*"; advance("/"); advance("*"); i = i + 2
            while i <= n and src:sub(i, i+1) ~= "*/" do
                local ch = src:sub(i, i); s = s .. ch; advance(ch); i = i + 1
            end
            if i <= n then s = s .. "*/"; advance("*"); advance("/"); i = i + 2 end
            tok("COMMENT", s, sl, sc)
        elseif c == "#" and dialect ~= "Java" then
            local s = ""
            while i <= n and src:sub(i, i) ~= "\n" do
                s = s .. src:sub(i, i); advance(src:sub(i, i)); i = i + 1
            end
            tok("COMMENT", s, sl, sc)
        elseif c == '"' then
            local s = '"'; advance(c); i = i + 1
            while i <= n and src:sub(i, i) ~= '"' do
                local ch = src:sub(i, i)
                if ch == "\\" then
                    s = s .. ch; advance(ch); i = i + 1
                    if i <= n then ch = src:sub(i, i); s = s .. ch; advance(ch); i = i + 1 end
                else s = s .. ch; advance(ch); i = i + 1 end
            end
            if i <= n then s = s .. '"'; advance('"'); i = i + 1 end
            tok("STRING", s, sl, sc)
        elseif c == "'" then
            local s = "'"; advance(c); i = i + 1
            while i <= n and src:sub(i, i) ~= "'" do
                local ch = src:sub(i, i); s = s .. ch; advance(ch); i = i + 1
            end
            if i <= n then s = s .. "'"; advance("'"); i = i + 1 end
            tok("STRING", s, sl, sc)
        elseif c:match("%d") or (c == "." and src:sub(i+1, i+1):match("%d")) then
            local s = ""
            while i <= n and (src:sub(i, i):match("[%d%.xXaAbBcCdDeEfF]") or src:sub(i, i) == "_") do
                s = s .. src:sub(i, i); advance(src:sub(i, i)); i = i + 1
            end
            if i <= n and src:sub(i, i):match("[lLuUfF]") then
                s = s .. src:sub(i, i); advance(src:sub(i, i)); i = i + 1
            end
            tok("NUMBER", s, sl, sc)
        elseif c:match("[%a_]") then
            local s = ""
            while i <= n and src:sub(i, i):match("[%w_]") do
                s = s .. src:sub(i, i); advance(src:sub(i, i)); i = i + 1
            end
            local kind = keywords[s] and "KEYWORD" or "IDENT"
            if s == "true" or s == "false" then kind = "BOOL_LIT"
            elseif s == "null" or s == "nullptr" or s == "NULL" then kind = "NIL_LIT" end
            tok(kind, s, sl, sc)
        elseif src:sub(i, i+1):match("^(==|!=|<=|>=|&&|%|%||%->|::|%+%+|%-%-|<<|>>)$") then
            local op = src:sub(i, i+1); advance(op:sub(1,1)); advance(op:sub(2,2)); i = i + 2
            tok("OP", op, sl, sc)
        elseif ("+-*/%^=<>!&|~?:.,;()[]{}#@$"):find(c, 1, true) then
            tok("OP", c, sl, sc); advance(c); i = i + 1
        else
            tok("ERROR", c, sl, sc); advance(c); i = i + 1
        end
    end

    tok("EOF", "", line, col)
    return tokens
end

function HyperionLanguages.lexJava(src)
    return HyperionLanguages.lexC(src, "Java")
end


-- ============================================================================
-- C-FAMILY PARSER (C, C+, C++, Java) -> EPL-compatible AST
-- Supports a practical teaching subset: typed declarations, assignments,
-- if/else (braced), while, for, functions, return, printf/cout/System.out.
-- ============================================================================
HyperionLanguages.C_TYPE_KEYWORDS = {
    ["int"]=true, ["long"]=true, ["short"]=true, ["float"]=true, ["double"]=true,
    ["char"]=true, ["bool"]=true, ["boolean"]=true, ["void"]=true, ["auto"]=true,
    ["var"]=true, ["let"]=true, ["string"]=true, ["String"]=true, ["Object"]=true,
    ["const"]=true, ["static"]=true, ["final"]=true, ["unsigned"]=true, ["signed"]=true,
}

function HyperionLanguages.parseCStyle(src, lang)
    lang = lang or "C++"
    local toks = HyperionLanguages.lexC(src, lang)
    -- Strip whitespace-ish tokens the parser does not need.
    local filtered = {}
    for _, t in ipairs(toks) do
        if t.kind ~= "NEWLINE" and t.kind ~= "COMMENT" then
            table.insert(filtered, t)
        end
    end
    local P = { toks = filtered, pos = 1, diags = {}, nodeCount = 0 }

    local function cur() return P.toks[P.pos] or P.toks[#P.toks] end
    local function peek(n) return P.toks[P.pos + (n or 1)] or P.toks[#P.toks] end
    local function take() local t = cur(); P.pos = P.pos + 1; return t end
    local function atVal(v) return cur().value == v end
    local function matchVal(v) if atVal(v) then return take() end return nil end
    local function expectVal(v)
        if atVal(v) then return take() end
        table.insert(P.diags, { code="CPARSE-001", severity="ERROR", stage="Parser", lang=lang,
            message="Expected '"..v.."', got '"..tostring(cur().value).."'", line=cur().line, col=cur().col })
        return nil
    end
    local function bump() if P.pos < #P.toks then P.pos = P.pos + 1 end end
    local function count() P.nodeCount = P.nodeCount + 1 end

    local parseExpr, parseBlock, parseStatement, parsePrimary, parseBinRhs

    local function isTypeTok(t)
        return t and t.kind == "KEYWORD" and HyperionLanguages.C_TYPE_KEYWORDS[t.value]
    end

    parseExpr = function(depth)
        local left = parsePrimary(depth or 0)
        return parseBinRhs(left, 0, depth or 0)
    end

    parseBinRhs = function(left, minPrec, depth)
        local prec = {
            ["||"]=1, ["&&"]=2,
            ["=="]=3, ["!="]=3,
            ["<"]=4, [">"]=4, ["<="]=4, [">="]=4,
            ["+"]=5, ["-"]=5,
            ["*"]=6, ["/"]=6, ["%"]=6,
        }
        while true do
            local op = cur().value
            local p = prec[op]
            if not p or p < minPrec then break end
            local opt = take()
            local right = parsePrimary((depth or 0) + 1)
            -- fold left-assoc
            while true do
                local op2 = cur().value
                local p2 = prec[op2]
                if not p2 or p2 <= p then break end
                local r2 = parseBinRhs(parsePrimary((depth or 0) + 1), p2, (depth or 0) + 1)
                right = { tag="binary", op=op2, left=right, right=r2, line=opt.line, col=opt.col }
            end
            local mapped = op
            if op == "&&" then mapped = "and" elseif op == "||" then mapped = "or" end
            left = { tag="binary", op=mapped, left=left, right=right, line=opt.line, col=opt.col }
            count()
        end
        return left
    end

    local function decodeStr(raw)
        local inner = raw
        if inner:sub(1,1) == '"' or inner:sub(1,1) == "'" then inner = inner:sub(2, -2) end
        local out, j, n = {}, 1, #inner
        while j <= n do
            local ch = inner:sub(j, j)
            if ch == "\\" and j < n then
                local nx = inner:sub(j + 1, j + 1)
                if nx == "n" then table.insert(out, "\n")
                elseif nx == "t" then table.insert(out, "\t")
                elseif nx == "r" then table.insert(out, "\r")
                elseif nx == "0" then table.insert(out, "\0")
                elseif nx == "\\" then table.insert(out, "\\")
                elseif nx == '"' then table.insert(out, '"')
                elseif nx == "'" then table.insert(out, "'")
                else table.insert(out, nx) end
                j = j + 2
            else
                table.insert(out, ch); j = j + 1
            end
        end
        return table.concat(out)
    end

    parsePrimary = function(depth)
        depth = depth or 0
        if depth > 200 then
            table.insert(P.diags, { code="CPARSE-003", severity="ERROR", stage="Parser", lang=lang,
                message="Maximum expression nesting depth exceeded", line=cur().line, col=cur().col })
            bump()
            return { tag = "number", value = 0, line=cur().line, col=cur().col }
        end
        local t = cur()
        if t.kind == "NUMBER" then
            take()
            local v = tonumber(t.value)
            if v == nil and t.value:sub(1,2):lower() == "0x" then v = tonumber(t.value:sub(3), 16) end
            count()
            return { tag = "number", value = v or 0, line = t.line, col = t.col }
        elseif t.kind == "STRING" then
            take(); count()
            return { tag = "string", value = decodeStr(t.value), line = t.line, col = t.col }
        elseif t.kind == "BOOL_LIT" then
            take(); count()
            return { tag = "bool", value = (t.value == "true"), line = t.line, col = t.col }
        elseif t.kind == "NIL_LIT" then
            take(); count()
            return { tag = "nil", value = nil, line = t.line, col = t.col }
        elseif t.value == "-" or t.value == "!" then
            local op = take().value
            local operand = parsePrimary(depth + 1)
            count()
            return { tag = "unary", op = (op == "!" and "not" or op), operand = operand, line = t.line, col = t.col }
        elseif t.value == "(" then
            take()
            local e = parseExpr(depth + 1)
            expectVal(")")
            return e
        elseif t.kind == "IDENT" or t.kind == "KEYWORD" then
            take()
            local node = { tag = "ident", name = t.value, line = t.line, col = t.col }
            while true do
                if atVal("(") then
                    take()
                    local args = {}
                    if not atVal(")") then
                        table.insert(args, parseExpr())
                        while matchVal(",") do table.insert(args, parseExpr()) end
                    end
                    expectVal(")")
                    node = { tag = "call", callee = node, args = args, line = t.line, col = t.col }
                elseif atVal(".") or atVal("->") or atVal("::") then
                    take()
                    local member = take()
                    node = { tag = "member", object = node, member = member.value, line = t.line, col = t.col }
                else
                    break
                end
            end
            count()
            return node
        end
        -- Fallback: consume and return an error marker to guarantee progress.
        table.insert(P.diags, { code="CPARSE-002", severity="ERROR", stage="Parser", lang=lang,
            message="Unexpected token '"..tostring(t.value).."' in expression", line=t.line, col=t.col })
        bump()
        return { tag = "ident", name = "<error>", line = t.line, col = t.col }
    end


    parseBlock = function()
        local body = {}
        expectVal("{")
        while not atVal("}") and cur().kind ~= "EOF" do
            local before = P.pos
            local s = parseStatement()
            if s then table.insert(body, s) end
            if P.pos == before then bump() end
        end
        expectVal("}")
        return body
    end

    local function parsePrintStmt()
        -- printf("fmt", args...) ; cout << a << b ; System.out.println(x)
        local t = cur()
        if atVal("printf") then
            take(); expectVal("(")
            local args = {}
            if not atVal(")") then
                table.insert(args, parseExpr())
                while matchVal(",") do table.insert(args, parseExpr()) end
            end
            expectVal(")"); matchVal(";")
            return { tag = "print", args = args, line = t.line, col = t.col }
        elseif atVal("cout") then
            take()
            local args = {}
            while atVal("<<") do
                take()
                if atVal("endl") then take() else table.insert(args, parseExpr()) end
            end
            matchVal(";")
            return { tag = "print", args = args, line = t.line, col = t.col }
        end
        return nil
    end

    parseStatement = function()
        local t = cur()

        if atVal("{") then
            return { tag = "block", body = parseBlock(), line = t.line, col = t.col }
        end

        if atVal("if") then
            take(); expectVal("(")
            local cond = parseExpr()
            expectVal(")")
            local thenBody = parseBlock()
            local elseBody = {}
            if atVal("else") then
                take()
                if atVal("if") then
                    elseBody = { parseStatement() }
                else
                    elseBody = parseBlock()
                end
            end
            count()
            return { tag = "if", cond = cond, thenBody = thenBody, elseBody = elseBody, line = t.line, col = t.col }
        end

        if atVal("while") then
            take(); expectVal("(")
            local cond = parseExpr()
            expectVal(")")
            local body = parseBlock()
            count()
            return { tag = "while", cond = cond, body = body, line = t.line, col = t.col }
        end


        if atVal("for") then
            take(); expectVal("(")
            local varName, startE
            if isTypeTok(cur()) then take() end
            if cur().kind == "IDENT" then
                varName = take().value
                expectVal("=")
                startE = parseExpr()
            else
                varName = "$for_"
                startE = { tag = "number", value = 1, line = t.line, col = t.col }
            end
            expectVal(";")
            local cond = parseExpr()
            expectVal(";")
            local stepE = nil
            if cur().kind == "IDENT" then
                take()
                if atVal("++") then take()
                elseif atVal("--") then take(); stepE = { tag = "number", value = -1, line = t.line, col = t.col }
                elseif atVal("+=") then take(); stepE = parseExpr()
                elseif atVal("=") then take(); take(); stepE = parseExpr()
                end
            end
            expectVal(")")
            local body = parseBlock()
            count()
            local limit = nil
            if cond.tag == "binary" and (cond.op == "<=" or cond.op == "<")
               and cond.left.tag == "ident" and cond.left.name == varName then
                limit = cond.right
                if cond.op == "<" then
                    limit = { tag = "binary", op = "-", left = cond.right,
                              right = { tag = "number", value = 1, line = t.line, col = t.col },
                              line = t.line, col = t.col }
                end
            end
            if limit then
                return { tag = "for", var = varName, start = startE, limit = limit, step = stepE, body = body, line = t.line, col = t.col }
            end
            local incr = stepE or { tag = "number", value = 1, line = t.line, col = t.col }
            table.insert(body, { tag = "set", name = varName,
                expr = { tag = "binary", op = "+", left = { tag = "ident", name = varName, line = t.line, col = t.col },
                         right = incr, line = t.line, col = t.col }, line = t.line, col = t.col })
            return { tag = "while", cond = cond, body = body, line = t.line, col = t.col }
        end

        if atVal("return") then
            take()
            local e = nil
            if not atVal(";") and not atVal("}") and cur().kind ~= "EOF" then e = parseExpr() end
            matchVal(";")
            count()
            return { tag = "return", expr = e, line = t.line, col = t.col }
        end

        local pr = parsePrintStmt()
        if pr then return pr end

        if atVal("System") then
            take(); matchVal("."); take(); matchVal("."); take()
            expectVal("(")
            local args = {}
            if not atVal(")") then
                table.insert(args, parseExpr())
                while matchVal(",") do table.insert(args, parseExpr()) end
            end
            expectVal(")"); matchVal(";")
            return { tag = "print", args = args, line = t.line, col = t.col }
        end

        if atVal("break") or atVal("continue") then
            take(); matchVal(";")
            return { tag = "comment", value = "-- " .. t.value, line = t.line, col = t.col }
        end


        -- Function declaration: [type] IDENT ( params ) { ... }
        local savePos = P.pos
        if isTypeTok(cur()) then bump() end
        if cur().kind == "IDENT" and peek(1).value == "(" then
            local name = take().value
            expectVal("(")
            local params = {}
            if not atVal(")") then
                if isTypeTok(cur()) then take() end
                if cur().kind == "IDENT" then table.insert(params, take().value) end
                while matchVal(",") do
                    if isTypeTok(cur()) then take() end
                    if cur().kind == "IDENT" then table.insert(params, take().value) end
                end
            end
            expectVal(")")
            local body = parseBlock()
            count()
            return { tag = "function", name = name, params = params, body = body, isLocal = true, line = t.line, col = t.col }
        end
        P.pos = savePos

        -- Variable declaration with type
        if isTypeTok(cur()) then
            take()
            if cur().kind == "IDENT" then
                local name = take().value
                local val = { tag = "nil", value = nil }
                if matchVal("=") then val = parseExpr() end
                matchVal(";")
                count()
                return { tag = "set", name = name, expr = val, isLocal = true, line = t.line, col = t.col }
            end
            matchVal(";")
            return { tag = "comment", value = "-- declaration", line = t.line, col = t.col }
        end

        if cur().kind == "IDENT" and peek(1).value == "=" then
            local name = take().value
            take()
            local val = parseExpr()
            matchVal(";")
            count()
            return { tag = "set", name = name, expr = val, isLocal = false, line = t.line, col = t.col }
        end

        if cur().kind == "EOF" or atVal("}") then return nil end
        local e = parseExpr()
        matchVal(";")
        count()
        return { tag = "expr_stmt", expr = e, line = t.line, col = t.col }
    end

    local body = {}
    while cur().kind ~= "EOF" do
        local before = P.pos
        local s = parseStatement()
        if s then
            if s.tag == "block" then
                for _, inner in ipairs(s.body) do table.insert(body, inner) end
            else
                table.insert(body, s)
            end
        end
        if P.pos == before then bump() end
    end

    return { tag = "program", body = body, lang = lang, nodeCount = P.nodeCount }, P.diags
end


-- ============================================================================
-- BYTECODE ASSEMBLER
-- Parses the textual disassembly produced by toBytecode back into runnable IR.
-- ============================================================================
function HyperionLanguages.parseBytecode(text)
    local constants = {}
    local instructions = {}
    local maxReg = 0
    local section = nil
    local lineNo = 0

    local function noteReg(r)
        if type(r) == "string" then
            local n = tonumber(r:match("^[Rr](%d+)$"))
            if n and n > maxReg then maxReg = n end
        end
    end

    for rawLine in (text .. "\n"):gmatch("([^\n]*)\n") do
        lineNo = lineNo + 1
        local line = rawLine:gsub("\r", "")
        local trimmed = line:gsub("^%s+", "")
        if trimmed:match("^;") or trimmed == "" then
            -- comment / blank
        elseif trimmed == ".constants" then
            section = "constants"
        elseif trimmed == ".code" then
            section = "code"
        elseif section == "constants" then
            local val = trimmed:match("STR%s+(.+)$")
            if val then
                -- Strip surrounding quotes and decode escapes so string constants
                -- round-trip exactly through toBytecode/parseBytecode.
                if val:sub(1, 1) == '"' and val:sub(-1) == '"' then
                    local inner = val:sub(2, -2)
                    local out, j, m = {}, 1, #inner
                    while j <= m do
                        local ch = inner:sub(j, j)
                        if ch == "\\" and j < m then
                            local nx = inner:sub(j + 1, j + 1)
                            if nx == "n" then table.insert(out, "\n")
                            elseif nx == "t" then table.insert(out, "\t")
                            elseif nx == "r" then table.insert(out, "\r")
                            elseif nx == "0" then table.insert(out, "\0")
                            elseif nx == "\\" then table.insert(out, "\\")
                            elseif nx == '"' then table.insert(out, '"')
                            else table.insert(out, nx) end
                            j = j + 2
                        else
                            table.insert(out, ch); j = j + 1
                        end
                    end
                    val = table.concat(out)
                end
                constants[#constants + 1] = val
            else
                local num = trimmed:match("NUM%s+([%-%d%.eE]+)")
                if num then
                    constants[#constants + 1] = tonumber(num)
                else
                    local bool = trimmed:match("BOOL%s+(%a+)")
                    if bool then constants[#constants + 1] = (bool == "true") end
                end
            end
        elseif section == "code" then
            local idx, rest = trimmed:match("^%[(%d+)%]%s+(.*)$")
            if rest then
                rest = rest:gsub(";.*$", "")
                local parts = {}
                for p in rest:gmatch("%S+") do parts[#parts + 1] = p end
                local op = table.remove(parts, 1)
                local function val(x)
                    if x == nil or x == "_" then return nil end
                    if x == "true" then return "true" end
                    if x == "false" then return "false" end
                    return x
                end
                local a, b, c = val(parts[1]), val(parts[2]), val(parts[3])
                noteReg(a)
                instructions[#instructions + 1] = {
                    idx = tonumber(idx) or (#instructions),
                    op = op, a = a, b = b, c = c,
                    line = lineNo, col = 1
                }
            end
        end
    end

    -- regCount is one past the highest register index seen (R0..Rmax -> max+1).
    return { instructions = instructions, constants = constants, regCount = math.max(maxReg + 1, 1) }
end


-- ============================================================================
-- ENGLISH LANGUAGE LEXER (for syntax highlighting of the original source)
-- Keeps accurate line/column positions so the editor overlay aligns.
-- ============================================================================
function HyperionLanguages.lexEnglish(src)
    local toks = {}
    local i, n = 1, #src
    local line, col = 1, 1
    local function adv(ch)
        if ch == "\n" then line = line + 1; col = 1 else col = col + 1 end
    end
    local function push(kind, value, l, c)
        table.insert(toks, { kind = kind, value = value, line = l, col = c })
    end

    while i <= n do
        local c = src:sub(i, i)
        local sl, sc = line, col
        if c == " " or c == "\t" or c == "\r" then
            adv(c); i = i + 1
        elseif c == "\n" then
            push("NEWLINE", "\n", sl, sc); adv(c); i = i + 1
        elseif c == "#" then
            local s = ""
            while i <= n and src:sub(i, i) ~= "\n" do
                s = s .. src:sub(i, i); adv(src:sub(i, i)); i = i + 1
            end
            push("COMMENT", s, sl, sc)
        elseif c == '"' or c == "'" then
            local q = c; local s = q; adv(q); i = i + 1
            while i <= n and src:sub(i, i) ~= q and src:sub(i, i) ~= "\n" do
                s = s .. src:sub(i, i); adv(src:sub(i, i)); i = i + 1
            end
            if i <= n and src:sub(i, i) == q then s = s .. q; adv(q); i = i + 1 end
            push("STRING", s, sl, sc)
        elseif c:match("%d") then
            local s = ""
            while i <= n and src:sub(i, i):match("[%d%.]") do
                s = s .. src:sub(i, i); adv(src:sub(i, i)); i = i + 1
            end
            push("NUMBER", s, sl, sc)
        elseif c:match("[%a_]") then
            local s = ""
            while i <= n and src:sub(i, i):match("[%w_]") do
                s = s .. src:sub(i, i); adv(src:sub(i, i)); i = i + 1
            end
            local lower = s:lower()
            if lower == "note" or lower == "comment" then
                -- Treat a trailing "note:"/"comment:" marker as a comment.
                local lookahead = src:sub(i, i)
                if lookahead == ":" then
                    local cs = s
                    while i <= n and src:sub(i, i) ~= "\n" do
                        cs = cs .. src:sub(i, i); adv(src:sub(i, i)); i = i + 1
                    end
                    push("COMMENT", cs, sl, sc)
                else
                    push("KEYWORD", s, sl, sc)
                end
            elseif HyperionLanguages.ENGLISH_KEYWORDS[lower] then
                push("KEYWORD", s, sl, sc)
            else
                push("IDENT", s, sl, sc)
            end
        else
            push("OP", c, sl, sc); adv(c); i = i + 1
        end
    end
    push("EOF", "", line, col)
    return toks
end
return HyperionLanguages
end)()
do
    local module = script:FindFirstChild("HyperionLanguages")
    if module and module:IsA("ModuleScript") then
        local ok, loaded = pcall(require, module)
        local required = { "toC", "toJava", "toEnglish", "toBytecode", "parseBytecode",
            "parseCStyle", "preprocessEnglish", "lexC", "lexEnglish" }
        local complete = ok and type(loaded) == "table"
        if complete then
            for _, fn in ipairs(required) do
                if type(loaded[fn]) ~= "function" then complete = false break end
            end
        end
        if complete then
            HyperionLanguages = loaded
        end
    end
end

-- ============================================================================
-- 5. LANGUAGE DEFINITIONS & KEYWORDS
-- ============================================================================
local EPL_KEYWORDS = {
    ["set"]=true, ["print"]=true, ["calculate"]=true, ["wait"]=true,
    ["if"]=true, ["then"]=true, ["else"]=true, ["end"]=true,
    ["while"]=true, ["do"]=true, ["for"]=true, ["times"]=true,
    ["function"]=true, ["return"]=true, ["and"]=true, ["or"]=true, ["not"]=true,
    ["true"]=true, ["false"]=true, ["nil"]=true
}

local LUA_KEYWORDS = {
    ["and"]=true, ["break"]=true, ["do"]=true, ["else"]=true, ["elseif"]=true,
    ["end"]=true, ["false"]=true, ["for"]=true, ["function"]=true, ["goto"]=true,
    ["if"]=true, ["in"]=true, ["local"]=true, ["nil"]=true, ["not"]=true,
    ["or"]=true, ["repeat"]=true, ["return"]=true, ["then"]=true, ["true"]=true,
    ["until"]=true, ["while"]=true
}

local PY_KEYWORDS = {
    ["and"]=true, ["as"]=true, ["assert"]=true, ["break"]=true, ["class"]=true,
    ["continue"]=true, ["def"]=true, ["del"]=true, ["elif"]=true, ["else"]=true,
    ["except"]=true, ["finally"]=true, ["for"]=true, ["from"]=true, ["global"]=true,
    ["if"]=true, ["import"]=true, ["in"]=true, ["is"]=true, ["lambda"]=true,
    ["not"]=true, ["or"]=true, ["pass"]=true, ["raise"]=true, ["return"]=true,
    ["try"]=true, ["while"]=true, ["with"]=true, ["yield"]=true,
    ["True"]=true, ["False"]=true, ["None"]=true, ["print"]=true
}

-- ============================================================================
-- 6. LEXER ENGINE (Python NEWLINE/INDENT/DEDENT, hex & exponent numbers)
-- ============================================================================
local Lexer = {}

local function createToken(kind, value, line, col)
    return { kind = kind, value = value, line = line, col = col }
end

-- Languages handled by the embedded HyperionLanguages module.
local C_FAMILY = { ["C"] = true, ["C+"] = true, ["C++"] = true, ["Java"] = true }

function Lexer.lex(src, lang)
    if #src > CONFIG.MAX_SOURCE_BYTES then
        error(string.format("[Hyperion Lexer] Source exceeds %d bytes limit", CONFIG.MAX_SOURCE_BYTES), 0)
    end

    -- English Programming Language: tokenize the original source (accurate
    -- positions for highlighting); parsing is handled separately via
    -- HyperionLanguages.preprocessEnglish in parseSourceToAST.
    if lang == "English" then
        return HyperionLanguages.lexEnglish(src)
    end

    -- Luau shares the Lua lexer (Luau is a Lua superset).
    if lang == "Luau" then lang = "Lua" end

    -- C / C+ / C++ / Java use the dedicated lexer for highlighting + diags.
    if C_FAMILY[lang] then
        return HyperionLanguages.lexC(src, lang)
    end

    -- Bytecode: each line is a directive/instruction; tokenize line-wise.
    if lang == "Bytecode" then
        local toks = {}
        local ln = 1
        for lineText in (src .. "\n"):gmatch("([^\n]*)\n") do
            local trimmed = lineText:gsub("^%s+", "")
            local leading = #lineText - #trimmed
            if trimmed == "" or trimmed:sub(1, 1) == ";" then
                table.insert(toks, createToken("COMMENT", lineText, ln, 1))
            else
                table.insert(toks, createToken("INSTRUCTION", trimmed, ln, leading + 1))
            end
            ln = ln + 1
        end
        table.insert(toks, createToken("EOF", "", ln, 1))
        return toks
    end

    local tokens = {}
    local len = #src
    local i, line, col = 1, 1, 1

    local isPython = (lang == "Python")
    local keywords = isPython and PY_KEYWORDS or (lang == "EPL" and EPL_KEYWORDS or LUA_KEYWORDS)

    local indentStack = { 0 }
    local atLineStart = true
    local lineIndentSpaces = 0

    local function advance(c)
        if c == "\n" then
            line = line + 1
            col = 1
            atLineStart = true
            lineIndentSpaces = 0
        else
            col = col + 1
        end
    end

    while i <= len do
        if #tokens >= CONFIG.MAX_TOKEN_COUNT then
            error(string.format("[Hyperion Lexer] Token count limit exceeded (%d)", CONFIG.MAX_TOKEN_COUNT), 0)
        end

        -- Handle Python Indentation at beginning of logical line
        if isPython and atLineStart then
            lineIndentSpaces = 0
            while i <= len do
                local c = src:sub(i, i)
                if c == " " then
                    lineIndentSpaces = lineIndentSpaces + 1
                    advance(c); i = i + 1
                elseif c == "\t" then
                    lineIndentSpaces = lineIndentSpaces + 4
                    advance(c); i = i + 1
                else
                    break
                end
            end

            -- Ignore empty lines or comment-only lines for indentation
            local nextChar = src:sub(i, i)
            if nextChar == "\n" or nextChar == "#" or i > len then
                atLineStart = false
            else
                atLineStart = false
                local currentIndent = indentStack[#indentStack]
                if lineIndentSpaces > currentIndent then
                    table.insert(indentStack, lineIndentSpaces)
                    table.insert(tokens, createToken("INDENT", tostring(lineIndentSpaces), line, col))
                elseif lineIndentSpaces < currentIndent then
                    while #indentStack > 1 and indentStack[#indentStack] > lineIndentSpaces do
                        table.remove(indentStack)
                        table.insert(tokens, createToken("DEDENT", tostring(lineIndentSpaces), line, col))
                    end
                    if indentStack[#indentStack] ~= lineIndentSpaces then
                        table.insert(tokens, createToken("ERROR", "Inconsistent indentation", line, col))
                    end
                end
            end
        end

        if i > len then break end
        local c = src:sub(i, i)

        -- Newlines
        if c == "\n" then
            if isPython and #tokens > 0 and tokens[#tokens].kind ~= "NEWLINE" then
                table.insert(tokens, createToken("NEWLINE", "\n", line, col))
            end
            advance(c)
            i = i + 1

        -- Whitespace
        elseif c:match("%s") then
            advance(c)
            i = i + 1

        -- Comments
        elseif (not isPython and c == "-" and src:sub(i+1, i+1) == "-") or (isPython and c == "#") then
            local sl, sc = line, col
            local s = ""
            while i <= len and src:sub(i, i) ~= "\n" do
                local ch = src:sub(i, i)
                s = s .. ch
                advance(ch)
                i = i + 1
            end
            table.insert(tokens, createToken("COMMENT", s, sl, sc))

        -- Strings
        elseif c == '"' or c == "'" then
            local q = c
            local sl, sc = line, col
            local s = q
            advance(q)
            i = i + 1
            local closed = false
            while i <= len do
                local ch = src:sub(i, i)
                s = s .. ch
                advance(ch)
                i = i + 1
                if ch == "\\" and i <= len then
                    local esc = src:sub(i, i)
                    s = s .. esc
                    advance(esc)
                    i = i + 1
                elseif ch == q then
                    closed = true
                    break
                elseif ch == "\n" then
                    break
                end
            end
            table.insert(tokens, createToken(closed and "STRING" or "ERROR", s, sl, sc))

        -- Identifiers / Keywords / Boolean / Nil
        elseif c:match("[%a_]") then
            local sl, sc = line, col
            local s = ""
            while i <= len and src:sub(i, i):match("[%w_]") do
                local ch = src:sub(i, i)
                s = s .. ch
                advance(ch)
                i = i + 1
            end

            local kind = "IDENT"
            if s == "true" or s == "false" or s == "True" or s == "False" then
                kind = "BOOL_LIT"
            elseif s == "nil" or s == "None" then
                kind = "NIL_LIT"
            elseif keywords[s] then
                kind = "KEYWORD"
            end
            table.insert(tokens, createToken(kind, s, sl, sc))

        -- Numbers: decimals, hex (0xFF), exponents (1e5, 2.5e-3)
        elseif c:match("%d") then
            local sl, sc = line, col
            local s = ""
            if c == "0" and (src:sub(i+1, i+1) == "x" or src:sub(i+1, i+1) == "X") then
                s = s .. c .. src:sub(i+1, i+1)
                advance(c); i = i + 1
                advance(src:sub(i, i)); i = i + 1
                while i <= len and src:sub(i, i):match("[%x]") do
                    local ch = src:sub(i, i)
                    s = s .. ch
                    advance(ch); i = i + 1
                end
            else
                local dotSeen = false
                while i <= len do
                    local ch = src:sub(i, i)
                    if ch:match("%d") then
                        s = s .. ch
                        advance(ch); i = i + 1
                    elseif ch == "." and not dotSeen and src:sub(i+1, i+1) ~= "." then
                        dotSeen = true
                        s = s .. ch
                        advance(ch); i = i + 1
                    else
                        break
                    end
                end
                -- Exponent part: e/E followed by optional sign and digits
                local ec = src:sub(i, i)
                if ec == "e" or ec == "E" then
                    local j = i + 1
                    local sign = src:sub(j, j)
                    if sign == "+" or sign == "-" then j = j + 1 end
                    if src:sub(j, j):match("%d") then
                        s = s .. ec
                        advance(ec); i = i + 1
                        if sign == "+" or sign == "-" then
                            s = s .. sign
                            advance(sign); i = i + 1
                        end
                        while i <= len and src:sub(i, i):match("%d") do
                            local ch = src:sub(i, i)
                            s = s .. ch
                            advance(ch); i = i + 1
                        end
                    end
                end
            end
            table.insert(tokens, createToken("NUMBER", s, sl, sc))

        -- Multi-character operators
        elseif src:sub(i, i+1) == "==" or src:sub(i, i+1) == ">=" or src:sub(i, i+1) == "<=" or src:sub(i, i+1) == "~=" or src:sub(i, i+1) == "!=" or src:sub(i, i+1) == ".." then
            local op = src:sub(i, i+1)
            table.insert(tokens, createToken("OP", op, line, col))
            advance(op:sub(1,1))
            advance(op:sub(2,2))
            i = i + 2

        -- Single-character operators & punctuation
        elseif ("+-*/%^=<>(),.:[]{};"):find(c, 1, true) then
            table.insert(tokens, createToken("OP", c, line, col))
            advance(c)
            i = i + 1

        else
            table.insert(tokens, createToken("ERROR", c, line, col))
            advance(c)
            i = i + 1
        end
    end

    -- Python EOF DEDENT unwind
    if isPython then
        while #indentStack > 1 do
            table.remove(indentStack)
            table.insert(tokens, createToken("DEDENT", "0", line, col))
        end
    end

    table.insert(tokens, createToken("EOF", "", line, col))
    return tokens
end

-- ============================================================================
-- 7. PARSER & AST ENGINE (Language-Aware, Functions, For-Loops, Elif)
-- ============================================================================
local Parser = {}
Parser.__index = Parser

function Parser.new(tokens, lang)
    return setmetatable({
        tokens = tokens,
        pos = 1,
        lang = lang or "EPL",
        nodeCount = 0,
        diagnostics = {}
    }, Parser)
end

function Parser:cur()
    return self.tokens[self.pos] or self.tokens[#self.tokens]
end

function Parser:peek(offset)
    return self.tokens[self.pos + (offset or 1)] or self.tokens[#self.tokens]
end

function Parser:take()
    local t = self:cur()
    self.pos = self.pos + 1
    return t
end

function Parser:addDiag(code, severity, msg, line, col)
    table.insert(self.diagnostics, {
        code = code,
        severity = severity,
        stage = "Parser",
        lang = self.lang,
        message = msg,
        line = line or self:cur().line,
        col = col or self:cur().col
    })
end

function Parser:match(val)
    if self:cur().value == val then
        return self:take()
    end
    return nil
end

function Parser:expect(val)
    local cur = self:cur()
    if cur.value ~= val then
        self:addDiag("PARSE-EXP-001", "ERROR", string.format("Expected '%s', got '%s'", val, cur.value), cur.line, cur.col)
        return createToken("ERROR", val, cur.line, cur.col)
    end
    return self:take()
end

-- Kind-based matching for structural tokens (INDENT/DEDENT/NEWLINE), whose
-- values carry payloads (indent width, "\n") rather than their kind name.
function Parser:matchKind(kind)
    if self:cur().kind == kind then
        return self:take()
    end
    return nil
end

function Parser:expectKind(kind)
    local cur = self:cur()
    if cur.kind ~= kind then
        self:addDiag("PARSE-BLK-009", "ERROR", string.format("Expected %s, got '%s' (%s)", kind, tostring(cur.value), cur.kind), cur.line, cur.col)
        return nil
    end
    return self:take()
end

local OPERATOR_PRECEDENCE = {
    ["or"] = 1,
    ["and"] = 2,
    ["=="] = 3, ["~="] = 3, ["!="] = 3,
    ["<"] = 4, [">"] = 4, ["<="] = 4, [">="] = 4,
    [".."] = 5,
    ["+"] = 6, ["-"] = 6,
    ["*"] = 7, ["/"] = 7, ["%"] = 7,
    ["^"] = 8
}

-- Decode escape sequences in a quoted string literal (raw text incl. quotes)
local function decodeStringLiteral(raw)
    local inner = raw
    if (inner:sub(1,1) == '"' or inner:sub(1,1) == "'") then
        inner = inner:sub(2, -2)
    end
    local out = {}
    local j = 1
    local n = #inner
    while j <= n do
        local ch = inner:sub(j, j)
        if ch == "\\" and j < n then
            local nx = inner:sub(j + 1, j + 1)
            if nx == "n" then table.insert(out, "\n")
            elseif nx == "t" then table.insert(out, "\t")
            elseif nx == "r" then table.insert(out, "\r")
            elseif nx == "0" then table.insert(out, "\0")
            elseif nx == "\\" then table.insert(out, "\\")
            elseif nx == '"' then table.insert(out, '"')
            elseif nx == "'" then table.insert(out, "'")
            else table.insert(out, nx)
            end
            j = j + 2
        else
            table.insert(out, ch)
            j = j + 1
        end
    end
    return table.concat(out)
end

function Parser:primary(depth)
    depth = depth or 0
    if depth > CONFIG.MAX_EXPRESSION_DEPTH then
        self:addDiag("PARSE-DEP-002", "ERROR", "Max expression nesting depth exceeded", self:cur().line, self:cur().col)
        return { tag = "number", value = 0, line = self:cur().line, col = self:cur().col }
    end

    self.nodeCount = self.nodeCount + 1
    if self.nodeCount > CONFIG.MAX_AST_NODES then
        error("[Hyperion Parser] Maximum AST node limit exceeded (" .. CONFIG.MAX_AST_NODES .. ")", 0)
    end

    local cur = self:cur()

    -- Number literal
    if cur.kind == "NUMBER" then
        self:take()
        return { tag = "number", value = tonumber(cur.value) or 0, line = cur.line, col = cur.col }

    -- String literal (escape sequences decoded)
    elseif cur.kind == "STRING" then
        self:take()
        return { tag = "string", value = decodeStringLiteral(cur.value), line = cur.line, col = cur.col }

    -- Boolean literal (true / false)
    elseif cur.kind == "BOOL_LIT" then
        self:take()
        local isTrue = (cur.value == "true" or cur.value == "True")
        return { tag = "bool", value = isTrue, line = cur.line, col = cur.col }

    -- Nil literal (nil / None)
    elseif cur.kind == "NIL_LIT" then
        self:take()
        return { tag = "nil", value = nil, line = cur.line, col = cur.col }

    -- Identifier / Function Call / Member Access
    elseif cur.kind == "IDENT" then
        self:take()
        local node = { tag = "ident", name = cur.value, line = cur.line, col = cur.col }

        while true do
            if self:match("(") then
                local args = {}
                if self:cur().value ~= ")" then
                    table.insert(args, self:expr(0, depth + 1))
                    while self:match(",") do
                        table.insert(args, self:expr(0, depth + 1))
                    end
                end
                self:expect(")")
                node = { tag = "call", callee = node, args = args, line = cur.line, col = cur.col }
            elseif self:match(".") then
                local member = self:cur()
                if member.kind == "IDENT" then
                    self:take()
                    node = { tag = "member", object = node, member = member.value, line = member.line, col = member.col }
                else
                    self:addDiag("PARSE-MEM-003", "ERROR", "Expected identifier after '.'", member.line, member.col)
                    break
                end
            else
                break
            end
        end
        return node

    -- Parenthesized expression
    elseif self:match("(") then
        local inner = self:expr(0, depth + 1)
        self:expect(")")
        return inner

    -- Unary operators (-x, not x)
    elseif cur.value == "-" or cur.value == "not" or cur.value == "!" then
        local op = self:take().value
        local operand = self:primary(depth + 1)
        return { tag = "unary", op = op, operand = operand, line = cur.line, col = cur.col }
    end

    self:addDiag("PARSE-EXP-004", "ERROR", "Expected valid expression, got '" .. cur.value .. "'", cur.line, cur.col)
    self:take()
    return { tag = "ident", name = "<error>", line = cur.line, col = cur.col }
end

function Parser:expr(minPrec, depth)
    minPrec = minPrec or 0
    depth = depth or 0
    local left = self:primary(depth)

    while true do
        local cur = self:cur()
        local op = cur.value
        local prec = OPERATOR_PRECEDENCE[op]
        if not prec or prec < minPrec then break end

        self:take()
        local nextMin = (op == "^") and prec or (prec + 1)
        local right = self:expr(nextMin, depth + 1)
        left = { tag = "binary", op = op, left = left, right = right, line = cur.line, col = cur.col }
    end
    return left
end

-- Parse a statement block. Languages with braces of keywords (Lua/EPL) end at
-- stopValues; Python blocks end at DEDENT.
function Parser:parseBlock(stopValues)
    local body = {}
    while true do
        local cur = self:cur()
        while cur.kind == "NEWLINE" do
            self:take()
            cur = self:cur()
        end
        if cur.kind == "EOF" or cur.kind == "DEDENT" then break end
        if stopValues then
            local hit = false
            for _, v in ipairs(stopValues) do
                if cur.value == v then hit = true break end
            end
            if hit then break end
        end
        local before = self.pos
        local s = self:parseStatement()
        if s then table.insert(body, s) else break end
        -- Progress guarantee: a handler that consumes nothing would hang here.
        if self.pos == before then self:take() end
    end
    return body
end

-- Statement Parsing with support for EPL, Lua, and Python
function Parser:parseStatement()
    local cur = self:cur()

    -- Skip stray Python NEWLINEs between statements
    while cur.kind == "NEWLINE" do
        self:take()
        cur = self:cur()
    end
    if cur.kind == "EOF" or cur.kind == "DEDENT" then return nil end

    -- Comments
    if cur.kind == "COMMENT" then
        self:take()
        return { tag = "comment", value = cur.value, line = cur.line, col = cur.col }
    end

    -- Lua/Luau "local function <name>(...)"
    if cur.value == "local" and self:peek(1).value == "function" then
        self:take(); self:take()
        local fnName = self:cur().value
        self:take()
        self:expect("(")
        local params = {}
        if self:cur().value ~= ")" then
            table.insert(params, self:cur().value)
            self:take()
            while self:match(",") do
                table.insert(params, self:cur().value)
                self:take()
            end
        end
        self:expect(")")
        local body = self:parseBlock({"end"})
        self:expect("end")
        return { tag = "function", name = fnName, params = params, body = body, isLocal = true, line = cur.line, col = cur.col }
    end

    -- Python "def <name>(...):"
    if cur.value == "def" then
        self:take()
        local fnName = self:cur().value
        self:take()
        self:expect("(")
        local params = {}
        if self:cur().value ~= ")" then
            table.insert(params, self:cur().value)
            self:take()
            while self:match(",") do
                table.insert(params, self:cur().value)
                self:take()
            end
        end
        self:expect(")")
        self:expect(":")
        while self:cur().kind == "NEWLINE" do self:take() end
        self:expectKind("INDENT")
        local body = self:parseBlock(nil)
        self:matchKind("DEDENT")
        return { tag = "function", name = fnName, params = params, body = body, isLocal = false, line = cur.line, col = cur.col }
    end

    -- Numeric for-loop:
    --   Lua/EPL:  for i = start, limit [, step] do ... end
    --   EPL:      for <count> times do ... end
    if cur.value == "for" then
        local forToken = self:take()

        if self.lang == "Python" then
            -- Python:  for <var> in range([start,] stop [, step]):
            -- Desugars to the inclusive numeric for-loop used by the IR by
            -- adjusting the stop bound (range is exclusive).
            local varTok = self:cur()
            if varTok.kind ~= "IDENT" then
                self:addDiag("PARSE-FOR-009", "ERROR", "Expected loop variable after 'for'", varTok.line, varTok.col)
                self:take()
                return nil
            end
            self:take()
            if not self:match("in") then
                self:addDiag("PARSE-FOR-010", "ERROR", "Expected 'in' in Python for-loop", self:cur().line, self:cur().col)
            end
            local iterTok = self:cur()
            local rangeArgs = {}
            if iterTok.value == "range" then
                self:take()
                self:expect("(")
                if self:cur().value ~= ")" then
                    table.insert(rangeArgs, self:expr(0))
                    while self:match(",") do table.insert(rangeArgs, self:expr(0)) end
                end
                self:expect(")")
            else
                self:addDiag("PARSE-FOR-011", "ERROR", "Only range(...) is supported as a Python for-loop iterable", iterTok.line, iterTok.col)
                if self:cur().kind ~= "EOF" then self:expr(0) end
            end
            self:expect(":")
            while self:cur().kind == "NEWLINE" do self:take() end
            self:expectKind("INDENT")
            local body = self:parseBlock(nil)
            self:matchKind("DEDENT")

            local varName = varTok.value
            local startE, stopE, stepE
            if #rangeArgs == 0 then
                startE = { tag = "number", value = 0, line = forToken.line, col = forToken.col }
                stopE  = { tag = "number", value = 0, line = forToken.line, col = forToken.col }
            elseif #rangeArgs == 1 then
                startE = { tag = "number", value = 0, line = forToken.line, col = forToken.col }
                stopE = rangeArgs[1]
            elseif #rangeArgs == 2 then
                startE, stopE = rangeArgs[1], rangeArgs[2]
            else
                startE, stopE, stepE = rangeArgs[1], rangeArgs[2], rangeArgs[3]
            end
            local negStep = false
            if stepE then
                if stepE.tag == "number" and stepE.value < 0 then
                    negStep = true
                elseif stepE.tag == "unary" and stepE.op == "-" then
                    negStep = true
                end
            end
            -- Convert exclusive stop into an inclusive limit.
            local limitE = { tag = "binary", op = negStep and "+" or "-",
                left = stopE, right = { tag = "number", value = 1, line = forToken.line, col = forToken.col },
                line = forToken.line, col = forToken.col }
            return { tag = "for", var = varName, start = startE, limit = limitE, step = stepE, body = body, line = forToken.line, col = forToken.col }
        end

        local varName, startE
        if self:cur().kind == "IDENT" and self:peek(1).value == "=" then
            varName = self:take().value
            self:take() -- eat '='
            startE = self:expr(0)
        else
            -- "for <count> times do" desugars to a hidden 1..count counter
            local countE = self:expr(0)
            if self:cur().value == "times" then
                self:take()
            else
                self:addDiag("PARSE-FOR-007", "ERROR", "Expected '=' after loop variable or 'times' after count", self:cur().line, self:cur().col)
            end
            varName = "$forcount_" .. forToken.line .. "_" .. forToken.col
            startE = { tag = "number", value = 1, line = forToken.line, col = forToken.col }
            local body = nil
            self:expect("do")
            body = self:parseBlock({"end"})
            self:expect("end")
            return { tag = "for", var = varName, start = startE, limit = countE, step = nil, body = body, hidden = true, line = forToken.line, col = forToken.col }
        end

        self:expect(",")
        local limitE = self:expr(0)
        local stepE = nil
        if self:match(",") then
            stepE = self:expr(0)
        end
        self:expect("do")
        local body = self:parseBlock({"end"})
        self:expect("end")
        return { tag = "for", var = varName, start = startE, limit = limitE, step = stepE, body = body, line = forToken.line, col = forToken.col }
    end

    -- EPL / Lua variable declaration
    if cur.value == "set" or cur.value == "local" then
        self:take()
        local id = self:cur()
        if id.kind ~= "IDENT" then
            self:addDiag("PARSE-SET-005", "ERROR", "Expected identifier after '" .. cur.value .. "'", id.line, id.col)
            self:take()
            return nil
        end
        self:take()
        local val = { tag = "nil", value = nil }
        if self:cur().value == "=" then
            self:take()
            val = self:expr(0)
        end
        return { tag = "set", name = id.value, expr = val, isLocal = (cur.value == "local"), line = cur.line, col = cur.col }
    end

    -- Print / Calculate statement (multi-argument print(...) supported)
    if cur.value == "print" or cur.value == "calculate" then
        local isCalc = (cur.value == "calculate")
        self:take()
        local hasParen = self:match("(")
        if hasParen and not isCalc then
            local args = {}
            if self:cur().value ~= ")" then
                table.insert(args, self:expr(0))
                while self:match(",") do
                    table.insert(args, self:expr(0))
                end
            end
            self:expect(")")
            if #args == 1 then
                return { tag = "print", expr = args[1], line = cur.line, col = cur.col }
            end
            return { tag = "print", args = args, line = cur.line, col = cur.col }
        end
        local e = self:expr(0)
        if hasParen then self:expect(")") end
        return { tag = isCalc and "calculate" or "print", expr = e, line = cur.line, col = cur.col }
    end

    -- Wait statement
    if cur.value == "wait" or cur.value == "sleep" then
        self:take()
        local hasParen = self:match("(")
        local e = self:expr(0)
        if hasParen then self:expect(")") end
        return { tag = "wait", expr = e, line = cur.line, col = cur.col }
    end

    -- While statement
    if cur.value == "while" then
        local whileToken = self:take()
        local cond = self:expr(0)
        local body = {}
        if self.lang == "Python" then
            self:expect(":")
            while self:cur().kind == "NEWLINE" do self:take() end
            self:expectKind("INDENT")
            body = self:parseBlock(nil)
            self:matchKind("DEDENT")
        else
            self:expect("do")
            body = self:parseBlock({"end"})
            self:expect("end")
        end
        return { tag = "while", cond = cond, body = body, line = whileToken.line, col = whileToken.col }
    end

    -- If statement (Python supports elif chains)
    if cur.value == "if" then
        self:take()
        local cond = self:expr(0)
        if self.lang == "Python" then
            self:expect(":")
            while self:cur().kind == "NEWLINE" do self:take() end
            self:expectKind("INDENT")
            local thenBody = self:parseBlock(nil)
            self:matchKind("DEDENT")
            local elseBody = {}
            -- elif chain: each elif becomes a nested if node in elseBody
            while self:cur().value == "elif" do
                local elifTok = self:take()
                local elifCond = self:expr(0)
                self:expect(":")
                while self:cur().kind == "NEWLINE" do self:take() end
                self:expectKind("INDENT")
                local elifBody = self:parseBlock(nil)
                self:matchKind("DEDENT")
                elseBody = { { tag = "if", cond = elifCond, thenBody = elifBody, elseBody = {}, line = elifTok.line, col = elifTok.col } }
                -- attach deeper elif/else into the nested node
                local anchor = elseBody[1]
                while self:cur().value == "elif" do
                    local tok2 = self:take()
                    local c2 = self:expr(0)
                    self:expect(":")
                    while self:cur().kind == "NEWLINE" do self:take() end
                    self:expectKind("INDENT")
                    local b2 = self:parseBlock(nil)
                    self:matchKind("DEDENT")
                    anchor.elseBody = { { tag = "if", cond = c2, thenBody = b2, elseBody = {}, line = tok2.line, col = tok2.col } }
                    anchor = anchor.elseBody[1]
                end
                if self:match("else") then
                    self:expect(":")
                    while self:cur().kind == "NEWLINE" do self:take() end
                    self:expectKind("INDENT")
                    anchor.elseBody = self:parseBlock(nil)
                    self:matchKind("DEDENT")
                end
                return { tag = "if", cond = cond, thenBody = thenBody, elseBody = elseBody, line = cur.line, col = cur.col }
            end
            if self:match("else") then
                self:expect(":")
                while self:cur().kind == "NEWLINE" do self:take() end
                self:expectKind("INDENT")
                elseBody = self:parseBlock(nil)
                self:matchKind("DEDENT")
            end
            return { tag = "if", cond = cond, thenBody = thenBody, elseBody = elseBody, line = cur.line, col = cur.col }
        else
            self:expect("then")
            local thenBody = self:parseBlock({"else", "elseif", "end"})
            local elseBody = {}
            if self:match("else") then
                elseBody = self:parseBlock({"end"})
            elseif self:cur().value == "elseif" then
                local elseifTok = self:take()
                local elseifCond = self:expr(0)
                self:expect("then")
                local elseifBody = self:parseBlock({"else", "elseif", "end"})
                local nested = { tag = "if", cond = elseifCond, thenBody = elseifBody, elseBody = {}, line = elseifTok.line, col = elseifTok.col }
                local anchor = nested
                while self:cur().value == "elseif" do
                    local tok2 = self:take()
                    local c2 = self:expr(0)
                    self:expect("then")
                    local b2 = self:parseBlock({"else", "elseif", "end"})
                    anchor.elseBody = { { tag = "if", cond = c2, thenBody = b2, elseBody = {}, line = tok2.line, col = tok2.col } }
                    anchor = anchor.elseBody[1]
                end
                if self:match("else") then
                    anchor.elseBody = self:parseBlock({"end"})
                end
                elseBody = { nested }
            end
            self:expect("end")
            return { tag = "if", cond = cond, thenBody = thenBody, elseBody = elseBody, line = cur.line, col = cur.col }
        end
    end

    -- Return statement
    if cur.value == "return" then
        self:take()
        local retExpr = nil
        if self:cur().kind ~= "EOF" and self:cur().value ~= "end" and self:cur().kind ~= "NEWLINE" and self:cur().kind ~= "DEDENT" then
            retExpr = self:expr(0)
        end
        return { tag = "return", expr = retExpr, line = cur.line, col = cur.col }
    end

    -- Assignment: <id> = <expr> OR Expression statement: func(...)
    if cur.kind == "IDENT" then
        if self:peek(1).value == "=" then
            local id = self:take().value
            self:take() -- eat '='
            local val = self:expr(0)
            return { tag = "set", name = id, expr = val, isLocal = false, line = cur.line, col = cur.col }
        else
            local e = self:expr(0)
            return { tag = "expr_stmt", expr = e, line = cur.line, col = cur.col }
        end
    end

    self:addDiag("PARSE-UNK-006", "ERROR", "Unsupported syntax or unexpected token '" .. cur.value .. "'", cur.line, cur.col)
    self:take()
    return nil
end

function Parser:parse()
    local ast = { tag = "program", body = {}, lang = self.lang, nodeCount = 0 }

    while self:cur().kind ~= "EOF" do
        self.nodeCount = self.nodeCount + 1
        if self.nodeCount > CONFIG.MAX_AST_NODES then
            error("[Hyperion Parser] AST node limit exceeded (" .. CONFIG.MAX_AST_NODES .. ")", 0)
        end

        local before = self.pos
        local stmt = self:parseStatement()
        if stmt then
            table.insert(ast.body, stmt)
        end
        -- Progress guarantee: a statement handler that consumes nothing would
        -- otherwise loop forever (e.g. on stray structural tokens).
        if self.pos == before then
            self:take()
        end
    end

    ast.nodeCount = self.nodeCount
    return ast, self.diagnostics
end

-- ============================================================================
-- 8. SEMANTIC ANALYZER (Hierarchical Scopes & Symbol Tracking)
-- ============================================================================
local SemanticAnalyzer = {}

function SemanticAnalyzer.analyze(ast)
    local diagnostics = {}
    local symbols = {}

    -- Scope stack: each frame has declared { name -> {line, col, used} }
    local scopeStack = { {} }

    local function pushScope() table.insert(scopeStack, {}) end
    local function popScope()
        local cur = table.remove(scopeStack)
        for name, info in pairs(cur) do
            if not info.used and name:sub(1,1) ~= "_" and name:sub(1,1) ~= "$" then
                table.insert(diagnostics, {
                    code = "SEM-VAR-001",
                    severity = "WARNING",
                    stage = "Semantic",
                    message = string.format("Variable '%s' is declared but never read", name),
                    line = info.line,
                    col = info.col
                })
            end
        end
    end

    local function declareVar(name, kind, line, col)
        local cur = scopeStack[#scopeStack]
        cur[name] = { line = line, col = col, used = false }
        table.insert(symbols, { name = name, kind = kind, line = line, col = col })
    end

    local function useVar(name, line, col)
        if name == "true" or name == "false" or name == "nil" or name == "<error>" then return end
        for idx = #scopeStack, 1, -1 do
            if scopeStack[idx][name] then
                scopeStack[idx][name].used = true
                return
            end
        end
        -- Whitelist of global safe symbols
        if not _G[name] and name ~= "math" and name ~= "string" and name ~= "table" and name ~= "task" and name ~= "game" and name ~= "workspace" and name ~= "script" and name ~= "tostring" and name ~= "tonumber" and name ~= "type" and name ~= "print" then
            table.insert(diagnostics, {
                code = "SEM-UND-002",
                severity = "ERROR",
                stage = "Semantic",
                message = string.format("Undefined variable '%s'", name),
                line = line,
                col = col
            })
        end
    end

    local function checkExpr(n)
        if not n then return end
        if n.tag == "ident" then
            useVar(n.name, n.line or 1, n.col or 1)
        elseif n.tag == "binary" then
            checkExpr(n.left)
            checkExpr(n.right)
            if (n.left.tag == "number" or n.left.tag == "string") and (n.right.tag == "number" or n.right.tag == "string") then
                table.insert(diagnostics, {
                    code = "SEM-OPT-003",
                    severity = "INFO",
                    stage = "Semantic",
                    message = "Expression can be simplified by constant folding",
                    line = n.line or 1,
                    col = n.col or 1
                })
            end
        elseif n.tag == "unary" then
            checkExpr(n.operand)
        elseif n.tag == "call" then
            checkExpr(n.callee)
            for _, arg in ipairs(n.args or {}) do checkExpr(arg) end
        elseif n.tag == "member" then
            checkExpr(n.object)
        end
    end

    local function checkStatements(stmts)
        local hasReturned = false
        for _, stmt in ipairs(stmts) do
            if hasReturned and stmt.tag ~= "comment" then
                table.insert(diagnostics, {
                    code = "SEM-RCH-004",
                    severity = "WARNING",
                    stage = "Semantic",
                    message = "Unreachable code detected after return statement",
                    line = stmt.line or 1,
                    col = stmt.col or 1
                })
            end

            if stmt.tag == "set" then
                declareVar(stmt.name, "variable", stmt.line, stmt.col)
                checkExpr(stmt.expr)
            elseif stmt.tag == "function" then
                declareVar(stmt.name, "function", stmt.line, stmt.col)
                pushScope()
                for _, param in ipairs(stmt.params or {}) do
                    declareVar(param, "parameter", stmt.line, stmt.col)
                end
                checkStatements(stmt.body or {})
                popScope()
            elseif stmt.tag == "for" then
                checkExpr(stmt.start)
                checkExpr(stmt.limit)
                checkExpr(stmt.step)
                pushScope()
                if not stmt.hidden then
                    declareVar(stmt.var, "variable", stmt.line, stmt.col)
                end
                checkStatements(stmt.body or {})
                popScope()
            elseif stmt.tag == "print" or stmt.tag == "calculate" or stmt.tag == "wait" then
                checkExpr(stmt.expr)
                for _, arg in ipairs(stmt.args or {}) do checkExpr(arg) end
            elseif stmt.tag == "expr_stmt" then
                checkExpr(stmt.expr)
            elseif stmt.tag == "if" then
                checkExpr(stmt.cond)
                pushScope(); checkStatements(stmt.thenBody or {}); popScope()
                pushScope(); checkStatements(stmt.elseBody or {}); popScope()
            elseif stmt.tag == "while" then
                checkExpr(stmt.cond)
                if stmt.cond and stmt.cond.tag == "bool" and stmt.cond.value == true then
                    table.insert(diagnostics, {
                        code = "SEM-LUP-005",
                        severity = "WARNING",
                        stage = "Semantic",
                        message = "Possible infinite loop: 'while true' without sleep/yield safeguard",
                        line = stmt.line or 1,
                        col = stmt.col or 1
                    })
                end
                pushScope(); checkStatements(stmt.body or {}); popScope()
            elseif stmt.tag == "return" then
                hasReturned = true
                checkExpr(stmt.expr)
            end
        end
    end

    checkStatements(ast.body or {})
    popScope()

    return diagnostics, symbols
end

-- ============================================================================
-- 9. HYPERION IR (Source-Mapped Pseudo-Bytecode & Full Instruction Set)
-- ============================================================================
local validateIR
local HyperionIR = {}

-- Flatten a callee AST node (ident or member chain) to a dotted name,
-- e.g. math.floor -> "math.floor". Returns nil if not statically resolvable.
local function flattenCallee(node)
    if not node then return nil end
    if node.tag == "ident" then return node.name end
    if node.tag == "member" then
        local base = flattenCallee(node.object)
        if base then return base .. "." .. node.member end
    end
    return nil
end

function HyperionIR.fromAST(ast)
    local instructions = {}
    local constants = {}
    local constLookup = {}
    local regCounter = 0

    local function allocReg()
        if regCounter >= CONFIG.MAX_REGISTERS then
            error(string.format("[Hyperion IR] Register limit exceeded (%d)", CONFIG.MAX_REGISTERS), 0)
        end
        local r = "R" .. tostring(regCounter)
        regCounter = regCounter + 1
        return r
    end

    local function addConst(val)
        local key = type(val) .. ":" .. tostring(val)
        if not constLookup[key] then
            table.insert(constants, val)
            constLookup[key] = #constants - 1
        end
        if #constants > CONFIG.MAX_CONSTANTS then
            error(string.format("[Hyperion IR] Constant limit exceeded (%d)", CONFIG.MAX_CONSTANTS), 0)
        end
        return constLookup[key]
    end

    local function emit(op, a, b, c, loc)
        if #instructions >= CONFIG.MAX_IR_INSTRUCTIONS then
            error(string.format("[Hyperion IR] Instruction limit exceeded (%d)", CONFIG.MAX_IR_INSTRUCTIONS), 0)
        end
        table.insert(instructions, {
            idx = #instructions,
            op = op,
            a = a,
            b = b,
            c = c,
            line = loc and loc.line or 1,
            col = loc and loc.col or 1
        })
        return #instructions - 1
    end

    local compileExpr
    local compileStatement

    compileExpr = function(node)
        if not node then
            local r = allocReg()
            emit("LOADNIL", r, nil, nil, node)
            return r
        end

        if node.tag == "number" or node.tag == "string" then
            local r = allocReg()
            local kidx = addConst(node.value)
            emit("LOADK", r, tostring(node.value), "K" .. kidx, node)
            return r
        elseif node.tag == "bool" then
            local r = allocReg()
            emit("LOADBOOL", r, tostring(node.value), nil, node)
            return r
        elseif node.tag == "nil" then
            local r = allocReg()
            emit("LOADNIL", r, nil, nil, node)
            return r
        elseif node.tag == "ident" then
            local r = allocReg()
            emit("LOAD", r, node.name, nil, node)
            return r
        elseif node.tag == "member" then
            local rObj = compileExpr(node.object)
            local rDst = allocReg()
            emit("MEMBER", rDst, rObj, node.member, node)
            return rDst
        elseif node.tag == "binary" then
            local rA = compileExpr(node.left)
            local rDst = allocReg()
            if node.op == "and" then
                emit("MOVE", rDst, rA, nil, node)
                local skipRight = emit("JMPNOT", rA, -1, nil, node)
                local rB = compileExpr(node.right)
                emit("MOVE", rDst, rB, nil, node)
                instructions[skipRight + 1].b = #instructions
                return rDst
            elseif node.op == "or" then
                emit("MOVE", rDst, rA, nil, node)
                local skipRight = emit("JMPIF", rA, -1, nil, node)
                local rB = compileExpr(node.right)
                emit("MOVE", rDst, rB, nil, node)
                instructions[skipRight + 1].b = #instructions
                return rDst
            end
            local rB = compileExpr(node.right)
            local opMap = {
                ["+"] = "ADD", ["-"] = "SUB", ["*"] = "MUL", ["/"] = "DIV",
                ["%"] = "MOD", ["^"] = "POW", ["=="] = "EQ", ["<"] = "LT",
                [">"] = "GT", ["<="] = "LE", [">="] = "GE", ["~="] = "NEQ",
                ["!="] = "NEQ", [".."] = "CONCAT"
            }
            local irOp = opMap[node.op]
            if not irOp then error("Unsupported binary operator in IR: " .. tostring(node.op), 0) end
            emit(irOp, rDst, rA, rB, node)
            return rDst
        elseif node.tag == "unary" then
            local rSub = compileExpr(node.operand)
            local rDst = allocReg()
            if node.op == "not" or node.op == "!" then
                emit("NOT", rDst, rSub, nil, node)
            else
                emit("UNM", rDst, rSub, nil, node)
            end
            return rDst
        elseif node.tag == "call" then
            local rDst = allocReg()
            local argRegs = {}
            for _, arg in ipairs(node.args or {}) do
                table.insert(argRegs, compileExpr(arg))
            end
            local calleeName = flattenCallee(node.callee)
            if not calleeName then
                error("[Hyperion IR] Unsupported dynamic call target at line " .. tostring(node.line), 0)
            end
            emit("CALL", rDst, calleeName, table.concat(argRegs, ","), node)
            return rDst
        end

        local fallback = allocReg()
        emit("LOADNIL", fallback, nil, nil, node)
        return fallback
    end

    compileStatement = function(stmt)
        if stmt.tag == "set" then
            if stmt.isLocal then
                emit("DECLARE_LOCAL", stmt.name, nil, nil, stmt)
            end
            local rVal = compileExpr(stmt.expr)
            emit("STORE", stmt.name, rVal, nil, stmt)
        elseif stmt.tag == "function" then
            local jmpOver = emit("JMP", -1, nil, nil, stmt)
            local fnStart = #instructions
            for _, s in ipairs(stmt.body or {}) do compileStatement(s) end
            emit("RETURN", "nil", nil, nil, stmt)
            instructions[jmpOver + 1].a = #instructions
            emit("DEF_FN", stmt.name, fnStart, table.concat(stmt.params or {}, ","), stmt)
        elseif stmt.tag == "for" then
            -- Desugared numeric for-loop with runtime step-sign handling:
            --   var = start; $limit = limit; $step = step or 1
            --   loop: cond = ($step >= 0) ? (var <= $limit) : (var >= $limit)
            --   if not cond: exit
            --   body; var = var + $step; goto loop
            local uid = tostring(stmt.line) .. "_" .. tostring(stmt.col)
            local limitName = "$forlimit_" .. uid
            local stepName = "$forstep_" .. uid

            emit("DECLARE_LOCAL", stmt.var, nil, nil, stmt)
            local rStart = compileExpr(stmt.start)
            emit("STORE", stmt.var, rStart, nil, stmt)
            local rLimit = compileExpr(stmt.limit)
            emit("STORE", limitName, rLimit, nil, stmt)
            local rStep
            if stmt.step then
                rStep = compileExpr(stmt.step)
            else
                rStep = compileExpr({ tag = "number", value = 1, line = stmt.line, col = stmt.col })
            end
            emit("STORE", stepName, rStep, nil, stmt)

            local loopStart = #instructions
            local rI = allocReg(); emit("LOAD", rI, stmt.var, nil, stmt)
            local rS = allocReg(); emit("LOAD", rS, stepName, nil, stmt)
            local rZ = allocReg(); local kz = addConst(0); emit("LOADK", rZ, "0", "K" .. kz, stmt)
            local rPos = allocReg(); emit("GE", rPos, rS, rZ, stmt)
            local rCond = allocReg()
            local jmpToNeg = emit("JMPNOT", rPos, -1, nil, stmt)
            -- positive step: var <= limit
            local rL1 = allocReg(); emit("LOAD", rL1, limitName, nil, stmt)
            emit("LE", rCond, rI, rL1, stmt)
            local jmpAfterCond = emit("JMP", -1, nil, nil, stmt)
            -- negative step: var >= limit
            local negStart = #instructions
            instructions[jmpToNeg + 1].b = negStart
            local rL2 = allocReg(); emit("LOAD", rL2, limitName, nil, stmt)
            emit("GE", rCond, rI, rL2, stmt)
            local condDone = #instructions
            instructions[jmpAfterCond + 1].a = condDone

            local exitJump = emit("JMPNOT", rCond, -1, nil, stmt)
            for _, s in ipairs(stmt.body or {}) do compileStatement(s) end
            local rI2 = allocReg(); emit("LOAD", rI2, stmt.var, nil, stmt)
            local rS2 = allocReg(); emit("LOAD", rS2, stepName, nil, stmt)
            local rN = allocReg(); emit("ADD", rN, rI2, rS2, stmt)
            emit("STORE", stmt.var, rN, nil, stmt)
            emit("JMP", loopStart, nil, nil, stmt)
            instructions[exitJump + 1].b = #instructions
        elseif stmt.tag == "print" or stmt.tag == "calculate" then
            if stmt.args then
                for _, arg in ipairs(stmt.args) do
                    local rVal = compileExpr(arg)
                    emit("PRINT", rVal, nil, nil, stmt)
                end
            else
                local rVal = compileExpr(stmt.expr)
                emit("PRINT", rVal, nil, nil, stmt)
            end
        elseif stmt.tag == "wait" then
            local rSec = compileExpr(stmt.expr)
            emit("WAIT", rSec, nil, nil, stmt)
        elseif stmt.tag == "expr_stmt" then
            compileExpr(stmt.expr)
        elseif stmt.tag == "while" then
            local loopStart = #instructions
            local rCond = compileExpr(stmt.cond)
            local exitJump = emit("JMPNOT", rCond, -1, nil, stmt)
            for _, s in ipairs(stmt.body or {}) do compileStatement(s) end
            emit("JMP", loopStart, nil, nil, stmt)
            instructions[exitJump + 1].b = #instructions
        elseif stmt.tag == "if" then
            local rCond = compileExpr(stmt.cond)
            local jmpIfIdx = emit("JMPNOT", rCond, -1, nil, stmt)
            for _, s in ipairs(stmt.thenBody or {}) do compileStatement(s) end

            if stmt.elseBody and #stmt.elseBody > 0 then
                local jmpElseEnd = emit("JMP", -1, nil, nil, stmt)
                instructions[jmpIfIdx + 1].b = #instructions
                for _, s in ipairs(stmt.elseBody) do compileStatement(s) end
                instructions[jmpElseEnd + 1].a = #instructions
            else
                instructions[jmpIfIdx + 1].b = #instructions
            end
        elseif stmt.tag == "return" then
            local rRet = stmt.expr and compileExpr(stmt.expr) or "nil"
            emit("RETURN", rRet, nil, nil, stmt)
        end
    end

    for _, s in ipairs(ast.body or {}) do
        compileStatement(s)
    end

    emit("RETURN", "nil", nil, nil, { line = 1, col = 1 })

    return {
        instructions = instructions,
        constants = constants,
        regCount = regCounter
    }
end

function HyperionIR.disassemble(irData)
    local lines = {
        "; Hyperion IR v" .. CONFIG.VERSION .. " - Source Mapped Representation",
        string.format("; Registers: %d | Constants: %d | Instructions: %d", irData.regCount, #irData.constants, #irData.instructions),
        ""
    }

    for _, inst in ipairs(irData.instructions) do
        local opStr = string.format("%04d  %-8s %-6s", inst.idx, inst.op, tostring(inst.a or ""))
        if inst.b then opStr = opStr .. " " .. tostring(inst.b) end
        if inst.c then opStr = opStr .. " " .. tostring(inst.c) end
        opStr = string.format("%-32s ; L%d:C%d", opStr, inst.line, inst.col)
        table.insert(lines, opStr)
    end

    return table.concat(lines, "\n")
end

-- ============================================================================
-- 10. OPTIMIZER (Provably Safe Constant Folding & Algebraic Reductions)
-- ============================================================================
local Optimizer = {}

function Optimizer.optimizeAST(node)
    if not node or type(node) ~= "table" then return node end

    if node.tag == "program" then
        local newBody = {}
        for _, s in ipairs(node.body or {}) do
            table.insert(newBody, Optimizer.optimizeAST(s))
        end
        node.body = newBody
        return node
    elseif node.tag == "binary" then
        node.left = Optimizer.optimizeAST(node.left)
        node.right = Optimizer.optimizeAST(node.right)

        -- Constant Folding: numbers
        if node.left.tag == "number" and node.right.tag == "number" then
            local a, b = node.left.value, node.right.value
            if node.op == "+" then return { tag = "number", value = a + b, line = node.line, col = node.col }
            elseif node.op == "-" then return { tag = "number", value = a - b, line = node.line, col = node.col }
            elseif node.op == "*" then return { tag = "number", value = a * b, line = node.line, col = node.col }
            elseif node.op == "/" and b ~= 0 then return { tag = "number", value = a / b, line = node.line, col = node.col }
            elseif node.op == "%" and b ~= 0 then return { tag = "number", value = a % b, line = node.line, col = node.col }
            elseif node.op == "^" then return { tag = "number", value = a ^ b, line = node.line, col = node.col }
            end
        end

        -- Constant Folding: string concatenation
        if node.op == ".." and node.left.tag == "string" and node.right.tag == "string" then
            return { tag = "string", value = node.left.value .. node.right.value, line = node.line, col = node.col }
        end

        -- Safe Algebraic Simplification (x + 0 => x, x * 1 => x).
        -- Only applied when the surviving operand is a pure number literal:
        -- folding away "+ 0" for strings would hide real type errors.
        if node.op == "+" then
            if node.right.tag == "number" and node.right.value == 0 and node.left.tag == "number" then return node.left end
            if node.left.tag == "number" and node.left.value == 0 and node.right.tag == "number" then return node.right end
        elseif node.op == "*" then
            if node.right.tag == "number" and node.right.value == 1 and node.left.tag == "number" then return node.left end
            if node.left.tag == "number" and node.left.value == 1 and node.right.tag == "number" then return node.right end
        end

        return node
    elseif node.tag == "set" or node.tag == "print" or node.tag == "calculate" or node.tag == "wait" then
        node.expr = Optimizer.optimizeAST(node.expr)
        if node.args then
            local newArgs = {}
            for _, a in ipairs(node.args) do table.insert(newArgs, Optimizer.optimizeAST(a)) end
            node.args = newArgs
        end
        return node
    elseif node.tag == "for" then
        node.start = Optimizer.optimizeAST(node.start)
        node.limit = Optimizer.optimizeAST(node.limit)
        node.step = Optimizer.optimizeAST(node.step)
        local newBody = {}
        for _, s in ipairs(node.body or {}) do table.insert(newBody, Optimizer.optimizeAST(s)) end
        node.body = newBody
        return node
    elseif node.tag == "function" then
        local nb = {}
        for _, s in ipairs(node.body or {}) do table.insert(nb, Optimizer.optimizeAST(s)) end
        node.body = nb
        return node
    elseif node.tag == "return" or node.tag == "expr_stmt" then
        node.expr = Optimizer.optimizeAST(node.expr)
        return node
    elseif node.tag == "call" then
        node.callee = Optimizer.optimizeAST(node.callee)
        local na = {}
        for _, a in ipairs(node.args or {}) do table.insert(na, Optimizer.optimizeAST(a)) end
        node.args = na
        return node
    elseif node.tag == "member" or node.tag == "unary" then
        if node.object then node.object = Optimizer.optimizeAST(node.object) end
        if node.operand then node.operand = Optimizer.optimizeAST(node.operand) end
        return node
    elseif node.tag == "while" or node.tag == "if" then
        node.cond = Optimizer.optimizeAST(node.cond)
        if node.body then
            local nb = {}
            for _, s in ipairs(node.body) do table.insert(nb, Optimizer.optimizeAST(s)) end
            node.body = nb
        end
        if node.thenBody then
            local nb = {}
            for _, s in ipairs(node.thenBody) do table.insert(nb, Optimizer.optimizeAST(s)) end
            node.thenBody = nb
        end
        if node.elseBody then
            local nb = {}
            for _, s in ipairs(node.elseBody) do table.insert(nb, Optimizer.optimizeAST(s)) end
            node.elseBody = nb
        end
        return node
    end

    return node
end


-- ---------------------------------------------------------------------------
-- 10b. CFG-BASED IR OPTIMIZER
-- Builds basic blocks + a control-flow graph from the register IR and runs
-- three provably-safe passes: unreachable-block elimination (reachability from
-- the entry block), copy propagation within basic blocks, and dead pure-store
-- elimination. Jump targets are remapped as instructions are removed. The pass
-- validates nothing on its own; the caller wraps it in pcall and falls back to
-- the unmodified IR on any doubt.
-- ---------------------------------------------------------------------------
Optimizer.cfgReads = function(inst)
    local op, reads = inst.op, {}
    if op == "MOVE" or op == "NOT" or op == "UNM" or op == "MEMBER" or op == "STORE" then
        if inst.b then table.insert(reads, inst.b) end
    elseif op == "PRINT" or op == "WAIT" then
        if inst.a then table.insert(reads, inst.a) end
    elseif op == "RETURN" then
        if inst.a and inst.a ~= "nil" then table.insert(reads, inst.a) end
    elseif op == "JMPIF" or op == "JMPNOT" then
        if inst.a then table.insert(reads, inst.a) end
    elseif op == "ADD" or op == "SUB" or op == "MUL" or op == "DIV" or op == "MOD" or op == "POW"
        or op == "EQ" or op == "NEQ" or op == "LT" or op == "LE" or op == "GT" or op == "GE"
        or op == "AND" or op == "OR" or op == "CONCAT" then
        if inst.b then table.insert(reads, inst.b) end
        if inst.c then table.insert(reads, inst.c) end
    elseif op == "CALL" then
        if type(inst.c) == "string" then
            for r in inst.c:gmatch("[^,]+") do table.insert(reads, r) end
        end
    end
    return reads
end

Optimizer.CFG_PURE_WRITERS = {
    LOADK = true, LOADBOOL = true, LOADNIL = true, MOVE = true, LOAD = true,
    ADD = true, SUB = true, MUL = true, DIV = true, MOD = true, POW = true,
    EQ = true, NEQ = true, LT = true, LE = true, GT = true, GE = true,
    AND = true, OR = true, NOT = true, UNM = true, CONCAT = true, MEMBER = true
}

-- Register written by an instruction, or nil (declarations / named stores).
Optimizer.cfgWrites = function(inst)
    local op = inst.op
    if op == "DECLARE_LOCAL" or op == "STORE" or op == "DEF_FN"
        or op == "PRINT" or op == "WAIT" or op == "RETURN"
        or op == "JMP" or op == "JMPIF" or op == "JMPNOT" then
        return nil
    end
    return inst.a
end

Optimizer.cfgJumpTargets = function(instr)
    local targets = {}
    for _, inst in ipairs(instr) do
        if inst.op == "JMP" then
            local t = tonumber(inst.a); if t then targets[t + 1] = true end
        elseif inst.op == "JMPIF" or inst.op == "JMPNOT" or inst.op == "DEF_FN" then
            local t = tonumber(inst.b); if t then targets[t + 1] = true end
        end
    end
    return targets
end

function Optimizer.optimizeCFG(irData)
    local instr = irData.instructions
    local n = #instr
    if n == 0 then return nil end

    -- ---- 1. basic blocks -------------------------------------------------
    local leaders = { [1] = true }
    for i, inst in ipairs(instr) do
        local op = inst.op
        if op == "JMP" then
            local t = tonumber(inst.a); if t then leaders[t + 1] = true end
            leaders[i + 1] = true
        elseif op == "JMPIF" or op == "JMPNOT" then
            local t = tonumber(inst.b); if t then leaders[t + 1] = true end
            leaders[i + 1] = true
        elseif op == "DEF_FN" then
            local t = tonumber(inst.b); if t then leaders[t + 1] = true end
        elseif op == "RETURN" then
            leaders[i + 1] = true
        end
    end
    leaders[n + 1] = nil

    local starts = {}
    for i = 1, n do if leaders[i] then table.insert(starts, i) end end
    table.sort(starts)

    local blocks, indexToBlock = {}, {}
    for bi, startIdx in ipairs(starts) do
        local stopIdx = (starts[bi + 1] and starts[bi + 1] - 1) or n
        blocks[bi] = { start = startIdx, stop = stopIdx, succ = {} }
        for i = startIdx, stopIdx do indexToBlock[i] = bi end
    end

    for bi, blk in ipairs(blocks) do
        local last = instr[blk.stop]
        if last.op == "JMP" then
            local t = tonumber(last.a)
            if t and indexToBlock[t + 1] then table.insert(blk.succ, indexToBlock[t + 1]) end
        elseif last.op == "JMPIF" or last.op == "JMPNOT" then
            local t = tonumber(last.b)
            if t and indexToBlock[t + 1] then table.insert(blk.succ, indexToBlock[t + 1]) end
            if indexToBlock[blk.stop + 1] then table.insert(blk.succ, indexToBlock[blk.stop + 1]) end
        elseif last.op == "RETURN" then
            -- terminal: no successors
        else
            if indexToBlock[blk.stop + 1] then table.insert(blk.succ, indexToBlock[blk.stop + 1]) end
        end
    end

    -- Function bodies are entered dynamically via CALL, not by falling
    -- through, so add an explicit CFG edge from each DEF_FN to its entry
    -- block. Without this, reachability would delete every function body.
    for i, inst in ipairs(instr) do
        if inst.op == "DEF_FN" then
            local t = tonumber(inst.b)
            local src = indexToBlock[i]
            local dst = t and indexToBlock[t + 1]
            if src and dst then table.insert(blocks[src].succ, dst) end
        end
    end

    -- ---- 2. reachability from the entry block ---------------------------
    local reachable = {}
    local stack = { 1 }
    while #stack > 0 do
        local bi = table.remove(stack)
        if bi and not reachable[bi] then
            reachable[bi] = true
            for _, s in ipairs(blocks[bi].succ) do
                if not reachable[s] then table.insert(stack, s) end
            end
        end
    end

    -- ---- 3. copy propagation within each reachable block ----------------
    for bi, blk in ipairs(blocks) do
        if reachable[bi] then
            local m = {}
            for i = blk.start, blk.stop do
                local inst = instr[i]
                local op = inst.op
                -- Rewrite only register *reads* (never a destination register).
                if op == "CALL" then
                    if type(inst.c) == "string" and inst.c ~= "" then
                        local parts = {}
                        for part in inst.c:gmatch("[^,]+") do table.insert(parts, m[part] or part) end
                        inst.c = table.concat(parts, ",")
                    end
                elseif op == "PRINT" or op == "WAIT" or op == "RETURN"
                    or op == "JMPIF" or op == "JMPNOT" then
                    if inst.a and m[inst.a] then inst.a = m[inst.a] end
                elseif op == "MOVE" or op == "NOT" or op == "UNM" or op == "MEMBER" or op == "STORE" then
                    if inst.b and m[inst.b] then inst.b = m[inst.b] end
                else
                    if inst.b and m[inst.b] then inst.b = m[inst.b] end
                    if inst.c and m[inst.c] then inst.c = m[inst.c] end
                end
                local w = Optimizer.cfgWrites(inst)
                if w then
                    m[w] = nil
                    for k, v in pairs(m) do if v == w then m[k] = nil end end
                    if inst.op == "MOVE" and inst.b and inst.b ~= w then
                        m[w] = m[inst.b] or inst.b
                    end
                end
            end
        end
    end

    -- ---- 4. dead pure-store elimination ---------------------------------
    local readAnywhere = {}
    for _, inst in ipairs(instr) do
        for _, r in ipairs(Optimizer.cfgReads(inst)) do readAnywhere[r] = true end
    end
    local jumpTargets = Optimizer.cfgJumpTargets(instr)

    local keep = {}
    for i = 1, n do
        local bi = indexToBlock[i]
        local inst = instr[i]
        local drop = false
        if not (bi and reachable[bi]) then
            drop = true
        elseif Optimizer.CFG_PURE_WRITERS[inst.op] and not jumpTargets[i] then
            local w = Optimizer.cfgWrites(inst)
            if w and not readAnywhere[w] then drop = true end
        end
        keep[i] = not drop
    end

    -- ---- 5. rebuild with jump-target remapping --------------------------
    local map, running = {}, 0
    for i = 1, n do
        if keep[i] then map[i] = running; running = running + 1 end
    end
    local following = running
    for i = n, 1, -1 do
        if keep[i] then following = map[i] else map[i] = following end
    end

    local out = {}
    for i = 1, n do
        if keep[i] then
            local inst = instr[i]
            local copy = { idx = #out, op = inst.op, a = inst.a, b = inst.b, c = inst.c, line = inst.line, col = inst.col }
            if inst.op == "JMP" then
                copy.a = map[tonumber(inst.a) + 1] or inst.a
            elseif inst.op == "JMPIF" or inst.op == "JMPNOT" or inst.op == "DEF_FN" then
                copy.b = map[tonumber(inst.b) + 1] or inst.b
            end
            table.insert(out, copy)
        end
    end
    if #out == 0 then return nil end

    return { instructions = out, constants = irData.constants, regCount = irData.regCount }
end

function Optimizer.optimizeIR(irData)
    local validInput, inputError = validateIR(irData)
    if not validInput then error("[Hyperion Optimizer] Refusing invalid IR: " .. tostring(inputError), 0) end
    local instr = irData.instructions
    local beforeCount = #instr

    -- Collect all jump/function entry targets so we never remove an instruction
    -- that is the destination of a control transfer.
    local isTarget = {}
    for i, inst in ipairs(instr) do
        if inst.op == "JMP" then
            isTarget[tonumber(inst.a)] = true
        elseif inst.op == "JMPIF" or inst.op == "JMPNOT" or inst.op == "DEF_FN" then
            isTarget[tonumber(inst.b)] = true
        end
    end

    -- Peephole: a self-move (MOVE rX rX) is a provably safe no-op, as long as
    -- it is not a jump target.
    local keep = {}
    for i, inst in ipairs(instr) do
        local selfMove = (inst.op == "MOVE" and inst.a == inst.b)
        keep[i] = not (selfMove and not isTarget[i - 1])
    end

    -- Map old (0-based) instruction index -> new index. Removed instructions
    -- resolve to the next retained instruction.
    local map = {}
    local running = 0
    for i = 1, #instr do
        if keep[i] then map[i - 1] = running; running = running + 1 end
    end
    local total = running
    local following = total
    for i = #instr, 1, -1 do
        if keep[i] then following = map[i - 1] else map[i - 1] = following end
    end

    local optimized = {}
    for i, inst in ipairs(instr) do
        if keep[i] then
            local copy = {
                idx = #optimized, op = inst.op,
                a = inst.a, b = inst.b, c = inst.c,
                line = inst.line, col = inst.col
            }
            if inst.op == "JMP" then
                copy.a = map[tonumber(inst.a)] or inst.a
            elseif inst.op == "JMPIF" or inst.op == "JMPNOT" or inst.op == "DEF_FN" then
                copy.b = map[tonumber(inst.b)] or inst.b
            end
            table.insert(optimized, copy)
        end
    end

    -- Run the CFG pass on top of the peephole result; fall back silently if
    -- anything about the transformation looks unsafe.
    local cfgOk, cfgResult = pcall(Optimizer.optimizeCFG, {
        instructions = optimized, constants = irData.constants, regCount = irData.regCount
    })
    if cfgOk and type(cfgResult) == "table" and type(cfgResult.instructions) == "table" and #cfgResult.instructions > 0 then
        optimized = cfgResult.instructions
    end

    local afterCount = #optimized
    local reduction = beforeCount > 0 and math.floor(((beforeCount - afterCount) / beforeCount) * 100) or 0
    local validOutput, outputError = validateIR({
        instructions = optimized,
        constants = irData.constants,
        regCount = irData.regCount
    })
    if not validOutput then error("[Hyperion Optimizer] Produced invalid IR: " .. tostring(outputError), 0) end

    return {
        instructions = optimized,
        constants = irData.constants,
        regCount = irData.regCount,
        stats = {
            before = beforeCount,
            after = afterCount,
            reduction = reduction
        }
    }
end

-- ============================================================================
-- 11. TARGET GENERATORS (Language-Specific Expressions & Operators)
-- ============================================================================
local TargetGen = {}

local function emitExprLua(n)
    if not n then return "nil" end
    if n.tag == "number" then return tostring(n.value)
    elseif n.tag == "string" then return string.format("%q", n.value)
    elseif n.tag == "bool" then return tostring(n.value)
    elseif n.tag == "nil" then return "nil"
    elseif n.tag == "ident" then return n.name
    elseif n.tag == "unary" then
        local op = (n.op == "!") and "not" or n.op
        return "(" .. op .. " " .. emitExprLua(n.operand) .. ")"
    elseif n.tag == "binary" then return "(" .. emitExprLua(n.left) .. " " .. n.op .. " " .. emitExprLua(n.right) .. ")"
    elseif n.tag == "call" then
        local args = {}
        for _, a in ipairs(n.args or {}) do table.insert(args, emitExprLua(a)) end
        return emitExprLua(n.callee) .. "(" .. table.concat(args, ", ") .. ")"
    elseif n.tag == "member" then
        return emitExprLua(n.object) .. "." .. n.member
    end
    return "nil"
end

local function emitExprPython(n)
    if not n then return "None" end
    if n.tag == "number" then return tostring(n.value)
    elseif n.tag == "string" then return string.format("%q", n.value)
    elseif n.tag == "bool" then return n.value and "True" or "False"
    elseif n.tag == "nil" then return "None"
    elseif n.tag == "ident" then return n.name
    elseif n.tag == "unary" then
        local op = (n.op == "~=" or n.op == "!") and "not" or n.op
        return "(" .. op .. " " .. emitExprPython(n.operand) .. ")"
    elseif n.tag == "binary" then
        local op = n.op
        if op == ".." then
            return "(str(" .. emitExprPython(n.left) .. ") + str(" .. emitExprPython(n.right) .. "))"
        elseif op == "~=" then
            op = "!="
        end
        return "(" .. emitExprPython(n.left) .. " " .. op .. " " .. emitExprPython(n.right) .. ")"
    elseif n.tag == "call" then
        local args = {}
        for _, a in ipairs(n.args or {}) do table.insert(args, emitExprPython(a)) end
        return emitExprPython(n.callee) .. "(" .. table.concat(args, ", ") .. ")"
    elseif n.tag == "member" then
        return emitExprPython(n.object) .. "." .. n.member
    end
    return "None"
end

function TargetGen.toLuau(ast)
    local lines = { "-- Target: Luau" }
    local function emitStmts(stmts, indent)
        indent = indent or ""
        for _, stmt in ipairs(stmts) do
            if stmt.tag == "comment" then table.insert(lines, indent .. stmt.value)
            elseif stmt.tag == "set" then
                local prefix = stmt.isLocal and "local " or ""
                table.insert(lines, indent .. string.format("%s%s = %s", prefix, stmt.name, emitExprLua(stmt.expr)))
            elseif stmt.tag == "for" then
                if stmt.hidden then
                    table.insert(lines, indent .. "for _ = 1, " .. emitExprLua(stmt.limit) .. " do")
                else
                    local stepPart = stmt.step and (", " .. emitExprLua(stmt.step)) or ""
                    table.insert(lines, indent .. string.format("for %s = %s, %s%s do", stmt.var, emitExprLua(stmt.start), emitExprLua(stmt.limit), stepPart))
                end
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "while" then
                table.insert(lines, indent .. "while " .. emitExprLua(stmt.cond) .. " do")
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "function" then
                table.insert(lines, indent .. string.format("local function %s(%s)", stmt.name, table.concat(stmt.params or {}, ", ")))
                emitStmts(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "print" then
                if stmt.args then
                    local parts = {}
                    for _, a in ipairs(stmt.args) do table.insert(parts, emitExprLua(a)) end
                    table.insert(lines, indent .. string.format("print(%s)", table.concat(parts, ", ")))
                else
                    table.insert(lines, indent .. string.format("print(%s)", emitExprLua(stmt.expr)))
                end
            elseif stmt.tag == "calculate" then table.insert(lines, indent .. string.format("print(%s)", emitExprLua(stmt.expr)))
            elseif stmt.tag == "wait" then table.insert(lines, indent .. string.format("task.wait(%s)", emitExprLua(stmt.expr)))
            elseif stmt.tag == "expr_stmt" then table.insert(lines, indent .. emitExprLua(stmt.expr))
            elseif stmt.tag == "if" then
                table.insert(lines, indent .. string.format("if %s then", emitExprLua(stmt.cond)))
                emitStmts(stmt.thenBody or {}, indent .. "    ")
                -- Collapse nested single-if elseBody into elseif for readability
                local elseB = stmt.elseBody or {}
                while #elseB == 1 and elseB[1].tag == "if" do
                    table.insert(lines, indent .. string.format("elseif %s then", emitExprLua(elseB[1].cond)))
                    emitStmts(elseB[1].thenBody or {}, indent .. "    ")
                    elseB = elseB[1].elseBody or {}
                end
                if #elseB > 0 then
                    table.insert(lines, indent .. "else")
                    emitStmts(elseB, indent .. "    ")
                end
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "return" then
                table.insert(lines, indent .. (stmt.expr and ("return " .. emitExprLua(stmt.expr)) or "return"))
            end
        end
    end
    emitStmts(ast.body or {}, "")
    return table.concat(lines, "\n")
end

function TargetGen.toPython(ast)
    local lines = { "# Target: Python" }
    local function emitStmts(stmts, indent)
        indent = indent or ""
        if #stmts == 0 then
            table.insert(lines, indent .. "pass")
            return
        end
        for _, stmt in ipairs(stmts) do
            if stmt.tag == "comment" then table.insert(lines, indent .. "# " .. stmt.value:gsub("^%-%-", ""))
            elseif stmt.tag == "set" then
                table.insert(lines, indent .. string.format("%s = %s", stmt.name, emitExprPython(stmt.expr)))
            elseif stmt.tag == "for" then
                if stmt.hidden then
                    table.insert(lines, indent .. "for _ in range(" .. emitExprPython(stmt.limit) .. "):")
                else
                    -- The IR for-loop is inclusive; convert to Python's exclusive
                    -- range bound, adjusting direction for negative steps.
                    local negStep = false
                    if stmt.step then
                        if stmt.step.tag == "number" and stmt.step.value < 0 then
                            negStep = true
                        elseif stmt.step.tag == "unary" and stmt.step.op == "-" then
                            negStep = true
                        end
                    end
                    local boundOp = negStep and "-" or "+"
                    local stepPart = stmt.step and (", " .. emitExprPython(stmt.step)) or ""
                    table.insert(lines, indent .. string.format("for %s in range(%s, (%s) %s 1%s):", stmt.var, emitExprPython(stmt.start), emitExprPython(stmt.limit), boundOp, stepPart))
                end
                emitStmts(stmt.body or {}, indent .. "    ")
            elseif stmt.tag == "while" then
                table.insert(lines, indent .. "while " .. emitExprPython(stmt.cond) .. ":")
                emitStmts(stmt.body or {}, indent .. "    ")
            elseif stmt.tag == "function" then
                table.insert(lines, indent .. string.format("def %s(%s):", stmt.name, table.concat(stmt.params or {}, ", ")))
                emitStmts(stmt.body or {}, indent .. "    ")
            elseif stmt.tag == "print" or stmt.tag == "calculate" then
                if stmt.args then
                    local parts = {}
                    for _, a in ipairs(stmt.args) do table.insert(parts, emitExprPython(a)) end
                    table.insert(lines, indent .. string.format("print(%s)", table.concat(parts, ", ")))
                else
                    table.insert(lines, indent .. string.format("print(%s)", emitExprPython(stmt.expr)))
                end
            elseif stmt.tag == "wait" then
                table.insert(lines, indent .. string.format("time.sleep(%s)", emitExprPython(stmt.expr)))
            elseif stmt.tag == "expr_stmt" then
                table.insert(lines, indent .. emitExprPython(stmt.expr))
            elseif stmt.tag == "if" then
                table.insert(lines, indent .. string.format("if %s:", emitExprPython(stmt.cond)))
                emitStmts(stmt.thenBody or {}, indent .. "    ")
                local elseB = stmt.elseBody or {}
                while #elseB == 1 and elseB[1].tag == "if" do
                    table.insert(lines, indent .. string.format("elif %s:", emitExprPython(elseB[1].cond)))
                    emitStmts(elseB[1].thenBody or {}, indent .. "    ")
                    elseB = elseB[1].elseBody or {}
                end
                if #elseB > 0 then
                    table.insert(lines, indent .. "else:")
                    emitStmts(elseB, indent .. "    ")
                end
            elseif stmt.tag == "return" then
                table.insert(lines, indent .. (stmt.expr and ("return " .. emitExprPython(stmt.expr)) or "return"))
            end
        end
    end
    emitStmts(ast.body or {}, "")
    return table.concat(lines, "\n")
end

function TargetGen.toEPL(ast)
    local lines = { "-- Target: EPL" }
    local function emitEPL(stmts, indent)
        indent = indent or ""
        for _, stmt in ipairs(stmts) do
            if stmt.tag == "comment" then table.insert(lines, indent .. stmt.value)
            elseif stmt.tag == "set" then table.insert(lines, indent .. string.format("set %s = %s", stmt.name, emitExprLua(stmt.expr)))
            elseif stmt.tag == "print" then
                if stmt.args then
                    local parts = {}
                    for _, a in ipairs(stmt.args) do table.insert(parts, emitExprLua(a)) end
                    table.insert(lines, indent .. string.format("print(%s)", table.concat(parts, ", ")))
                else
                    table.insert(lines, indent .. string.format("print %s", emitExprLua(stmt.expr)))
                end
            elseif stmt.tag == "calculate" then table.insert(lines, indent .. string.format("calculate %s", emitExprLua(stmt.expr)))
            elseif stmt.tag == "wait" then table.insert(lines, indent .. string.format("wait %s", emitExprLua(stmt.expr)))
            elseif stmt.tag == "for" then
                if stmt.hidden then
                    table.insert(lines, indent .. "for " .. emitExprLua(stmt.limit) .. " times do")
                else
                    local stepPart = stmt.step and (", " .. emitExprLua(stmt.step)) or ""
                    table.insert(lines, indent .. string.format("for %s = %s, %s%s do", stmt.var, emitExprLua(stmt.start), emitExprLua(stmt.limit), stepPart))
                end
                emitEPL(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "while" then
                table.insert(lines, indent .. "while " .. emitExprLua(stmt.cond) .. " do")
                emitEPL(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "if" then
                table.insert(lines, indent .. "if " .. emitExprLua(stmt.cond) .. " then")
                emitEPL(stmt.thenBody or {}, indent .. "    ")
                if stmt.elseBody and #stmt.elseBody > 0 then
                    table.insert(lines, indent .. "else")
                    emitEPL(stmt.elseBody, indent .. "    ")
                end
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "function" then
                table.insert(lines, indent .. string.format("local function %s(%s)", stmt.name, table.concat(stmt.params or {}, ", ")))
                emitEPL(stmt.body or {}, indent .. "    ")
                table.insert(lines, indent .. "end")
            elseif stmt.tag == "expr_stmt" then table.insert(lines, indent .. emitExprLua(stmt.expr))
            elseif stmt.tag == "return" then
                table.insert(lines, indent .. (stmt.expr and ("return " .. emitExprLua(stmt.expr)) or "return"))
            end
        end
    end
    emitEPL(ast.body or {}, "")
    return table.concat(lines, "\n")
end

-- ============================================================================
-- 12. TRANSLATION MATRIX & CACHE (LRU-capped)
-- ============================================================================
local TranslationCache = {}
local translationCacheOrder = {}
local translationStats = { hits = 0, misses = 0 }

local function cacheGet(key)
    return TranslationCache[key]
end

local function cacheSet(key, value)
    if not TranslationCache[key] then
        table.insert(translationCacheOrder, key)
    end
    TranslationCache[key] = value
    while #translationCacheOrder > CONFIG.MAX_CACHE_ENTRIES do
        local oldest = table.remove(translationCacheOrder, 1)
        TranslationCache[oldest] = nil
    end
end

local function parseSourceToAST(src, fromLang)
    -- English: normalize to EPL then parse with the EPL engine.
    if fromLang == "English" then
        local normalized = HyperionLanguages.preprocessEnglish(src)
        local tokens = Lexer.lex(normalized, "EPL")
        local parser = Parser.new(tokens, "EPL")
        return parser:parse()
    end
    -- C / C+ / C++ / Java: dedicated C-family parser.
    if C_FAMILY[fromLang] then
        return HyperionLanguages.parseCStyle(src, fromLang)
    end
    -- Everything else (EPL, Lua, Luau, Python) uses the built-in parser.
    local tokens = Lexer.lex(src, fromLang)
    local parser = Parser.new(tokens, fromLang)
    return parser:parse()
end

local function translateSource(src, fromLang, toLang)
    if fromLang == toLang then return src end

    local cacheKey = hashSource(src, fromLang, toLang)
    local cached = cacheGet(cacheKey)
    if cached then
        translationStats.hits = translationStats.hits + 1
        return cached
    end
    translationStats.misses = translationStats.misses + 1

    -- Bytecode source: assemble straight into IR (no AST stage).
    if fromLang == "Bytecode" then
        local irData = HyperionLanguages.parseBytecode(src)
        if #irData.instructions == 0 then
            error("[Hyperion Translator] No bytecode instructions found in source", 0)
        end
        local result
        if toLang == "IR" then
            result = HyperionIR.disassemble(irData)
        elseif toLang == "Bytecode" then
            result = HyperionLanguages.toBytecode(irData)
        else
            error("[Hyperion Translator] Bytecode source can only target 'IR' or 'Bytecode'", 0)
        end
        cacheSet(cacheKey, result)
        return result
    end

    local ast, diags = parseSourceToAST(src, fromLang)

    for _, d in ipairs(diags or {}) do
        if d.severity == "ERROR" then
            error(string.format("[Hyperion Translator] %s at Line %d, Col %d", d.message, d.line, d.col), 0)
        end
    end

    local optAST = Optimizer.optimizeAST(ast)
    local result = ""

    if toLang == "IR" then
        local irData = HyperionIR.fromAST(optAST)
        local optIR = Optimizer.optimizeIR(irData)
        result = HyperionIR.disassemble(optIR)
    elseif toLang == "Bytecode" then
        local irData = HyperionIR.fromAST(optAST)
        local optIR = Optimizer.optimizeIR(irData)
        result = HyperionLanguages.toBytecode(optIR)
    elseif toLang == "Luau" or toLang == "Lua" then
        result = TargetGen.toLuau(optAST)
    elseif toLang == "Python" then
        result = TargetGen.toPython(optAST)
    elseif toLang == "EPL" then
        result = TargetGen.toEPL(optAST)
    elseif toLang == "English" then
        result = HyperionLanguages.toEnglish(optAST)
    elseif toLang == "C" then
        result = HyperionLanguages.toC(optAST, "C")
    elseif toLang == "C+" then
        result = HyperionLanguages.toC(optAST, "C+")
    elseif toLang == "C++" then
        result = HyperionLanguages.toC(optAST, "C++")
    elseif toLang == "Java" then
        result = HyperionLanguages.toJava(optAST)
    else
        error("Unsupported target translation language: " .. tostring(toLang), 0)
    end

    cacheSet(cacheKey, result)
    return result
end

local TypeInference, IntelliSense, HyperionStdlib = (function()
-- ============================================================================
-- 12b. STATIC TYPE INFERENCE & INTELLISENSE ENGINE
--     A conservative, purely client-side type-inference pass that annotates
--     every expression with number / string / bool / nil / table / function /
--     any. It powers IDE code intelligence: completion, hover types,
--     go-to-definition, references and rename. No new Roblox services are used
--     and all diagnostics are WARNING-level so they never block compilation.
-- ============================================================================

local TypeSystem = {}
local TYPE_ANY = "any"
local TYPE_UNKNOWN = "unknown"

-- Least-upper-bound join of two inferred types (a small union model).
function TypeSystem.join(a, b)
    if a == nil or a == TYPE_UNKNOWN then return b or TYPE_UNKNOWN end
    if b == nil or b == TYPE_UNKNOWN then return a end
    if a == b then return a end
    return TYPE_ANY
end

-- Builtin global -> inferred type (return type for functions, table for modules).
local BUILTIN_TYPES = {
    ["print"] = "nil", ["warn"] = "nil", ["error"] = "nil", ["assert"] = "any",
    ["pcall"] = "any", ["xpcall"] = "any", ["select"] = "any", ["tostring"] = "string",
    ["tonumber"] = "number", ["type"] = "string", ["typeof"] = "string",
    ["pairs"] = "table", ["ipairs"] = "table", ["next"] = "any", ["rawget"] = "any",
    ["rawset"] = "table", ["setmetatable"] = "table", ["getmetatable"] = "table",
    ["string"] = "table", ["table"] = "table", ["math"] = "table", ["task"] = "table",
    ["game"] = "table", ["workspace"] = "table", ["script"] = "table", ["os"] = "table",
}

-- Member return types for the most common standard-library modules.
local MEMBER_RETURNS = {
    math = { abs = "number", ceil = "number", floor = "number", sqrt = "number",
        max = "number", min = "number", random = "number", pow = "number",
        sin = "number", cos = "number", tan = "number", round = "number",
        clamp = "number", pi = "number", huge = "number" },
    string = { len = "number", byte = "number", find = "number", format = "string",
        sub = "string", upper = "string", lower = "string", rep = "string",
        reverse = "string", gsub = "string", char = "string" },
    table = { concat = "string" },
}

-- Candidate members offered by completion for modules / value types.
local MEMBER_LISTS = {
    math = { "abs", "ceil", "floor", "sqrt", "max", "min", "random", "pow",
        "sin", "cos", "tan", "round", "clamp", "pi", "huge" },
    string = { "format", "sub", "len", "upper", "lower", "rep", "reverse",
        "find", "gsub", "byte", "char" },
    table = { "insert", "remove", "concat", "sort", "unpack", "pack", "find" },
    task = { "wait", "delay", "spawn", "defer" },
    game = { "GetService", "Players", "Workspace", "HttpService" },
}

function TypeSystem.memberReturn(moduleName, member)
    local t = moduleName and MEMBER_RETURNS[moduleName]
    if t and t[member] then return t[member] end
    return TYPE_ANY
end

function TypeSystem.valueMembers(t)
    if t == "string" then return MEMBER_LISTS.string end
    if t == "table" then return MEMBER_LISTS.table end
    if t == "number" then return MEMBER_LISTS.math end
    return {}
end

-- --- Type inference pass ----------------------------------------------------
local TypeInference = {}

-- Infer types for an AST. Returns
--   { diagnostics = {...}, symbols = {...}, nodeTypes = { [node] = type },
--     globals = { name = type } }
function TypeInference.infer(ast)
    local diagnostics, symbols, nodeTypes, globals = {}, {}, {}, {}
    local scopeStack = { {} }

    local function pushScope() table.insert(scopeStack, {}) end
    local function popScope() table.remove(scopeStack) end

    local function lookup(name)
        for i = #scopeStack, 1, -1 do
            local s = scopeStack[i][name]
            if s then return s end
        end
        return nil
    end

    local function declare(name, kind, ty, line, col)
        if not name or name == "" then return end
        scopeStack[#scopeStack][name] = { name = name, kind = kind, type = ty or TYPE_UNKNOWN, line = line or 1, col = col or 1 }
        table.insert(symbols, { name = name, kind = kind, type = ty or TYPE_UNKNOWN, line = line or 1, col = col or 1 })
        if #scopeStack == 1 then globals[name] = ty or TYPE_UNKNOWN end
    end

    local function diag(code, message, node)
        table.insert(diagnostics, {
            code = code, severity = "WARNING", stage = "Types", message = message,
            line = (node and node.line) or 1, col = (node and node.col) or 1
        })
    end

    local inferExpr

    local function inferBinary(n)
        local lt, rt = inferExpr(n.left), inferExpr(n.right)
        local op = n.op
        if op == "+" or op == "-" or op == "*" or op == "/" or op == "%" or op == "^" then
            if lt == "bool" or rt == "bool" then
                diag("TYP-001", "Arithmetic operator '" .. op .. "' used on a boolean value", n)
            elseif lt == "string" or rt == "string" then
                diag("TYP-002", "Arithmetic operator '" .. op .. "' used on a string value", n)
            end
            return "number"
        elseif op == ".." then
            if lt == "bool" or rt == "bool" then
                diag("TYP-003", "String concatenation of a boolean value", n)
            end
            return "string"
        elseif op == "==" or op == "~=" or op == "!=" or op == "<" or op == "<=" or op == ">" or op == ">=" then
            return "bool"
        elseif op == "and" or op == "or" then
            return TypeSystem.join(lt, rt)
        end
        return TYPE_UNKNOWN
    end

    inferExpr = function(n)
        if not n then return TYPE_UNKNOWN end
        local tag = n.tag
        local result = TYPE_UNKNOWN
        if tag == "number" then result = "number"
        elseif tag == "string" then result = "string"
        elseif tag == "bool" then result = "bool"
        elseif tag == "nil" then result = "nil"
        elseif tag == "ident" then
            local s = lookup(n.name)
            if s then result = s.type
            elseif BUILTIN_TYPES[n.name] then result = BUILTIN_TYPES[n.name]
            else result = TYPE_ANY end
        elseif tag == "unary" then
            inferExpr(n.operand)
            result = (n.op == "not" or n.op == "!") and "bool" or "number"
        elseif tag == "binary" then
            result = inferBinary(n)
        elseif tag == "member" then
            local ot = inferExpr(n.object)
            local moduleName = (n.object and n.object.tag == "ident") and n.object.name or nil
            if ot ~= "table" and ot ~= TYPE_ANY and ot ~= TYPE_UNKNOWN and ot ~= nil then
                diag("TYP-004", "Member access on a value of type '" .. tostring(ot) .. "'", n)
            end
            result = TypeSystem.memberReturn(moduleName, n.member)
        elseif tag == "call" then
            if n.callee and n.callee.tag == "member" then
                inferExpr(n.callee.object)
                local moduleName = (n.callee.object and n.callee.object.tag == "ident") and n.callee.object.name or nil
                result = TypeSystem.memberReturn(moduleName, n.callee.member)
            else
                local ct = inferExpr(n.callee)
                if ct ~= "function" and ct ~= TYPE_ANY and ct ~= TYPE_UNKNOWN and ct ~= nil then
                    diag("TYP-005", "Attempt to call a value of type '" .. tostring(ct) .. "'", n)
                end
                result = TYPE_ANY
            end
            for _, a in ipairs(n.args or {}) do inferExpr(a) end
        end
        nodeTypes[n] = result
        return result
    end

    local inferStatements
    inferStatements = function(stmts)
        for _, stmt in ipairs(stmts or {}) do
            local tag = stmt.tag
            if tag == "set" then
                declare(stmt.name, "variable", inferExpr(stmt.expr), stmt.line, stmt.col)
            elseif tag == "function" then
                declare(stmt.name, "function", "function", stmt.line, stmt.col)
                pushScope()
                for _, p in ipairs(stmt.params or {}) do declare(p, "parameter", TYPE_ANY, stmt.line, stmt.col) end
                inferStatements(stmt.body)
                popScope()
            elseif tag == "for" then
                inferExpr(stmt.start); inferExpr(stmt.limit); inferExpr(stmt.step)
                pushScope()
                if not stmt.hidden then declare(stmt.var, "variable", "number", stmt.line, stmt.col) end
                inferStatements(stmt.body)
                popScope()
            elseif tag == "if" then
                inferExpr(stmt.cond)
                pushScope(); inferStatements(stmt.thenBody); popScope()
                pushScope(); inferStatements(stmt.elseBody); popScope()
            elseif tag == "while" then
                inferExpr(stmt.cond)
                pushScope(); inferStatements(stmt.body); popScope()
            elseif tag == "return" then
                inferExpr(stmt.expr)
            elseif tag == "print" or tag == "calculate" or tag == "wait" then
                inferExpr(stmt.expr)
                for _, a in ipairs(stmt.args or {}) do inferExpr(a) end
            elseif tag == "expr_stmt" then
                inferExpr(stmt.expr)
            end
        end
    end

    inferStatements(ast and ast.body or {})
    return { diagnostics = diagnostics, symbols = symbols, nodeTypes = nodeTypes, globals = globals }
end

-- --- IntelliSense: completion, hover, definition, references, rename --------
local IntelliSense = { _cache = { key = nil, lang = nil, data = nil } }

local function buildLineStarts(src)
    local starts = { 1 }
    local pos = 1
    while true do
        local nl = src:find("\n", pos, true)
        if not nl then break end
        table.insert(starts, nl + 1)
        pos = nl + 1
    end
    return starts
end

local function languageKeywords(lang)
    local list = {}
    local set
    if lang == "EPL" then set = EPL_KEYWORDS
    elseif lang == "Python" then set = PY_KEYWORDS
    elseif lang == "English" then set = HyperionLanguages.ENGLISH_KEYWORDS
    elseif C_FAMILY[lang] then set = HyperionLanguages.CXX_KEYWORDS
    elseif lang == "Bytecode" then
        for _, op in ipairs(HyperionLanguages.BYTECODE_OPCODES or {}) do table.insert(list, op) end
        return list
    else set = LUA_KEYWORDS end
    for k in pairs(set or {}) do table.insert(list, k) end
    table.sort(list)
    return list
end

-- Analyze a source buffer once and cache the result by (source, lang) hash.
function IntelliSense.analyze(source, lang)
    lang = lang or "EPL"
    local key = hashSource(source, lang, "IS")
    local cache = IntelliSense._cache
    if cache.key == key and cache.lang == lang then return cache.data end

    local data = { source = source, lang = lang, tokens = {}, ast = nil,
        diagnostics = {}, symbols = {}, nodeTypes = {}, ok = false }

    local okTok, tokens = pcall(Lexer.lex, source, lang)
    if okTok and type(tokens) == "table" then data.tokens = tokens end

    local okAst, ast = pcall(parseSourceToAST, source, lang)
    if okAst and type(ast) == "table" then
        data.ast = ast
        data.ok = true
        local okSem, semDiags = pcall(SemanticAnalyzer.analyze, ast)
        if okSem and type(semDiags) == "table" then
            for _, d in ipairs(semDiags) do table.insert(data.diagnostics, d) end
        end
        local okTypes, tr = pcall(TypeInference.infer, ast)
        if okTypes and type(tr) == "table" then
            data.nodeTypes = tr.nodeTypes or {}
            data.symbols = tr.symbols or {}
            for _, d in ipairs(tr.diagnostics or {}) do table.insert(data.diagnostics, d) end
        end
    end

    -- Fallback: derive a symbol list from the token stream if parsing failed.
    if #data.symbols == 0 then
        local seen = {}
        for _, t in ipairs(data.tokens) do
            if t.kind == "IDENT" and not seen[t.value] then
                seen[t.value] = true
                table.insert(data.symbols, { name = t.value, kind = "identifier", type = TYPE_ANY, line = t.line, col = t.col })
            end
        end
    end

    cache.key, cache.lang, cache.data = key, lang, data
    return data
end

function IntelliSense.typeOfName(data, name)
    if not name then return nil end
    if BUILTIN_TYPES[name] then return BUILTIN_TYPES[name] end
    for _, s in ipairs(data.symbols or {}) do
        if s.name == name then return s.type end
    end
    return nil
end

local function tokenAt(tokens, line, col)
    for _, t in ipairs(tokens) do
        if t.line == line then
            local c0 = t.col or 1
            local c1 = c0 + #tostring(t.value) - 1
            if col >= c0 and col <= c1 then return t end
        elseif t.line and t.line > line then
            break
        end
    end
    return nil
end

-- Completion. Detects member access (after '.') vs. symbol/keyword completion.
function IntelliSense.complete(source, line, col, lang)
    local data = IntelliSense.analyze(source, lang)
    local starts = buildLineStarts(source)
    local lineStart = starts[line] or 1
    local before = source:sub(lineStart, lineStart + col - 2)
    local word = before:match("([%a_][%w_]*)$") or ""
    local prefixStartCol = col - #word
    local items, seen = {}, {}

    local function add(label, kind, ty)
        if not label or seen[label] then return end
        seen[label] = true
        table.insert(items, { label = label, kind = kind, type = ty or "" })
    end

    if before:match("%.$") then
        local base = before:match("([%a_][%w_]*)%.$")
        local members = MEMBER_LISTS[base or ""]
        if not members then members = TypeSystem.valueMembers(IntelliSense.typeOfName(data, base)) end
        for _, m in ipairs(members or {}) do add(m, "member", "any") end
        return { items = items, prefix = word, prefixStartCol = prefixStartCol, mode = "member" }
    end

    for _, kw in ipairs(languageKeywords(lang)) do add(kw, "keyword", "") end
    for _, s in ipairs(data.symbols or {}) do add(s.name, s.kind or "variable", s.type) end
    for name, ty in pairs(BUILTIN_TYPES) do add(name, "builtin", ty) end

    local lower = word:lower()
    local filtered = {}
    for _, it in ipairs(items) do
        if lower == "" or it.label:lower():sub(1, #lower) == lower then
            table.insert(filtered, it)
        end
        if #filtered >= 100 then break end
    end
    return { items = filtered, prefix = word, prefixStartCol = prefixStartCol, mode = "symbol" }
end

function IntelliSense.hover(source, line, col, lang)
    local data = IntelliSense.analyze(source, lang)
    local tok = tokenAt(data.tokens, line, col)
    if not tok or tok.kind ~= "IDENT" then return nil end
    local decl
    for _, s in ipairs(data.symbols or {}) do
        if s.name == tok.value then decl = s; break end
    end
    return {
        name = tok.value,
        type = decl and decl.type or (BUILTIN_TYPES[tok.value] or TYPE_ANY),
        kind = decl and decl.kind or "identifier",
        line = decl and decl.line or nil,
        col = decl and decl.col or nil
    }
end

function IntelliSense.definition(source, line, col, lang)
    local data = IntelliSense.analyze(source, lang)
    local tok = tokenAt(data.tokens, line, col)
    if not tok or tok.kind ~= "IDENT" then return nil end
    for _, s in ipairs(data.symbols or {}) do
        if s.name == tok.value then return { name = s.name, line = s.line, col = s.col, type = s.type } end
    end
    return nil
end

function IntelliSense.references(source, line, col, lang)
    local data = IntelliSense.analyze(source, lang)
    local tok = tokenAt(data.tokens, line, col)
    if not tok or tok.kind ~= "IDENT" then return nil end
    local refs = {}
    for _, t in ipairs(data.tokens) do
        if t.kind == "IDENT" and t.value == tok.value then
            table.insert(refs, { line = t.line, col = t.col })
        end
    end
    return { name = tok.value, refs = refs }
end

function IntelliSense.rename(source, line, col, newName, lang)
    if type(newName) ~= "string" or not newName:match("^[%a_][%w_]*$") then
        return nil, "Invalid identifier"
    end
    local data = IntelliSense.analyze(source, lang)
    local tok = tokenAt(data.tokens, line, col)
    if not tok or tok.kind ~= "IDENT" then return nil, "No identifier at cursor" end
    if tok.value == newName then return source, 0 end
    local starts = buildLineStarts(source)
    local edits = {}
    for _, t in ipairs(data.tokens) do
        if t.kind == "IDENT" and t.value == tok.value then
            local start = (starts[t.line] or 1) + (t.col or 1) - 1
            table.insert(edits, { start = start, len = #t.value })
        end
    end
    table.sort(edits, function(a, b) return a.start > b.start end)
    local out = source
    for _, e in ipairs(edits) do
        out = out:sub(1, e.start - 1) .. newName .. out:sub(e.start + e.len)
    end
    return out, #edits
end

-- ---------------------------------------------------------------------------
-- 12c. HYPERION STANDARD LIBRARY
-- A pure, sandbox-safe library exposed to every program as the global `std`.
-- It deliberately avoids anything with side effects (no io/os/loadstring), so
-- it is safe inside the VM sandbox. A sibling ModuleScript named
-- 'HyperionStdlib' may override it (same pattern as HyperionBase64).
-- ---------------------------------------------------------------------------
local HyperionStdlib = {}
HyperionStdlib.VERSION = "1.0.0"

local function num(v) return tonumber(v) or 0 end
local function isTable(v) return type(v) == "table" end

HyperionStdlib.math = {
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
        return HyperionStdlib.math.sum(t) / #t
    end
}

HyperionStdlib.list = {
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
    sum = function(t) return HyperionStdlib.math.sum(t) end,
    range = function(a, b, step)
        a, b = math.floor(num(a)), math.floor(num(b))
        step = math.floor(num(step))
        if step == 0 then step = 1 end
        local out = {}
        if step > 0 then
            for i = a, b, step do table.insert(out, i) end
        else
            for i = a, b, step do table.insert(out, i) end
        end
        return out
    end
}

HyperionStdlib.string = {
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
    join = function(t, sep) return HyperionStdlib.list.join(t, sep) end,
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
    reverse = function(s)
        s = tostring(s or "")
        return s:reverse()
    end,
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
        s = tostring(s or "")
        ch = tostring(ch or " ")
        len = math.floor(num(len))
        while #s < len do s = ch .. s end
        return s
    end,
    padEnd = function(s, len, ch)
        s = tostring(s or "")
        ch = tostring(ch or " ")
        len = math.floor(num(len))
        while #s < len do s = s .. ch end
        return s
    end
}

HyperionStdlib.table = {
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

HyperionStdlib.util = {
    range = function(a, b, step) return HyperionStdlib.list.range(a, b, step) end,
    identity = function(v) return v end,
    noop = function() end
}

-- Optional ModuleScript override (named 'HyperionStdlib' beside this script).
do
    local module = script:FindFirstChild("HyperionStdlib")
    if module and module:IsA("ModuleScript") then
        local ok, loaded = pcall(require, module)
        if ok and type(loaded) == "table" then
            HyperionStdlib = loaded
        end
    end
end

return TypeInference, IntelliSense, HyperionStdlib
end)()

-- ============================================================================
-- 13. HARDENED SANDBOXED VM (Call Frames, Scopes, Strict Watchdog, Debugger)
-- ============================================================================
local VM = {
    state = "IDLE", -- "IDLE", "RUNNING", "PAUSED", "HALTED"
    pc = 1,
    registers = {},
    environment = {},
    callStack = {},
    functions = {},
    breakpoints = {},
    instructions = {},
    constants = {},
    outputBytes = 0,
    instructionsExecuted = 0,
    startTime = 0,
    deadline = 0,
    onOutput = nil,
    onHalt = nil,
    onPause = nil,
    lastError = nil,
    -- Profiler / debugger extensions
    lineHits = {},
    trace = {},
    traceEnabled = false,
    traceLimit = 20000,
    suppressOutput = false,
    watchList = {},
    breakpointConds = {},
    initialEnv = nil,
    documentProvider = nil,
    requireCache = {}
}

local VALID_OPCODES = {
    LOADK=true, LOADBOOL=true, LOADNIL=true, MOVE=true, DECLARE_LOCAL=true,
    LOAD=true, STORE=true, ADD=true, SUB=true, MUL=true, DIV=true, MOD=true,
    POW=true, EQ=true, NEQ=true, LT=true, LE=true, GT=true, GE=true,
    AND=true, OR=true, NOT=true, UNM=true, CONCAT=true, MEMBER=true,
    DEF_FN=true, CALL=true, RETURN=true, PRINT=true, WAIT=true,
    JMP=true, JMPIF=true, JMPNOT=true
}

validateIR = function(irData)
    if type(irData) ~= "table" or type(irData.instructions) ~= "table" then
        return false, "IR is missing its instruction array"
    end
    if type(irData.regCount) ~= "number" or irData.regCount < 0 or irData.regCount % 1 ~= 0 or irData.regCount > CONFIG.MAX_REGISTERS then
        return false, "IR register count is invalid"
    end
    if type(irData.constants) ~= "table" or #irData.constants > CONFIG.MAX_CONSTANTS then
        return false, "IR constant table is invalid or too large"
    end
    local count = #irData.instructions
    if count == 0 then
        return false, "IR contains no instructions"
    end
    if count > CONFIG.MAX_IR_INSTRUCTIONS then
        return false, string.format("IR contains %d instructions; maximum is %d", count, CONFIG.MAX_IR_INSTRUCTIONS)
    end
    if type(irData.regCount) == "number" and (irData.regCount < 0 or irData.regCount > CONFIG.MAX_REGISTERS) then
        return false, string.format("IR register count is outside the safe range: %s", tostring(irData.regCount))
    end
    for i, inst in ipairs(irData.instructions) do
        if type(inst) ~= "table" or type(inst.op) ~= "string" or not VALID_OPCODES[inst.op] then
            return false, string.format("Invalid opcode at instruction %d", i)
        end
        if inst.idx ~= nil and (type(inst.idx) ~= "number" or inst.idx ~= i - 1) then
            return false, string.format("Invalid instruction index at instruction %d", i)
        end
        if inst.line ~= nil and type(inst.line) ~= "number" then
            return false, string.format("Invalid source line at instruction %d", i)
        end
        local function validReg(value)
            if type(value) ~= "string" then return false end
            local n = tonumber(value:match("^R(%d+)$"))
            return n ~= nil and n % 1 == 0 and n >= 0 and n < irData.regCount
        end
        local function requireReg(value, label)
            if not validReg(value) then
                return false, string.format("Invalid %s register at instruction %d", label, i)
            end
            return true
        end
        if inst.op == "LOADK" or inst.op == "LOADBOOL" or inst.op == "LOADNIL" or inst.op == "PRINT" or inst.op == "WAIT" or inst.op == "DECLARE_LOCAL" then
            if inst.op ~= "DECLARE_LOCAL" then
                local okReg, msg = requireReg(inst.a, "destination")
                if not okReg then return false, msg end
            elseif type(inst.a) ~= "string" or inst.a == "" then
                return false, string.format("Invalid local name at instruction %d", i)
            end
        elseif inst.op == "MOVE" then
            local okA, msgA = requireReg(inst.a, "destination"); if not okA then return false, msgA end
            local okB, msgB = requireReg(inst.b, "source"); if not okB then return false, msgB end
        elseif inst.op == "LOAD" then
            local okA, msgA = requireReg(inst.a, "destination"); if not okA then return false, msgA end
            if type(inst.b) ~= "string" or inst.b == "" then return false, string.format("Invalid load name at instruction %d", i) end
        elseif inst.op == "STORE" then
            if type(inst.a) ~= "string" or inst.a == "" then return false, string.format("Invalid store name at instruction %d", i) end
            local okB, msgB = requireReg(inst.b, "source"); if not okB then return false, msgB end
        elseif inst.op == "ADD" or inst.op == "SUB" or inst.op == "MUL" or inst.op == "DIV" or inst.op == "MOD" or inst.op == "POW" or inst.op == "EQ" or inst.op == "NEQ" or inst.op == "LT" or inst.op == "LE" or inst.op == "GT" or inst.op == "GE" or inst.op == "AND" or inst.op == "OR" or inst.op == "CONCAT" then
            local okA, msgA = requireReg(inst.a, "destination"); if not okA then return false, msgA end
            local okB, msgB = requireReg(inst.b, "left/source"); if not okB then return false, msgB end
            local okC, msgC = requireReg(inst.c, "right/source"); if not okC then return false, msgC end
        elseif inst.op == "NOT" or inst.op == "UNM" then
            local okA, msgA = requireReg(inst.a, "destination"); if not okA then return false, msgA end
            local okB, msgB = requireReg(inst.b, "source"); if not okB then return false, msgB end
        elseif inst.op == "MEMBER" then
            local okA, msgA = requireReg(inst.a, "destination"); if not okA then return false, msgA end
            local okB, msgB = requireReg(inst.b, "object"); if not okB then return false, msgB end
            if type(inst.c) ~= "string" or inst.c == "" then return false, string.format("Invalid member name at instruction %d", i) end
        elseif inst.op == "CALL" then
            local okA, msgA = requireReg(inst.a, "destination"); if not okA then return false, msgA end
            if type(inst.b) ~= "string" or inst.b == "" then return false, string.format("Invalid call target at instruction %d", i) end
            if inst.c then
                for arg in inst.c:gmatch("[^,]+") do
                    local okArg, msgArg = requireReg(arg, "argument")
                    if not okArg then return false, msgArg end
                end
            end
        elseif inst.op == "RETURN" then
            if inst.a ~= nil and inst.a ~= "nil" then
                local okA, msgA = requireReg(inst.a, "return"); if not okA then return false, msgA end
            end
        elseif inst.op == "JMPIF" or inst.op == "JMPNOT" then
            local okA, msgA = requireReg(inst.a, "condition"); if not okA then return false, msgA end
        end
        if inst.op == "JMP" then
            local target = tonumber(inst.a)
            if not target or target % 1 ~= 0 or target < 0 or target >= count then
                return false, string.format("Invalid JMP target at instruction %d", i)
            end
        elseif inst.op == "JMPIF" or inst.op == "JMPNOT" then
            local target = tonumber(inst.b)
            if not target or target % 1 ~= 0 or target < 0 or target >= count then
                return false, string.format("Invalid conditional jump target at instruction %d", i)
            end
        elseif inst.op == "DEF_FN" then
            local target = tonumber(inst.b)
            if not target or target % 1 ~= 0 or target < 0 or target >= count then
                return false, string.format("Invalid function entry at instruction %d", i)
            end
        elseif inst.op == "LOADK" and type(inst.c) == "string" and inst.c:sub(1, 1) == "K" then
            local k = tonumber(inst.c:sub(2))
            if not k or k % 1 ~= 0 or k < 0 or not irData.constants or irData.constants[k + 1] == nil then
                return false, string.format("Invalid constant reference at instruction %d", i)
            end
        elseif inst.op == "CALL" and inst.c ~= nil and type(inst.c) ~= "string" then
            return false, string.format("Invalid CALL argument encoding at instruction %d", i)
        end
    end
    return true
end

function VM.init(irData, customEnv)
    local valid, validationError = validateIR(irData)
    if not valid then
        error("[Hyperion IR] " .. validationError, 0)
    end
    VM.lastError = nil
    VM.instructions = irData.instructions
    VM.constants = irData.constants or {}
    VM.regCount = irData.regCount or 0
    VM.deadline = os.clock() + CONFIG.MAX_RUNTIME_SEC
    VM.pc = 1
    VM.registers = {}
    VM.callStack = {}
    VM.functions = {}
    VM.breakpoints = {}
    VM.outputBytes = 0
    VM.instructionsExecuted = 0
    VM.state = "IDLE"
    VM.lineHits = {}
    VM.trace = {}
    VM.suppressOutput = false
    VM.initialEnv = customEnv

    -- Sandboxed Safe Environment.
    -- string.rep / string.format / table.concat are wrapped so a program cannot
    -- allocate an unbounded amount of memory before the output watchdog fires.
    local function tooLarge(result)
        if type(result) == "string" and #result > CONFIG.MAX_OUTPUT_BYTES then
            VM.state = "HALTED"
            error("[Hyperion VM] Result exceeds the sandbox size limit (10 KB).", 0)
        end
        return result
    end
    local safeString = {}
    for k, v in pairs(string) do safeString[k] = v end
    safeString.rep = function(s, n)
        n = tonumber(n) or 0
        if n < 0 then error("[Hyperion VM] string.rep count must be non-negative", 0) end
        if #tostring(s) * n > CONFIG.MAX_OUTPUT_BYTES then
            VM.state = "HALTED"
            error("[Hyperion VM] string.rep result would exceed the sandbox size limit.", 0)
        end
        return string.rep(s, n)
    end
    safeString.format = function(fmt, ...)
        if type(fmt) == "string" then
            -- Reject any width/precision that could allocate an enormous string
            -- before string.format is allowed to run.
            for spec in fmt:gmatch("%%[%-%+ #0]*%d*%.?%d*[a-zA-Z]") do
                for digits in spec:gmatch("%d+") do
                    local n = tonumber(digits)
                    if n and n > 100000 then
                        VM.state = "HALTED"
                        error("[Hyperion VM] string.format width/precision too large.", 0)
                    end
                end
            end
        end
        return tooLarge(string.format(fmt, ...))
    end
    local safeTable = {}
    for k, v in pairs(table) do safeTable[k] = v end
    safeTable.concat = function(t, sep, i, j)
        if type(t) == "table" then
            local joiner = sep == nil and "" or tostring(sep)
            local from, to = i or 1, j or #t
            local total = 0
            for k = from, to do total = total + #tostring(t[k]) end
            total = total + #joiner * math.max(0, to - from)
            if total > CONFIG.MAX_OUTPUT_BYTES then
                VM.state = "HALTED"
                error("[Hyperion VM] table.concat result would exceed the sandbox size limit.", 0)
            end
        end
        return tooLarge(table.concat(t, sep, i, j))
    end

    VM.environment = {
        math = math,
        string = safeString,
        table = safeTable,
        task = { wait = task.wait },
        tostring = tostring,
        tonumber = tonumber,
        type = type,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do table.insert(parts, tostring(select(i, ...))) end
            local outStr = table.concat(parts, "\t")
            VM.outputBytes = VM.outputBytes + #outStr
            if VM.outputBytes > CONFIG.MAX_OUTPUT_BYTES then
                VM.state = "HALTED"
                error("[Hyperion VM] Execution stopped: maximum output size (10 KB) exceeded.", 0)
            end
            if VM.onOutput and not VM.suppressOutput then VM.onOutput(outStr) end
        end,
        std = HyperionStdlib,
        require = function(name) return VM.requireModule(name) end
    }

    if customEnv then
        for k, v in pairs(customEnv) do VM.environment[k] = v end
    end
end

-- table.unpack on modern Luau, unpack as a legacy fallback.
local unpackArgs = table.unpack or unpack
local packArgs = table.pack or function(...) return { n = select("#", ...), ... } end

local function isTruthy(value)
    return value ~= nil and value ~= false
end

local function getScopedValue(frame, name)
    local depth = 0
    local cursor = frame
    while cursor do
        depth = depth + 1
        if depth > CONFIG.MAX_CLOSURE_DEPTH then
            error("[Hyperion VM] Closure scope depth exceeded", 0)
        end
        if cursor.declaredLocals[name] then
            return cursor.locals[name]
        end
        cursor = cursor.parent
    end
    return VM.environment[name]
end

local function setScopedValue(frame, name, value)
    local depth = 0
    local cursor = frame
    while cursor do
        depth = depth + 1
        if depth > CONFIG.MAX_CLOSURE_DEPTH then
            error("[Hyperion VM] Closure scope depth exceeded", 0)
        end
        if cursor.declaredLocals[name] then
            cursor.locals[name] = value
            return
        end
        cursor = cursor.parent
    end
    VM.environment[name] = value
end

-- Resolve a dotted name like "math.floor" against the sandboxed environment.
local function resolveDotted(env, dottedName)
    local current = env
    for part in dottedName:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[part]
        if current == nil then return nil end
    end
    return current
end

local function expectComparable(a, b, operation, inst)
    local ta, tb = type(a), type(b)
    if (ta ~= "number" and ta ~= "string") or (tb ~= "number" and tb ~= "string") or ta ~= tb then
        VM.state = "HALTED"
        error(string.format("Runtime error at L%d:C%d: %s requires matching number or string operands, got %s and %s",
            inst.line or 1, inst.col or 1, operation, ta, tb), 0)
    end
    return a, b
end

local function expectNumber(value, operation, inst, operandName)
    if type(value) == "number" then return value end
    if type(value) == "string" then
        local converted = tonumber(value)
        if converted ~= nil then return converted end
    end
    VM.state = "HALTED"
    error(string.format("Runtime error at L%d:C%d: %s requires a numeric value for %s, got %s",
        inst.line or 1, inst.col or 1, operation, operandName or "operand", type(value)), 0)
end

function VM.step()
    if VM.state == "HALTED" or VM.state == "PAUSED" then
        return false
    end
    if VM.pc < 1 then
        VM.state = "HALTED"
        error(string.format("VM ERROR: Program counter out of bounds (%s)", tostring(VM.pc)), 0)
    elseif VM.pc > #VM.instructions then
        VM.state = "HALTED"
        if VM.onHalt then VM.onHalt("Execution finished") end
        return false
    end

    VM.instructionsExecuted = VM.instructionsExecuted + 1

    if VM.instructionsExecuted > CONFIG.MAX_INSTRUCTIONS then
        VM.state = "HALTED"
        error(string.format("[Hyperion Watchdog] Instruction budget exceeded (%d ops)", CONFIG.MAX_INSTRUCTIONS), 0)
    end
    if os.clock() > VM.deadline then
        VM.state = "HALTED"
        error(string.format("[Hyperion Watchdog] Runtime budget exceeded (%.2f s)", CONFIG.MAX_RUNTIME_SEC), 0)
    end

    local inst = VM.instructions[VM.pc]
    local op = inst.op

    -- Line-level profiling + optional execution trace (time-travel debugger).
    if inst.line then
        VM.lineHits[inst.line] = (VM.lineHits[inst.line] or 0) + 1
    end
    if VM.traceEnabled then
        if #VM.trace >= VM.traceLimit then
            local keep = math.floor(VM.traceLimit / 2)
            local trimmed = {}
            local n = #VM.trace
            for i = n - keep + 1, n do table.insert(trimmed, VM.trace[i]) end
            VM.trace = trimmed
        end
        table.insert(VM.trace, { pc = VM.pc, line = inst.line, op = op })
    end
    -- Breakpoint check
    if VM.breakpoints[inst.line] and VM.state == "RUNNING" and VM.instructionsExecuted > 1 then
        local shouldPause = true
        local cond = VM.breakpointConds[inst.line]
        if cond and cond ~= "" then
            local okCond, condValue = pcall(VM.evalCondition, cond)
            shouldPause = okCond and isTruthy(condValue)
        end
        if shouldPause then
            VM.state = "PAUSED"
            if VM.onPause then VM.onPause(inst.line, inst.idx) end
            return false
        end
    end

    -- Execute Opcodes
    if op == "LOADK" then
        local value = inst.b
        if type(inst.c) == "string" and inst.c:sub(1, 1) == "K" then
            local k = tonumber(inst.c:sub(2))
            if k ~= nil and VM.constants[k + 1] ~= nil then
                value = VM.constants[k + 1]
            end
        end
        VM.registers[inst.a] = value
        VM.pc = VM.pc + 1
    elseif op == "LOADBOOL" then
        VM.registers[inst.a] = (inst.b == "true")
        VM.pc = VM.pc + 1
    elseif op == "LOADNIL" then
        VM.registers[inst.a] = nil
        VM.pc = VM.pc + 1
    elseif op == "MOVE" then
        VM.registers[inst.a] = VM.registers[inst.b]
        VM.pc = VM.pc + 1
    elseif op == "DECLARE_LOCAL" then
        if #VM.callStack > 0 then
            local frame = VM.callStack[#VM.callStack]
            frame.declaredLocals[inst.a] = true
            frame.locals[inst.a] = nil
        end
        VM.pc = VM.pc + 1
    elseif op == "LOAD" then
        local frame = #VM.callStack > 0 and VM.callStack[#VM.callStack] or nil
        if frame then
            VM.registers[inst.a] = getScopedValue(frame, inst.b)
        else
            VM.registers[inst.a] = VM.environment[inst.b]
        end
        VM.pc = VM.pc + 1
    elseif op == "STORE" then
        local val = VM.registers[inst.b]
        local frame = #VM.callStack > 0 and VM.callStack[#VM.callStack] or nil
        if frame then
            setScopedValue(frame, inst.a, val)
        else
            VM.environment[inst.a] = val
        end
        VM.pc = VM.pc + 1
    elseif op == "ADD" then
        local a = expectNumber(VM.registers[inst.b], "ADD", inst, "left operand")
        local b = expectNumber(VM.registers[inst.c], "ADD", inst, "right operand")
        VM.registers[inst.a] = a + b
        VM.pc = VM.pc + 1
    elseif op == "SUB" then
        local a = expectNumber(VM.registers[inst.b], "SUB", inst, "left operand")
        local b = expectNumber(VM.registers[inst.c], "SUB", inst, "right operand")
        VM.registers[inst.a] = a - b
        VM.pc = VM.pc + 1
    elseif op == "MUL" then
        local a = expectNumber(VM.registers[inst.b], "MUL", inst, "left operand")
        local b = expectNumber(VM.registers[inst.c], "MUL", inst, "right operand")
        VM.registers[inst.a] = a * b
        VM.pc = VM.pc + 1
    elseif op == "DIV" then
        local a = expectNumber(VM.registers[inst.b], "DIV", inst, "left operand")
        local d = expectNumber(VM.registers[inst.c], "DIV", inst, "denominator")
        if d == 0 then
            VM.state = "HALTED"
            error(string.format("Runtime error at L%d:C%d: Division by zero", inst.line or 1, inst.col or 1), 0)
        end
        VM.registers[inst.a] = a / d
        VM.pc = VM.pc + 1
    elseif op == "MOD" then
        local a = expectNumber(VM.registers[inst.b], "MOD", inst, "left operand")
        local d = expectNumber(VM.registers[inst.c], "MOD", inst, "denominator")
        if d == 0 then
            VM.state = "HALTED"
            error(string.format("Runtime error at L%d:C%d: Modulo by zero", inst.line or 1, inst.col or 1), 0)
        end
        VM.registers[inst.a] = a % d
        VM.pc = VM.pc + 1
    elseif op == "POW" then
        local a = expectNumber(VM.registers[inst.b], "POW", inst, "base")
        local b = expectNumber(VM.registers[inst.c], "POW", inst, "exponent")
        VM.registers[inst.a] = a ^ b
        VM.pc = VM.pc + 1
    elseif op == "EQ" then
        VM.registers[inst.a] = (VM.registers[inst.b] == VM.registers[inst.c])
        VM.pc = VM.pc + 1
    elseif op == "NEQ" then
        VM.registers[inst.a] = (VM.registers[inst.b] ~= VM.registers[inst.c])
        VM.pc = VM.pc + 1
    elseif op == "LT" then
        local a, b = expectComparable(VM.registers[inst.b], VM.registers[inst.c], "LT", inst)
        VM.registers[inst.a] = (a < b)
        VM.pc = VM.pc + 1
    elseif op == "LE" then
        local a, b = expectComparable(VM.registers[inst.b], VM.registers[inst.c], "LE", inst)
        VM.registers[inst.a] = (a <= b)
        VM.pc = VM.pc + 1
    elseif op == "GT" then
        local a, b = expectComparable(VM.registers[inst.b], VM.registers[inst.c], "GT", inst)
        VM.registers[inst.a] = (a > b)
        VM.pc = VM.pc + 1
    elseif op == "GE" then
        local a, b = expectComparable(VM.registers[inst.b], VM.registers[inst.c], "GE", inst)
        VM.registers[inst.a] = (a >= b)
        VM.pc = VM.pc + 1
    elseif op == "AND" then
        VM.registers[inst.a] = VM.registers[inst.b] and VM.registers[inst.c]
        VM.pc = VM.pc + 1
    elseif op == "OR" then
        VM.registers[inst.a] = VM.registers[inst.b] or VM.registers[inst.c]
        VM.pc = VM.pc + 1
    elseif op == "NOT" then
        VM.registers[inst.a] = not VM.registers[inst.b]
        VM.pc = VM.pc + 1
    elseif op == "UNM" then
        local value = expectNumber(VM.registers[inst.b], "UNM", inst, "operand")
        VM.registers[inst.a] = -value
        VM.pc = VM.pc + 1
    elseif op == "CONCAT" then
        local left, right = VM.registers[inst.b], VM.registers[inst.c]
        local function concatValue(value, operandName)
            local valueType = type(value)
            if valueType == "string" or valueType == "number" then return tostring(value) end
            VM.state = "HALTED"
            error(string.format("Runtime error at L%d:C%d: CONCAT requires string or number for %s, got %s",
                inst.line or 1, inst.col or 1, operandName, valueType), 0)
        end
        VM.registers[inst.a] = concatValue(left, "left operand") .. concatValue(right, "right operand")
        VM.pc = VM.pc + 1
    elseif op == "MEMBER" then
        local obj = VM.registers[inst.b]
        if type(inst.c) ~= "string" or inst.c == "" then
            VM.state = "HALTED"
            error(string.format("Runtime error at L%d:C%d: Invalid member name", inst.line or 1, inst.col or 1), 0)
        end
        if type(obj) == "table" then
            VM.registers[inst.a] = obj[inst.c]
        else
            VM.state = "HALTED"
            error(string.format("Runtime error at L%d:C%d: Cannot index %s with '%s'", inst.line, inst.col, type(obj), tostring(inst.c)), 0)
        end
        VM.pc = VM.pc + 1
    elseif op == "DEF_FN" then
        VM.functions[inst.a] = {
            pc = tonumber(inst.b),
            params = inst.c,
            closure = #VM.callStack > 0 and VM.callStack[#VM.callStack] or nil
        }
        VM.pc = VM.pc + 1
    elseif op == "CALL" then
        local fnName = inst.b
        local fnInfo = VM.functions[fnName]
        local envFn = nil
        if not fnInfo then
            envFn = resolveDotted(VM.environment, fnName)
        end
        if fnInfo then
            if type(inst.c) ~= "string" and inst.c ~= nil then
                VM.state = "HALTED"
                error(string.format("Runtime error at L%d:C%d: Malformed CALL argument list", inst.line or 1, inst.col or 1), 0)
            end
            if #VM.callStack >= CONFIG.MAX_RECURSION_DEPTH then
                VM.state = "HALTED"
                error(string.format("Runtime error at L%d:C%d: Maximum recursion depth (%d) exceeded", inst.line, inst.col, CONFIG.MAX_RECURSION_DEPTH), 0)
            end
            local callerRegisters = VM.registers
            local locals = {}
            local declaredLocals = {}
            local argNames = {}
            if fnInfo.params then
                for p in fnInfo.params:gmatch("[^,]+") do
                    table.insert(argNames, p)
                    declaredLocals[p] = true
                end
            end
            local argVals = {}
            if inst.c and inst.c ~= "" then
                for a in inst.c:gmatch("[^,]+") do
                    if #argVals >= CONFIG.MAX_CALL_ARGS then
                        VM.state = "HALTED"
                        error(string.format("Runtime error at L%d:C%d: Call argument limit (%d) exceeded",
                            inst.line or 1, inst.col or 1, CONFIG.MAX_CALL_ARGS), 0)
                    end
                    table.insert(argVals, VM.registers[a])
                end
            end
            if #argVals > #argNames then
                VM.state = "HALTED"
                error(string.format("Runtime error at L%d:C%d: Too many arguments for '%s' (expected %d, got %d)",
                    inst.line or 1, inst.col or 1, fnName, #argNames, #argVals), 0)
            end
            for idx, name in ipairs(argNames) do
                locals[name] = argVals[idx]
            end
            table.insert(VM.callStack, {
                returnPC = VM.pc + 1,
                returnReg = inst.a,
                callerRegisters = callerRegisters,
                locals = locals,
                declaredLocals = declaredLocals,
                parent = fnInfo.closure,
                name = fnName
            })
            VM.registers = {}
            VM.pc = fnInfo.pc + 1
        elseif envFn ~= nil and type(envFn) == "function" then
            local args = {}
            if inst.c and inst.c ~= "" then
                for a in inst.c:gmatch("[^,]+") do
                    if #args >= CONFIG.MAX_CALL_ARGS then
                        VM.state = "HALTED"
                        error(string.format("Runtime error at L%d:C%d: Call argument limit (%d) exceeded",
                            inst.line or 1, inst.col or 1, CONFIG.MAX_CALL_ARGS), 0)
                    end
                    table.insert(args, VM.registers[a])
                end
            end
            VM.registers[inst.a] = envFn(unpackArgs(args))
            VM.pc = VM.pc + 1
        else
            VM.state = "HALTED"
            error(string.format("Runtime error at L%d:C%d: Attempt to call undefined function '%s'", inst.line, inst.col, tostring(fnName)), 0)
        end
    elseif op == "RETURN" then
        local retVal = nil
        if inst.a and inst.a ~= "nil" then retVal = VM.registers[inst.a] end
        if #VM.callStack > 0 then
            local frame = table.remove(VM.callStack)
            VM.registers = frame.callerRegisters
            if frame.returnReg then VM.registers[frame.returnReg] = retVal end
            VM.pc = frame.returnPC
        else
            VM.state = "HALTED"
            if VM.onHalt then VM.onHalt("Finished") end
            return false
        end
    elseif op == "PRINT" then
        local val = VM.registers[inst.a]
        VM.environment.print(val)
        VM.pc = VM.pc + 1
    elseif op == "WAIT" then
        local sec = expectNumber(VM.registers[inst.a], "WAIT", inst, "seconds")
        if sec < 0 then
            VM.state = "HALTED"
            error(string.format("Runtime error at L%d:C%d: WAIT requires non-negative seconds", inst.line or 1, inst.col or 1), 0)
        end
        local remaining = VM.deadline - os.clock()
        if remaining <= 0 then
            VM.state = "HALTED"
            error("[Hyperion Watchdog] Runtime budget exceeded in wait", 0)
        end
        task.wait(math.clamp(sec, 0, math.min(1.0, remaining)))
        VM.pc = VM.pc + 1
    elseif op == "JMP" then
        VM.pc = tonumber(inst.a) + 1
    elseif op == "JMPIF" then
        if isTruthy(VM.registers[inst.a]) then VM.pc = tonumber(inst.b) + 1 else VM.pc = VM.pc + 1 end
    elseif op == "JMPNOT" then
        if not isTruthy(VM.registers[inst.a]) then VM.pc = tonumber(inst.b) + 1 else VM.pc = VM.pc + 1 end
    else
        VM.state = "HALTED"
        error(string.format("VM ERROR: Unsupported opcode '%s' at instruction %d", tostring(op), inst.idx), 0)
    end

    return true
end

function VM.runContinuous()
    VM.state = "RUNNING"
    VM.startTime = os.clock()
    VM.deadline = VM.startTime + CONFIG.MAX_RUNTIME_SEC

    while VM.state == "RUNNING" do
        local ok, cont = pcall(VM.step)
        if not ok then
            VM.state = "HALTED"
            VM.lastError = tostring(cont)
            if VM.onOutput and not VM.suppressOutput then VM.onOutput("[Error] " .. VM.lastError) end
            break
        end
        if not cont then break end
    end
end
-- ---------------------------------------------------------------------------
-- Time-travel debugging: reverse execution by deterministic replay.
-- The VM is a pure state machine, so rewinding to operation N is equivalent to
-- re-running from a fresh init while suppressing output. Breakpoints are
-- suspended during the replay so it cannot pause on the way back.
-- ---------------------------------------------------------------------------
function VM.rewindTo(targetOps)
    targetOps = math.max(0, math.floor(tonumber(targetOps) or 0))
    local irData = {
        instructions = VM.instructions,
        constants = VM.constants,
        regCount = VM.regCount or 0
    }
    local savedBreakpoints, savedConds = VM.breakpoints, VM.breakpointConds
    local savedHits, savedTrace = VM.lineHits, VM.trace
    VM.breakpoints, VM.breakpointConds = {}, {}
    VM.init(irData, VM.initialEnv)
    VM.breakpoints, VM.breakpointConds = savedBreakpoints, savedConds
    VM.lineHits, VM.trace = savedHits, savedTrace
    VM.suppressOutput = true
    VM.state = "RUNNING"
    VM.deadline = os.clock() + CONFIG.MAX_RUNTIME_SEC
    local ok = true
    for _ = 1, targetOps do
        local stepOk, cont = pcall(VM.step)
        if not stepOk or not cont then ok = false break end
    end
    VM.suppressOutput = false
    if VM.state == "RUNNING" then VM.state = "PAUSED" end
    return ok, VM.instructionsExecuted
end

-- Evaluate a watch / breakpoint-condition expression against the paused frame.
function VM.evalCondition(src)
    if type(src) ~= "string" or src == "" then return true end
    local function tryParse(text)
        local ok, tokens = pcall(Lexer.lex, text, "EPL")
        if not ok or type(tokens) ~= "table" then return nil end
        local ok2, ast = pcall(function() return Parser.new(tokens, "EPL"):parse() end)
        if not ok2 or type(ast) ~= "table" or type(ast.body) ~= "table" then return nil end
        local stmt = ast.body[1]
        if stmt and stmt.expr then return stmt.expr end
        return nil
    end
    local expr = tryParse(src) or tryParse("print " .. src)
    if not expr then return true end
    return VM.evalNode(expr)
end

-- A tiny, side-effect-free expression evaluator used by watches/conditions.
function VM.evalNode(n)
    if not n then return nil end
    local tag = n.tag
    if tag == "number" or tag == "string" or tag == "bool" then return n.value end
    if tag == "nil" then return nil end
    if tag == "ident" then
        if #VM.callStack > 0 then return getScopedValue(VM.callStack[#VM.callStack], n.name) end
        return VM.environment[n.name]
    end
    if tag == "unary" then
        local v = VM.evalNode(n.operand)
        if n.op == "not" or n.op == "!" then return not isTruthy(v) end
        return -(tonumber(v) or 0)
    end
    if tag == "member" then
        local obj = VM.evalNode(n.object)
        if type(obj) == "table" then return obj[n.member] end
        return nil
    end
    if tag == "call" then
        local name = n.callee and n.callee.tag == "ident" and n.callee.name or nil
        local args = {}
        for _, a in ipairs(n.args or {}) do table.insert(args, VM.evalNode(a)) end
        if name == "len" and type(args[1]) == "string" then return #args[1] end
        if name == "type" then return type(args[1]) end
        if name == "tostring" then return tostring(args[1]) end
        if name == "tonumber" then return tonumber(args[1]) end
        return nil
    end
    if tag == "binary" then
        local a, b = VM.evalNode(n.left), VM.evalNode(n.right)
        local op = n.op
        if op == "and" then if isTruthy(a) then return b end return a end
        if op == "or" then if isTruthy(a) then return a end return b end
        if op == ".." then return tostring(a) .. tostring(b) end
        if op == "==" then return a == b end
        if op == "~=" or op == "!=" then return a ~= b end
        if op == "<" or op == "<=" or op == ">" or op == ">=" then
            local ta, tb = type(a), type(b)
            if ta ~= tb or (ta ~= "number" and ta ~= "string") then return nil end
            if op == "<" then return a < b end
            if op == "<=" then return a <= b end
            if op == ">" then return a > b end
            return a >= b
        end
        local na, nb = tonumber(a), tonumber(b)
        if na == nil or nb == nil then return nil end
        if op == "+" then return na + nb
        elseif op == "-" then return na - nb
        elseif op == "*" then return na * nb
        elseif op == "/" then if nb == 0 then return nil end return na / nb
        elseif op == "%" then if nb == 0 then return nil end return na % nb
        elseif op == "^" then return na ^ nb end
        return nil
    end
    return nil
end


-- ---------------------------------------------------------------------------
-- Isolated sub-VM execution + cross-document package loading (`require`).
-- A module document is compiled and run in a fresh sandbox; only its
-- non-builtin, non-function globals are re-exported as the module table.
-- ---------------------------------------------------------------------------
local MODULE_BUILTIN_KEYS = {
    math = true, string = true, table = true, task = true, std = true,
    tostring = true, tonumber = true, type = true, ["print"] = true, require = true
}

function VM.runIsolated(irData)
    local saved = {}
    for k, v in pairs(VM) do saved[k] = v end
    VM.init(irData, VM.initialEnv)
    VM.suppressOutput = true
    VM.state = "RUNNING"
    VM.runContinuous()
    local env = VM.environment
    for k in pairs(VM) do VM[k] = nil end
    for k, v in pairs(saved) do VM[k] = v end
    return env
end

function VM.requireModule(name)
    if type(name) ~= "string" or name == "" then return nil end
    if VM.requireCache[name] then return VM.requireCache[name] end
    local provider = VM.documentProvider
    if type(provider) ~= "function" then return nil end
    local okDoc, doc = pcall(provider, name)
    if not okDoc or type(doc) ~= "table" or type(doc.source) ~= "string" then return nil end
    local okAst, ast = pcall(parseSourceToAST, doc.source, doc.lang or "EPL")
    if not okAst or type(ast) ~= "table" then return nil end
    local okIR, ir = pcall(HyperionIR.fromAST, ast)
    if not okIR or type(ir) ~= "table" then return nil end
    local env = VM.runIsolated(ir)
    local exports = {}
    for k, v in pairs(env) do
        if not MODULE_BUILTIN_KEYS[k] and type(v) ~= "function" then exports[k] = v end
    end
    VM.requireCache[name] = exports
    return exports
end

-- ============================================================================
-- 14. PROFILER & SELF-TEST SUITE
-- ============================================================================
local Profiler = {
    timings = { lex = 0, parse = 0, semantic = 0, ir = 0, optimize = 0, target = 0, runtime = 0 },
    counts = { tokens = 0, astNodes = 0, irInstructions = 0 },
    maxLineHits = 1
}

-- Whether the gutter paints a per-line execution heatmap.
local heatmapEnabled = true

-- Recompute the hottest-line maximum (call before rendering the gutter).
function Profiler.computeHeat()
    local max = 0
    for _, c in pairs(VM.lineHits) do if c > max then max = c end end
    Profiler.maxLineHits = math.max(1, max)
    return Profiler.maxLineHits
end

-- Return the N hottest executed source lines as { line, hits }.
function Profiler.hotLines(limit)
    local list = {}
    for line, c in pairs(VM.lineHits) do table.insert(list, { line = line, hits = c }) end
    table.sort(list, function(a, b) return a.hits > b.hits end)
    local out = {}
    for i = 1, math.min(limit or 10, #list) do table.insert(out, list[i]) end
    return out
end

-- Heat colour for a line (nil when the line was never executed).
function Profiler.heatColor(line)
    if not heatmapEnabled then return nil end
    local hits = VM.lineHits[line]
    if not hits or hits == 0 then return nil end
    local t = hits / math.max(1, Profiler.maxLineHits)
    if t > 0.75 then return C.red
    elseif t > 0.5 then return C.yellow
    elseif t > 0.25 then return C.cyan
    else return C.green end
end

function Profiler.reset()
    Profiler.timings = { lex = 0, parse = 0, semantic = 0, ir = 0, optimize = 0, target = 0, runtime = 0 }
    Profiler.counts = { tokens = 0, astNodes = 0, irInstructions = 0 }
    Profiler.maxLineHits = 1
end

local TestRunner = {}

function TestRunner.runAll()
    local tests = {
        {
            name = "Arithmetic & Precedence",
            fn = function()
                local t = Lexer.lex("set x = 5 + 10 * 2", "EPL")
                local p = Parser.new(t, "EPL")
                local ast = p:parse()
                local opt = Optimizer.optimizeAST(ast)
                return opt.body[1].expr.value == 25
            end
        },
        {
            name = "Boolean & Nil Literals",
            fn = function()
                local t = Lexer.lex("set a = true\nset b = nil", "EPL")
                local p = Parser.new(t, "EPL")
                local ast = p:parse()
                return ast.body[1].expr.tag == "bool" and ast.body[2].expr.tag == "nil"
            end
        },
        {
            name = "Python Indentation & DEDENT",
            fn = function()
                local py = "if score > 10:\n    print(score)\nprint(0)"
                local toks = Lexer.lex(py, "Python")
                local hasIndent, hasDedent = false, false
                for _, t in ipairs(toks) do
                    if t.kind == "INDENT" then hasIndent = true end
                    if t.kind == "DEDENT" then hasDedent = true end
                end
                return hasIndent and hasDedent
            end
        },
        {
            name = "Function Declaration & VM Call Frames",
            fn = function()
                local src = "local function add(a, b)\n    return a + b\nend\nset res = add(10, 20)\nprint res"
                local toks = Lexer.lex(src, "Lua")
                local p = Parser.new(toks, "Lua")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.environment["res"] == 30
            end
        },
        {
            name = "Recursion Depth Guard",
            fn = function()
                local src = "local function inf()\n    return inf()\nend\ninf()"
                local toks = Lexer.lex(src, "Lua")
                local p = Parser.new(toks, "Lua")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.state == "HALTED" and VM.instructionsExecuted > 0
            end
        },
        {
            name = "Watchdog Infinite Loop Prevention",
            fn = function()
                local ir = {
                    instructions = {
                        { idx = 0, op = "JMP", a = 0, line = 1, col = 1 },
                        { idx = 1, op = "RETURN", a = "nil", line = 2, col = 1 }
                    },
                    constants = {},
                    regCount = 1
                }
                VM.init(ir)
                VM.runContinuous()
                return VM.state == "HALTED" and VM.instructionsExecuted >= CONFIG.MAX_INSTRUCTIONS
            end
        },
        {
            name = "Translation Full-Source Hash Determinism",
            fn = function()
                local h1 = hashSource("set a = 1", "EPL", "Luau")
                local h2 = hashSource("set a = 1", "EPL", "Luau")
                local h3 = hashSource("set a = 2", "EPL", "Luau")
                return h1 == h2 and h1 ~= h3
            end
        },
        {
            name = "Safe Optimizer (No side-effect corruption)",
            fn = function()
                local node = { tag = "binary", op = "+", left = { tag = "number", value = 15 }, right = { tag = "number", value = 25 } }
                local opt = Optimizer.optimizeAST(node)
                return opt.value == 40
            end
        },
        {
            name = "Base64 Round Trip",
            fn = function()
                local samples = {"", "hello", "1..2", "Hyperion ✓"}
                for _, sample in ipairs(samples) do
                    local encoded = Base64.encode(sample)
                    local decoded, err = Base64.decode(encoded)
                    if err or decoded ~= sample then return false end
                end
                return true
            end
        },
        {
            name = "Number vs Concatenation Lexing",
            fn = function()
                local toks = Lexer.lex("set x = 1 .. 2", "EPL")
                local sawNumber, sawConcat = false, false
                for _, t in ipairs(toks) do
                    if t.kind == "NUMBER" and t.value == "1" then sawNumber = true end
                    if t.kind == "OP" and t.value == ".." then sawConcat = true end
                end
                return sawNumber and sawConcat
            end
        },
        {
            name = "Closure Capture",
            fn = function()
                local src = "local x = 41\nlocal function get()\n    return x\nend\nset x = 42\nset result = get()"
                local toks = Lexer.lex(src, "Lua")
                local p = Parser.new(toks, "Lua")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.lastError == nil and VM.environment["result"] == 42
            end
        },
        {
            name = "Short Circuit Semantics",
            fn = function()
                local src = "set a = false and missingFunction()\nset b = true or missingFunction()"
                local toks = Lexer.lex(src, "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.lastError == nil and VM.environment["a"] == false and VM.environment["b"] == true
            end
        },
        {
            name = "While Loop Execution",
            fn = function()
                local src = "set x = 0\nwhile x < 3 do\n    set x = x + 1\nend"
                local toks = Lexer.lex(src, "Lua")
                local p = Parser.new(toks, "Lua")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.lastError == nil and VM.environment["x"] == 3
            end
        },
        {
            name = "Luau Truthiness Regression",
            fn = function()
                return isTruthy(0) and isTruthy("") and isTruthy({}) and not isTruthy(false) and not isTruthy(nil)
            end
        },
        {
            name = "Malformed IR Rejection",
            fn = function()
                local ok = pcall(function()
                    VM.init({
                        instructions = {
                            { idx = 0, op = "JMP", a = 999, line = 1, col = 1 }
                        },
                        constants = {},
                        regCount = 0
                    })
                end)
                return not ok
            end
        },
        {
            name = "Register Budget Rejection",
            fn = function()
                local ok = pcall(function()
                    VM.init({
                        instructions = {
                            { idx = 0, op = "RETURN", a = "nil", line = 1, col = 1 }
                        },
                        constants = {},
                        regCount = CONFIG.MAX_REGISTERS + 1
                    })
                end)
                return not ok
            end
        },
        {
            name = "Comparison Type Guard",
            fn = function()
                local ok = pcall(function()
                    VM.init({
                        instructions = {
                            { idx = 0, op = "LOADBOOL", a = "R0", b = "true", line = 1, col = 1 },
                            { idx = 1, op = "LOADBOOL", a = "R1", b = "false", line = 1, col = 1 },
                            { idx = 2, op = "LT", a = "R2", b = "R0", c = "R1", line = 1, col = 1 },
                            { idx = 3, op = "RETURN", a = "R2", line = 1, col = 1 }
                        },
                        constants = {},
                        regCount = 3
                    })
                    VM.runContinuous()
                end)
                return ok and VM.state == "HALTED" and VM.lastError ~= nil
            end
        },
        {
            name = "Member Function Call (math.floor)",
            fn = function()
                local src = "set r = math.floor(3.7)"
                local toks = Lexer.lex(src, "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.lastError == nil and VM.environment["r"] == 3
            end
        },
        {
            name = "Numeric For Loop",
            fn = function()
                local src = "set s = 0\nfor i = 1, 5 do\n    set s = s + i\nend"
                local toks = Lexer.lex(src, "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.lastError == nil and VM.environment["s"] == 15
            end
        },
        {
            name = "For Loop Negative Step",
            fn = function()
                local src = "set s = 0\nfor i = 5, 1, -1 do\n    set s = s + i\nend"
                local toks = Lexer.lex(src, "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.lastError == nil and VM.environment["s"] == 15
            end
        },
        {
            name = "For Times Loop",
            fn = function()
                local src = "set c = 0\nfor 3 times do\n    set c = c + 1\nend"
                local toks = Lexer.lex(src, "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.lastError == nil and VM.environment["c"] == 3
            end
        },
        {
            name = "Escape Sequence Decoding",
            fn = function()
                local toks = Lexer.lex('set s = "a\\nb"', "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                return ast.body[1].expr.value == "a\nb"
            end
        },
        {
            name = "Hex & Exponent Numbers",
            fn = function()
                local toks = Lexer.lex("set a = 0x10\nset b = 1e3", "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                return ast.body[1].expr.value == 16 and ast.body[2].expr.value == 1000
            end
        },
        {
            name = "Python elif Chain",
            fn = function()
                local py = "x = 5\nif x > 10:\n    print(1)\nelif x > 3:\n    print(2)\nelse:\n    print(3)"
                local toks = Lexer.lex(py, "Python")
                local p = Parser.new(toks, "Python")
                local ast, diags = p:parse()
                for _, d in ipairs(diags) do
                    if d.severity == "ERROR" then return false end
                end
                return ast.body[2].tag == "if" and #ast.body[2].elseBody == 1 and ast.body[2].elseBody[1].tag == "if"
            end
        },
        {
            name = "Multi-Argument Print",
            fn = function()
                local toks = Lexer.lex('print("a", "b", 3)', "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.lastError == nil and ast.body[1].tag == "print" and ast.body[1].args ~= nil and #ast.body[1].args == 3
            end
        },
        {
            name = "Python for-in-range Loop",
            fn = function()
                local py = "for i in range(3):\n    print(i)\n"
                local toks = Lexer.lex(py, "Python")
                local p = Parser.new(toks, "Python")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.state == "HALTED" and VM.environment["i"] == 3
            end
        },
        {
            name = "English Language Preprocessing & Execution",
            fn = function()
                local src = "define x as 5 plus 3\ndisplay x\n"
                local normalized = HyperionLanguages.preprocessEnglish(src)
                local toks = Lexer.lex(normalized, "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.environment["x"] == 8
            end
        },
        {
            name = "C / C++ / Java Target Generation",
            fn = function()
                local toks = Lexer.lex("set x = 5\nprint x", "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local c = HyperionLanguages.toC(ast, "C")
                local cpp = HyperionLanguages.toC(ast, "C++")
                local java = HyperionLanguages.toJava(ast)
                return c:find("int main", 1, true) ~= nil
                    and cpp:find("cout", 1, true) ~= nil
                    and java:find("class HyperionProgram", 1, true) ~= nil
            end
        },
        {
            name = "C-family Source Parser",
            fn = function()
                local src = "int main() {\n  int x = 4;\n  printf(\"%d\", x);\n  return 0;\n}\n"
                local ast, diags = HyperionLanguages.parseCStyle(src, "C")
                return ast ~= nil and #ast.body > 0
            end
        },
        {
            name = "Bytecode Assemble / Disassemble Round Trip",
            fn = function()
                local ir = { instructions = {
                    { idx = 0, op = "LOADK", a = "R1", b = "hi", c = "K0", line = 1, col = 1 },
                    { idx = 1, op = "PRINT", a = "R1", line = 1, col = 1 },
                }, constants = { "line1\nline2" }, regCount = 2 }
                local text = HyperionLanguages.toBytecode(ir)
                local back = HyperionLanguages.parseBytecode(text)
                return #back.instructions == 2 and back.instructions[1].op == "LOADK"
                    and back.constants[1] == "line1\nline2" and back.regCount == 2
            end
        },
        {
            name = "Luau Source Language",
            fn = function()
                local toks = Lexer.lex("local a = 3\nprint a", "Luau")
                local p = Parser.new(toks, "Luau")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.environment["a"] == 3
            end
        },
        {
            name = "Cross-Language Translation Matrix",
            fn = function()
                local src = "set x = 5\nprint x\n"
                local targets = { "Luau", "Lua", "Python", "EPL", "English", "C", "C+", "C++", "Java", "Bytecode", "IR" }
                for _, target in ipairs(targets) do
                    local out = translateSource(src, "EPL", target)
                    if type(out) ~= "string" or #out == 0 then return false end
                end
                return true
            end
        },
        {
            name = "IR Optimizer Removes Self-Moves",
            fn = function()
                local ir = {
                    instructions = {
                        { idx = 0, op = "LOADK", a = "R0", b = "5", c = "K0", line = 1, col = 1 },
                        { idx = 1, op = "MOVE", a = "R0", b = "R0", line = 1, col = 1 },
                        { idx = 2, op = "PRINT", a = "R0", line = 1, col = 1 },
                        { idx = 3, op = "RETURN", a = "nil", line = 1, col = 1 }
                    },
                    constants = { 5 },
                    regCount = 1
                }
                local opt = Optimizer.optimizeIR(ir)
                return #opt.instructions == 3 and opt.stats.reduction > 0
            end
        },
        {
            name = "Sandbox String-Allocation Guard",
            fn = function()
                local src = "set s = string.rep(\"x\", 100000000)\nprint s"
                local toks = Lexer.lex(src, "EPL")
                local p = Parser.new(toks, "EPL")
                local ast = p:parse()
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.state == "HALTED"
            end
        },
        {
            name = "Type Inference: Literals & Arithmetic",
            fn = function()
                local ast = parseSourceToAST("set n = 1 + 2 * 3\nset s = \"a\" .. \"b\"\nset b = n > 2\nprint s", "EPL")
                local r = TypeInference.infer(ast)
                local types = {}
                for _, sym in ipairs(r.symbols) do types[sym.name] = sym.type end
                return types.n == "number" and types.s == "string" and types.b == "bool"
            end
        },
        {
            name = "Type Inference: Function & Parameter Symbols",
            fn = function()
                local ast = parseSourceToAST("local function add(a, b)\n    return a + b\nend\nset r = add(1, 2)", "Lua")
                local r = TypeInference.infer(ast)
                local kinds = {}
                for _, sym in ipairs(r.symbols) do kinds[sym.name] = sym.kind end
                return kinds.add == "function" and kinds.a == "parameter" and kinds.r == "variable"
            end
        },
        {
            name = "IntelliSense: Completion & Go-To-Definition",
            fn = function()
                local src = "set counter = 10\nprint counter"
                local res = IntelliSense.complete(src, 2, 14, "EPL")
                local found = false
                for _, it in ipairs(res.items) do if it.label == "counter" then found = true end end
                local def = IntelliSense.definition(src, 2, 7, "EPL")
                return found and def ~= nil and def.name == "counter" and def.line == 1
            end
        },
        {
            name = "IntelliSense: Rename References",
            fn = function()
                local src = "set total = 1\nset sum = total + total\nprint total"
                local out, count = IntelliSense.rename(src, 2, 11, "grand")
                return out ~= nil and count == 4
                    and out:find("grand", 1, true) ~= nil
                    and out:find("total", 1, true) == nil
            end
        },
        {
            name = "Profiler: Line Hit Counters",
            fn = function()
                local ast = parseSourceToAST("set x = 1\nset x = x + 1\nprint x", "EPL")
                VM.init(HyperionIR.fromAST(ast))
                VM.runContinuous()
                return (VM.lineHits[1] or 0) > 0 and (VM.lineHits[2] or 0) > 0
            end
        },
        {
            name = "Time-Travel: Rewind Restores Earlier State",
            fn = function()
                local ast = parseSourceToAST("set x = 1\nset x = 2\nset x = 3\nprint x", "EPL")
                VM.init(HyperionIR.fromAST(ast))
                VM.runContinuous()
                local final = VM.environment["x"]
                VM.rewindTo(2)
                local rewound = VM.environment["x"]
                return final == 3 and rewound == 1
            end
        },
        {
            name = "Debugger: Conditional Expression Eval",
            fn = function()
                VM.init({ instructions = {
                    { idx = 0, op = "LOADK", a = "R0", b = "0", c = "K0", line = 1, col = 1 },
                    { idx = 1, op = "RETURN", a = "nil", line = 1, col = 1 }
                }, constants = { 0 }, regCount = 1 })
                VM.environment["x"] = 5
                return VM.evalCondition("x > 3") == true
                    and VM.evalCondition("x > 9") == false
                    and VM.evalCondition("x >") ~= true
            end
        },
        {
            name = "CFG Optimizer: Unreachable & Dead Code",
            fn = function()
                local ir = { instructions = {
                    { idx = 0, op = "LOADK", a = "R0", b = "1", c = "K0", line = 1, col = 1 },
                    { idx = 1, op = "LOADK", a = "R9", b = "42", c = "K2", line = 1, col = 1 },
                    { idx = 2, op = "JMP", a = 5, line = 2, col = 1 },
                    { idx = 3, op = "LOADK", a = "R1", b = "99", c = "K1", line = 3, col = 1 },
                    { idx = 4, op = "PRINT", a = "R1", line = 3, col = 1 },
                    { idx = 5, op = "PRINT", a = "R0", line = 4, col = 1 },
                    { idx = 6, op = "RETURN", a = "nil", line = 5, col = 1 }
                }, constants = { 1, 99, 42 }, regCount = 10 }
                local opt = Optimizer.optimizeCFG(ir)
                if not opt or #opt.instructions ~= 4 then return false end
                for _, inst in ipairs(opt.instructions) do
                    if inst.a == "R9" or inst.a == "R1" then return false end
                end
                return true
            end
        },
        {
            name = "Standard Library: math, list & string",
            fn = function()
                local function runOut(src)
                    local ast = parseSourceToAST(src, "EPL")
                    local ir = HyperionIR.fromAST(ast)
                    local out = {}
                    VM.onOutput = function(s) table.insert(out, tostring(s)) end
                    VM.init(ir)
                    VM.runContinuous()
                    return table.concat(out, "|")
                end
                return runOut("print std.math.gcd(12, 18)") == "6"
                    and runOut("print std.list.sum(std.list.range(1, 5, 1))") == "15"
                    and runOut('print std.string.trim("  hi  ")') == 'hi'
            end
        },
        {
            name = "Package System: require across documents",
            fn = function()
                VM.documentProvider = function(name)
                    if name == "geom" then return { source = "set area = 42", lang = "EPL" } end
                    return nil
                end
                VM.requireCache = {}
                local ast = parseSourceToAST('set m = require("geom")\nprint m.area', "EPL")
                local ir = HyperionIR.fromAST(ast)
                local out = {}
                VM.onOutput = function(s) table.insert(out, tostring(s)) end
                VM.init(ir)
                VM.runContinuous()
                return table.concat(out, "|") == "42"
            end
        },
        {
            name = "Sandbox: string.format width guard",
            fn = function()
                local ast = parseSourceToAST('set s = string.format("%200000d", 5)', "EPL")
                local ir = HyperionIR.fromAST(ast)
                VM.init(ir)
                VM.runContinuous()
                return VM.state == "HALTED"
            end
        },
    }

    local passed = 0
    local results = {}
    for _, t in ipairs(tests) do
        local ok, res = pcall(t.fn)
        local pass = ok and (res == true)
        table.insert(results, { name = t.name, passed = pass })
        if pass then passed = passed + 1 end
    end
    return results, passed, #tests
end

-- ============================================================================
-- 15. RESPONSIVE GUI SETUP
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "EPLHyperion"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function mk(class, props, parent)
    local x = Instance.new(class)
    for k, v in pairs(props or {}) do x[k] = v end
    x.Parent = parent
    return x
end

local function corner(x, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = x
end

local function stroke(x, col)
    local s = Instance.new("UIStroke")
    s.Color = col or C.border
    s.Thickness = 1
    s.Parent = x
    return s
end

local function button(parent, text, col, bgCol)
    local b = mk("TextButton", {
        BackgroundColor3 = bgCol or C.panel2,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = col or C.text,
        TextSize = 13,
        Font = Enum.Font.Code,
        AutoButtonColor = false
    }, parent)
    corner(b, 5)
    return b
end

-- Main Root Window with Size Constraints for Mobile / Tablet Safety
local root = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.92, 0, 0.88, 0),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0
}, gui)
corner(root, 8)
local rootStroke = stroke(root)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(480, 360)
sizeConstraint.MaxSize = Vector2.new(2560, 1440)
sizeConstraint.Parent = root

local uiScale = Instance.new("UIScale")
uiScale.Name = "HyperionUIScale"
uiScale.Scale = 1
uiScale.Parent = root

local function updateUIScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    uiScale.Scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 650), 0.72, 1)
end

local function bindCameraScale()
    local camera = workspace.CurrentCamera
    if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale) end
    updateUIScale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraScale)
bindCameraScale()

-- Header
local top = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0
}, root)
corner(top, 8)

local title = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(12, 0),
    Size = UDim2.new(0.4, 0, 1, 0),
    Text = "EPL Hyperion " .. CONFIG.VERSION .. " [" .. CONFIG.SUBTITLE .. "]",
    TextColor3 = C.text,
    TextSize = 13,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left
}, top)

local minBtn = button(top, "—", C.muted)
minBtn.AnchorPoint = Vector2.new(1, 0.5)
minBtn.Position = UDim2.new(1, -8, 0.5, 0)
minBtn.Size = UDim2.fromOffset(28, 24)

local themeBtn = button(top, "Theme", C.text)
themeBtn.AnchorPoint = Vector2.new(1, 0.5)
themeBtn.Position = UDim2.new(1, -42, 0.5, 0)
themeBtn.Size = UDim2.fromOffset(68, 24)

local shareBtn = button(top, "Share", C.green)
shareBtn.AnchorPoint = Vector2.new(1, 0.5)
shareBtn.Position = UDim2.new(1, -116, 0.5, 0)
shareBtn.Size = UDim2.fromOffset(68, 24)

local openPill = button(gui, "Hyperion", C.blue, C.panel)
openPill.AnchorPoint = Vector2.new(1, 0.5)
openPill.Position = UDim2.new(1, -14, 0.5, 0)
openPill.Size = UDim2.fromOffset(95, 34)
openPill.Visible = false
corner(openPill, 6)
stroke(openPill)

-- Sidebar & Center Body
local side = mk("Frame", {
    Position = UDim2.fromOffset(0, 38),
    Size = UDim2.new(0, 220, 1, -66),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0
}, root)

local center = mk("Frame", {
    Position = UDim2.fromOffset(220, 38),
    Size = UDim2.new(1, -220, 1, -66),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0
}, root)

-- Status Bar
local statusBar = mk("Frame", {
    Position = UDim2.new(0, 0, 1, -28),
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = C.panel2,
    BorderSizePixel = 0
}, root)

local statusLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(10, 0),
    Size = UDim2.new(1, -20, 1, 0),
    Text = "Ready  |  Ln 1, Col 1  |  EPL  |  Watchdog: 1.0s / 100k ops",
    TextColor3 = C.muted,
    TextSize = 11,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left
}, statusBar)

-- Side File List & Tree
local sideLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(10, 6),
    Size = UDim2.new(1, -20, 0, 20),
    Text = "DOCUMENTS",
    TextColor3 = C.muted,
    TextSize = 11,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left
}, side)

local fileList = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(6, 28),
    Size = UDim2.new(1, -12, 1, -70),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    CanvasSize = UDim2.new()
}, side)
local fileLayout = mk("UIListLayout", { Padding = UDim.new(0, 3) }, fileList)

local newDocBtn = button(side, "+ New Document", C.green)
newDocBtn.Position = UDim2.new(0, 6, 1, -34)
newDocBtn.Size = UDim2.new(1, -12, 0, 26)

-- Tabs Bar
local tabsBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 32),
    BackgroundColor3 = C.panel2,
    BorderSizePixel = 0
}, center)

local tabsContainer = mk("ScrollingFrame", {
    Size = UDim2.new(1, -8, 1, 0),
    Position = UDim2.fromOffset(4, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    CanvasSize = UDim2.new()
}, tabsBar)
local tabsLayout = mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, tabsContainer)

-- Editor Area (scrollable editor + clickable breakpoint gutter)
local LINE_HEIGHT = math.ceil(TextService:GetTextSize("Ag", CONFIG.EDITOR_TEXT_SIZE, Enum.Font.Code, Vector2.new(1000, 1000)).Y)
if LINE_HEIGHT < 10 then LINE_HEIGHT = 16 end

local editorFrame = mk("Frame", {
    Position = UDim2.fromOffset(0, 32),
    Size = UDim2.new(1, 0, 1, -192),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0,
    ClipsDescendants = true
}, center)

local gutterScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(0, 46, 1, 0),
    BackgroundColor3 = C.gutter,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    ScrollingEnabled = false,
    CanvasSize = UDim2.new()
}, editorFrame)
local gutterLayout = mk("UIListLayout", { Padding = UDim.new(0, 0) }, gutterScroll)

local editorScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(50, 0),
    Size = UDim2.new(1, -54, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    CanvasSize = UDim2.new()
}, editorFrame)

-- Editable plain TextBox
local editor = mk("TextBox", {
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    ClearTextOnFocus = false,
    MultiLine = true,
    Text = "",
    TextColor3 = C.text,
    TextSize = CONFIG.EDITOR_TEXT_SIZE,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = false
}, editorScroll)
editor.TextEditable = true

-- Separate rich syntax overlay label (avoids focused XML tag corruption)
local syntaxOverlay = mk("TextLabel", {
    Position = editor.Position,
    Size = editor.Size,
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = C.text,
    TextSize = CONFIG.EDITOR_TEXT_SIZE,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = false,
    RichText = true,
    Visible = false
}, editorScroll)

-- Toolbar (horizontally scrollable)
local toolbar = mk("Frame", {
    Position = UDim2.new(0, 0, 1, -160),
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    ClipsDescendants = true
}, center)

local toolbarScroll = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    ScrollingDirection = Enum.ScrollingDirection.X,
    CanvasSize = UDim2.new()
}, toolbar)
local toolbarLayout = mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5) }, toolbarScroll)
mk("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 5) }, toolbarScroll)

local function toolBtn(text, col, width)
    local b = button(toolbarScroll, text, col)
    b.Size = UDim2.fromOffset(width or 70, 26)
    return b
end

local runBtn    = toolBtn("▶ Run", C.green, 64)
local stepBtn   = toolBtn("Step", C.cyan, 54)
local contBtn   = toolBtn("Cont", C.cyan, 54)
local inspBtn   = toolBtn("Inspect", C.purple, 70)
local transBtn  = toolBtn("Translate", C.blue, 78)
local optBtn    = toolBtn("Optimize", C.yellow, 74)
local langBtn   = toolBtn("Src: EPL", C.text, 84)
local targetBtn = toolBtn("Target: Luau", C.text, 100)
local testBtn   = toolBtn("Tests", C.cyan, 60)
local clearBtn  = toolBtn("Clear", C.muted, 56)
local errorsBtn = toolBtn("Errors", C.red, 64)
-- IntelliSense / profiler / debugger toolbar buttons (one table keeps the
-- main chunk under Luau's 200-local limit).
local extraBtns = {
    def    = toolBtn("Go Def", C.cyan, 62),
    rename = toolBtn("Rename", C.purple, 66),
    heat   = toolBtn("Heat", C.yellow, 52),
    back   = toolBtn("Back", C.cyan, 54),
    watch  = toolBtn("Watch", C.purple, 62),
    cond   = toolBtn("Cond", C.red, 52),
    sentinel = toolBtn("Sentinel", C.green, 74)
}
if not CONFIG.IS_OWNER then extraBtns.sentinel.Visible = false end

toolbarLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    toolbarScroll.CanvasSize = UDim2.new(0, toolbarLayout.AbsoluteContentSize.X + 12, 0, 0)
end)

-- Terminal & Output Dock
local terminal = mk("Frame", {
    Position = UDim2.new(0, 0, 1, -124),
    Size = UDim2.new(1, 0, 0, 124),
    BackgroundColor3 = Color3.fromRGB(11, 12, 15),
    BorderSizePixel = 0
}, center)

local termHeader = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(8, 2),
    Size = UDim2.new(1, -16, 0, 18),
    Text = "TERMINAL",
    TextColor3 = C.muted,
    TextSize = 11,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left
}, terminal)

local outLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(8, 22),
    Size = UDim2.new(1, -16, 1, -26),
    Text = "EPL Hyperion " .. CONFIG.VERSION .. " Ready.",
    TextColor3 = Color3.fromRGB(175, 215, 180),
    TextSize = 11,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true
}, terminal)

local logs = {}
local consoleErrors = {}
local consolePanelOpen = false
local logBytes = 0

local function safeErrorText(value)
    local s = tostring(value)
    if #s > 4000 then s = s:sub(1, 4000) .. "\n...[truncated]" end
    return s
end

-- Developer Console note: Roblox does not expose the /console history as a
-- readable client API. This viewer therefore records Hyperion-owned failures
-- at their source instead of pretending to scrape Roblox's console.
-- Hyperion-owned console diagnostics. User-program execution output is kept
-- in the normal terminal and is never mixed into this list.
local function addConsoleError(message, source)
    table.insert(consoleErrors, {
        message = safeErrorText(message),
        source = tostring(source or "Hyperion"),
        time = os.date("%H:%M:%S")
    })
    if #consoleErrors > CONFIG.MAX_LOG_ENTRIES then
        table.remove(consoleErrors, 1)
    end
end

local function log(msg)
    local textValue = safeErrorText(msg)
    table.insert(logs, textValue)
    logBytes = logBytes + #textValue + 1
    -- Enforce both the entry-count cap and the total output byte budget so a
    -- runaway program cannot grow the terminal buffer without bound.
    while (#logs > CONFIG.MAX_LOG_ENTRIES) or (logBytes > CONFIG.MAX_OUTPUT_BYTES and #logs > 1) do
        local removed = table.remove(logs, 1)
        logBytes = logBytes - (#removed + 1)
    end
    outLabel.Text = table.concat(logs, "\n")
end

local consolePanel = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.82, 0, 0.74, 0),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 50
}, root)
corner(consolePanel, 8)
stroke(consolePanel, C.red)

local consoleTitle = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(12, 6),
    Size = UDim2.new(1, -180, 0, 26),
    Text = "CONSOLE ERRORS",
    TextColor3 = C.red,
    TextSize = 13,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 51
}, consolePanel)

local consoleCount = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -165, 0, 6),
    Size = UDim2.fromOffset(153, 26),
    Text = "0 errors",
    TextColor3 = C.muted,
    TextSize = 11,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Right,
    ZIndex = 51
}, consolePanel)

local consoleClose = button(consolePanel, "Close", C.text)
consoleClose.Position = UDim2.new(1, -74, 0, 36)
consoleClose.Size = UDim2.fromOffset(62, 24)
consoleClose.ZIndex = 52

local consoleClear = button(consolePanel, "Clear", C.muted)
consoleClear.Position = UDim2.new(1, -144, 0, 36)
consoleClear.Size = UDim2.fromOffset(62, 24)
consoleClear.ZIndex = 52

local consoleCopy = button(consolePanel, "Copy", C.green)
consoleCopy.Position = UDim2.new(1, -214, 0, 36)
consoleCopy.Size = UDim2.fromOffset(62, 24)
consoleCopy.ZIndex = 52

local consoleList = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(10, 68),
    Size = UDim2.new(1, -20, 1, -78),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0,
    ScrollBarThickness = 5,
    CanvasSize = UDim2.new(),
    ZIndex = 51
}, consolePanel)
corner(consoleList, 5)

local consoleLayout = mk("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder
}, consoleList)

local consoleCopyBox = mk("TextBox", {
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(2, 2),
    BackgroundTransparency = 1,
    TextTransparency = 1,
    Text = "",
    ClearTextOnFocus = false,
    TextEditable = false,
    MultiLine = true,
    ZIndex = 53
}, consolePanel)

local function formatConsoleError(entry)
    return string.format("[%s] %s\n%s", entry.time, entry.source, entry.message)
end

local function rebuildConsoleErrors()
    for _, child in ipairs(consoleList:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    consoleCount.Text = string.format("%d error%s", #consoleErrors, #consoleErrors == 1 and "" or "s")

    for index, entry in ipairs(consoleErrors) do
        local item = mk("TextButton", {
            Size = UDim2.new(1, -8, 0, 58),
            BackgroundColor3 = C.panel2,
            BorderSizePixel = 0,
            Text = formatConsoleError(entry),
            TextColor3 = C.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
            AutoButtonColor = false,
            LayoutOrder = index,
            ZIndex = 52
        }, consoleList)
        corner(item, 5)
        item.Activated:Connect(function()
            consoleCopyBox.Text = formatConsoleError(entry)
            consoleCopyBox:CaptureFocus()
            consoleCopyBox.SelectionStart = 1
            consoleCopyBox.CursorPosition = #consoleCopyBox.Text + 1
        end)
    end
    consoleList.CanvasSize = UDim2.new(0, 0, 0, consoleLayout.AbsoluteContentSize.Y + 8)
end

local function reportConsoleError(message, source)
    addConsoleError(message, source)
    if consolePanelOpen then rebuildConsoleErrors() end
end

consoleLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    consoleList.CanvasSize = UDim2.new(0, 0, 0, consoleLayout.AbsoluteContentSize.Y + 8)
end)

local function guardConsoleAction(name, callback)
    return function(...)
        local ok, err = xpcall(callback, function(e) return safeErrorText(e) end, ...)
        if not ok then
            reportConsoleError(err, "UI:" .. name)
        end
    end
end

errorsBtn.Activated:Connect(guardConsoleAction("ErrorsOpen", function()
    consolePanelOpen = true
    rebuildConsoleErrors()
    consolePanel.Visible = true
end))

consoleClose.Activated:Connect(guardConsoleAction("ErrorsClose", function()
    consolePanelOpen = false
    consolePanel.Visible = false
end))

consoleClear.Activated:Connect(guardConsoleAction("ErrorsClear", function()
    table.clear(consoleErrors)
    rebuildConsoleErrors()
    log("Console error history cleared.")
end))

consoleCopy.Activated:Connect(guardConsoleAction("ErrorsCopy", function()
    if consoleCopyBox.Text == "" then
        log("Select a console error first.")
        return
    end
    consoleCopyBox:CaptureFocus()
    consoleCopyBox.SelectionStart = 1
    consoleCopyBox.CursorPosition = #consoleCopyBox.Text + 1
    log("Console error selected. Use the platform Copy action to copy it.")
end))

-- Route Hyperion-owned failures here. Do not route user-program VM errors.
local function reportHyperionError(message, source)
    reportConsoleError(message, source or "Hyperion")
    log("[Console Error] " .. tostring(source or "Hyperion") .. ": " .. safeErrorText(message))
end

-- ============================================================================
-- 15.5. MAJOR UI VISUAL REVAMP
-- ============================================================================
-- Visual-only styling layer. Existing controls and behavior are preserved.
local function hyperionGradient(parent, a, b, rotation)
    local g = parent:FindFirstChild("HyperionGradient")
    if not g then
        g = Instance.new("UIGradient")
        g.Name = "HyperionGradient"
        g.Parent = parent
    end
    g.Color = ColorSequence.new(a, b)
    g.Rotation = rotation or 90
end

local function hyperionStroke(parent, color, transparency, thickness)
    local s = parent:FindFirstChild("HyperionStroke")
    if not s then
        s = Instance.new("UIStroke")
        s.Name = "HyperionStroke"
        s.Parent = parent
    end
    s.Color = color
    s.Transparency = transparency or 0.35
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local function hyperionCorner(parent, radius)
    local c = parent:FindFirstChild("HyperionCorner")
    if not c then
        c = Instance.new("UICorner")
        c.Name = "HyperionCorner"
        c.Parent = parent
    end
    c.CornerRadius = UDim.new(0, radius or 8)
end

local function styleHyperionButton(btn, accent)
    if not btn or not btn:IsA("GuiButton") then return end
    btn.Active = true
    btn.AutoButtonColor = false
    btn.BackgroundColor3 = C.panel2
    btn.TextColor3 = C.text
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = math.clamp(btn.TextSize, 11, 13)
    hyperionCorner(btn, 7)
    hyperionStroke(btn, accent or C.border, 0.45, 1)

    if not btn:GetAttribute("HyperionHoverBound") then
        btn:SetAttribute("HyperionHoverBound", true)
        btn.MouseEnter:Connect(function()
            btn.BackgroundColor3 = C.panel
            local s = btn:FindFirstChild("HyperionStroke")
            if s then s.Transparency = 0.05; s.Thickness = 1.25 end
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundColor3 = C.panel2
            local s = btn:FindFirstChild("HyperionStroke")
            if s then s.Transparency = 0.45; s.Thickness = 1 end
        end)
    end
end

local function applyMajorUIRevamp()
    -- Main window.
    root.BackgroundColor3 = C.bg
    root.BackgroundTransparency = 0
    root.ClipsDescendants = true
    hyperionCorner(root, 12)
    hyperionStroke(root, C.border, 0.08, 1)
    hyperionGradient(root, C.bg, C.panel, 90)

    -- Header / application chrome.
    top.BackgroundColor3 = C.panel
    hyperionCorner(top, 10)
    hyperionStroke(top, C.border, 0.3, 1)
    hyperionGradient(top, C.panel, C.panel2, 0)

    toolbar.BackgroundColor3 = C.panel2
    hyperionCorner(toolbar, 8)
    hyperionStroke(toolbar, C.border, 0.42, 1)

    tabsBar.BackgroundColor3 = C.panel2
    hyperionCorner(tabsBar, 7)
    hyperionStroke(tabsBar, C.border, 0.5, 1)

    -- Main workspace surfaces.
    side.BackgroundColor3 = C.panel
    hyperionCorner(side, 9)
    hyperionStroke(side, C.border, 0.5, 1)

    center.BackgroundColor3 = C.bg
    editorFrame.BackgroundColor3 = C.bg
    hyperionCorner(editorFrame, 8)
    hyperionStroke(editorFrame, C.border, 0.42, 1)

    terminal.BackgroundColor3 = C.panel
    hyperionCorner(terminal, 8)
    hyperionStroke(terminal, C.border, 0.45, 1)

    statusBar.BackgroundColor3 = C.panel2
    hyperionCorner(statusBar, 7)
    hyperionStroke(statusBar, C.border, 0.5, 1)

    gutterScroll.BackgroundColor3 = C.gutter

    -- Editor typography.
    editor.Font = Enum.Font.Code
    editor.TextSize = CONFIG.EDITOR_TEXT_SIZE
    syntaxOverlay.Font = Enum.Font.Code
    syntaxOverlay.TextSize = CONFIG.EDITOR_TEXT_SIZE
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    statusLabel.Font = Enum.Font.GothamMedium
    sideLabel.Font = Enum.Font.GothamBold
    termHeader.Font = Enum.Font.GothamBold

    -- Consistent button language.
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextButton") or obj:IsA("ImageButton") then
            styleHyperionButton(obj, C.border)
        end
    end

    styleHyperionButton(runBtn, C.green)
    styleHyperionButton(stepBtn, C.cyan)
    styleHyperionButton(contBtn, C.cyan)
    styleHyperionButton(inspBtn, C.purple)
    styleHyperionButton(transBtn, C.blue)
    styleHyperionButton(optBtn, C.yellow)
    styleHyperionButton(testBtn, C.cyan)
    styleHyperionButton(shareBtn, C.green)
    styleHyperionButton(errorsBtn, C.red)

    -- Console/error viewer.
    consolePanel.BackgroundColor3 = C.panel
    hyperionCorner(consolePanel, 10)
    hyperionStroke(consolePanel, C.red, 0.18, 1)
    consoleList.BackgroundColor3 = C.bg
    hyperionCorner(consoleList, 7)
    hyperionStroke(consoleList, C.border, 0.55, 1)

    if openPill then
        openPill.BackgroundColor3 = C.panel
        hyperionCorner(openPill, 10)
        hyperionStroke(openPill, C.border, 0.2, 1)
    end
end

applyMajorUIRevamp()

-- ============================================================================
-- 16. DOCUMENTS, TABS & EDITOR INFRASTRUCTURE
-- ============================================================================
local sourceLanguages = { "EPL", "English", "Lua", "Luau", "Python", "C", "C+", "C++", "Java", "Bytecode" }
local sourceLangIndex = 1
local targetLanguages = { "Luau", "Lua", "Python", "EPL", "English", "C", "C+", "C++", "Java", "Bytecode", "IR" }
local targetIndex = 1

local docs = {}
local currentDoc = 1
local debugSessionActive = false

local function docLang()
    return docs[currentDoc] and docs[currentDoc].lang or "EPL"
end

local function countLines(text)
    return 1 + select(2, text:gsub("\n", "\n"))
end

-- Forward declarations
local buildGutter
local rebuildHighlight
local rebuildTabs
local rebuildFileList
local updateStatusBar

local function markDirty()
    if docs[currentDoc] then
        docs[currentDoc].text = editor.Text
    end
    debugSessionActive = false
end

local function newDoc(name, text, lang)
    if #docs >= CONFIG.MAX_DOCUMENTS then
        log("Document limit reached (" .. CONFIG.MAX_DOCUMENTS .. ").")
        return nil
    end
    local d = { name = name, text = text or "", lang = lang or "EPL", bps = {}, bpConds = {} }
    table.insert(docs, d)
    return d
end

local function loadDocIntoEditor(i)
    local d = docs[i]
    if not d then return end
    editor.Text = d.text
    syntaxOverlay.Text = ""
    sourceLangIndex = table.find(sourceLanguages, d.lang) or 1
    langBtn.Text = "Src: " .. d.lang
    buildGutter()
    rebuildHighlight()
    updateStatusBar()
end

local function switchDoc(i)
    if i == currentDoc or not docs[i] then return end
    markDirty()
    currentDoc = i
    loadDocIntoEditor(i)
    rebuildTabs()
    rebuildFileList()
end

local function closeDoc(i)
    if #docs <= 1 then
        log("Cannot close the last document.")
        return
    end
    table.remove(docs, i)
    if currentDoc > #docs then currentDoc = #docs end
    if currentDoc >= i and currentDoc > 1 then currentDoc = currentDoc - 1 end
    loadDocIntoEditor(currentDoc)
    rebuildTabs()
    rebuildFileList()
end

-- ============================================================================
-- 17. GUTTER (line numbers + click-to-toggle breakpoints)
-- ============================================================================
local function gutterButtonText(ln)
    local d = docs[currentDoc]
    if d and d.bps[ln] then
        return "● " .. ln
    end
    return tostring(ln)
end

buildGutter = function()
    for _, child in ipairs(gutterScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    local lines = countLines(editor.Text)
    Profiler.computeHeat()
    local capped = math.min(lines, CONFIG.MAX_GUTTER_LINES)
    for ln = 1, capped do
        local gb = mk("TextButton", {
            Size = UDim2.new(1, 0, 0, LINE_HEIGHT),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = gutterButtonText(ln),
            TextColor3 = (docs[currentDoc] and docs[currentDoc].bps[ln]) and C.red or (Profiler.heatColor(ln) or C.gutterText),
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Right,
            AutoButtonColor = false,
            LayoutOrder = ln
        }, gutterScroll)
        gb.Activated:Connect(function()
            local d = docs[currentDoc]
            if not d then return end
            if d.bps[ln] then d.bps[ln] = nil else d.bps[ln] = true end
            buildGutter()
            if d.bps[ln] then
                log("Breakpoint set at line " .. ln .. ".")
            else
                log("Breakpoint removed at line " .. ln .. ".")
            end
        end)
    end
    gutterScroll.CanvasSize = UDim2.new(0, 0, 0, lines * LINE_HEIGHT + 8)

    -- Resize editor textbox so the scroll canvas matches the content
    local viewH = editorScroll.AbsoluteWindowSize.Y
    local contentH = math.max(lines * LINE_HEIGHT + 8, viewH)
    local longest = 0
    for line in (editor.Text .. "\n"):gmatch("([^\n]*)\n") do
        if #line > longest then longest = #line end
    end
    local contentW = math.max(longest * math.ceil(CONFIG.EDITOR_TEXT_SIZE * 0.62) + 40, editorScroll.AbsoluteWindowSize.X)
    editor.Size = UDim2.new(0, contentW, 0, contentH)
    syntaxOverlay.Size = editor.Size
    editorScroll.CanvasSize = UDim2.new(0, contentW, 0, contentH)
end

editorScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    gutterScroll.CanvasPosition = Vector2.new(0, editorScroll.CanvasPosition.Y)
end)

-- ============================================================================
-- 18. SYNTAX HIGHLIGHTING (debounced, token-accurate via the real Lexer)
-- ============================================================================
local function richEscape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local TOKEN_HEX = {
    KEYWORD = "KEYWORD", STRING = "STRING", NUMBER = "NUMBER",
    BOOL_LIT = "NUMBER", NIL_LIT = "NUMBER",
    COMMENT = "COMMENT", OP = "OP", ERROR = "ERROR", IDENT = "IDENT",
    INSTRUCTION = "KEYWORD"
}

rebuildHighlight = function()
    local src = editor.Text
    if #src == 0 then
        syntaxOverlay.Text = ""
        return
    end
    local ok, tokens = pcall(Lexer.lex, src, docLang())
    if not ok then
        syntaxOverlay.Text = richEscape(src)
        return
    end

    -- Map (line, col) to absolute offsets
    local lineStarts = { 1 }
    local pos = 1
    while true do
        local nl = src:find("\n", pos, true)
        if not nl then break end
        table.insert(lineStarts, nl + 1)
        pos = nl + 1
    end

    local parts = {}
    local cursor = 1
    local srcLen = #src
    for _, t in ipairs(tokens) do
        if t.kind == "EOF" then break end
        if t.kind ~= "NEWLINE" and t.kind ~= "INDENT" and t.kind ~= "DEDENT" then
            local start = (lineStarts[t.line] or srcLen + 1) + (t.col or 1) - 1
            if start > srcLen + 1 then break end
            if start >= cursor then
                if start > cursor then
                    table.insert(parts, richEscape(src:sub(cursor, start - 1)))
                end
                local raw = src:sub(start, start + #t.value - 1)
                local hexKey = TOKEN_HEX[t.kind] or "IDENT"
                table.insert(parts, '<font color="' .. C.hex[hexKey] .. '">' .. richEscape(raw) .. "</font>")
                cursor = start + #raw
            end
        end
    end
    if cursor <= srcLen then
        table.insert(parts, richEscape(src:sub(cursor)))
    end
    syntaxOverlay.Text = table.concat(parts)
end

local highlightToken = 0
local function scheduleHighlight()
    highlightToken = highlightToken + 1
    local myToken = highlightToken
    task.delay(CONFIG.DEBOUNCE_DELAY_SEC, function()
        if myToken == highlightToken then
            rebuildHighlight()
        end
    end)
end

-- ============================================================================
-- 19. TABS & FILE LIST
-- ============================================================================
rebuildTabs = function()
    for _, child in ipairs(tabsContainer:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") then child:Destroy() end
    end
    for i, d in ipairs(docs) do
        local tab = mk("Frame", {
            Size = UDim2.new(0, math.max(70, #d.name * 8 + 34), 0, 24),
            BackgroundColor3 = (i == currentDoc) and C.selection or C.panel,
            BorderSizePixel = 0,
            LayoutOrder = i
        }, tabsContainer)
        corner(tab, 5)
        local tabBtn = mk("TextButton", {
            Size = UDim2.new(1, -20, 1, 0),
            BackgroundTransparency = 1,
            Text = d.name,
            TextColor3 = (i == currentDoc) and C.text or C.muted,
            TextSize = 11,
            Font = Enum.Font.Code,
            AutoButtonColor = false
        }, tab)
        tabBtn.Activated:Connect(function() switchDoc(i) end)
        local closeB = mk("TextButton", {
            Position = UDim2.new(1, -18, 0, 2),
            Size = UDim2.fromOffset(16, 20),
            BackgroundTransparency = 1,
            Text = "×",
            TextColor3 = C.muted,
            TextSize = 12,
            Font = Enum.Font.Code,
            AutoButtonColor = false
        }, tab)
        closeB.Activated:Connect(function() closeDoc(i) end)
    end
    tabsContainer.CanvasSize = UDim2.new(0, tabsLayout.AbsoluteContentSize.X + 8, 0, 0)
end

tabsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    tabsContainer.CanvasSize = UDim2.new(0, tabsLayout.AbsoluteContentSize.X + 8, 0, 0)
end)

rebuildFileList = function()
    for _, child in ipairs(fileList:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    for i, d in ipairs(docs) do
        local fb = mk("TextButton", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundColor3 = (i == currentDoc) and C.selection or C.panel2,
            BorderSizePixel = 0,
            Text = "  " .. d.name .. "  [" .. d.lang .. "]",
            TextColor3 = (i == currentDoc) and C.text or C.muted,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false,
            LayoutOrder = i
        }, fileList)
        corner(fb, 4)
        fb.Activated:Connect(function() switchDoc(i) end)
    end
    fileList.CanvasSize = UDim2.new(0, 0, 0, fileLayout.AbsoluteContentSize.Y + 4)
end

-- ============================================================================
-- 20. BUTTON ACTION WIRING & UI ACTION SAFETY
-- ============================================================================
local function countErrors(diags)
    local n = 0
    for _, d in ipairs(diags or {}) do
        if d.severity == "ERROR" then n = n + 1 end
    end
    return n
end

local function showDiagnostics(diags)
    local errors = countErrors(diags)
    for _, d in ipairs(diags or {}) do
        log(string.format("[%s] %s:%s:%s - %s", d.severity or "ERROR", d.stage or "Compiler", d.line or 1, d.col or 1, d.message or "Unknown diagnostic"))
    end
    if errors > 0 then
        statusLabel.Text = string.format("%d compiler error%s", errors, errors == 1 and "" or "s")
        return false
    end
    return true
end

local function parseEditorSource()
    local source = editor.Text or ""
    if #source == 0 then
        statusLabel.Text = "Nothing to compile"
        log("Nothing to compile.")
        return nil
    end
    Profiler.reset()
    local lang = docLang()

    local t0 = os.clock()
    local ok, tokensOrErr = pcall(Lexer.lex, source, lang)
    Profiler.timings.lex = os.clock() - t0
    if not ok then
        log("[Lexer] " .. safeErrorText(tokensOrErr))
        statusLabel.Text = "Lexer error"
        return nil
    end
    Profiler.counts.tokens = #tokensOrErr
    for _, token in ipairs(tokensOrErr) do
        if token.kind == "ERROR" then
            log(string.format("[Lexer] %s:%s - %s", token.line or 1, token.col or 1, tostring(token.value)))
            statusLabel.Text = "Lexer error"
            return nil
        end
    end

    t0 = os.clock()
    local okParse, ast, diags = pcall(parseSourceToAST, source, lang)
    Profiler.timings.parse = os.clock() - t0
    if not okParse then
        log("[Parser] " .. safeErrorText(ast))
        statusLabel.Text = "Parser error"
        return nil
    end
    Profiler.counts.astNodes = ast.nodeCount or 0

    -- Semantic analysis pass (undefined vars, unused vars, unreachable code)
    t0 = os.clock()
    local okSem, semDiags = pcall(SemanticAnalyzer.analyze, ast)
    Profiler.timings.semantic = os.clock() - t0
    if okSem and semDiags then
        for _, d in ipairs(semDiags) do
            table.insert(diags, d)
        end
    end

    if not showDiagnostics(diags) then return nil end
    return ast
end

updateStatusBar = function(extra)
    local pos = editor.CursorPosition
    local ln, col = 1, 1
    if pos and pos > 0 then
        local before = editor.Text:sub(1, pos - 1)
        ln = 1 + select(2, before:gsub("\n", "\n"))
        local lastNl = 0
        while true do
            local p = before:find("\n", lastNl + 1, true)
            if p then lastNl = p else break end
        end
        col = pos - lastNl
    end
    local t = Profiler.timings
    statusLabel.Text = string.format("%s  |  Ln %d, Col %d  |  %s → %s  |  Lex %.0fms Parse %.0fms Sem %.0fms%s",
        extra or "Ready", ln, col, docLang(), targetLanguages[targetIndex],
        t.lex * 1000, t.parse * 1000, t.semantic * 1000,
        VM.state ~= "IDLE" and ("  |  VM: " .. VM.state) or "")
end

local function refreshTheme()
    root.BackgroundColor3 = C.bg
    rootStroke.Color = C.border
    top.BackgroundColor3 = C.panel
    side.BackgroundColor3 = C.panel
    center.BackgroundColor3 = C.bg
    statusBar.BackgroundColor3 = C.panel2
    toolbar.BackgroundColor3 = C.panel
    tabsBar.BackgroundColor3 = C.panel2
    terminal.BackgroundColor3 = Color3.fromRGB(11, 12, 15)
    editorFrame.BackgroundColor3 = C.bg
    gutterScroll.BackgroundColor3 = C.gutter
    editor.TextColor3 = C.text
    syntaxOverlay.TextColor3 = C.text
    title.TextColor3 = C.text
    statusLabel.TextColor3 = C.muted
    sideLabel.TextColor3 = C.muted
    termHeader.TextColor3 = C.muted
    outLabel.TextColor3 = C.text
    consolePanel.BackgroundColor3 = C.panel
    consoleList.BackgroundColor3 = C.bg
    consoleTitle.TextColor3 = C.red
    consoleCount.TextColor3 = C.muted
    consoleCopyBox.TextColor3 = C.text
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextButton") then
            obj.TextColor3 = C.text
        elseif obj:IsA("TextLabel") and obj ~= title and obj ~= statusLabel and obj ~= sideLabel and obj ~= termHeader and obj ~= outLabel and obj ~= consoleTitle and obj ~= consoleCount then
            obj.TextColor3 = C.text
        end
    end
    themeBtn.TextColor3 = C.text
    shareBtn.TextColor3 = C.green
    runBtn.TextColor3 = C.green
    stepBtn.TextColor3 = C.cyan
    contBtn.TextColor3 = C.cyan
    inspBtn.TextColor3 = C.purple
    transBtn.TextColor3 = C.blue
    optBtn.TextColor3 = C.yellow
    targetBtn.TextColor3 = C.text
    langBtn.TextColor3 = C.text
    testBtn.TextColor3 = C.cyan
    clearBtn.TextColor3 = C.muted
    errorsBtn.TextColor3 = C.red
    extraBtns.def.TextColor3 = C.cyan
    extraBtns.rename.TextColor3 = C.purple
    extraBtns.heat.TextColor3 = C.yellow
    extraBtns.back.TextColor3 = C.cyan
    extraBtns.watch.TextColor3 = C.purple
    extraBtns.cond.TextColor3 = C.red
    extraBtns.sentinel.TextColor3 = C.green
    statusLabel.Text = "Theme: " .. currentThemeName .. "  |  " .. docLang() .. " → " .. targetLanguages[targetIndex]
    if applyMajorUIRevamp then applyMajorUIRevamp() end
    rebuildTabs()
    rebuildFileList()
    buildGutter()
    rebuildHighlight()
end

local function safeAction(name, callback)
    return function(...)
        local args = packArgs(...)
        local ok, err = xpcall(function()
            callback(unpackArgs(args, 1, args.n))
        end, function(e)
            local message = safeErrorText(e)
            reportHyperionError(message, "UI:" .. name)
            return message
        end)
        return ok
    end
end

-- ============================================================================
-- 21. DEBUGGER (Step / Continue / Breakpoints / Inspector)
-- ============================================================================
local inspectorPanel = mk("Frame", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -8, 0, 70),
    Size = UDim2.new(0, 300, 0, 320),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 40
}, root)
corner(inspectorPanel, 8)
stroke(inspectorPanel, C.purple)

local inspTitle = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(10, 6),
    Size = UDim2.new(1, -20, 0, 20),
    Text = "DEBUGGER INSPECTOR",
    TextColor3 = C.purple,
    TextSize = 12,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 41
}, inspectorPanel)

local inspBody = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(10, 30),
    Size = UDim2.new(1, -20, 1, -40),
    Text = "No active debug session.",
    TextColor3 = C.text,
    TextSize = 11,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = false,
    ZIndex = 41
}, inspectorPanel)

local function updateInspector()
    if not inspectorPanel.Visible then return end
    local lines = {
        string.format("State: %s   PC: %s   Ops: %d", VM.state, tostring(VM.pc), VM.instructionsExecuted),
        string.format("Call stack depth: %d", #VM.callStack),
        ""
    }
    if #VM.callStack > 0 then
        table.insert(lines, "-- Call Stack --")
        for i = #VM.callStack, math.max(1, #VM.callStack - 5), -1 do
            table.insert(lines, "  " .. tostring(VM.callStack[i].name or "?"))
        end
        table.insert(lines, "")
    end
    table.insert(lines, "-- Registers --")
    local shown = 0
    for name, value in pairs(VM.registers) do
        if value ~= nil and shown < CONFIG.MAX_INSPECTOR_REGS then
            local vs = tostring(value)
            if #vs > 36 then vs = vs:sub(1, 36) .. "…" end
            table.insert(lines, string.format("  %-6s = %s", name, vs))
            shown = shown + 1
        end
    end
    if shown == 0 then table.insert(lines, "  (empty)") end
    table.insert(lines, "")
    table.insert(lines, "-- Environment --")
    local envShown = 0
    for name, value in pairs(VM.environment) do
        if type(value) ~= "function" and type(value) ~= "table" and envShown < 20 then
            local vs = tostring(value)
            if #vs > 30 then vs = vs:sub(1, 30) .. "…" end
            table.insert(lines, string.format("  %s = %s", name, vs))
            envShown = envShown + 1
        end
    end
    if envShown == 0 then table.insert(lines, "  (none)") end
    if #VM.watchList > 0 then
        table.insert(lines, "")
        table.insert(lines, "-- Watch --")
        for _, expr in ipairs(VM.watchList) do
            local okW, val = pcall(VM.evalCondition, expr)
            local shown = okW and tostring(val) or "<error>"
            if #shown > 34 then shown = shown:sub(1, 34) .. "..." end
            table.insert(lines, string.format("  %s = %s", expr, shown))
        end
    end
    inspBody.Text = table.concat(lines, "\n")
end

VM.documentProvider = function(name)
    if type(name) ~= "string" then return nil end
    for _, d in ipairs(docs) do
        local base = d.name:gsub("%.[^.]+$", "")
        if d.name == name or base == name then
            return { source = d.text or "", lang = d.lang or "EPL" }
        end
    end
    return nil
end

local function wireVMCallbacks()
    VM.onOutput = function(s) log(s) end
    VM.onHalt = function(msg)
        log("[VM] " .. tostring(msg))
        debugSessionActive = false
        updateInspector()
    end
    VM.onPause = function(line)
        log("[Debugger] Paused at line " .. tostring(line) .. ".")
        updateInspector()
    end
end

local function compileForRun()
    -- Bytecode source is assembled directly into IR (no AST stage).
    if docLang() == "Bytecode" then
        local source = editor.Text or ""
        if #source == 0 then
            statusLabel.Text = "Nothing to compile"
            log("Nothing to compile.")
            return nil
        end
        Profiler.reset()
        local ok, ir = pcall(HyperionLanguages.parseBytecode, source)
        if not ok then
            log("[Bytecode] " .. safeErrorText(ir))
            statusLabel.Text = "Bytecode error"
            return nil
        end
        if #ir.instructions == 0 then
            log("[Bytecode] No instructions found in source.")
            statusLabel.Text = "Bytecode error"
            return nil
        end
        Profiler.counts.irInstructions = #ir.instructions
        return ir
    end
    local ast = parseEditorSource()
    if not ast then return nil end
    local t0 = os.clock()
    local ir = HyperionIR.fromAST(ast)
    Profiler.timings.ir = os.clock() - t0
    Profiler.counts.irInstructions = #ir.instructions
    return ir
end

local function applyDocBreakpoints()
    local d = docs[currentDoc]
    VM.breakpoints = {}
    VM.breakpointConds = {}
    if d then
        for ln in pairs(d.bps) do VM.breakpoints[ln] = true end
        for ln, cond in pairs(d.bpConds or {}) do
            if VM.breakpoints[ln] then VM.breakpointConds[ln] = cond end
        end
    end
end

local function startDebugSession()
    local ir = compileForRun()
    if not ir then return false end
    VM.init(ir)
    wireVMCallbacks()
    applyDocBreakpoints()
    VM.trace = {}
    VM.traceEnabled = true
    debugSessionActive = true
    return true
end

local function endDebugSessionIfDone()
    if VM.state == "HALTED" then
        debugSessionActive = false
        updateStatusBar("Run finished: HALTED")
    end
    updateInspector()
end

-- ============================================================================
-- 22. SHARE PANEL (Export & Import)
-- ============================================================================
local sharePanel
local function openSharePanel()
    if sharePanel then sharePanel:Destroy() end
    sharePanel = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.82, 0, 0.66, 0), BackgroundColor3 = C.panel,
        BorderSizePixel = 0, ZIndex = 60
    }, root)
    corner(sharePanel, 8); stroke(sharePanel, C.green)
    mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -240, 0, 24), Text = "SHARE CODE", TextColor3 = C.green,
        TextSize = 13, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 61 }, sharePanel)
    local close = button(sharePanel, "Close", C.text); close.Position = UDim2.new(1, -74, 0, 8); close.Size = UDim2.fromOffset(62, 24); close.ZIndex = 62
    local exportTab = button(sharePanel, "Export", C.green); exportTab.Position = UDim2.new(1, -144, 0, 8); exportTab.Size = UDim2.fromOffset(62, 24); exportTab.ZIndex = 62
    local importTab = button(sharePanel, "Import", C.blue); importTab.Position = UDim2.new(1, -214, 0, 8); importTab.Size = UDim2.fromOffset(62, 24); importTab.ZIndex = 62

    local shareBox = mk("TextBox", { Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -20, 1, -88),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, Text = "", TextColor3 = C.text,
        TextSize = 11, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, MultiLine = true,
        ClearTextOnFocus = false, TextEditable = false, ZIndex = 61 }, sharePanel)
    corner(shareBox, 5)

    local actionBtn = button(sharePanel, "Load into editor", C.yellow)
    actionBtn.Position = UDim2.new(0, 10, 1, -36)
    actionBtn.Size = UDim2.fromOffset(150, 24)
    actionBtn.ZIndex = 62
    actionBtn.Visible = false

    local mode = "export"
    local confirmArmed = false

    local function showExport()
        mode = "export"
        actionBtn.Visible = false
        shareBox.TextEditable = false
        local ok, encoded = pcall(Base64.encode, editor.Text or "")
        if ok then
            shareBox.Text = encoded
            shareBox:CaptureFocus()
            shareBox.SelectionStart = 1
            shareBox.CursorPosition = #encoded + 1
            log("Share code generated and selected for copying.")
        else
            shareBox.Text = "Share generation failed: " .. safeErrorText(encoded)
            reportHyperionError(encoded, "Share")
        end
    end

    local function showImport()
        mode = "import"
        confirmArmed = false
        shareBox.TextEditable = true
        shareBox.Text = ""
        actionBtn.Text = "Load into editor"
        actionBtn.Visible = true
        log("Paste a share code, then click 'Load into editor'.")
    end

    exportTab.Activated:Connect(showExport)
    importTab.Activated:Connect(showImport)
    actionBtn.Activated:Connect(function()
        if mode ~= "import" then return end
        if not confirmArmed then
            local decoded, derr = Base64.decode(shareBox.Text)
            if not decoded then
                log("[Share] Import failed: " .. safeErrorText(derr))
                reportHyperionError(derr, "Share:Import")
                return
            end
            confirmArmed = true
            actionBtn.Text = "Confirm replace?"
            log("[Share] Code decoded (" .. #decoded .. " bytes). Click 'Confirm replace?' to load it.")
            return
        end
        local decoded, derr = Base64.decode(shareBox.Text)
        if decoded then
            markDirty()
            local d = newDoc("import_" .. tostring(#docs + 1) .. ".epl", decoded, "EPL")
            if d then
                switchDoc(#docs)
                log("[Share] Imported into new document '" .. d.name .. "'.")
            end
            sharePanel:Destroy()
            sharePanel = nil
        else
            log("[Share] Import failed: " .. safeErrorText(derr))
        end
    end)

    close.Activated:Connect(function() sharePanel:Destroy(); sharePanel = nil end)
    showExport()
end

-- ============================================================================
-- 23. BUTTON WIRING
-- ============================================================================
minBtn.Activated:Connect(safeAction("Minimize", function()
    root.Visible = false; openPill.Visible = true
end))
openPill.Activated:Connect(safeAction("Restore", function()
    root.Visible = true; openPill.Visible = false
end))

themeBtn.Activated:Connect(safeAction("Theme", function()
    local names = {}
    for name in pairs(THEMES) do table.insert(names, name) end
    table.sort(names)
    local current = table.find(names, currentThemeName) or 1
    current = (current % #names) + 1
    currentThemeName = names[current]
    C = THEMES[currentThemeName]
    refreshTheme()
    log("Theme changed to " .. currentThemeName .. ".")
end))

shareBtn.Activated:Connect(safeAction("Share", openSharePanel))

clearBtn.Activated:Connect(safeAction("Clear", function()
    editor.Text = ""
    syntaxOverlay.Text = ""
    markDirty()
    buildGutter()
    statusLabel.Text = "Editor cleared"
    log("Editor cleared.")
end))

newDocBtn.Activated:Connect(safeAction("NewDoc", function()
    markDirty()
    local d = newDoc("doc_" .. tostring(#docs + 1) .. ".epl", "", "EPL")
    if d then
        currentDoc = #docs
        loadDocIntoEditor(currentDoc)
        rebuildTabs()
        rebuildFileList()
        log("Created document '" .. d.name .. "'.")
    end
end))

langBtn.Activated:Connect(safeAction("SourceLang", function()
    sourceLangIndex = (sourceLangIndex % #sourceLanguages) + 1
    local lang = sourceLanguages[sourceLangIndex]
    docs[currentDoc].lang = lang
    langBtn.Text = "Src: " .. lang
    updateStatusBar()
    rebuildFileList()
    rebuildHighlight()
    log("Source language: " .. lang .. ".")
end))

targetBtn.Activated:Connect(safeAction("Target", function()
    targetIndex = (targetIndex % #targetLanguages) + 1
    targetBtn.Text = "Target: " .. targetLanguages[targetIndex]
    updateStatusBar()
end))

transBtn.Activated:Connect(safeAction("Translate", function()
    local target = targetLanguages[targetIndex]
    local result = translateSource(editor.Text or "", docLang(), target)
    local outLang = (target == "Luau" or target == "Lua") and "Lua" or target
    local d = newDoc("out_" .. target:lower() .. "_" .. tostring(#docs + 1), result, outLang == "IR" and "Lua" or outLang)
    if d then
        markDirty()
        switchDoc(#docs)
    end
    log("Translation complete: " .. docLang() .. " → " .. target .. " (opened in new tab).")
end))

optBtn.Activated:Connect(safeAction("Optimize", function()
    local target = targetLanguages[targetIndex]

    -- Bytecode source: optimize the assembled IR directly (no AST stage).
    if docLang() == "Bytecode" then
        local ir = compileForRun()
        if not ir then return end
        local t0 = os.clock()
        local optIR = Optimizer.optimizeIR(ir)
        Profiler.timings.optimize = os.clock() - t0
        local result = (target == "IR") and HyperionIR.disassemble(optIR)
            or HyperionLanguages.toBytecode(optIR)
        local d = newDoc("opt_" .. tostring(#docs + 1), result, target)
        if d then
            markDirty()
            switchDoc(#docs)
        end
        log("Optimization complete (bytecode). Output opened in new tab.")
        return
    end

    local ast = parseEditorSource()
    if not ast then return end
    local t0 = os.clock()
    local optimized = Optimizer.optimizeAST(ast)
    Profiler.timings.optimize = os.clock() - t0
    local result
    if target == "IR" then
        result = HyperionIR.disassemble(Optimizer.optimizeIR(HyperionIR.fromAST(optimized)))
    elseif target == "Bytecode" then
        result = HyperionLanguages.toBytecode(Optimizer.optimizeIR(HyperionIR.fromAST(optimized)))
    elseif target == "Luau" or target == "Lua" then
        result = TargetGen.toLuau(optimized)
    elseif target == "Python" then
        result = TargetGen.toPython(optimized)
    elseif target == "English" then
        result = HyperionLanguages.toEnglish(optimized)
    elseif target == "C" then
        result = HyperionLanguages.toC(optimized, "C")
    elseif target == "C+" then
        result = HyperionLanguages.toC(optimized, "C+")
    elseif target == "C++" then
        result = HyperionLanguages.toC(optimized, "C++")
    elseif target == "Java" then
        result = HyperionLanguages.toJava(optimized)
    else
        result = TargetGen.toEPL(optimized)
    end
    local outLang = target
    if target == "Luau" or target == "IR" then outLang = "Lua" end
    local d = newDoc("opt_" .. tostring(#docs + 1), result, outLang)
    if d then
        markDirty()
        switchDoc(#docs)
    end
    log("Optimization complete. Output opened in new tab (" .. target .. ").")
end))

runBtn.Activated:Connect(safeAction("Run", function()
    if not startDebugSession() then return end
    local t0 = os.clock()
    VM.runContinuous()
    Profiler.timings.runtime = os.clock() - t0
    updateStatusBar("Run finished: " .. VM.state)
    log("Program run finished with VM state: " .. tostring(VM.state) .. ".")
end))

stepBtn.Activated:Connect(safeAction("Step", function()
    if not debugSessionActive then
        if not startDebugSession() then return end
        log("[Debugger] Session started. Stepping…")
    end
    -- Refresh the watchdog deadline so human think-time between steps
    -- does not count against the execution budget.
    VM.deadline = os.clock() + CONFIG.MAX_RUNTIME_SEC
    VM.state = "RUNNING"
    local ok, cont = pcall(VM.step)
    if not ok then
        VM.state = "HALTED"
        VM.lastError = tostring(cont)
        log("[Error] " .. VM.lastError)
        endDebugSessionIfDone()
        return
    end
    if VM.state == "RUNNING" then
        VM.state = "PAUSED"
        local inst = VM.instructions[VM.pc]
        if inst then
            updateStatusBar(string.format("Paused at Ln %d (op %s)", inst.line or 1, tostring(inst.op)))
        end
    end
    if not cont then endDebugSessionIfDone() end
    updateInspector()
end))

contBtn.Activated:Connect(safeAction("Continue", function()
    if not debugSessionActive then
        if not startDebugSession() then return end
    end
    VM.deadline = os.clock() + CONFIG.MAX_RUNTIME_SEC
    VM.runContinuous()
    updateStatusBar("VM: " .. VM.state)
    endDebugSessionIfDone()
end))

inspBtn.Activated:Connect(safeAction("Inspect", function()
    inspectorPanel.Visible = not inspectorPanel.Visible
    if inspectorPanel.Visible then updateInspector() end
end))

testBtn.Activated:Connect(safeAction("Tests", function()
    local results, passed, total = TestRunner.runAll()
    log(string.format("Self-tests: %d/%d passed.", passed, total))
    for _, result in ipairs(results) do
        log(string.format("[%s] %s", result.passed and "PASS" or "FAIL", result.name))
    end
    statusLabel.Text = string.format("Self-tests: %d/%d passed", passed, total)
end))

-- ============================================================================
-- 24. EDITOR EVENTS (autosave, gutter, highlight, cursor tracking)
-- ============================================================================
editor.Focused:Connect(function()
    syntaxOverlay.Visible = false
    editor.TextTransparency = 0
end)

editor.FocusLost:Connect(function()
    markDirty()
    rebuildHighlight()
    syntaxOverlay.Visible = true
    editor.TextTransparency = 1
end)

editor:GetPropertyChangedSignal("Text"):Connect(function()
    if #editor.Text > CONFIG.MAX_SOURCE_BYTES then
        editor.Text = editor.Text:sub(1, CONFIG.MAX_SOURCE_BYTES)
        log("Source truncated at " .. CONFIG.MAX_SOURCE_BYTES .. " bytes.")
    end
    markDirty()
    buildGutter()
    updateStatusBar()
    scheduleHighlight()
end)

editor:GetPropertyChangedSignal("CursorPosition"):Connect(function()
    updateStatusBar()
end)

-- Dragging support
local dragging, dragStart, startPos = false, nil, nil
top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = root.Position
    end
end)
top.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

do
-- ============================================================================
-- 24b. INTELLISENSE UI (completion popup, hover types, go-to-definition, rename)
-- ============================================================================

-- Returns (line, col, textBeforeCaret) for the current editor caret.
local function caretLineCol()
    local pos = editor.CursorPosition or 1
    if pos < 1 then pos = 1 end
    local before = editor.Text:sub(1, pos - 1)
    local ln = 1 + select(2, before:gsub("\n", "\n"))
    local lastNl = 0
    local from = 0
    while true do
        local p = before:find("\n", from + 1, true)
        if p then lastNl = p; from = p else break end
    end
    return ln, pos - lastNl, before
end

local function absoluteOffset(source, line, col)
    local starts = { 1 }
    local pos = 1
    while true do
        local nl = source:find("\n", pos, true)
        if not nl then break end
        table.insert(starts, nl + 1)
        pos = nl + 1
    end
    return (starts[line] or 1) + (col or 1) - 1
end

-- ---- Completion popup ------------------------------------------------------
local completionPopup = mk("Frame", {
    BackgroundColor3 = C.panel, BorderSizePixel = 0, Visible = false, ZIndex = 80
}, root)
corner(completionPopup, 6)
stroke(completionPopup, C.cyan)
local completionList = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, CanvasSize = UDim2.new()
}, completionPopup)
mk("UIListLayout", { Padding = UDim.new(0, 1) }, completionList)

local completionState = { items = {}, index = 1, prefixLen = 0, open = false }
local completionRows = {}

local function hideCompletion()
    completionState.open = false
    completionPopup.Visible = false
    for _, b in ipairs(completionRows) do b:Destroy() end
    completionRows = {}
end

local function acceptCompletion()
    if not completionState.open then return end
    local item = completionState.items[completionState.index]
    if not item then return end
    local pos = editor.CursorPosition or 1
    local startPos = math.max(1, pos - completionState.prefixLen)
    editor.Text = editor.Text:sub(1, startPos - 1) .. item.label .. editor.Text:sub(pos)
    editor.CursorPosition = startPos + #item.label
    editor.SelectionStart = editor.CursorPosition
    hideCompletion()
    markDirty()
    buildGutter()
    scheduleHighlight()
end

local function renderCompletion()
    for _, b in ipairs(completionRows) do b:Destroy() end
    completionRows = {}
    local n = math.min(#completionState.items, 9)
    for i = 1, n do
        local item = completionState.items[i]
        local selected = (i == completionState.index)
        local row = mk("TextButton", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundColor3 = selected and C.selection or C.panel2,
            BackgroundTransparency = selected and 0 or 1,
            BorderSizePixel = 0,
            Text = "  " .. item.label .. (item.type ~= "" and ("   : " .. item.type) or ""),
            TextColor3 = selected and C.text or C.muted,
            TextSize = 11, Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false, LayoutOrder = i
        }, completionList)
        row.Activated:Connect(function()
            completionState.index = i
            acceptCompletion()
        end)
        completionRows[i] = row
    end
    completionList.CanvasSize = UDim2.new(0, 0, 0, math.max(#completionRows * 19, 1))
end

local function refreshCompletion(force)
    if not editor:IsFocused() then hideCompletion(); return end
    local ln, col = caretLineCol()
    local ok, result = pcall(IntelliSense.complete, editor.Text, ln, col, docLang())
    if not ok or type(result) ~= "table" or #result.items == 0 then hideCompletion(); return end
    if not force and #result.prefix == 0 and result.mode ~= "member" then hideCompletion(); return end
    completionState.items = result.items
    completionState.index = 1
    completionState.prefixLen = #result.prefix
    completionState.open = true
    completionPopup.Visible = true
    renderCompletion()

    local pos = editor.CursorPosition or 1
    local linePrefix = editor.Text:sub(1, pos - 1):match("([^\n]*)$") or ""
    local w = TextService:GetTextSize(linePrefix, CONFIG.EDITOR_TEXT_SIZE, Enum.Font.Code, Vector2.new(4000, 60)).X
    local relX = (editor.AbsolutePosition.X + w) - root.AbsolutePosition.X
    local relY = (editor.AbsolutePosition.Y + (ln - 1) * LINE_HEIGHT + LINE_HEIGHT) - root.AbsolutePosition.Y
    relX = math.clamp(relX, 0, math.max(0, root.AbsoluteSize.X - 230))
    relY = math.clamp(relY, 0, math.max(0, root.AbsoluteSize.Y - 120))
    completionPopup.Position = UDim2.fromOffset(relX, relY)
    completionPopup.Size = UDim2.fromOffset(226, math.min(#completionState.items, 9) * 19 + 4)
end

local function moveCompletion(delta)
    if not completionState.open then return end
    local n = math.min(#completionState.items, 9)
    if n > 0 then
        completionState.index = ((completionState.index - 1 + delta) % n) + 1
        renderCompletion()
    end
end

-- ---- Hover tooltip ---------------------------------------------------------
local hoverTip = mk("Frame", {
    BackgroundColor3 = C.panel, BorderSizePixel = 0, Visible = false, ZIndex = 85,
    Size = UDim2.fromOffset(270, 56)
}, root)
corner(hoverTip, 6)
stroke(hoverTip, C.purple)
local hoverLabel = mk("TextLabel", {
    Position = UDim2.fromOffset(7, 4), Size = UDim2.new(1, -14, 1, -8),
    BackgroundTransparency = 1, Text = "", TextColor3 = C.text, TextSize = 11,
    Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true
}, hoverTip)

local function hideHover() hoverTip.Visible = false end

local function hoverAtMouse()
    local loc = UIS:GetMouseLocation()
    local rx = loc.X - editor.AbsolutePosition.X
    local ry = loc.Y - editor.AbsolutePosition.Y
    if rx < 0 or ry < 0 or rx > editor.AbsoluteSize.X or ry > editor.AbsoluteSize.Y then
        hideHover(); return
    end
    local line = math.floor(ry / LINE_HEIGHT) + 1
    local charW = math.max(1, TextService:GetTextSize("0", CONFIG.EDITOR_TEXT_SIZE, Enum.Font.Code, Vector2.new(4000, 60)).X)
    local col = math.floor(rx / charW) + 1
    local ok, info = pcall(IntelliSense.hover, editor.Text, line, col, docLang())
    if not ok or not info then hideHover(); return end
    local where = info.line and string.format("  (line %d)", info.line) or ""
    hoverLabel.Text = string.format("%s : %s  [%s]%s", info.name, info.type, info.kind, where)
    local relX = loc.X - root.AbsolutePosition.X + 14
    local relY = loc.Y - root.AbsolutePosition.Y + 16
    relX = math.clamp(relX, 0, math.max(0, root.AbsoluteSize.X - 280))
    relY = math.clamp(relY, 0, math.max(0, root.AbsoluteSize.Y - 66))
    hoverTip.Position = UDim2.fromOffset(relX, relY)
    hoverTip.Visible = true
end


-- ---- Go to definition ------------------------------------------------------
local function gotoDefinitionAtCursor()
    local ln, col = caretLineCol()
    local ok, def = pcall(IntelliSense.definition, editor.Text, ln, col, docLang())
    if not ok or not def then
        log("[IntelliSense] No definition found for the symbol at the cursor.")
        return
    end
    local offset = absoluteOffset(editor.Text, def.line, def.col)
    editor.CursorPosition = offset
    editor.SelectionStart = offset
    log(string.format("[IntelliSense] '%s' defined at line %d, col %d.", def.name, def.line, def.col))
end

-- ---- Rename symbol ---------------------------------------------------------
local renamePanel
local function openRenameDialog()
    local ln, col = caretLineCol()
    local ok, info = pcall(IntelliSense.hover, editor.Text, ln, col, docLang())
    if not ok or not info then
        log("[IntelliSense] Place the cursor on an identifier to rename it.")
        return
    end
    if renamePanel then renamePanel:Destroy() end
    renamePanel = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(380, 156), BackgroundColor3 = C.panel,
        BorderSizePixel = 0, ZIndex = 90
    }, root)
    corner(renamePanel, 8)
    stroke(renamePanel, C.purple)
    mk("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 10),
        Size = UDim2.new(1, -24, 0, 20), Text = "RENAME SYMBOL", TextColor3 = C.purple,
        TextSize = 13, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91
    }, renamePanel)
    local box = mk("TextBox", {
        Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 28),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, Text = info.name,
        TextColor3 = C.text, TextSize = 13, Font = Enum.Font.Code,
        ClearTextOnFocus = false, ZIndex = 91
    }, renamePanel)
    corner(box, 5)
    local statusLbl = mk("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 72),
        Size = UDim2.new(1, -24, 0, 18), Text = "Renames every reference in this document.",
        TextColor3 = C.muted, TextSize = 11, Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91
    }, renamePanel)
    local okBtn = button(renamePanel, "Rename", C.green)
    okBtn.Position = UDim2.fromOffset(12, 110); okBtn.Size = UDim2.fromOffset(120, 28); okBtn.ZIndex = 91
    local cancelBtn = button(renamePanel, "Cancel", C.muted)
    cancelBtn.Position = UDim2.fromOffset(142, 110); cancelBtn.Size = UDim2.fromOffset(100, 28); cancelBtn.ZIndex = 91

    cancelBtn.Activated:Connect(function()
        if renamePanel then renamePanel:Destroy(); renamePanel = nil end
    end)
    okBtn.Activated:Connect(safeAction("Rename", function()
        local newName = box.Text
        local okR, newSource, count = pcall(IntelliSense.rename, editor.Text, ln, col, newName, docLang())
        if not okR or not newSource then
            statusLbl.Text = "Rename failed: " .. tostring(count or "unknown error")
            statusLbl.TextColor3 = C.red
            return
        end
        if count == 0 then
            statusLbl.Text = "Nothing to rename."
            statusLbl.TextColor3 = C.red
            return
        end
        editor.Text = newSource
        markDirty(); buildGutter(); rebuildHighlight(); updateStatusBar()
        log(string.format("[IntelliSense] Renamed '%s' -> '%s' (%d occurrence%s).", info.name, newName, count, count == 1 and "" or "s"))
        if renamePanel then renamePanel:Destroy(); renamePanel = nil end
    end))
    box:CaptureFocus()
    box.SelectionStart = 1
    box.CursorPosition = #info.name + 1
end


-- ---- Small text-prompt dialog (Watch + conditional breakpoints) ------------
local promptPanel
local function openPromptDialog(title, initial, hint, onAccept)
    if promptPanel then promptPanel:Destroy() end
    promptPanel = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(380, 150), BackgroundColor3 = C.panel,
        BorderSizePixel = 0, ZIndex = 90
    }, root)
    corner(promptPanel, 8)
    stroke(promptPanel, C.cyan)
    mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 10),
        Size = UDim2.new(1, -24, 0, 20), Text = title, TextColor3 = C.cyan, TextSize = 13,
        Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91 }, promptPanel)
    local box = mk("TextBox", { Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 28),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, Text = initial or "", TextColor3 = C.text,
        TextSize = 13, Font = Enum.Font.Code, ClearTextOnFocus = false, ZIndex = 91 }, promptPanel)
    corner(box, 5)
    mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 70),
        Size = UDim2.new(1, -24, 0, 16), Text = hint or "", TextColor3 = C.muted, TextSize = 11,
        Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91 }, promptPanel)
    local okBtn = button(promptPanel, "OK", C.green)
    okBtn.Position = UDim2.fromOffset(12, 108); okBtn.Size = UDim2.fromOffset(90, 28); okBtn.ZIndex = 91
    local cancelBtn = button(promptPanel, "Cancel", C.muted)
    cancelBtn.Position = UDim2.fromOffset(112, 108); cancelBtn.Size = UDim2.fromOffset(90, 28); cancelBtn.ZIndex = 91
    cancelBtn.Activated:Connect(function()
        if promptPanel then promptPanel:Destroy(); promptPanel = nil end
    end)
    okBtn.Activated:Connect(safeAction("PromptAccept", function()
        local text = box.Text
        if promptPanel then promptPanel:Destroy(); promptPanel = nil end
        onAccept(text)
    end))
    box:CaptureFocus()
    box.CursorPosition = #(initial or "") + 1
end

extraBtns.back.Activated:Connect(safeAction("StepBack", function()
    if not debugSessionActive then
        log("[Debugger] Start a session (Step/Run) before rewinding.")
        return
    end
    local target = VM.instructionsExecuted - 1
    VM.rewindTo(target)
    local inst = VM.instructions[VM.pc]
    if inst then
        updateStatusBar(string.format("Rewound to op %d (Ln %d, op %s)", VM.instructionsExecuted, inst.line or 1, tostring(inst.op)))
    end
    log(string.format("[Debugger] Rewound to operation %d.", VM.instructionsExecuted))
    updateInspector()
end))

extraBtns.watch.Activated:Connect(safeAction("Watch", function()
    openPromptDialog("ADD WATCH EXPRESSION", "", "e.g. x + 1  (evaluated against the paused frame)", function(text)
        if text == nil or text == "" then return end
        table.insert(VM.watchList, text)
        log("[Debugger] Watching: " .. text)
        updateInspector()
    end)
end))

extraBtns.cond.Activated:Connect(safeAction("BreakpointCondition", function()
    local ln = caretLineCol()
    local d = docs[currentDoc]
    if not d then return end
    if not d.bps[ln] then
        log(string.format("[Debugger] No breakpoint on line %d - click the gutter number first.", ln))
        return
    end
    d.bpConds = d.bpConds or {}
    openPromptDialog("BREAKPOINT CONDITION (LINE " .. ln .. ")", d.bpConds[ln] or "", "Pause only when this is true. Blank clears it.", function(text)
        if text == nil or text == "" then d.bpConds[ln] = nil else d.bpConds[ln] = text end
        applyDocBreakpoints()
        log(string.format("[Debugger] Breakpoint on line %d condition: %s", ln, d.bpConds[ln] or "(none)"))
    end)
end))

-- ---- Event wiring ----------------------------------------------------------
extraBtns.def.Activated:Connect(safeAction("GoToDefinition", gotoDefinitionAtCursor))
extraBtns.rename.Activated:Connect(safeAction("RenameSymbol", openRenameDialog))

extraBtns.heat.Activated:Connect(safeAction("Heatmap", function()
    heatmapEnabled = not heatmapEnabled
    buildGutter()
    if heatmapEnabled then
        Profiler.computeHeat()
        local hot = Profiler.hotLines(5)
        if #hot == 0 then
            log("[Profiler] Heatmap enabled. Run a program to collect line hit counts.")
        else
            local parts = {}
            for _, h in ipairs(hot) do table.insert(parts, string.format("L%d (%d)", h.line, h.hits)) end
            log("[Profiler] Heatmap enabled. Hottest lines: " .. table.concat(parts, ", "))
        end
    else
        log("[Profiler] Heatmap disabled.")
    end
end))

editor:GetPropertyChangedSignal("CursorPosition"):Connect(function()
    if completionState.open then pcall(refreshCompletion, false) end
end)

editor:GetPropertyChangedSignal("Text"):Connect(function()
    task.defer(function() pcall(refreshCompletion, false) end)
end)

editor.FocusLost:Connect(function()
    hideCompletion()
    hideHover()
end)

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if not editor:IsFocused() then return end
    local key = input.KeyCode
    if completionState.open then
        if key == Enum.KeyCode.Down then
            moveCompletion(1)
        elseif key == Enum.KeyCode.Up then
            moveCompletion(-1)
        elseif key == Enum.KeyCode.Tab then
            acceptCompletion()
        elseif key == Enum.KeyCode.Escape then
            hideCompletion()
        end
    elseif key == Enum.KeyCode.Space and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
        refreshCompletion(true)
    end
end)

UIS.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    if dragging or completionState.open or renamePanel then hideHover(); return end
    pcall(hoverAtMouse)
end)
end

do

-- ---- Sentinel: self-wiring static analysis + conservative auto-patch ------
-- The Sentinel module is auto-detected beside this script. If it is absent the
-- button explains how to install it; everything else in Hyperion keeps working.
local SentinelEngine = nil
do
    local module = script:FindFirstChild("HyperionSentinel")
    if module and module:IsA("ModuleScript") then
        local ok, loaded = pcall(require, module)
        if ok and type(loaded) == "table" and type(loaded.scan) == "function" then
            SentinelEngine = loaded
        end
    end
end

local sentinelPanel
local sentinelBackup = {}   -- [docIndex] = source before the last auto-fix (undo)
local sentinelLastKey = nil
local sentinelLastCount = -1

-- Sentinel is SILENT by default: findings are never written to the terminal, so
-- nobody using the IDE sees them. They are only visible in the Sentinel panel,
-- which the developer opens deliberately. Scanning stays purely static - the
-- Sentinel never executes the document.
local sentinelVerbose = CONFIG.IS_OWNER
local function sentinelLog(msg)
    if sentinelVerbose then log(msg) end
end

local function sentinelScan()
    if not SentinelEngine then return nil end
    local src = editor.Text or ""
    return SentinelEngine.scan(src, docLang(), {
        hostDiagnostics = function(source, lang)
            local ok, ast = pcall(parseSourceToAST, source, lang)
            if not ok or not ast then return {} end
            local okSem, diags = pcall(SemanticAnalyzer.analyze, ast)
            if okSem and type(diags) == "table" then return diags end
            return {}
        end,
    })
end

local function sentinelApplySafe()
    if not SentinelEngine then
        sentinelLog("[Sentinel] HyperionSentinel module not found - install HyperionModules/HyperionSentinel.lua.")
        return
    end
    local src = editor.Text or ""
    local patches = SentinelEngine.proposeFixes(src, docLang(), {})
    if #patches == 0 then
        sentinelLog("[Sentinel] No auto-safe fixes available for this document.")
        return
    end
    local newSource, statsOrReason = SentinelEngine.apply(src, docLang(), patches, {
        parseFn = function(text, lang)
            local ok, ast = pcall(parseSourceToAST, text, lang)
            return ok and ast ~= nil
        end,
    })
    if not newSource then
        sentinelLog("[Sentinel] Refused to patch (guard tripped): " .. tostring(statsOrReason))
        return
    end
    sentinelBackup[currentDoc] = src
    editor.Text = newSource
    markDirty(); buildGutter(); rebuildHighlight(); updateStatusBar()
    sentinelLog(string.format("[Sentinel] Applied %d safe fix(es): %d line(s) changed, %.1f%% of the file retained.",
        statsOrReason.hunks, statsOrReason.added + statsOrReason.removed, statsOrReason.retainedPercent))
end

local function sentinelUndo()
    local saved = sentinelBackup[currentDoc]
    if not saved then
        sentinelLog("[Sentinel] Nothing to undo.")
        return
    end
    editor.Text = saved
    sentinelBackup[currentDoc] = nil
    markDirty(); buildGutter(); rebuildHighlight(); updateStatusBar()
    sentinelLog("[Sentinel] Reverted the last Sentinel patch.")
end

local function sentinelClose()
    if sentinelPanel then sentinelPanel:Destroy(); sentinelPanel = nil end
end

local function sentinelOpen()
    if sentinelPanel then sentinelPanel:Destroy() end
    sentinelPanel = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.7, 0, 0.6, 0), BackgroundColor3 = C.panel,
        BorderSizePixel = 0, ZIndex = 70
    }, root)
    corner(sentinelPanel, 8)
    stroke(sentinelPanel, C.green)
    mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -160, 0, 22), Text = "SENTINEL - STATIC ANALYSIS & SAFE AUTO-PATCH",
        TextColor3 = C.green, TextSize = 13, Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 71 }, sentinelPanel)
    local body = mk("TextBox", { Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 1, -86),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, Text = "", TextColor3 = C.text,
        TextSize = 11, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, MultiLine = true,
        ClearTextOnFocus = false, TextEditable = false, ZIndex = 71 }, sentinelPanel)
    corner(body, 5)

    local function render()
        if not SentinelEngine then
            body.Text = "HyperionSentinel module not installed.\n\nPlace HyperionModules/HyperionSentinel.lua as a child ModuleScript named 'HyperionSentinel'."
            return
        end
        local findings = sentinelScan() or {}
        local lines = { SentinelEngine.summaryText(findings), "" }
        local shown = 0
        for _, f in ipairs(findings) do
            if shown >= 60 then break end
            table.insert(lines, string.format("[%s] %s%s", f.severity or "INFO", f.message or f.rule,
                f.autoSafe and "  (auto-safe)" or ""))
            shown = shown + 1
        end
        if #findings == 0 then table.insert(lines, "No issues detected.") end
        body.Text = table.concat(lines, "\n")
    end

    local scanBtn = button(sentinelPanel, "Scan", C.cyan)
    scanBtn.Position = UDim2.new(1, -74, 0, 8); scanBtn.Size = UDim2.fromOffset(62, 22); scanBtn.ZIndex = 72
    local fixBtn = button(sentinelPanel, "Auto-fix safe", C.green)
    fixBtn.Position = UDim2.new(0, 12, 1, -40); fixBtn.Size = UDim2.fromOffset(120, 26); fixBtn.ZIndex = 72
    local undoBtn = button(sentinelPanel, "Undo", C.yellow)
    undoBtn.Position = UDim2.new(0, 142, 1, -40); undoBtn.Size = UDim2.fromOffset(80, 26); undoBtn.ZIndex = 72
    local closeBtn = button(sentinelPanel, "Close", C.muted)
    closeBtn.Position = UDim2.new(1, -92, 1, -40); closeBtn.Size = UDim2.fromOffset(80, 26); closeBtn.ZIndex = 72

    scanBtn.Activated:Connect(safeAction("SentinelScan", render))
    fixBtn.Activated:Connect(safeAction("SentinelFix", function() sentinelApplySafe(); render() end))
    undoBtn.Activated:Connect(safeAction("SentinelUndo", function() sentinelUndo(); render() end))
    closeBtn.Activated:Connect(safeAction("SentinelClose", sentinelClose))
    render()
end

if CONFIG.IS_OWNER then
    extraBtns.sentinel.Activated:Connect(safeAction("Sentinel", sentinelOpen))
end

-- Background autopilot: keeps watching the active document, reports the health
-- score, and AUTOMATICALLY applies auto-safe fixes with no button press. It only
-- ever runs while the editor is unfocused and the text is stable, and every edit
-- still has to pass the module's hard budget guards. The original source is kept
-- for Undo.
local sentinelAutoEnabled = CONFIG.IS_OWNER
local sentinelAutoKey = nil

local function sentinelAutoTick()
    if not SentinelEngine or not sentinelAutoEnabled then return end
    if editor:IsFocused() then return end
    local src = editor.Text or ""
    local key = hashSource(src, docLang(), "SENTAUTO")
    if key == sentinelAutoKey then return end
    sentinelAutoKey = key

    local patches = SentinelEngine.proposeFixes(src, docLang(), {})
    if #patches > 0 then
        local newSource, statsOrReason = SentinelEngine.apply(src, docLang(), patches, {
            parseFn = function(text, lang)
                local ok, ast = pcall(parseSourceToAST, text, lang)
                return ok and ast ~= nil
            end,
        })
        if newSource then
            sentinelBackup[currentDoc] = src
            editor.Text = newSource
            markDirty(); buildGutter(); rebuildHighlight(); updateStatusBar()
            sentinelLog(string.format("[Sentinel] Auto-patched %d safe fix(es): %d line(s) changed, %.1f%% retained.",
                statsOrReason.hunks, statsOrReason.added + statsOrReason.removed, statsOrReason.retainedPercent))
            return
        elseif statsOrReason then
            sentinelLog("[Sentinel] Auto-patch skipped (guard tripped): " .. tostring(statsOrReason))
        end
    end
    local findings = SentinelEngine.scan(src, docLang(), {})
    if #findings ~= sentinelLastCount then
        sentinelLastCount = #findings
        sentinelLog("[Sentinel] " .. SentinelEngine.summaryText(findings))
    end
end

if SentinelEngine and CONFIG.IS_OWNER then
    editor.FocusLost:Connect(function()
        task.defer(function() pcall(sentinelAutoTick) end)
    end)
    task.spawn(function()
        while root.Parent do
            task.wait(10)
            local ok, err = pcall(sentinelAutoTick)
            if not ok then sentinelLog("[Sentinel] Autopilot error: " .. safeErrorText(err)) end
        end
    end)
end
end

-- ============================================================================
-- 25. INITIALIZATION
-- ============================================================================
newDoc("main.epl", "-- Welcome to EPL Hyperion " .. CONFIG.VERSION .. "\n-- Click a line number to set a breakpoint, then use Step / Cont.\n\nset x = 5 + 10 * 2\nprint x\n\nfor i = 1, 3 do\n    print i\nend\n", "EPL")
loadDocIntoEditor(1)
rebuildTabs()
rebuildFileList()
log("EPL Hyperion " .. CONFIG.VERSION .. " initialized. " .. #docs .. " document(s) open.")
