# TUI Integration Design

Integrate the v2 parser with the TUI, replacing the v1 parser and Entries model entirely. The TUI navigates Layers and returns selected instructions. main.zig handles execution.

## Data Flow

```
main.zig:
  1. Read CLI arg for file path (error with usage if missing)
  2. Read file contents
  3. Parse with v2 parser → Layers
  4. Pass Layers to TUI
  5. TUI returns []Instruction (empty = user quit without selecting)
  6. Execute instructions in sequence (root→leaf order)
  7. Clean up
```

The TUI is focused on display and navigation only. Execution happens in main.zig after the TUI quits.

## TUI Model

```zig
Model:
  layers: models.Layers
  current_layer: usize              // starts at 0 (root), replaces current_parent: ?usize
  selected_instructions: []Instruction  // set on leaf submit, read by main after quit
  arena, filtered, list_view, text_field  // unchanged from v1
```

### Navigation

- **repopulate_list**: iterate `layers.items[current_layer].sublayers`, display each sublayer by its `name`
- **Escape**: set `current_layer = layers.items[current_layer].parent orelse return` (at root, do nothing)
- **Submit on sublayer with children**: `current_layer = selected_sublayer_index`, repopulate
- **Submit on leaf** (layer with `sublayers.len == 0`): collect instructions from root→leaf path, store in `selected_instructions`, quit

### Instruction Collection

When a leaf layer is selected, walk the `parent` chain from the leaf back to root, collecting each layer's instructions. Reverse the collected list so root's instructions execute first, then each child's, ending with the leaf's.

### Display

Each item in the filtered list is a sublayer shown by `name`. The existing `filter` function operates on the name string for fuzzy matching. `DisplayItem` stores a layer index instead of an entry index.

## Instruction Execution (main.zig)

After TUI returns, if `selected_instructions` is empty, exit. Otherwise execute each in order:

- **`open`**: `xdg-open <url>` (Linux) / `open <url>` (macOS) via `std.process.Child`
- **`run`**: `sh -c "<command>"` via `std.process.Child`
- **`print`**: write value to stdout

Errors from `open`/`run` are printed to stderr but do not stop execution of remaining instructions.

## CLI Argument

`main.zig` reads `std.process.args()` for the file path. If no argument is provided, print a usage message and exit.

## File Changes

| Action | File | What |
|--------|------|------|
| Modify | `main.zig` | CLI arg, v2 parser, file reading, instruction execution |
| Modify | `tui.zig` | Layers instead of Entries, sublayer navigation, instruction collection |
| Delete | `src/parser.zig` | v1 parser |
| Delete | `src/entries.zig` | v1 data model |
| Delete | `test.ap` | v1 format file |
