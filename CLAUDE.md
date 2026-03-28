# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
zig build          # Build the project (output: zig-out/bin/ap)
zig build run      # Build and run
zig build test     # Run all inline test blocks
```

## Project Overview

AccessPoint (`ap`) is a terminal-based link/command manager written in Zig. It parses structured `.ap` files and presents entries in an interactive TUI for searching and opening URLs or running commands.

## Architecture

```
main.zig → parser.zig → entries.zig   (parse .ap file into Entries)
         → tui.zig                     (launch vaxis-based TUI with parsed entries)
```

- **`entries.zig`** — Core data types: `Entries` (collection with arena + parent tracking) and `Entry` (name, url, id, tags)
- **`parser.zig`** — V1 parser: reads JSON-object-per-line format with indentation-based hierarchy
- **`tui.zig`** — Interactive TUI using `vaxis` framework; Model-View pattern with real-time filtering, navigation, and system command execution (xdg-open/open)

### V2 Parser (WIP, `src/parser/`)

A new DSL replacing the JSON-per-line format. Supports `layer` blocks, `let` variables with `{{interpolation}}`, and commands (`open`, `run`, `print`).

- **`scanner.zig`** — Lexical tokenizer
- **`token.zig`** — Token type definitions (keywords: LAYER, LET, OPEN, PRINT, RUN)
- **`parser.zig`** — Syntax parser (incomplete)
- **`models.zig`** — Layer data structures

## Code Conventions

- **Naming**: `snake_case` for functions/variables, `PascalCase` for types, `UPPER_CASE` for constants
- **Memory**: Every function takes `allocator: Allocator`; use arena allocators for bulk alloc/dealloc; always `defer deinit()`
- **Testing**: Inline `test` blocks in the same source file; test data lives in `test.ap` and `v2.ap`
- **Dependencies**: `vaxis` v0.5.1 (terminal UI framework); otherwise standard library only

## Design Constraints (from concept.txt)

- Do NOT identify/validate URLs
- No multiline objects
- No comments after objects
- IDs must be unique
