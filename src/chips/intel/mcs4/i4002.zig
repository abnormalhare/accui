const std = @import("std");

const Global = @import("global");
const Step = Global.Step;
const CompType = Global.CompType;
const num_to_list = Global.num_to_list;
const list_to_num = Global.list_to_num;

const Motherboard = @import("../../../motherboard.zig");
const signal_read_bus  = Motherboard.signal_read_bus;
const signal_write_bus = Motherboard.signal_write_bus;
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;
const get_global_clock = Motherboard.get_global_clock;

const T = enum(u3) {
    A1, A2, A3,
    M1, M2,
    X1, X2, X3,
};

const Reg = struct {
    data: [16]u4,
    stat:  [4]u4,
};

pub const I4002 = struct {
    // Main Information //
    ram: [4]Reg,
    chip_num: u2,

    // Timing //
    timing: T,

    // External Communication //
    data_bus: u4,
    io: u4,

    // Internal Information //
    clock_phase: u2, // ext
    sync: u1, // ext
    cm_ram: u1, // ext
    reset: u1, // ext

    // Register Information //
    xreg: u4,
    yreg: u2,

    // IO Control //
    instr: u4,
    src: u1,
    io_op: u1,

    pub fn init(alloc: std.mem.Allocator, chip_num: u2) !*I4002 {
        const self = try alloc.create(I4002);

        self.chip_num = chip_num;

        self.zero_values();

        return self;
    }

    fn zero_values(self: *I4002) void {
        self.ram = [_]Reg{ Reg{ .data = [_]u4{ 0 } ** 16, .stat = [_]u4{ 0 } ** 4 } } ** 4;
        
        self.timing = T.A1;

        self.data_bus = 0;
        self.io = 0;

        self.clock_phase = 0;
        self.sync = 0;
        self.cm_ram = 0;
        self.reset = 1;

        self.xreg = 0;
        self.yreg = 0;

        self.instr = 0;
        self.src = 0;
        self.io_op = 0;
    }

    pub fn debug_print(self: *I4002, alloc: std.mem.Allocator) ![]u8 {
        var list = try std.ArrayList(u8).initCapacity(alloc, 0x2000);
        defer list.deinit(alloc);
        
        const writer = list.writer(alloc);
        
        try writer.print("| STAT   |       {X:0>1}{X:0>1}{X:0>1}{X:0>1}    {X:0>1}{X:0>1}{X:0>1}{X:0>1}    {X:0>1}{X:0>1}{X:0>1}{X:0>1}    {X:0>1}{X:0>1}{X:0>1}{X:0>1}             |\n", .{
            self.ram[0].stat[0], self.ram[0].stat[1], self.ram[0].stat[2], self.ram[0].stat[3],
            self.ram[1].stat[0], self.ram[1].stat[1], self.ram[1].stat[2], self.ram[1].stat[3],
            self.ram[2].stat[0], self.ram[2].stat[1], self.ram[2].stat[2], self.ram[2].stat[3],
            self.ram[3].stat[0], self.ram[3].stat[1], self.ram[3].stat[2], self.ram[3].stat[3],
        });
        try writer.print("---------|                                                |\n", .{});

        for (0..4) |i| {
            for (self.ram, 0..) |reg, j| {
                if (j == 0) {
                    try writer.print("| DATA {d} |       ", .{ i });
                }

                try writer.print("{X:0>1}{X:0>1}{X:0>1}{X:0>1}    ", .{
                    reg.data[i * 4 + 0], reg.data[i * 4 + 1], reg.data[i * 4 + 2], reg.data[i * 4 + 3]
                });

                if (j == 3) {
                    try writer.print("         |\n", .{});
                }
            }
        }

        const ret: []u8 = try alloc.alloc(u8, list.items.len);

        @memcpy(ret, list.items);
        return ret;
    }

    fn check_io(self: *I4002) void {
        if (self.clock_phase != 1 or self.src == 0) return;

        self.io_op = self.cm_ram;

        if (self.io_op == 1) {
            self.data_bus = signal_read_bus();
        }
    }

    fn reset_io(self: *I4002) void {
        self.io_op = 0;
        self.src = 0;
    }

    fn execute_io_command(self: *I4002) void {
        if (self.timing == T.X1 and self.clock_phase == 2) {
            self.instr = self.data_bus;
            return;
        }

        if (self.timing != T.X2) return;

        self.data_bus = signal_read_bus();

        switch (self.instr) {
            else => {},
            // WRM
            0x0 => {
                if (self.clock_phase != 2) return;

                self.ram[self.yreg].data[self.xreg] = self.data_bus;
                self.reset_io();
            },
            // WMP
            0x1 => {
                if (self.clock_phase != 2) return;

                self.io = self.data_bus;

                var out: [4]u1 = [_]u1{ 0 } ** 4;
                num_to_list(&out, self.io, 4);
                signal_write(&out, .I4002, 13);

                self.reset_io();
            },
            // WR(0-3)
            0x4...0x7 => {
                if (self.clock_phase != 2) return;

                self.ram[self.yreg].stat[self.instr & 3] = self.data_bus;
                self.reset_io();
            },
            // SBM, RDM, ADM
            0x8...0x9, 0xB => {
                if (self.clock_phase != 1) return;

                signal_write_bus(self.ram[self.yreg].data[self.xreg]);
                self.reset_io();
            },
            // RDR
            0xA => {
                if (self.clock_phase != 1) return;
                
                signal_write_bus(self.io);
                self.reset_io();
            },
            // RD(0-3)
            0xC...0xF => {
                if (self.clock_phase != 1) return;

                signal_write_bus(self.ram[self.yreg].stat[self.instr & 3]);
                self.reset_io();
            }
        }

    }

    fn check_src(self: *I4002) void {
        if (self.clock_phase != 2) return;

        self.data_bus = signal_read_bus();
        const chip_num: u2 = @truncate(self.data_bus >> 2);

        switch (self.timing) {
            else => {},
            T.X2 => {
                self.src = @intFromBool(self.chip_num == chip_num and self.cm_ram == 1);
                if (self.src == 0) return;

                self.yreg = @truncate(self.data_bus);
            },
            T.X3 => {
                if (self.src == 0) return;

                self.xreg = self.data_bus;
            }
        }
    }

    fn interpret_command(self: *I4002) void {
        if (self.io_op == 1) {
            self.execute_io_command();
        } else {
            self.check_src();
        }
    }

    fn inc_timing(self: *I4002) void {
        const t_int: u3 = @intCast(@intFromEnum(self.timing));
        const t_inc: u3, _ = @addWithOverflow(t_int, 1);
        self.timing = @enumFromInt(t_inc);
    }

    fn tick_timing(self: *I4002) void {
        self.clock_phase = get_global_clock();
        
        if (self.sync == 1) {
            self.timing = T.X3;
            return;
        }

        if (self.clock_phase == 0) {
            self.inc_timing();
            return;
        }
    }

    pub fn tick(self: *I4002) void {
        self.tick_timing();

        if (self.reset == 1) {
            self.zero_values();
            return;
        }

        switch (self.timing) {
            else => {},
            T.M2 => self.check_io(),
            T.X1, T.X2, T.X3 => self.interpret_command(),
        }
    }
};