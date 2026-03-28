# Default .ap Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract default.ap path resolution into a clean function that owns its memory and doesn't leak.

**Architecture:** New `resolveDefaultPath` function in `main.zig` handles XDG/HOME lookup and returns a heap-allocated path. `main` dupes CLI arg paths so ownership is always uniform: caller always frees.

**Tech Stack:** Zig standard library (`std.fs.path.join`, `std.posix.getenv`)

---

### Task 1: Add `resolveDefaultPath` and update `main`

**Files:**
- Modify: `src/main.zig:19-29`

- [ ] **Step 1: Write the `resolveDefaultPath` function**

Add this function after `main` (before `collect_instructions`), at line 50 in the current file:

```zig
fn resolveDefaultPath(allocator: Allocator) error{ HomeNotSet, OutOfMemory }![]const u8 {
    const xdg = std.posix.getenv("XDG_CONFIG_HOME");
    const config_base = xdg orelse blk: {
        const home = std.posix.getenv("HOME") orelse return error.HomeNotSet;
        break :blk try std.fs.path.join(allocator, &.{ home, ".config" });
    };
    defer if (xdg == null) allocator.free(config_base);
    return try std.fs.path.join(allocator, &.{ config_base, "ap", "default.ap" });
}
```

Note: `xdg` tracks whether we allocated `config_base`. When `XDG_CONFIG_HOME` is set, `config_base` points to env memory and must not be freed. When it's null, we allocated via `join` and the `defer` cleans it up.

- [ ] **Step 2: Replace the path resolution block in `main`**

Replace lines 19-29 (the `const path = if (args.len >= 2) args[1] else blk: { ... }` block) with:

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

- [ ] **Step 3: Build and verify no leaks**

Run: `zig build`
Expected: Clean build, no errors.

Then run with no args and no HOME (to test the error path):

```bash
env -u HOME -u XDG_CONFIG_HOME zig-out/bin/ap
```

Expected: Clean error message like `error: cannot resolve default config path: error.HomeNotSet`, no stack trace.

Then run with a valid file to verify normal operation still works:

```bash
zig-out/bin/ap v2.ap
```

Expected: TUI launches normally.

- [ ] **Step 4: Run tests**

Run: `zig build test`
Expected: All tests pass (this change doesn't affect parser/TUI tests).

- [ ] **Step 5: Commit**

```bash
git add src/main.zig
git commit -m "extract resolveDefaultPath, fix memory leaks in default.ap loading"
```
