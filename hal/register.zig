const std = @import("std");

pub fn Register(comptime T: type) type {
    return struct {
        const Self = @This();
        address: usize,

        pub inline fn read(self: Self) T {
            return @as(*volatile T, @ptrFromInt(self.address)).*;
        }

        pub inline fn write(self: Self, value: T) void {
            @as(*volatile T, @ptrFromInt(self.address)).* = value;
        }

        pub inline fn modify(self: Self, fields: anytype) void {
            var value = self.read();
            inline for (std.meta.fields(@TypeOf(fields))) |f| {
                @field(value, f.name) = @field(fields, f.name);
            }
            self.write(value);
        }
    };
}
