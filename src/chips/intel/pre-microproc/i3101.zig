const std = @import("std");

const Global = @import("global");
const CompType = Global.CompType;
const num_to_list = Global.num_to_list;
const list_to_num = Global.list_to_num;

const Motherboard = @import("../../../motherboard.zig");
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;

pub const I3101 = struct {
    ram: [16]u4,

    write_enable: u1,
    chip_select: u1,

    pub fn init(alloc: std.mem.Allocator) !*I3101 {
        const self = try alloc.create(I3101);

        self.ram = [_]u4{ 0 } ** 16;
        
        self.write_enable = 0;
        self.chip_select = 0;

        return self;
    }

    pub fn tick(self: *I3101) !void {
        self.write_enable = @truncate(list_to_num(signal_read(.I3101, 3), 1));
        self.chip_select  = @truncate(list_to_num(signal_read(.I3101, 2), 1));

        if (self.chip_select == 0) {
            const wires = signal_read(.I3101, 1);
            const addr: u4 = @truncate(list_to_num(wires, 4));

            var out: [4]u1 = [_]u1{ 0 } ** 4;
            num_to_list(&out, self.ram[addr], 4);
            signal_write(&out, .I3101, 5);
        }

        if (self.write_enable == 1) {
            const wires = signal_read(.I3101, 6);
            self.ram[self.addr] = @truncate(list_to_num(wires, 4));
        }
    }
};