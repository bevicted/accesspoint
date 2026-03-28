# Implicit `layer_name` Variable

## Summary

Each layer automatically receives an implicit `layer_name` variable set to the layer's resolved name. The root layer is named `"accesspoint"`. The implicit variable can be shadowed by an explicit `let layer_name = ...` declaration.

## Behavior

```ap
// root level
print {{layer_name}}                // "accesspoint"

layer kubectl {
    print {{layer_name}}            // "kubectl"

    let layer_name = custom
    print {{layer_name}}            // "custom"

    layer pods {
        print {{layer_name}}        // "pods" (child's own implicit)
    }
}

let env = prod
layer my-{{env}}-service {
    print {{layer_name}}            // "my-prod-service" (resolved name)
}
```

Key behaviors:
- Each layer's `layer_name` is its **resolved** name (after interpolation)
- Root layer (index 0) has `layer_name = "accesspoint"`
- Child layers get their own `layer_name`, shadowing the parent's
- Explicit `let layer_name = ...` within a layer shadows the implicit value for subsequent statements

## Implementation

### Change 1: Reverse `lookup_variable` iteration direction

Currently `lookup_variable` iterates forward through a scope's variables, returning the first match. This means the first declaration wins within a scope, which would prevent `let layer_name = ...` from shadowing the prepended implicit variable.

**Fix:** Reverse the iteration to use `std.mem.reverseIterator` (or index backwards), so the **last** declaration in a scope wins. This is also more intuitive for same-scope redeclarations generally.

Cross-scope shadowing (child vs parent) is unaffected since the scope chain always checks the current scope fully before walking to the parent.

### Change 2: Prepend implicit variable in `parse_body`

At the start of `parse_body`, before the parse loop, append `Variable{ .name = "layer_name", .value = <name> }` to the `variables` ArrayList:

- For root (`is_root == true`): value is `"accesspoint"`
- For non-root: value is the layer's already-resolved name (passed as a parameter)

Since this is the first variable in the list and lookup now iterates in reverse, any later `let layer_name = ...` naturally shadows it.

### Change 3: Set root layer name

Set `self.layers.items[0].name` to `"accesspoint"` instead of `""`.

### Interface change to `parse_body`

`parse_body` currently has signature:

```zig
fn parse_body(self: *Self, layer_index: usize, is_root: bool, parent_scope: ?*const Scope) Error!void
```

Add a `layer_name` parameter (type `[]const u8`) so the caller can pass the resolved name. `parse_layer` already has the resolved name available before calling `parse_body`. For root, the caller passes `"accesspoint"`.

### Files changed

- `src/parser/parser.zig` — `lookup_variable`, `parse_body`, `parse` (root setup), `parse_layer` (pass name)

### Files unchanged

- `src/parser/scanner.zig` — no lexer changes
- `src/parser/token.zig` — no new token types
- `src/parser/models.zig` — no struct changes (the implicit variable uses the existing `Variable` type)

## Test cases

1. **Root layer_name**: `print {{layer_name}}` at root resolves to `"accesspoint"`
2. **Basic layer_name**: `layer foo { print {{layer_name}} }` resolves to `"foo"`
3. **Nested layers**: child gets its own `layer_name`, not parent's
4. **Explicit shadowing**: `let layer_name = x` shadows the implicit value
5. **Interpolated layer name**: `layer my-{{var}}-svc { print {{layer_name}} }` resolves to the fully interpolated name
6. **Same-scope redeclaration** (bonus): verify reversed iteration means last `let x = ...` wins
