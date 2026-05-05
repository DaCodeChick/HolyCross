const std = @import("std");

/// Abstract Syntax Tree (AST) node types for HolyC
/// Represents the parsed structure of a HolyC program
/// Source location for AST nodes (for error reporting)
pub const SourceLocation = struct {
    line: usize,
    column: usize,
};

/// Base type information
pub const Type = union(enum) {
    // Primitive types
    i0,
    i8,
    i16,
    i32,
    i64,
    u0,
    u8,
    u16,
    u32,
    u64,
    f64,
    bool, // Boolean type (internally I64)

    // Complex types
    pointer: *Type, // T*
    array: struct { element_type: *Type, size: ?u64 }, // T[n] or T[]
    named: []const u8, // class/union name
    function: struct {
        return_type: *Type,
        params: []Type,
    },

    pub fn format(self: Type, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .i0 => try writer.writeAll("I0"),
            .i8 => try writer.writeAll("I8"),
            .i16 => try writer.writeAll("I16"),
            .i32 => try writer.writeAll("I32"),
            .i64 => try writer.writeAll("I64"),
            .u0 => try writer.writeAll("U0"),
            .u8 => try writer.writeAll("U8"),
            .u16 => try writer.writeAll("U16"),
            .u32 => try writer.writeAll("U32"),
            .u64 => try writer.writeAll("U64"),
            .f64 => try writer.writeAll("F64"),
            .bool => try writer.writeAll("Bool"),
            .pointer => |ptr| try writer.print("*{}", .{ptr}),
            .array => |arr| {
                if (arr.size) |size| {
                    try writer.print("[{}]{}", .{ size, arr.element_type });
                } else {
                    try writer.print("[]{}", .{arr.element_type});
                }
            },
            .named => |name| try writer.writeAll(name),
            .function => try writer.writeAll("<function>"),
        }
    }
};

/// Expression nodes
pub const Expr = union(enum) {
    // Literals
    integer: struct { value: i64, loc: SourceLocation },
    float: struct { value: f64, loc: SourceLocation },
    string: struct { value: []const u8, loc: SourceLocation },
    char: struct { value: u32, loc: SourceLocation }, // u32 for multi-char constants

    // Identifiers
    identifier: struct { name: []const u8, loc: SourceLocation },

    // Binary operators
    binary: struct {
        op: BinaryOp,
        left: *Expr,
        right: *Expr,
        loc: SourceLocation,
    },

    // Unary operators
    unary: struct {
        op: UnaryOp,
        operand: *Expr,
        loc: SourceLocation,
    },

    // Function call
    call: struct {
        callee: *Expr,
        args: []Expr,
        loc: SourceLocation,
    },

    // Array subscript: arr[index]
    subscript: struct {
        array: *Expr,
        index: *Expr,
        loc: SourceLocation,
    },

    // Member access: obj.member
    member: struct {
        object: *Expr,
        member: []const u8,
        loc: SourceLocation,
    },

    // Pointer member access: ptr->member
    arrow: struct {
        object: *Expr,
        member: []const u8,
        loc: SourceLocation,
    },

    // Type cast: (Type)expr
    cast: struct {
        type: Type,
        expr: *Expr,
        loc: SourceLocation,
    },

    // sizeof(expr) or sizeof(Type)
    sizeof_expr: struct { expr: *Expr, loc: SourceLocation },
    sizeof_type: struct { type: Type, loc: SourceLocation },

    // offset(Type, member)
    offset: struct {
        type: Type,
        member: []const u8,
        loc: SourceLocation,
    },

    pub fn getLocation(self: Expr) SourceLocation {
        return switch (self) {
            .integer => |n| n.loc,
            .float => |f| f.loc,
            .string => |s| s.loc,
            .char => |c| c.loc,
            .identifier => |id| id.loc,
            .binary => |b| b.loc,
            .unary => |u| u.loc,
            .call => |c| c.loc,
            .subscript => |s| s.loc,
            .member => |m| m.loc,
            .arrow => |a| a.loc,
            .cast => |c| c.loc,
            .sizeof_expr => |s| s.loc,
            .sizeof_type => |s| s.loc,
            .offset => |o| o.loc,
        };
    }
};

/// Binary operators with precedence info
pub const BinaryOp = enum {
    // Arithmetic
    add, // +
    subtract, // -
    multiply, // *
    divide, // /
    modulo, // %

    // Bitwise
    bitwise_and, // &
    bitwise_or, // |
    bitwise_xor, // ^
    shift_left, // <<
    shift_right, // >>

    // Logical
    logical_and, // &&
    logical_or, // ||
    logical_xor, // ^^ (HolyC-specific)

    // Comparison
    equal, // ==
    not_equal, // !=
    less, // <
    less_equal, // <=
    greater, // >
    greater_equal, // >=

    // Assignment
    assign, // =
    add_assign, // +=
    sub_assign, // -=
    mul_assign, // *=
    div_assign, // /=
    mod_assign, // %=
    and_assign, // &=
    or_assign, // |=
    xor_assign, // ^=
    shl_assign, // <<=
    shr_assign, // >>=

    // Power (HolyC-specific)
    power, // ` (backtick)

    pub fn precedence(self: BinaryOp) u8 {
        return switch (self) {
            // Highest precedence (15)
            .power => 15,

            // Multiplicative (13)
            .multiply, .divide, .modulo => 13,

            // Additive (12)
            .add, .subtract => 12,

            // Shift (11)
            .shift_left, .shift_right => 11,

            // Relational (10, 9)
            .less, .less_equal, .greater, .greater_equal => 10,
            .equal, .not_equal => 9,

            // Bitwise (8, 7, 6)
            .bitwise_and => 8,
            .bitwise_xor => 7,
            .bitwise_or => 6,

            // Logical (5, 4, 3)
            .logical_and => 5,
            .logical_xor => 4,
            .logical_or => 3,

            // Assignment (lowest precedence: 2)
            .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .mod_assign, .and_assign, .or_assign, .xor_assign, .shl_assign, .shr_assign => 2,
        };
    }

    pub fn isRightAssociative(self: BinaryOp) bool {
        return switch (self) {
            .power, .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .mod_assign, .and_assign, .or_assign, .xor_assign, .shl_assign, .shr_assign => true,
            else => false,
        };
    }
};

/// Unary operators
pub const UnaryOp = enum {
    // Arithmetic
    negate, // -
    plus, // + (unary)

    // Logical
    logical_not, // !

    // Bitwise
    bitwise_not, // ~

    // Pointer/Address
    dereference, // *
    address_of, // &

    // Increment/Decrement
    pre_increment, // ++x
    pre_decrement, // --x
    post_increment, // x++
    post_decrement, // x--
};

/// Statement nodes
pub const Stmt = union(enum) {
    // Empty statement
    empty: struct { loc: SourceLocation },

    // Expression statement
    expr: struct { expr: Expr, loc: SourceLocation },

    // Variable declaration: I64 x = 42;
    var_decl: struct {
        type: Type,
        name: []const u8,
        init: ?Expr,
        loc: SourceLocation,
    },

    // Block: { stmt1; stmt2; ... }
    block: struct {
        stmts: []Stmt,
        loc: SourceLocation,
    },

    // If statement
    if_stmt: struct {
        condition: Expr,
        then_stmt: *Stmt,
        else_stmt: ?*Stmt,
        loc: SourceLocation,
    },

    // While loop
    while_stmt: struct {
        condition: Expr,
        body: *Stmt,
        loc: SourceLocation,
    },

    // Do-while loop
    do_while: struct {
        body: *Stmt,
        condition: Expr,
        loc: SourceLocation,
    },

    // For loop: for (init; cond; incr) body
    for_stmt: struct {
        init: ?*Stmt, // Can be declaration or expression
        condition: ?Expr,
        increment: ?Expr,
        body: *Stmt,
        loc: SourceLocation,
    },

    // Switch statement
    switch_stmt: struct {
        expr: Expr,
        cases: []SwitchCase,
        loc: SourceLocation,
    },

    // Return statement
    return_stmt: struct {
        expr: ?Expr,
        loc: SourceLocation,
    },

    // Break statement
    break_stmt: struct { loc: SourceLocation },

    // Goto statement
    goto_stmt: struct {
        label: []const u8,
        loc: SourceLocation,
    },

    // Label: label_name:
    label: struct {
        name: []const u8,
        loc: SourceLocation,
    },

    // Try-catch block
    try_catch: struct {
        try_block: *Stmt,
        catch_block: *Stmt,
        loc: SourceLocation,
    },

    // Inline assembly: asm { ... }
    asm_block: struct {
        code: []const u8,
        loc: SourceLocation,
    },

    pub fn getLocation(self: Stmt) SourceLocation {
        return switch (self) {
            .empty => |e| e.loc,
            .expr => |e| e.loc,
            .var_decl => |v| v.loc,
            .block => |b| b.loc,
            .if_stmt => |i| i.loc,
            .while_stmt => |w| w.loc,
            .do_while => |d| d.loc,
            .for_stmt => |f| f.loc,
            .switch_stmt => |s| s.loc,
            .return_stmt => |r| r.loc,
            .break_stmt => |b| b.loc,
            .goto_stmt => |g| g.loc,
            .label => |l| l.loc,
            .try_catch => |t| t.loc,
            .asm_block => |a| a.loc,
        };
    }
};

/// Switch case
pub const SwitchCase = struct {
    // null for default case
    value: ?Expr,
    stmts: []Stmt,
    loc: SourceLocation,
};

/// Top-level declaration nodes
pub const Decl = union(enum) {
    // Function declaration/definition
    function: struct {
        return_type: Type,
        name: []const u8,
        params: []Param,
        body: ?Stmt, // null for forward declaration
        attributes: FunctionAttributes,
        loc: SourceLocation,
    },

    // Class definition
    // HolyC syntax: [visibility] [repr_type] [alias] class Name [: Base] { members };
    // Examples:
    //   class MyClass { ... };
    //   public I64 class CDate { ... };  (I64 is representation type, not inheritance)
    //   U16i union U16 { ... };  (alias syntax)
    //   class Derived : Base { ... };  (inheritance uses colon)
    class: struct {
        name: []const u8,
        alias: ?[]const u8, // For "U16i union U16" typedef-like syntax
        repr_type: ?Type, // For "I64 class CDate" (representation type, allows casting)
        base_class: ?[]const u8, // For "class Derived : Base" (true inheritance)
        is_public: bool,
        is_static: bool,
        is_extern: bool,
        members: []ClassMember,
        loc: SourceLocation,
    },

    // Union definition
    // HolyC syntax: [visibility] [repr_type] [alias] union Name { members };
    // Example: I64 union TimeUnion { ... } (can be represented as I64)
    union_decl: struct {
        name: []const u8,
        alias: ?[]const u8, // For "U16i union U16" syntax
        repr_type: ?Type, // Representation type (e.g., I64)
        is_public: bool,
        is_static: bool,
        is_extern: bool,
        members: []ClassMember,
        loc: SourceLocation,
    },

    // Global variable declaration
    global_var: struct {
        type: Type,
        name: []const u8,
        init: ?Expr,
        loc: SourceLocation,
    },

    // Import/Extern declarations
    import: struct {
        path: []const u8,
        loc: SourceLocation,
    },

    // Preprocessor directives (kept for semantic analysis)
    preprocessor: struct {
        directive: []const u8,
        loc: SourceLocation,
    },
};

/// Function parameter
pub const Param = struct {
    type: Type,
    name: []const u8,
    loc: SourceLocation,
};

/// Function attributes
pub const FunctionAttributes = struct {
    is_extern: bool = false,
    is_public: bool = false,
    is_static: bool = false,
    is_interrupt: bool = false,
    has_err_code: bool = false,
    is_argpop: bool = false,
    is_noargpop: bool = false,
    is_lock: bool = false,
};

/// Class/Union member
pub const ClassMember = struct {
    type: Type,
    name: []const u8,
    loc: SourceLocation,
};

/// Complete program (translation unit)
pub const Program = struct {
    decls: []Decl,
    top_level_stmts: []Stmt, // Statements to execute at program load time
    allocator: std.mem.Allocator, // Backing allocator (used by arena)
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Program) void {
        // Arena deinit frees all AST allocations at once
        self.arena.deinit();
    }
};

// Helper functions for creating AST nodes

pub fn createIntegerExpr(allocator: std.mem.Allocator, value: i64, loc: SourceLocation) !*Expr {
    const expr = try allocator.create(Expr);
    expr.* = .{ .integer = .{ .value = value, .loc = loc } };
    return expr;
}

pub fn createBinaryExpr(allocator: std.mem.Allocator, op: BinaryOp, left: *Expr, right: *Expr, loc: SourceLocation) !*Expr {
    const expr = try allocator.create(Expr);
    expr.* = .{ .binary = .{ .op = op, .left = left, .right = right, .loc = loc } };
    return expr;
}

pub fn createUnaryExpr(allocator: std.mem.Allocator, op: UnaryOp, operand: *Expr, loc: SourceLocation) !*Expr {
    const expr = try allocator.create(Expr);
    expr.* = .{ .unary = .{ .op = op, .operand = operand, .loc = loc } };
    return expr;
}

// Tests
test "AST node creation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const loc = SourceLocation{ .line = 1, .column = 1 };

    // Create: 1 + 2
    const left = try createIntegerExpr(allocator, 1, loc);
    const right = try createIntegerExpr(allocator, 2, loc);
    const binary = try createBinaryExpr(allocator, .add, left, right, loc);

    try testing.expectEqual(BinaryOp.add, binary.binary.op);
    try testing.expectEqual(@as(i64, 1), binary.binary.left.integer.value);
    try testing.expectEqual(@as(i64, 2), binary.binary.right.integer.value);
}

test "Binary operator precedence" {
    const testing = std.testing;

    // Test precedence ordering
    try testing.expect(BinaryOp.power.precedence() > BinaryOp.multiply.precedence());
    try testing.expect(BinaryOp.multiply.precedence() > BinaryOp.add.precedence());
    try testing.expect(BinaryOp.add.precedence() > BinaryOp.shift_left.precedence());
    try testing.expect(BinaryOp.shift_left.precedence() > BinaryOp.less.precedence());
    try testing.expect(BinaryOp.less.precedence() > BinaryOp.equal.precedence());
    try testing.expect(BinaryOp.equal.precedence() > BinaryOp.bitwise_and.precedence());
    try testing.expect(BinaryOp.bitwise_and.precedence() > BinaryOp.logical_and.precedence());
    try testing.expect(BinaryOp.logical_and.precedence() > BinaryOp.assign.precedence());
}

test "Right associativity" {
    const testing = std.testing;

    // Power and assignment are right-associative
    try testing.expect(BinaryOp.power.isRightAssociative());
    try testing.expect(BinaryOp.assign.isRightAssociative());
    try testing.expect(BinaryOp.add_assign.isRightAssociative());

    // Most operators are left-associative
    try testing.expect(!BinaryOp.add.isRightAssociative());
    try testing.expect(!BinaryOp.multiply.isRightAssociative());
    try testing.expect(!BinaryOp.logical_and.isRightAssociative());
}
