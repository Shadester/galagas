#include "video.h"
#include "assets.h"
#include "aga.h"
#include <stddef.h>
#include "game.h"                                  /* NAL and EBN: 40 aliens and 8 bombs */

#define CUSTOM ((volatile u16 *)0xdff000)
#define W(reg) (CUSTOM[(reg) / 2])
#define L(reg) (*(volatile u32 *)(0xdff000 + (reg)))
#define DMACONR W(0x002)

/* A bitmap is 448 pixels wide (the screen has 64 pixels of guard on each side: a sprite needs no clipping at the sides, and the playfield below
 * the hud can be shown scrolled by up to 48 pixels): 56 bytes a row of a plane, NPL planes a line (32 colours). */
#define STRIDE 56
#define GUARD 64
/* The number of bitplanes is chosen at start-up (video_init): 5 (32 colours, OCS) or 6 (64 colours, AGA). -DFORCE_NPL6 tests the layout of 6 planes on any machine (the
 * extra plane is empty, and OCS shows 6 planes as extra half-brite: the picture is the same). fast.s reads video_npl. */
int video_npl = 5;
static int rowb = STRIDE * 5;                     /* bytes of a line of the bitmap: all planes */
extern u32 aga_block;                             /* hw.s: the memory that the bootblock gave an AGA machine (0: none) */
extern u8 hw_aga;
static int aga_mode;                              /* 1: AGA: 6 planes, 64 colours, the AGA sprites, a 24-bit palette */
/* The bitplane fetch: OCS 16 bits (a word) at a time, AGA (FMODE 3) 64 bits: a quarter of the DMA slots. On OCS the fetch starts one word early (the hidden word), so the
 * playfield below the hud can be shown scrolled by the copper (the formation sways without being drawn again). An AGA machine in FMODE 3 cannot do that (its fetch cannot start
 * earlier): there the formation is drawn where it is (video_can_scroll). */
static int fm3;                                   /* 1: FMODE 3 */
static int unit_bits = 4, unit_bytes = 2, fetch_bytes = 42, hidden_bytes = 2;
int video_can_scroll(void) { return !fm3; }
static const SpriteInfo *spr_tab = sprites;       /* the sprites (the AGA set has 6 planes) */
static const u16 *spr_words = sprite_words;
static const u32 *pal_game, *pal_title;           /* the AGA palettes: 64 longs 0x00RRGGBB */
static const u16 *title_ptr = title_words;
#define NPL video_npl
#define ROWB rowb
#ifdef FORCE_NPL6
#define MEM_PLANES 6
#else
#define MEM_PLANES 5
#endif
#define BITMAP_BYTES (STRIDE * MEM_PLANES * SCREEN_H)
#define MAX_RECTS 96
#define MAX_OBJ (NAL + 3 + 4 + EBN)                /* sprite slots (main.c): aliens, ship, dual, captive, player shots, bombs */
#define MAX_TEXTS 8

typedef struct { s16 xw, wd, y, h; } Rect;       /* words from the left of the bitmap, width in words, lines */
typedef struct {
    Rect rect[MAX_RECTS];                         /* what the CPU drew (text, beam): cleared at the start of the next use of this bitmap */
    int nrect;
} Dirty;

/* Where a sprite is in a bitmap, with all the blitter needs (computed once, when the sprite moves). fast.s knows the offsets (checked below). */
typedef struct { Rect r; u32 dst, bob, mask, bits; u16 con0, size, mod; u8 has, r0, r1, pad; u16 rows; } Place;   /* bits: the word columns, r0 .. r1: the 16-line rows that it touches, rows: a bit for each of them */
typedef struct { Place p[2]; Place *cur; } Slot;      /* the place now, and the one before: that one is still in the bitmap until it is cleared */
typedef struct { Slot *s; Place *old; } Dirt;       /* a slot that is drawn again in this frame, and the place to clear first (0: none) */
_Static_assert(sizeof(Place) == 36 && offsetof(Place, rows) == 34 && offsetof(Place, dst) == 8 && offsetof(Place, bob) == 12 && offsetof(Place, mask) == 16 && offsetof(Place, bits) == 20 &&
               offsetof(Place, con0) == 24 && offsetof(Place, size) == 26 && offsetof(Place, mod) == 28 && offsetof(Place, has) == 30 &&
               offsetof(Place, r0) == 31 && offsetof(Place, r1) == 32 && sizeof(Slot) == 76 && sizeof(Obj) == 6 && MAX_OBJ == 55 && TOP == 28 && SCREEN_H == 256 && GUARD == 64 && STRIDE == 56 && offsetof(Slot, cur) == 72 && sizeof(Dirt) == 8,
               "fast.s: Place, Slot");

extern volatile u32 vbl_count;
static u32 published;                             /* vbl_count when a bitmap was handed to the copper: it is shown at the next vertical blank */
#define NBMP 3                                    /* three bitmaps: one shown, one waiting for its vertical blank, one drawn into: no waiting */
static u16 bitmap_mem[NBMP][BITMAP_BYTES / 2];     /* the bitmaps of an OCS machine */
static u16 *bmp[NBMP];                            /* where the bitmaps are */
static Dirty dirty[NBMP];
static Obj drawn[NBMP][MAX_OBJ];                  /* the sprites that a bitmap shows */
static Slot slots[NBMP][MAX_OBJ];
Obj want[MAX_OBJ];                                /* the sprites of this frame (video_bob in video.h writes them) */
static int back;                                  /* the bitmap that is drawn into */
static int shown = 0, pending = -1;               /* the bitmap on the screen; the one handed to the copper at the last video_end, not yet shown */
#define COPLEN 400
static u16 copper[NBMP][COPLEN];                  /* a copper list for each bitmap (see build_copper) */
static int cop_title[NBMP];                       /* the palette that is in a list: 1 title, 0 game */
static int scroll_d;                              /* this frame: the playfield below the hud is shown shifted to the right by this many pixels */
static const u16 no_sprite[2] = {0, 0};          /* a sprite list with nothing in it */
static struct { s16 x, y; u8 on; } ship_req[2];   /* the hardware fighters and shots of this frame (see below) */
static struct { s16 x, y; u8 hw; } shot_req[4];
static int nshot_req;
static void stars_init(void);
u32 row_off[SCREEN_H];                            /* the bytes of the lines of a bitmap (a table is faster than a multiplication: fast.s) */
static int cop_bpl, cop_spr, cop_bpl2, cop_con1;   /* indexes in the copper list: the palette values, the bitplane pointers (hud, playfield), the sprite pointers, BPLCON1 of the playfield */

/* What the frame asks for. Nothing is drawn until video_end: a sprite that has not changed since this bitmap was drawn last
 * is not drawn again (the formation moves once in about 9 ticks), unless something else is cleared or drawn over it. */
typedef struct { char s[24]; s16 x, y, colour; } TextReq;
static TextReq text_req[MAX_TEXTS];
static int ntext;
static struct { s16 x, y, rows, phase; } beam_req;                   /* rows 0: no beam */
static Rect old_ov[MAX_RECTS], new_ov[MAX_RECTS];                    /* rects of text and beam: cleared at the start / drawn now */
static int nold_ov, nnew_ov;

static void wait_blit(void) {
    (void)DMACONR;
    while (DMACONR & 0x4000) ;
}
void video_wait_blitter(void) { wait_blit(); }

static int pal_hi[64], pal_lo[64];                /* where the value of a colour is in the copper list: AGA writes the high and the low nibbles of the 24 bits one after the other */
static void copper_set_palette(int b, int title) {
    int i;
    if (!aga_mode) {
        const u16 *pal = title ? title_palette : game_palette;
        for (i = 0; i < 32; ++i) copper[b][pal_hi[i]] = pal[i];
    } else {
        const u32 *pal = title ? pal_title : pal_game;
        for (i = 0; i < 64; ++i) {
            u32 c = pal[i];
            copper[b][pal_hi[i]] = (c >> 12 & 0xf00) | (c >> 8 & 0xf0) | (c >> 4 & 0xf);          /* the high nibbles */
            copper[b][pal_lo[i]] = (c >> 8 & 0xf00) | (c >> 4 & 0xf0) | (c & 0xf);                /* the low nibbles (BPLCON3 LOCT) */
        }
    }
}

/* The copper list of a bitmap: the setup, the palette, the bitplane pointers for the hud (lines 0 .. TOP - 1, never scrolled), the sprite pointers, then
 * at the end of the line TOP - 1 (in the horizontal blank) the pointers and BPLCON1 for the playfield, which is shown scrolled by scroll_d.
 * The fetch starts one word early (DDFSTRT 0x30): the first word is hidden, and BPLCON1 delays the picture to the right by 0 .. 15 pixels. */
static void build_copper(int b) {
    u16 *c = copper[b];
    int i;
#define MOVE(reg, val) (*c++ = (reg), *c++ = (val))
    MOVE(0x100, NPL << 12 | 0x200);              /* BPLCON0: NPL bitplanes, lores, colour */
    MOVE(0x102, 0); MOVE(0x104, aga_mode ? 4 | 0x200 : 4);   /* BPLCON1, BPLCON2 (AGA: 6 planes are 64 colours, not extra half-brite) */
    if (aga_mode) { MOVE(0x1fc, fm3 ? 3 : 0); MOVE(0x10c, 0x0011); }   /* FMODE: bitplane fetch 64 bits, sprites 16 bits wide; BPLCON4: the sprite colours 16 .. 31 */
    MOVE(0x108, ROWB - fetch_bytes); MOVE(0x10a, ROWB - fetch_bytes);   /* BPL1MOD, BPL2MOD: the rest of the line of the planes (OCS: 21 words are fetched, AGA: 24) */
    if (fm3) { MOVE(0x092, 0x38); MOVE(0x094, 0xb8); }   /* DDFSTRT, DDFSTOP: the plain fetch of 320 pixels: 5 blocks of 4 words */
    else { MOVE(0x092, 0x30); MOVE(0x094, 0xd0); }       /* (OCS: 21 words, the first one hidden) */
    MOVE(0x08e, 0x2c81); MOVE(0x090, 0x2cc1);     /* DIWSTRT, DIWSTOP: 320 x 256, PAL */
    if (!aga_mode) {
        for (i = 0; i < 32; ++i) { pal_hi[i] = c - copper[b] + 1; MOVE(0x180 + 2 * i, 0); }
    } else {                                      /* 64 colours: two banks of 32 (BPLCON3), each written twice: the high nibbles, then the low nibbles (LOCT) */
        int bank, k;
        for (bank = 0; bank < 2; ++bank) {
            MOVE(0x106, 0x0c00 | bank << 13);
            for (k = 0; k < 32; ++k) { pal_hi[bank * 32 + k] = c - copper[b] + 1; MOVE(0x180 + 2 * k, 0); }
            MOVE(0x106, 0x0e00 | bank << 13);
            for (k = 0; k < 32; ++k) { pal_lo[bank * 32 + k] = c - copper[b] + 1; MOVE(0x180 + 2 * k, 0); }
        }
        MOVE(0x106, 0x0c00);
    }
    cop_bpl = c - copper[b] + 1;
    for (i = 0; i < NPL; ++i) { MOVE(0xe0 + 4 * i, 0); MOVE(0xe2 + 4 * i, 0); }
    cop_spr = c - copper[b] + 1;
    for (i = 0; i < 8; ++i) { MOVE(0x120 + 4 * i, (u32)no_sprite >> 16); MOVE(0x122 + 4 * i, (u32)no_sprite & 0xffff); }
    *c++ = ((0x2c + TOP - 1) << 8) | 0xd9; *c++ = 0xfffe;     /* WAIT: the end of the last hud line, after the fetch */
    cop_bpl2 = c - copper[b] + 1;
    for (i = 0; i < NPL; ++i) { MOVE(0xe0 + 4 * i, 0); MOVE(0xe2 + 4 * i, 0); }
    cop_con1 = c - copper[b] + 1;
    MOVE(0x102, 0);
    *c++ = 0xffff; *c++ = 0xfffe;                 /* the end */
#undef MOVE
}

int video_is_aga(void) { return aga_mode; }

void video_init(void) {
    int i, b;
#ifdef FORCE_NPL6
    video_npl = 6;
#endif
    for (b = 0; b < NBMP; ++b) bmp[b] = bitmap_mem[b];
#ifndef FORCE_OCS                                 /* test: an AGA machine plays the OCS game */
    if (hw_aga && aga_block) {                    /* an AGA machine, and the bootblock has read the AGA data */
#else
    if (0) {
#endif
        const AgaHeader *h = (const AgaHeader *)aga_block;
        if (h->magic[0] == 'A' && h->magic[1] == 'G' && h->magic[2] == 'A' && h->magic[3] == '1') {
            u32 *z = (u32 *)(aga_block + h->size);
            aga_mode = 1;
#ifndef AGA_FMODE0
            fm3 = 1; fetch_bytes = 40; hidden_bytes = 0;      /* no hidden block: AGA cannot start its fetch earlier than 0x38 (tested), so there is no copper scroll (can_scroll) */
#endif
            video_npl = AGA_NPL;
            spr_tab = (const SpriteInfo *)(aga_block + h->spr_off);
            spr_words = (const u16 *)(aga_block + h->words_off);
            pal_game = (const u32 *)(aga_block + h->pal_off);
            pal_title = (const u32 *)(aga_block + h->tpal_off);
            title_ptr = (const u16 *)(aga_block + h->title_off);
            for (b = 0; b < NBMP; ++b) bmp[b] = (u16 *)(aga_block + h->size + b * (STRIDE * AGA_NPL * SCREEN_H));
            for (i = 0; i < NBMP * STRIDE * AGA_NPL * SCREEN_H / 4; ++i) z[i] = 0;   /* AllocMem does not clear */
        }
    }
    rowb = STRIDE * video_npl;
    for (i = 0; i < SCREEN_H; ++i) row_off[i] = i * ROWB;
    W(0x044) = 0xffff; W(0x046) = 0xffff;         /* BLTAFWM, BLTALWM, BLTAMOD, BLTBMOD: the same for every blit of a sprite (fast.s) */
    W(0x064) = 0; W(0x062) = 0;
    for (b = 0; b < NBMP; ++b) {
        for (i = 0; i < MAX_OBJ; ++i) slots[b][i].cur = &slots[b][i].p[0];
        build_copper(b);
        copper_set_palette(b, 0);
        for (i = 0; i < NPL; ++i) {
            u32 p = (u32)bmp[b] + GUARD / 8 - hidden_bytes + i * STRIDE;
            copper[b][cop_bpl + 4 * i] = p >> 16; copper[b][cop_bpl + 4 * i + 2] = p & 0xffff;
            copper[b][cop_bpl2 + 4 * i] = p >> 16; copper[b][cop_bpl2 + 4 * i + 2] = p & 0xffff;
        }
    }
    L(0x080) = (u32)copper[0];                    /* COP1LC */
    W(0x088) = 0;                                 /* COPJMP1 */
    stars_init();
#ifdef AGA_NOSPR                                  /* test: no sprite DMA */
    W(0x096) = 0x8fc0;
#else
    W(0x096) = 0x8fe0;                            /* DMACON: set, master, bitplanes, copper, blitter, sprites, and the blitter before the CPU */
#endif
    back = 1;
    shown = 0;
}

/* The playfield (below the hud) is shown shifted to the right by d pixels (-48 .. 48): the formation sways without being drawn again. Call it
 * in every frame, before the sprites: they are drawn at x - d. */
void video_scroll(int d) { scroll_d = fm3 ? 0 : d; }

static void clear_rect(const Rect *r) {
    if (r->h * NPL > 1000) {                      /* a blit has at most 1024 lines: of all planes (the title picture with 6 planes) */
        Rect a = *r, b = *r;
        a.h = r->h / 2; b.y += a.h; b.h = r->h - a.h;
        clear_rect(&a); clear_rect(&b);
        return;
    }
    wait_blit();
    W(0x040) = 0x0100;                            /* BLTCON0: D only, all minterm bits 0 = clear */
    W(0x042) = 0;
    W(0x066) = STRIDE - 2 * r->wd;                /* BLTDMOD */
    L(0x054) = (u32)bmp[back] + r->y * ROWB + r->xw * 2;     /* BLTDPT */
    W(0x058) = ((r->h * NPL) << 6) | r->wd;         /* BLTSIZE: starts the blitter */
}

static int static_mode;                           /* drawing the static layer: it is drawn at once and not cleared in every frame */

static void add_dirty(int xw, int wd, int y, int h) {      /* the CPU drew here: clear it when this bitmap is used again */
    Dirty *d = &dirty[back];
    Rect *r;
    if (d->nrect >= MAX_RECTS) return;
    r = &d->rect[d->nrect++];
    r->xw = xw; r->wd = wd; r->y = y; r->h = h;
}

/* A bitmap that was handed to the copper is on the screen after the next vertical blank: from then on it is the shown one. This must be
 * checked whenever a bitmap is chosen or handed over, or the bitmap on the screen could be taken for a free one. */
static void settle_display(void) {
    if (pending >= 0 && vbl_count != published) { shown = pending; pending = -1; }
}

void video_begin(void) {
    Dirty *d;
    int i;
    settle_display();
    for (back = 0; back == shown || back == pending; ++back) ;                          /* the third one is free */
    d = &dirty[back];
    nold_ov = d->nrect;
    for (i = 0; i < d->nrect; ++i) { old_ov[i] = d->rect[i]; clear_rect(&d->rect[i]); }
    d->nrect = 0;
    for (i = NAL; i < MAX_OBJ; ++i) { want[i].id = -1; want[i].x = want[i].y = 0; }     /* (the aliens: main.c sets all of their slots in every frame) */
    ntext = nnew_ov = 0;
    ship_req[0].on = ship_req[1].on = 0;
    nshot_req = 0;
    beam_req.rows = 0;
}

/* The hud (score, lives) changes seldom: a part of it is drawn again in a bitmap only when its value has changed. The text and the lives are
 * sprites for the blitter, as everything else. Part 0 is the labels: when they are drawn (the first time in a bitmap, or after the title picture
 * was in it) the whole band is cleared, so all other parts follow. */
#define HUD_PARTS 5
static int hud_key[NBMP][HUD_PARTS] = {{-1, -1, -1, -1, -1}, {-1, -1, -1, -1, -1}, {-1, -1, -1, -1, -1}};
static const struct { s16 x, y, w, h; } hud_area[HUD_PARTS] = {{0, 0, SCREEN_W, TOP}, {8, 12, 48, 9}, {136, 12, 48, 9}, {264, 12, 16, 9}, {64, 2, 56, 26}};   /* px */

static void hud_reset(int b) {
    int i;
    for (i = 0; i < HUD_PARTS; ++i) hud_key[b][i] = -1;
}

int video_hud(int part, int value) {
    int *k = hud_key[back], i;
    Rect r;
    int x0, x1;
    if (k[part] == value) return 0;
    if (part == 0) for (i = 1; i < HUD_PARTS; ++i) k[i] = -1;
    k[part] = value;
    x0 = hud_area[part].x + GUARD; x1 = x0 + hud_area[part].w - 1;
    r.xw = x0 >> 4; r.wd = (x1 >> 4) - (x0 >> 4) + 1; r.y = hud_area[part].y; r.h = hud_area[part].h;
    clear_rect(&r);
    wait_blit();
    static_mode = 1;
    return 1;
}

void video_static_end(void) { static_mode = 0; }

/* ---- the stars: hardware sprites 4 and 5 (the CPU is too slow to draw them: it gets few memory cycles while the screen is shown).
 * Each sprite channel shows many stars: a list of one-pixel objects, one below the other. Like in the arcade game, the stars
 * move down in fixed columns, in two layers (1 and 2 pixels a tick). Sprites 4 and 5 use the colours 25, 26 and 27 (mid, dim, bright). ---- */
#define STAR_N 12                                 /* stars in a layer */
#define STAR_H (SCREEN_H - 16 - TOP)              /* the stars stay between the hud and the lives */
#define STAR_HOFF 128                             /* hardware sprite position of the left edge of the screen (to check in the emulator) */
typedef struct { s16 base; u8 hsx, hs1; u16 da, db; } Star;      /* base: line (ascending); hsx, hs1: SPRxPOS and the low bit of SPRxCTL; the pixel: plane a, plane b */
_Static_assert(sizeof(Star) == 8 && STAR_N == 12 && STAR_H == 212, "fast.s: stars_layer");
static Star stars[2][STAR_N];
static u16 star_t0[STAR_H], star_t1[STAR_H];     /* the words of a list that depend on the line: VSTART (and the beam line of the sprite), VSTOP and its high bits */
static u16 star_list[NBMP][2][STAR_N * 4 + 2];
static int star_scroll[2] = {-1, -1};             /* the offset of the layers (-1: no stars, the title screen) */

static void stars_init(void) {
    u32 r = 12345;
    int g, i;
    for (g = 0; g < 2; ++g)
        for (i = 0; i < STAR_N; ++i) {
            int hs, col;
            r = r * 1103515245u + 12345u;
            stars[g][i].base = i * (STAR_H / STAR_N) + ((r >> 16) % 9);                  /* ascending, at least 4 lines apart */
            hs = STAR_HOFF + (r >> 20) % SCREEN_W;
            stars[g][i].hsx = hs >> 1 & 255; stars[g][i].hs1 = hs & 1;
            col = g ? ((r >> 12) & 1 ? 3 : 1) : ((r >> 12) & 3 ? 2 : 1);                /* layer 0: dim; layer 1: bright and mid */
            stars[g][i].da = col & 1 ? 0x8000 : 0;
            stars[g][i].db = col & 2 ? 0x8000 : 0;
        }
    for (i = 0; i < STAR_H; ++i) {
        int v = 0x2c + TOP + i;                                                         /* the beam line of the sprite */
        star_t0[i] = (v & 255) << 8;
        star_t1[i] = ((v + 1) & 255) << 8 | (v >> 8 & 1) << 2 | ((v + 1) >> 8 & 1) << 1;   /* stop one line below */
    }
}

/* The scroll offsets of the two layers, 0 .. STAR_H - 1 (the CPU is slow: no division here); a negative one: no stars */
void video_stars(int slow, int fast) {
    star_scroll[0] = slow; star_scroll[1] = fast;
}

#ifdef NOASM
static void stars_layer(u16 *l, const Star *st, int off, const u16 *t0, const u16 *t1) {
    int n = 0, first = 0, k;
    while (first < STAR_N && st[first].base + off < STAR_H) ++first;          /* from here the stars wrapped to the top: they come first */
    for (k = 0; k < STAR_N; ++k) {
        int j = first + k, y;
        if (j >= STAR_N) j -= STAR_N;
        y = st[j].base + off;
        if (y >= STAR_H) y -= STAR_H;
        l[n++] = t0[y] | st[j].hsx;
        l[n++] = t1[y] | st[j].hs1;
        l[n++] = st[j].da;
        l[n++] = st[j].db;
    }
    l[n++] = 0; l[n] = 0;
}
#else
void stars_layer(u16 *l, const Star *st, int off, const u16 *t0, const u16 *t1);     /* fast.s */
#endif

static void build_stars(int b) {
    int g;
    for (g = 0; g < 2; ++g) {
        if (star_scroll[g] >= 0) stars_layer(star_list[b][g], stars[g], star_scroll[g], star_t0, star_t1);
        else star_list[b][g][0] = star_list[b][g][1] = 0;
    }
}


/* ---- the fighter and its shots are hardware sprites: no blitter, no clearing, nothing drawn over. The fighter is two attached sprites (0 + 1, and 2 + 3 for the second
 * fighter of a dual): 16 x SHIP_HW_H pixels, 15 colours (entries 17 .. 31). The shots (2 pixels wide) are sprites 6 and 7: a channel shows one shot below the other. The lists are
 * made in video_end, like the stars. A shot that does not fit in a channel is drawn by the blitter (video_shots says which). ---- */
#define SHIP_LIST (2 + SHIP_HW_H * 2 + 2)
#define SHOT_LIST (2 * (2 + SHOT_HW_H * 2) + 2)
static u16 ship_list[NBMP][4][SHIP_LIST];
static u16 shot_list[NBMP][2][SHOT_LIST];
void video_ship(int n, int x, int y) { ship_req[n].x = x; ship_req[n].y = y; ship_req[n].on = 1; }

static u16 *hw_head(u16 *l, int x, int y, int h, int attach) {       /* the two first words of a sprite: SPRxPOS, SPRxCTL */
    int hs = STAR_HOFF + x, v = 0x2c + y;
    *l++ = (v & 255) << 8 | (hs >> 1 & 255);
    *l++ = ((v + h) & 255) << 8 | (v >> 8 & 1) << 2 | ((v + h) >> 8 & 1) << 1 | (hs & 1) | (attach ? 0x80 : 0);
    return l;
}

/* The shots of this frame (x, y: the top left in screen pixels, not scrolled): sets hw[i] to 1 for the ones that a sprite shows. */
void video_shots(const s16 *x, const s16 *y, int n, u8 *hw) {
    int i, j, last[2] = {-1000, -1000}, order[4], c;
    nshot_req = 0;
    for (i = 0; i < n; ++i) { order[i] = i; hw[i] = 0; }
    for (i = 1; i < n; ++i) { int t = order[i]; for (j = i; j > 0 && y[order[j - 1]] > y[t]; --j) order[j] = order[j - 1]; order[j] = t; }   /* by y: a channel needs them in this order */
    for (i = 0; i < n; ++i) {
        int k = order[i], v = 0x2c + y[k];
        for (c = 0; c < 2; ++c) if (v >= last[c] + 2) break;
        if (c == 2) continue;
        last[c] = v + SHOT_HW_H;
        hw[k] = 1;
        shot_req[nshot_req].x = x[k]; shot_req[nshot_req].y = y[k]; shot_req[nshot_req].hw = c; ++nshot_req;
    }
}

static void build_hw(int b) {
    int n, k;
    for (n = 0; n < 2; ++n) {
        u16 *e = ship_list[b][2 * n], *o = ship_list[b][2 * n + 1];
        if (ship_req[n].on) {
            e = hw_head(e, ship_req[n].x, ship_req[n].y, SHIP_HW_H, 0);
            o = hw_head(o, ship_req[n].x, ship_req[n].y, SHIP_HW_H, 1);
            for (k = 0; k < SHIP_HW_H * 2; ++k) { *e++ = ship_hw_even[k]; *o++ = ship_hw_odd[k]; }
        }
        *e++ = 0; *e = 0; *o++ = 0; *o = 0;
    }
    {
        u16 *l[2] = {shot_list[b][0], shot_list[b][1]};
        for (n = 0; n < nshot_req; ++n) {
            int c = shot_req[n].hw;
            l[c] = hw_head(l[c], shot_req[n].x, shot_req[n].y, SHOT_HW_H, 0);
            for (k = 0; k < SHOT_HW_H * 2; ++k) *l[c]++ = shot_hw[k];
        }
        *l[0]++ = 0; *l[0] = 0; *l[1]++ = 0; *l[1] = 0;
    }
}

/* ---- sprites ---- */

/* The place of an Obj in the bitmap that is drawn into: clipped at the top (the hud: lines above `top`) and at the bottom. has 0: nothing to draw. */
static void place_fill(const Obj *o, Place *p, int top) {
    const SpriteInfo *s;
    int w, h, skip = 0, y, xb, xw, rowwords;
    p->has = 0;
    if (o->id < 0) return;
    s = &spr_tab[o->id];
    w = s->w; h = s->h; y = o->y; xb = o->x + GUARD; xw = xb >> 4;
    if (xb < 0 || xw + w > STRIDE / 2 - 1) return;             /* the guard of 32 pixels is enough for every sprite we draw */
    if (y < top) { skip = top - y; y = top; }
    if (skip >= h) return;
    if (y + (h - skip) > SCREEN_H) h = SCREEN_H - y + skip;
    if (h <= skip) return;
    h -= skip;
    rowwords = (w + 1) * NPL;
    p->r.xw = xw; p->r.wd = w + 1; p->r.y = y; p->r.h = h;
    p->dst = (u32)bmp[back] + y * ROWB + xw * 2;
    p->bob = (u32)(spr_words + s->bob + skip * rowwords);
    p->mask = (u32)(spr_words + s->mask + skip * rowwords);
    p->bits = ((1UL << (w + 1)) - 1) << xw;
    p->con0 = 0x0fca | (xb & 15) << 12;                       /* BLTCON0: A, B, C, D; D = A B + /A C (A the mask, B the picture, C the screen); the shift of B */
    p->size = (h * NPL) << 6 | (w + 1);
    p->mod = STRIDE - 2 * (w + 1);
    p->r0 = y >> 4; p->r1 = (y + h - 1) >> 4;
    p->rows = (2 << p->r1) - (1 << p->r0);
    p->has = 1;
}

static void blit_place(const Place *p) {
    wait_blit();
    W(0x040) = p->con0;
    W(0x042) = p->con0 & 0xf000;                  /* BLTCON1: the shift of B */
    W(0x044) = 0xffff; W(0x046) = 0xffff;         /* BLTAFWM, BLTALWM */
    W(0x064) = 0; W(0x062) = 0;                   /* BLTAMOD, BLTBMOD */
    W(0x060) = p->mod; W(0x066) = p->mod;         /* BLTCMOD, BLTDMOD */
    L(0x050) = p->mask;
    L(0x04c) = p->bob;
    L(0x048) = p->dst; L(0x054) = p->dst;
    W(0x058) = p->size;
}

#ifdef NOASM
static void clear_place(const Place *p) {
    wait_blit();
    W(0x040) = 0x0100;                            /* BLTCON0: D only, all minterm bits 0 = clear */
    W(0x042) = 0;
    W(0x066) = p->mod;
    L(0x054) = p->dst;
    W(0x058) = p->size;
}
#endif

/* A sprite of the static layer (the lives): drawn at once. */
void video_static_bob(int id, int x, int y) {
    Obj o = {id, x, y};
    Place p;
    place_fill(&o, &p, 0);
    if (p.has) blit_place(&p);
}

/* What the frame does to a bitmap (draw_sprites): a sprite is kept (no clear, no blit) when it is the same as the bitmap shows, and nothing
 * is cleared or drawn over it. The sprites that change (and the ones that are drawn over) are in the list dl. */
#define OBJ_PAD 56                                /* MAX_OBJ rounded up to a multiple of 4 (fast.s copies the flags by longs) */
static u8 hasv[NBMP][OBJ_PAD];                    /* the slot has a place in this bitmap */
static u8 keep[OBJ_PAD];                          /* it stays (it has a place, and nothing is cleared or drawn over it) */
static u8 todo[OBJ_PAD];                          /* it is drawn in this frame */
static Dirt dl[MAX_OBJ];
static u32 mark[SCREEN_H / 16];                   /* the cells (a bit for each word column, a u32 for each 16 lines) that something changes */

#ifdef NOASM
/* the sprites that changed since this bitmap was drawn: their new places; returns how many (the length of dl) */
static int sprites_scan(Slot *sl, Obj *dr, const Obj *w, u8 *keep, u8 *hasv, u8 *todo, Dirt *dl, u32 base, const SpriteInfo *spr, const u16 *words) {
    int s, n = 0;
    for (s = 0; s < OBJ_PAD; ++s) { keep[s] = hasv[s]; todo[s] = 0; }
    for (s = 0; s < MAX_OBJ; ++s) {
        const Obj *o = &w[s];
        Obj *d = &dr[s];
        Slot *q = &sl[s];
        Place *old, *nw;
        if (o->id == d->id && (o->id < 0 || (o->x == d->x && o->y == d->y))) continue;      /* the same sprite at the same place */
        old = q->cur;
        nw = old == &q->p[0] ? &q->p[1] : &q->p[0];
        dl[n].s = q; dl[n].old = old->has ? old : 0; ++n;
        *d = *o;
        place_fill(o, nw, TOP);
        q->cur = nw;
        keep[s] = 0;
        hasv[s] = todo[s] = nw->has;
    }
    return n;
}

static void mark_place(u32 *mark, const Place *p) {
    int row;
    for (row = p->r0; row <= p->r1; ++row) mark[row] |= p->bits;
}

static void mark_rect(u32 *mark, const Rect *r) {
    u32 bits = ((1UL << r->wd) - 1) << r->xw;
    int row;
    for (row = r->y >> 4; row <= (r->y + r->h - 1) >> 4; ++row) mark[row] |= bits;
}

/* A sprite that stays is drawn again only if something is cleared or drawn over it: the cells that a changed sprite or a text touches are
 * marked, and a sprite that stays is checked against the marks. Returns the new length of dl. */
static int sprites_mark(Slot *sl, u32 *mark, u8 *keep, u8 *todo, Dirt *dl, int n, const Rect *ov_old, int nold, const Rect *ov_new, int nnew) {
    int s, i, again;
    for (i = 0; i < SCREEN_H / 16; ++i) mark[i] = 0;
    for (i = 0; i < nold; ++i) mark_rect(mark, &ov_old[i]);
    for (i = 0; i < nnew; ++i) mark_rect(mark, &ov_new[i]);
    for (i = 0; i < n; ++i) {
        if (dl[i].old) mark_place(mark, dl[i].old);
        if (dl[i].s->cur->has) mark_place(mark, dl[i].s->cur);
    }
    do {
        again = 0;
        for (s = 0; s < MAX_OBJ; ++s) {
            Place *p = sl[s].cur;
            int row, hit = 0;
            if (!keep[s]) continue;
            for (row = p->r0; row <= p->r1; ++row) if (mark[row] & p->bits) { hit = 1; break; }
            if (!hit) continue;
            keep[s] = 0;                          /* it is cleared and drawn again, and so it marks its cells too */
            todo[s] = 1;
            dl[n].s = &sl[s]; dl[n].old = p; ++n;
            mark_place(mark, p);
            again = 1;
        }
    } while (again);
    return n;
}

static void sprites_clear(const Dirt *dl, int n) {
    int i;
    for (i = 0; i < n; ++i) if (dl[i].old) clear_place(dl[i].old);
}

static void sprites_blit(const Slot *sl, const u8 *todo) {
    int s;
    for (s = 0; s < MAX_OBJ; ++s) if (todo[s]) blit_place(sl[s].cur);
}
#else
/* fast.s */
int sprites_scan(Slot *sl, Obj *dr, const Obj *w, u8 *keep, u8 *hasv, u8 *todo, Dirt *dl, u32 base, const SpriteInfo *spr, const u16 *words);
int sprites_mark(Slot *sl, u32 *mark, u8 *keep, u8 *todo, Dirt *dl, int n, const Rect *ov_old, int nold, const Rect *ov_new, int nnew);
void sprites_clear(const Dirt *dl, int n);
void sprites_blit(const Slot *sl, const u8 *todo);
#endif

static void beam_now(void);
#ifdef PROFILE2
u32 prof_acc[12]; int prof_on;
extern u32 now_lines(void);
extern u32 prof_changed;
#define PT(i, t0) do { u32 t1_ = now_lines(); if (prof_on) prof_acc[i] += t1_ - (t0); (t0) = t1_; } while (0)
#else
#define PT(i, t0) ((void)0)
#endif

static void draw_sprites(void) {
#ifdef PROFILE2
    u32 pt = now_lines();
#endif
    Slot *sl = slots[back];
    int n = sprites_scan(sl, drawn[back], want, keep, hasv[back], todo, dl, (u32)bmp[back], spr_tab, spr_words);
    PT(4, pt);
#ifdef NOSKIP                                     /* test: draw every sprite in every frame */
    { int s; for (s = 0; s < MAX_OBJ; ++s) if (keep[s]) { dl[n].s = &sl[s]; dl[n].old = sl[s].cur; ++n; todo[s] = 1; keep[s] = 0; } }
    if (!n) n = 0;
#endif
    if (n || nold_ov || nnew_ov) n = sprites_mark(sl, mark, keep, todo, dl, n, old_ov, nold_ov, new_ov, nnew_ov);
    PT(0, pt);
#ifdef PROFILE2
    prof_changed = n;
    if (prof_on) { prof_acc[2] += n; prof_acc[7] += n; }
#endif
    sprites_clear(dl, n);
    PT(1, pt);
    wait_blit();
    if (beam_req.rows) beam_now();                /* the beam is behind the sprites: drawn first (CPU) */
    sprites_blit(sl, todo);
    PT(3, pt);
}

/* ---- text and the beam: text is drawn after the sprites (the blitter: every character is a sprite, see glyph_list in tools/gen_assets.py),
 * the beam before them (the CPU) ---- */

/* the words that a text covers */
static void text_rect(int x, int n, int y, Rect *r) {
    int x0 = x + GUARD, x1 = x0 + 8 * n - 1;
    r->xw = x0 >> 4; r->wd = (x1 >> 4) - (x0 >> 4) + 1; r->y = y; r->h = 9;
}

static void text_now(const char *s, int x, int y, int colour) {
    int n, id0 = SPR_GLYPH + (colour == 2 ? 64 : colour == 28 ? 128 : 0) - 32;      /* the colours of the text: white (pen 1), red (2), cyan (28) */
    for (n = 0; s[n]; ++n) {
        Obj o = {id0 + s[n], x + 8 * n, y};
        Place p;
        if (s[n] <= 32 || s[n] >= 96) continue;
        place_fill(&o, &p, static_mode ? 0 : TOP);
        if (p.has) blit_place(&p);
    }
    if (!static_mode) { Rect r; text_rect(x, n, y, &r); add_dirty(r.xw, r.wd, y, 9); }
}

void video_text(const char *s, int x, int y, int colour) {
    TextReq *t;
    int n;
    if (static_mode) { text_now(s, x, y, colour); return; }
    x -= scroll_d;
    if (ntext >= MAX_TEXTS || nnew_ov >= MAX_RECTS) return;
    t = &text_req[ntext++];
    for (n = 0; s[n] && n < 23; ++n) t->s[n] = s[n];
    t->s[n] = 0;
    t->x = x; t->y = y; t->colour = colour;
    text_rect(x, n, y, &new_ov[nnew_ov++]);
}

static const u8 beam_colours[4] = {28, 30, 1, 30};           /* cyan, light blue, white, light blue */

/* the beam: rows of 8 pixel cells that get wider, with a checkerboard in the colours of beam_colours */
static void beam_rect(int r, Rect *out) {
    int cells = 2 * r + 5, xb = beam_req.x - cells * 4 + GUARD;
    out->xw = xb >> 4; out->wd = ((xb + cells * 8 - 1) >> 4) - (xb >> 4) + 1; out->y = beam_req.y + r * 8; out->h = 8;
}

void video_beam(int x, int y, int rows, int phase) {
    int r;
    beam_req.x = x; beam_req.y = y; beam_req.rows = rows; beam_req.phase = phase;
    for (r = 0; r < rows && nnew_ov < MAX_RECTS; ++r) beam_rect(r, &new_ov[nnew_ov++]);
}

static void beam_now(void) {
    int r, k, line, pl;
    for (r = 0; r < beam_req.rows; ++r) {
        int cells = 2 * r + 5, xb = beam_req.x - cells * 4 + GUARD, yy = beam_req.y + r * 8;
        Rect rc;
        if (yy < TOP || yy + 8 > SCREEN_H) continue;
        for (k = 0; k < cells; ++k) {
            int col = beam_colours[(k + r + beam_req.phase) & 3];
            u8 *p = (u8 *)bmp[back] + yy * ROWB + ((xb + k * 8) >> 3);
            for (line = 0; line < 8; ++line, p += ROWB)
                for (pl = 0; pl < NPL; ++pl)
                    if (col >> pl & 1) p[pl * STRIDE] |= (line + k) & 1 ? 0x55 : 0xaa;      /* a checkerboard */
        }
        beam_rect(r, &rc);
        add_dirty(rc.xw, rc.wd, rc.y, rc.h);
    }
}

static u8 has_title[NBMP];                                    /* the title picture is in this bitmap */

/* The title picture is copied once to each bitmap, and cleared when the game starts: it is not redrawn in every frame. */
void video_title(int on) {
    int half;
    if (on && !has_title[back]) {
        wait_blit();
        W(0x040) = 0x09f0;                                     /* BLTCON0: A, D; D = A */
        W(0x042) = 0;
        W(0x044) = 0xffff; W(0x046) = 0xffff;
        W(0x064) = 0;                                          /* BLTAMOD */
        W(0x066) = STRIDE - 40;                                /* BLTDMOD: the guard of the bitmap */
        for (half = 0; half < 2; ++half) {                       /* in two halves: a blit has at most 1024 lines (178 lines of 6 planes are more) */
            int rows = TITLE_H / 2;
            wait_blit();
            L(0x050) = (u32)title_ptr + half * rows * NPL * 40;
            L(0x054) = (u32)bmp[back] + GUARD / 8 + half * rows * ROWB;
            W(0x058) = ((rows * NPL) << 6) | 20;
        }
        has_title[back] = 1;
        hud_reset(back);                                       /* the title covers the hud: draw it again later */
    } else if (!on && has_title[back]) {
        Rect r = {0, STRIDE / 2, 0, TITLE_H};
        clear_rect(&r);
        has_title[back] = 0;
    }
}

void video_end(int title) {
    int i;
#ifdef PROFILE2
    u32 pe = now_lines();
#endif
    wait_blit();
    draw_sprites();
#ifdef PROFILE2
    { u32 pt = now_lines(); wait_blit(); build_stars(back); PT(5, pt); pe = pt; }
#else
    wait_blit();
    build_stars(back);
#endif
    build_hw(back);
    for (i = 0; i < ntext; ++i) text_now(text_req[i].s, text_req[i].x, text_req[i].y, text_req[i].colour);
    if (cop_title[back] != title) { copper_set_palette(back, title); cop_title[back] = title; }
    {
        int coarse = scroll_d >> unit_bits, fine = scroll_d & ((1 << unit_bits) - 1);             /* floor: a negative shift is a smaller pointer and a bigger delay */
        u16 *c = copper[back];
        for (i = 0; i < NPL; ++i) {
            u32 p = (u32)bmp[back] + GUARD / 8 - hidden_bytes + i * STRIDE, q = p - unit_bytes * coarse + TOP * ROWB;   /* (the pointers go on from the next line, TOP) */
            c[cop_bpl + 4 * i] = p >> 16; c[cop_bpl + 4 * i + 2] = p & 0xffff;
            c[cop_bpl2 + 4 * i] = q >> 16; c[cop_bpl2 + 4 * i + 2] = q & 0xffff;
        }
        c[cop_con1] = (fine & 15) * 0x11 | (fine >> 4 & 3) * 0x500;     /* (AGA: the bits 4 and 5 of the scroll: BPLCON1 bits 8, 9 and 10, 11) */
        for (i = 0; i < 2; ++i) {                  /* sprites 4 and 5: the stars of this bitmap */
            u32 p = (u32)star_list[back][i];
            c[cop_spr + 4 * (4 + i)] = p >> 16; c[cop_spr + 4 * (4 + i) + 2] = p & 0xffff;
        }
        for (i = 0; i < 4; ++i) {                  /* sprites 0 .. 3: the fighters; 6 and 7: the shots */
            u32 p = (u32)ship_list[back][i];
            c[cop_spr + 4 * i] = p >> 16; c[cop_spr + 4 * i + 2] = p & 0xffff;
        }
        for (i = 0; i < 2; ++i) {
            u32 p = (u32)shot_list[back][i];
            c[cop_spr + 4 * (6 + i)] = p >> 16; c[cop_spr + 4 * (6 + i) + 2] = p & 0xffff;
        }
    }
    while (((W(0x004) & 1) << 8 | W(0x006) >> 8) < 8) ;       /* COP1LC is read at the vertical blank: not now (the first lines) */
    L(0x080) = (u32)copper[back];                  /* the copper runs this list from the next frame on; the list of the shown bitmap is not touched */
    settle_display();                              /* (a vertical blank may have come while we drew) */
    published = vbl_count;
    pending = back;
    PT(8, pe);
}

