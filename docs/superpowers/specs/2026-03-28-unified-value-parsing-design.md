# Unified Value Parsing for Layer Names and Variable Values

## Problem

The V2 parser has two separate mechanisms for parsing text content:

- **Variable values / instruction arguments** use `next_value()` in the scanner, which reads free-form text (any character) until `{{`, `\n`, or EOF.
- **Layer names** use `next()` in the scanner, which only accepts `is_alpha_numeric` characters (letters, digits, `_`).

This means layer names cannot contain `-`, `/`, `.`, or other common characters. Adding these to `is_alpha_numeric` would also allow them in variable names, which is undesirable.

## Design

### Approach: Parameterized `next_value` with terminator

Unify both parsing paths through `next_value` by adding a `Terminator` parameter that controls which character ends a `VALUE_TEXT` segment.

### Scanner changes

Add a `Terminator` enum and pass it to `next_value`:

```zig
pub const Terminator = enum { newline, left_brace };

pub fn next_value(self: *Self, terminator: Terminator) Token
```

- **`.newline`** — current behavior: `VALUE_TEXT` runs until `{{`, `\n`, or EOF.
- **`.left_brace`** — `VALUE_TEXT` runs until `{{`, single `{`, `\n`, or EOF. When `{` is encountered, peek next: if `{`, it's `DOUBLE_LEFT_BRACE` (interpolation); otherwise, stop before the `{` without consuming it.

### Parser changes

**`resolve_value`** gains a `terminator: Scanner.Terminator` parameter, passed through to `scanner.next_value()`:

```zig
fn resolve_value(self: *Self, scope: *const Scope, terminator: Scanner.Terminator) Error![]const u8
```

Call sites:
- `parse_let` → `resolve_value(scope, .newline)`
- `parse_instruction` → `resolve_value(scope, .newline)`
- `parse_layer` → `resolve_value(scope, .left_brace)`, then trim leading/trailing whitespace

**`parse_layer` rewrite:** Replace the identifier-accumulation loop (`name_parts` ArrayList + `is_identifier_like` checks) with a single call to `resolve_value(scope, .left_brace)`. Trim the result. Then expect and consume `LEFT_BRACE` as before.

### Removals

- `join_with_spaces` — no longer needed; layer names come back as a single resolved string.
- The `name_parts` loop in `parse_layer`.

### Token changes

None. `VALUE_TEXT`, `DOUBLE_LEFT_BRACE`, etc. are reused as-is.

### Whitespace handling

- **Layer names:** `resolve_value` returns the raw text; `parse_layer` trims leading and trailing whitespace.
- **Variable values:** unchanged — `skip_spaces` handles leading whitespace before `resolve_value` is called; trailing whitespace before `\n` is preserved as content.

### Layer name rules

Anything goes until `{`, `\n`, or EOF. No character restrictions. The result is trimmed.

## Tests

Existing tests for multi-word layer names, interpolated layer names, and variable values should continue to pass. New tests:

- Layer name with `-`: `layer my-layer {}`
- Layer name with mixed special chars: `layer foo/bar.baz {}`
- Layer name with embedded interpolation: `layer my-{{env}}-service {}`
- Whitespace trimming: `layer  padded  {}` → name is `padded`
