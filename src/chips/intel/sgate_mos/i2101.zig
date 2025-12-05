const std = @import("std");

const Global = @import("global");
const CompType = Global.CompType;
const num_to_list = Global.num_to_list;
const list_to_num = Global.list_to_num;

const Motherboard = @import("../../../motherboard.zig");
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;

// ---------------------------------------
// |             Intel 2101              |
// |    1024 Bit Static MOS RAM with     |
// |            Separate I/O             |
// ---------------------------------------
pub const I2101 = struct {
    ram: [8][32]u4,
    data_input: u4,

    row: u5,
    column: u3,

    read_write: u1,
    chip_select: u2,
    output_disable: u1,

    pub fn init(alloc: std.mem.Allocator) !*I2101 {
        const self = try alloc.create(I2101);

        self.ram = [_][16]u1{ [_]u1 { 0 } ** 16 } ** 256;

        self.row = 0;
        self.column = 0;

        self.read_write = 0;
        self.chip_select = 0;
        self.output_disable = 0;

        return self;
    }

    pub fn tick(self: *I2101) void {
        self.read_write     = @truncate(list_to_num(signal_read(.I2101, 20), 1));
        self.chip_select    = @truncate(list_to_num(signal_read(.I2101, 17), 2));
        self.output_disable = @truncate(list_to_num(signal_read(.I2101, 18), 1));

        self.row    = @truncate(list_to_num(signal_read(.I2101, 1), 5));
        self.column = @truncate(list_to_num(signal_read(.I2101, 5), 3));
        
        if (self.chip_select != 2) return;

        self.data_input = @truncate(list_to_num(signal_read(.I2101, 9), 4));

        if (self.read_write == 1) {
            self.ram[self.column][self.row] = self.data_input;
        }

        const data_output: u4 = self.ram[self.column][self.row];
                
        if (self.output_disable == 0) return;

        const out: [4]u1 = [_]u1{ 0 } ** 4;
        num_to_list(out, data_output, 4);
        signal_write(out, .I2101, 10);
    }
};