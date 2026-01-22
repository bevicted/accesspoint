const std = @import("std");

fn run(src: []const u8) void {
    const scanner: Scanner = .init(src);
    const tokens = scanner.scan_tokens();

    for (tokens) |token| {
        std.debug.print("{any}", token);
    }
}

fn report_err(line: u16, msg: []const u8) void {
    std.debug.print("config error on line {d}: {s}", line, msg);
}
