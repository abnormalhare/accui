const std = @import("std");

pub const Step = enum {
    NORMAL, // no stepping
    INSTR,  // steps every instruction
    TIMING, // steps every timing tick
    PHASE,  // steps every clock phase
};

pub const CompType = enum {
    CPU,
    ROM,
    RAM,
};

pub fn clear_screen() void {
    std.debug.print("\x1B[H\x1B[2J", .{});
}

pub fn reset_screen() void {
    std.debug.print("\x1B[H", .{});
}