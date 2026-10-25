/* Galaga for the Amiga: the main loop, input, and what the game state looks like on the screen.
 * The rules are psp/game.c (src/game.c). One tick of the game for each vertical blank: 50 a second, as on the C64. */
#include <stddef.h>
#include "game.h"
#include "video.h"
#include "audio.h"
#include "assets.h"

extern volatile u32 vbl_count;
extern volatile u8 keys[128];

#define REG(r) (*(volatile u16 *)(0xdff000 + (r)))


#ifdef SELFTEST
/* -DSELFTEST=n: instead of the game, run n ticks of the scripted game (src/selftest.h): a green screen if the hash is
 * SELFTEST_EXPECT (made by tests/selftest_native.c), a red one if not. */
#include "selftest.h"
static void run_selftest(void) {
    REG(0x180) = 0x0ff0;                              /* yellow: running */
    REG(0x096) = 0x8100;                              /* bitplane DMA on, no plane: the colour fills the screen */
    REG(0x100) = 0x0200;
    REG(0x180) = selftest_hash(SELFTEST) == SELFTEST_EXPECT ? 0x00f0 : 0x0f00;
    for (;;) ;
}
#endif

#ifndef PROF_FROM
#define PROF_FROM 0              /* PROFILE: the ticks before this one are not measured */
#endif
#ifndef TITLE_HOLD
#define TITLE_HOLD 150          /* AUTOPLAY: ticks until it presses fire on the title screen */
#endif

/* ---- input: the cursor keys or A / D, space / Z / X / Return or the fire button of a joystick in port 2; P pauses, Esc quits ---- */
enum { K_P = 0x19, K_A = 0x20, K_D = 0x22, K_Z = 0x31, K_X = 0x32, K_SPACE = 0x40, K_RETURN = 0x44, K_ESC = 0x45,
       K_RIGHT = 0x4e, K_LEFT = 0x4f, K_CTRL = 0x63 };

static void read_input(Input *in) {
    static int old_pause, old_quit;
    u16 j = REG(0x00c);                               /* JOY1DAT: port 2 */
    int pause = keys[K_P], quit = keys[K_ESC];
    in->left = keys[K_LEFT] || keys[K_A] || (j & 0x0200);
    in->right = keys[K_RIGHT] || keys[K_D] || (j & 0x0002);
    in->fire = keys[K_SPACE] || keys[K_Z] || keys[K_X] || keys[K_RETURN] || keys[K_CTRL] || !(*(volatile u8 *)0xbfe001 & 0x80);
    in->pause = pause && !old_pause;
    in->quit = quit && !old_quit;
    old_pause = pause; old_quit = quit;
}

/* ---- the screen ---- */
static int star_slow, star_fast;                  /* the starfield (hardware sprites, video.c): the offsets of its two layers */

enum { WHITE = 1, RED = 2, CYAN = 28 };          /* palette entries (tools/art.py) */

static char *put_num(char *p, int n, int digits) {
    int i;
    for (i = digits - 1; i >= 0; --i) { p[i] = '0' + n % 10; n /= 10; }
    return p + digits;
}
static int str_len(const char *s) { int n = 0; while (s[n]) ++n; return n; }
static void centre(const char *s, int y, int colour) { video_text(s, (SCREEN_W - 8 * str_len(s)) / 2, y, colour); }

/* sprite slots (video.c): the aliens are 0..NAL-1 */
enum { SLOT_SHIP = NAL, SLOT_DUAL, SLOT_CAPTIVE, SLOT_PBUL, SLOT_EBUL = SLOT_PBUL + 4 };

/* C64 position of a sprite box -> screen */
static int scroll;                                /* the formation's sway (formDx): the playfield is shown shifted by it (copper), so everything is drawn at x - scroll */
#define SX(x) ((x) - 24 - scroll)
#define SY(y) ((y) - 50 + TOP)

static void draw_hud(const Game *g) {
    char b[16];
    int i;
    if (video_hud(0, 0)) {                              /* each part stays in the bitmap until its number changes */
        video_text("SCORE", 8, 2, RED);
        video_text("HI-SCORE", 128, 2, RED);
        video_text("STAGE", 256, 2, RED);
        video_static_end();
    }
    if (video_hud(1, g->score)) { put_num(b, g->score, 6); b[6] = 0; video_text(b, 8, 12, WHITE); video_static_end(); }
    if (video_hud(2, g->hi)) { put_num(b, g->hi, 6); b[6] = 0; video_text(b, 136, 12, WHITE); video_static_end(); }
    if (video_hud(3, g->stage)) { put_num(b, g->stage, 2); b[2] = 0; video_text(b, 264, 12, WHITE); video_static_end(); }
    if (video_hud(4, g->lives)) {
        for (i = 0; i < g->lives && i < 8; ++i) video_static_bob(SPR_LIFE, 64 + (i & 3) * 14, 2 + (i >> 2) * 13);   /* two rows of four */
        video_static_end();
    }
}

static void draw_messages(const Game *g) {
    char *p;
    if (g->paused) { centre("PAUSED", 120, WHITE); return; }
    switch (g->state) {
    case S_INTRO:
        if (g->challenge) centre("CHALLENGING STAGE", 150, CYAN);
        else { char t[10] = "STAGE "; put_num(t + 6, g->stage, 2); t[8] = 0; centre(t, 150, WHITE); }
        break;
    case S_READY: centre("READY", 192, WHITE); break;
    case S_DYING: if (g->dyingQuiet) centre("FIGHTER CAPTURED", 192, RED); break;
    case S_RESULT:
        if (g->challenge) {
            char t[24] = "NUMBER OF HITS ";
            p = put_num(t + 15, g->chalHits, 2); *p = 0;
            centre(t, 96, WHITE);
            if (g->chalHits == NAL) { centre("PERFECT!", 120, CYAN); centre("BONUS 10000", 136, WHITE); }
        } else {
            char t[16];
            int sh = g->shots > 999 ? 999 : g->shots, hi = g->hits > 999 ? 999 : g->hits;
            int ratio = g->shots ? g->hits * 100 / g->shots : 0;
            if (ratio > 100) ratio = 100;
            p = t; *p++ = 'S'; *p++ = 'H'; *p++ = 'O'; *p++ = 'T'; *p++ = 'S'; *p++ = ' '; p = put_num(p, sh, 3); *p = 0;
            centre(t, 96, WHITE);
            p = t; *p++ = 'H'; *p++ = 'I'; *p++ = 'T'; *p++ = 'S'; *p++ = ' '; *p++ = ' '; p = put_num(p, hi, 3); *p = 0;
            centre(t, 112, WHITE);
            p = t; *p++ = 'R'; *p++ = 'A'; *p++ = 'T'; *p++ = 'I'; *p++ = 'O'; *p++ = ' '; p = put_num(p, ratio, 3); *p++ = '%'; *p = 0;
            centre(t, 128, CYAN);
        }
        break;
    case S_GAMEOVER:
        centre("GAME OVER", 102, WHITE);
        if (g->stateTimer == 0) centre("PRESS FIRE", 130, WHITE);
        break;
    }
}

#ifdef PROFILE
static int loops;                                 /* PROFILE (+ HALT): loops of the main loop; fewer loops for the same ticks = a slower picture */
static u32 vbl_start, vbl_halt;
static u32 lines_tick, lines_draw;                /* PROFILE: the beam lines (64 us) that the ticks and the picture needed in total */
extern volatile u32 vbl_count;
u32 now_lines(void) { u32 v; do { v = vbl_count; } while (v != vbl_count); return v * 313 + ((REG(0x004) & 1) << 8 | REG(0x006) >> 8); }                   /* the VBLs the game needed for HALT ticks: HALT = 50 a second */
#endif

#ifdef PROFILE2
extern u32 prof_acc[12]; extern int prof_on;
u32 prof_hist[8];                                 /* loops that took n vertical blanks */
u32 prof_changed; static u32 prof_ch[6];                                 /* video.c: sprites that changed in the last picture */
static u32 cls_n[2], cls_t[2], cls_d[2], cls_c[2], prev_t, prev_d, prev_c;   /* the loops that took one vertical blank, and the ones that took more: their costs */
#endif
/* The aliens of this frame in slots 0 .. NAL - 1 (fast.s has the same in assembly). A slot that shows nothing gets id -1. */
_Static_assert(sizeof(Alien) == 68 && offsetof(Alien, x) == 0 && offsetof(Alien, y) == 4 && offsetof(Alien, st) == 8 && offsetof(Alien, type) == 12 &&
               offsetof(Alien, hp) == 16 && offsetof(Alien, timer) == 20 && offsetof(Alien, ent) == 48 && NAL == 40 && TOP == 28 &&
               SPR_BEE_A == 0 && SPR_BFLY_A == 2 && SPR_BOSS_A == 4 && SPR_BOSSP_A == 6 && SPR_EXPL1 == 12 && A_DEAD == 0 && A_EXPLODE == 4 &&
               A_ENTER == 6 && T_BOSS == 0 && T_BUTTERFLY == 1 && T_BEE == 2, "fast.s: alien_wants");
#ifdef NOASM
static void alien_wants(const Alien *al, Obj *w, int anim, int challenge, int sc) {
    int i;
    for (i = 0; i < NAL; ++i) {
        const Alien *a = &al[i];
        int id;
        if (a->st == A_DEAD || (a->st == A_ENTER && a->ent == 0)) { w[i].id = -1; w[i].x = w[i].y = 0; continue; }
        if (a->st == A_EXPLODE) { int f = (G_EXPL_TICKS - a->timer) >> 2; id = SPR_EXPL1 + (f < 0 ? 0 : f > 4 ? 4 : f); }
        else if (a->type == T_BOSS && a->hp == 1 && !challenge) id = SPR_BOSSP_A + anim;
        else id = (a->type == T_BOSS ? SPR_BOSS_A : a->type == T_BUTTERFLY ? SPR_BFLY_A : SPR_BEE_A) + anim;
        w[i].id = id; w[i].x = a->x - 24 - sc; w[i].y = a->y - 50 + TOP - (a->st == A_EXPLODE ? 2 : 0);
    }
}
#else
void alien_wants(const Alien *al, Obj *w, int anim, int challenge, int sc);
#endif

static void draw(const Game *g) {
    int i, anim = (g->frame >> 4) & 1;
#ifdef PROFILE2
    u32 pstart = now_lines();
    prof_on = g->frame + 3 < HALT && g->frame + 3 >= PROF_FROM;
#endif
    video_begin();
#ifdef PROFILE2
    if (prof_on) prof_acc[9] += now_lines() - pstart;
#endif
    if (g->state == S_TITLE || g->state == S_GAMEOVER) for (i = 0; i < NAL; ++i) { want[i].id = -1; want[i].x = want[i].y = 0; }
    scroll = g->state == S_TITLE || !video_can_scroll() ? 0 : g->formDx;
#ifdef NOSCROLL                                         /* test: no copper scroll: the formation is drawn where it is */
    scroll = 0;
#endif
#ifdef SCROLLTEST                                       /* test: scroll further, the pictures must be the same (everything is drawn at x - scroll) */
    if (g->state != S_TITLE) scroll += SCROLLTEST;
#endif
    video_scroll(scroll);
    video_title(g->state == S_TITLE);
    if (g->state == S_TITLE) {
        char b[20] = "HI-SCORE ";
        put_num(b + 9, g->hi, 6); b[15] = 0;
        centre(b, 190, RED);
        centre("PRESS FIRE", 206, WHITE);
        centre("ARROWS AND SPACE", 232, WHITE);
        video_stars(-1, -1);
        video_end(1);
        return;
    }
    video_stars(star_slow, star_fast);
    draw_hud(g);
    if (g->state != S_GAMEOVER) {
        if ((g->cap == C_BEAM || g->cap == C_PULL) && g->beamLen) {      /* behind the boss, as the text characters are on the C64 */
            const Alien *b = &g->al[g->capBoss];
            video_beam(SX(b->x + 12), TOP + 1 + ((b->y - 36) >> 3) * 8, g->beamLen, (g->frame >> 2) & 3);
        }
#ifdef PROFILE2
        u32 pa = now_lines();
#endif
        alien_wants(g->al, want, anim, g->challenge, scroll);
#ifdef PROFILE2
        if (prof_on) prof_acc[10] += now_lines() - pa;
#endif
        if (g->state == S_DYING) {
            if (!g->dyingQuiet) { int f = (G_DIE_TICKS - g->stateTimer) >> 3; if (f < 6) video_bob(SLOT_SHIP, SPR_PEXP1 + f, SX(g->px - 1), SY(g->py - 5)); }
        } else if (g->state != S_READY && !(g->invuln & 4)) {
            video_ship(0, g->px + 3 - 24, SY(g->py - 2));                  /* hardware sprites: the playfield scroll does not move them */
            if (g->dual) video_ship(1, g->px + 19 - 24, SY(g->py - 2));
        }
        if (g->cap == C_CARRY) {
            const Alien *b = &g->al[g->capBoss];
            if (b->st != A_DEAD && b->y >= 32) video_bob(SLOT_CAPTIVE, SPR_CAPTIVE, SX(b->x + 3), SY(b->y - 18));
        } else if (g->cap == C_RESCUE) {
            video_bob(SLOT_CAPTIVE, SPR_CAPTIVE, SX(g->rx + 3), SY(g->ry - 2));
        }
        {
            s16 sx[4], sy[4], si[4];
            u8 hw[4];
            int n = 0;
            for (i = 0; i < 4; ++i) if (g->ps[i].act) { sx[n] = g->ps[i].x + 7 - 24; sy[n] = SY(g->ps[i].y + 1); si[n++] = i; }
            video_shots(sx, sy, n, hw);
            for (i = 0; i < n; ++i) if (!hw[i]) video_bob(SLOT_PBUL + si[i], SPR_PBUL, sx[i] - scroll, sy[i]);
        }
        for (i = 0; i < EBN; ++i) if (g->eb[i].act) video_bob(SLOT_EBUL + i, (g->frame >> 2) & 1 ? SPR_EBUL2 : SPR_EBUL, SX(g->eb[i].x + 9), SY(g->eb[i].y - 3));
    }
    draw_messages(g);
#ifdef SHOWBOMBS                                        /* test: the two frames of the bomb, in the corner (the two last bomb slots) */
    video_bob(SLOT_EBUL + EBN - 1, SPR_EBUL, 100, 100);
    video_bob(SLOT_EBUL + EBN - 2, SPR_EBUL2, 116, 100);
#endif
#ifdef SHOWHW                                       /* test: say what the game runs on */
    video_text(video_is_aga() ? "AGA" : "OCS", 280, 244, WHITE);
#endif
#ifdef PROFILE2
    if (prof_on) prof_acc[6] += now_lines() - pstart;
#endif
#if defined(PROFILE2) && defined(HALT)
    if (g->frame + 3 >= HALT && loops) { char b[40]; char *p = b; int k; for (k = 0; k < 4; ++k) { p = put_num(p, (int)(prof_acc[k] / loops) % 10000, 4); *p++ = ' '; } *p = 0; video_text(b, 60, 229, WHITE);
        p = b; for (k = 4; k < 8; ++k) { p = put_num(p, (int)(prof_acc[k] / loops) % 10000, 4); *p++ = ' '; } *p = 0; video_text(b, 60, 238, WHITE);
        p = b; for (k = 1; k < 5; ++k) { p = put_num(p, (int)prof_hist[k] % 10000, 4); *p++ = ' '; } *p = 0; video_text(b, 60, 220, WHITE);
        p = b; for (k = 0; k < 6; ++k) { p = put_num(p, (int)prof_ch[k] % 1000, 3); *p++ = ' '; } *p = 0; video_text(b, 60, 184, WHITE);
        for (k = 0; k < 2; ++k) { u32 q = cls_n[k] ? cls_n[k] : 1; p = b; p = put_num(p, (int)cls_n[k] % 10000, 4); *p++ = ' '; p = put_num(p, (int)(cls_t[k] / q) % 10000, 4); *p++ = ' '; p = put_num(p, (int)(cls_d[k] / q) % 10000, 4); *p++ = ' '; p = put_num(p, (int)(cls_c[k] * 10 / q) % 10000, 4); *p = 0; video_text(b, 60, 202 + 9 * k, WHITE); } }
#endif
#if defined(PROFILE) && defined(HALT)
    if (g->frame + 3 >= HALT) { char b[40] = "LOOPS "; char *p = put_num(b + 6, loops, 4); *p++ = ' '; *p++ = 'T'; p = put_num(p, (lines_tick >> 4) % 10000, 4); *p++ = ' '; *p++ = 'D'; p = put_num(p, (lines_draw >> 4) % 10000, 4); *p = 0; video_text(b, 60, 247, WHITE); }
#endif
    video_end(0);
}

int main(void) {
    static Game g;
    Input in;
    u32 last;
    int t = 0;
    (void)t;
#ifdef SELFTEST
    run_selftest();
#endif
    video_init();
    audio_init();
    game_init(&g, 0);
    last = vbl_count;
#ifdef PROFILE
    vbl_start = last;
#endif
    for (;;) {
        u32 now;
        int n;
        while ((now = vbl_count) == last) ;
        n = now - last > 6 ? 6 : now - last;              /* a slow frame: the game catches up, 6 ticks at most */
#if defined(PROFILE2) && defined(HALT)
        if (t < HALT && t >= PROF_FROM) { ++prof_hist[n]; if (loops > 1) { int c = n > 1; ++cls_n[c]; cls_t[c] += prev_t; cls_d[c] += prev_d; cls_c[c] += prev_c; } }
#endif
#ifdef PROFILE
#ifdef HALT
        if (t < HALT && t >= PROF_FROM) ++loops;     /* only until the game stops */
#else
        ++loops;
#endif
#endif
        last = now;
#ifdef PROFILE
        u32 t0 = now_lines(), t1, t2;
#endif
        read_input(&in);
        while (n--) {
#ifdef HALT
            if (t >= HALT) break;
#endif
#ifdef AUTOPLAY
            if (g.state != S_TITLE || t >= TITLE_HOLD) game_autoplay(&g, &in);    /* for every tick, so the game is the same at any frame rate */
#endif
            game_tick(&g, &in);
            ++t;
            if (g.paused || g.state == S_TITLE) audio_mute();
            else { audio_play(g.snd); audio_tick(); }
            g.snd = 0;
            if (g.state != S_TITLE && !g.paused) {
                if (++star_slow >= STAR_ROWS) star_slow = 0;
                if ((star_fast += 2) >= STAR_ROWS) star_fast -= STAR_ROWS;
            }
        }
#if defined(PROFILE) && defined(HALT)
        if (t >= HALT && !vbl_halt) vbl_halt = vbl_count - vbl_start;
#endif
#ifdef PROFILE
        t1 = now_lines();
#endif
        draw(&g);
#ifdef PROFILE
        t2 = now_lines();
#ifdef HALT
        if (t < HALT && t >= PROF_FROM)
#endif
        { lines_tick += t1 - t0; lines_draw += t2 - t1; }
#ifdef PROFILE2
        prev_t = t1 - t0; prev_d = t2 - t1; prev_c = prof_changed;
        if (t < HALT && t >= PROF_FROM) ++prof_ch[prof_changed == 0 ? 0 : prof_changed < 3 ? 1 : prof_changed < 6 ? 2 : prof_changed < 11 ? 3 : prof_changed < 21 ? 4 : 5];
#endif
#endif
    }
}
