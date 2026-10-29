const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) std.process.exit(64);
    const count = std.fmt.parseInt(u64, args[1], 10) catch std.process.exit(65);

    var sum: u32 = 0;
    var i = count;
    while (i > 0) : (i -= 1) {
        sum +%= @truncate(i);
    }
    std.process.exit(@intCast(sum & 255));
}
