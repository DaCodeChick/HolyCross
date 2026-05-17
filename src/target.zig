const std = @import("std");

/// Target platform and architecture
pub const Target = struct {
    os: OS,
    arch: Arch,
    abi: ABI,
    
    pub const OS = enum {
        linux,
        windows,
        templeos,
        
        pub fn toString(self: OS) []const u8 {
            return switch (self) {
                .linux => "linux",
                .windows => "windows",
                .templeos => "templeos",
            };
        }
    };
    
    pub const Arch = enum {
        x64,
        
        pub fn toString(self: Arch) []const u8 {
            return switch (self) {
                .x64 => "x64",
            };
        }
    };
    
    pub const ABI = enum {
        none,      // TempleOS (no standard ABI)
        gnu,       // Linux GNU / MinGW (GCC-based Windows)
        msvc,      // Windows MSVC
        
        pub fn toString(self: ABI) []const u8 {
            return switch (self) {
                .none => "none",
                .gnu => "gnu",
                .msvc => "msvc",
            };
        }
        
        /// Check if this ABI uses GCC/GNU toolchain conventions
        pub fn isGNU(self: ABI) bool {
            return self == .gnu;
        }
        
        /// Check if this ABI uses Microsoft conventions
        pub fn isMSVC(self: ABI) bool {
            return self == .msvc;
        }
    };
    
    /// Get the native target (host system)
    pub fn native() Target {
        const builtin = @import("builtin");
        return .{
            .os = switch (builtin.os.tag) {
                .linux => .linux,
                .windows => .windows,
                else => .linux, // Default to Linux for unknown
            },
            .arch = .x64,
            .abi = switch (builtin.os.tag) {
                .linux => .gnu,
                .windows => .msvc,
                else => .gnu,
            },
        };
    }
    
    /// Parse a target triple string (e.g., "x64-linux-gnu", "windows-x64-msvc", "x64-windows-gnu")
    pub fn parse(triple: []const u8) !Target {
        var parts = std.mem.splitScalar(u8, triple, '-');
        
        var os: ?OS = null;
        var arch: ?Arch = null;
        var abi: ?ABI = null;
        
        while (parts.next()) |part| {
            if (std.mem.eql(u8, part, "x64") or std.mem.eql(u8, part, "x86_64") or std.mem.eql(u8, part, "amd64")) {
                arch = .x64;
            } else if (std.mem.eql(u8, part, "linux")) {
                os = .linux;
            } else if (std.mem.eql(u8, part, "windows") or std.mem.eql(u8, part, "win64") or std.mem.eql(u8, part, "mingw64") or std.mem.eql(u8, part, "w64")) {
                os = .windows;
            } else if (std.mem.eql(u8, part, "templeos")) {
                os = .templeos;
            } else if (std.mem.eql(u8, part, "gnu") or std.mem.eql(u8, part, "mingw")) {
                abi = .gnu;
            } else if (std.mem.eql(u8, part, "msvc")) {
                abi = .msvc;
            } else if (std.mem.eql(u8, part, "none")) {
                abi = .none;
            }
        }
        
        // Set defaults based on OS if not specified
        const final_os = os orelse OS.linux;
        const final_arch = arch orelse Arch.x64;
        const final_abi = if (abi) |a| a else switch (final_os) {
            OS.linux => ABI.gnu,
            OS.windows => ABI.msvc,
            OS.templeos => ABI.none,
        };
        
        return .{
            .os = final_os,
            .arch = final_arch,
            .abi = final_abi,
        };
    }
    
    /// Get a string representation of the target
    pub fn toString(self: Target, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{
            self.arch.toString(),
            self.os.toString(),
            self.abi.toString(),
        });
    }
    
    /// Get the calling convention for this target
    pub fn callingConvention(self: Target) CallingConvention {
        return switch (self.os) {
            .linux => .sysv,
            .windows => .win64,
            .templeos => .sysv, // TempleOS uses System V-like convention
        };
    }
    
    /// Get the object file format for this target
    pub fn objectFormat(self: Target) ObjectFormat {
        return switch (self.os) {
            .linux => .elf,
            .windows => .coff,
            .templeos => .bin,
        };
    }
    
    /// Get the executable format for this target
    pub fn executableFormat(self: Target) ExecutableFormat {
        return switch (self.os) {
            .linux => .elf,
            .windows => .pe,
            .templeos => .bin,
        };
    }
    
    /// Get the default file extension for executables
    pub fn executableExtension(self: Target) []const u8 {
        return switch (self.os) {
            .linux => "",
            .windows => ".exe",
            .templeos => ".BIN",
        };
    }
    
    /// Get the default file extension for object files
    pub fn objectExtension(self: Target) []const u8 {
        return switch (self.os) {
            .linux => ".o",
            .windows => ".obj",
            .templeos => ".OBJ",
        };
    }
    
    /// Check if this is a MinGW target (Windows + GNU ABI)
    pub fn isMinGW(self: Target) bool {
        return self.os == .windows and self.abi == .gnu;
    }
    
    /// Check if this is an MSVC target (Windows + MSVC ABI)
    pub fn isMSVC(self: Target) bool {
        return self.os == .windows and self.abi == .msvc;
    }
    
    /// Get default C runtime library for linking
    pub fn defaultCRuntime(self: Target) []const u8 {
        if (self.os == .windows) {
            return if (self.abi == .gnu) "msvcrt.dll" else "ucrt.dll";  // MinGW uses msvcrt, MSVC uses UCRT
        }
        return "libc.so.6";
    }
};

pub const CallingConvention = enum {
    sysv,   // System V AMD64 ABI (Linux, BSD)
    win64,  // Microsoft x64 calling convention (Windows)
    
    pub fn toString(self: CallingConvention) []const u8 {
        return switch (self) {
            .sysv => "System V",
            .win64 => "Win64",
        };
    }
    
    /// Get parameter registers in order
    pub fn parameterRegisters(self: CallingConvention) []const []const u8 {
        return switch (self) {
            .sysv => &.{"rdi", "rsi", "rdx", "rcx", "r8", "r9"},
            .win64 => &.{"rcx", "rdx", "r8", "r9"},
        };
    }
    
    /// Get the shadow space size (stack space reserved for register params)
    pub fn shadowSpace(self: CallingConvention) usize {
        return switch (self) {
            .sysv => 0,    // No shadow space
            .win64 => 32,  // 4 × 8 bytes for RCX, RDX, R8, R9
        };
    }
    
    /// Check if stack must be 16-byte aligned before CALL
    pub fn requiresStackAlignment(self: CallingConvention) bool {
        _ = self;
        return true; // Both conventions require 16-byte alignment
    }
};

pub const ObjectFormat = enum {
    elf,   // ELF object file (.o)
    coff,  // COFF object file (.obj)
    bin,   // Raw binary (TempleOS .OBJ)
    
    pub fn toString(self: ObjectFormat) []const u8 {
        return switch (self) {
            .elf => "ELF",
            .coff => "COFF",
            .bin => "BIN",
        };
    }
};

pub const ExecutableFormat = enum {
    elf,   // ELF executable
    pe,    // PE32+ executable (.exe)
    bin,   // TempleOS binary (.BIN)
    
    pub fn toString(self: ExecutableFormat) []const u8 {
        return switch (self) {
            .elf => "ELF",
            .pe => "PE32+",
            .bin => "BIN",
        };
    }
};

// Tests
test "Target.parse - Linux x64" {
    const target = try Target.parse("x64-linux-gnu");
    try std.testing.expectEqual(Target.OS.linux, target.os);
    try std.testing.expectEqual(Target.Arch.x64, target.arch);
    try std.testing.expectEqual(Target.ABI.gnu, target.abi);
}

test "Target.parse - Windows x64" {
    const target = try Target.parse("windows-x64");
    try std.testing.expectEqual(Target.OS.windows, target.os);
    try std.testing.expectEqual(Target.Arch.x64, target.arch);
    try std.testing.expectEqual(Target.ABI.msvc, target.abi);
}

test "Target.parse - MinGW x64" {
    const target = try Target.parse("x64-windows-gnu");
    try std.testing.expectEqual(Target.OS.windows, target.os);
    try std.testing.expectEqual(Target.Arch.x64, target.arch);
    try std.testing.expectEqual(Target.ABI.gnu, target.abi);
    try std.testing.expect(target.isMinGW());
    try std.testing.expect(!target.isMSVC());
}

test "Target.parse - MSVC explicit" {
    const target = try Target.parse("x64-windows-msvc");
    try std.testing.expectEqual(Target.OS.windows, target.os);
    try std.testing.expectEqual(Target.ABI.msvc, target.abi);
    try std.testing.expect(target.isMSVC());
    try std.testing.expect(!target.isMinGW());
}

test "Target.parse - TempleOS" {
    const target = try Target.parse("templeos-x64");
    try std.testing.expectEqual(Target.OS.templeos, target.os);
    try std.testing.expectEqual(Target.Arch.x64, target.arch);
    try std.testing.expectEqual(Target.ABI.none, target.abi);
}

test "Target calling conventions" {
    const linux = try Target.parse("x64-linux");
    try std.testing.expectEqual(CallingConvention.sysv, linux.callingConvention());
    
    const windows = try Target.parse("x64-windows");
    try std.testing.expectEqual(CallingConvention.win64, windows.callingConvention());
}

test "CallingConvention parameter registers" {
    const sysv_regs = CallingConvention.sysv.parameterRegisters();
    try std.testing.expectEqual(@as(usize, 6), sysv_regs.len);
    try std.testing.expectEqualStrings("rdi", sysv_regs[0]);
    
    const win64_regs = CallingConvention.win64.parameterRegisters();
    try std.testing.expectEqual(@as(usize, 4), win64_regs.len);
    try std.testing.expectEqualStrings("rcx", win64_regs[0]);
}

test "CallingConvention shadow space" {
    try std.testing.expectEqual(@as(usize, 0), CallingConvention.sysv.shadowSpace());
    try std.testing.expectEqual(@as(usize, 32), CallingConvention.win64.shadowSpace());
}
