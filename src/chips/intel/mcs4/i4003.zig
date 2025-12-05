const std = @import("std");

const Global = @import("global");
const CompType = Global.CompType;
const num_to_list = Global.num_to_list;
const list_to_num = Global.list_to_num;

const Motherboard = @import("../../../motherboard.zig");
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;

// ---------------------------------------
// |              Intel 4003             |
// |    10-Bit Serial-In Parallel-Out    |
// |      Serial-Out Shift Register      |
// ---------------------------------------
pub const I4003 = struct {
    // Main Information //
    shift: u10,
    data_out: u10,

    // External Communication //
    data_in: u1, // ext
    serial_out: u1,
    clock: u1, // ext
    enable: u1, // ext

    // Internal Information //
    power_on: u1,
    was_clocked: u1,

    pub fn init(alloc: std.mem.Allocator) !*I4003 {
        const self = try alloc.create(I4003);

        self.zero_values();

        return self;
    }

    fn zero_values(self: *I4003) void {
        self.shift = 0;
        self.data_out = 0;

        self.data_in = 0;
        self.serial_out = 0;
        self.clock = 0;
        self.enable = 0;

        self.power_on = 0;
    }

    pub fn tick(self: *I4003) void {
        self.clock   = @truncate(list_to_num(signal_read(.I4003, 1) , 1));
        self.data_in = @truncate(list_to_num(signal_read(.I4003, 2) , 1));
        self.enable  = @truncate(list_to_num(signal_read(.I4003, 16), 1));

        if (self.enable == 1) {
            self.data_out = self.shift;

            var out: [10]u1 = [_]u1{ 0 } ** 10;
            num_to_list(&out, self.data_out, 10);
            signal_write(&out, .I4003, 3);
        }

        if (self.was_clocked == 0) {
            self.serial_out = @truncate(self.shift);
            self.shift >> 1;
            self.shift = @as(u10, self.data_in) << 9;
        }

        self.was_clocked = self.clock;

        var out: [1]u1 = [_]u1{ self.serial_out };
        signal_write(&out, .I4003, 15);
    }
};