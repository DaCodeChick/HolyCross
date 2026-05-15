const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("../parser/parser.zig");
const ast = @import("../parser/ast.zig");

const Lexer = lexer.Lexer;
const Parser = parser.Parser;
const Expr = ast.Expr;
const Stmt = ast.Stmt;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;

/// Compile-time interpreter for #exe blocks
/// Executes HolyC code during preprocessing
pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    variables: std.StringHashMap(Value),
    output: std.ArrayList(u8), // Capture Print() output
    
    pub const Value = union(enum) {
        int: i64,
        float: f64,
        string: []const u8,
        bool: bool,
        void,
        
        pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            switch (self) {
                .int => |i| try writer.print("{d}", .{i}),
                .float => |f| try writer.print("{d}", .{f}),
                .string => |s| try writer.writeAll(s),
                .bool => |b| try writer.writeAll(if (b) "TRUE" else "FALSE"),
                .void => try writer.writeAll("void"),
            }
        }
    };
    
    pub const InterpreterError = error{
        RuntimeError,
        UndefinedVariable,
        TypeMismatch,
        DivisionByZero,
        UnsupportedOperation,
    } || std.mem.Allocator.Error;
    
    pub fn init(allocator: std.mem.Allocator) Interpreter {
        return .{
            .allocator = allocator,
            .variables = std.StringHashMap(Value).init(allocator),
            .output = .{ .items = &.{}, .capacity = 0 },
        };
    }
    
    pub fn deinit(self: *Interpreter) void {
        self.variables.deinit();
        self.output.deinit(self.allocator);
    }
    
    /// Execute code at compile time
    /// Returns the captured output from Print() calls
    pub fn execute(self: *Interpreter, code: []const u8) ![]const u8 {
        // Create lexer and parser for the code
        var lex = Lexer.init(self.allocator, code);
        var parse = try Parser.init(self.allocator, &lex);
        defer parse.deinit();
        
        // Parse the code into statements
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        parse.ast_allocator = arena.allocator();
        
        const empty_slice = try self.allocator.alloc(Stmt, 0);
        var statements = std.ArrayList(Stmt).fromOwnedSlice(empty_slice);
        defer statements.deinit(self.allocator);
        
        // Parse statements until EOF
        while (parse.current.type != .eof) {
            if (parse.parseStatement()) |stmt| {
                try statements.append(self.allocator, stmt);
            } else |err| {
                std.debug.print("Parse error during #exe: {}\n", .{err});
                return error.RuntimeError;
            }
        }
        
        // Execute each statement
        for (statements.items) |stmt| {
            _ = try self.executeStatement(stmt);
        }
        
        return try self.output.toOwnedSlice(self.allocator);
    }
    
    fn executeStatement(self: *Interpreter, stmt: Stmt) InterpreterError!Value {
        switch (stmt) {
            .expr => |expr_stmt| {
                return try self.evaluateExpression(expr_stmt.expr);
            },
            .var_decl => |decl| {
                const value = if (decl.init) |initializer|
                    try self.evaluateExpression(initializer)
                else
                    Value{ .int = 0 }; // Default initialization
                
                try self.variables.put(decl.name, value);
                return Value.void;
            },
            .return_stmt => |ret| {
                if (ret.expr) |val| {
                    return try self.evaluateExpression(val);
                }
                return Value.void;
            },
            .block => |block_stmt| {
                var last_value: Value = .void;
                for (block_stmt.stmts) |s| {
                    last_value = try self.executeStatement(s);
                }
                return last_value;
            },
            .if_stmt => |if_stmt| {
                const condition = try self.evaluateExpression(if_stmt.condition);
                const is_true = switch (condition) {
                    .bool => |b| b,
                    .int => |i| i != 0,
                    else => return error.TypeMismatch,
                };
                
                if (is_true) {
                    return try self.executeStatement(if_stmt.then_stmt.*);
                } else if (if_stmt.else_stmt) |else_branch| {
                    return try self.executeStatement(else_branch.*);
                }
                return Value.void;
            },
            .while_stmt => |while_stmt| {
                while (true) {
                    const condition = try self.evaluateExpression(while_stmt.condition);
                    const is_true = switch (condition) {
                        .bool => |b| b,
                        .int => |i| i != 0,
                        else => return error.TypeMismatch,
                    };
                    
                    if (!is_true) break;
                    _ = try self.executeStatement(while_stmt.body.*);
                }
                return Value.void;
            },
            else => {
                std.debug.print("Unsupported statement type in #exe: {s}\n", .{@tagName(stmt)});
                return error.UnsupportedOperation;
            },
        }
    }
    
    pub fn evaluateExpression(self: *Interpreter, expr: Expr) InterpreterError!Value {
        switch (expr) {
            .integer => |lit| return Value{ .int = lit.value },
            .float => |lit| return Value{ .float = lit.value },
            .string => |lit| return Value{ .string = lit.value },
            
            .identifier => |ident| {
                return self.variables.get(ident.name) orelse {
                    std.debug.print("Undefined variable: {s}\n", .{ident.name});
                    return error.UndefinedVariable;
                };
            },
            
            .binary => |bin| {
                // Handle assignment operators specially
                if (bin.op == .assign) {
                    const value = try self.evaluateExpression(bin.right.*);
                    
                    // Handle simple identifier assignment
                    if (bin.left.* == .identifier) {
                        const name = bin.left.identifier.name;
                        try self.variables.put(name, value);
                        return value;
                    }
                    
                    std.debug.print("Complex assignment not yet supported in #exe\n", .{});
                    return error.UnsupportedOperation;
                }
                
                const left = try self.evaluateExpression(bin.left.*);
                const right = try self.evaluateExpression(bin.right.*);
                return try self.evaluateBinaryOp(bin.op, left, right);
            },
            
            .unary => |un| {
                const operand = try self.evaluateExpression(un.operand.*);
                return try self.evaluateUnaryOp(un.op, operand);
            },
            
            .call => |call| {
                return try self.evaluateCall(call.callee.*, call.args);
            },
            
            else => {
                std.debug.print("Unsupported expression type in #exe: {s}\n", .{@tagName(expr)});
                return error.UnsupportedOperation;
            },
        }
    }
    
    fn evaluateBinaryOp(self: *Interpreter, op: BinaryOp, left: Value, right: Value) InterpreterError!Value {
        _ = self;
        
        // Handle integer operations
        if (left == .int and right == .int) {
            const l = left.int;
            const r = right.int;
            
            return switch (op) {
                .add => Value{ .int = l + r },
                .subtract => Value{ .int = l - r },
                .multiply => Value{ .int = l * r },
                .divide => {
                    if (r == 0) return error.DivisionByZero;
                    return Value{ .int = @divTrunc(l, r) };
                },
                .modulo => {
                    if (r == 0) return error.DivisionByZero;
                    return Value{ .int = @rem(l, r) };
                },
                .power => Value{ .int = std.math.pow(i64, l, r) },
                .equal => Value{ .bool = l == r },
                .not_equal => Value{ .bool = l != r },
                .less => Value{ .bool = l < r },
                .less_equal => Value{ .bool = l <= r },
                .greater => Value{ .bool = l > r },
                .greater_equal => Value{ .bool = l >= r },
                .bitwise_and => Value{ .int = l & r },
                .bitwise_or => Value{ .int = l | r },
                .bitwise_xor => Value{ .int = l ^ r },
                .shift_left => Value{ .int = l << @intCast(r) },
                .shift_right => Value{ .int = l >> @intCast(r) },
                .logical_and => Value{ .bool = (l != 0) and (r != 0) },
                .logical_or => Value{ .bool = (l != 0) or (r != 0) },
                .logical_xor => Value{ .bool = (l != 0) != (r != 0) },
                else => error.UnsupportedOperation,
            };
        }
        
        // Handle float operations
        if (left == .float and right == .float) {
            const l = left.float;
            const r = right.float;
            
            return switch (op) {
                .add => Value{ .float = l + r },
                .subtract => Value{ .float = l - r },
                .multiply => Value{ .float = l * r },
                .divide => Value{ .float = l / r },
                .power => Value{ .float = std.math.pow(f64, l, r) },
                .equal => Value{ .bool = l == r },
                .not_equal => Value{ .bool = l != r },
                .less => Value{ .bool = l < r },
                .less_equal => Value{ .bool = l <= r },
                .greater => Value{ .bool = l > r },
                .greater_equal => Value{ .bool = l >= r },
                else => error.UnsupportedOperation,
            };
        }
        
        // Mixed int/float operations - promote to float
        if ((left == .int or left == .float) and (right == .int or right == .float)) {
            const l = if (left == .int) @as(f64, @floatFromInt(left.int)) else left.float;
            const r = if (right == .int) @as(f64, @floatFromInt(right.int)) else right.float;
            
            return switch (op) {
                .add => Value{ .float = l + r },
                .subtract => Value{ .float = l - r },
                .multiply => Value{ .float = l * r },
                .divide => Value{ .float = l / r },
                .power => Value{ .float = std.math.pow(f64, l, r) },
                .equal => Value{ .bool = l == r },
                .not_equal => Value{ .bool = l != r },
                .less => Value{ .bool = l < r },
                .less_equal => Value{ .bool = l <= r },
                .greater => Value{ .bool = l > r },
                .greater_equal => Value{ .bool = l >= r },
                else => error.UnsupportedOperation,
            };
        }
        
        return error.TypeMismatch;
    }
    
    fn evaluateUnaryOp(self: *Interpreter, op: UnaryOp, operand: Value) InterpreterError!Value {
        _ = self;
        
        return switch (op) {
            .negate => switch (operand) {
                .int => |i| Value{ .int = -i },
                .float => |f| Value{ .float = -f },
                else => error.TypeMismatch,
            },
            .logical_not => switch (operand) {
                .int => |i| Value{ .bool = i == 0 },
                .bool => |b| Value{ .bool = !b },
                else => error.TypeMismatch,
            },
            .bitwise_not => switch (operand) {
                .int => |i| Value{ .int = ~i },
                else => error.TypeMismatch,
            },
            else => error.UnsupportedOperation,
        };
    }
    
    fn evaluateCall(self: *Interpreter, callee: Expr, args: []Expr) InterpreterError!Value {
        // Check if it's a function call to a known built-in
        if (callee == .identifier) {
            const func_name = callee.identifier.name;
            
            // Handle Print() function
            if (std.mem.eql(u8, func_name, "Print")) {
                return try self.builtinPrint(args);
            }
        }
        
        std.debug.print("Unknown function call in #exe\n", .{});
        return error.UnsupportedOperation;
    }
    
    fn builtinPrint(self: *Interpreter, args: []Expr) InterpreterError!Value {
        if (args.len == 0) {
            return Value.void;
        }
        
        // First argument should be a format string
        const fmt_value = try self.evaluateExpression(args[0]);
        if (fmt_value != .string) {
            std.debug.print("Print() expects a string format as first argument\n", .{});
            return error.TypeMismatch;
        }
        
        const format_str = fmt_value.string;
        
        // Parse the format string and substitute values (or just process escapes if no args)
        var arg_index: usize = 1;
        var i: usize = 0;
        
        while (i < format_str.len) {
            if (format_str[i] == '%' and i + 1 < format_str.len) {
                const spec = format_str[i + 1];
                
                // Handle %%
                if (spec == '%') {
                    try self.output.append(self.allocator, '%');
                    i += 2;
                    continue;
                }
                
                // Get next argument
                if (arg_index >= args.len) {
                    try self.output.append(self.allocator, format_str[i]);
                    i += 1;
                    continue;
                }
                
                const arg_value = try self.evaluateExpression(args[arg_index]);
                arg_index += 1;
                
                // Format based on specifier
                switch (spec) {
                    'd', 'i' => {
                        if (arg_value == .int) {
                            const formatted = try std.fmt.allocPrint(self.allocator, "{d}", .{arg_value.int});
                            defer self.allocator.free(formatted);
                            try self.output.appendSlice(self.allocator, formatted);
                        } else {
                            return error.TypeMismatch;
                        }
                    },
                    'f' => {
                        if (arg_value == .float) {
                            const formatted = try std.fmt.allocPrint(self.allocator, "{d}", .{arg_value.float});
                            defer self.allocator.free(formatted);
                            try self.output.appendSlice(self.allocator, formatted);
                        } else if (arg_value == .int) {
                            const formatted = try std.fmt.allocPrint(self.allocator, "{d}", .{@as(f64, @floatFromInt(arg_value.int))});
                            defer self.allocator.free(formatted);
                            try self.output.appendSlice(self.allocator, formatted);
                        } else {
                            return error.TypeMismatch;
                        }
                    },
                    's' => {
                        if (arg_value == .string) {
                            try self.output.appendSlice(self.allocator, arg_value.string);
                        } else {
                            return error.TypeMismatch;
                        }
                    },
                    'c' => {
                        if (arg_value == .int) {
                            try self.output.append(self.allocator, @intCast(arg_value.int));
                        } else {
                            return error.TypeMismatch;
                        }
                    },
                    else => {
                        // Unknown format specifier, just print it
                        try self.output.append(self.allocator, '%');
                        try self.output.append(self.allocator, spec);
                    },
                }
                
                i += 2;
            } else if (format_str[i] == '\\' and i + 1 < format_str.len) {
                // Handle escape sequences
                const next = format_str[i + 1];
                switch (next) {
                    'n' => try self.output.append(self.allocator, '\n'),
                    't' => try self.output.append(self.allocator, '\t'),
                    'r' => try self.output.append(self.allocator, '\r'),
                    '\\' => try self.output.append(self.allocator, '\\'),
                    '"' => try self.output.append(self.allocator, '"'),
                    else => {
                        try self.output.append(self.allocator, format_str[i]);
                        try self.output.append(self.allocator, next);
                    },
                }
                i += 2;
            } else {
                try self.output.append(self.allocator, format_str[i]);
                i += 1;
            }
        }
        
        return Value.void;
    }
};
