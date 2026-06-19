const std = @import("std");
const addr = @import("addr.zig");
const Bus = @import("bus.zig").Bus;

// ── Flag Register ────────────────────────────────────────────────────

pub const FlagRegister = packed struct {
    _unused: u4,
    carry: u1,
    half_carry: u1,
    subtract: u1,
    zero: u1,

    pub fn setZero(self: *FlagRegister, v: bool) void  { self.zero = @intFromBool(v); }
    pub fn setSub(self: *FlagRegister, v: bool) void   { self.subtract = @intFromBool(v); }
    pub fn setHalf(self: *FlagRegister, v: bool) void  { self.half_carry = @intFromBool(v); }
    pub fn setCarry(self: *FlagRegister, v: bool) void { self.carry = @intFromBool(v); }
};

comptime {
    std.debug.assert(@sizeOf(FlagRegister) == 1);
}

// ── Registers ────────────────────────────────────────────────────────

pub const Registers = packed struct {
    a: u8,
    f: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    sp: u16,
    pc: u16,

    pub fn getAf(self: *const Registers) u16 {
        return (@as(u16, self.a) << 8) | @as(u16, self.f & addr.FLAG_MASK);
    }

    pub fn setAf(self: *Registers, value: u16) void {
        self.a = @truncate(value >> 8);
        self.f = @as(u8, @truncate(value)) & addr.FLAG_MASK;
    }

    pub fn getBc(self: *const Registers) u16 {
        return (@as(u16, self.b) << 8) | @as(u16, self.c);
    }

    pub fn setBc(self: *Registers, value: u16) void {
        self.b = @truncate(value >> 8);
        self.c = @truncate(value);
    }

    pub fn getDe(self: *const Registers) u16 {
        return (@as(u16, self.d) << 8) | @as(u16, self.e);
    }

    pub fn setDe(self: *Registers, value: u16) void {
        self.d = @truncate(value >> 8);
        self.e = @truncate(value);
    }

    pub fn getHl(self: *const Registers) u16 {
        return (@as(u16, self.h) << 8) | @as(u16, self.l);
    }

    pub fn setHl(self: *Registers, value: u16) void {
        self.h = @truncate(value >> 8);
        self.l = @truncate(value);
    }

    pub fn getFlags(self: *const Registers) FlagRegister {
        return @bitCast(self.f);
    }

    pub fn setFlags(self: *Registers, flags: FlagRegister) void {
        self.f = @as(u8, @bitCast(flags)) & addr.FLAG_MASK;
    }
};

comptime {
    std.debug.assert(@sizeOf(Registers) == 16);
}

// ── Register Enums ───────────────────────────────────────────────────

pub const R8 = enum(u3) {
    b = 0x00,
    c = 0x01,
    d = 0x02,
    e = 0x03,
    h = 0x04,
    l = 0x05,
    a = 0x07,
};

pub const R16Load = enum(u2) {
    bc = 0x00,
    de = 0x01,
    hl = 0x02,
    sp = 0x03,
};

pub const R16Stack = enum(u2) {
    bc = 0x00,
    de = 0x01,
    hl = 0x02,
    af = 0x03,
};

pub const Cond = enum(u2) {
    nz = 0x00,
    z = 0x01,
    nc = 0x02,
    c = 0x03,
};

// ── Instruction Tag ──────────────────────────────────────────────────

pub const InstTag = enum(u8) {
    nop,
    ld_r16_imm16,
    ld_r8_imm8,
    ld_r8_r8,
    ld_r16_a,
    ld_a_r16,
    ld_a_c,
    ld_c_a,
    ld_a_imm16,
    ld_imm16_a,
    ld_hl_plus_a,
    ld_hl_minus_a,
    ld_hl_sp_rel,
    ld_sp_hl,
    inc_r16,
    dec_r16,
    inc_r8,
    dec_r8,
    inc_hl,
    dec_hl,
    add_a_r8,
    adc_a_r8,
    sub_a_r8,
    sbc_a_r8,
    and_a_r8,
    xor_a_r8,
    or_a_r8,
    cp_a_r8,
    add_a_imm8,
    adc_a_imm8,
    sub_a_imm8,
    sbc_a_imm8,
    and_a_imm8,
    xor_a_imm8,
    or_a_imm8,
    cp_a_imm8,
    add_hl_r16,
    add_sp_rel,
    jp_imm16,
    jp_hl,
    jp_cond,
    jr_rel,
    jr_cond,
    call_imm16,
    call_cond,
    ret,
    ret_cond,
    reti,
    rst_vec,
    push_r16,
    pop_r16,
    halt,
    stop,
    ei,
    di,
    daa,
    cpl,
    scf,
    ccf,
    rlca,
    rrca,
    rla,
    rra,
    ld_ff_c_a,
    ld_a_ff_c,
    ld_ff_imm8_a,
    ld_a_ff_imm8,
    cb_prefix,
    invalid,
};

// ── Opcode Entry ─────────────────────────────────────────────────────

pub const OpcodeEntry = struct {
    tag: InstTag,
    length: u3,
    mcycles_taken: u4,
    mcycles_not_taken: u4,
};

// ── Main Opcode Table (256 entries) ──────────────────────────────────

fn decodeMain(opcode: u8) OpcodeEntry {
    return switch (opcode) {
        // 0x00-0x0F
        0x00 => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x01 => .{ .tag = .ld_r16_imm16, .length = 3, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0x02 => .{ .tag = .ld_r16_a, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x03 => .{ .tag = .inc_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x04 => .{ .tag = .inc_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x05 => .{ .tag = .dec_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x06 => .{ .tag = .ld_r8_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x07 => .{ .tag = .rlca, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x08 => .{ .tag = .ld_imm16_a, .length = 3, .mcycles_taken = 5, .mcycles_not_taken = 5 },
        0x09 => .{ .tag = .add_hl_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x0A => .{ .tag = .ld_a_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x0B => .{ .tag = .dec_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x0C => .{ .tag = .inc_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x0D => .{ .tag = .dec_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x0E => .{ .tag = .ld_r8_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x0F => .{ .tag = .rrca, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },

        // 0x10-0x1F
        0x10 => .{ .tag = .stop, .length = 2, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x11 => .{ .tag = .ld_r16_imm16, .length = 3, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0x12 => .{ .tag = .ld_r16_a, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x13 => .{ .tag = .inc_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x14 => .{ .tag = .inc_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x15 => .{ .tag = .dec_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x16 => .{ .tag = .ld_r8_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x17 => .{ .tag = .rla, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x18 => .{ .tag = .jr_rel, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0x19 => .{ .tag = .add_hl_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x1A => .{ .tag = .ld_a_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x1B => .{ .tag = .dec_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x1C => .{ .tag = .inc_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x1D => .{ .tag = .dec_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x1E => .{ .tag = .ld_r8_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x1F => .{ .tag = .rra, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },

        // 0x20-0x2F
        0x20 => .{ .tag = .jr_cond, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 2 },
        0x21 => .{ .tag = .ld_r16_imm16, .length = 3, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0x22 => .{ .tag = .ld_hl_plus_a, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x23 => .{ .tag = .inc_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x24 => .{ .tag = .inc_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x25 => .{ .tag = .dec_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x26 => .{ .tag = .ld_r8_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x27 => .{ .tag = .daa, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x28 => .{ .tag = .jr_cond, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 2 },
        0x29 => .{ .tag = .add_hl_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x2A => .{ .tag = .ld_a_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x2B => .{ .tag = .dec_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x2C => .{ .tag = .inc_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x2D => .{ .tag = .dec_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x2E => .{ .tag = .ld_r8_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x2F => .{ .tag = .cpl, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },

        // 0x30-0x3F
        0x30 => .{ .tag = .jr_cond, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 2 },
        0x31 => .{ .tag = .ld_r16_imm16, .length = 3, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0x32 => .{ .tag = .ld_hl_minus_a, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x33 => .{ .tag = .inc_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x34 => .{ .tag = .inc_hl, .length = 1, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0x35 => .{ .tag = .dec_hl, .length = 1, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0x36 => .{ .tag = .ld_r8_imm8, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0x37 => .{ .tag = .scf, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x38 => .{ .tag = .jr_cond, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 2 },
        0x39 => .{ .tag = .add_hl_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x3A => .{ .tag = .ld_a_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x3B => .{ .tag = .dec_r16, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x3C => .{ .tag = .inc_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x3D => .{ .tag = .dec_r8, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0x3E => .{ .tag = .ld_r8_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0x3F => .{ .tag = .ccf, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },

        // 0x40-0x7F: LD r8, r8 (with HALT at 0x76)
        0x40...0x7F => {
            // HALT, not LD (HL), (HL)
            if (opcode == addr.OP_HALT) {
                return .{ .tag = .halt, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 };
            }
            const dst: u4 = (opcode >> 3) & addr.REG_MASK;
            const src: u4 = opcode & addr.REG_MASK;
            const mcycles: u4 = if (dst == addr.REG_HL or src == addr.REG_HL) 2 else 1;
            return .{ .tag = .ld_r8_r8, .length = 1, .mcycles_taken = mcycles, .mcycles_not_taken = mcycles };
        },

        // 0x80-0xBF: ALU on A from r8
        0x80...0xBF => {
            const alu_base: u8 = (opcode >> 3) & addr.ALU_OP_MASK; // which ALU op
            const src: u3 = @truncate(opcode & addr.REG_MASK);
            _ = alu_base;
            const mcycles: u4 = if (src == addr.REG_HL) 2 else 1;
            const tag: InstTag = switch ((opcode >> 3) & addr.ALU_GROUP_MASK) {
                addr.ALU_GROUP_ADD...addr.ALU_GROUP_ADD + 0x07 => .add_a_r8,
                addr.ALU_GROUP_ADC...addr.ALU_GROUP_ADC + 0x07 => .adc_a_r8,
                addr.ALU_GROUP_SUB...addr.ALU_GROUP_SUB + 0x07 => .sub_a_r8,
                addr.ALU_GROUP_SBC...addr.ALU_GROUP_SBC + 0x07 => .sbc_a_r8,
                addr.ALU_GROUP_AND...addr.ALU_GROUP_AND + 0x07 => .and_a_r8,
                addr.ALU_GROUP_XOR...addr.ALU_GROUP_XOR + 0x07 => .xor_a_r8,
                addr.ALU_GROUP_OR...addr.ALU_GROUP_OR + 0x07 => .or_a_r8,
                addr.ALU_GROUP_CP...addr.ALU_GROUP_CP + 0x07 => .cp_a_r8,
                else => unreachable,
            };
            return .{ .tag = tag, .length = 1, .mcycles_taken = mcycles, .mcycles_not_taken = mcycles };
        },

        // 0xC0-0xFF
        0xC0 => .{ .tag = .ret_cond, .length = 1, .mcycles_taken = 5, .mcycles_not_taken = 2 },
        0xC1 => .{ .tag = .pop_r16, .length = 1, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0xC2 => .{ .tag = .jp_cond, .length = 3, .mcycles_taken = 4, .mcycles_not_taken = 3 },
        0xC3 => .{ .tag = .jp_imm16, .length = 3, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xC4 => .{ .tag = .call_cond, .length = 3, .mcycles_taken = 6, .mcycles_not_taken = 3 },
        0xC5 => .{ .tag = .push_r16, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xC6 => .{ .tag = .add_a_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xC7 => .{ .tag = .rst_vec, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xC8 => .{ .tag = .ret_cond, .length = 1, .mcycles_taken = 5, .mcycles_not_taken = 2 },
        0xC9 => .{ .tag = .ret, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xCA => .{ .tag = .jp_cond, .length = 3, .mcycles_taken = 4, .mcycles_not_taken = 3 },
        0xCB => .{ .tag = .cb_prefix, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xCC => .{ .tag = .call_cond, .length = 3, .mcycles_taken = 6, .mcycles_not_taken = 3 },
        0xCD => .{ .tag = .call_imm16, .length = 3, .mcycles_taken = 6, .mcycles_not_taken = 6 },
        0xCE => .{ .tag = .adc_a_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xCF => .{ .tag = .rst_vec, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },

        0xD0 => .{ .tag = .ret_cond, .length = 1, .mcycles_taken = 5, .mcycles_not_taken = 2 },
        0xD1 => .{ .tag = .pop_r16, .length = 1, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0xD2 => .{ .tag = .jp_cond, .length = 3, .mcycles_taken = 4, .mcycles_not_taken = 3 },
        0xD3 => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xD4 => .{ .tag = .call_cond, .length = 3, .mcycles_taken = 6, .mcycles_not_taken = 3 },
        0xD5 => .{ .tag = .push_r16, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xD6 => .{ .tag = .sub_a_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xD7 => .{ .tag = .rst_vec, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xD8 => .{ .tag = .ret_cond, .length = 1, .mcycles_taken = 5, .mcycles_not_taken = 2 },
        0xD9 => .{ .tag = .reti, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xDA => .{ .tag = .jp_cond, .length = 3, .mcycles_taken = 4, .mcycles_not_taken = 3 },
        0xDB => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xDC => .{ .tag = .call_cond, .length = 3, .mcycles_taken = 6, .mcycles_not_taken = 3 },
        0xDD => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xDE => .{ .tag = .sbc_a_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xDF => .{ .tag = .rst_vec, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },

        0xE0 => .{ .tag = .ld_ff_imm8_a, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0xE1 => .{ .tag = .pop_r16, .length = 1, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0xE2 => .{ .tag = .ld_ff_c_a, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xE3 => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xE4 => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xE5 => .{ .tag = .push_r16, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xE6 => .{ .tag = .and_a_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xE7 => .{ .tag = .rst_vec, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xE8 => .{ .tag = .add_sp_rel, .length = 2, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xE9 => .{ .tag = .jp_hl, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xEA => .{ .tag = .ld_imm16_a, .length = 3, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xEB => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xEC => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xED => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xEE => .{ .tag = .xor_a_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xEF => .{ .tag = .rst_vec, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },

        0xF0 => .{ .tag = .ld_a_ff_imm8, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0xF1 => .{ .tag = .pop_r16, .length = 1, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0xF2 => .{ .tag = .ld_a_ff_c, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xF3 => .{ .tag = .di, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xF4 => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xF5 => .{ .tag = .push_r16, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xF6 => .{ .tag = .or_a_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xF7 => .{ .tag = .rst_vec, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xF8 => .{ .tag = .ld_hl_sp_rel, .length = 2, .mcycles_taken = 3, .mcycles_not_taken = 3 },
        0xF9 => .{ .tag = .ld_sp_hl, .length = 1, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xFA => .{ .tag = .ld_a_imm16, .length = 3, .mcycles_taken = 4, .mcycles_not_taken = 4 },
        0xFB => .{ .tag = .ei, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xFC => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xFD => .{ .tag = .nop, .length = 1, .mcycles_taken = 1, .mcycles_not_taken = 1 },
        0xFE => .{ .tag = .cp_a_imm8, .length = 2, .mcycles_taken = 2, .mcycles_not_taken = 2 },
        0xFF => .{ .tag = .rst_vec, .length = 1, .mcycles_taken = 4, .mcycles_not_taken = 4 },
    };
}

pub const main_table: [256]OpcodeEntry = blk: {
    @setEvalBranchQuota(10000);
    var table: [256]OpcodeEntry = undefined;
    for (&table, 0..) |*entry, i| {
        entry.* = decodeMain(@intCast(i));
    }
    break :blk table;
};

// ── CB Opcode Table (256 entries) ────────────────────────────────────

// CB opcodes: RLC/RRC/RL/RR/SLA/SRA/SWAP/SRL (0x00-0x3F),
// BIT (0x40-0x7F), RES (0x80-0xBF), SET (0xC0-0xFF)
// Register variants: 2 M-cycles, (HL) variants: 4 M-cycles

pub const cb_table: [256]OpcodeEntry = blk: {
    @setEvalBranchQuota(10000);
    var table: [256]OpcodeEntry = undefined;
    for (&table, 0..) |*entry, i| {
        const is_hl = (i & addr.REG_MASK) == addr.REG_HL;
        const mcycles: u4 = if (is_hl) 4 else 2;
        entry.* = .{ .tag = .nop, .length = 2, .mcycles_taken = mcycles, .mcycles_not_taken = mcycles };
    }
    break :blk table;
};

// ── CPU Struct ───────────────────────────────────────────────────────

pub const Cpu = struct {
    regs: Registers,
    ime: bool,
    ime_next: bool,
    halted: bool,
    halt_bug: bool,
    bus: *Bus,
    ime_enable_pending: bool,
    stop: bool,

    pub fn init(bus: *Bus) Cpu {
        return Cpu{
            .regs = .{
                .a = addr.A_RESET,
                .f = addr.F_RESET,
                .b = addr.B_RESET,
                .c = addr.C_RESET,
                .d = addr.D_RESET,
                .e = addr.E_RESET,
                .h = addr.H_RESET,
                .l = addr.L_RESET,
                .sp = addr.SP_RESET,
                .pc = addr.PC_RESET,
            },
            .ime = false,
            .ime_next = false,
            .halted = false,
            .halt_bug = false,
            .bus = bus,
            .ime_enable_pending = false,
            .stop = false,
        };
    }

    pub fn fetchDecode(self: *Cpu) OpcodeEntry {
        const pc = self.regs.pc;

        if (self.halt_bug) {
            self.halt_bug = false;
            // Re-read the same PC (don't advance) — the byte after HALT gets re-decoded
            return main_table[self.bus.read8(pc)];
        }

        const opcode = self.bus.read8(pc);
        self.regs.pc +%= 1;
        return main_table[opcode];
    }

    pub fn stepInstruction(self: *Cpu) void {
        if (self.stop) {
            _ = self.bus.tick(1);
            return;
        }

        if (self.halted) {
            _ = self.bus.tick(1);
            if (self.bus.hasInterruptRequest()) {
                self.halted = false;
                if (self.ime) {
                    self.handleInterrupts();
                }
            }
            return;
        }

        const entry = self.fetchDecode();

        if (entry.tag == .cb_prefix) {
            const pc = self.regs.pc;
            const cb_opcode = self.bus.read8(pc);
            self.regs.pc +%= 1;
            const cb_entry = cb_table[cb_opcode];
            self.executeCb(cb_opcode);
            self.applyInterruptDelay();
            self.bus.tick(cb_entry.mcycles_taken);
            return;
        }

        var actual_mcycles = entry.mcycles_taken;

        // HALT handling — must check before general execution
        if (entry.tag == .halt) {
            const ie = self.bus.read8(addr.IE_ADDR);
            const intf = self.bus.readIF();
            if ((ie & intf & addr.INTERRUPT_MASK) != 0 and !self.ime) {
                self.halt_bug = true;
            } else {
                self.halted = true;
            }
        }

        if (entry.tag == .ret_cond or entry.tag == .jp_cond or entry.tag == .call_cond or entry.tag == .jr_cond) {
            const opcode = self.bus.read8(self.regs.pc - 1);
            const cond: Cond = @enumFromInt((opcode >> 3) & addr.COND_MASK);
            const condition_met = self.checkCondition(cond);
            if (!condition_met) {
                actual_mcycles = entry.mcycles_not_taken;
            }
            self.maybeBranchWithCond(entry.tag, cond, condition_met);
        } else {
            self.execute(entry.tag);
        }

        self.applyInterruptDelay();

        if (!self.halted) {
            if (self.ime) {
                self.handleInterrupts();
            }
        }

        self.bus.tick(actual_mcycles);
    }

    pub fn stepMCycle(self: *Cpu) void {
        // Fine-grained stepping not fully implemented in Phase 1;
        // delegate to stepInstruction for now.
        self.stepInstruction();
    }

    pub fn getPc(self: *const Cpu) u16 {
        return self.regs.pc;
    }

    fn checkCondition(self: *Cpu, cond: Cond) bool {
        const flags = self.regs.getFlags();
        return switch (cond) {
            .nz => flags.zero == 0,
            .z => flags.zero == 1,
            .nc => flags.carry == 0,
            .c => flags.carry == 1,
        };
    }

    fn applyInterruptDelay(self: *Cpu) void {
        if (self.ime_enable_pending) {
            self.ime = true;
            self.ime_enable_pending = false;
        }
        self.ime = self.ime_next;
    }

    pub fn handleInterrupts(self: *Cpu) void {
        const ie = self.bus.read8(addr.IE_ADDR);
        var intf = self.bus.readIF();
        const pending = ie & intf & addr.INTERRUPT_MASK;
        if (pending == 0) return;

        const bit = @ctz(pending);
        self.ime = false;
        self.ime_next = false;
        self.halted = false;

        const vector: u16 = switch (bit) {
            0 => addr.VEC_VBLANK,
            1 => addr.VEC_STAT,
            2 => addr.VEC_TIMER,
            3 => addr.VEC_SERIAL,
            4 => addr.VEC_JOYPAD,
            else => unreachable,
        };

        // Push PC to stack
        self.regs.sp -%= 2;
        self.bus.write8(self.regs.sp, @truncate(self.regs.pc & addr.LOW_BYTE_MASK));
        self.bus.write8(self.regs.sp + 1, @truncate(self.regs.pc >> addr.HIGH_BYTE_SHIFT));

        // Clear the interrupt flag bit
        intf &= ~(@as(u8, 1) << @intCast(bit));
        self.bus.writeIF(intf);

        self.regs.pc = vector;
    }

    fn execute(self: *Cpu, tag: InstTag) void {
        const regs = &self.regs;
        switch (tag) {
            .nop => {},
            .halt => {},
            .stop => { self.stop = true; },
            .ei => { self.ime_next = true; self.ime_enable_pending = true; },
            .di => { self.ime_next = false; self.ime = false; },
            .reti => {
                self.ime_next = true;
                const lo = self.bus.read8(regs.sp);
                const hi = self.bus.read8(regs.sp + 1);
                regs.sp +%= 2;
                regs.pc = (@as(u16, hi) << 8) | lo;
            },
            .ret => {
                const lo = self.bus.read8(regs.sp);
                const hi = self.bus.read8(regs.sp + 1);
                regs.sp +%= 2;
                regs.pc = (@as(u16, hi) << 8) | lo;
            },
            .jp_imm16 => {
                const lo = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const hi = self.bus.read8(regs.pc);
                regs.pc = (@as(u16, hi) << 8) | lo;
            },
            .jp_hl => {
                regs.pc = regs.getHl();
            },
            .jr_rel => {
                const offset = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                regs.pc = @addWithOverflow(regs.pc, @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(offset))))))[0];
            },
            .call_imm16 => {
                const lo = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const hi = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const abs_addr = (@as(u16, hi) << 8) | lo;
                regs.sp -%= 2;
                self.bus.write8(regs.sp, @truncate(regs.pc & addr.LOW_BYTE_MASK));
                self.bus.write8(regs.sp + 1, @truncate(regs.pc >> addr.HIGH_BYTE_SHIFT));
                regs.pc = abs_addr;
            },
            .rst_vec => {
                const vec_byte = self.bus.read8(regs.pc - 1);
                const vec: u16 = switch (vec_byte) {
                    addr.OP_RST_00 => addr.RST_00,
                    addr.OP_RST_08 => addr.RST_08,
                    addr.OP_RST_10 => addr.RST_10,
                    addr.OP_RST_18 => addr.RST_18,
                    addr.OP_RST_20 => addr.RST_20,
                    addr.OP_RST_28 => addr.RST_28,
                    addr.OP_RST_30 => addr.RST_30,
                    addr.OP_RST_38 => addr.RST_38,
                    else => unreachable,
                };
                regs.sp -%= 2;
                self.bus.write8(regs.sp, @truncate(regs.pc & addr.LOW_BYTE_MASK));
                self.bus.write8(regs.sp + 1, @truncate(regs.pc >> addr.HIGH_BYTE_SHIFT));
                regs.pc = vec;
            },
            .push_r16 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const pair: R16Stack = @enumFromInt((opcode >> 4) & addr.PAIR_MASK);
                const value: u16 = switch (pair) {
                    .bc => regs.getBc(),
                    .de => regs.getDe(),
                    .hl => regs.getHl(),
                    .af => regs.getAf(),
                };
                regs.sp -%= 2;
                self.bus.write8(regs.sp, @truncate(value & 0xFF));
                self.bus.write8(regs.sp + 1, @truncate(value >> 8));
            },
            .pop_r16 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const pair: R16Stack = @enumFromInt((opcode >> 4) & addr.PAIR_MASK);
                const lo = self.bus.read8(regs.sp);
                const hi = self.bus.read8(regs.sp + 1);
                regs.sp +%= 2;
                const value = (@as(u16, hi) << 8) | lo;
                switch (pair) {
                    .bc => regs.setBc(value),
                    .de => regs.setDe(value),
                    .hl => regs.setHl(value),
                    .af => regs.setAf(value),
                }
            },
            .ld_r16_imm16 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const pair: R16Load = @enumFromInt((opcode >> 4) & addr.PAIR_MASK);
                const lo = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const hi = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const value = (@as(u16, hi) << 8) | lo;
                switch (pair) {
                    .bc => regs.setBc(value),
                    .de => regs.setDe(value),
                    .hl => regs.setHl(value),
                    .sp => regs.sp = value,
                }
            },
            .ld_r8_imm8 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                if (opcode == addr.OP_LD_HL_IMM8) {
                    self.bus.write8(regs.getHl(), val);
                } else {
                    const r8_idx_imm: u3 = @truncate((opcode >> 3) & addr.REG_MASK);
                    const r8_imm: R8 = @enumFromInt(r8_idx_imm);
                    setR8Value(regs, r8_imm, val);
                }
            },
            .ld_r8_r8 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const dst_idx: u3 = @truncate((opcode >> 3) & addr.REG_MASK);
                const src_idx: u3 = @truncate(opcode & addr.REG_MASK);
                if (dst_idx == addr.REG_HL) {
                    const val = getR8Value(regs, @enumFromInt(src_idx), self.bus);
                    self.bus.write8(regs.getHl(), val);
                } else if (src_idx == addr.REG_HL) {
                    const val = self.bus.read8(regs.getHl());
                    setR8Value(regs, @enumFromInt(dst_idx), val);
                } else {
                    const val = getR8Value(regs, @enumFromInt(src_idx), self.bus);
                    setR8Value(regs, @enumFromInt(dst_idx), val);
                }
            },
            .ld_r16_a => {
                const opcode = self.bus.read8(regs.pc - 1);
                const target: u16 = switch (opcode) {
                    addr.OP_LD_BC_A => regs.getBc(),
                    addr.OP_LD_DE_A => regs.getDe(),
                    else => unreachable,
                };
                self.bus.write8(target, regs.a);
            },
            .ld_a_r16 => {
                const opcode = self.bus.read8(regs.pc - 1);
                switch (opcode) {
                    addr.OP_LD_A_BC => regs.a = self.bus.read8(regs.getBc()),
                    addr.OP_LD_A_DE => regs.a = self.bus.read8(regs.getDe()),
                    addr.OP_LD_A_HLI => {
                        const hl = regs.getHl();
                        regs.a = self.bus.read8(hl);
                        regs.setHl(hl +% 1);
                    },
                    addr.OP_LD_A_HLD => {
                        const hl = regs.getHl();
                        regs.a = self.bus.read8(hl);
                        regs.setHl(hl -% 1);
                    },
                    else => unreachable,
                }
            },
            .ld_hl_plus_a => {
                const hl = regs.getHl();
                self.bus.write8(hl, regs.a);
                regs.setHl(hl +% 1);
            },
            .ld_hl_minus_a => {
                const hl = regs.getHl();
                self.bus.write8(hl, regs.a);
                regs.setHl(hl -% 1);
            },
            .ld_a_imm16 => {
                const lo = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const hi = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const abs_addr = (@as(u16, hi) << 8) | lo;
                regs.a = self.bus.read8(abs_addr);
            },
            .ld_imm16_a => {
                const opcode = self.bus.read8(regs.pc - 1);
                const prev_pc = regs.pc;
                _ = prev_pc;
                const lo = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const hi = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const abs_addr = (@as(u16, hi) << 8) | lo;
                if (opcode == addr.OP_LD_IMM16_SP) {
                    self.bus.write8(abs_addr, @truncate(regs.sp & 0xFF));
                    self.bus.write8(abs_addr + 1, @truncate(regs.sp >> 8));
                } else {
                    self.bus.write8(abs_addr, regs.a);
                }
            },
            .inc_r16 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const pair: R16Load = @enumFromInt((opcode >> 4) & addr.PAIR_MASK);
                switch (pair) {
                    .bc => regs.setBc(regs.getBc() +% 1),
                    .de => regs.setDe(regs.getDe() +% 1),
                    .hl => regs.setHl(regs.getHl() +% 1),
                    .sp => regs.sp +%= 1,
                }
            },
            .dec_r16 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const pair: R16Load = @enumFromInt((opcode >> 4) & addr.PAIR_MASK);
                switch (pair) {
                    .bc => regs.setBc(regs.getBc() -% 1),
                    .de => regs.setDe(regs.getDe() -% 1),
                    .hl => regs.setHl(regs.getHl() -% 1),
                    .sp => regs.sp -%= 1,
                }
            },
            .inc_r8 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const r8_idx_inc: u3 = @truncate((opcode >> 3) & addr.REG_MASK);
                if (r8_idx_inc == addr.REG_HL) {
                    // INC (HL)
                    const hl = regs.getHl();
                    const val = self.bus.read8(hl);
                    const result = val +% 1;
                    self.bus.write8(hl, result);
                    var flags = regs.getFlags();
                    flags.setZero(result == 0);
                    flags.setSub(false);
                    flags.setHalf((val & addr.LOW_4_BITS) + 1 > addr.LOW_4_BITS);
                    regs.setFlags(flags);
                } else {
                    const r8_inc: R8 = @enumFromInt(r8_idx_inc);
                    const val = getR8Value(regs, r8_inc, self.bus);
                    const result = val +% 1;
                    setR8Value(regs, r8_inc, result);
                    var flags = regs.getFlags();
                    flags.setZero(result == 0);
                    flags.setSub(false);
                    flags.setHalf((val & addr.LOW_4_BITS) + 1 > addr.LOW_4_BITS);
                    regs.setFlags(flags);
                }
            },
            .dec_r8 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const r8_idx_dec: u3 = @truncate((opcode >> 3) & addr.REG_MASK);
                if (r8_idx_dec == addr.REG_HL) {
                    // DEC (HL)
                    const hl = regs.getHl();
                    const val = self.bus.read8(hl);
                    const result = val -% 1;
                    self.bus.write8(hl, result);
                    var flags = regs.getFlags();
                    flags.setZero(result == 0);
                    flags.setSub(true);
                    flags.setHalf((val & addr.LOW_4_BITS) == 0);
                    regs.setFlags(flags);
                } else {
                    const r8_dec: R8 = @enumFromInt(r8_idx_dec);
                    const val = getR8Value(regs, r8_dec, self.bus);
                    const result = val -% 1;
                    setR8Value(regs, r8_dec, result);
                    var flags = regs.getFlags();
                    flags.setZero(result == 0);
                    flags.setSub(true);
                    flags.setHalf((val & addr.LOW_4_BITS) == 0);
                    regs.setFlags(flags);
                }
            },
            .inc_hl => {
                const hl = regs.getHl();
                const val = self.bus.read8(hl);
                const result = val +% 1;
                self.bus.write8(hl, result);
                var flags = regs.getFlags();
                flags.setZero(result == 0);
                flags.setSub(false);
                flags.setHalf((val & addr.LOW_4_BITS) + 1 > addr.LOW_4_BITS);
                regs.setFlags(flags);
            },
            .dec_hl => {
                const hl = regs.getHl();
                const val = self.bus.read8(hl);
                const result = val -% 1;
                self.bus.write8(hl, result);
                var flags = regs.getFlags();
                flags.setZero(result == 0);
                flags.setSub(true);
                flags.setHalf((val & addr.LOW_4_BITS) == 0);
                regs.setFlags(flags);
            },
            .add_a_r8 => { self.execAluR8(.add, false); },
            .adc_a_r8 => { self.execAluR8(.add, true); },
            .sub_a_r8 => { self.execAluR8(.sub, false); },
            .sbc_a_r8 => { self.execAluR8(.sub, true); },
            .and_a_r8 => { self.execAluR8(.alu_and, false); },
            .xor_a_r8 => { self.execAluR8(.xor, false); },
            .or_a_r8 => { self.execAluR8(.alu_or, false); },
            .cp_a_r8 => { self.execAluR8(.cp, false); },
            .add_a_imm8 => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                execAluOp(regs, .add, val, false);
            },
            .adc_a_imm8 => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                execAluOp(regs, .add, val, true);
            },
            .sub_a_imm8 => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                execAluOp(regs, .sub, val, false);
            },
            .sbc_a_imm8 => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                execAluOp(regs, .sub, val, true);
            },
            .and_a_imm8 => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                regs.a &= val;
                var flags = regs.getFlags();
                flags.setZero(regs.a == 0);
                flags.setSub(false);
                flags.setHalf(true);
                flags.setCarry(false);
                regs.setFlags(flags);
            },
            .xor_a_imm8 => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                regs.a ^= val;
                var flags = regs.getFlags();
                flags.setZero(regs.a == 0);
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(false);
                regs.setFlags(flags);
            },
            .or_a_imm8 => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                regs.a |= val;
                var flags = regs.getFlags();
                flags.setZero(regs.a == 0);
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(false);
                regs.setFlags(flags);
            },
            .cp_a_imm8 => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                execCp(regs, val);
            },
            .add_hl_r16 => {
                const opcode = self.bus.read8(regs.pc - 1);
                const pair: R16Load = @enumFromInt((opcode >> 4) & addr.PAIR_MASK);
                const hl = regs.getHl();
                const add_val: u16 = switch (pair) {
                    .bc => regs.getBc(),
                    .de => regs.getDe(),
                    .hl => regs.getHl(),
                    .sp => regs.sp,
                };
                const result = @addWithOverflow(hl, add_val);
                var flags = regs.getFlags();
                flags.setSub(false);
                flags.setHalf(((hl & addr.LOW_12_BITS) + (add_val & addr.LOW_12_BITS)) > addr.LOW_12_BITS);
                flags.carry = @intCast(result[1]);
                regs.setHl(result[0]);
                regs.setFlags(flags);
            },
            .add_sp_rel => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const signed_val = @as(i16, @as(i8, @bitCast(val)));
                const result = @addWithOverflow(regs.sp, @as(u16, @bitCast(signed_val)));
                var flags = regs.getFlags();
                flags.setZero(false);
                flags.setSub(false);
                flags.setHalf((regs.sp & addr.LOW_4_BITS) + (@as(u16, @bitCast(signed_val)) & addr.LOW_4_BITS) > addr.LOW_4_BITS);
                flags.setCarry((regs.sp & addr.LOW_BYTE_MASK) + (@as(u16, @bitCast(signed_val)) & addr.LOW_BYTE_MASK) > addr.LOW_BYTE_MASK);
                regs.sp = result[0];
                regs.setFlags(flags);
            },
            .daa => {
                var a = regs.a;
                const flags = regs.getFlags();
                var adjust: u8 = 0;
                if (flags.subtract == 0) {
                    if (flags.half_carry == 1 or (a & addr.LOW_4_BITS) > addr.DAA_BCD_MAX_LO) adjust |= addr.DAA_ADJUST_LO;
                    if (flags.carry == 1 or a > addr.DAA_MAX_A) adjust |= addr.DAA_ADJUST_HI;
                } else {
                    if (flags.half_carry == 1) adjust |= addr.DAA_ADJUST_LO;
                    if (flags.carry == 1) adjust |= addr.DAA_ADJUST_HI;
                }
                if (flags.subtract == 1) {
                    a -%= adjust;
                } else {
                    a +%= adjust;
                }
                var new_flags = regs.getFlags();
                new_flags.setZero(a == 0);
                new_flags.setHalf(false);
                if (flags.carry == 1 or adjust >= addr.DAA_ADJUST_HI) new_flags.setCarry(true);
                regs.a = a;
                regs.setFlags(new_flags);
            },
            .cpl => {
                regs.a = ~regs.a;
                var flags = regs.getFlags();
                flags.setSub(true);
                flags.setHalf(true);
                regs.setFlags(flags);
            },
            .scf => {
                var flags = regs.getFlags();
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(true);
                regs.setFlags(flags);
            },
            .ccf => {
                var flags = regs.getFlags();
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(flags.carry == 0);
                regs.setFlags(flags);
            },
            .rlca => {
                const carry_val = (regs.a >> addr.BIT_7_SHIFT) & 1;
                regs.a = (regs.a << 1) | @as(u8, carry_val);
                var flags = regs.getFlags();
                flags.setZero(false);
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(carry_val == 1);
                regs.setFlags(flags);
            },
            .rrca => {
                const carry_val = regs.a & 1;
                regs.a = (regs.a >> 1) | @as(u8, carry_val << addr.BIT_7_SHIFT);
                var flags = regs.getFlags();
                flags.setZero(false);
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(carry_val == 1);
                regs.setFlags(flags);
            },
            .rla => {
                const old_carry = regs.getFlags().carry;
                const new_carry_val = (regs.a >> addr.BIT_7_SHIFT) & 1;
                regs.a = (regs.a << 1) | old_carry;
                var flags = regs.getFlags();
                flags.setZero(false);
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(new_carry_val == 1);
                regs.setFlags(flags);
            },
            .rra => {
                const old_carry = regs.getFlags().carry;
                const new_carry_val = regs.a & 1;
                regs.a = (regs.a >> 1) | (@as(u8, old_carry) << addr.BIT_7_SHIFT);
                var flags = regs.getFlags();
                flags.setZero(false);
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(new_carry_val == 1);
                regs.setFlags(flags);
            },
            .ld_ff_c_a => {
                const io_port = addr.IO_BASE | @as(u16, regs.c);
                self.bus.write8(io_port, regs.a);
            },
            .ld_a_ff_c => {
                const io_port = addr.IO_BASE | @as(u16, regs.c);
                regs.a = self.bus.read8(io_port);
            },
            .ld_ff_imm8_a => {
                const offset = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const io_port = addr.IO_BASE | @as(u16, offset);
                self.bus.write8(io_port, regs.a);
            },
            .ld_a_ff_imm8 => {
                const offset = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const io_port = addr.IO_BASE | @as(u16, offset);
                regs.a = self.bus.read8(io_port);
            },
            .ld_hl_sp_rel => {
                const val = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const signed_val = @as(i16, @as(i8, @bitCast(val)));
                const sp = regs.sp;
                const result = @addWithOverflow(sp, @as(u16, @bitCast(signed_val)));
                var flags = regs.getFlags();
                flags.setZero(false);
                flags.setSub(false);
                flags.setHalf((sp & addr.LOW_4_BITS) + (@as(u16, @bitCast(signed_val)) & addr.LOW_4_BITS) > addr.LOW_4_BITS);
                flags.setCarry((sp & 0xFF) + (@as(u16, @bitCast(signed_val)) & 0xFF) > 0xFF);
                regs.setHl(result[0]);
                regs.setFlags(flags);
            },
            .ld_sp_hl => {
                regs.sp = regs.getHl();
            },

            .cb_prefix => unreachable, // handled in stepInstruction
            .jp_cond, .jr_cond, .call_cond, .ret_cond => unreachable, // handled in stepInstruction
            .ld_a_c, .ld_c_a, .invalid => {},
        }
    }

    fn maybeBranchWithCond(self: *Cpu, tag: InstTag, cond: Cond, condition_met: bool) void {
        const regs = &self.regs;
        switch (tag) {
            .jr_cond => {
                const offset = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                if (condition_met) {
                    regs.pc = @addWithOverflow(regs.pc, @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(offset))))))[0];
                }
            },
            .jp_cond => {
                const lo = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const hi = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                if (condition_met) {
                    regs.pc = (@as(u16, hi) << 8) | lo;
                }
            },
            .call_cond => {
                const lo = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                const hi = self.bus.read8(regs.pc);
                regs.pc +%= 1;
                if (condition_met) {
                    const abs_addr = (@as(u16, hi) << 8) | lo;
                    regs.sp -%= 2;
                    self.bus.write8(regs.sp, @truncate(regs.pc & 0xFF));
                    self.bus.write8(regs.sp + 1, @truncate(regs.pc >> 8));
                    regs.pc = abs_addr;
                }
            },
            .ret_cond => {
                _ = cond;
                if (condition_met) {
                    const lo = self.bus.read8(regs.sp);
                    const hi = self.bus.read8(regs.sp + 1);
                    regs.sp +%= 2;
                    regs.pc = (@as(u16, hi) << 8) | lo;
                }
            },
            else => unreachable,
        }
    }

    fn executeCb(self: *Cpu, opcode: u8) void {
        const regs = &self.regs;
        const bit = (opcode >> 3) & addr.REG_MASK;
        const r8_idx: u3 = @truncate(opcode & addr.REG_MASK);
        const is_hl = r8_idx == addr.REG_HL;

        const val = if (is_hl) self.bus.read8(regs.getHl()) else getR8Value(regs, @enumFromInt(r8_idx), self.bus);

        const group = opcode >> addr.CB_GROUP_SHIFT;
        switch (group) {
            0x00, 0x01 => {
                const sub_op = (opcode >> 3) & addr.REG_MASK;
                const result: u8 = switch (sub_op) {
                    0 => blk: { // RLC
                        const c = @as(u1, @truncate(val >> 7));
                        break :blk (val << 1) | @as(u8, c);
                    },
                    1 => blk: { // RRC
                        const c = @as(u1, @truncate(val & 1));
                        break :blk (val >> 1) | (@as(u8, c) << 7);
                    },
                    2 => blk: { // RL
                        break :blk (val << 1) | regs.getFlags().carry;
                    },
                    3 => blk: { // RR
                        break :blk (val >> 1) | (@as(u8, regs.getFlags().carry) << addr.BIT_7_SHIFT);
                    },
                    4 => blk: { // SLA
                        break :blk val << 1;
                    },
                    5 => blk: { // SRA
                        const msb = val & addr.BIT_7_MASK;
                        break :blk (val >> 1) | msb;
                    },
                    6 => blk: { // SWAP
                        break :blk (val << addr.NIBBLE_SHIFT) | (val >> addr.NIBBLE_SHIFT);
                    },
                    7 => blk: { // SRL
                        break :blk val >> 1;
                    },
                    else => unreachable,
                };

                const carry: u1 = switch (sub_op) {
                    0 => @truncate(val >> 7),
                    1 => @truncate(val & 1),
                    2 => @truncate(val >> 7),
                    3 => @truncate(val & 1),
                    4 => @truncate(val >> 7),
                    5 => @truncate(val & 1),
                    6 => 0,
                    7 => @truncate(val & 1),
                    else => unreachable,
                };

                var flags = regs.getFlags();
                flags.setZero(result == 0);
                flags.setSub(false);
                flags.setHalf(false);
                flags.carry = carry;
                regs.setFlags(flags);

                if (is_hl) {
                    self.bus.write8(regs.getHl(), result);
                } else {
                    setR8Value(regs, @enumFromInt(r8_idx), result);
                }
            },
            0x02 => {
                // BIT b, r8
                const bit_val = (val >> @as(u3, @intCast(bit))) & 1;
                var flags = regs.getFlags();
                flags.setZero(bit_val == 0);
                flags.setSub(false);
                flags.setHalf(true);
                regs.setFlags(flags);
            },
            0x03 => {
                // RES or SET
                const is_set = (opcode & addr.CB_BIT_MASK) != 0;
                const mask = @as(u8, 1) << @as(u3, @intCast(bit));
                const result = if (is_set) val | mask else val & ~mask;
                if (is_hl) {
                    self.bus.write8(regs.getHl(), result);
                } else {
                    setR8Value(regs, @enumFromInt(r8_idx), result);
                }
            },
            else => {},
        }
    }

    const AluOp = enum { add, sub, alu_and, xor, alu_or, cp };

    fn execAluR8(self: *Cpu, op: AluOp, carry: bool) void {
        const regs = &self.regs;
        const opcode = self.bus.read8(regs.pc - 1);
        const alu_r8_idx: u3 = @truncate(opcode & addr.REG_MASK);
        const val = if (alu_r8_idx == addr.REG_HL)
            self.bus.read8(regs.getHl())
        else
            getR8Value(regs, @enumFromInt(alu_r8_idx), self.bus);
        switch (op) {
            .add => execAluOp(regs, .add, val, carry),
            .sub => execAluOp(regs, .sub, val, carry),
            .alu_and => {
                regs.a &= val;
                var flags = regs.getFlags();
                flags.setZero(regs.a == 0);
                flags.setSub(false);
                flags.setHalf(true);
                flags.setCarry(false);
                regs.setFlags(flags);
            },
            .xor => {
                regs.a ^= val;
                var flags = regs.getFlags();
                flags.setZero(regs.a == 0);
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(false);
                regs.setFlags(flags);
            },
            .alu_or => {
                regs.a |= val;
                var flags = regs.getFlags();
                flags.setZero(regs.a == 0);
                flags.setSub(false);
                flags.setHalf(false);
                flags.setCarry(false);
                regs.setFlags(flags);
            },
            .cp => execCp(regs, val),
        }
    }
};

// ── Top-Level Helper Functions ───────────────────────────────────────

fn getR8Value(regs: *const Registers, r8: R8, bus: *Bus) u8 {
    _ = bus;
    return switch (r8) {
        .a => regs.a,
        .b => regs.b,
        .c => regs.c,
        .d => regs.d,
        .e => regs.e,
        .h => regs.h,
        .l => regs.l,
    };
}

fn setR8Value(regs: *Registers, r8: R8, val: u8) void {
    switch (r8) {
        .a => regs.a = val,
        .b => regs.b = val,
        .c => regs.c = val,
        .d => regs.d = val,
        .e => regs.e = val,
        .h => regs.h = val,
        .l => regs.l = val,
    }
}

fn execAluOp(regs: *Registers, op: enum { add, sub }, val: u8, carry: bool) void {
    const carry_in: u8 = if (carry) regs.getFlags().carry else 0;
    var flags = regs.getFlags();

    switch (op) {
        .add => {
            const result = regs.a +% val +% carry_in;
            const full: u16 = @as(u16, regs.a) + @as(u16, val) + @as(u16, carry_in);
            flags.setZero(result == 0);
            flags.setSub(false);
            flags.setHalf(((regs.a & addr.LOW_4_BITS) + (val & addr.LOW_4_BITS) + carry_in) > addr.LOW_4_BITS);
            flags.setCarry(full > std.math.maxInt(u8));
            regs.a = result;
        },
        .sub => {
            const result = regs.a -% val -% carry_in;
            flags.setZero(result == 0);
            flags.setSub(true);
            flags.setHalf((regs.a & addr.LOW_4_BITS) < (val & addr.LOW_4_BITS) + carry_in);
            flags.setCarry(regs.a < val + carry_in);
            regs.a = result;
        },
    }

    regs.setFlags(flags);
}

fn execCp(regs: *Registers, val: u8) void {
    var flags = regs.getFlags();
    _ = regs.a -% val;
    flags.setZero(regs.a == val);
    flags.setSub(true);
    flags.setHalf((regs.a & addr.LOW_4_BITS) < (val & addr.LOW_4_BITS));
    flags.setCarry(regs.a < val);
    regs.setFlags(flags);
}
