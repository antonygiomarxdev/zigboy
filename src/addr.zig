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
pub const UNUSABLE_END    = UNUSABLE_BASE + UNUSABLE_SIZE;
pub const IO_END          = IO_BASE + IO_SIZE;
pub const HRAM_END        = HRAM_BASE + HRAM_SIZE;

// ── Memory Region Sizes (for padding & boundaries) ───────────────────

pub const UNUSABLE_SIZE   = 0x60;
pub const IO_SIZE         = 0x80;
pub const MMIO_PAD_08_0E_SIZE = 7;
pub const MMIO_APU_SIZE   = 48;
pub const MMIO_PAD_4C_4F_SIZE = 4;
pub const MMIO_PAD_51_7E_SIZE = 46;
pub const MMIO_PAD_7F_SIZE = 1;

// ── Screen Dimensions ────────────────────────────────────────────────

pub const SCREEN_WIDTH    = 160;
pub const SCREEN_HEIGHT   = 144;

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

// ── Cartridge Type Constants ─────────────────────────────────────────

pub const CART_TYPE_ROM_ONLY       = 0x00;
pub const CART_TYPE_MBC1           = 0x01;
pub const CART_TYPE_MBC1_RAM       = 0x02;
pub const CART_TYPE_MBC1_RAM_BATT  = 0x03;
pub const CART_TYPE_MBC2           = 0x05;
pub const CART_TYPE_MBC2_BATT      = 0x06;
pub const CART_TYPE_MBC3           = 0x0F;
pub const CART_TYPE_MBC3_RAM       = 0x10;
pub const CART_TYPE_MBC3_RAM_BATT  = 0x11;
pub const CART_TYPE_MBC3_TIMER_BATT = 0x12;
pub const CART_TYPE_MBC5           = 0x19;
pub const CART_TYPE_MBC5_RAM       = 0x1A;
pub const CART_TYPE_MBC5_RAM_BATT  = 0x1B;
pub const CART_TYPE_MBC5_RUMBLE    = 0x1C;
pub const CART_TYPE_MBC5_RUMBLE_RAM = 0x1D;
pub const CART_TYPE_MBC5_RUMBLE_RAM_BATT = 0x1E;

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

// ── Cartridge RAM Size Encoding (header byte at 0x149) ──────────────

pub const RAM_SIZE_0  = 0x00; // none
pub const RAM_SIZE_1  = 0x01; // 2 KB
pub const RAM_SIZE_2  = 0x02; // 8 KB
pub const RAM_SIZE_4  = 0x03; // 32 KB
pub const RAM_SIZE_16 = 0x04; // 128 KB (MBC5)
pub const RAM_SIZE_64 = 0x05; // 512 KB (MBC5)

pub const ROM_BANK_SIZE    = 0x4000; // 16 KB
pub const RAM_BANK_SIZE    = 0x2000; // 8 KB (8192)
pub const UNMAPPED_READ    = 0xFF;
pub const RAM_INIT_VALUE   = 0xFF;
pub const RAM_ENABLE_MAGIC = 0x0A;

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

// ── PPU Register Offsets (within IO_BASE 0xFF40-0xFF4F) ────────────

pub const LCDC = 0x40;
pub const STAT = 0x41;
pub const SCY  = 0x42;
pub const SCX  = 0x43;
pub const LY   = 0x44;
pub const LYC  = 0x45;
pub const DMA  = 0x46;
pub const BGP  = 0x47;
pub const OBP0 = 0x48;
pub const OBP1 = 0x49;
pub const WY   = 0x4A;
pub const WX   = 0x4B;

// ── LCDC Bit Flags ─────────────────────────────────────────────────

pub const LCDC_ENABLE      = 0x80;
pub const LCDC_WIN_MAP     = 0x40;
pub const LCDC_WIN_ENABLE  = 0x20;
pub const LCDC_BG_DATA     = 0x10;
pub const LCDC_BG_MAP      = 0x08;
pub const LCDC_OBJ_SIZE    = 0x04;
pub const LCDC_OBJ_ENABLE  = 0x02;
pub const LCDC_BG_ENABLE   = 0x01;

// ── STAT Bit Flags ─────────────────────────────────────────────────

pub const STAT_LYC_IRQ    = 0x40;
pub const STAT_MODE2_IRQ  = 0x20;
pub const STAT_MODE1_IRQ  = 0x10;
pub const STAT_MODE0_IRQ  = 0x08;
pub const STAT_LYC        = 0x04;
pub const STAT_MODE_MASK  = 0x03;
pub const STAT_MODE_CLEAR = 0xF8;
pub const STAT_INIT_VAL   = 0x00;

// ── Palette Shade Values ───────────────────────────────────────────

pub const SHADE_WHITE = 0xFF;
pub const SHADE_LIGHT = 0xAA;
pub const SHADE_DARK  = 0x55;
pub const SHADE_BLACK = 0x00;
pub const PALETTE_SHIFT_PER_COLOR = 2;
pub const PALETTE_COLOR_MASK = 0x03;
pub const PAL_ID_WHITE      = 0;
pub const PAL_ID_LIGHT      = 1;
pub const PAL_ID_DARK       = 2;
pub const PAL_ID_BLACK      = 3;

// ── Window Constants ───────────────────────────────────────────────

pub const WX_OFFSET = 7;

// ── Tile Map / Data Base Addresses ─────────────────────────────────

pub const TILE_DATA_0     = 0x8000;
pub const TILE_DATA_1     = 0x8800;
pub const TILE_MAP_0      = 0x9800;
pub const TILE_MAP_1      = 0x9C00;
pub const TILE_MAP_SIZE   = 0x0400;
pub const TILE_SIZE_BYTES = 16;
pub const TILE_ROWS       = 8;
pub const TILE_BYTES_PER_ROW = 2;
pub const TILES_PER_MAP_ROW = 32;
pub const TILE_INDEX_SIGNED_BIAS = 128;

// ── PPU Timing Constants ───────────────────────────────────────────

pub const DOTS_PER_LINE   = 456;
pub const DOTS_OAM        = 80;
pub const DOTS_DRAWING    = 172;
pub const LY_VBLANK_START = 144;
pub const LY_MAX          = 153;

// ── Flag Register Bit Positions & Masks ─────────────────────────────

pub const FLAG_ZERO       = 1 << 7; // u8: 0x80
pub const FLAG_SUBTRACT   = 1 << 6; // u8: 0x40
pub const FLAG_HALF_CARRY = 1 << 5; // u8: 0x20
pub const FLAG_CARRY      = 1 << 4; // u8: 0x10
pub const FLAG_MASK       = 0xF0;
pub const LOW_NIBBLE_MASK = 0x0F;

pub const INTERRUPT_MASK  = 0x1F; // Low 5 bits of IF/IE
pub const IF_UNUSED_BITS  = 0xE0; // High 3 bits of IF read as 1

// ── Bit-Level Masks & Shifts ────────────────────────────────────────

pub const REG_MASK        = 0x07; // 3-bit register index
pub const REG_HL          = 0x06; // (HL) register index
pub const COND_MASK       = 0x03; // 2-bit condition code
pub const PAIR_MASK       = 0x03; // 2-bit register pair
pub const ALU_OP_MASK     = 0x17; // ALU operation in 0x80-0xBF
pub const RST_MASK        = 0x38; // RST vector encoding bits 3-5
pub const CB_GROUP_SHIFT  = 6;    // CB opcode group in high 2 bits
pub const CB_BIT_MASK     = 0x40; // SET vs RES in CB 0xC0-0xFF

pub const LOW_BYTE_MASK   = 0xFF;
pub const HIGH_BYTE_SHIFT = 8;
pub const BIT_7_MASK      = 0x80;
pub const BIT_7_SHIFT     = 7;
pub const NIBBLE_SHIFT    = 4;
pub const ALU_GROUP_MASK  = 0x1F;
pub const REGION_SHIFT    = 12;

// ── Half-Carry Detection Masks ──────────────────────────────────────

pub const LOW_4_BITS  = 0x0F;
pub const LOW_12_BITS = 0x0FFF;

// ── Specific Opcodes Used in execute() ──────────────────────────────

pub const OP_HALT        = 0x76;
pub const OP_LD_HL_IMM8  = 0x36;
pub const OP_LD_IMM16_SP = 0x08;
pub const OP_LD_IMM16_A  = 0xEA;
pub const OP_LD_BC_A     = 0x02;
pub const OP_LD_DE_A     = 0x12;
pub const OP_LD_A_BC     = 0x0A;
pub const OP_LD_A_DE     = 0x1A;
pub const OP_LD_A_HLI    = 0x2A;
pub const OP_LD_A_HLD    = 0x3A;
pub const OP_NOP         = 0x00;
pub const OP_JP_IMM16    = 0xC3;
pub const OP_LD_A_IMM8   = 0x3E;
pub const OP_LDH_IMM8_A  = 0xE0;
pub const OP_JR_REL      = 0x18;

// ── DAA Constants ───────────────────────────────────────────────────

pub const DAA_ADJUST_LO  = 0x06;
pub const DAA_ADJUST_HI  = 0x60;
pub const DAA_MAX_A      = 0x99;
pub const DAA_BCD_MAX_LO = 0x09;

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

// ── RST Opcode Values ───────────────────────────────────────────────

pub const OP_RST_00 = 0xC7;
pub const OP_RST_08 = 0xCF;
pub const OP_RST_10 = 0xD7;
pub const OP_RST_18 = 0xDF;
pub const OP_RST_20 = 0xE7;
pub const OP_RST_28 = 0xEF;
pub const OP_RST_30 = 0xF7;
pub const OP_RST_38 = 0xFF;

// ── Timing Constants ────────────────────────────────────────────────

pub const T_CYCLES_PER_M_CYCLE = 4;
pub const MCYCLES_PER_FRAME    = 17556;
pub const T_CYCLES_PER_FRAME   = MCYCLES_PER_FRAME * T_CYCLES_PER_M_CYCLE; // 70224
pub const DMG_CLOCK_HZ         = 4_194_304;

// ── Interrupt Flags ──────────────────────────────────────────────────

pub const IF_VBLANK  = 0x01;
pub const IF_LCD_STAT = 0x02;
pub const IF_TIMER   = 0x04;
pub const IF_SERIAL  = 0x08;
pub const IF_JOYPAD  = 0x10;

// ── MMIO Initial Values ─────────────────────────────────────────────

pub const JOYP_INIT  = 0xCF;
pub const IF_INIT    = 0xE0;

// ── MBC1 Constants ──────────────────────────────────────────────────

pub const MBC1_BANK_HI_SHIFT     = 5;
pub const MBC1_BANK_LO_MASK      = 0x1F;
pub const MBC1_RAM_BANK_MASK     = 0x03;
pub const MBC1_MODE_FLAG_BIT     = 0x01;
pub const MBC1_INITIAL_BANK      = 1;
pub const MBC1_BANK_PROHIBITED_0  = 0x00;
pub const MBC1_BANK_PROHIBITED_20 = 0x20;
pub const MBC1_BANK_PROHIBITED_40 = 0x40;
pub const MBC1_BANK_PROHIBITED_60 = 0x60;

// ── MBC2 Constants ──────────────────────────────────────────────────

pub const MBC2_RAM_SIZE       = 512;
pub const MBC2_ROM_BANK_MASK  = 0x0F;
pub const MBC2_RAM_READ_MASK  = 0xF0;
pub const MBC2_BIT8           = 0x0100;
pub const MBC2_REGION_END     = 0x200;
pub const MBC2_INITIAL_BANK   = 1;

// ── MBC3 Constants ──────────────────────────────────────────────────

pub const MBC3_ROM_BANK_MASK    = 0x7F;
pub const MBC3_RTC_REGS         = 5;
pub const MBC3_RTC_LATCH_SIZE   = 2;
pub const MBC3_RTC_REG_BASE     = 0x08;
pub const MBC3_RTC_REG_MAX      = 0x0C;
pub const MBC3_RAM_BANK_MAX     = 0x03;
pub const MBC3_INITIAL_BANK     = 1;
pub const MBC3_LATCH_PREV       = 0;
pub const MBC3_LATCH_CURR       = 1;

// ── MBC5 Constants ──────────────────────────────────────────────────

pub const MBC5_BANK_HI_BOUNDARY  = 0x3000;
pub const MBC5_BANK_HI_MASK      = 0x01;
pub const MBC5_BANK_LO_BITS      = 8;
pub const MBC5_RAM_BANK_MASK     = 0x0F;
pub const MBC5_INITIAL_BANK      = 1;

// ── Joypad / Button Constants ────────────────────────────────────────

pub const JOYP_SELECT_ACTION    = 0x20;
pub const JOYP_SELECT_DIRECTION = 0x10;
pub const JOYP_UNUSED_BITS      = 0xC0;

pub const JoypadButton = enum(u3) {
    a = 0,
    b = 1,
    select = 2,
    start = 3,
    right = 4,
    left = 5,
    up = 6,
    down = 7,
};

pub const BUTTON_A: u3 = 0;
pub const BUTTON_B: u3 = 1;
pub const BUTTON_SELECT: u3 = 2;
pub const BUTTON_START: u3 = 3;
pub const BUTTON_RIGHT: u3 = 4;
pub const BUTTON_LEFT: u3 = 5;
pub const BUTTON_UP: u3 = 6;
pub const BUTTON_DOWN: u3 = 7;

// ── Timer Constants ──────────────────────────────────────────────────

pub const TIMER_TAC_ENABLE     = 0x04;
pub const TIMER_TAC_CLOCK_MASK = 0x03;
pub const TIMER_CLOCK_1024     = 1024;
pub const TIMER_CLOCK_16       = 16;
pub const TIMER_CLOCK_64       = 64;
pub const TIMER_CLOCK_256      = 256;

// ── ALU Group Ranges (top 5 bits of opcode after masking with ALU_GROUP_MASK) ─

pub const ALU_GROUP_ADD = 0x10;
pub const ALU_GROUP_ADC = 0x18;
pub const ALU_GROUP_SUB = 0x20;
pub const ALU_GROUP_SBC = 0x28;
pub const ALU_GROUP_AND = 0x30;
pub const ALU_GROUP_XOR = 0x38;
pub const ALU_GROUP_OR  = 0x00;
pub const ALU_GROUP_CP  = 0x08;

// ── Sprite Constants ──────────────────────────────────────────────────

pub const SPRITE_NUM_ENTRIES     = 40;
pub const SPRITE_ENTRY_SIZE      = 4;
pub const SPRITES_MAX_PER_LINE   = 10;
pub const SPRITE_HEIGHT_8        = 8;
pub const SPRITE_HEIGHT_16       = 16;
pub const SPRITE_WIDTH           = 8;
pub const SPRITE_MAX_COL         = SPRITE_WIDTH - 1;
pub const SPRITE_Y_OFFSET        = 16;
pub const SPRITE_X_OFFSET        = 8;
pub const SPRITE_TILE_MASK       = 0xFE;
pub const SPRITE_TILE_LSB        = 0x01;

pub const SPRITE_ATTR_PRIORITY  = 0x80;
pub const SPRITE_ATTR_Y_FLIP    = 0x40;
pub const SPRITE_ATTR_X_FLIP    = 0x20;
pub const SPRITE_ATTR_PALETTE   = 0x10;

// ── OAM DMA Constants ─────────────────────────────────────────────────

pub const DMA_TRANSFER_SIZE     = 160;
pub const DMA_SOURCE_SHIFT      = 8;
pub const DMA_BLOCK_VAL         = 0xFF;

// ── Comptime Sanity Checks ──────────────────────────────────────────

comptime {
    std.debug.assert(ECHO_BASE + WRAM_SIZE == ECHO_END);
    std.debug.assert(UNUSABLE_BASE + UNUSABLE_SIZE == UNUSABLE_END);
    std.debug.assert(HRAM_BASE + HRAM_SIZE == IE_ADDR);
    std.debug.assert(T_CYCLES_PER_FRAME == 70224);
}
