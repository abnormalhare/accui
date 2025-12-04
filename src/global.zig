const std = @import("std");

pub const Step = enum {
    NORMAL, // no stepping
    INSTR,  // steps every instruction
    TIMING, // steps every timing tick
    PHASE,  // steps every clock phase
};

pub const CompType = enum {
    I1101A,
    I1103,
    I3101,
    I4001,
    I4002,
    I4003,
    I4004,
};

pub fn clear_screen() void {
    std.debug.print("\x1B[H\x1B[2J", .{});
}

pub fn reset_screen() void {
    std.debug.print("\x1B[H", .{});
}

pub fn num_to_list(out: []u1, val: u16, cnt: u5) void {
    for (0..cnt) |sft| {
        const tsft: u4 = @truncate(sft);
        out[sft] = @truncate(val >> tsft);
    }
}

pub fn list_to_num(list: []u1, cnt: u5) u16 {
    var num: u16 = 0;

    for (0..cnt) |sft| {
        num |= @as(u16, list[sft]) << @truncate(sft);
    }

    return num;
}