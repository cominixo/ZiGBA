pub const c = @cImport({
    @cInclude("SDL.h");
});
const std = @import("std");

const io = @import("io.zig");

const DISP_HEIGHT = 160;
const DISP_WIDTH = 240;

pub const PPU = struct {
    pal_ram: []u8,
    vram: []u8,
    oam: []u8,

    io: *io.IO,

    state: PPUState = PPUState.hdraw,

    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,

    pixel_buffer: [*c]?*anyopaque,
    pitch: c_int = 0,

    lines_drawn: u32 = 0,

    pub fn init(allocator: *const std.mem.Allocator, renderer: *c.SDL_Renderer, io_inst: *io.IO) anyerror!PPU {
        const pixels: **anyopaque = try allocator.create(*anyopaque);
        const this = PPU{
            .pal_ram = try allocator.alloc(u8, 0x400),
            .vram = try allocator.alloc(u8, 0x18000),
            .oam = try allocator.alloc(u8, 0x400),
            .io = io_inst,
            .renderer = renderer,
            .pixel_buffer = @ptrCast(pixels),
            .texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STREAMING, DISP_WIDTH, DISP_HEIGHT).?,
        };
        @memset(this.pal_ram, 0);
        @memset(this.vram, 0);
        return this;
    }

    pub fn tick(self: *PPU) void {
        const dispstat = self.io.getDISPSTAT();

        switch (self.state) {
            PPUState.hdraw => {
                _ = c.SDL_LockTexture(self.texture, 0, self.pixel_buffer, &self.pitch);

                var base = @as([*c]u8, @ptrCast(self.pixel_buffer.*)) + (4 * (self.lines_drawn * DISP_WIDTH));
                const dispcnt = self.io.getDISPCNT();

                switch (dispcnt.bg_mode) {
                    3 => {
                        var index = (self.lines_drawn * DISP_WIDTH) * 2;
                        for (0..DISP_WIDTH) |_| {
                            const rgb: *const RGBPixel = @alignCast(@ptrCast(&self.vram[index]));

                            base[0] = @as(u8, rgb.blue) * 8;
                            base[1] = @as(u8, rgb.green) * 8;
                            base[2] = @as(u8, rgb.red) * 8;
                            base[3] = 255; // A

                            base += 4;
                            index += 2;
                        }
                    },
                    4 => {
                        var index = (self.lines_drawn * DISP_WIDTH);
                        for (0..DISP_WIDTH) |_| {
                            var pal_index: u16 = @as(u16, self.vram[index]) * 2;
                            if (pal_index % 16 == 0) {
                                pal_index = 0;
                            }
                            const rgb: RGBPixel = @bitCast(@as(u16, self.pal_ram[pal_index]) | std.math.shl(u16, self.pal_ram[pal_index + 1], 8));

                            base[0] = @as(u8, rgb.blue) * 8;
                            base[1] = @as(u8, rgb.green) * 8;
                            base[2] = @as(u8, rgb.red) * 8;
                            base[3] = 255; // A

                            base += 4;
                            index += 1;
                        }
                    },
                    else => {},
                }

                self.state = PPUState.hblank;
                self.lines_drawn += 1;
                self.io.map[6] += 1; // VCOUNT
            },
            PPUState.hblank => {
                if (self.lines_drawn >= DISP_HEIGHT) {
                    dispstat.*.vblank = true;
                    self.state = PPUState.vblank;
                } else {
                    self.state = PPUState.hdraw;
                }
            },
            PPUState.vblank => {
                dispstat.*.vblank = false;
                self.state = PPUState.hdraw;

                _ = c.SDL_UnlockTexture(self.texture);
                _ = c.SDL_RenderCopy(self.renderer, self.texture, 0, 0);
                _ = c.SDL_RenderPresent(self.renderer);

                self.lines_drawn = 0;
                self.io.map[6] = 0; // reset VCOUNT
            },
        }
    }
};

pub const PPUState = enum {
    hdraw,
    hblank,
    vblank,
};

const RGBPixel = packed struct(u16) {
    red: u5,
    green: u5,
    blue: u5,
    _: u1,
};
