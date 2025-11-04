const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} --call\n", .{args[0]});
        std.process.exit(1);
    }

    if (std.mem.eql(u8, args[1], "--call")) {
        std.debug.print("{d}\n", .{3});
    } else {
        std.debug.print("Unknown option: {s}\n", .{args[1]});
        std.debug.print("Usage: {s} --call\n", .{args[0]});
        std.process.exit(1);
    }
}
