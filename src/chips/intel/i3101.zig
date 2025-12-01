const std = @import("std");

const Motherboard = @import("../../motherboard.zig");
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;

pub const I3101 = struct {
    ram: [16]u4,

    addr: u4,
    data_in: u4,
    data_out: u4,

    write_enable: u1,
    chip_select: u1,

    pub fn init(alloc: std.mem.Allocator) !*I3101 {
        const self = try alloc.create(I3101);

        self.addr = 0;
        self.data_in = 0;
        self.data_out = 0;
        self.write_enable = 0;
        self.chip_select = 0;

        return self;
    }

    pub fn tick(self: *I3101) void {
        self.data_in = signal_read();

        if (self.chip_select == 1) {
            self.data_out = self.ram[self.addr];
        }

        if (self.write_enable == 1) {
            self.ram[self.addr] = self.data_in;
        }
    }
};