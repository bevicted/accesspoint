# Unified Value Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify layer name and variable value parsing through a parameterized `next_value` so layer names accept any characters (not just alphanumeric).

**Architecture:** Add a `Terminator` enum to the scanner. `next_value` takes a `Terminator` to decide what ends a `VALUE_TEXT` segment. The parser's `resolve_value` passes the terminator through, and `parse_layer` switches from identifier accumulation to `resolve_value(.left_brace)` + trim.

**Tech Stack:** Zig, inline tests (`zig build test`)

---

### Task 1: Scanner — Add Terminator enum and update `next_value` signature

**Files:**
- Modify: `src/parser/scanner.zig:149-177` (next_value function)
- Modify: `src/parser/scanner.zig:231-271` (existing next_value tests)

- [ ] **Step 1: Write failing test for `.left_brace` terminator — plain text**

Add this test at the end of `src/parser/scanner.zig`:

```zig
test "next_value left_brace plain text" {
    var s = Self.init("my-layer {");
    const tok = s.next_value(.left_brace);
    try std.testing.expectEqual(.VALUE_TEXT, tok.kind);
    try std.testing.expectEqualStrings("my-layer ", tok.lexeme);
    try std.testing.expectEqual(.LEFT_BRACE, s.next_value(.left_brace).kind);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test --summary all 2>&1 | tail -20`
Expected: compilation error — `next_value` doesn't accept arguments yet.

- [ ] **Step 3: Add `Terminator` enum and update `next_value` to accept it**

In `src/parser/scanner.zig`, add the enum before `next_value`:

```zig
pub const Terminator = enum { newline, left_brace };
```

Update `next_value` signature and implementation:

```zig
pub fn next_value(self: *Self, terminator: Terminator) Token {
    self.current_token_start = self.current_token_end;

    if (self.is_at_end()) return self.make_token(.EOF);

    const c = self.source[self.current_token_end];

    if (c == '{') {
        if (self.peek_next() == '{') {
            self.advance();
            self.advance();
            return self.make_token(.DOUBLE_LEFT_BRACE);
        }
        if (terminator == .left_brace) {
            // Single { is our terminator — don't consume it
            return self.make_token(.LEFT_BRACE);
        }
    }

    if (c == '\n') {
        self.advance();
        self.line += 1;
        return self.make_token(.NEWLINE);
    }

    // Consume VALUE_TEXT until {{ or terminator or \n or EOF
    self.advance();
    while (self.peek()) |nc| {
        if (nc == '\n') break;
        if (nc == '{') {
            if (self.peek_next() == '{') break;
            if (terminator == .left_brace) break;
        }
        self.advance();
    }

    return self.make_token(.VALUE_TEXT);
}
```

- [ ] **Step 4: Update existing scanner tests to pass `.newline`**

In `src/parser/scanner.zig`, update all existing `next_value()` calls to `next_value(.newline)`:

- Test "next_value plain text": `s.next_value()` → `s.next_value(.newline)` (2 occurrences)
- Test "next_value with interpolation": `s.next_value()` → `s.next_value(.newline)` (3 occurrences)
- Test "next_value empty": `s.next_value()` → `s.next_value(.newline)` (1 occurrence)
- Test "next_value eof": `s.next_value()` → `s.next_value(.newline)` (1 occurrence)
- Test "skip_spaces": `s.next_value()` → `s.next_value(.newline)` (1 occurrence)

- [ ] **Step 5: Run tests to verify everything passes**

Run: `zig build test --summary all 2>&1 | tail -20`
Expected: all scanner tests pass, including the new `.left_brace` test.

- [ ] **Step 6: Write additional scanner tests for `.left_brace` terminator**

Add these tests at the end of `src/parser/scanner.zig`:

```zig
test "next_value left_brace with interpolation" {
    var s = Self.init("my-{{var}}-svc {");
    const t1 = s.next_value(.left_brace);
    try std.testing.expectEqual(.VALUE_TEXT, t1.kind);
    try std.testing.expectEqualStrings("my-", t1.lexeme);
    try std.testing.expectEqual(.DOUBLE_LEFT_BRACE, s.next_value(.left_brace).kind);
    // variable name inside interpolation uses next()
    const id = s.next();
    try std.testing.expectEqual(.IDENTIFIER, id.kind);
    try std.testing.expectEqualStrings("var", id.lexeme);
    try std.testing.expectEqual(.DOUBLE_RIGHT_BRACE, s.next().kind);
    const t2 = s.next_value(.left_brace);
    try std.testing.expectEqual(.VALUE_TEXT, t2.kind);
    try std.testing.expectEqualStrings("-svc ", t2.lexeme);
    try std.testing.expectEqual(.LEFT_BRACE, s.next_value(.left_brace).kind);
}

test "next_value left_brace eof" {
    var s = Self.init("no-brace");
    const tok = s.next_value(.left_brace);
    try std.testing.expectEqual(.VALUE_TEXT, tok.kind);
    try std.testing.expectEqualStrings("no-brace", tok.lexeme);
    try std.testing.expectEqual(.EOF, s.next_value(.left_brace).kind);
}
```

- [ ] **Step 7: Run tests to verify new tests pass**

Run: `zig build test --summary all 2>&1 | tail -20`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add src/parser/scanner.zig
git commit -m "scanner: add Terminator enum and parameterize next_value"
```

---

### Task 2: Parser — Update `resolve_value` and call sites

**Files:**
- Modify: `src/parser/parser.zig:175-193` (parse_let)
- Modify: `src/parser/parser.zig:195-206` (parse_instruction)
- Modify: `src/parser/parser.zig:208-234` (resolve_value)

- [ ] **Step 1: Update `resolve_value` to accept `terminator` parameter**

In `src/parser/parser.zig`, change the `resolve_value` signature and pass `terminator` through to `next_value`. Also add `.LEFT_BRACE` to the break conditions:

```zig
fn resolve_value(self: *Self, scope: *const Scope, terminator: Scanner.Terminator) Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;

    self.scanner.skip_spaces();

    while (true) {
        const tok = self.scanner.next_value(terminator);
        switch (tok.kind) {
            .VALUE_TEXT => try buf.appendSlice(self.arena, tok.lexeme),
            .DOUBLE_LEFT_BRACE => {
                const id = self.scanner.next();
                if (!is_identifier_like(id.kind)) return error.ExpectedIdentifier;
                const close = self.scanner.next();
                if (close.kind != .DOUBLE_RIGHT_BRACE) return error.ExpectedDoubleRightBrace;
                const resolved = self.lookup_variable(scope, id.lexeme) orelse {
                    std.log.err("line {d}: unresolved variable '{s}'", .{ id.line, id.lexeme });
                    return error.UnresolvedVariable;
                };
                try buf.appendSlice(self.arena, resolved);
            },
            .NEWLINE, .EOF, .LEFT_BRACE => break,
            else => return error.UnexpectedToken,
        }
    }

    return try buf.toOwnedSlice(self.arena);
}
```

- [ ] **Step 2: Update `parse_let` to pass `.newline`**

In `src/parser/parser.zig`, change line 189:

```zig
    const value = try self.resolve_value(scope, .newline);
```

- [ ] **Step 3: Update `parse_instruction` to pass `.newline`**

In `src/parser/parser.zig`, change line 197:

```zig
    const value = try self.resolve_value(scope, .newline);
```

- [ ] **Step 4: Run tests to verify nothing broke**

Run: `zig build test --summary all 2>&1 | tail -20`
Expected: all existing parser tests pass unchanged.

- [ ] **Step 5: Commit**

```bash
git add src/parser/parser.zig
git commit -m "parser: add terminator parameter to resolve_value"
```

---

### Task 3: Parser — Rewrite `parse_layer` and clean up

**Files:**
- Modify: `src/parser/parser.zig:74-86` (parse_body LAYER branch)
- Modify: `src/parser/parser.zig:126-173` (parse_layer)
- Remove: `src/parser/parser.zig:248-264` (join_with_spaces)

- [ ] **Step 1: Write failing tests for special-character layer names**

Add these tests at the end of `src/parser/parser.zig`:

```zig
test "parse layer name with hyphen" {
    const result = try parse(std.testing.allocator,
        \\layer my-layer {
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("my-layer", result.items[1].name);
}

test "parse layer name with special chars" {
    const result = try parse(std.testing.allocator,
        \\layer foo/bar.baz {
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("foo/bar.baz", result.items[1].name);
}

test "parse layer name with embedded interpolation" {
    const result = try parse(std.testing.allocator,
        \\let env = prod
        \\layer my-{{env}}-service {
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("my-prod-service", result.items[1].name);
}

test "parse layer name whitespace trimming" {
    const result = try parse(std.testing.allocator,
        \\layer   padded   {
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("padded", result.items[1].name);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test --summary all 2>&1 | tail -20`
Expected: "parse layer name with hyphen" and "parse layer name with special chars" fail (scanner returns ERROR for `-` and `/`).

- [ ] **Step 3: Remove `self.advance()` from LAYER branch in `parse_body`**

In `src/parser/parser.zig`, change the LAYER branch in `parse_body` from:

```zig
            .LAYER => {
                try self.advance();
                const scope = Scope{ .vars = variables.items, .parent = parent_scope };
                const idx = try self.parse_layer(layer_index, &scope);
                try sublayers.append(self.arena, idx);
            },
```

to:

```zig
            .LAYER => {
                const scope = Scope{ .vars = variables.items, .parent = parent_scope };
                const idx = try self.parse_layer(layer_index, &scope);
                try sublayers.append(self.arena, idx);
            },
```

- [ ] **Step 4: Rewrite `parse_layer` to use `resolve_value`**

Replace the entire `parse_layer` function with:

```zig
fn parse_layer(self: *Self, parent_index: usize, parent_scope: *const Scope) Error!usize {
    const raw_name = try self.resolve_value(parent_scope, .left_brace);
    const name = std.mem.trim(u8, raw_name, " \t");

    if (name.len == 0) {
        std.log.err("line {d}: expected layer name", .{self.scanner.line});
        return error.ExpectedIdentifier;
    }

    try self.advance(); // reads LEFT_BRACE
    if (self.current.kind != .LEFT_BRACE) {
        std.log.err("line {d}: expected '{{'", .{self.current.line});
        return error.ExpectedLeftBrace;
    }
    try self.advance(); // consume {

    const new_index = self.layers.items.len;
    try self.layers.append(self.arena, .{
        .name = name,
        .parent = parent_index,
        .sublayers = &.{},
        .variables = &.{},
        .instructions = &.{},
    });

    try self.parse_body(new_index, false, parent_scope);

    return new_index;
}
```

- [ ] **Step 5: Delete `join_with_spaces`**

Remove the entire `join_with_spaces` function from `src/parser/parser.zig` (lines 248-264).

- [ ] **Step 6: Run all tests**

Run: `zig build test --summary all 2>&1 | tail -20`
Expected: all tests pass — both existing and new.

- [ ] **Step 7: Commit**

```bash
git add src/parser/parser.zig
git commit -m "parser: rewrite parse_layer to use resolve_value with left_brace terminator"
```
