const std = @import("std");

const Global = @import("global");
const CompType = Global.CompType;
const num_to_list = Global.num_to_list;
const list_to_num = Global.list_to_num;

const Motherboard = @import("../../../motherboard.zig");
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;

pub const I1103 = struct {
    ram: [32][32]u1,

    read_write: u1,
    chip_enable: u1,
    

    pub fn init(alloc: std.mem.Allocator) !*I1103 {
        const self = try alloc.create(I1103);

        self.ram = [_][16]u1{ [_]u1 { 0 } ** 32 } ** 1024;

        self.read_write = 0;
        self.chip_enable = 0;

        return self;
    }

    pub fn tick(self: *I1103) !void {
        self.read_write  = @truncate(list_to_num(signal_read(.I1103, 18), 1));
        self.chip_enable = @truncate(list_to_num(signal_read(.I1103, 16), 1));

        if (self.chip_enable == 0) return;

        const wiresx = signal_read(.I1103, 1);
        const xreg: u5 = @truncate(list_to_num(wiresx, 5));
        
        const wiresy = signal_read(.I1103, 6);
        const yreg: u5 = @truncate(list_to_num(wiresy, 5));
        
        switch (self.read_write) {
            0 => {
                var out: [4]u1 = [_]u1{ ~self.ram[yreg][xreg] };
                signal_write(&out, .I1103, 1);
            },
            1 => {
                const wires = signal_read(.I1103, 12);
                self.ram[yreg][xreg] = @truncate(list_to_num(wires, 1));
            }
        }
    }
};