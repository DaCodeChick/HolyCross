const std = @import("std");

/// Compilation target platform
pub const Target = enum {
    /// Native x64 Linux/ELF executable
    native_x64_linux,
    /// TempleOS .BIN format
    templeos,
    /// ZealOS .BIN format (potentially different conventions)
    zealos,

    pub fn fromString(s: []const u8) !Target {
        if (std.mem.eql(u8, s, "native") or std.mem.eql(u8, s, "native-x64-linux")) {
            return .native_x64_linux;
        } else if (std.mem.eql(u8, s, "templeos")) {
            return .templeos;
        } else if (std.mem.eql(u8, s, "zealos")) {
            return .zealos;
        }
        return error.InvalidTarget;
    }

    pub fn toString(self: Target) []const u8 {
        return switch (self) {
            .native_x64_linux => "native-x64-linux",
            .templeos => "templeos",
            .zealos => "zealos",
        };
    }

    pub fn defaultExtension(self: Target) []const u8 {
        return switch (self) {
            .native_x64_linux => "",
            .templeos, .zealos => ".BIN",
        };
    }

    pub fn supportsInlineAsm(self: Target) bool {
        return switch (self) {
            .native_x64_linux => true,
            .templeos => true,
            .zealos => true,
        };
    }

    pub fn requiresRelocations(self: Target) bool {
        return switch (self) {
            .native_x64_linux => false,
            .templeos, .zealos => true, // .BIN patch table required
        };
    }
};

/// Target-specific configuration
pub const TargetConfig = struct {
    target: Target,
    /// Whether to emit detailed debug info
    debug_info: bool = false,
    /// Whether to optimize code
    optimize: bool = false,

    pub fn init(target: Target) TargetConfig {
        return .{
            .target = target,
            .debug_info = false,
            .optimize = false,
        };
    }
};
