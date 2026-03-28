# V2 Parser Design

The v2 parser replaces the JSON-per-line v1 format with a custom DSL. It parses `.ap` files into a flat array of `Layer`s using single-pass recursive descent with eager variable resolution.

## Grammar

The format is line-oriented. A file is an implicit root layer body. Each line is one of:

```
let <name> = <value>
layer <name> { <body> }
open <value>
run <value>
print <value>
// comment
```

Values can contain `{{variable}}` interpolation. Multi-word layer names are supported (`layer multi word layer {`).

## Example

```
let var1 = some value
let var2 = {{var1}} resolved

layer accesspoint {
    let repo = https://github.com/bevicted/accesspoint

    layer repo {
        open {{repo}}
    }
    layer issues {
        open {{repo}}/issues
    }
}
```

## Data Model

All types live in `src/parser/models.zig`.

```zig
const Instruction = union(enum) {
    open: []const u8,
    run: []const u8,
    print: []const u8,
};

const Variable = struct {
    name: []const u8,
    value: []const u8, // already resolved
};

const Layer = struct {
    name: []const u8,
    parent: ?usize,
    sublayers: []usize,
    variables: []Variable,
    instructions: []Instruction,
};

const Layers = struct {
    arena: *std.heap.ArenaAllocator,
    items: []Layer,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};
```

- `items[0]` is always the root layer (`name = ""`, `parent = null`).
- Sublayers are stored as indexes into the same `items` array.
- Variables are stored per-layer for scope chain lookups.

## Scanner

The existing scanner (`src/parser/scanner.zig`) is extended with:

### New token kinds

- `DOUBLE_LEFT_BRACE` — `{{`
- `DOUBLE_RIGHT_BRACE` — `}}`
- `VALUE_TEXT` — raw text within a value (everything that isn't `{{`, `}}`, or newline)
- `NEWLINE` — signals end of a value

### Double-brace detection

When `{` is seen, peek ahead. If the next char is `{`, consume both and emit `DOUBLE_LEFT_BRACE`. Otherwise emit `LEFT_BRACE`. Same logic for `}` / `}}`.

### Value mode

A separate `next_value() Token` method for scanning value content. The parser calls this (instead of `next()`) after `=` or a command keyword. In this mode:

- `{{` emits `DOUBLE_LEFT_BRACE`
- `}}` emits `DOUBLE_RIGHT_BRACE`
- `\n` emits `NEWLINE`
- Everything else accumulates into `VALUE_TEXT`

Between `{{` and `}}`, the parser switches back to `next()` to scan exactly one `IDENTIFIER` token (the variable name), then expects `DOUBLE_RIGHT_BRACE`.

This keeps the scanner stateless — the parser drives the mode switch.

## Parser

Single-pass recursive descent in `src/parser/parser.zig`.

### State

- `ArrayList(Layer)` — flat array, grows as layers are found
- Current layer index — used as scope context
- Scanner instance

### Parse functions

```
parse(source) -> Layers
    Create root layer at index 0 (name = "", parent = null)
    Call parse_body(0)
    Convert ArrayList to owned slice, wrap in Layers

parse_body(layer_index)
    Loop on tokens until RIGHT_BRACE or EOF:
        LET   -> parse_let(layer_index)
        LAYER -> parse_layer(layer_index)
        OPEN  -> parse_instruction(layer_index, .open)
        RUN   -> parse_instruction(layer_index, .run)
        PRINT -> parse_instruction(layer_index, .print)
        RIGHT_BRACE -> return
        EOF   -> return (only valid for root)
        else  -> error

parse_let(layer_index)
    Consume IDENTIFIER (variable name)
    Consume EQUAL
    Consume value tokens via next_value until NEWLINE
    Resolve {{var}} by walking scope chain from layer_index
    Append Variable to current layer's variables

parse_layer(parent_index)
    Consume IDENTIFIERs until LEFT_BRACE (multi-word names)
    Create new Layer at next index, parent = parent_index
    Append new index to parent's sublayers
    Consume LEFT_BRACE
    Call parse_body(new_layer_index)
    Consume RIGHT_BRACE

parse_instruction(layer_index, kind)
    Consume value tokens via next_value until NEWLINE
    Resolve {{var}} by walking scope chain
    Create Instruction with resolved string
    Append to current layer's instructions
```

### Variable resolution

A shared helper used by `parse_let` and `parse_instruction`:

1. Collect value segments from `VALUE_TEXT` and interpolation tokens
2. For each `{{name}}`, walk the scope chain: current layer's variables, then parent's, then grandparent's, up to root
3. Concatenate all segments into one resolved `[]const u8` on the arena
4. Error if a variable is not found (with line number)

### Error handling

Parse errors include the line number from the current token. Error cases:

- Unexpected token (e.g., `}` at top level without matching `{`)
- Missing `}` at EOF for non-root layers
- Unresolved variable in `{{name}}`
- Missing `=` after `let <name>`
- Empty layer name

## Scope

Out of scope for this design:

- `input` keyword (user-prompted variables)
- Integration with the TUI (adapting `Layers` to `Entries` or replacing `Entries`)
- CLI argument for selecting v1 vs v2 parser
