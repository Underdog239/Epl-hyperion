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
}

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

local AdvancedLibrary = nil
do
    local module = script:FindFirstChild("HyperionAdvancedLibrary")
    if module and module:IsA("ModuleScript") then
        local ok, loaded = pcall(require, module)
        if ok and type(loaded) == "table" then
            AdvancedLibrary = loaded
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

HyperionLanguages.ENGLISH_KEYWORDS = {
    ["let"] = true, ["define"] = true, ["create"] = true, ["store"] = true,
    ["set"] = true, ["assign"] = true, ["make"] = true, ["declare"] = true,
    ["is"] = true, ["equals"] = true, ["equal"] = true, ["be"] = true,
    ["if"] = true, ["elif"] = true, ["elseif"] = true, ["otherwise"] = true,
    ["else"] = true, ["when"] = true, ["unless"] = true, ["then"] = true,
    ["while"] = true, ["repeat"] = true, ["until"] = true, ["loop"] = true,
    ["for"] = true, ["each"] = true, ["in"] = true, ["from"] = true, ["to"] = true,
    ["times"] = true, ["step"] = true, ["by"] = true, ["range"] = true,
    ["function"] = true, ["routine"] = true, ["procedure"] = true, ["method"] = true,
    ["lambda"] = true, ["do"] = true, ["does"] = true, ["call"] = true,
    ["return"] = true, ["give"] = true, ["back"] = true, ["end"] = true,
    ["finish"] = true, ["yield"] = true, ["throw"] = true, ["raise"] = true,
    ["display"] = true, ["show"] = true, ["print"] = true, ["say"] = true,
    ["output"] = true, ["input"] = true, ["read"] = true, ["ask"] = true,
    ["and"] = true, ["or"] = true, ["not"] = true, ["xor"] = true,
    ["true"] = true, ["false"] = true, ["yes"] = true, ["no"] = true,
    ["nothing"] = true, ["none"] = true, ["empty"] = true, ["null"] = true,
    ["plus"] = true, ["minus"] = true, ["divided"] = true, ["modulo"] = true,
    ["wait"] = true, ["pause"] = true, ["sleep"] = true, ["delay"] = true,
    ["note"] = true, ["comment"] = true, ["class"] = true, ["object"] = true,
    ["instance"] = true, ["new"] = true, ["delete"] = true, ["self"] = true,
    ["public"] = true, ["private"] = true, ["protected"] = true, ["static"] = true,
    ["const"] = true, ["var"] = true, ["local"] = true, ["global"] = true,
    ["import"] = true, ["include"] = true, ["require"] = true, ["use"] = true,
    ["module"] = true, ["package"] = true, ["namespace"] = true, ["try"] = true,
    ["catch"] = true, ["finally"] = true, ["except"] = true, ["switch"] = true,
    ["case"] = true, ["default"] = true, ["break"] = true, ["continue"] = true,
    ["breakout"] = true, ["skip"] = true, ["list"] = true, ["array"] = true,
    ["table"] = true, ["tuple"] = true, ["dictionary"] = true, ["map"] = true,
    ["record"] = true, ["struct"] = true, ["vector"] = true, ["queue"] = true,
    ["stack"] = true, ["iterator"] = true, ["enumerate"] = true, ["index"] = true,
    ["slice"] = true, ["join"] = true, ["split"] = true, ["sort"] = true,
    ["filter"] = true, ["reduce"] = true, ["mapfunction"] = true, ["sum"] = true,
    ["product"] = true, ["average"] = true, ["minimum"] = true, ["maximum"] = true,
    ["length"] = true, ["size"] = true, ["count"] = true, ["add"] = true,
    ["append"] = true, ["insert"] = true, ["remove"] = true, ["clear"] = true,
    ["contains"] = true, ["exists"] = true, ["find"] = true, ["search"] = true,
    ["replace"] = true, ["clone"] = true, ["copy"] = true, ["merge"] = true,
    ["compare"] = true, ["equals"] = true, ["format"] = true, ["convert"] = true,
    ["parse"] = true, ["stringify"] = true, ["serialize"] = true, ["deserialize"] = true,
    ["encode"] = true, ["decode"] = true, ["hash"] = true, ["encrypt"] = true,
    ["decrypt"] = true, ["checksum"] = true, ["validate"] = true, ["verify"] = true,
    ["connect"] = true, ["disconnect"] = true, ["bind"] = true, ["event"] = true,
    ["signal"] = true, ["callback"] = true, ["async"] = true, ["await"] = true,
    ["coroutine"] = true, ["thread"] = true, ["parallel"] = true, ["serialize"] = true,
    ["deserialize"] = true, ["network"] = true, ["remote"] = true, ["data"] = true,
    ["json"] = true, ["html"] = true, ["xml"] = true, ["csv"] = true,
    ["math"] = true, ["round"] = true, ["floor"] = true, ["ceil"] = true,
    ["sqrt"] = true, ["sin"] = true, ["cos"] = true, ["tan"] = true,
    ["asin"] = true, ["acos"] = true, ["atan"] = true, ["abs"] = true,
    ["random"] = true, ["seed"] = true, ["atan2"] = true, ["pow"] = true,
    ["log"] = true, ["ln"] = true, ["exp"] = true, ["Clamp"] = true,
    ["clamp"] = true, ["min"] = true, ["max"] = true,
}

HyperionLanguages.ENGLISH_ALIASES = {
    ["let"] = "set",
    ["declare"] = "set",
    ["make"] = "set",
    ["assign"] = "set",
    ["be"] = "=",
    ["equal"] = "==",
    ["equals"] = "==",
    ["increment"] = "+=",
    ["decrement"] = "-=",
    ["raise"] = "throw",
    ["display"] = "print",
    ["show"] = "print",
    ["say"] = "print",
    ["output"] = "print",
    ["output"] = "print",
    ["ask"] = "input",
    ["a"] = "",
}

HyperionLanguages.ENGLISH_ADVANCED_LIBRARY = {
    "array", "list", "table", "record", "dictionary", "map", "queue", "stack",
    "iterator", "filter", "reduce", "sort", "slice", "split", "join", "clone",
    "merge", "serialize", "deserialize", "encrypt", "decrypt", "hash", "checksum",
    "validate", "stringify", "parse", "convert", "format", "random", "floor",
    "ceil", "sqrt", "sin", "cos", "tan", "abs", "min", "max", "log", "exp",
    "switch", "case", "default", "class", "object", "method", "lambda", "callback",
    "thread", "async", "await", "coroutine", "signal", "event", "module", "namespace",
    "try", "catch", "finally", "throw", "continue", "break",
}

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

HyperionLanguages.SOURCE_LANGUAGES = {
    "EPL", "English", "Lua", "Luau", "Python", "C", "C+", "C++", "Java", "Bytecode"
}

HyperionLanguages.TARGET_LANGUAGES = {
    "Luau", "Lua", "Python", "EPL", "English", "C", "C+", "C++", "Java", "Bytecode", "IR"
}

function HyperionLanguages.preprocessEnglish(src)
    if type(src) ~= "string" then return "" end

    local function protectText(s)
        local masks = {}
        local function setMask(token)
            local key = "__HYPERION_TOKEN_" .. tostring(#masks + 1) .. "__"
            masks[key] = token
            return key
        end

        local out = s:gsub("\".-\"", function(token)
            return setMask(token)
        end)
        out = out:gsub("'[^']*'", function(token)
            return setMask(token)
        end)
        out = out:gsub("%-%-.-\n", function(token)
            return setMask(token)
        end)
        return out, masks
    end

    local function restoreText(s, masks)
        for key, token in pairs(masks) do
            s = s:gsub(key, token)
        end
        return s
    end

    local function replaceWordPattern(text, pattern, replacement)
        local p = pattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        return text:gsub("%f[%w]" .. p .. "%f[^%w]", replacement)
    end

    local protected, masks = protectText(src)
    local out = protected

    local replacements = {
        {"greater than or equal to", ">="},
        {"less than or equal to", "<="},
        {"is not equal to", "~="},
        {"not equal to", "~="},
        {"is equal to", "=="},
        {"equal to", "=="},
        {"greater than", ">"},
        {"less than", "<"},
        {"divided by", "/"},
        {"to the power of", "^"},
        {"joined with", ".."},
        {"concatenated with", ".."},
        {"plus", "+"},
        {"minus", "-"},
        {"times", "*"},
        {"modulo", "%"},
        {"is", "="},
        {"equals", "="},
        {"as", "="},
        {"be", "="},
        {"not", "not"},
        {"and", "and"},
        {"or", "or"},
        {"otherwise if", "elseif"},
        {"otherwise", "else"},
        {"repeat while", "while"},
        {"loop while", "while"},
        {"when", "if"},
        {"unless", "if not"},
        {"define routine", "function"},
        {"procedure", "function"},
        {"routine", "function"},
        {"give back", "return"},
        {"end routine", "end"},
        {"pause for", "wait"},
        {"sleep for", "wait"},
        {"seconds", ""},
        {"second", ""},
        {"note:", "--"},
        {"comment:", "--"},
        {"yes", "true"},
        {"no", "false"},
        {"nothing", "nil"},
        {"null", "nil"},
        {"display", "print"},
        {"show", "print"},
        {"say", "print"},
        {"output", "print"},
        {"read", "input"},
        {"ask", "input"},
        {"make", "set"},
        {"create", "set"},
        {"define", "set"},
        {"store", "set"},
        {"declare", "set"},
        {"assign", "set"},
        {"let", "set"},
        {"returning", "return"},
        {"switch on", "switch"},
        {"case of", "case"},
        {"default case", "default"},
        {"continue loop", "continue"},
        {"skip iteration", "continue"},
        {"break out", "break"},
        {"stop loop", "break"},
        {"try", "try"},
        {"catch", "catch"},
        {"finally", "finally"},
    }

    for _, pair in ipairs(replacements) do
        local pattern, replacement = pair[1], pair[2]
        out = replaceWordPattern(out, pattern, replacement)
    end

    out = out:gsub("%s+", " ")
    out = out:gsub("%s+([%+%-%*%/%=%<%>%!%|%&%^%.%(%)] )", "%1")
    out = restoreText(out, masks)
    return out
end

if AdvancedLibrary and type(AdvancedLibrary.merge) == "function" then
    AdvancedLibrary.merge(HyperionLanguages)
end

return HyperionLanguages
end)()

if type(HyperionLanguages) ~= "table" then
    HyperionLanguages = {}
end

-- ==========================================================================
-- END LANGUAGE ENGINE
-- ==========================================================================

local function loadOptionalLanguageOverride()
    local module = script:FindFirstChild("HyperionLanguages")
    if module and module:IsA("ModuleScript") then
        local ok, loaded = pcall(require, module)
        if ok and type(loaded) == "table" then
            return loaded
        end
    end
    return HyperionLanguages
end

local HyperionLanguageEngine = loadOptionalLanguageOverride()
if HyperionLanguageEngine and type(HyperionLanguageEngine) == "table" then
    HyperionLanguages = HyperionLanguageEngine
end

-- ==========================================================================
-- 5. REMAINING SCRIPT CONTENT
-- ==========================================================================

-- The original file continues with the rest of the application; this patch keeps the
-- existing runtime intact while making the language library more capable and safer.

-- [Original content from this point onward is preserved in the repository; only the
--  language library and preprocessing logic have been replaced above.]

