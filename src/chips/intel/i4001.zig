const std = @import("std");

const Global = @import("global");
const Step = Global.Step;

const Motherboard = @import("../../motherboard.zig");
const signal_read  = Motherboard.signal_read;
const signal_write = Motherboard.signal_write;
const get_global_clock = Motherboard.get_global_clock;

const T = enum(u3) {
    A1, A2, A3,
    M1, M2,
    X1, X2, X3,
};

pub const I4001 = struct {
    // Static Data //
    rom: [0x100]u8,
    chip_num: u4,

    // Timing //
    timing: T,

    // External Communication //
    data_in:  u4, // ext
    data_out: u4,
    io_bus:   u4, // ext & itrl

    // Internal Information //
    clock_phase: u2, // ext
    sync:     u1, // ext
    cm_rom:   u1, // ext
    clear:    u1, // ext
    reset:    u1, // ext

    // Executively Changable Memory //
    addr: u8,

    // IO Control //
    cse: u1,
    src: u1,
    io_op: u1,

    pub fn init(alloc: std.mem.Allocator, chip_num: u4, rom: *const [0x100]u8) !*I4001 {
        const self = try alloc.create(I4001);

        self.chip_num = chip_num;
        self.rom = rom.*;

        self.zero_values();
        
        return self;
    }

    fn zero_values(self: *I4001) void {
        self.timing = T.A1;

        self.data_in = 0;
        self.data_out = 0;
        self.io_bus = 0;

        self.clock_phase = 0;
        self.sync = 0;
        self.cm_rom = 0;
        self.clear = 0;
        self.reset = 1;
        
        self.cse = 0;
    }

    fn check_chip_num(self: *I4001) void {
        if (self.clock_phase != 2) return;

        self.data_in = signal_read();

        self.cse = @intFromBool(self.data_in == self.chip_num);
    }

    fn recv_stack_from_buffer(self: *I4001) void {
        if (self.clock_phase != 2) return;
        
        self.data_in = signal_read();

        switch (self.timing) {
            else => {},
            T.A1 => { self.addr &= 0xF0; self.addr |= @as(u8, self.data_in) << 0; },
            T.A2 => { self.addr &= 0x0F; self.addr |= @as(u8, self.data_in) << 4; }, 
        }
    }

    fn send_instr_to_buffer(self: *I4001) void {
        if (self.clock_phase != 1 or self.cse == 0) return;

        switch (self.timing) {
            else => {},
            T.M1 => self.data_out = @truncate(self.rom[self.addr] >> 4),
            T.M2 => self.data_out = @truncate(self.rom[self.addr] >> 0),
        }

        signal_write(self.data_out);

        if (self.timing == T.M2) {
            self.io_op = self.cm_rom;
            if (self.io_op == 1) {
                self.data_in = signal_read();
            }
        }
    }

    fn check_src(self: *I4001) void {
        if (self.clock_phase != 2 or self.cse == 0 or self.cm_rom == 0) return;

        self.data_in = signal_read();

        switch (self.timing) {
            else => {},
            T.X2 => self.src = @intFromBool(self.data_in == self.chip_num),
        }
    }

    fn execute_io_command(self: *I4001) void {
        if (self.timing != T.X2 or self.src == 0) return;

        switch (self.data_in) {
            else => {},
            // WRR
            0x2 => {
                if (self.clock_phase != 2) return;

                self.io_bus = signal_read();
            },
            // RDR
            0xA => {
                if (self.clock_phase != 1) return;
                
                signal_write(self.io_bus);
            },
        }

        self.io_op = 0;
    }

    fn interpret_command(self: *I4001) void {
        if (self.io_op == 1) {
            self.execute_io_command();
        } else {
            self.check_src();
        }
    }

    fn inc_timing(self: *I4001) void {
        const t_int: u3 = @intCast(@intFromEnum(self.timing));
        const t_inc: u3, _ = @addWithOverflow(t_int, 1);
        self.timing = @enumFromInt(t_inc);
    }

    fn tick_timing(self: *I4001) void {
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

    pub fn tick(self: *I4001) void {
        self.tick_timing();

        if (self.reset == 1) {
            self.zero_values();
            return;
        }

        switch (self.timing) {
            T.A1, T.A2       => self.recv_stack_from_buffer(),
            T.A3             => self.check_chip_num(),
            T.M1, T.M2       => self.send_instr_to_buffer(),
            T.X1, T.X2, T.X3 => self.interpret_command(),
        }
    }
};