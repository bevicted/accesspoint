const std = @import("std");
const builtin = @import("builtin");
const tui = @import("tui.zig");
const Parser = @import("parser/parser.zig");
const models = @import("parser/models.zig");

const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) {
        std.log.err("Memory leak", .{});
    };
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const path = if (args.len >= 2)
        try allocator.dupe(u8, args[1])
    else
        resolveDefaultPath(allocator) catch |err| {
            std.log.err("cannot resolve default config path: {}", .{err});
            return;
        };
    defer allocator.free(path);

    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
        std.log.err("cannot open '{s}': {}", .{ path, err });
        return;
    };
    defer allocator.free(source);

    const layers = Parser.parse(allocator, source) catch |err| {
        if (err != error.OutOfMemory) return; // parser already logged the error
        return err;
    };
    defer layers.deinit();

    const selected = try tui.run(allocator, layers) orelse return;

    const instructions = try collect_instructions(allocator, layers, selected);
    defer allocator.free(instructions);

    execute_instructions(allocator, instructions);
}

fn resolveDefaultPath(allocator: Allocator) error{ HomeNotSet, OutOfMemory }![]const u8 {
    const xdg = std.posix.getenv("XDG_CONFIG_HOME");
    const config_base = xdg orelse blk: {
        const home = std.posix.getenv("HOME") orelse return error.HomeNotSet;
        break :blk try std.fs.path.join(allocator, &.{ home, ".config" });
    };
    defer if (xdg == null) allocator.free(config_base);
    return try std.fs.path.join(allocator, &.{ config_base, "ap", "default.ap" });
}

fn collect_instructions(allocator: Allocator, layers: models.Layers, leaf_index: usize) ![]const models.Instruction {
    var slices: std.ArrayList([]const models.Instruction) = .empty;
    defer slices.deinit(allocator);

    var idx: ?usize = leaf_index;
    while (idx) |i| {
        if (layers.items[i].instructions.len > 0) {
            try slices.append(allocator, layers.items[i].instructions);
        }
        idx = layers.items[i].parent;
    }

    // Reverse so root's instructions come first
    std.mem.reverse([]const models.Instruction, slices.items);

    // Flatten into single array
    var total: usize = 0;
    for (slices.items) |s| total += s.len;
    const result = try allocator.alloc(models.Instruction, total);
    var pos: usize = 0;
    for (slices.items) |s| {
        @memcpy(result[pos..][0..s.len], s);
        pos += s.len;
    }

    return result;
}

fn execute_instructions(allocator: Allocator, instructions: []const models.Instruction) void {
    for (instructions) |instr| {
        switch (instr) {
            .open => |url| execute_open(allocator, url),
            .run => |cmd| execute_run(allocator, cmd),
            .print => |text| {
                const stdout = std.fs.File.stdout();
                stdout.writeAll(text) catch {};
                stdout.writeAll("\n") catch {};
            },
        }
    }
}

fn execute_open(allocator: Allocator, url: []const u8) void {
    const cmd: []const u8 = switch (builtin.os.tag) {
        .linux => "xdg-open",
        .macos => "open",
        else => {
            std.log.err("unsupported platform for open", .{});
            return;
        },
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ cmd, url },
    }) catch |err| {
        std.log.err("open failed: {}", .{err});
        return;
    };
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

fn execute_run(allocator: Allocator, cmd: []const u8) void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "sh", "-c", cmd },
    }) catch |err| {
        std.log.err("run failed: {}", .{err});
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        const stdout = std.fs.File.stdout();
        stdout.writeAll(result.stdout) catch {};
    }
    if (result.stderr.len > 0) {
        const stderr = std.fs.File.stderr();
        stderr.writeAll(result.stderr) catch {};
    }
}
