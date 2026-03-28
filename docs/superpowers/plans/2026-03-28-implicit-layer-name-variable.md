# Implicit `layer_name` Variable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each layer automatically has a `layer_name` variable set to its resolved name, with root named `"accesspoint"`.

**Architecture:** Prepend an implicit `Variable` into each layer's scope at parse time. Reverse `lookup_variable` iteration so later declarations shadow earlier ones (enabling `let layer_name = ...` to override the implicit).

**Tech Stack:** Zig, inline tests

**Spec:** `docs/superpowers/specs/2026-03-28-implicit-layer-name-variable-design.md`

---

### Task 1: Reverse `lookup_variable` iteration direction

**Files:**
- Modify: `src/parser/parser.zig:216-226` (`lookup_variable`)
- Modify: `src/parser/parser.zig` (new test)

- [ ] **Step 1: Write failing test for same-scope redeclaration**

Add this test at the end of the test block in `src/parser/parser.zig`:

```zig
test "same-scope redeclaration shadows earlier" {
    const result = try parse(std.testing.allocator,
        \\let x = first
        \\let x = second
        \\layer foo {
        \\    open {{x}}
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("second", result.items[1].instructions[0].open);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL — the forward iteration finds `"first"` instead of `"second"`

- [ ] **Step 3: Reverse iteration in `lookup_variable`**

Replace lines 216-226 of `src/parser/parser.zig`:

```zig
fn lookup_variable(self: *Self, scope: *const Scope, name: []const u8) ?[]const u8 {
    _ = self;
    var current: ?*const Scope = scope;
    while (current) |s| {
        var i = s.vars.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, s.vars[i].name, name)) return s.vars[i].value;
        }
        current = s.parent;
    }
    return null;
}
```

- [ ] **Step 4: Run all tests to verify they pass**

Run: `zig build test 2>&1 | tail -5`
Expected: All tests pass (existing shadowing tests use cross-scope which works either direction)

- [ ] **Step 5: Commit**

```bash
git add src/parser/parser.zig
git commit -m "parser: reverse lookup_variable iteration so last declaration shadows"
```

---

### Task 2: Inject implicit `layer_name` variable

**Files:**
- Modify: `src/parser/parser.zig:31-60` (`parse`, root layer creation)
- Modify: `src/parser/parser.zig:74-123` (`parse_body`)
- Modify: `src/parser/parser.zig:125-153` (`parse_layer`, pass name to `parse_body`)

- [ ] **Step 1: Write failing tests for implicit `layer_name`**

Add these tests at the end of the test block in `src/parser/parser.zig`:

```zig
test "root layer has implicit layer_name" {
    const result = try parse(std.testing.allocator,
        \\layer foo {
        \\    open {{layer_name}}
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("accesspoint", result.items[0].name);
    try std.testing.expectEqualStrings("layer_name", result.items[0].variables[0].name);
    try std.testing.expectEqualStrings("accesspoint", result.items[0].variables[0].value);
    try std.testing.expectEqualStrings("foo", result.items[1].instructions[0].open);
}

test "layer has implicit layer_name" {
    const result = try parse(std.testing.allocator,
        \\layer my-service {
        \\    print {{layer_name}}
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("layer_name", result.items[1].variables[0].name);
    try std.testing.expectEqualStrings("my-service", result.items[1].variables[0].value);
    try std.testing.expectEqualStrings("my-service", result.items[1].instructions[0].print);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL — root name is `""`, no implicit variable exists, `layer_name` is unresolved

- [ ] **Step 3: Implement the changes**

**3a.** Change `parse_body` signature to accept `layer_name`:

Replace the function signature at line 74:
```zig
fn parse_body(self: *Self, layer_index: usize, is_root: bool, parent_scope: ?*const Scope, layer_name: []const u8) Error!void {
```

**3b.** Prepend implicit variable. After the three `ArrayList` declarations (line 77), add:

```zig
    try variables.append(self.arena, .{ .name = "layer_name", .value = layer_name });
```

**3c.** Set root layer name to `"accesspoint"`. In `parse` (line 46), change:
```zig
        .name = "accesspoint",
```

**3d.** Update root call to `parse_body`. In `parse` (line 54), change:
```zig
    try self.parse_body(0, true, null, "accesspoint");
```

**3e.** Update `parse_layer` to pass the resolved name. In `parse_layer` (line 150), change:
```zig
    try self.parse_body(new_index, false, parent_scope, name);
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `zig build test 2>&1 | tail -20`
Expected: New tests pass, but some existing tests fail due to shifted variable indices and root name change

- [ ] **Step 5: Update existing tests for shifted variable indices and root name**

The implicit `layer_name` is now `variables[0]` in every layer, pushing user-declared variables up by 1.

**"parse empty input"** — root name changed:
```zig
    try std.testing.expectEqualStrings("accesspoint", result.items[0].name);
```

**"parse let binding"** — variable count and index:
```zig
    try std.testing.expectEqual(@as(usize, 2), result.items[0].variables.len);
    try std.testing.expectEqualStrings("x", result.items[0].variables[1].name);
    try std.testing.expectEqualStrings("hello world", result.items[0].variables[1].value);
```

**"parse let with interpolation"** — indices shift:
```zig
    try std.testing.expectEqualStrings("hello", result.items[0].variables[1].value);
    try std.testing.expectEqualStrings("hello world", result.items[0].variables[2].value);
```

**"parse variable scope chain"** — child variable index:
```zig
    try std.testing.expectEqualStrings("parent_val extended", result.items[1].variables[1].value);
```

**"parse let with keyword name"** — index shift:
```zig
    try std.testing.expectEqualStrings("layer", result.items[0].variables[1].name);
    try std.testing.expectEqualStrings("myvalue", result.items[0].variables[1].value);
```

**"parse full v2.ap"** — root variables and sub-layer variables shift:
```zig
    // Root (index 0) — variables shift by 1
    try std.testing.expectEqualStrings("some value", result.items[0].variables[1].value);
    try std.testing.expectEqualStrings("some value resolved", result.items[0].variables[2].value);

    // accesspoint (index 1) — variable shift by 1
    try std.testing.expectEqualStrings("https://github.com/bevicted/accesspoint", result.items[1].variables[1].value);

    // get (index 9) — variable shift by 1
    try std.testing.expectEqualStrings("kubectl get", result.items[9].variables[1].value);

    // get > pod (index 10) — variable shift by 1
    try std.testing.expectEqualStrings("kubectl get pod", result.items[10].variables[1].value);
```

- [ ] **Step 6: Run all tests to verify they pass**

Run: `zig build test 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add src/parser/parser.zig
git commit -m "parser: add implicit layer_name variable to every layer"
```

---

### Task 3: Test edge cases

**Files:**
- Modify: `src/parser/parser.zig` (new tests)

- [ ] **Step 1: Write edge case tests**

Add these tests at the end of the test block in `src/parser/parser.zig`:

```zig
test "nested layers each get their own layer_name" {
    const result = try parse(std.testing.allocator,
        \\layer outer {
        \\    layer inner {
        \\        print {{layer_name}}
        \\    }
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("outer", result.items[1].variables[0].value);
    try std.testing.expectEqualStrings("inner", result.items[2].variables[0].value);
    try std.testing.expectEqualStrings("inner", result.items[2].instructions[0].print);
}

test "explicit let shadows implicit layer_name" {
    const result = try parse(std.testing.allocator,
        \\layer original {
        \\    let layer_name = override
        \\    print {{layer_name}}
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("override", result.items[1].instructions[0].print);
}

test "interpolated layer name in layer_name variable" {
    const result = try parse(std.testing.allocator,
        \\let env = prod
        \\layer my-{{env}}-service {
        \\    print {{layer_name}}
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("my-prod-service", result.items[1].variables[0].value);
    try std.testing.expectEqualStrings("my-prod-service", result.items[1].instructions[0].print);
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -5`
Expected: All pass — the implementation from Task 2 already handles these cases

- [ ] **Step 3: Commit**

```bash
git add src/parser/parser.zig
git commit -m "parser: add edge case tests for implicit layer_name"
```
