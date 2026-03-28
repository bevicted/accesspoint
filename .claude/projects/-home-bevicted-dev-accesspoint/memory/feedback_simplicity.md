---
name: simplicity-focus
description: User values simplicity in the v2 DSL design — keep the language and implementation straightforward
type: feedback
---

The v2 DSL language focus is simplicity. The grammar is line-oriented.

**Why:** The language is a simple config DSL for links/commands, not a general-purpose language. Complexity is the enemy.

**How to apply:** Favor simpler approaches in scanner/parser design. Avoid over-engineering token types or grammar rules. Let the line-oriented nature of the format drive design decisions (e.g., value mode in scanner rather than complex token-by-token reconstruction).
