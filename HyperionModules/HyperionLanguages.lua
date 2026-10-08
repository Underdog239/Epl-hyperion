-- EPL Hyperion - HyperionLanguages Module
-- Multi-language lexer/parser/codegen extensions
-- Supports: C, C+, C++, Java, Lua, Luau, Python, Bytecode, English
-- Place as a ModuleScript sibling to HyperionBase64

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
                table.insert(lines, string.format("  [%04d]  STR   %q", i - 1, k))
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
        elseif ("+-*/%^=<>!&|?:.,;()[]{}#"):find(c, 1, true) then
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

    parseExpr = function()
        local left = parsePrimary()
        return parseBinRhs(left, 0)
    end

    parseBinRhs = function(left, minPrec)
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
            local right = parsePrimary()
            -- fold left-assoc
            while true do
                local op2 = cur().value
                local p2 = prec[op2]
                if not p2 or p2 <= p then break end
                local r2 = parseBinRhs(parsePrimary(), p2)
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

    parsePrimary = function()
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
            local operand = parsePrimary()
            count()
            return { tag = "unary", op = (op == "!" and "not" or op), operand = operand, line = t.line, col = t.col }
        elseif t.value == "(" then
            take()
            local e = parseExpr()
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
                constants[#constants + 1] = val
            else
                local num = trimmed:match("NUM%s+([%-%d%.eE]+)")
                if num then constants[#constants + 1] = tonumber(num)
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
