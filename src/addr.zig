const std = @import("std");

// ── Memory Map Base Addresses ────────────────────────────────────────

pub const ROM_BASE        = 0x0000;
pub const VRAM_BASE       = 0x8000;
pub const CART_RAM_BASE   = 0xA000;
pub const WRAM_BASE       = 0xC000;
pub const ECHO_BASE       = 0xE000;
pub const OAM_BASE        = 0xFE00;
pub const UNUSABLE_BASE   = 0xFEA0;
pub const IO_BASE         = 0xFF00;
pub const HRAM_BASE       = 0xFF80;
pub const IE_ADDR         = 0xFFFF;

pub const WRAM_SIZE       = 8 * 1024;
pub const VRAM_SIZE       = 8 * 1024;
pub const OAM_SIZE        = 160;
pub const HRAM_SIZE       = 127;
pub const FRAMEBUFFER_LEN = 160 * 144;

pub const DMG_WRAM_SIZE   = 8 * 1024;

pub const WRAM_END        = WRAM_BASE + WRAM_SIZE;
pub const ECHO_END        = ECHO_BASE + WRAM_SIZE;
pub const OAM_END         = OAM_BASE + OAM_SIZE;
pub const UNUSABLE_END    = UNUSABLE_BASE + 0x60;
pub const IO_END          = IO_BASE + 0x80;
pub const HRAM_END        = HRAM_BASE + HRAM_SIZE;

// ── CPU Register Reset Values ────────────────────────────────────────

pub const A_RESET   = 0x01;
pub const F_RESET   = 0xB0;
pub const B_RESET   = 0x00;
pub const C_RESET   = 0x13;
pub const D_RESET   = 0x00;
pub const E_RESET   = 0xD8;
pub const H_RESET   = 0x01;
pub const L_RESET   = 0x4D;
pub const SP_RESET  = 0xFFFE;
pub const PC_RESET  = 0x0100;

// ── Cartridge Header Offsets ────────────────────────────────────────

pub const CART_TITLE         = 0x0134;
pub const CART_TITLE_LEN     = 16;
pub const CART_TYPE          = 0x0147;
pub const CART_ROM_SIZE      = 0x0148;
pub const CART_RAM_SIZE      = 0x0149;
pub const CART_CHECKSUM      = 0x014D;
pub const CART_CHECKSUM_BEGIN = 0x0134;
pub const CART_CHECKSUM_END  = 0x014D;
pub const CART_MIN_SIZE      = 0x0150;
pub const CART_MAX_SIZE      = 8 * 1024 * 1024; // 8 MiB per threat model T-01-05

// ── MMIO Register Offsets (within IO_BASE 0xFF00-0xFF7F) ───────────

pub const JOYP      = 0x00;
pub const SB        = 0x01;
pub const SC        = 0x02;
pub const DIV       = 0x04;
pub const TIMA      = 0x05;
pub const TMA       = 0x06;
pub const TAC       = 0x07;
pub const IF        = 0x0F;
pub const BANK      = 0x50;

pub const SC_TRANSFER: u8 = 0x81; // Blargg serial trigger

// ── Flag Register Bit Positions & Masks ─────────────────────────────

pub const FLAG_ZERO       = 1 << 7; // u8: 0x80
pub const FLAG_SUBTRACT   = 1 << 6; // u8: 0x40
pub const FLAG_HALF_CARRY = 1 << 5; // u8: 0x20
pub const FLAG_CARRY      = 1 << 4; // u8: 0x10
pub const FLAG_MASK       = 0xF0;
pub const LOW_NIBBLE_MASK = 0x0F;

pub const INTERRUPT_MASK  = 0x1F; // Low 5 bits of IF/IE
pub const IF_UNUSED_BITS  = 0xE0; // High 3 bits of IF read as 1

// ── Opcode Bit Field Masks ──────────────────────────────────────────

pub const REG_MASK        = 0x07; // 3-bit register index
pub const REG_HL          = 0x06; // (HL) register index
pub const COND_MASK       = 0x03; // 2-bit condition code
pub const PAIR_MASK       = 0x03; // 2-bit register pair
pub const ALU_OP_MASK     = 0x17; // ALU operation in 0x80-0xBF
pub const RST_MASK        = 0x38; // RST vector encoding bits 3-5
pub const CB_GROUP_SHIFT  = 6;    // CB opcode group in high 2 bits
pub const CB_BIT_MASK     = 0x40; // SET vs RES in CB 0xC0-0xFF

// ── Half-Carry Detection Masks ──────────────────────────────────────

pub const LOW_4_BITS  = 0x0F;
pub const LOW_12_BITS = 0x0FFF;

// ── Specific Opcodes Used in execute() ──────────────────────────────

pub const OP_LD_HL_IMM8  = 0x36;
pub const OP_LD_IMM16_SP = 0x08;
pub const OP_LD_IMM16_A  = 0xEA;
pub const OP_LD_BC_A     = 0x02;
pub const OP_LD_DE_A     = 0x12;
pub const OP_LD_A_BC     = 0x0A;
pub const OP_LD_A_DE     = 0x1A;
pub const OP_LD_A_HLI    = 0x2A;
pub const OP_LD_A_HLD    = 0x3A;

// ── DAA Constants ───────────────────────────────────────────────────

pub const DAA_ADJUST_LO = 0x06;
pub const DAA_ADJUST_HI = 0x60;
pub const DAA_MAX_A     = 0x99;

// ── Interrupt Vector Addresses ──────────────────────────────────────

pub const VEC_VBLANK = 0x40;
pub const VEC_STAT   = 0x48;
pub const VEC_TIMER  = 0x50;
pub const VEC_SERIAL = 0x58;
pub const VEC_JOYPAD = 0x60;

// ── Reset Vector Addresses ──────────────────────────────────────────

pub const RST_00 = 0x00;
pub const RST_08 = 0x08;
pub const RST_10 = 0x10;
pub const RST_18 = 0x18;
pub const RST_20 = 0x20;
pub const RST_28 = 0x28;
pub const RST_30 = 0x30;
pub const RST_38 = 0x38;

// ── Timing Constants ────────────────────────────────────────────────

pub const T_CYCLES_PER_M_CYCLE = 4;
pub const MCYCLES_PER_FRAME    = 17556;
pub const T_CYCLES_PER_FRAME   = MCYCLES_PER_FRAME * T_CYCLES_PER_M_CYCLE; // 70224

// ── Interrupt Flags ──────────────────────────────────────────────────

pub const IF_VBLANK  = 0x01;
pub const IF_LCD_STAT = 0x02;
pub const IF_TIMER   = 0x04;
pub const IF_SERIAL  = 0x08;
pub const IF_JOYPAD  = 0x10;

// ── MMIO Initial Values ─────────────────────────────────────────────

pub const JOYP_INIT  = 0xCF;
pub const IF_INIT    = 0xE0;

// ── Comptime Sanity Checks ──────────────────────────────────────────

comptime {
    std.debug.assert(ECHO_BASE + WRAM_SIZE == ECHO_END);
    std.debug.assert(UNUSABLE_BASE + 0x60 == UNUSABLE_END);
    std.debug.assert(HRAM_BASE + HRAM_SIZE == IE_ADDR);
    std.debug.assert(T_CYCLES_PER_FRAME == 70224);
}
