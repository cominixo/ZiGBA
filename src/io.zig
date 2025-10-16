const std = @import("std");

const DISPCNT_IND = 0;
const DISPSTAT_IND = 4;

pub const IO = struct {
    map: []u8,

    pub fn init(allocator: *const std.mem.Allocator) !IO {
        const this = IO{
            .map = try allocator.alloc(u8, 0x400),
        };
        @memset(this.map, 0);
        return this;
    }

    pub fn getDISPCNT(self: *IO) *DISPCNT {
        return @alignCast(@ptrCast(&self.map[DISPCNT_IND]));
    }

    pub fn getDISPSTAT(self: *IO) *DISPSTAT {
        return @alignCast(@ptrCast(&self.map[DISPSTAT_IND]));
    }
};

// Register Structs //
pub const DISPCNT = packed struct(u16) {
    bg_mode: u3,
    _cgb_mode: bool,
    frame_select: u1,
    hblank_free: bool,
    vram_mapping_type: u1, // 0 = 2D, 1 = 1D
    forced_blank: bool,
    display_bg0: bool,
    display_bg1: bool,
    display_bg2: bool,
    display_bg3: bool,
    display_obj: bool,
    window_0_display: bool,
    window_1_display: bool,
    obj_window_display: bool,
};

pub const DISPSTAT = packed struct(u16) {
    vblank: bool,
    hblank: bool,
    vcounter: bool,
    vblank_irq: bool,
    hblank_irq: bool,
    vcounter_irq: bool,
    _: u2,
    vcount_setting: u8,
};

pub const VCOUNT = packed struct(u16) {
    cur_scanline: u8 = 0,
    _: u8 = 0,
};
