const std = @import("std");
const ppu = @import("ppu.zig");
const io = @import("io.zig");

pub const ROM_START = 0x8000000;
pub const VRAM_START = 0x6000000;
pub const PAL_START = 0x5000000;
pub const IO_START = 0x4000000;
pub const WRAM_CHIP_START = 0x3000000;

pub const Memory = struct {
    bios: []u8,
    wram: []u8,
    chip_wram: []u8,
    rom: []u8,

    ppu: *ppu.PPU,
    io: *io.IO,

    pub fn init(allocator: *const std.mem.Allocator, ppu_inst: *ppu.PPU, io_inst: *io.IO) anyerror!Memory {
        return Memory{
            .bios = try allocator.alloc(u8, 0x4000),
            .wram = try allocator.alloc(u8, 0x40000),
            .chip_wram = try allocator.alloc(u8, 0x8000),
            .rom = try allocator.alloc(u8, 0x2000000),
            .ppu = ppu_inst,
            .io = io_inst,
        };
    }

    pub fn loadROM(self: *Memory, bytes: []const u8) void {
        std.mem.copyForwards(u8, self.rom, bytes);
    }

    pub fn read(self: *Memory, comptime T: type, addr: u32) T {
        return switch (addr >> 24) {
            3 => {
                const mapped_memory = addr - WRAM_CHIP_START;
                const ret = std.mem.bytesAsSlice(T, self.chip_wram[mapped_memory .. mapped_memory + @sizeOf(T)])[0];
                return ret;
            },
            4 => {
                const mapped_memory = addr - IO_START;
                const ret = std.mem.bytesAsSlice(T, self.io.map[mapped_memory .. mapped_memory + @sizeOf(T)])[0];
                return ret;
            },
            8 => {
                const mapped_memory = addr - ROM_START;
                return std.mem.bytesAsSlice(T, self.rom[mapped_memory .. mapped_memory + @sizeOf(T)])[0];
            },
            else => 0,
        };
    }

    pub fn write(self: *Memory, comptime T: type, addr: u32, data: T) void {
        // TODO proper bus
        //std.debug.print("write {x} addr {x}\n", .{data, addr});
        switch (addr >> 24) {
            3 => {
                const mapped_memory = addr - WRAM_CHIP_START;
                std.mem.writeInt(T, self.chip_wram[mapped_memory..][0..@sizeOf(T)], data, .little);
            },
            4 => {
                const mapped_memory = addr - IO_START;
                std.mem.writeInt(T, self.io.map[mapped_memory..][0..@sizeOf(T)], data, .little);
            },
            5 => {
                const mapped_memory = addr - PAL_START;
                std.mem.writeInt(T, self.ppu.pal_ram[mapped_memory..][0..@sizeOf(T)], data, .little);
            },
            6 => {
                const mapped_memory = addr - VRAM_START;
                std.mem.writeInt(T, self.ppu.vram[mapped_memory..][0..@sizeOf(T)], data, .little);
            },
            else => {},
        }
    }
};
