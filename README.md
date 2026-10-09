# EPL Hyperion

A fully client-side, self-contained Roblox IDE, multi-language compiler, and sandboxed VM — all in a single LocalScript. No server, no RemoteEvents, no DataStore.

**Version 3.0.0 — Polyglot Compiler & IDE Edition**

## Install

1. In Roblox Studio, create a **LocalScript** in `StarterPlayer > StarterPlayerScripts`.
2. Paste the contents of `EPLHyperion.client.lua` into it.
3. Press Play. The Hyperion window appears; use the side "Hyperion" pill to reopen it after minimizing.

Optional ModuleScripts (place them as children of the LocalScript):

- `HyperionModules/HyperionBase64.lua` — named `HyperionBase64`; overrides the built-in Base64 codec.
- `HyperionModules/HyperionLanguages.lua` — named `HyperionLanguages`; overrides the built-in multi-language engine.

If either module is absent, Hyperion uses its own built-in implementation, so the script is fully self-contained.

## What it is

Hyperion is a small teaching-language (**EPL**) plus a full polyglot toolchain that runs entirely on the client.

### Source languages (lexer / parser / diagnostics)

- **EPL** — the native teaching language.
- **English** — a natural-language programming dialect (`define x as 5 plus 3`, `display x`, `repeat while …`, `otherwise`, …), normalized to EPL before parsing.
- **Lua** and **Luau** — parsed and executed.
- **Python** — real INDENT/DEDENT handling, `elif` chains, `def`, `while`, and `for … in range([start,] stop [, step])`.
- **C**, **C+**, **C++**, **Java** — a practical C-family subset: typed declarations, assignments, `if/else`, `while`, `for`, functions, `return`, and `printf` / `cout <<` / `System.out.println`.
- **Bytecode** — the textual Hyperion IR disassembly can be re-assembled and executed.

### Target languages (translation)

`Luau`, `Lua`, `Python`, `EPL`, `English`, `C`, `C+`, `C++`, `Java`, `Bytecode`, and `IR` — every source language can be translated to every compatible target, with a full-source-hash LRU cache.

### Toolchain

- **Lexer / Parser / AST** for all of the above.
- **Semantic analyzer** — undefined-variable errors, unused-variable warnings, unreachable-code and `while true` loop warnings.
- **Hyperion IR** — source-mapped pseudo-bytecode with a strict validator.
- **Optimizer** — provably safe AST constant folding/algebraic reduction plus IR peephole optimization (dead self-move elimination with jump-target remapping).
- **Sandboxed VM** — call frames, closures, a hardened environment (math/string/table only), and a strict watchdog (1.0 s / 100k instructions, recursion and output caps).
- **Static type inference & IntelliSense** — a conservative type pass (number / string / bool / nil / table / function / any) that powers autocomplete (symbols, keywords, member access), hover types, go-to-definition, find-references and document-wide rename.
- **Step debugger** — click a line number to set a breakpoint, then Step / Continue, with a live inspector (registers, call stack, environment).
- **IDE** — multi-document tabs, syntax highlighting driven by the real lexer (per language), four themes, a terminal, a Hyperion console-error viewer, and Base64 share-code export/import.
- **Self-test suite** — 38 built-in tests (Tests button), all passing.

## Safety limits

Source ≤ 100 KB, tokens ≤ 20k, AST nodes ≤ 12k, IR ≤ 25k instructions / 4k registers / 8k constants, calls ≤ 128 args, recursion ≤ 64 frames, output ≤ 10 KB, share payloads ≤ 120 KB. Anything exceeding these is rejected with a clear diagnostic.

## Repository layout

- `EPLHyperion.client.lua` — the entire application (single LocalScript), including an embedded copy of the language engine.
- `HyperionModules/HyperionBase64.lua` — optional Base64 ModuleScript override.
- `HyperionModules/HyperionLanguages.lua` — optional multi-language ModuleScript override (C, C+, C++, Java, English, Bytecode, Luau).
