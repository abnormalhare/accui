const std = @import("std");

const Global = @import("global");
const Step = Global.Step;
const CompType = Global.CompType;
const reset_screen = Global.reset_screen;

const Motherboard = @import("../../../motherboard.zig");
const signal_read_bus  = Motherboard.signal_read_bus;
const signal_write_bus = Motherboard.signal_write_bus;
const signal_cm = Motherboard.signal_cm;
const get_global_clock = Motherboard.get_global_clock;

pub const T = enum(u3) {
    A1, A2, A3,
    M1, M2,
    X1, X2, X3,
};

const SetTime = struct {
    enable: bool,
    timing: T,
    phase: u2,

    pub fn new(timing: T, phase: u2) SetTime {
        const self = SetTime{ .enable = true, .timing = timing, .phase = phase };

        return self;
    }
};

const Conditional = struct {
    is_invert: bool,
    is_accum_zero: bool,
    is_carry: bool,
    is_test: bool,

    fn new(flags: u4) Conditional {
        return Conditional{
            .is_invert = (flags & 0b1000) == 0b1000,
            .is_accum_zero = (flags & 0b0100) == 0b0100,
            .is_carry = (flags & 0b0010) == 0b0010,
            .is_test = (flags & 0b0001) == 0b0001,
        };
    }

    fn set_bool(self: *Conditional, prev: ?bool, next: bool) bool {
        _ = self; // makes code look better

        if (prev == null) {
            return next;
        }

        const nprev = prev.?;
        if (nprev == false) {
            return false;
        }

        return next;
    }

    pub fn pass(self: *Conditional, cpu: *I4004) bool {
        var ret: ?bool = null;

        if (self.is_accum_zero) {
            const check = if (self.is_invert) cpu.accum != 0 else cpu.accum == 0;
            ret = self.set_bool(ret, check);
        }
        if (self.is_carry) {
            const check = if (self.is_invert) cpu.carry == 0 else cpu.carry == 1;
            ret = self.set_bool(ret, check);
        }
        if (self.is_test) {
            const check = if (self.is_invert) cpu.test_pin == 1 else cpu.test_pin == 0;
            ret = self.set_bool(ret, check);
        }

        return ret orelse false;
    }
};

pub const I4004 = struct {
    // External Communication //
    data_bus: u4, // external & internal input
    cm_ram: u4,
    cm_rom: u1,
    cm_time: SetTime,

    // Timing //
    timing: T,
    running: bool,

    // Internal Information //
    clock_phase: u2, // external input
    sync: u1, // external input
    test_pin: u1, // external input
    reset: u1, // external input
    carry: u1,
    two_byte: u1,
    bank: u3,

    // Special States //
    special_fin_mode: bool,

    // Executively Changable Memory //
    stack: [4]u12,
    regs: [16]u4,
    instr: u8,
    itrl_instr: u8,
    accum: u4,
    temp: u4,

    pub fn init(alloc: std.mem.Allocator) !*I4004 {
        const self: *I4004 = try alloc.create(I4004);

        self.zero_values();

        return self;
    }

    pub fn zero_values(self: *I4004) void {
        self.data_bus = 0;
        self.cm_ram = 0;
        self.cm_rom = 0;
        self.cm_time = SetTime{ .enable = false, .timing = T.A1, .phase = 0 };

        self.timing = T.A1;
        self.bank = 0;
        self.running = true;

        self.clock_phase = 0;
        self.sync = 0;
        self.test_pin = 0;
        self.reset = 1;
        self.carry = 0;
        self.two_byte = 0;

        self.special_fin_mode = false;

        self.stack = [_]u12{0} ** 4;
        self.regs =  [_]u4 {0} ** 16;
        self.instr = 0;
        self.itrl_instr = 0;
        self.accum = 0;
        self.temp = 0;
    }

    pub fn debug_print(self: *I4004, alloc: std.mem.Allocator, step_type: Step) ![]u8 {
        var list = try std.ArrayList(u8).initCapacity(alloc, 0x2000);
        defer list.deinit(alloc);
        
        const writer = list.writer(alloc);
        
        try writer.print("| DATA:  0x{X:0>2} |   ROM 0x{X:0>3}   | STACK: 0x{X:0>3} 0x{X:0>3} 0x{X:0>3}  |\n", .{
            self.instr,
            @as(u16, self.stack[0]),
            self.stack[1], self.stack[2], self.stack[3]
        });

        const name: []const u8 = std.enums.tagName(T, self.timing).?;
        try writer.print("| TIMING: {s}  |", .{ name });
        if (step_type == Step.PHASE) {
            const phase_name = switch (self.clock_phase) {
                0 => "P1^",
                1 => "P1v",
                2 => "P2^",
                3 => "P2v",
            };
            try writer.print(" SUBCYCLE: {s} | CURR INSTR: {X:0>2}            |\n", .{ phase_name, self.itrl_instr });
        } else {
            try writer.print("               | CURR INSTR: {X:0>2}            |\n", .{ self.itrl_instr });
        }

        try writer.print("|---------------------------------------------------------|\n", .{});
        try writer.print("| REGS |  A: 0x{X:0>1}  C: {b}  |    CMROM: {b:0>1}    |   CMRAM: {b:0>4}  |\n", .{
            self.accum,
            self.carry,
            self.cm_rom,
            self.cm_ram
        });
        try writer.print("|---------------------------------------------------------|\n", .{});
        try writer.print("| 0x{X:0>1} 0x{X:0>1} 0x{X:0>1} 0x{X:0>1}                                         |\n", .{ self.regs[0],  self.regs[1],  self.regs[2],  self.regs[3]  });
        try writer.print("| 0x{X:0>1} 0x{X:0>1} 0x{X:0>1} 0x{X:0>1}                                         |\n", .{ self.regs[4],  self.regs[5],  self.regs[6],  self.regs[7]  });
        try writer.print("| 0x{X:0>1} 0x{X:0>1} 0x{X:0>1} 0x{X:0>1}                                         |\n", .{ self.regs[8],  self.regs[9],  self.regs[10], self.regs[11] });
        try writer.print("| 0x{X:0>1} 0x{X:0>1} 0x{X:0>1} 0x{X:0>1}                                         |\n", .{ self.regs[12], self.regs[13], self.regs[14], self.regs[15] });

        const ret: []u8 = try alloc.alloc(u8, list.items.len);

        @memcpy(ret, list.items);
        return ret;
    }

    fn get_instr_type(self: *I4004) u4 {
        return @intCast((self.itrl_instr & 0xF0) >> 4);
    }

    fn flip_two_byte(self: *I4004) bool {
        self.two_byte = ~self.two_byte;
        return self.two_byte == 1;
    }

    fn set_cm_rom_out(self: *I4004, end: SetTime) void {
        self.cm_time = end;

        self.cm_rom = 1;
        self.cm_ram = self.get_cm_ram();

        signal_cm();
    }

    fn get_cm_ram(self: *I4004) u4 {
        return switch (self.bank) {
            0 => 0b0001,
            else => @as(u4, self.bank) * 2,
        };
    }

    fn decimal_adjust(self: *I4004) void {
        if (self.carry == 1 or self.accum > 9) {
            self.temp = 6;
            self.add_accum();
        }
    }

    fn add_accum(self: *I4004) void {
        var carry: u1 = 0;
        self.accum, carry = @addWithOverflow(self.accum, self.temp);
        self.carry |= carry;
    }

    fn sub_accum(self: *I4004) void {
        var carry: u1 = 0;
        self.accum, carry = @subWithOverflow(self.accum, self.temp);

        if (carry == 1) self.carry = 0;
    }

    fn instr_decoder(self: *I4004) void {
        if ((self.itrl_instr & 0xF0) != 0xE0) {
            if (self.clock_phase != 1) return; // maybe we'll actually implement this, but not today
        }

        switch (self.get_instr_type()) {
            // NOP
            0x0 => {},

            // JCN
            0x1 => {
                if (self.flip_two_byte() or self.timing != T.X1) return;

                const cond_flags: u4 = @intCast(self.itrl_instr & 0x0F);
                var conditions = Conditional.new(cond_flags);
                const jump_val: u8 = self.instr;
                if (conditions.pass(self)) {
                    self.stack[0] &= 0xF00;
                    self.stack[0] |= jump_val;
                }
            },

            0x2 => {
                const reg: u4 = @truncate((self.instr >> 1) << 1);

                if ((self.itrl_instr & 1) == 0) { // FIM
                    if (self.flip_two_byte() or self.timing != T.X1) return;

                    self.regs[reg + 0] = @truncate(self.instr >> 4);
                    self.regs[reg + 1] = @truncate(self.instr >> 0);
                } else { // SRC
                    if (self.timing == T.X2) {
                        self.set_cm_rom_out(SetTime.new(T.X3, 0));
                    }
                    switch (self.timing) {
                        else => {},
                        T.X2 => self.data_bus = self.regs[reg + 0],
                        T.X3 => self.data_bus = self.regs[reg + 1],
                    }

                    signal_write_bus(self.data_bus);
                }
            },

            0x3 => {
                const reg = (self.instr >> 1) << 1;

                if ((self.itrl_instr & 1) == 0) { // FIN
                    self.special_fin_mode = true;

                    if (self.flip_two_byte() or self.timing != T.X1) return;

                    self.regs[reg + 0] = @truncate(self.instr >> 4);
                    self.regs[reg + 1] = @truncate(self.instr);
                } else { // JIN
                    if (self.timing != T.X1) return;

                    self.stack[0] &= 0xF00;
                    self.stack[0] |= @as(u12, self.regs[reg + 0]) << 4;
                    self.stack[0] |= @as(u12, self.regs[reg + 1]) << 0;
                }
            },

            0x4 => { // JUN
                if (self.flip_two_byte() or self.timing != T.X1) return;

                self.stack[0] &= 0xF00;
                self.stack[0] |= @as(u12, self.itrl_instr & 0x0F) << 8;
                self.stack[0] |= @as(u12, self.instr);
            },

            0x5 => { // JMS
                if (self.flip_two_byte() or self.timing != T.X1) return;

                self.stack[3] = self.stack[2];
                self.stack[2] = self.stack[1];
                self.stack[1] = self.stack[0];

                self.stack[0] &= 0xF00;
                self.stack[0] |= @as(u12, self.itrl_instr & 0x0F) << 8;
                self.stack[0] |= @as(u12, self.instr);
            },

            0x6 => { // INC
                if (self.timing != T.X1) return;

                var carry: u1 = 0;
                self.regs[self.instr & 0x0F], carry = @addWithOverflow(self.regs[self.instr & 0x0F], 1);
                self.carry |= carry;
            },

            0x7 => { // ISZ
                if (self.flip_two_byte() or self.timing != T.X1) return;

                var carry: u1 = 0;
                self.regs[self.itrl_instr & 0x0F], carry = @addWithOverflow(self.regs[self.itrl_instr & 0x0F], 1);
                self.carry |= carry;

                if (self.regs[self.itrl_instr & 0x0F] != 0) {
                    self.stack[0] &= 0xF00;
                    self.stack[0] |= @intCast(self.instr);
                }
            },

            0x8 => { // ADD
                if (self.timing != T.X1) return;

                self.temp = self.regs[self.instr & 0x0F];
                self.add_accum();
            },

            0x9 => { // SUB
                if (self.timing != T.X1) return;

                self.temp = self.regs[self.instr & 0x0F];
                self.sub_accum();
            },

            0xA => { // LD
                if (self.timing != T.X1) return;

                self.accum = self.regs[self.instr & 0x0F];
            },

            0xB => { // XCH
                if (self.timing != T.X1) return;

                self.temp = self.accum;
                self.accum = self.regs[self.instr & 0x0F];
                self.regs[self.instr & 0x0F] = self.temp;
            },

            0xC => { // BBL
                if (self.timing != T.X1) return;

                self.stack[0] = self.stack[1];
                self.stack[1] = self.stack[2];
                self.stack[2] = self.stack[3];

                self.accum = @truncate(self.instr);
            },

            0xD => { // LDM
                if (self.timing != T.X1) return;

                self.accum = @truncate(self.instr);
            },

            0xE => { // Write/Read IO
                if (self.timing == T.X2 and self.clock_phase == 1) {
                    self.data_bus = self.accum;
                    signal_write_bus(self.data_bus);
                }
                if (self.timing == T.X3 and self.clock_phase == 2) {
                    switch (self.instr & 0x0F) {
                        // WR(M,R,0,1,2,3), WMP, WPM
                        else => {},

                        // RD(M,R,0,1,2,3)
                        9...10, 12...15 => self.accum = self.data_bus,

                        // SBM
                        8  => { self.temp = self.data_bus; self.sub_accum(); },
                        // ADM
                        11 => { self.temp = self.data_bus; self.add_accum(); },
                    }
                }
            },

            0xF => {
                if (self.timing != T.X1) return;

                switch (self.instr & 0x0F) {
                    else => {},

                    0 => { self.carry = 0; self.accum = 0; },   // CLB
                    1 => self.carry = 0,                        // CLC
                    2 => { self.temp = 1; self.add_accum(); },  // IAC
                    3 => self.carry = ~self.carry,              // CMC
                    4 => self.accum = ~self.accum,              // CMA
                    5 => {                                      // RAL
                        var carry: u1 = 0;
                        self.accum, carry = @shlWithOverflow(self.accum, 1);
                        self.accum |= carry;
                    },
                    6 => {                                      // RAR
                        const carry: u4 = self.accum & 1;
                        self.accum >>= 1;
                        self.accum |= carry << 3;
                    },
                    7 => {                                      // TCC
                        self.accum = @intCast(self.carry); 
                        self.carry = 0;
                    },
                    8 => { self.temp = 1; self.sub_accum(); },  // DAC
                    9 => {                                      // TCS
                        self.accum = 9 + @as(u4, self.carry); 
                        self.carry = 0;
                    },
                    10 => self.carry = 1,                       // STC
                    11 => self.decimal_adjust(),                // DAA
                    12 => {                                     // KBP
                        switch (self.accum) {
                            else => self.accum = 15,

                            0b0001 => self.accum = 1,
                            0b0010 => self.accum = 2,
                            0b0100 => self.accum = 3,
                            0b1000 => self.accum = 4,
                        }
                    },
                    13 => {                                     // DCL
                        self.bank = @intCast(self.accum & 0x7);
                    },
                    14...15 => {},
                }
            }
        }
    }

    fn inc_timing(self: *I4004) void {
        const t_int: u3 = @intCast(@intFromEnum(self.timing));
        const t_inc: u3, _ = @addWithOverflow(t_int, 1);
        self.timing = @enumFromInt(t_inc);
    }

    fn tick_timing(self: *I4004) void {
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

    fn send_stack_to_buffer(self: *I4004) void {
        if (self.timing == T.A3 and self.clock_phase == 2) {
            self.set_cm_rom_out(SetTime.new(T.M1, 0));
        }

        if (self.clock_phase != 1) return;

        if (self.special_fin_mode) {
            switch (self.timing) {
                else => {},
                T.A1 => self.data_bus = @intCast((self.stack[0] & 0xF00) >> 8),
                T.A2 => self.data_bus = @intCast(self.regs[(self.itrl_instr + 0) & 0x0F]),
                T.A3 => self.data_bus = @intCast(self.regs[(self.itrl_instr + 1) & 0x0F]),
            }
            return;
        }

        switch (self.timing) {
            else => {},
            T.A1 => self.data_bus = @intCast((self.stack[0] & 0x00F) >> 0),
            T.A2 => self.data_bus = @intCast((self.stack[0] & 0x0F0) >> 4),
            T.A3 => self.data_bus = @intCast((self.stack[0] & 0xF00) >> 8),
        }

        signal_write_bus(self.data_bus);
    }

    fn recv_instr_from_buffer(self: *I4004) void {
        if ((self.instr & 0xF0) == 0xE0 and self.timing == T.M2 and self.clock_phase == 0) {
            self.set_cm_rom_out(SetTime.new(T.X1, 0));
        }

        if (self.clock_phase != 2) return;

        self.data_bus = signal_read_bus();

        switch (self.timing) {
            else => {},
            T.M1 => { self.instr &= 0x0F; self.instr |= @as(u8, self.data_bus) << 4; },
            T.M2 => { self.instr &= 0xF0; self.instr |= @as(u8, self.data_bus) << 0; },
        }

        if (self.timing == T.M2 and self.two_byte == 0) {
            self.itrl_instr = self.instr;
        }
    }

    pub fn tick(self: *I4004) void {
        self.tick_timing();

        if (self.reset == 1) {
            self.zero_values();
            return;
        }

        switch (self.timing) {
            T.A1, T.A2, T.A3 => self.send_stack_to_buffer(),
            T.M1, T.M2       => self.recv_instr_from_buffer(),
            T.X1, T.X2, T.X3 => self.instr_decoder(),
        }

        if (self.timing == T.M2 and self.clock_phase == 0) {
            self.stack[0], _ = @addWithOverflow(self.stack[0], 1);
        }

        if (self.cm_time.enable and self.cm_time.timing == self.timing and self.cm_time.phase == self.clock_phase) {
            self.cm_rom = 0;
            self.cm_ram = 0;
            signal_cm();
            self.cm_time.enable = false;
        }
    }
};
