const std = @import("std");
const math = std.math;

const utils = @import("utils.zig");
const ppu = @import("ppu.zig");
const io = @import("io.zig");
const memory = @import("memory.zig");
const arm = @import("arm.zig");
const thumb = @import("thumb.zig");

pub var arm_lut: [arm.lut_size]*const fn (u32, *ARM7TDMI) void = arm.build_arm_lut();
pub var thumb_lut: [thumb.lut_size]*const fn (u16, *ARM7TDMI) void = thumb.build_thumb_lut();

pub const ARM7TDMI = struct {
    regs: [16]u32,
    banks: [6][8]u32,
    pipelined_inst: [2]u32,
    ppu: *ppu.PPU,
    io: *io.IO,
    mem: memory.Memory = undefined,
    cpsr: CPSR,
    spsr: [6]CPSR,

    pub fn init(ppu_inst: *ppu.PPU, io_inst: *io.IO) ARM7TDMI {
        return ARM7TDMI{
            .ppu = ppu_inst,
            .io = io_inst,
            .regs = .{0} ** 16,
            .banks = .{.{0} ** 8} ** 6,
            .pipelined_inst = .{0} ** 2,
            .cpsr = CPSR{},
            .spsr = .{CPSR{}} ** 6,
        };
    }

    pub fn initMem(self: *ARM7TDMI, allocator: *const std.mem.Allocator) anyerror!void {
        self.mem = try memory.Memory.init(allocator, self.ppu, self.io);
    }

    pub fn executeARMInstruction(self: *ARM7TDMI, inst: u32) void {
        const identifier = ((inst >> 4) & 0xF) | ((inst >> 16) & 0xFF0);
        arm_lut[identifier](inst, self);
    }

    pub fn executeTHUMBInstruction(self: *ARM7TDMI, inst: u16) void {
        const identifier = inst >> 6;
        thumb_lut[identifier](inst, self);
    }

    pub fn step(self: *ARM7TDMI) void {
        if (!self.cpsr.T) {
            // ARM
            //self.regs[arm.PC] += 4;
            const inst = self.pipelined_inst[1];
            self.pipelined_inst[1] = self.pipelined_inst[0];
            self.pipelined_inst[0] = self.mem.read(u32, self.regs[arm.PC]);
            const cond: u4 = @truncate(inst >> 28);

            if (!self.checkCPSR(cond)) {
                self.regs[arm.PC] += 4;
                return;
            }

            self.executeARMInstruction(inst);
        } else {
            // THUMB
            const inst = self.mem.read(u16, self.regs[arm.PC]);
            self.regs[arm.PC] += 2;

            self.executeTHUMBInstruction(inst);
        }
    }

    pub fn checkCPSR(self: *ARM7TDMI, cond: u4) bool {
        return switch (cond) {
            0x0 => self.cpsr.Z,
            0x1 => !self.cpsr.Z,
            0x2 => self.cpsr.C,
            0x3 => !self.cpsr.C,
            0x4 => self.cpsr.N,
            0x5 => !self.cpsr.N,
            0x6 => self.cpsr.V,
            0x7 => !self.cpsr.V,
            0x8 => self.cpsr.C and !self.cpsr.Z,
            0x9 => !self.cpsr.C and self.cpsr.Z,
            0xa => self.cpsr.N == self.cpsr.V,
            0xb => self.cpsr.N != self.cpsr.V,
            0xc => !self.cpsr.Z and self.cpsr.N == self.cpsr.V,
            0xd => self.cpsr.Z or self.cpsr.N != self.cpsr.V,
            0xe => true,
            else => false,
        };
    }

    pub fn changeMode(self: *ARM7TDMI, mode: Mode) void {
        const old_bank = self.cpsr.mode.toBank();
        const bank = mode.toBank();
        // TODO other banks
        if (bank == .FIQ) {
            for (8..15) |i| {
                self.banks[@intFromEnum(Bank.USER)][i - 8] = self.regs[i];
                self.regs[i] = self.banks[@intFromEnum(Bank.FIQ)][i - 8];
            }
        } else if (old_bank == .FIQ) {
            for (8..15) |i| {
                self.banks[@intFromEnum(Bank.FIQ)][i - 8] = self.regs[i];
                self.regs[i] = self.banks[@intFromEnum(Bank.USER)][i - 8];
            }
        }
    }

    pub inline fn flushPipeline(self: *ARM7TDMI) void {
        self.pipelined_inst[0] = self.mem.read(u32, self.regs[arm.PC] + 4);
        self.pipelined_inst[1] = self.mem.read(u32, self.regs[arm.PC]);
        self.regs[arm.PC] += 8;
    }
};

const Mode = enum(u5) {
    USER = 0x10,
    FIQ = 0x11,
    IRQ = 0x12,
    SVC = 0x13,
    ABT = 0x17,
    UND = 0x1b,
    SYS = 0x1f,

    pub fn toBank(self: Mode) Bank {
        return switch (self) {
            .FIQ => Bank.FIQ,
            .IRQ => Bank.IRQ,
            .SVC => Bank.SVC,
            .ABT => Bank.ABT,
            .UND => Bank.UND,
            else => Bank.USER,
        };
    }
};

const Bank = enum { USER, FIQ, IRQ, SVC, ABT, UND };

pub const CPSR = packed struct(u32) {
    mode: Mode = .UND,
    T: bool = false,
    F: bool = false,
    I: bool = false,
    _: u19 = 0,
    Q: bool = false,
    V: bool = false,
    C: bool = false,
    Z: bool = false,
    N: bool = false,
};
