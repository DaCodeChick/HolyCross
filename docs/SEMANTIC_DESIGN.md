# Semantic Analyzer Design

## Overview

The semantic analyzer is Phase 3 of the HolyCross compiler. It performs type checking, scope resolution, and validates that the program is semantically correct before code generation.

## Architecture

```
src/semantic/
├── analyzer.zig        - Main semantic analyzer
├── symbol_table.zig    - Symbol table for scope management
├── type_checker.zig    - Type checking and inference
├── scope.zig           - Scope management
└── tests.zig           - Comprehensive tests
```

## Key Components

### 1. Symbol Table (`symbol_table.zig`)

**Purpose**: Track all declared symbols (variables, functions, types) with their scopes.

**Data Structures**:
```zig
pub const Symbol = union(enum) {
    variable: struct {
        name: []const u8,
        type: ast.Type,
        is_global: bool,
        loc: SourceLocation,
    },
    function: struct {
        name: []const u8,
        return_type: ast.Type,
        params: []ast.Param,
        loc: SourceLocation,
    },
    type_def: struct {
        name: []const u8,
        underlying_type: ast.Type,
        loc: SourceLocation,
    },
};

pub const SymbolTable = struct {
    scopes: std.ArrayList(Scope),
    allocator: Allocator,
    
    fn enterScope() void;
    fn exitScope() void;
    fn define(name: []const u8, symbol: Symbol) !void;
    fn lookup(name: []const u8) ?Symbol;
    fn lookupInCurrentScope(name: []const u8) ?Symbol;
};
```

### 2. Scope Management (`scope.zig`)

**Purpose**: Manage lexical scopes (global, function, block).

**Scope Types**:
- **Global scope**: Functions, global variables, type definitions
- **Function scope**: Function parameters and local variables
- **Block scope**: Variables declared in `{ }` blocks

**Features**:
- Nested scope support
- Shadow detection (optional warning)
- Scope-aware symbol lookup (searches parent scopes)

### 3. Type Checker (`type_checker.zig`)

**Purpose**: Verify type correctness and perform type inference.

**Responsibilities**:
1. **Expression Type Inference**:
   - Literals have obvious types (`42` → `I64`, `3.14` → `F64`)
   - Binary operations return appropriate types
   - Function calls return function's return type

2. **Type Compatibility**:
   - Assignment type checking
   - Function argument type checking
   - Implicit conversions (HolyC is weakly typed)

3. **Operator Type Checking**:
   - Arithmetic operators require numeric types
   - Comparison operators work on compatible types
   - Pointer arithmetic rules

**HolyC Type Rules**:
- **Weak typing**: Implicit conversions between compatible types
- **Pointer arithmetic**: `ptr + int` → `ptr`
- **Integer promotion**: Smaller integers promoted to larger
- **No implicit pointer conversions** (except `U0*` - void pointer)

### 4. Analyzer (`analyzer.zig`)

**Purpose**: Main entry point, orchestrates semantic analysis.

**Process**:
```
1. Initialize symbol table
2. First pass: Collect all declarations (functions, globals, types)
3. Second pass: Analyze function bodies
   a. Check variable declarations
   b. Type check expressions
   c. Validate control flow
   d. Check function calls
4. Report errors
```

## Semantic Checks

### Variable Checks
- ✅ Variable declared before use
- ✅ No duplicate declarations in same scope
- ✅ Type compatibility in assignments
- ✅ Array bounds (if known at compile time)

### Function Checks
- ✅ Function declared/defined before call
- ✅ Correct number of arguments
- ✅ Argument type compatibility
- ✅ Return type matches function signature
- ✅ All code paths return (for non-U0 functions)

### Type Checks
- ✅ Expression types are compatible with operations
- ✅ Cast types are valid
- ✅ Pointer dereference on pointer types
- ✅ Array subscript on array/pointer types
- ✅ Member access on class/union types

### Control Flow Checks
- ✅ `break` only inside loops/switch
- ✅ `goto` target label exists
- ✅ No unreachable code (warning)

## Error Reporting

**Error Structure**:
```zig
pub const SemanticError = struct {
    message: []const u8,
    loc: SourceLocation,
    kind: ErrorKind,
};

pub const ErrorKind = enum {
    undeclared_identifier,
    redeclared_identifier,
    type_mismatch,
    invalid_operation,
    invalid_cast,
    argument_count_mismatch,
    argument_type_mismatch,
    invalid_break,
    invalid_return,
    undefined_label,
};
```

**Error Messages**:
```
[line 10:5] Error: Undeclared variable 'x'
[line 15:10] Error: Type mismatch: cannot assign 'F64' to 'I64*'
[line 20:3] Error: Function 'Add' expects 2 arguments, got 3
```

## Implementation Phases

### Phase 3.1: Basic Symbol Table (Week 1)
- ✅ Symbol table data structure
- ✅ Scope management
- ✅ Variable and function symbol tracking
- ✅ Basic lookup functionality

### Phase 3.2: Type Checking (Week 2)
- ✅ Expression type inference
- ✅ Binary/unary operator type checking
- ✅ Type compatibility checking
- ✅ Basic implicit conversions

### Phase 3.3: Function Analysis (Week 3)
- ✅ Function signature validation
- ✅ Argument type checking
- ✅ Return statement validation
- ✅ Call site validation

### Phase 3.4: Advanced Features (Week 4)
- ✅ Class/union member validation
- ✅ Pointer arithmetic rules
- ✅ Array bounds checking
- ✅ Control flow validation

## Testing Strategy

**Test Coverage**:
1. **Symbol Table Tests**: Define, lookup, scope shadowing
2. **Type Checking Tests**: All operators, implicit conversions
3. **Function Tests**: Calls, arguments, returns
4. **Error Tests**: All error kinds with correct messages
5. **Integration Tests**: Full programs with semantic errors

**Example Test**:
```zig
test "Undeclared variable error" {
    const source = 
        \\U0 Main() {
        \\    I64 x = y + 1; // y undeclared
        \\}
    ;
    
    const errors = try analyzeSource(source);
    try testing.expectEqual(@as(usize, 1), errors.len);
    try testing.expectEqual(ErrorKind.undeclared_identifier, errors[0].kind);
    try testing.expectEqualStrings("y", errors[0].message);
}
```

## HolyC-Specific Considerations

### Weak Typing
HolyC allows implicit conversions:
- Integer ↔ Integer (any size)
- Integer → Float
- Pointer ↔ Integer (for pointer arithmetic)

### Representation Types
Classes can have representation types:
```holyc
I64 class CDate { U32 time; };  // CDate can cast to/from I64
```

### Multi-Character Constants
```holyc
I64 x = 'ABCD';  // Valid: packed into integer
```

### Implicit Print
String expressions call Print implicitly:
```holyc
"Hello!\n";  // Semantic: call Print("Hello!\n");
```

## Success Criteria

Phase 3 is complete when:
1. ✅ All variable declarations are tracked
2. ✅ All identifiers resolve to symbols
3. ✅ All expressions have inferred types
4. ✅ All type mismatches are detected
5. ✅ All function calls are validated
6. ✅ Comprehensive test coverage (>80%)
7. ✅ Clear, helpful error messages

## Next Phase

After semantic analysis, we move to **Phase 4: Intermediate Representation (IR)** where we generate a lower-level representation suitable for code generation.
