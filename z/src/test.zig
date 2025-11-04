const std = @import("std");
const testing = std.testing;

test "1 + 2 equals 3" {
    try testing.expectEqual(@as(c_int, 3), 1 + 2);
}
