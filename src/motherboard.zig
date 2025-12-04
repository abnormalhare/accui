const std = @import("std");

const Global = @import("global");
const Step = Global.Step;
const CompType = Global.CompType;
const clear_screen = Global.clear_screen;
const reset_screen = Global.reset_screen;
const num_to_list = Global.num_to_list;
const list_to_num = Global.list_to_num;

const I4001 = @import("chips/intel/i4001.zig").I4001;
const I4002 = @import("chips/intel/i4002.zig").I4002;
const I4004 = @import("chips/intel/i4004.zig").I4004;
const T = @import("chips/intel/i4004.zig").T;

const SECOND = 1_000_000_000;

var step_type: Step = Step.NORMAL;
var pause_time: f32 = 0;

var cpu: *I4004 = undefined;
var roms: [16]*I4001 = undefined;
var rams: [16]*I4002 = undefined;

var main_thread: std.Thread = undefined;
var main_thread_ended: bool = false;

var debug_thread: std.Thread = undefined;
var debug_thread_ended: bool = false;

// Reads 
pub fn init(alloc: std.mem.Allocator, filename: []const u8, def_step_type: Step, def_pause_time: f32) !void {
    cpu = try I4004.init(alloc);
    errdefer alloc.destroy(cpu);

    var file = std.fs.cwd().openFile(filename, .{}) catch |err| switch (err) {
        else => {
            std.debug.print("ERROR WITH FILENAME: {s}\n", .{filename});
            @panic("");
        }
    };
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
        ram.* = try I4002.init(alloc, @truncate(idx));
    }

    step_type = def_step_type;
    pause_time = def_pause_time;
}

fn reset_reset() void {
    cpu.reset = 0;
    for (&roms) |rom| {
        rom.reset = 0;
    }
    for (&rams) |ram| {
        ram.reset = 0;
    }
}

pub var global_clock: u2 = 0;
pub var wires: [16]u1 = [_]u1{ 0 } ** 16;

//// CHIP SIGNAL INSTRUCTIONS ////

pub fn get_global_clock() u2 {
    return global_clock;
}

pub fn signal_write_bus(val: u4) void {
    wires[0] = @truncate(val >> 0);
    wires[1] = @truncate(val >> 1);
    wires[2] = @truncate(val >> 2);
    wires[3] = @truncate(val >> 3);
}

// Allows for chips to no need to know where they are
// sending their data, we handle it here.
pub fn signal_write(val: []u1, from: CompType, pin: u8) void {
    _ = val; _ = from; _ = pin;
}

pub fn signal_read_bus() u4 {
    const data_bus: u4 = @truncate(list_to_num(&wires, 4));
    return data_bus;
}

pub fn signal_read(from: CompType, pin: u8) []u1 {
    _ = from; _ = pin;
    return wires;
}

pub fn signal_cm() void {
    for (roms) |rom| {
        rom.cm_rom = cpu.cm_rom;
    }
    
    for (rams, 0..) |ram, idx| {
        const shf_cnt: u4 = std.math.pow(u4, 2, @intCast(idx / 4));
        ram.cm_ram = @truncate(cpu.cm_ram & shf_cnt);
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
        for (rams) |ram| {
            ram.tick();
        }

        if (pause_time != 0 and should_pause()) {
            std.Thread.sleep(@intFromFloat(SECOND * pause_time));
        }
    }

    main_thread_ended = true;
}

var debug_ram_page: u4 = 0;

fn print_motherboard(alloc: std.mem.Allocator) !void {
    while (cpu.running) {
        const cpu_dbp = try cpu.debug_print(alloc, step_type);
        defer alloc.free(cpu_dbp);

        const ram_dbp = try rams[debug_ram_page].debug_print(alloc);
        defer alloc.free(ram_dbp);


        var list = try std.ArrayList(u8).initCapacity(alloc, 0x2000);
        defer list.deinit(alloc);
        
        const writer = list.writer(alloc);
        
        try writer.print("-----------------------------------------------------------\n", .{});
        try writer.print("{s}", .{ cpu_dbp });
        try writer.print("|---------------------------------------------------------|\n", .{});
        try writer.print("{s}", .{ ram_dbp });
        try writer.print("|---------------------------------------------------------|\n", .{});
        try writer.print("| MOTHERBOARD DATA: {b:0>4} | CHIP SELECT: ", .{ signal_read_bus() });

        for (roms) |rom| {
            if (rom.cse == 1) {
                try writer.print("{X:0>1}    |            |\n", .{rom.chip_num});
                break;
            }
        } else {
            try writer.print("NONE |            |\n", .{});
        }

        try writer.print("-----------------------------------------------------------\n", .{});

        reset_screen();
        std.debug.print("{s}", .{list.items});
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