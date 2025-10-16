const std = @import("std");
const arm7tdmi = @import("arm7tdmi.zig");
const builtin = @import("builtin");

pub fn did_overflow(comptime T: type, a: T, b: T, result: T) bool {
    const msb = 1 << (@typeInfo(T).int.bits) - 1;
    return ((a ^ b) & (a ^ result)) & msb != 0;
}

pub fn shift(shift_type: u2, val: u32, shift_amnt: u32, carry_in: bool) struct { u32, bool } {
    return switch (shift_type) {
        0 => blk: {
            const result_64 = std.math.shl(u64, val, shift_amnt);
            const carry = if (shift_amnt > 32) false else (result_64 >> 32) != 0;
            break :blk .{ @truncate(result_64), carry and (shift_amnt != 0) };
        },
        1 => blk: {
            var result = std.math.shr(u32, val, shift_amnt);
            var carry = false;

            if (shift_amnt > 32) {
                carry = false;
            } else if (shift_amnt >= 32 or shift_amnt == 0) {
                carry = val >> 31 != 0;
                result = 0;
            } else {
                carry = std.math.shr(u32, val, shift_amnt - 1) & 1 != 0;
            }

            break :blk .{ result, carry };
        },
        2 => blk: {
            // ASR
            var result = @as(u32, @bitCast(std.math.shr(i32, @as(i32, @bitCast(val)), shift_amnt)));
            var carry = false;

            if (shift_amnt >= 32 or shift_amnt == 0) {
                const bit: u1 = @truncate(val >> 31);
                carry = bit != 0;
                result = if (bit == 1) 0xffffffff else 0;
            } else {
                carry = std.math.shr(u32, val, shift_amnt - 1) & 1 != 0;
            }

            break :blk .{ result, carry };
        },
        3 => blk: {
            var amnt: u32 = shift_amnt;

            if (shift_amnt == 0) {
                amnt = 1;
            }
            const result_33 = std.math.rotr(u33, val, amnt);

            var result: u32 = @truncate(result_33 >> 1);

            if (shift_amnt == 0) {
                const mask: u32 = 1 << 31;
                // set bit 31 of result to old carry
                result = (result & ~mask) |
                    (@as(u32, @as(u1, @bitCast(carry_in))) << 31);
            }

            const carry = (result_33 & (1 << 32)) != 0;

            break :blk .{ result, carry };
        },
    };
}

pub inline fn calc_zn_flags(result: u32) struct { bool, bool } {
    return .{ result == 0, result >> 31 != 0 };
}

var logfile: std.fs.File = undefined;

var init_logfile_once = std.once(init_file);

fn init_file() void {
    logfile = std.fs.cwd().createFile("gba.log", .{}) catch |err| {
        std.debug.print("Couldn't open gba.log: {any}\n", .{err});
        return undefined;
    };
}
pub fn print_to_file(comptime format: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        init_logfile_once.call();

        logfile.seekFromEnd(0) catch {};

        logfile.writer().print(format, args) catch |err| {
            std.debug.print("Couldn't open gba.log: {any}\n", .{err});
            return;
        };
    }
}
