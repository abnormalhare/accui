const std = @import("std");

const Global = @import("global");
const CompType = Global.CompType;
const num_to_list = Global.num_to_list;
const list_to_num = Global.list_to_num;

const Motherboard = @import("../../../motherboard.zig");
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;

// ---------------------------------------
// |              Intel 2102             |
// |  1024 Bit Fully Decoded Static MOS  |
// |         Random Access Memory        |
// ---------------------------------------
pub const I2101 = struct {
    ram: [32][32]u1,

    row: u5,
    column: u5,

    data_in: u1,
    data_out: u1,

    read_write: u1,
    chip_enable: u1,
    
    pub fn init(alloc: std.mem.Allocator) !*I2101 {
        const self = try alloc.create(I2101);

        self.ram = [_][16]u1{ [_]u1 { 0 } ** 32 } ** 1024;

        self.read_write = 0;
        self.chip_enable = 0;

        return self;
    }

    pub fn tick(self: *I2101) !void {
        self.read_write  = @truncate(list_to_num(signal_read(.I2101, 3) , 1));
        self.chip_enable = @truncate(list_to_num(signal_read(.I2101, 13), 1));

        if (self.chip_enable == 1) return;

        self.data_in = @truncate(list_to_num(signal_read(.I2101, 11), 1));

        const wiresx = signal_read(.I2101, 4);
        self.row = @truncate(list_to_num(wiresx, 5));
        
        const wiresy = signal_read(.I2101, 1);
        self.column = @truncate(list_to_num(wiresy, 5));
        
        switch (self.read_write) {
            0 => {
                self.data_out = self.ram[self.column][self.row];
                var out: [4]u1 = [_]u1{ 0 };
                signal_write(&out, .I2101, 1);
            },
            1 => {
                self.ram[self.column][self.row] = self.data_in;
            }
        }
    }
};