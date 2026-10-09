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
- `HyperionModules/HyperionStdlib.lua` — named `HyperionStdlib`; overrides the built-in `std` library.
- `HyperionModules/HyperionSentinel.lua` — named `HyperionSentinel`; enables the Sentinel panel + background scanner.

### Sentinel safety contract

- It never regenerates a file: every fix is a small span-based text substitution.
- Only rules flagged `autoSafe` are ever applied automatically; everything else is report-only.
- Hard guards: ≤25 changed lines, ≤2% of the file, ≤20 hunks, ≤5 net-deleted lines, a 64-byte-floor shrink guard, and the result must re-parse. Any breach → refuse and keep the original.
- The original source is kept for one-click Undo; the autopilot only ever edits while the editor is unfocused and the text is stable.
- The Sentinel is **static-only** (it never executes your document) and **silent by default**: findings are never written to the terminal, so nobody using the IDE sees them - they appear only in the Sentinel panel, which the developer opens deliberately.

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
- **Optimizer** — provably safe AST constant folding/algebraic reduction, IR peephole optimization (dead self-move elimination with jump-target remapping) and a **CFG pass**: basic-block construction, unreachable-block elimination, intra-block copy propagation and dead pure-store elimination, all with jump-target remapping.
- **Sandboxed VM** — call frames, closures, a hardened environment (math/string/table only), and a strict watchdog (1.0 s / 100k instructions, recursion and output caps).
- **Standard library & packages** — every program gets a sandbox-safe `std` library (`std.math`, `std.list`, `std.string`, `std.table`, `std.util`) and a `require("name")` package loader that compiles and runs another open document in an isolated sandbox, exporting its globals.
- **Sentinel (optional module)** — a self-wiring, *language-aware* static analyzer and conservative auto-patcher: it scans continuously in the background (no button press needed) and auto-applies safe fixes while the editor is idle for logic bugs (`and/or` ternaries), division by zero, allocation hazards, runaway `while true` loops and unfinished code, and auto-applies only provably-local, semantics-preserving fixes (numeric constant folding, trailing-whitespace, missing final newline). Every patch must pass hard budget guards (max changed lines, max hunks, max net-deleted lines, a byte-floor shrink guard and a mandatory re-parse) or it is refused and the original source is left untouched — so it can never collapse a large script. One-click Undo.
- **Profiler** — per-phase timings plus per-line execution counters rendered as a gutter **heatmap** (Heat toolbar toggle) with a hottest-lines report.
- **Static type inference & IntelliSense** — a conservative type pass (number / string / bool / nil / table / function / any) that powers autocomplete (symbols, keywords, member access), hover types, go-to-definition, find-references and document-wide rename.
- **Debugger** — line breakpoints with optional **conditions**, Step / Continue / **Back (time-travel reverse execution)**, and a live inspector (registers, call stack, environment) with user **watch expressions**.
- **IDE** — multi-document tabs, syntax highlighting driven by the real lexer (per language), four themes, a terminal, a Hyperion console-error viewer, and Base64 share-code export/import.
- **Self-test suite** — 45 built-in tests (Tests button), all passing.

## Safety limits

Source ≤ 100 KB, tokens ≤ 20k, AST nodes ≤ 12k, IR ≤ 25k instructions / 4k registers / 8k constants, calls ≤ 128 args, recursion ≤ 64 frames, output ≤ 10 KB, share payloads ≤ 120 KB. Anything exceeding these is rejected with a clear diagnostic.

## Repository layout

- `EPLHyperion.client.lua` — the entire application (single LocalScript), including an embedded copy of the language engine.
- `HyperionModules/HyperionBase64.lua` — optional Base64 ModuleScript override.
- `HyperionModules/HyperionLanguages.lua` — optional multi-language ModuleScript override (C, C+, C++, Java, English, Bytecode, Luau).
- `HyperionModules/HyperionStdlib.lua` — optional standard-library ModuleScript override (named `HyperionStdlib`).
- `HyperionModules/HyperionSentinel.lua` — self-wiring static analyzer + conservative auto-patcher (named `HyperionSentinel`).
