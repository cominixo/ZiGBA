const std = @import("std");
const math = std.math;

const ARM7TDMI = @import("arm7tdmi.zig").ARM7TDMI;
const CPSR = @import("arm7tdmi.zig").CPSR;
const fmts = @import("arm_fmts.zig");
const utils = @import("utils.zig");

pub const lut_size = std.math.pow(u32, 2, 12);

pub const PC = 15;
pub const LR = 14;
pub const SP = 13;

pub fn build_arm_lut() [lut_size]*const fn (u32, *ARM7TDMI) void {
    var lut: [lut_size]*const fn (u32, *ARM7TDMI) void = undefined;

    @setEvalBranchQuota(lut_size + 1);
    for (0..lut_size) |i| {
        if (i == 0b0001_0010_0001) {
            // Branch and Exchange
            lut[i] = process_BX;
        } else if ((i & 0b1110_0000_0000) == 0b1000_0000_0000) {
            // Block Data Transfer
            lut[i] = process_BDT;
        } else if ((i & 0b1110_0000_0000) == 0b1010_0000_0000) {
            // Branch and Branch with Link
            lut[i] = process_B;
        } else if ((i & 0b1111_0000_0000) == 0b1111_0000_0000) {
            // Software Interrupt
            lut[i] = process_SWI;
        } else if ((i & 0b1110_0000_0000) == 0b0110_0000_0001) {
            // Undefined
            lut[i] = process_undefined;
        } else if ((i & 0b1100_0000_0000) == 0b0100_0000_0000) {
            // Single Data Transfer
            lut[i] = process_SDT;
        } else if ((i & 0b1111_1011_1111) == 0b0001_0000_1001) {
            // Single Data Swap
            lut[i] = process_SWP;
        } else if ((i & 0b1111_1100_1111) == 0b0000_0000_1001) {
            // Multiply
            lut[i] = process_MUL;
        } else if ((i & 0b1111_1000_1111) == 0b0000_1000_1001) {
            // Multiply Long
            lut[i] = process_MULL;
        } else if ((i & 0b1110_0000_1001) == 0b0000_0000_1001) {
            // Halfword Data Transfer
            lut[i] = process_HDT;
        } else if ((i & 0b1111_1011_0000) == 0b0001_0000_0000) {
            // MRS
            lut[i] = process_MRS;
        } else if ((i & 0b1111_1011_0000) == 0b0001_0010_0000) {
            // MSR REG
            lut[i] = process_MSR_REG;
        } else if ((i & 0b1111_1011_0000) == 0b0011_0010_0000) {
            // MSR IMM
            lut[i] = process_MSR_IMM;
        } else if ((i & 0b1100_0000_0000) == 0b0000_0000_0000) {
            // Data Processing (ALU)
            if ((i & 0b0010_0000_0000) != 0) {
                lut[i] = process_ALU_IMM;
            } else {
                lut[i] = process_ALU_REG;
            }
        }
    }
    return lut;
}

// Branch and Exchange
fn process_BX(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.BX = @bitCast(inst);
    var jump_addr = cpu.regs[instruction.rn];
    if (cpu.regs[instruction.rn] & 1 != 0) {
        // switch to thumb
        jump_addr -= 1;
        cpu.cpsr.T = true;
    }
    cpu.regs[PC] = jump_addr;
}

// Block Data Transfer (LDM/STM)
fn process_BDT(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.BDT = @bitCast(inst);

    const writeback = instruction.writeback; // TODO or !instruction.is_pre?

    var address: i32 = @bitCast(cpu.regs[instruction.rn]); // TODO bad

    const offset: i32 = if (instruction.is_up) 4 else -4;

    var reg: u32 = if (instruction.is_up) 0 else 15;

    var modifies_r15 = false;

    if (instruction.is_load) {
        while (reg < 16) {
            if (instruction.reg_list & std.math.shl(u16, 1, reg) != 0) {
                if (instruction.is_pre) {
                    address += offset;
                    cpu.regs[reg] = cpu.mem.read(u32, @as(u32, @bitCast(address)));
                } else {
                    cpu.regs[reg] = cpu.mem.read(u32, @as(u32, @bitCast(address)));
                    address += offset;
                }
                if (reg == PC) {
                    modifies_r15 = true;
                }
                utils.print_to_file("{x}: read {x} {} addr {x}\n", .{ cpu.regs[PC], cpu.regs[reg], reg, address });
            }
            if (instruction.is_up) reg += 1 else reg -%= 1;
        }
    } else {
        while (reg < 16) {
            if (instruction.reg_list & std.math.shl(u16, 1, reg) != 0) {
                if (instruction.is_pre) {
                    address += offset;
                    cpu.mem.write(u32, @as(u32, @bitCast(address)), cpu.regs[reg]);
                } else {
                    cpu.mem.write(u32, @as(u32, @bitCast(address)), cpu.regs[reg]);
                    address += offset;
                }
                utils.print_to_file("{x}: write {x} {} addr {x}\n", .{ cpu.regs[PC], cpu.regs[reg], reg, address });
            }
            if (instruction.is_up) reg += 1 else reg -%= 1;
        }
    }

    if (writeback) {
        cpu.regs[instruction.rn] = @as(u32, @bitCast(address));
    }
    if (modifies_r15) {
        cpu.flushPipeline();
    } else {
        cpu.regs[PC] += 4;
    }
}

// Branch and Branch with Link
fn process_B(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.B_BL = @bitCast(inst);

    if (instruction.opcode == 1) {
        // Link
        cpu.regs[LR] = cpu.regs[PC] - 4;
    }

    utils.print_to_file("prev pc {x} cond {b} offset {x}\n", .{ cpu.regs[PC], instruction.cond, @as(i32, instruction.offset) * 4 });

    cpu.regs[PC] +%= @bitCast(@as(i32, instruction.offset) * 4);

    cpu.flushPipeline();

    utils.print_to_file("new pc {x} r12 {} link {x}\n", .{ cpu.regs[PC], cpu.regs[12], cpu.regs[LR] });
}

// Software Interrupt
fn process_SWI(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.SWI = @bitCast(inst);

    switch (instruction.comment) {
        0x60000 => {
            // DIV
            const n1: i32 = @bitCast(cpu.regs[0]);
            const n2: i32 = @bitCast(cpu.regs[1]);
            const result = @divFloor(n1, n2);
            const mod = @rem(n1, n2);

            cpu.regs[0] = @bitCast(result);
            cpu.regs[1] = @bitCast(mod);
            cpu.regs[3] = @abs(result);
        },
        else => {},
    }
    cpu.regs[PC] += 4;
}

// Single Data Transfer
fn process_SDT(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.SDT = @bitCast(inst);

    const writeback = instruction.writeback or !instruction.is_pre;

    var address = cpu.regs[instruction.rn];

    var offset = instruction.offset; // TODO register offset

    if (!instruction.is_up) offset ^= 0xFFF;

    if (instruction.is_pre) {
        address +%= offset;
    }

    if (instruction.is_load) {
        cpu.regs[instruction.rd] = if (instruction.is_byte) @as(u32, cpu.mem.read(u8, address)) else cpu.mem.read(u32, address);
    } else {
        if (instruction.is_byte) {
            cpu.mem.write(u8, address, @truncate(cpu.regs[instruction.rd]));
        } else {
            cpu.mem.write(u32, address, cpu.regs[instruction.rd]);
        }

        if (instruction.rd == PC) {
            cpu.flushPipeline();
        }
    }

    if (writeback) {
        cpu.regs[instruction.rn] +%= offset;
    }

    cpu.regs[PC] += 4;
}

// Single Data Swap (LDR, STR)
fn process_SWP(_: u32, cpu: *ARM7TDMI) void {
    //var instruction: fmts.SWP = @bitCast(inst);
    cpu.regs[PC] += 4;
}

// Multiply
fn process_MUL(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.MUL = @bitCast(inst);

    cpu.regs[instruction.rd] = @truncate(@as(u64, cpu.regs[instruction.rm]) * @as(u64, cpu.regs[instruction.rs]));

    if (instruction.accumulate) {
        cpu.regs[instruction.rd] +%= cpu.regs[instruction.rn];
    }
    if (instruction.set_condition) {
        cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[instruction.rd]);
    }
    if (instruction.rd == PC) {
        cpu.flushPipeline();
    }

    cpu.regs[PC] += 4;
}

// Multiply Long
fn process_MULL(_: u32, cpu: *ARM7TDMI) void {

    //var instruction: fmts.MULL = @bitCast(inst);
    cpu.regs[PC] += 4;
}

fn process_HDT(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.HDT = @bitCast(inst);

    const offset = if (instruction.is_immediate)
        math.shl(u8, instruction.offset_hi, 4) | instruction.offset_lo
    else
        cpu.regs[instruction.offset_lo]; // offset_lo is the reg number in this case

    const writeback = instruction.writeback or !instruction.is_pre;

    var address = cpu.regs[instruction.rn];

    if (instruction.is_pre) {
        address +%= offset;
    }

    if (instruction.is_load) {
        switch (instruction.opcode) {
            1 => {
                const val = cpu.mem.read(u16, address);
                cpu.regs[instruction.rd] = val;
            },
            else => {},
        }
    } else {
        switch (instruction.opcode) {
            1 => {
                //utils.print_to_file("halfword offset {x} rn {x} rd {x}\n", .{offset, cpu.regs[instruction.rn], cpu.regs[instruction.rd]});
                const write_val: u16 = @truncate(cpu.regs[instruction.rd]); // TODO use instruction.is_up
                cpu.mem.write(u16, address, write_val);
            },
            else => {},
        }
    }

    if (writeback) {
        cpu.regs[instruction.rn] +%= offset;
    }

    cpu.regs[PC] += 4;
}

fn process_MRS(_: u32, cpu: *ARM7TDMI) void {
    cpu.regs[PC] += 4;
}

fn process_MSR_IMM(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.MSR_IMM = @bitCast(inst);

    const imm = std.math.rotr(u32, instruction.imm, instruction.rot * 2);

    utils.print_to_file("new cpsr {b} {} {}\n", .{ imm, instruction.c, instruction.f });
    var cpsr_bits: u32 = @bitCast(cpu.cpsr);

    if (instruction.c) cpsr_bits = (cpsr_bits & 0xFFFFFF00) | (imm & 0xFF);
    if (instruction.f) cpsr_bits = (cpsr_bits & 0x00FFFFFF) | (imm & 0xFF000000);

    if (instruction.destination == 0) {
        // CPSR
        const new_cpsr: CPSR = @bitCast(cpsr_bits);
        cpu.changeMode(new_cpsr.mode);
        cpu.cpsr = new_cpsr;
    } else {
        // SPSR
        const spsr = cpu.cpsr.mode.toBank();
        cpu.spsr[@intFromEnum(spsr)] = @bitCast(cpsr_bits);
    }
    cpu.regs[PC] += 4;
}

fn process_MSR_REG(_: u32, cpu: *ARM7TDMI) void {
    cpu.regs[PC] += 4;
}

//
fn process_ALU(opcode: u4, rd: u32, rn: u32, op2: u32, s: bool, cpu: *ARM7TDMI) bool {
    utils.print_to_file("{x}: ALU OP: {x} {d}: {x} op {x} = r{d} ", .{ cpu.regs[PC] - 8, opcode, rn, cpu.regs[rn], op2, rd });
    var override_carry = false;
    switch (opcode) {
        0x0 => {
            // AND
            cpu.regs[rd] = cpu.regs[rn] & op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
        },
        0x1 => {
            // EOR
            cpu.regs[rd] = cpu.regs[rn] ^ op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
        },
        0x2 => {
            // SUB
            cpu.cpsr.C = cpu.regs[rn] >= op2;
            const old_rn = cpu.regs[rn];
            cpu.regs[rd] = cpu.regs[rn] -% op2;

            cpu.cpsr.V = utils.did_overflow(u32, old_rn, op2, cpu.regs[rd]);
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
            override_carry = true;
        },
        0x3 => {
            // RSB
            const carry_op = @as(u1, @bitCast(cpu.cpsr.C)) ^ 1;
            const result = op2 -% cpu.regs[rn] -% carry_op;

            cpu.cpsr.C = (cpu.regs[rn] >= op2 +% carry_op);

            const old_rn = cpu.regs[rn];
            cpu.regs[rd] = result;

            cpu.cpsr.V = utils.did_overflow(u32, old_rn, op2, cpu.regs[rd]);
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
            override_carry = true;
        },
        0x4 => {
            // ADD
            const result = @addWithOverflow(cpu.regs[rn], op2);
            const old_rn = cpu.regs[rn];

            cpu.regs[rd] = result[0];
            cpu.cpsr.C = @bitCast(result[1]);
            cpu.cpsr.V = utils.did_overflow(u32, old_rn, ~op2, cpu.regs[rd]);

            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
            override_carry = true;
        },
        0x5 => {
            // ADDC
            const result = @as(u64, cpu.regs[rn]) +% @as(u64, op2) +% @as(u1, @bitCast(cpu.cpsr.C));

            const old_rn = cpu.regs[rn];
            cpu.regs[rd] = @truncate(result);
            cpu.cpsr.C = (result >> 32) != 0;
            cpu.cpsr.V = utils.did_overflow(u32, old_rn, ~op2, cpu.regs[rd]);
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
            override_carry = true;
        },
        0x6 => {
            // SUBC
            const carry_op = @as(u1, @bitCast(cpu.cpsr.C)) ^ 1;
            const result = cpu.regs[rn] -% op2 -% carry_op;

            cpu.cpsr.C = (cpu.regs[rn] >= op2 +% carry_op);

            const old_rn = cpu.regs[rn];
            cpu.regs[rd] = result;

            cpu.cpsr.V = utils.did_overflow(u32, old_rn, op2, cpu.regs[rd]);
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
            override_carry = true;
        },
        0x7 => {
            // RSB
            const carry_op = @as(u1, @bitCast(cpu.cpsr.C)) ^ 1;
            const result = op2 -% cpu.regs[rn] -% carry_op;

            cpu.cpsr.C = (cpu.regs[rn] >= op2 +% carry_op);

            const old_rn = cpu.regs[rn];
            cpu.regs[rd] = result;

            cpu.cpsr.V = utils.did_overflow(u32, old_rn, op2, cpu.regs[rd]);
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
            override_carry = true;
        },
        0x8 => {
            // TST
            // TODO carryflag
            const result = cpu.regs[rn] & op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(result);
        },
        0x9 => {
            // TEQ
            const result = cpu.regs[rn] ^ op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(result);
        },
        0xa => {
            // CMP
            const result = cpu.regs[rn] -% op2;

            cpu.cpsr.V = utils.did_overflow(u32, cpu.regs[rn], op2, result);
            cpu.cpsr.C = cpu.regs[rn] >= op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(result);
            override_carry = true;
        },
        0xb => {
            // CMN
            const result = cpu.regs[rn] +% op2;

            cpu.cpsr.V = utils.did_overflow(u32, cpu.regs[rn], op2, result);
            cpu.cpsr.C = cpu.regs[rn] >= op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(result);
            override_carry = true;
        },
        0xc => {
            // ORR
            cpu.regs[rd] = cpu.regs[rn] | op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
        },
        0xd => {
            // MOV
            cpu.regs[rd] = op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
        },
        0xe => {
            // BIC
            cpu.regs[rd] = cpu.regs[rn] & ~(op2);
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
        },
        0xf => {
            // MVN
            cpu.regs[rd] = ~op2;
            cpu.cpsr.Z, cpu.cpsr.N = utils.calc_zn_flags(cpu.regs[rd]);
        },
    }

    if (rd == PC) {
        if (s) {
            const spsr = cpu.cpsr.mode.toBank();
            const new_cpsr = cpu.spsr[@intFromEnum(spsr)];
            cpu.changeMode(new_cpsr.mode);
            cpu.cpsr = new_cpsr;
        }
        // don't flush pipeline for invalid CMP/CMN/TST/TEQ
        if (!(opcode >= 0x8 and opcode <= 0xb))
            cpu.flushPipeline();
    } else {
        cpu.regs[PC] += 4;
    }

    utils.print_to_file("{x} carry {}\n", .{ cpu.regs[rd], cpu.cpsr.C });
    return override_carry;
}

fn process_ALU_IMM(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.ALU_IMM = @bitCast(inst);
    const op2 = math.rotr(u32, instruction.nn, @as(u8, instruction.is) * 2);

    const override_carry = process_ALU(instruction.opcode, instruction.rd, instruction.rn, op2, instruction.s, cpu);
    if (instruction.is != 0 and !override_carry) {
        const op2_33 = math.rotr(u33, instruction.nn, @as(u8, instruction.is) * 2);
        cpu.cpsr.C = (op2_33 & (1 << 32)) != 0;
    }
}

fn process_ALU_REG(inst: u32, cpu: *ARM7TDMI) void {
    const instruction: fmts.ALU_REG = @bitCast(inst);

    if (instruction.shift_by_register) {
        if (instruction.rm == PC or instruction.rn == PC) cpu.regs[PC] += 4;
    }

    const rm_val: u32 = cpu.regs[instruction.rm];

    const shift_amnt: u32 = if (instruction.shift_by_register) cpu.regs[(instruction.shift >> 1)] & 0xff else @as(u32, instruction.shift);

    var op2 = rm_val;
    var shift_carry: ?bool = null;
    if (!(instruction.shift_by_register and shift_amnt == 0)) {
        op2, shift_carry = utils.shift(instruction.shift_type, rm_val, shift_amnt, cpu.cpsr.C);
    }

    utils.print_to_file("shift {x} done: {x} by {x}\n", .{ instruction.shift_type, rm_val, shift_amnt });
    const override_carry = process_ALU(instruction.opcode, instruction.rd, instruction.rn, op2, instruction.s, cpu);

    if (!override_carry and shift_carry != null) {
        cpu.cpsr.C = shift_carry.?;
    }

    if (instruction.shift_by_register) {
        if (instruction.rm == PC or instruction.rn == PC) cpu.regs[PC] -= 4;
    }
}
// Undefined
fn process_undefined(_: u32, _: *ARM7TDMI) void {}
