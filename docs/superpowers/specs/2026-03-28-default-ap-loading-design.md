# Default .ap File Loading

## Problem

The current default.ap path resolution in `main()` uses nested labeled blocks that are hard to follow and leak memory:

1. When `XDG_CONFIG_HOME` is unset, `std.fs.path.join(home, ".config")` allocates but is never freed.
2. The final joined path is never freed, and can't be uniformly freed because `path` is sometimes borrowed (from CLI args) and sometimes owned (from `join`).

## Design

### New function: `resolveDefaultPath`

```zig
fn resolveDefaultPath(allocator: Allocator) error{HomeNotSet, OutOfMemory}![]const u8
```

- Reads `XDG_CONFIG_HOME`. If set, uses it directly (no allocation needed for the base).
- If `XDG_CONFIG_HOME` is unset, reads `HOME`. If `HOME` is also unset, returns `error.HomeNotSet`.
- Joins the config base with `"ap/default.ap"` via `std.fs.path.join`.
- If an intermediate string was allocated (`$HOME/.config`), frees it before returning.
- Returns a heap-allocated path. Caller owns it and must free it.

### Updated `main` callsite

```zig
const path = if (args.len >= 2)
    try allocator.dupe(u8, args[1])
else
    resolveDefaultPath(allocator) catch |err| {
        std.log.err("cannot resolve default config path: {}", .{err});
        return;
    };
defer allocator.free(path);
```

- CLI arg path is duped so ownership is always uniform: caller always frees `path`.
- Errors are caught and logged with `std.log.err`, then `main` returns normally (no stack trace).
- This matches the existing error pattern used for file-read failures.

## Constraints

- No stack traces on user-facing errors. All error paths use `catch` + `std.log.err` + `return`.
- `OutOfMemory` from `resolveDefaultPath` can be caught the same way (clean message, no trace).
