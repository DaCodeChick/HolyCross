const std = @import("std");

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
        };
    }

    pub fn deinit(self: *Preprocessor) void {
        // Free all macro values
        var it = self.defines.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.defines.deinit();
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
        
        const value_copy = try self.allocator.dupe(u8, trimmed_value);
        try self.defines.put(macro_name, value_copy);
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
        defer include_preprocessor.defines = std.StringHashMap([]const u8).init(self.allocator); // Prevent double-free
        
        // Process the included file
        const processed_include = try include_preprocessor.process();
        defer self.allocator.free(processed_include);
        
        // Append the processed content to our output
        try self.output.appendSlice(self.allocator, processed_include);
        
        self.skipToEndOfLine();
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
