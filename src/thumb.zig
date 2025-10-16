const std = @import("std");
const math = std.math;

const ARM7TDMI = @import("arm7tdmi.zig").ARM7TDMI;
const fmts = @import("thumb_fmts.zig");
const utils = @import("utils.zig");

pub const lut_size = std.math.pow(u32, 2, 10);

pub const PC = 15;
pub const LR = 14;
pub const SP = 13;

pub fn build_thumb_lut() [lut_size]*const fn (u16, *ARM7TDMI) void {
    var lut: [lut_size]*const fn (u16, *ARM7TDMI) void = undefined;

    @setEvalBranchQuota(lut_size + 1);
    for (0..lut_size) |i| {
        if ((i & 0b1111_1100_00) == 0b0100_0100_00) {
            // Branch and Exchange and Hi register operations
            lut[i] = process_HI_BX;
        } else if ((i & 0b1110_0000_00) == 0b0010_0000_00) {
            // MOVE, CMP, ADD/SUB IMM
            lut[i] = process_MOV_CMP;
        } else if ((i & 0b1111_1000_00) == 0b0001_1000_00) {
            // ADD/SUB
            lut[i] = process_ADD_SUB;
        } else if ((i & 0b1111_0000_00) == 0b1010_0000_00) {
            // ADD with PC/SP
            lut[i] = process_REL_ADDR;
        }
    }
    return lut;
}

pub fn process_HI_BX(inst: u16, cpu: *ARM7TDMI) void {
    const instruction: fmts.HI_BX = @bitCast(inst);

    const rs = std.math.shl(u4, instruction.rs_hi, 3) | instruction.rs_lo;
    const rd = std.math.shl(u4, instruction.rd_hi, 3) | instruction.rd_lo;

    switch (instruction.opcode) {
        2 => {
            // Hi reg MOV
            switch (instruction.opcode) {
                2 => {
                    // MOV
                    cpu.regs[rd] = cpu.regs[rs];
                },
                else => {},
            }
        },
        3 => {
            // BX
            //std.debug.print("thumb bx to {x}\n", .{(cpu.regs[rs] & 0xFFFF_FFFC) - 4});
            const new_pc = cpu.regs[rs] & 0xFFFF_FFFC; // 32-bit aligned
            cpu.regs[PC] = new_pc - 8;
            cpu.cpsr.T = false;
        },
        else => {},
    }
}

pub fn process_ADD_SUB(inst: u16, cpu: *ARM7TDMI) void {
    const instruction: fmts.ADD_SUB = @bitCast(inst);
    switch (instruction.opcode) {
        2 => {
            cpu.regs[instruction.rd] = cpu.regs[instruction.rs] +% instruction.operand;
        },
        else => {},
    }
}

pub fn process_MOV_CMP(inst: u16, cpu: *ARM7TDMI) void {
    const instruction: fmts.MOV_CMP = @bitCast(inst);

    switch (instruction.opcode) {
        0 => {
            //std.debug.print("mov thumb {x} to reg {}\n", .{ instruction.nn, instruction.rd });
            cpu.regs[instruction.rd] = instruction.nn;
        },
        else => {},
    }
}

// add PC/SP
pub fn process_REL_ADDR(inst: u16, cpu: *ARM7TDMI) void {
    const instruction: fmts.REL_ADDR = @bitCast(inst);
    const source = if (!instruction.sp_source) cpu.regs[PC] + 2 else cpu.regs[SP];

    //std.debug.print("{} = {x} + {x}\n", .{ instruction.rd, source, instruction.nn });
    cpu.regs[instruction.rd] = source + instruction.nn;
}
