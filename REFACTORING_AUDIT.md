# Semantic Analyzer Refactoring Audit

**Date**: 2026-01-10  
**Status**: Phase 3 Complete - Refactoring Opportunities Identified  
**Current Stats**: ~3,200 lines, 196 tests passing, 0 memory leaks

---

## Executive Summary

The semantic analyzer is **functionally complete and production-ready**. However, there are several opportunities to reduce code duplication, improve maintainability, and simplify complex functions through targeted refactoring.

**Key Findings**:
- ✅ No architectural issues
- ✅ Clean separation of concerns
- ⚠️ **12 instances** of duplicated error propagation pattern (type checker → analyzer)
- ⚠️ **2 nearly identical functions** for class/union declaration collection
- ⚠️ Several long functions (70+ lines) that could be decomposed
- ⚠️ **23 instances** of similar error message allocation pattern

---

## Refactoring Opportunities (Priority Order)

### 🔥 HIGH PRIORITY - High Impact, Low Risk

#### 1. Extract Type Checker Error Propagation Helper (Impact: -100 lines)

**Problem**: Pattern repeated **12 times** across the codebase:
```zig
_ = self.type_checker.inferExprType(expr) catch |err| {
    if (self.type_checker.errors.items.len > 0) {
        const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
        const msg = try self.allocator.dupe(u8, type_err.message);
        try self.errors.append(self.allocator, .{
            .kind = .type_mismatch,
            .message = msg,
            .loc = type_err.loc,
        });
    }
    return err;
};
```

**Locations**:
- `collectGlobalVariableDeclaration` (line ~237)
- `validateExpression` (line ~378)
- `validateFunctionCall` (line ~494)
- `analyzeVariableDeclaration` (line ~620)
- `analyzeIfStatement` (line ~730)
- `analyzeWhileStatement` (line ~742)
- `analyzeDoWhileStatement` (line ~754)
- `analyzeForStatement` (lines 782, 798, 823)
- `analyzeSwitchStatement` (line ~823)
- `analyzeReturnStatement` (line ~908)

**Solution**: Extract helper method:
```zig
/// Infer expression type and propagate type checker errors to analyzer
fn inferExprTypeOrPropagate(self: *Analyzer, expr: ast.Expr) !ast.Type {
    return self.type_checker.inferExprType(expr) catch |err| {
        if (self.type_checker.errors.items.len > 0) {
            const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
            const msg = try self.allocator.dupe(u8, type_err.message);
            try self.errors.append(self.allocator, .{
                .kind = .type_mismatch,
                .message = msg,
                .loc = type_err.loc,
            });
        }
        return err;
    };
}
```

**Impact**:
- Reduces ~100 lines of duplicated code
- Single point of maintenance for error propagation logic
- Easier to modify error handling strategy in future

**Risk**: Low (mechanical refactoring, no logic changes)

---

#### 2. Merge `collectClassDeclaration` and `collectUnionDeclaration` (Impact: -35 lines)

**Problem**: Two functions with 95% identical logic (37 lines each):
- `collectClassDeclaration` (line 133)
- `collectUnionDeclaration` (line 172)

**Differences**: Only error messages say "class" vs "union"

**Solution**: Create unified helper:
```zig
/// Collect a composite type declaration (class or union)
fn collectCompositeTypeDeclaration(
    self: *Analyzer,
    name: []const u8,
    members: []ast.ClassMember,
    repr_type: ?ast.Type,
    loc: ast.SourceLocation,
    type_kind: enum { class, union_type },
) AnalyzerError!void {
    const kind_str = if (type_kind == .class) "class" else "union";
    
    // Check for duplicate declaration
    if (self.symbol_table.lookupLocal(name)) |existing| {
        const msg = try std.fmt.allocPrint(
            self.allocator,
            "Redeclaration of {s} '{s}' (previously declared at line {d})",
            .{ kind_str, name, existing.getLocation().line },
        );
        try self.addError(.redeclared_identifier, msg, loc);
        return;
    }

    // Check for duplicate member names
    var seen_members = std.StringHashMap(void).init(self.allocator);
    defer seen_members.deinit();

    for (members) |member| {
        if (seen_members.contains(member.name)) {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Duplicate member '{s}' in {s} '{s}'",
                .{ member.name, kind_str, name },
            );
            try self.addError(.redeclared_identifier, msg, member.loc);
        } else {
            try seen_members.put(member.name, {});
        }
    }

    // Store member information
    const members_map = if (type_kind == .class) &self.class_members else &self.union_members;
    try members_map.put(name, members);

    // Define as type
    const underlying_type = if (repr_type) |rt| rt else ast.Type{ .named = name };
    try self.symbol_table.defineType(name, underlying_type, loc);
}

// Thin wrappers:
fn collectClassDeclaration(self: *Analyzer, cls: anytype) AnalyzerError!void {
    try self.collectCompositeTypeDeclaration(cls.name, cls.members, cls.repr_type, cls.loc, .class);
}

fn collectUnionDeclaration(self: *Analyzer, uni: anytype) AnalyzerError!void {
    try self.collectCompositeTypeDeclaration(uni.name, uni.members, uni.repr_type, uni.loc, .union_type);
}
```

**Impact**:
- Reduces ~35 lines of duplication
- Single point of maintenance for composite type logic
- Easier to add future composite type variants

**Risk**: Low (pure refactoring, well-tested)

---

### 📋 MEDIUM PRIORITY - Moderate Impact, Low Risk

#### 3. Extract Member Validation Helper (Impact: -40 lines)

**Problem**: Duplicate member checking in both class and union collection

**Current Pattern** (repeated 2x):
```zig
var seen_members = std.StringHashMap(void).init(self.allocator);
defer seen_members.deinit();

for (members) |member| {
    if (seen_members.contains(member.name)) {
        const msg = try std.fmt.allocPrint(
            self.allocator,
            "Duplicate member '{s}' in {type} '{s}'",
            .{ member.name, type_name },
        );
        try self.addError(.redeclared_identifier, msg, member.loc);
    } else {
        try seen_members.put(member.name, {});
    }
}
```

**Solution**: Extract to helper:
```zig
/// Check for duplicate members in a composite type
fn checkDuplicateMembers(
    self: *Analyzer,
    members: []ast.ClassMember,
    type_name: []const u8,
    type_kind: []const u8, // "class" or "union"
) AnalyzerError!void {
    var seen = std.StringHashMap(void).init(self.allocator);
    defer seen.deinit();

    for (members) |member| {
        if (seen.contains(member.name)) {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Duplicate member '{s}' in {s} '{s}'",
                .{ member.name, type_kind, type_name },
            );
            try self.addError(.redeclared_identifier, msg, member.loc);
        } else {
            try seen.put(member.name, {});
        }
    }
}
```

**Impact**: Reduces ~20 lines, improves readability  
**Risk**: Low

**NOTE**: This becomes **obsolete** if we implement Refactoring #2 (merge class/union), but is useful independently.

---

#### 4. Simplify `validateMemberAccess` (Impact: -10 lines, complexity reduction)

**Problem**: 72-line function with nested logic

**Current Structure**:
1. Infer object type (lines 528-531)
2. Handle arrow dereference (lines 534-549)
3. Extract type name (lines 552-559)
4. Look up members (lines 562-572)
5. Check if member exists (lines 574-591)

**Solution**: Extract arrow handling:
```zig
/// Resolve type through pointer dereference if arrow operator used
fn resolveAccessType(
    self: *Analyzer,
    object_type: ast.Type,
    is_arrow: bool,
    loc: ast.SourceLocation,
) !ast.Type {
    if (!is_arrow) return object_type;

    return switch (object_type) {
        .pointer => |ptr_type| ptr_type.*,
        else => {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Arrow operator requires pointer type, got '{s}'",
                .{@tagName(object_type)},
            );
            try self.addError(.type_mismatch, msg, loc);
            return error.SemanticError;
        },
    };
}
```

**Impact**: Makes `validateMemberAccess` more readable (60 lines → 50 lines)  
**Risk**: Very low

---

#### 5. Extract Member Lookup Helper (Impact: -15 lines)

**Problem**: Member lookup logic duplicated in `validateMemberAccess`

**Solution**:
```zig
/// Find a member by name in a type's member list
fn findMember(members: []ast.ClassMember, name: []const u8) ?ast.ClassMember {
    for (members) |member| {
        if (std.mem.eql(u8, member.name, name)) {
            return member;
        }
    }
    return null;
}
```

Usage in `validateMemberAccess`:
```zig
if (self.findMember(members, member_name) == null) {
    const msg = try std.fmt.allocPrint(
        self.allocator,
        "Type '{s}' has no member named '{s}'",
        .{ type_name, member_name },
    );
    try self.addError(.undeclared_identifier, msg, loc);
}
```

**Impact**: Cleaner code, reusable helper  
**Risk**: Very low

---

#### 6. Extract Function Symbol Lookup (Impact: -20 lines)

**Problem**: `validateFunctionCall` does complex symbol lookup and validation

**Solution**: Extract to helper:
```zig
/// Look up a function symbol by name, reporting errors if not found or not callable
fn lookupFunctionSymbol(
    self: *Analyzer,
    func_name: []const u8,
    loc: ast.SourceLocation,
) !symbol_table.FunctionSymbol {
    const symbol = self.symbol_table.lookupSymbol(func_name) orelse {
        const msg = try std.fmt.allocPrint(
            self.allocator,
            "Undeclared function '{s}'",
            .{func_name},
        );
        try self.addError(.undeclared_identifier, msg, loc);
        return error.SemanticError;
    };

    return switch (symbol) {
        .function => |f| f,
        else => {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "'{s}' is not a function",
                .{func_name},
            );
            try self.addError(.not_callable, msg, loc);
            return error.SemanticError;
        },
    };
}
```

**Impact**: Makes `validateFunctionCall` more focused (68 lines → ~50 lines)  
**Risk**: Low

---

### 🎯 LOW PRIORITY - Nice to Have

#### 7. Extract Redeclaration Check Helper (Impact: -30 lines)

**Problem**: Redeclaration checking pattern repeated in:
- `collectFunctionDeclaration`
- `collectClassDeclaration`
- `collectUnionDeclaration`
- `collectGlobalVariableDeclaration`

**Solution**:
```zig
/// Check if a name is already declared in local scope, reporting error if found
fn checkNotRedeclared(
    self: *Analyzer,
    name: []const u8,
    kind: []const u8, // "function", "class", "union", "global variable"
    loc: ast.SourceLocation,
) !void {
    if (self.symbol_table.lookupLocal(name)) |existing| {
        const msg = try std.fmt.allocPrint(
            self.allocator,
            "Redeclaration of {s} '{s}' (previously declared at line {d})",
            .{ kind, name, existing.getLocation().line },
        );
        try self.addError(.redeclared_identifier, msg, loc);
        return error.SemanticError;
    }
}
```

**Impact**: Reduces ~30 lines  
**Risk**: Low

**NOTE**: Becomes **partially obsolete** if we implement Refactoring #2 (which already handles class/union).

---

#### 8. Extract Argument Validation Loop (Impact: -20 lines)

**Problem**: Complex argument type checking in `validateFunctionCall` (lines 493-516)

**Solution**:
```zig
/// Validate function call arguments match parameter types
fn validateCallArguments(
    self: *Analyzer,
    func_name: []const u8,
    args: []const ast.Expr,
    params: []ast.Param,
    loc: ast.SourceLocation,
) !void {
    for (args, params, 0..) |arg, param, i| {
        const arg_type = try self.inferExprTypeOrPropagate(arg);
        
        const compatible = try self.type_checker.areTypesCompatible(arg_type, param.type);
        if (!compatible) {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Argument {d} to function '{s}': expected type '{s}', got '{s}'",
                .{ i + 1, func_name, @tagName(param.type), @tagName(arg_type) },
            );
            try self.addError(.argument_type_mismatch, msg, loc);
        }
    }
}
```

**Impact**: Simplifies `validateFunctionCall` further  
**Risk**: Low

**NOTE**: Depends on Refactoring #1 (`inferExprTypeOrPropagate`)

---

## Refactoring Phases

### Phase 1: Foundation (Refactorings #1, #2) - 1-2 hours
**Goal**: Eliminate the two largest sources of duplication

1. Extract `inferExprTypeOrPropagate` helper
2. Replace all 12 instances with helper call
3. Merge `collectClassDeclaration` and `collectUnionDeclaration`
4. Run full test suite (expect 196/196 passing)

**Expected Impact**: -135 lines, significantly improved maintainability

---

### Phase 2: Simplification (Refactorings #4, #5, #6) - 1-2 hours
**Goal**: Break down complex functions

1. Extract `resolveAccessType` from `validateMemberAccess`
2. Extract `findMember` helper
3. Extract `lookupFunctionSymbol` from `validateFunctionCall`
4. Run full test suite

**Expected Impact**: -45 lines, improved readability

---

### Phase 3: Polish (Refactorings #7, #8) - Optional
**Goal**: Final cleanup if desired

1. Extract `checkNotRedeclared` helper
2. Extract `validateCallArguments` from `validateFunctionCall`
3. Run full test suite

**Expected Impact**: -50 lines, consistent patterns throughout

---

## Summary Statistics

### Before Refactoring
- **Total Lines**: ~1,016 lines (analyzer.zig)
- **Functions**: 27
- **Longest Function**: 72 lines (`validateMemberAccess`)
- **Code Duplication**: ~200 lines duplicated

### After All Refactorings (Estimated)
- **Total Lines**: ~785 lines (-231 lines, -23%)
- **Functions**: ~35 (+8 helpers)
- **Longest Function**: ~50 lines
- **Code Duplication**: <50 lines

---

## Risk Assessment

| Refactoring | Risk Level | Reason |
|-------------|-----------|---------|
| #1 - Error Propagation | Low | Mechanical, pure extraction |
| #2 - Merge Class/Union | Low | Nearly identical logic |
| #3 - Member Validation | Low | Simple extraction |
| #4 - Simplify Member Access | Very Low | Single-purpose extraction |
| #5 - Member Lookup | Very Low | Pure helper function |
| #6 - Function Lookup | Low | Clear extraction boundary |
| #7 - Redeclaration Check | Low | Repeated pattern |
| #8 - Argument Validation | Low | Well-defined scope |

**Overall Risk**: LOW - All refactorings are mechanical with comprehensive test coverage

---

## Testing Strategy

For **each** refactoring step:

1. Make the change
2. Run `zig build test --summary all`
3. Verify: **196/196 tests passing, 0 memory leaks**
4. Commit with descriptive message

**If any test fails**: Immediately revert and investigate.

---

## Recommended Action

**Priority Order**:
1. ✅ **Do Phase 1** - High-impact, low-risk, saves 135 lines
2. ⚠️ **Consider Phase 2** - Improves readability, saves 45 lines
3. 🤔 **Optional Phase 3** - Nice polish, saves 50 lines

**Total Potential Savings**: 230 lines (23% reduction) with improved maintainability

---

## Questions for Consideration

1. **Should we proceed with refactoring now**, or wait until Phase 4 (Code Generation)?
   - Pro: Cleaner codebase before adding more complexity
   - Con: "If it ain't broke, don't fix it"

2. **Which phase(s) should we tackle?**
   - Phase 1 is **highly recommended** (biggest wins)
   - Phase 2 is **nice to have**
   - Phase 3 is **optional polish**

3. **Should we create a new branch** for refactoring?
   - Pro: Safe experimentation
   - Con: Extra overhead for simple mechanical changes

---

## Files Affected

- `src/semantic/analyzer.zig` - Main refactoring target
- `src/semantic/analyzer_test.zig` - Verify tests still pass (no changes needed)

---

## Conclusion

The semantic analyzer is **well-structured and production-ready**. The identified refactorings are **optional improvements** that would reduce code duplication and improve maintainability, but are **not necessary** for functionality.

**Recommendation**: Proceed with **Phase 1** refactorings (#1 and #2) as they provide the highest impact with minimal risk.
