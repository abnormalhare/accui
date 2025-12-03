const std = @import("std");

const Global = @import("global");
const CompType = Global.CompType;
const num_to_list = Global.num_to_list;
const list_to_num = Global.list_to_num;

const Motherboard = @import("../../motherboard.zig");
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;

pub const I1101 = struct {
    ram: [16][16]u1,

    xreg: u4,
    yreg: u4,

    data_in: u1,
    data_out: u1,
    inv_data_out: u1,

    read_write: u1,
    chip_select: u1,

    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !*I1101 {
        const self = try alloc.create(I1101);

        self.ram = [_][16]u1{ [_]u1 { 0 } ** 16 } ** 256;

        self.xreg = 0;
        self.yreg = 0;

        self.data_in = 0;
        self.data_out = 0;
        self.inv_data_out = 0;

        self.read_write = 0;
        self.chip_select = 0;

        self.alloc = alloc;

        return self;
    }

    pub fn tick(self: *I1101) void {

        switch (self.read_write) {
            // read
            0 => {
                if (self.chip_select == 1) return;

                self.data_out = self.ram[self.yreg][self.xreg];
                self.inv_data_out = !self.data_out;

                const out1: [1]u1 = [_]u1{ self.data_out };
                const out2: [1]u1 = [_]u1{ self.inv_data_out };

                signal_write(out1, .I1101A, 13);
                signal_write(out2, .I1101A, 14);
            },
            // write
            1 => {
                const wires = signal_read(.I1101A, 12);
                self.data_in = list_to_num(wires, 1);
                
                self.ram[self.yreg][self.xreg] = self.data_in;
            }
        }
    }
};