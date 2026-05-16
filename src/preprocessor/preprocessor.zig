const std = @import("std");
const interpreter = @import("interpreter.zig");
const lexer = @import("../lexer/lexer.zig");
const parser = @import("../parser/parser.zig");

/// Preprocessor for HolyC source code
/// Handles conditional compilation (#ifdef, #ifndef, #else, #endif),
/// file inclusion (#include), and macro expansion
pub const Preprocessor = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    filename: []const u8,
    defines: std.StringHashMap([]const u8), // Macros with optional values
    output: std.ArrayList(u8),
    pos: usize = 0,
    line: usize = 1,
    column: usize = 1,
    include_depth: usize = 0, // Track recursion depth to prevent infinite loops
    io: *const std.Io = undefined, // For file operations
    owns_defines: bool = true, // Whether this preprocessor owns the defines map

    pub fn init(allocator: std.mem.Allocator, source: []const u8, filename: []const u8) !Preprocessor {
        return Preprocessor{
            .allocator = allocator,
            .source = source,
            .filename = filename,
            .defines = std.StringHashMap([]const u8).init(allocator),
            .output = .{ .items = &.{}, .capacity = 0 },
            .include_depth = 0,
        };
    }

    pub fn initWithIo(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, io: *const std.Io) !Preprocessor {
        return Preprocessor{
            .allocator = allocator,
            .source = source,
            .filename = filename,
            .defines = std.StringHashMap([]const u8).init(allocator),
            .output = .{ .items = &.{}, .capacity = 0 },
            .include_depth = 0,
            .io = io,
        };
    }

    /// Create a preprocessor for an included file (shares defines with parent)
    fn initForInclude(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, io: *const std.Io, parent_defines: std.StringHashMap([]const u8), depth: usize) !Preprocessor {
        return Preprocessor{
            .allocator = allocator,
            .source = source,
            .filename = filename,
            .defines = parent_defines,
            .output = .{ .items = &.{}, .capacity = 0 },
            .include_depth = depth,
            .io = io,
            .owns_defines = false, // Don't own the parent's defines
        };
    }

    pub fn deinit(self: *Preprocessor) void {
        // Only free defines if we own them
        if (self.owns_defines) {
            // Free all macro keys and values
            var it = self.defines.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            self.defines.deinit();
        }
        self.output.deinit(self.allocator);
    }

    /// Process the source and return the preprocessed text
    pub fn process(self: *Preprocessor) PreprocessorError![]const u8 {
        try self.processConditionals();
        return try self.output.toOwnedSlice(self.allocator);
    }

    /// Main preprocessing loop - handles conditional compilation
    fn processConditionals(self: *Preprocessor) PreprocessorError!void {
        const empty_slice = try self.allocator.alloc(bool, 0);
        var include_stack = std.ArrayList(bool).fromOwnedSlice(empty_slice);
        defer include_stack.deinit(self.allocator);

        // Start with including everything
        try include_stack.append(self.allocator, true);

        while (self.pos < self.source.len) {
            const currently_including = include_stack.items[include_stack.items.len - 1];

            // Check if we're at the start of a line (possibly with leading whitespace) and see a '#' directive
            if (self.isAtLineStart()) {
                const saved_pos = self.pos;
                self.skipWhitespace();
                
                if (self.peek() == '#') {
                const directive_line = self.line;
                
                _ = self.advance(); // consume '#'
                self.skipWhitespace();
                
                const directive = try self.readIdentifier();
                
                if (std.mem.eql(u8, directive, "define")) {
                    if (currently_including) {
                        try self.handleDefine();
                    }
                    self.skipToEndOfLine();
                } else if (std.mem.eql(u8, directive, "include")) {
                    if (currently_including) {
                        try self.handleInclude();
                    } else {
                        self.skipToEndOfLine();
                    }
                } else if (std.mem.eql(u8, directive, "ifdef")) {
                    const macro = try self.readDirectiveIdentifier();
                    const is_defined = self.defines.contains(macro);
                    try include_stack.append(self.allocator, currently_including and is_defined);
                    self.skipToEndOfLine();
                } else if (std.mem.eql(u8, directive, "ifndef")) {
                    const macro = try self.readDirectiveIdentifier();
                    const is_defined = self.defines.contains(macro);
                    try include_stack.append(self.allocator, currently_including and !is_defined);
                    self.skipToEndOfLine();
                } else if (std.mem.eql(u8, directive, "ifaot")) {
                    // AOT (ahead-of-time) compilation - always true for now
                    try include_stack.append(self.allocator, currently_including and true);
                    self.skipToEndOfLine();
                } else if (std.mem.eql(u8, directive, "ifjit")) {
                    // JIT (just-in-time) compilation - always false for now
                    try include_stack.append(self.allocator, currently_including and false);
                    self.skipToEndOfLine();
                } else if (std.mem.eql(u8, directive, "assert")) {
                    if (currently_including) {
                        try self.handleAssert();
                    }
                    self.skipToEndOfLine();
                } else if (std.mem.eql(u8, directive, "exe")) {
                    if (currently_including) {
                        try self.handleExe();
                    } else {
                        self.skipToEndOfLine();
                    }
                } else if (std.mem.eql(u8, directive, "else")) {
                    if (include_stack.items.len <= 1) {
                        return self.reportError(directive_line, "#else without matching #ifdef/#ifndef/#ifaot/#ifjit");
                    }
                    // Flip the current include state (if parent is including)
                    const parent_including = if (include_stack.items.len > 1) 
                        include_stack.items[include_stack.items.len - 2] 
                    else 
                        true;
                    include_stack.items[include_stack.items.len - 1] = parent_including and !currently_including;
                    self.skipToEndOfLine();
                } else if (std.mem.eql(u8, directive, "endif")) {
                    if (include_stack.items.len <= 1) {
                        return self.reportError(directive_line, "#endif without matching #ifdef/#ifndef/#ifaot/#ifjit");
                    }
                    _ = include_stack.pop();
                    self.skipToEndOfLine();
                } else {
                    // Unknown directive - if we're including, output it as-is
                    if (currently_including) {
                        try self.output.append(self.allocator, '#');
                        try self.output.appendSlice(self.allocator, directive);
                        // Copy rest of line
                        while (self.pos < self.source.len and self.peek() != '\n') {
                            try self.output.append(self.allocator, self.advance());
                        }
                    } else {
                        self.skipToEndOfLine();
                    }
                }
                
                // Output the newline if present
                if (self.pos < self.source.len and self.peek() == '\n') {
                    try self.output.append(self.allocator, self.advance());
                }
                } else {
                    // Not a directive, restore position and output the whitespace/content normally
                    self.pos = saved_pos;
                    if (currently_including) {
                        try self.output.append(self.allocator, self.advance());
                    } else {
                        _ = self.advance();
                    }
                }
            } else {
                // Regular content - check for identifier expansion if we're currently including
                if (currently_including) {
                    const ch = self.peek();
                    if (self.isIdentifierStart(ch)) {
                        // Try to expand identifier
                        try self.expandIdentifier();
                    } else {
                        try self.output.append(self.allocator, self.advance());
                    }
                } else {
                    _ = self.advance();
                }
            }
        }

        // Check for unclosed conditionals
        if (include_stack.items.len > 1) {
            return self.reportError(self.line, "Unclosed #ifdef/#ifndef/#ifaot/#ifjit at end of file");
        }
    }

    /// Handle #define directive
    fn handleDefine(self: *Preprocessor) PreprocessorError!void {
        self.skipWhitespace();
        const macro_name = try self.readIdentifier();
        
        if (macro_name.len == 0) {
            return self.reportError(self.line, "Expected identifier after #define");
        }

        // Read the rest of the line as the macro value
        self.skipWhitespace();
        const value_start = self.pos;
        while (self.pos < self.source.len and self.peek() != '\n') {
            _ = self.advance();
        }
        const value = self.source[value_start..self.pos];
        
        // Trim trailing whitespace from value
        var trimmed_value = value;
        while (trimmed_value.len > 0 and (trimmed_value[trimmed_value.len - 1] == ' ' or trimmed_value[trimmed_value.len - 1] == '\t')) {
            trimmed_value = trimmed_value[0..trimmed_value.len - 1];
        }
        
        // Check if this macro already exists and free old memory if so
        if (self.defines.get(macro_name)) |old_value| {
            const old_key = self.defines.getKey(macro_name).?;
            self.allocator.free(old_key);
            self.allocator.free(old_value);
            _ = self.defines.remove(macro_name);
        }
        
        const name_copy = try self.allocator.dupe(u8, macro_name);
        const value_copy = try self.allocator.dupe(u8, trimmed_value);
        try self.defines.put(name_copy, value_copy);
    }

    /// Handle #include directive
    fn handleInclude(self: *Preprocessor) PreprocessorError!void {
        const max_include_depth = 32;
        if (self.include_depth >= max_include_depth) {
            return self.reportError(self.line, "Maximum include depth exceeded (possible circular includes)");
        }

        self.skipWhitespace();
        
        // Read the filename - should be "filename" or <filename>
        const quote_char = self.peek();
        if (quote_char != '"' and quote_char != '<') {
            return self.reportError(self.line, "Expected '\"' or '<' after #include");
        }
        
        _ = self.advance(); // consume opening quote
        const close_char: u8 = if (quote_char == '"') '"' else '>';
        
        const filename_start = self.pos;
        while (self.pos < self.source.len and self.peek() != close_char and self.peek() != '\n') {
            _ = self.advance();
        }
        
        if (self.peek() != close_char) {
            return self.reportError(self.line, "Unterminated #include filename");
        }
        
        const include_filename = self.source[filename_start..self.pos];
        _ = self.advance(); // consume closing quote
        
        // Resolve the path relative to the current file's directory
        const include_path = try self.resolveIncludePath(include_filename, quote_char == '<');
        defer self.allocator.free(include_path);
        
        // Read the included file
        const cwd = std.Io.Dir.cwd();
        const included_source = cwd.readFileAlloc(self.io.*, include_path, self.allocator, std.Io.Limit.limited(1024 * 1024)) catch |err| {
            std.debug.print("[{s}:{d}] Failed to read include file '{s}': {}\n", .{ self.filename, self.line, include_path, err });
            return error.PreprocessorError;
        };
        defer self.allocator.free(included_source);
        
        // Create a new preprocessor for the included file, sharing defines
        var include_preprocessor = try Preprocessor.initForInclude(
            self.allocator,
            included_source,
            include_path,
            self.io,
            self.defines,
            self.include_depth + 1
        );
        defer include_preprocessor.deinit(); // Now safe - won't double-free
        
        // Process the included file
        const processed_include = try include_preprocessor.process();
        defer self.allocator.free(processed_include);
        
        // Append the processed content to our output
        try self.output.appendSlice(self.allocator, processed_include);
        
        self.skipToEndOfLine();
    }

    /// Handle #exe directive - execute code at compile time
    fn handleExe(self: *Preprocessor) PreprocessorError!void {
        self.skipWhitespace();
        
        // Check if it's a block { ... } or single line
        const is_block = self.peek() == '{';
        
        if (is_block) {
            // Block form: #exe { code }
            _ = self.advance(); // consume '{'
            
            const start_pos = self.pos;
            var brace_depth: i32 = 1;
            
            // Find matching closing brace
            while (self.pos < self.source.len and brace_depth > 0) {
                const ch = self.peek();
                if (ch == '{') {
                    brace_depth += 1;
                } else if (ch == '}') {
                    brace_depth -= 1;
                    if (brace_depth == 0) break;
                }
                _ = self.advance();
            }
            
            if (brace_depth != 0) {
                return self.reportError(self.line, "Unclosed #exe block");
            }
            
            const exe_code = self.source[start_pos..self.pos];
            _ = self.advance(); // consume '}'
            
            // Execute compile-time code
            try self.executeCompileTime(exe_code);
            
            self.skipToEndOfLine();
        } else {
            // Single line form: #exe statement;
            const start_pos = self.pos;
            
            // Read until end of line or semicolon
            while (self.pos < self.source.len and self.peek() != '\n' and self.peek() != ';') {
                _ = self.advance();
            }
            
            if (self.peek() == ';') {
                _ = self.advance(); // consume ';'
            }
            
            const exe_code = self.source[start_pos..self.pos];
            
            // Execute compile-time code
            try self.executeCompileTime(exe_code);
            
            self.skipToEndOfLine();
        }
    }

    /// Execute code at compile time using the interpreter
    fn executeCompileTime(self: *Preprocessor, code: []const u8) !void {
        var interp = interpreter.Interpreter.init(self.allocator);
        defer interp.deinit();
        
        // Execute the code and capture output
        const output = interp.execute(code) catch |err| {
            std.debug.print("Error executing #exe at line {d}: {}\n", .{ self.line, err });
            return;
        };
        defer self.allocator.free(output);
        
        // Print the output to stderr (compile-time output)
        if (output.len > 0) {
            std.debug.print("{s}", .{output});
        }
    }

    /// Handle #assert directive
    fn handleAssert(self: *Preprocessor) PreprocessorError!void {
        self.skipWhitespace();
        
        // Read the expression until end of line
        const expr_start = self.pos;
        while (self.pos < self.source.len and self.peek() != '\n') {
            _ = self.advance();
        }
        
        const expr_text = std.mem.trim(u8, self.source[expr_start..self.pos], &std.ascii.whitespace);
        
        if (expr_text.len == 0) {
            return self.reportError(self.line, "Expected expression after #assert");
        }
        
        // Substitute defines in the expression
        const substituted = try self.substituteDefines(expr_text);
        defer if (substituted.ptr != expr_text.ptr) self.allocator.free(substituted);
        
        // Evaluate the expression at compile time
        var interp = interpreter.Interpreter.init(self.allocator);
        defer interp.deinit();
        
        // Parse and evaluate the expression
        const result = self.evaluateAssertExpression(&interp, substituted) catch |err| {
            std.debug.print("[{s}:{d}] Warning: #assert expression could not be evaluated: {}\n", .{ self.filename, self.line, err });
            std.debug.print("  Expression: {s}\n", .{substituted});
            return;
        };
        
        // Check if the result is false/zero
        const is_true = switch (result) {
            .int => |i| i != 0,
            .bool => |b| b,
            .float => |f| f != 0.0,
            else => false,
        };
        
        if (!is_true) {
            std.debug.print("[{s}:{d}] Warning: #assert failed: {s}\n", .{ self.filename, self.line, substituted });
        }
    }
    
    /// Substitute defines in an expression
    fn substituteDefines(self: *Preprocessor, text: []const u8) ![]const u8 {
        const empty_slice = try self.allocator.alloc(u8, 0);
        var result = std.ArrayList(u8).fromOwnedSlice(empty_slice);
        defer result.deinit(self.allocator);
        
        var i: usize = 0;
        while (i < text.len) {
            // Check if we're at an identifier
            if (std.ascii.isAlphabetic(text[i]) or text[i] == '_') {
                const ident_start = i;
                while (i < text.len and (std.ascii.isAlphanumeric(text[i]) or text[i] == '_')) {
                    i += 1;
                }
                const ident = text[ident_start..i];
                
                // Check if this is a defined macro
                if (self.defines.get(ident)) |value| {
                    try result.appendSlice(self.allocator, value);
                } else {
                    try result.appendSlice(self.allocator, ident);
                }
            } else {
                try result.append(self.allocator, text[i]);
                i += 1;
            }
        }
        
        return try result.toOwnedSlice(self.allocator);
    }
    
    /// Evaluate an assertion expression
    fn evaluateAssertExpression(self: *Preprocessor, interp: *interpreter.Interpreter, expr_text: []const u8) !interpreter.Interpreter.Value {
        // Create an arena for AST allocations
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        
        // Create a simple lexer and parser for the expression
        var lex = lexer.Lexer.init(arena.allocator(), expr_text);
        
        var pars = try parser.Parser.init(arena.allocator(), &lex);
        defer pars.deinit();
        
        // Parse as an expression
        const expr = try pars.parseExpression();
        
        // Evaluate the expression
        return try interp.evaluateExpression(expr);
    }

    /// Expand an identifier if it's a defined macro
    fn expandIdentifier(self: *Preprocessor) !void {
        const start_pos = self.pos;
        const identifier = try self.readIdentifier();
        
        if (identifier.len == 0) {
            // Not an identifier, just output the char
            self.pos = start_pos;
            try self.output.append(self.allocator, self.advance());
            return;
        }
        
        // Check if this identifier is a defined macro
        if (self.defines.get(identifier)) |value| {
            // Expand the macro by outputting its value
            try self.output.appendSlice(self.allocator, value);
        } else {
            // Not a macro, output the identifier as-is
            try self.output.appendSlice(self.allocator, identifier);
        }
    }

    /// Resolve include path relative to current file or as absolute
    fn resolveIncludePath(self: *Preprocessor, include_name: []const u8, is_system: bool) ![]const u8 {
        _ = is_system; // For now, treat both <> and "" the same way
        
        // Append .hc extension if not already present
        const has_extension = std.mem.endsWith(u8, include_name, ".hc") or 
                             std.mem.endsWith(u8, include_name, ".HC");
        
        const full_name = if (has_extension)
            include_name
        else
            try std.fmt.allocPrint(self.allocator, "{s}.hc", .{include_name});
        defer if (!has_extension) self.allocator.free(full_name);
        
        // Get the directory of the current file
        const last_slash = std.mem.lastIndexOfScalar(u8, self.filename, '/');
        
        if (last_slash) |slash_pos| {
            const dir = self.filename[0..slash_pos + 1];
            return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ dir, full_name });
        } else {
            // No directory in filename, duplicate the full name
            return try self.allocator.dupe(u8, full_name);
        }
    }

    /// Read an identifier for a directive argument
    fn readDirectiveIdentifier(self: *Preprocessor) ![]const u8 {
        self.skipWhitespace();
        return try self.readIdentifier();
    }

    /// Read an identifier from current position
    fn readIdentifier(self: *Preprocessor) ![]const u8 {
        const start = self.pos;
        
        if (self.pos >= self.source.len or !self.isIdentifierStart(self.peek())) {
            return "";
        }
        
        _ = self.advance();
        
        while (self.pos < self.source.len and self.isIdentifierChar(self.peek())) {
            _ = self.advance();
        }
        
        return self.source[start..self.pos];
    }

    fn isIdentifierStart(self: *Preprocessor, c: u8) bool {
        _ = self;
        return std.ascii.isAlphabetic(c) or c == '_';
    }

    fn isIdentifierChar(self: *Preprocessor, c: u8) bool {
        _ = self;
        return std.ascii.isAlphanumeric(c) or c == '_';
    }

    fn isAtLineStart(self: *Preprocessor) bool {
        // We're at line start if pos is 0 or the previous char was a newline
        return self.pos == 0 or (self.pos > 0 and self.source[self.pos - 1] == '\n');
    }

    fn peek(self: *Preprocessor) u8 {
        if (self.pos >= self.source.len) return 0;
        return self.source[self.pos];
    }

    fn advance(self: *Preprocessor) u8 {
        if (self.pos >= self.source.len) return 0;
        const c = self.source[self.pos];
        self.pos += 1;
        
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        
        return c;
    }

    fn skipWhitespace(self: *Preprocessor) void {
        while (self.pos < self.source.len) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\r') {
                _ = self.advance();
            } else {
                break;
            }
        }
    }

    fn skipToEndOfLine(self: *Preprocessor) void {
        while (self.pos < self.source.len and self.peek() != '\n') {
            _ = self.advance();
        }
    }

    fn reportError(self: *Preprocessor, line: usize, message: []const u8) error{PreprocessorError} {
        std.debug.print("[{s}:{d}] Preprocessor error: {s}\n", .{ self.filename, line, message });
        return error.PreprocessorError;
    }
};

pub const PreprocessorError = error{
    PreprocessorError,
    OutOfMemory,
};
