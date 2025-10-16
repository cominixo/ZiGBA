const std = @import("std");
const builtin = @import("builtin");
const arm7tdmi = @import("arm7tdmi.zig");
const memory = @import("memory.zig");
const ppu = @import("ppu.zig");
const io = @import("io.zig");

const c = ppu.c;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;

pub fn main() !void {
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("GBA", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 240 * 3, 160 * 3, 0);
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, 0, 0); //c.SDL_RENDERER_PRESENTVSYNC);
    defer c.SDL_DestroyRenderer(renderer);

    _ = c.SDL_RenderSetLogicalSize(renderer, 240, 160);

    const rom = @embedFile("roms/arm.gba");

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var io_inst = try io.IO.init(&allocator);
    var ppu_inst = try ppu.PPU.init(&arena_alloc, renderer.?, &io_inst);

    var cpu = arm7tdmi.ARM7TDMI.init(&ppu_inst, &io_inst);

    // Init memory

    try cpu.initMem(&arena_alloc);

    cpu.mem.loadROM(rom);

    cpu.regs[15] = memory.ROM_START;
    cpu.regs[13] = 0x03007F00; // stack start

    cpu.flushPipeline();

    _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0);

    _ = c.SDL_RenderClear(renderer);

    var t = try std.time.Timer.start();

    var b: u32 = 0;
    mainloop: while (true) {
        const cpu_cycles: u32 = switch (cpu.ppu.state) {
            ppu.PPUState.hdraw => 960,
            ppu.PPUState.hblank => 272,
            ppu.PPUState.vblank => 83776,
        };

        for (0..cpu_cycles) |_| {
            cpu.step();
        }

        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event) != 0) {
            switch (sdl_event.type) {
                c.SDL_QUIT => break :mainloop,
                else => {},
            }
        }

        cpu.ppu.tick();

        if (cpu.ppu.state == ppu.PPUState.vblank) {
            const lap_int = t.lap();
            const lap: f32 = @as(f32, @floatFromInt(lap_int)) / 1000000000.0;
            if (lap > 0) {
                //std.debug.print("{d} fps\n", .{@divFloor(1, lap)});
            }
        }
        b += 1;
    }
}
