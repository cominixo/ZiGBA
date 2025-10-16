pub const BX = packed struct(u32) {
    rn: u4,
    _: u24,
    cond: u4,
};

pub const BDT = packed struct(u32) {
    reg_list: u16,
    rn: u4,
    is_load: bool,
    writeback: bool,
    s: bool,
    is_up: bool,
    is_pre: bool,
    _: u3,
    cond: u4,
};

pub const B = packed struct(u32) {
    offset: u24,
    link: bool,
    _: u3,
    cond: u4,
};

pub const SWI = packed struct(u32) {
    comment: u24,
    _: u4,
    cond: u4,
};

pub const SDT_OFFSET_REG = packed struct(u12) {
    shift_amnt: u5,
    shift_type: u2,
    _: u1,
    rm: u4,
};

pub const SDT = packed struct(u32) {
    offset: u12, // if reg offset bitcast to SDT_OFFSET_REG
    rd: u4,
    rn: u4,
    is_load: bool,
    writeback: bool,
    is_byte: bool,
    is_up: bool,
    is_pre: bool,
    is_immediate: bool,
    _: u2,
    cond: u4,
};

pub const SWP = packed struct(u32) {
    rm: u4,
    _unused1: u8,
    rd: u4,
    rn: u4,
    _unused2: u2,
    b: u1,
    _unused3: u5,
    cond: u4,
};

pub const MUL = packed struct(u32) {
    rm: u4,
    _res: u4,
    rs: u4,
    rn: u4,
    rd: u4,
    set_condition: bool,
    accumulate: bool,
    _: u6,
    cond: u4,
};

pub const MULL = packed struct(u32) {
    rm: u4,
    _unused1: u4,
    rs: u4,
    rdlo: u4,
    rdhi: u4,
    s: u1,
    a: u1,
    u: u1,
    _unused2: u5,
    cond: u4,
};

pub const ALU_IMM = packed struct(u32) {
    nn: u8,
    is: u4,
    rd: u4,
    rn: u4,
    s: bool,
    opcode: u4,
    is_immediate: bool,
    _: u2,
    cond: u4,
};

pub const ALU_REG = packed struct(u32) {
    rm: u4,
    shift_by_register: bool,
    shift_type: u2,
    shift: u5, // can be register or immediate
    rd: u4,
    rn: u4,
    s: bool,
    opcode: u4,
    is_immediate: bool,
    _: u2,
    cond: u4,
};

pub const HDT = packed struct(u32) {
    offset_lo: u4,
    _res: u1,
    opcode: u2,
    _res2: u1,
    offset_hi: u4,
    rd: u4,
    rn: u4,
    is_load: bool,
    writeback: bool,
    is_immediate: bool,
    is_up: bool,
    is_pre: bool,
    _: u3,
    cond: u4,
};

pub const B_BL = packed struct(u32) {
    offset: i24,
    opcode: u1,
    _: u3,
    cond: u4,
};

pub const MSR_REG = packed struct(u32) {};

pub const MSR_IMM = packed struct(u32) {
    imm: u8,
    rot: u4,
    _: u4,
    c: bool,
    x: bool,
    s: bool,
    f: bool,
    _res: u2,
    destination: u1,
    _res2: u5,
    cond: u4,
};
