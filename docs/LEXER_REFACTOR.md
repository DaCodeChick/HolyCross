# Lexer Refactoring Plan

**Date**: 2026-01-09  
**Status**: Planned  
**Goal**: Split monolithic 2091-line lexer.zig into multiple focused modules

## Current State

**File**: `src/lexer/lexer.zig`  
**Size**: 2,091 lines  
**Problems**:
- Single file is too large for easy navigation
- All functionality mixed together
- Harder to maintain and test individual components

## Proposed Structure

```
src/lexer/
├── lexer.zig           # Main public interface (~300 lines)
├── token.zig           # Token types and structures (~200 lines)
├── keywords.zig        # Keyword map and lookup (~150 lines)
├── operators.zig       # Operator scanning functions (~400 lines)
├── literals.zig        # Number, string, char scanning (~500 lines)
├── identifiers.zig     # Identifier and keyword scanning (~200 lines)
├── whitespace.zig      # Whitespace and comment handling (~150 lines)
└── tests.zig           # All lexer tests (~500 lines)
```

## Module Breakdown

### 1. `token.zig` - Token Types and Structures
**Lines**: ~200  
**Contents**:
- `TokenType` enum (120+ types)
- `Token` struct
- Token creation helpers

**Purpose**: Central definition of all token types

### 2. `keywords.zig` - Keyword Management
**Lines**: ~150  
**Contents**:
- `KeywordMap` typedef
- `keywords` static string map (71 keywords)
- `getKeyword()` function

**Purpose**: Keyword lookup and management

### 3. `operators.zig` - Operator Scanning
**Lines**: ~400  
**Contents**:
- `scanOperatorVariants()` - Simple compound operators
- `scanShiftOperator()` - << and >>
- `scanMinusOperator()` - -, --, -=, ->
- `scanSlashOperator()` - /, /=, comments
- `scanDotOperator()` - ., ...
- All single-char operator scanning

**Purpose**: All operator tokenization logic

### 4. `literals.zig` - Literal Scanning
**Lines**: ~500  
**Contents**:
- `scanNumber()` - Integers and floats
- `scanString()` - String literals with escapes
- `scanChar()` - Character literals (including multi-char)
- `scanBinaryNumber()`, `scanHexNumber()`, `scanOctalNumber()`
- `parseEscape()` - Escape sequence handling
- Number parsing helpers

**Purpose**: All literal value tokenization

### 5. `identifiers.zig` - Identifier Scanning
**Lines**: ~200  
**Contents**:
- `scanIdentifier()` - Identifier scanning
- `scanPreprocessorDirective()` - #define, #include, etc.
- `isIdentifierStart()`, `isIdentifierContinue()`
- Character classification helpers

**Purpose**: Identifier and preprocessor tokenization

### 6. `whitespace.zig` - Whitespace & Comments
**Lines**: ~150  
**Contents**:
- `skipWhitespace()` - Whitespace handling
- `skipLineComment()` - // comments
- `skipBlockComment()` - /* */ comments
- `isWhitespace()`, `isNewline()`

**Purpose**: Non-token character handling

### 7. `lexer.zig` - Main Lexer
**Lines**: ~300  
**Contents**:
- `Lexer` struct definition
- `init()` - Constructor
- `nextToken()` - Main tokenization loop
- High-level orchestration
- Re-exports from other modules

**Purpose**: Public API and coordination

### 8. `tests.zig` - All Tests
**Lines**: ~500  
**Contents**:
- All 50+ existing tests
- Organized by category (keywords, operators, literals, etc.)
- Integration tests

**Purpose**: Comprehensive test coverage

## Migration Strategy

### Phase 1: Extract Token Types
1. Create `token.zig` with `TokenType` enum and `Token` struct
2. Update `lexer.zig` to import from `token.zig`
3. Run tests to verify no breakage

### Phase 2: Extract Keywords
1. Create `keywords.zig` with keyword map
2. Move keyword-related code
3. Update imports
4. Run tests

### Phase 3: Extract Operators
1. Create `operators.zig`
2. Move all `scanXxxOperator()` functions
3. Update imports
4. Run tests

### Phase 4: Extract Literals
1. Create `literals.zig`
2. Move `scanNumber()`, `scanString()`, `scanChar()`
3. Update imports
4. Run tests

### Phase 5: Extract Identifiers
1. Create `identifiers.zig`
2. Move `scanIdentifier()` and related functions
3. Update imports
4. Run tests

### Phase 6: Extract Whitespace
1. Create `whitespace.zig`
2. Move whitespace/comment handling
3. Update imports
4. Run tests

### Phase 7: Extract Tests
1. Create `tests.zig`
2. Move all test blocks
3. Ensure all tests still pass
4. Organize tests by category

### Phase 8: Clean Up Main Lexer
1. Simplify `lexer.zig` to just orchestration
2. Add re-exports for public API
3. Update documentation
4. Final test run

## Public API Compatibility

**Goal**: Zero breaking changes to existing code

**Strategy**: 
- Keep all public functions in `lexer.zig`
- Re-export types from submodules
- Maintain same function signatures

**Example**:
```zig
// lexer.zig
pub const Token = @import("token.zig").Token;
pub const TokenType = @import("token.zig").TokenType;
pub const Lexer = struct {
    // ... uses functions from other modules internally
};
```

## Benefits

1. **Maintainability**: Easier to find and modify specific functionality
2. **Testability**: Can test individual modules in isolation
3. **Readability**: Smaller files are easier to understand
4. **Organization**: Clear separation of concerns
5. **Collaboration**: Multiple people can work on different modules
6. **Documentation**: Each module can have focused documentation

## Testing Strategy

**After each phase**:
1. Run `zig build test --summary all`
2. Verify all 50+ tests still pass
3. Check test execution time (should remain ~440μs)
4. Manual review of one complex test case

**Final verification**:
1. All tests passing
2. No performance regression
3. Build successful
4. Examples still work

## Estimated Time

- **Phase 1-2**: 30 minutes (tokens and keywords)
- **Phase 3-4**: 1 hour (operators and literals - largest modules)
- **Phase 5-6**: 30 minutes (identifiers and whitespace)
- **Phase 7-8**: 30 minutes (tests and cleanup)
- **Total**: ~2.5 hours

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking existing code | Test after each phase |
| Import cycle issues | Careful module dependency design |
| Performance regression | Benchmark before/after |
| Lost functionality | Comprehensive test suite |

## Success Criteria

✅ All 50+ tests passing  
✅ No performance regression  
✅ No breaking changes to public API  
✅ Each module < 500 lines  
✅ Clear module boundaries  
✅ Better code organization  

## Notes

- This is a pure refactoring - no new features
- Maintain git history with descriptive commit messages
- Consider doing this in a separate branch if desired
- Can be done incrementally over multiple sessions

---

**Next Steps**: Begin Phase 1 (Extract Token Types)
