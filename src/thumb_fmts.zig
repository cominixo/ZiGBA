pub const HI_BX = packed struct(u16) {
    rd_lo: u3,
    rs_lo: u3,
    rs_hi: u1,
    rd_hi: u1,
    opcode: u2,
    _: u6,
};

pub const ADD_SUB = packed struct(u16) {
    rd: u3,
    rs: u3,
    operand: u3,
    opcode: u2,
    _: u5,
};

pub const MOV_CMP = packed struct(u16) {
    nn: u8,
    rd: u3,
    opcode: u2,
    _: u3,
};

pub const REL_ADDR = packed struct(u16) {
    nn: u8,
    rd: u3,
    sp_source: bool,
    _: u4,
};
