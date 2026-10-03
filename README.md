# EPL Hyperion

A fully client-side, self-contained Roblox IDE, compiler, and sandboxed VM — all in a single LocalScript. No server, no RemoteEvents, no DataStore.

**Version 2.1.0 — Debugger & IDE Edition**

## Install

1. In Roblox Studio, create a **LocalScript** in `StarterPlayer > StarterPlayerScripts`.
2. Paste the contents of `EPLHyperion.client.lua` into it.
3. Press Play. The Hyperion window appears; use the side "Hyperion" pill to reopen it after minimizing.

`HyperionModules/HyperionBase64.lua` is an optional ModuleScript (place it as a child of the LocalScript, named `HyperionBase64`). If absent, Hyperion uses its built-in Base64 implementation.

## What it is

Hyperion is a small teaching-language (**EPL**) plus a full toolchain that runs entirely on the client:

- **Lexer / Parser / AST** for three source languages: EPL, Lua, and Python (Python with real INDENT/DEDENT handling, `elif` chains, `def`, `while`).
- **Semantic analyzer** — undefined-variable errors, unused-variable warnings, unreachable-code and `while true` loop warnings.
- **Hyperion IR** — source-mapped pseudo-bytecode with a strict validator.
- **Optimizer** — provably safe constant folding and algebraic reductions.
- **Sandboxed VM** — call frames, closures, a hardened environment (math/string/table only), and a strict watchdog (1.0 s / 100k instructions, recursion and output caps).
- **Translator** — EPL ⇄ Luau ⇄ Python ⇄ IR, with a full-source-hash LRU cache.
- **Step debugger** — click a line number to set a breakpoint, then Step / Continue, with a live inspector (registers, call stack, environment).
- **IDE** — multi-document tabs, syntax highlighting driven by the real lexer, four themes, a terminal, a Hyperion console-error viewer, and Base64 share-code export/import.
- **Self-test suite** — 25 built-in tests (Tests button), all passing.

## Safety limits

Source ≤ 100 KB, tokens ≤ 20k, AST nodes ≤ 12k, IR ≤ 25k instructions / 4k registers / 8k constants, calls ≤ 128 args, recursion ≤ 64 frames, output ≤ 10 KB, share payloads ≤ 120 KB. Anything exceeding these is rejected with a clear diagnostic.

## Repository layout

- `EPLHyperion.client.lua` — the entire application (single LocalScript).
- `HyperionModules/HyperionBase64.lua` — optional Base64 ModuleScript override.
