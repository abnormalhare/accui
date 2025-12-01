const std = @import("std");

const Step = @import("global").Step;
const clear_screen = @import("global").clear_screen;

const I4001 = @import("chips/intel/i4001.zig").I4001;
const I4002 = @import("chips/intel/i4002.zig").I4002;
const I4004 = @import("chips/intel/i4004.zig").I4004;
const T = @import("chips/intel/i4004.zig").T;

const SECOND = 1_000_000_000;

var step_type: Step = Step.NORMAL;
var pause: bool = false;

var cpu: *I4004 = undefined;
var roms: [16]*I4001 = undefined;
var rams: [16]*I4001 = undefined;

var main_thread: std.Thread = undefined;
var main_thread_ended: bool = false;

var debug_thread: std.Thread = undefined;
var debug_thread_ended: bool = false;

pub fn init(alloc: std.mem.Allocator, filename: []const u8, def_step_type: Step, def_pause: bool) !void {
    cpu = try I4004.init(alloc);
    errdefer alloc.destroy(cpu);

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const stat = try file.stat();
    const size = stat.size;

    var verification: [3]u8 = [_]u8{ 0 } ** 3;
    _ = try file.read(&verification);
    if (!std.mem.eql(u8, &verification, "i44")) return;

    try file.seekTo(0x10);
    
    for (&roms, 0..) |*rom, idx| {
        var read_rom: [0x100]u8 = [_]u8{ 0 } ** 0x100;

        if (idx * 0x100 > size) {
            rom.* = try I4001.init(alloc, @intCast(idx), &read_rom);
            continue;
        }

        _ = try file.read(&read_rom);
        
        rom.* = try I4001.init(alloc, @intCast(idx), &read_rom);
    }
    errdefer for (&roms) |*rom| { alloc.destroy(rom.*); };

    for (&rams, 0..) |*ram, idx| {
        ram.* = try I4002.init(alloc, idx & 3);
    }

    step_type = def_step_type;
    pause = def_pause;
}

fn reset_reset() void {
    cpu.reset = 0;
    for (&roms) |rom| {
        rom.reset = 0;
    }
}

pub var global_clock: u2 = 0;
pub var data_bus: u4 = 0;

//// CHIP SIGNAL INSTRUCTIONS ////

pub fn get_global_clock() u2 {
    return global_clock;
}

pub fn signal_write(val: u4) void {
    data_bus = val;
}

pub fn signal_read() u4 {
    return data_bus;
}

pub fn signal_cm() void {
    for (roms) |rom| {
        rom.cm_rom = cpu.cm_rom;
    }
}

////

fn inc_clock() void {
    global_clock, _ = @addWithOverflow(global_clock, 1);
}

fn should_pause() bool {
    return switch (step_type) {
        Step.NORMAL, Step.INSTR => cpu.timing == T.X3 and cpu.clock_phase == 3,
        Step.TIMING => cpu.clock_phase == 3,
        Step.PHASE => true,
    };
}

fn run_motherboard() void {
    while (cpu.running) {
        inc_clock();
        cpu.tick();
        
        for (roms) |rom| {
            rom.tick();
        }

        if (pause and should_pause()) {
            if (step_type == Step.PHASE) {
                std.Thread.sleep(SECOND / 2);
            } else {
                std.Thread.sleep(SECOND);
            }
        }
    }

    main_thread_ended = true;
}

fn print_motherboard(alloc: std.mem.Allocator) !void {
    while (cpu.running) {
        try cpu.debug_print(alloc, step_type);

        std.debug.print("| MOTHERBOARD DATA: {b:0>4} | CHIP SELECT: ", .{ data_bus });

        for (roms) |rom| {
            if (rom.cse == 1) {
                std.debug.print("{X:0>1}    |            |\n", .{rom.chip_num});
                break;
            }
        } else {
            std.debug.print("NONE |            |\n", .{});
        }

        std.debug.print("-----------------------------------------------------------\n", .{});
    }

    debug_thread_ended = true;
}



pub fn run(alloc: std.mem.Allocator) !void {
    reset_reset();
    clear_screen();

    defer {
        alloc.destroy(cpu);
        for (&roms) |*rom| {
            alloc.destroy(rom.*);
        }
    }

    main_thread = try std.Thread.spawn(.{}, run_motherboard, .{});
    debug_thread = try std.Thread.spawn(.{}, print_motherboard, .{ alloc });

    main_thread.join();
    debug_thread.join();
    
    while (!main_thread_ended and !debug_thread_ended) {}
}