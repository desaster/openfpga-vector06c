//
// Virtual keyboard OSD UI for Vector-06C softcpu firmware.
//

#include "softcpu_regs.h"
#include "vkb_ui.h"
#include "font_5x8.h"
#include "cpu_cycle.h"

// Timing

#define CLK_FREQ      8000000
#define REPEAT_DELAY  (CLK_FREQ / 2)
#define REPEAT_RATE   (CLK_FREQ / 10)
#define MOVE_COOLDOWN (CLK_FREQ / 25) // 40ms debounce between moves

// Palette indices

#define PAL_TRANS      0
#define PAL_BEZEL      1
#define PAL_GRAY       2
#define PAL_DOLIVE     3
#define PAL_LOLIVE     4
#define PAL_BROWN      5
#define PAL_BDARK      6
#define PAL_LABEL      7
#define PAL_TDARK      8
#define PAL_TWHITE     9
#define PAL_LED_GREEN  10
#define PAL_LED_RED    11
#define PAL_STICKY     12
#define PAL_STICKY_CUR 13

// Cyrillic glyph byte codes
//
// Font Cyrillic block starts at glyph index 96, follows KOI-7 order:
//   glyph 96=Ю(0x40), 97=А(0x41), 98=Б(0x42), 99=Ц(0x43), ...
// Byte encoding: 0x80 + (KOI7_code - 0x40), decoded in glyph_from_byte().

#define CYR_YU  0x80 // Ю
#define CYR_A   0x81 // А
#define CYR_B   0x82 // Б
#define CYR_TS  0x83 // Ц
#define CYR_D   0x84 // Д
#define CYR_YE  0x85 // Е
#define CYR_F   0x86 // Ф
#define CYR_G   0x87 // Г
#define CYR_KH  0x88 // Х
#define CYR_I   0x89 // И
#define CYR_J   0x8A // Й
#define CYR_K   0x8B // К
#define CYR_L   0x8C // Л
#define CYR_M   0x8D // М
#define CYR_N   0x8E // Н
#define CYR_O   0x8F // О
#define CYR_P   0x90 // П
#define CYR_YA  0x91 // Я
#define CYR_R   0x92 // Р
#define CYR_S   0x93 // С
#define CYR_T   0x94 // Т
#define CYR_U   0x95 // У
#define CYR_ZH  0x96 // Ж
#define CYR_V   0x97 // В
#define CYR_SS  0x98 // Ь
#define CYR_Y   0x99 // Ы
#define CYR_Z   0x9A // З
#define CYR_SH  0x9B // Ш
#define CYR_E   0x9C // Э
#define CYR_SCH 0x9D // Щ
#define CYR_CH  0x9E // Ч

// Extended glyph byte codes, font row 8, indices 128+
#define GLYPH_ARR_UP 0xA0
#define GLYPH_ARR_DN 0xA1
#define GLYPH_ARR_LT 0xA2
#define GLYPH_ARR_RT 0xA3
#define GLYPH_ARR_NW 0xA4

// Multi-char legend byte codes
//
// Legend encoding for key_t legend_top/legend_bot fields:
//   0x00         = empty (no legend)
//   0x20-0x7E    = single ASCII character
//   0x80-0x9E    = single Cyrillic character (CYR_* constants)
//   0xA0-0xA4    = single extended glyph (GLYPH_ARR_* constants)
//   0xC0+n       = index into multi_legends[] table

#define ML_VK   0xC0 // ВК
#define ML_SS   0xC1 // СС
#define ML_US   0xC2 // УС
#define ML_RUS  0xC3 // РУС
#define ML_LAT  0xC4 // LAT
#define ML_TAB  0xC5 // ТАБ
#define ML_PS   0xC6 // ПС
#define ML_ZB   0xC7 // ЗБ
#define ML_VVOD 0xC8 // ВВОД
#define ML_BLK  0xC9 // БЛК
#define ML_SBR  0xCA // СБР
#define ML_NF1  0xCB // F1
#define ML_NF2  0xCC // F2
#define ML_NF3  0xCD // F3
#define ML_NF4  0xCE // F4
#define ML_NF5  0xCF // F5
#define ML_AR2  0xD0 // АР2
#define ML_STR  0xD1 // СТР

static const uint8_t ml_vk[] = { CYR_V, CYR_K, 0 };
static const uint8_t ml_ss[] = { CYR_S, CYR_S, 0 };
static const uint8_t ml_us[] = { CYR_U, CYR_S, 0 };
static const uint8_t ml_rus[] = { CYR_R, CYR_U, CYR_S, 0 };
static const uint8_t ml_lat[] = { 'L', 'A', 'T', 0 };
static const uint8_t ml_tab[] = { CYR_T, CYR_A, CYR_B, 0 };
static const uint8_t ml_ps[] = { CYR_P, CYR_S, 0 };
static const uint8_t ml_zb[] = { CYR_Z, CYR_B, 0 };
static const uint8_t ml_vvod[] = { CYR_V, CYR_V, CYR_O, CYR_D, 0 };
static const uint8_t ml_blk[] = { CYR_B, CYR_L, CYR_K, 0 };
static const uint8_t ml_sbr[] = { CYR_S, CYR_B, CYR_R, 0 };
static const uint8_t ml_nf1[] = { 'F', '1', 0 };
static const uint8_t ml_nf2[] = { 'F', '2', 0 };
static const uint8_t ml_nf3[] = { 'F', '3', 0 };
static const uint8_t ml_nf4[] = { 'F', '4', 0 };
static const uint8_t ml_nf5[] = { 'F', '5', 0 };
static const uint8_t ml_ar2[] = { CYR_A, CYR_R, '2', 0 };
static const uint8_t ml_str[] = { CYR_S, CYR_T, CYR_R, 0 };

static const uint8_t *const multi_legends[] = {
    ml_vk,
    ml_ss,
    ml_us,
    ml_rus,
    ml_lat,
    ml_tab,
    ml_ps,
    ml_zb,
    ml_vvod,
    ml_blk,
    ml_sbr,
    ml_nf1,
    ml_nf2,
    ml_nf3,
    ml_nf4,
    ml_nf5,
    ml_ar2,
    ml_str,
};

// Key definitions

#define KF_NUMPAD   0x01
#define KF_MODIFIER 0x02
#define KF_SPECIAL  0x04

#define MK(r, c) (((r) << 4) | (c))

typedef struct {
    uint16_t x;
    uint8_t y, w, h;
    uint8_t fill_color;
    uint8_t text_color;
    uint8_t matrix; // MK(row,col) or 0xFF
    uint8_t flags;
    uint8_t legend_top; // byte-encoded legend (see encoding above)
    uint8_t legend_bot;
} key_t;

// Key layout

#define KEY_H   17
#define KEY_W   28
#define KEY_W15 42
#define GAP_H   2
#define GAP_V   1
#define KS      (KEY_W + GAP_H)
#define MAIN_X  6
#define MAIN_Y  21
#define NUM_X   (OSD_WIDTH - MAIN_X - 2 * KS - KEY_W - 1)
#define NUM_Y   21

#define ROW_Y(r)  (MAIN_Y + (r) * (KEY_H + GAP_V))
#define NROW_Y(r) (NUM_Y + (r) * (KEY_H + GAP_V))

// Matrix mapping verified against keyboard.sv {c,r} encoding.
// keyboard.sv: {c,r} = 7-bit value, c=col bits 6:4, r=row bits 3:0.
// MK(row, col) encodes for our firmware use.

// clang-format off
static const key_t keys[] = {
    // Row 0
    {MAIN_X+0*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(3,3), 0, ';', '+'},
    {MAIN_X+1*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(2,1), 0, '1', '!'},
    {MAIN_X+2*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(2,2), 0, '2', '"'},
    {MAIN_X+3*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(2,3), 0, '3', '#'},
    {MAIN_X+4*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(2,4), 0, '4', '$'},
    {MAIN_X+5*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(2,5), 0, '5', '%'},
    {MAIN_X+6*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(2,6), 0, '6', '&'},
    {MAIN_X+7*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(2,7), 0, '7', '\''},
    {MAIN_X+8*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(3,0), 0, '8', '('},
    {MAIN_X+9*KS,   ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(3,1), 0, '9', ')'},
    {MAIN_X+10*KS,  ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(2,0), 0, '0', 0},
    {MAIN_X+11*KS,  ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(3,5), 0, '-', '='},
    {MAIN_X+12*KS,  ROW_Y(0),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(3,7), 0, '/', '?'},
    {NUM_X+0*KS,    NROW_Y(0),  KEY_W, KEY_H, PAL_DOLIVE,   PAL_TDARK, 0xFF,    KF_NUMPAD|KF_SPECIAL, ML_VVOD, ML_VVOD},
    {NUM_X+1*KS,    NROW_Y(0),  KEY_W, KEY_H, PAL_DOLIVE,   PAL_TDARK, 0xFF,    KF_NUMPAD|KF_SPECIAL, ML_BLK,  ML_BLK},
    {NUM_X+2*KS,    NROW_Y(0),  KEY_W, KEY_H, PAL_DOLIVE,   PAL_TDARK, 0xFF,    KF_NUMPAD|KF_SPECIAL, ML_SBR,  ML_SBR},

    // Row 1
    {MAIN_X+15+0*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(5,2), 0, CYR_J,   'J'},
    {MAIN_X+15+1*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(4,3), 0, CYR_TS,  'C'},
    {MAIN_X+15+2*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(6,5), 0, CYR_U,   'U'},
    {MAIN_X+15+3*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(5,3), 0, CYR_K,   'K'},
    {MAIN_X+15+4*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(4,5), 0, CYR_YE,  'E'},
    {MAIN_X+15+5*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(5,6), 0, CYR_N,   'N'},
    {MAIN_X+15+6*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(4,7), 0, CYR_G,   'G'},
    {MAIN_X+15+7*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(7,3), 0, CYR_SH,  '['},
    {MAIN_X+15+8*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(7,5), 0, CYR_SCH, ']'},
    {MAIN_X+15+9*KS,    ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(7,2), 0, CYR_Z,   'Z'},
    {MAIN_X+15+10*KS,   ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(5,0), 0, CYR_KH,  'H'},
    {MAIN_X+15+11*KS,   ROW_Y(1),   KEY_W, KEY_H, PAL_GRAY,     PAL_TDARK, MK(3,2), 0, ':',     '*'},
    {NUM_X+0*KS,        NROW_Y(1),  KEY_W, KEY_H, PAL_LOLIVE,   PAL_TDARK, MK(1,3), KF_NUMPAD, ML_NF1, ML_NF1},
    {NUM_X+1*KS,        NROW_Y(1),  KEY_W, KEY_H, PAL_LOLIVE,   PAL_TDARK, MK(1,4), KF_NUMPAD, ML_NF2, ML_NF2},
    {NUM_X+2*KS,        NROW_Y(1),  KEY_W, KEY_H, PAL_LOLIVE,   PAL_TDARK, MK(1,5), KF_NUMPAD, ML_NF3, ML_NF3},

    // Row 2
    {MAIN_X+0*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_DOLIVE, PAL_TDARK, 0xFF,    KF_MODIFIER, ML_US, 0},
    {MAIN_X+1*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(4,6), 0, CYR_F,  'F'},
    {MAIN_X+2*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(7,1), 0, CYR_Y,  'Y'},
    {MAIN_X+3*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(6,7), 0, CYR_V,  'W'},
    {MAIN_X+4*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(4,1), 0, CYR_A,  'A'},
    {MAIN_X+5*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(6,0), 0, CYR_P,  'P'},
    {MAIN_X+6*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(6,2), 0, CYR_R,  'R'},
    {MAIN_X+7*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(5,7), 0, CYR_O,  'O'},
    {MAIN_X+8*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(5,4), 0, CYR_L,  'L'},
    {MAIN_X+9*KS,   ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(4,4), 0, CYR_D,  'D'},
    {MAIN_X+10*KS,  ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(6,6), 0, CYR_ZH, 'V'},
    {MAIN_X+11*KS,  ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(7,4), 0, CYR_E,  '\\'},
    {MAIN_X+12*KS,  ROW_Y(2),   KEY_W, KEY_H, PAL_GRAY,   PAL_TDARK, MK(3,6), 0, '.',    '>'},
    {NUM_X+0*KS,    NROW_Y(2),  KEY_W, KEY_H, PAL_LOLIVE, PAL_TDARK, MK(1,6), KF_NUMPAD, ML_NF4, ML_NF4},
    {NUM_X+1*KS,    NROW_Y(2),  KEY_W, KEY_H, PAL_LOLIVE, PAL_TDARK, MK(1,7), KF_NUMPAD, ML_NF5, ML_NF5},
    {NUM_X+2*KS,    NROW_Y(2),  KEY_W, KEY_H, PAL_DOLIVE, PAL_TDARK, MK(1,2), KF_NUMPAD, ML_AR2, ML_AR2},

    // Row 3
    {MAIN_X,                        ROW_Y(3),   KEY_W15, KEY_H, PAL_BROWN, PAL_GRAY,  0xFF,    KF_MODIFIER, ML_SS,        0},
    {MAIN_X+KEY_W15+GAP_H+0*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(6,1), 0, CYR_YA,  'Q'},
    {MAIN_X+KEY_W15+GAP_H+1*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(7,6), 0, CYR_CH,  '^'},
    {MAIN_X+KEY_W15+GAP_H+2*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(6,3), 0, CYR_S,   'S'},
    {MAIN_X+KEY_W15+GAP_H+3*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(5,5), 0, CYR_M,   'M'},
    {MAIN_X+KEY_W15+GAP_H+4*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(5,1), 0, CYR_I,   'I'},
    {MAIN_X+KEY_W15+GAP_H+5*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(6,4), 0, CYR_T,   'T'},
    {MAIN_X+KEY_W15+GAP_H+6*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(7,0), 0, CYR_SS,  'X'},
    {MAIN_X+KEY_W15+GAP_H+7*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(4,2), 0, CYR_B,   'B'},
    {MAIN_X+KEY_W15+GAP_H+8*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(4,0), 0, CYR_YU,  '@'},
    {MAIN_X+KEY_W15+GAP_H+9*KS,     ROW_Y(3),   KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(3,4), 0, ',',     '<'},
    {MAIN_X+KEY_W15+GAP_H+10*KS,    ROW_Y(3),   KEY_W15, KEY_H, PAL_BROWN, PAL_GRAY,  MK(0,2), 0, ML_VK,   0},
    {NUM_X+0*KS,                    NROW_Y(3),  KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(1,0), KF_NUMPAD, GLYPH_ARR_NW, GLYPH_ARR_NW},
    {NUM_X+1*KS,                    NROW_Y(3),  KEY_W,   KEY_H, PAL_GRAY,  PAL_TDARK, MK(0,5), KF_NUMPAD, GLYPH_ARR_UP, GLYPH_ARR_UP},
    {NUM_X+2*KS,                    NROW_Y(3),  KEY_W,   KEY_H, PAL_LOLIVE,PAL_TDARK, MK(1,1), KF_NUMPAD, ML_STR,       ML_STR},

    // Row 4
    {MAIN_X,                                            ROW_Y(4),   KEY_W15,    KEY_H, PAL_BROWN,  PAL_GRAY,  0xFF,    0, ML_RUS, ML_LAT},
    {MAIN_X+KEY_W15+GAP_H,                              ROW_Y(4),   KEY_W15,    KEY_H, PAL_BROWN,  PAL_GRAY,  MK(0,0), 0, ML_TAB,  0},
    {MAIN_X+2*(KEY_W15+GAP_H),                          ROW_Y(4),   210,        KEY_H, PAL_DOLIVE, PAL_TDARK, MK(7,7), 0, ' ',     0},
    {MAIN_X+2*(KEY_W15+GAP_H)+210+GAP_H,                ROW_Y(4),   KEY_W15,    KEY_H, PAL_BROWN,  PAL_GRAY,  MK(0,1), 0, ML_PS,   0},
    {MAIN_X+2*(KEY_W15+GAP_H)+210+GAP_H+KEY_W15+GAP_H,  ROW_Y(4),   KEY_W15,    KEY_H, PAL_BROWN,  PAL_GRAY,  MK(0,3), 0, ML_ZB,   0},
    {NUM_X+0*KS,                                        NROW_Y(4),  KEY_W,      KEY_H, PAL_GRAY,   PAL_TDARK, MK(0,4), KF_NUMPAD, GLYPH_ARR_LT, GLYPH_ARR_LT},
    {NUM_X+1*KS,                                        NROW_Y(4),  KEY_W,      KEY_H, PAL_GRAY,   PAL_TDARK, MK(0,7), KF_NUMPAD, GLYPH_ARR_DN, GLYPH_ARR_DN},
    {NUM_X+2*KS,                                        NROW_Y(4),  KEY_W,      KEY_H, PAL_GRAY,   PAL_TDARK, MK(0,6), KF_NUMPAD, GLYPH_ARR_RT, GLYPH_ARR_RT},
};
// clang-format on

#define NUM_KEYS (sizeof(keys) / sizeof(keys[0]))

// Visual rows for cursor navigation, each row = main keys + numpad keys
static const struct {
    uint8_t start, count;
} vrows[] = {
    { 0, 16 },  // row 0: 13 main + 3 numpad
    { 16, 15 }, // row 1: 12 main + 3 numpad
    { 31, 16 }, // row 2: 13 main + 3 numpad
    { 47, 15 }, // row 3: 12 main + 3 numpad
    { 62, 8 },  // row 4: 5 main + 3 numpad
};
#define NUM_VROWS 5

// 4bpp drawing primitives

// Callers must ensure x,y are within [0,OSD_WIDTH) × [0,OSD_HEIGHT).
static inline void osd_set_pixel_4bpp(int x, int y, uint8_t color)
{
    int ba = y * OSD_STRIDE + (x >> 1);
    if (x & 1) {
        OSD_FB[ba] = (OSD_FB[ba] & 0xF0) | (color & 0x0F);
    } else {
        OSD_FB[ba] = (OSD_FB[ba] & 0x0F) | ((color & 0x0F) << 4);
    }
}

// Callers must ensure the rect is within [0,OSD_WIDTH) × [0,OSD_HEIGHT).
static void osd_fill_rect(int x, int y, int w, int h, uint8_t color)
{
    uint8_t cnib = color & 0x0F;
    for (int ry = y; ry < y + h; ry++) {
        int ba = ry * OSD_STRIDE + (x >> 1);
        int rx = x;
        // Handle odd starting pixel
        if (rx & 1) {
            OSD_FB[ba] = (OSD_FB[ba] & 0xF0) | cnib;
            ba++;
            rx++;
        }
        // Fill pairs of pixels (whole bytes)
        uint8_t pair = (cnib << 4) | cnib;
        while (rx + 1 < x + w) {
            OSD_FB[ba] = pair;
            ba++;
            rx += 2;
        }
        // Handle odd trailing pixel
        if (rx < x + w) {
            OSD_FB[ba] = (OSD_FB[ba] & 0x0F) | (cnib << 4);
        }
    }
}

static void osd_clear(void)
{
    for (int i = 0; i < OSD_FB_SIZE; i++) {
        OSD_FB[i] = 0;
    }
}

static void draw_char(int x, int y, uint8_t glyph_idx, uint8_t color)
{
    if (glyph_idx >= FONT_NUM_GLYPHS) {
        return;
    }
    for (int row = 0; row < 8; row++) {
        uint8_t bits = font_5x8[glyph_idx][row];
        for (int col = 0; col < 5; col++) {
            if (bits & (0x80 >> col)) {
                osd_set_pixel_4bpp(x + col, y + row, color);
            }
        }
    }
}

static inline uint8_t glyph_from_byte(uint8_t b)
{
    if (b >= 0x80) {
        return 96 + (b - 0x80);
    }
    if (b >= 0x20 && b < 0x7F) {
        return b - 0x20;
    }
    return 0;
}

static int string_width(const uint8_t *str)
{
    int len = 0;
    while (*str++) {
        len++;
    }
    return len ? len * 6 - 1 : 0;
}

static void draw_string(int x, int y, const uint8_t *str, uint8_t color)
{
    while (*str) {
        draw_char(x, y, glyph_from_byte(*str), color);
        x += 6;
        str++;
    }
}

// Returns a null-terminated string for a legend byte value.
// Single-char legends are written into the caller-provided buf[2].
static const uint8_t *legend_to_str(uint8_t legend, uint8_t *buf)
{
    if (legend == 0) {
        return 0;
    }
    if (legend >= 0xC0) {
        return multi_legends[legend - 0xC0];
    }
    buf[0] = legend;
    buf[1] = 0;
    return buf;
}

// Returns true if the key has two distinct, non-empty legends
static inline int key_has_dual(const key_t *k)
{
    return k->legend_bot != 0 && k->legend_bot != k->legend_top;
}

static void draw_legend(const key_t *k, uint8_t color)
{
    int ix = k->x + 1, iy = k->y + 1;
    int iw = k->w - 2, ih = k->h - 2;
    uint8_t buf1[2], buf2[2];

    if (key_has_dual(k)) {
        // Dual legend: top at upper-left, bottom at lower-right
        const uint8_t *top_str = legend_to_str(k->legend_top, buf1);
        const uint8_t *bot_str = legend_to_str(k->legend_bot, buf2);
        int bot_sw = string_width(bot_str);
        int mx = (k->flags & KF_MODIFIER) ? 1 : 3;
        draw_string(ix + mx, iy + 1, top_str, color);
        draw_string(ix + iw - bot_sw - mx, iy + ih - 8, bot_str, color);
    } else {
        // Single legend: centered
        const uint8_t *str = legend_to_str(k->legend_top, buf1);
        if (!str) {
            return;
        }
        int sw = string_width(str);
        draw_string(ix + (iw - sw) / 2, iy + 4, str, color);
    }
}

static void draw_key_border(const key_t *k, uint8_t color)
{
    int x = k->x, y = k->y, w = k->w, h = k->h;
    for (int i = 1; i < w - 1; i++) {
        osd_set_pixel_4bpp(x + i, y, color);
        osd_set_pixel_4bpp(x + i, y + h - 1, color);
    }
    for (int i = 1; i < h - 1; i++) {
        osd_set_pixel_4bpp(x, y + i, color);
        osd_set_pixel_4bpp(x + w - 1, y + i, color);
    }
}

// RUS LED indicator
#define LED_W     6
#define LED_H     9
#define LED_RUS_X 402
#define LED_RUS_Y 21
#define LBL_RUS_X 397
#define LBL_RUS_Y 31

static void draw_led(int x, int y, uint8_t fill_color)
{
    osd_fill_rect(x, y, LED_W, LED_H, PAL_BDARK);
    osd_fill_rect(x + 1, y + 1, LED_W - 2, LED_H - 2, fill_color);
}

static const uint8_t lbl_rus[] = { CYR_R, CYR_U, CYR_S, 0 };

// FDD track display layout
#define TRK_BOX_X 399
#define TRK_BOX_W 13
#define TRK_BOX_H 9
#define TRK_LBL_X 403
#define TRK_A_Y   57
#define TRK_A_LBL 67
#define TRK_B_Y   79
#define TRK_B_LBL 89

static const char hex_chars[] = "0123456789ABCDEF";
static const uint8_t lbl_fd1[] = { 'A', 0 };
static const uint8_t lbl_fd2[] = { 'B', 0 };

static uint32_t fdd1_led_timeout, fdd2_led_timeout;
static uint8_t fdd1_led_on, fdd2_led_on;
static uint8_t prev_fdd1_active, prev_fdd2_active;
static uint8_t prev_fdd1_track, prev_fdd2_track;
static uint8_t prev_rus_led;

static void draw_hex_byte(int x, int y, uint8_t val, uint8_t color)
{
    draw_char(x, y, glyph_from_byte(hex_chars[val >> 4]), color);
    draw_char(x + 6, y, glyph_from_byte(hex_chars[val & 0xF]), color);
}

static void draw_track_display(int y, uint8_t track, int active)
{
    uint8_t bg = active ? PAL_LED_GREEN : PAL_TDARK;
    uint8_t fg = active ? PAL_TDARK : PAL_LED_GREEN;
    osd_fill_rect(TRK_BOX_X, y, TRK_BOX_W, TRK_BOX_H, PAL_BDARK);
    osd_fill_rect(TRK_BOX_X + 1, y + 1, TRK_BOX_W - 2, TRK_BOX_H - 2, bg);
    draw_hex_byte(TRK_BOX_X + 1, y + 1, track, fg);
}

static void draw_indicators(void)
{
    prev_rus_led = (*RUS_LED_STATUS & RUS_LED_ON) ? 1 : 0;
    draw_led(LED_RUS_X, LED_RUS_Y, prev_rus_led ? PAL_LED_RED : PAL_BDARK);
    draw_string(LBL_RUS_X, LBL_RUS_Y, lbl_rus, PAL_LABEL);
    draw_track_display(TRK_A_Y, prev_fdd1_track, prev_fdd1_active);
    draw_string(TRK_LBL_X, TRK_A_LBL, lbl_fd1, PAL_LABEL);
    draw_track_display(TRK_B_Y, prev_fdd2_track, prev_fdd2_active);
    draw_string(TRK_LBL_X, TRK_B_LBL, lbl_fd2, PAL_LABEL);
}

static void update_indicators(void)
{
    uint32_t hw = *FDD_HW_STATUS;
    uint32_t now = rdcycle();

    if (hw & FDD_HW_BUSY1) {
        fdd1_led_timeout = now + CLK_FREQ / 10;
        fdd1_led_on = 1;
    }
    if (fdd1_led_on && (int32_t) (now - fdd1_led_timeout) >= 0) {
        fdd1_led_on = 0;
    }

    if (hw & FDD_HW_BUSY2) {
        fdd2_led_timeout = now + CLK_FREQ / 10;
        fdd2_led_on = 1;
    }
    if (fdd2_led_on && (int32_t) (now - fdd2_led_timeout) >= 0) {
        fdd2_led_on = 0;
    }

    uint8_t fdd1_active = fdd1_led_on;
    uint8_t fdd2_active = fdd2_led_on;
    uint8_t fdd1_track = (hw >> 8) & 0xFF;
    uint8_t fdd2_track = (hw >> 16) & 0xFF;

    if (fdd1_active != prev_fdd1_active || fdd1_track != prev_fdd1_track) {
        draw_track_display(TRK_A_Y, fdd1_track, fdd1_active);
        prev_fdd1_active = fdd1_active;
        prev_fdd1_track = fdd1_track;
    }
    if (fdd2_active != prev_fdd2_active || fdd2_track != prev_fdd2_track) {
        draw_track_display(TRK_B_Y, fdd2_track, fdd2_active);
        prev_fdd2_active = fdd2_active;
        prev_fdd2_track = fdd2_track;
    }

    uint8_t cur_rus = (*RUS_LED_STATUS & RUS_LED_ON) ? 1 : 0;
    if (cur_rus != prev_rus_led) {
        draw_led(LED_RUS_X, LED_RUS_Y, cur_rus ? PAL_LED_RED : PAL_BDARK);
        prev_rus_led = cur_rus;
    }
}

// Keyboard state

static int cur_key = 20;       // current highlighted key index in keys[] (init: Е)
static int cur_vrow = 1;       // current visual row index in vrows[]
static uint8_t sticky_mods;    // bit 0=Shift, 1=Ctrl, 2=RUS (sticky toggle)
static uint32_t sticky_lo;     // sticky matrix bits, rows 0-3
static uint32_t sticky_hi;     // sticky matrix bits, rows 4-7
static uint8_t momentary_mods; // momentary modifier state while A held

#define KEY_VVOD_IDX 13 // ВВОД = numpad row 0, position 0
#define KEY_BLK_IDX  14 // БЛК = numpad row 0, position 1 (display-only)
#define KEY_SBR_IDX  15 // СБР = numpad row 0, position 2
#define MOD_US_IDX   31 // УС = first key of row 2
#define MOD_SS_IDX   47 // СС = first key of row 3
#define KEY_RUS_IDX  62 // РУС = first key of row 4

static int mod_bit(int ki)
{
    if (ki == MOD_SS_IDX) {
        return 0;
    }
    if (ki == MOD_US_IDX) {
        return 1;
    }
    if (ki == KEY_RUS_IDX) {
        return 2;
    }
    return -1;
}

static int is_sticky(int ki)
{
    int mb = mod_bit(ki);
    if (mb >= 0) {
        return (sticky_mods & (1 << mb)) != 0;
    }
    uint8_t matrix = keys[ki].matrix;
    if (matrix == 0xFF) {
        return 0;
    }
    int row = (matrix >> 4) & 7;
    int col = matrix & 7;
    if (row < 4) {
        return (sticky_lo & (1u << (row * 8 + col))) != 0;
    }
    return (sticky_hi & (1u << ((row - 4) * 8 + col))) != 0;
}

// Key matrix output

static uint32_t vkb_lo, vkb_hi;

static void update_vkb(void)
{
    *VKB_KEYS_0 = vkb_lo | sticky_lo;
    *VKB_KEYS_1 = vkb_hi | sticky_hi;
    *VKB_SHIFT = momentary_mods | sticky_mods;
}

static void set_key_bit(uint8_t matrix, int on)
{
    if (matrix == 0xFF) {
        return;
    }
    int row = (matrix >> 4) & 7;
    int col = matrix & 7;
    if (row < 4) {
        uint32_t bit = 1u << (row * 8 + col);
        if (on) {
            vkb_lo |= bit;
        } else {
            vkb_lo &= ~bit;
        }
    } else {
        uint32_t bit = 1u << ((row - 4) * 8 + col);
        if (on) {
            vkb_hi |= bit;
        } else {
            vkb_hi &= ~bit;
        }
    }
}

static void release_all(void)
{
    vkb_lo = 0;
    vkb_hi = 0;
    sticky_lo = 0;
    sticky_hi = 0;
    sticky_mods = 0;
    momentary_mods = 0;
    update_vkb();
}

// Drawing

static void draw_bezels(void)
{
    osd_fill_rect(0, MAIN_Y - 4, OSD_WIDTH, 5 * KEY_H + 4 * GAP_V + 8, PAL_BEZEL);
}

static void draw_keys(void)
{
    for (unsigned i = 0; i < NUM_KEYS; i++) {
        const key_t *k = &keys[i];
        osd_fill_rect(k->x + 1, k->y + 1, k->w - 2, k->h - 2, k->fill_color);
        draw_key_border(k, PAL_BDARK);
        draw_legend(k, k->text_color);
    }
}

static uint8_t border_color_for(int ki)
{
    return is_sticky(ki) ? PAL_STICKY : PAL_BDARK;
}

static void draw_cursor(int ki)
{
    uint8_t color = is_sticky(ki) ? PAL_STICKY_CUR : PAL_TWHITE;
    draw_key_border(&keys[ki], color);
}

static void erase_cursor(int ki)
{
    draw_key_border(&keys[ki], border_color_for(ki));
}

static void redraw(void)
{
    osd_clear();
    draw_bezels();
    draw_keys();
    draw_indicators();
    draw_cursor(cur_key);
}

// Move the cursor by (dx, dy) on the visual keyboard grid.
//
// Vertical (dy): wraps rows circularly and finds the key in the target
// row whose horizontal center is nearest to the current key's center.
// This handles variable-width keys naturally — e.g. moving up from the
// 210px Space bar lands on the visually aligned key, not an arbitrary
// index.
//
// Horizontal (dx): steps by key index within the current visual row,
// wrapping at both ends.
//
// Both axes can be non-zero (vertical applied first, then horizontal),
// though the caller currently suppresses diagonals.
//
static void cursor_move(int dx, int dy)
{
    erase_cursor(cur_key);

    if (dy) {
        int new_vrow = cur_vrow + dy;
        if (new_vrow < 0) {
            new_vrow = NUM_VROWS - 1;
        }
        if (new_vrow >= NUM_VROWS) {
            new_vrow = 0;
        }

        int cur_cx = keys[cur_key].x + keys[cur_key].w / 2;
        int best = vrows[new_vrow].start;
        int best_dist = 9999; // > max possible distance (OSD is 512px wide)
        for (int i = 0; i < vrows[new_vrow].count; i++) {
            int ki = vrows[new_vrow].start + i;
            int kx = keys[ki].x + keys[ki].w / 2;
            int dist = cur_cx - kx;
            if (dist < 0) {
                dist = -dist;
            }
            // On ties, prefer the rightward key when moving down (scan
            // is left-to-right, so strict < already picks leftward on up)
            if (dist < best_dist || (dist == best_dist && dy > 0)) {
                best_dist = dist;
                best = ki;
            }
        }
        cur_key = best;
        cur_vrow = new_vrow;
    }

    if (dx) {
        int vcol = (cur_key - vrows[cur_vrow].start) + dx;
        int count = vrows[cur_vrow].count;
        if (vcol < 0) {
            vcol = count - 1;
        }
        if (vcol >= count) {
            vcol = 0;
        }
        cur_key = vrows[cur_vrow].start + vcol;
    }

    draw_cursor(cur_key);
}

// OSD close helper

static void close_osd(int *held_key_idx)
{
    erase_cursor(cur_key);
    if (*held_key_idx >= 0) {
        set_key_bit(keys[*held_key_idx].matrix, 0);
        *held_key_idx = -1;
    }
    // Reset all key borders to clean state before releasing
    for (unsigned i = 0; i < NUM_KEYS; i++) {
        draw_key_border(&keys[i], PAL_BDARK);
    }
    release_all();
    *OSD_CTRL = 0;
    *VKB_ACTIVE = 0;
}

static int ui_osd_active;
static int ui_osd_top;
static int ui_held_key_idx;
static uint16_t ui_prev_buttons;
static uint32_t ui_repeat_timer;  // rdcycle() deadline for next auto-repeat
static uint16_t ui_repeat_btn;    // dpad direction(s) held for repeat
static uint32_t ui_move_cooldown; // rdcycle() deadline suppressing next move

void vkb_ui_init(void)
{
    ui_osd_active = 0;
    ui_osd_top = 0;
    ui_held_key_idx = -1;
    ui_prev_buttons = *CONT1_KEY;
    ui_repeat_timer = 0;
    ui_repeat_btn = 0;
    ui_move_cooldown = 0;

    redraw();
}

void vkb_ui_tick(uint16_t buttons)
{
    uint16_t pressed = buttons & ~ui_prev_buttons;
    uint16_t released = ~buttons & ui_prev_buttons;

    if (pressed & BTN_L1) {
        ui_osd_active = !ui_osd_active;
        if (ui_osd_active) {
            draw_cursor(cur_key);
            *OSD_CTRL = OSD_ENABLE;
            *VKB_ACTIVE = 1;
        } else {
            close_osd(&ui_held_key_idx);
        }
    }

    update_indicators();

    if (!ui_osd_active) {
        ui_prev_buttons = buttons;
        return;
    }

    if (pressed & BTN_R1) {
        ui_osd_top = !ui_osd_top;
        *OSD_POS = ui_osd_top;
    }

    if (pressed & BTN_B) {
        ui_osd_active = 0;
        close_osd(&ui_held_key_idx);
        ui_prev_buttons = buttons;
        return;
    }

    if (pressed & BTN_A) {
        const key_t *k = &keys[cur_key];
        if (k->flags & KF_SPECIAL) {
            if (cur_key == KEY_VVOD_IDX) {
                *VKB_VVOD = 1;
            } else if (cur_key == KEY_SBR_IDX) {
                *VKB_SBR = 1;
            }
        } else {
            int mb = mod_bit(cur_key);
            if (mb >= 0) {
                momentary_mods |= (1 << mb);
            } else {
                set_key_bit(k->matrix, 1);
            }
            update_vkb();
            ui_held_key_idx = cur_key;
        }
    }

    if ((released & BTN_A) && ui_held_key_idx >= 0) {
        int mb = mod_bit(ui_held_key_idx);
        if (mb >= 0) {
            momentary_mods &= ~(1 << mb);
        } else {
            set_key_bit(keys[ui_held_key_idx].matrix, 0);
        }
        ui_held_key_idx = -1;
        update_vkb();
    }

    // X: toggle sticky on current key
    if (pressed & BTN_X) {
        const key_t *k = &keys[cur_key];
        if (!(k->flags & KF_SPECIAL)) {
            int mb = mod_bit(cur_key);
            if (mb >= 0) {
                sticky_mods ^= (1 << mb);
            } else if (k->matrix != 0xFF) {
                int row = (k->matrix >> 4) & 7;
                int col = k->matrix & 7;
                if (row < 4) {
                    sticky_lo ^= 1u << (row * 8 + col);
                } else {
                    sticky_hi ^= 1u << ((row - 4) * 8 + col);
                }
            }
            update_vkb();
            erase_cursor(cur_key);
            draw_cursor(cur_key);
        }
    }

    // Y: clear all stickies
    if (pressed & BTN_Y) {
        if (sticky_lo || sticky_hi || sticky_mods) {
            for (unsigned i = 0; i < NUM_KEYS; i++) {
                if (is_sticky(i)) {
                    draw_key_border(&keys[i], PAL_BDARK);
                }
            }
            sticky_lo = 0;
            sticky_hi = 0;
            sticky_mods = 0;
            update_vkb();
            draw_cursor(cur_key);
        }
    }

    // D-pad navigation with initial-delay auto-repeat.
    //
    // First press fires immediately (subject to cooldown).  If held
    // past REPEAT_DELAY (500ms), the direction auto-repeats at
    // REPEAT_RATE (100ms / 10 Hz).  MOVE_COOLDOWN (40ms) after each
    // move prevents accidental double-triggers on noisy input.
    // Diagonal presses are suppressed: vertical wins.
    uint16_t dpad = BTN_DPAD_UP | BTN_DPAD_DOWN | BTN_DPAD_LEFT | BTN_DPAD_RIGHT;
    uint16_t dpad_ev = pressed & dpad;
    uint32_t now = rdcycle();

    if (buttons & dpad) {
        if (pressed & dpad) {
            ui_repeat_btn = buttons & dpad;
            ui_repeat_timer = now + REPEAT_DELAY;
            if ((int32_t) (now - ui_move_cooldown) < 0) {
                dpad_ev = 0;
            }
        } else if ((int32_t) (now - ui_repeat_timer) >= 0) {
            dpad_ev |= ui_repeat_btn;
            ui_repeat_timer = now + REPEAT_RATE;
        }
    } else {
        ui_repeat_btn = 0;
        // Reset cooldown to "now" so the next fresh press after a full
        // release is never suppressed.  (Post-move cooldown is set below.)
        ui_move_cooldown = now;
    }

    // Diagonal suppression: if both axes fire, keep vertical only
    if ((dpad_ev & (BTN_DPAD_UP | BTN_DPAD_DOWN)) && (dpad_ev & (BTN_DPAD_LEFT | BTN_DPAD_RIGHT))) {
        dpad_ev &= BTN_DPAD_UP | BTN_DPAD_DOWN;
    }

    if (dpad_ev & BTN_DPAD_UP) {
        cursor_move(0, -1);
    }
    if (dpad_ev & BTN_DPAD_DOWN) {
        cursor_move(0, 1);
    }
    if (dpad_ev & BTN_DPAD_LEFT) {
        cursor_move(-1, 0);
    }
    if (dpad_ev & BTN_DPAD_RIGHT) {
        cursor_move(1, 0);
    }

    if (dpad_ev) {
        ui_move_cooldown = now + MOVE_COOLDOWN;
    }

    ui_prev_buttons = buttons;
}
