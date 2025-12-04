const std = @import("std");
const Step = @import("global").Step;
const Motherboard = @import("motherboard.zig");

const ver: []const u8 = "0.00.5";

fn argument_processor(alloc: std.mem.Allocator) !struct { []u8, Step, f32 } {
    var args_iter = try std.process.ArgIterator.initWithAllocator(alloc);
    defer args_iter.deinit();
    _ = args_iter.next();

    var process_pause: bool = false;

    var pause_time: f32 = 0.0;
    var step_type: Step = Step.NORMAL;
    var filename = try std.ArrayList(u8).initCapacity(alloc, 0x200);
    defer filename.deinit(alloc);

    while (args_iter.next()) |str| {
        if (std.mem.eql(u8, str, "--help")) {
            std.debug.print("The Accui Project v{s}\nCommand Usage: [emu].exe [filename].i44 {{args}}\n\n", .{ ver });
            std.debug.print("Arguments:\n", .{});
            std.debug.print("-s (off|instr|timing|phase) : Step   | Sets the type of stepping used:\n  - instr: steps every instruction cycle\n  - timing: steps every clock cycle\n  - phase: steps every clock phase\n\n", .{});
            std.debug.print("-p {{time}}                    : Pause  | Sets whether to pause, and optionally for how long", .{});
            return .{ "", Step.NORMAL, 0.0 };
        }

        if (str[0] != '-') {
            if (process_pause) {
                pause_time = std.fmt.parseFloat(f32, str) catch |err| switch (err) {
                    else => {
                        @panic("Invalid pause time, must be float");
                    }
                };
                continue;
            }
            if (filename.getLastOrNull() == null) {
                try filename.writer(alloc).print("{s}", .{str});
            } else {
                try filename.writer(alloc).print(" {s}", .{str});
            }
            continue;
        }

        if (str[1] == 's') {
            if (args_iter.next()) |st| {
                if (std.mem.eql(u8, st, "instr")) {
                    step_type = Step.INSTR;
                    continue;
                }
                if (std.mem.eql(u8, st, "timing")) {
                    step_type = Step.TIMING;
                    continue;
                }
                if (std.mem.eql(u8, st, "phase")) {
                    step_type = Step.PHASE;
                    continue;
                }
                if (!std.mem.eql(u8, st, "off")) {
                    std.debug.print("Incorrect step type: \"{s}\"\n", .{st});
                    @panic("");
                }
            }
            continue;
        }

        if (str[1] == 'p') {
            if (step_type == Step.PHASE) {
                pause_time = 0.5;
            } else {
                pause_time = 1.0;
            }
            process_pause = true;
            continue;
        }
    }

    const ret: []u8 = try alloc.alloc(u8, filename.items.len);
    @memcpy(ret, filename.items);

    return .{ ret, step_type, pause_time };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) {
            @panic("LEAK!!!");
        }
    }

    const filename, const step_type, const pause_time = try argument_processor(alloc);
    defer alloc.free(filename);

    if (std.mem.eql(u8, filename, "")) {
        std.debug.print("The Accui Project v{s}\nCommand Usage: [emu].exe [filename].i44 {{args}}\n", .{ ver });
        return;
    }

    try Motherboard.init(alloc, filename, step_type, pause_time);

    try Motherboard.run(alloc);
}