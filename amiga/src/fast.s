| The hot loops of the picture, in assembly (the 68000 gets about half a million instructions a second here). Each routine has a C version
| beside it (-DNOASM) that does the same: the pictures must be identical (tests/compare.py). GNU as, called from C (gcc m68k ABI: the
| arguments are on the stack, d0 d1 a0 a1 are free, the other registers are saved).
        .text

        .set    STAR_N,12
        .set    STAR_H,212              | SCREEN_H - 16 - TOP (video.h): checked in video.c
        .set    NAL,40                  | game.h

| ---- the starfield: the list of one hardware sprite channel (video.c, stars_layer_c) ----
| void stars_layer(u16 *list, const Star *stars, int off, const u16 *t0, const u16 *t1)
| A star is 8 bytes: s16 base, u8 hsx, u8 hs1, u16 data a, u16 data b. The stars are sorted by base, so the ones that wrapped to the top of the
| screen (base + off >= STAR_H) are the last ones, and come first in the list. t0 / t1 give the two words of the list that depend on the line.
        .global stars_layer
stars_layer:
        movem.l d2-d6/a2-a4,-(sp)
        move.l  36(sp),a0               | list
        move.l  40(sp),a1               | stars
        move.l  44(sp),d2               | off
        move.l  48(sp),a2               | t0
        move.l  52(sp),a3               | t1
        move.w  #STAR_H,d3
        sub.w   d2,d3                   | a star has wrapped when base >= STAR_H - off
        moveq   #0,d4                   | d4: the number of stars that have not wrapped
        move.l  a1,a4
1:      cmp.w   (a4),d3
        bls.s   2f
        addq.w  #1,d4
        addq.l  #8,a4
        cmp.w   #STAR_N,d4
        bne.s   1b
2:      move.w  #STAR_N,d5
        sub.w   d4,d5                   | the wrapped ones: a4 points at the first of them
        beq.s   3f
        subq.w  #1,d5
        move.w  d2,d6
        sub.w   #STAR_H,d6
        bsr.s   star_run
3:      move.w  d4,d5                   | then the others, from the first star
        beq.s   4f
        subq.w  #1,d5
        move.l  a1,a4
        move.w  d2,d6
        bsr.s   star_run
4:      clr.l   (a0)                    | the end of the list
        movem.l (sp)+,d2-d6/a2-a4
        rts

| d5 + 1 stars from a4, line = base + d6, into a0
star_run:
1:      move.w  (a4)+,d0
        add.w   d6,d0
        add.w   d0,d0
        move.w  0(a2,d0.w),d1
        or.b    (a4)+,d1                | hsx
        move.w  d1,(a0)+
        move.w  0(a3,d0.w),d1
        or.b    (a4)+,d1                | hs1
        move.w  d1,(a0)+
        move.l  (a4)+,(a0)+             | the pixel: plane a, plane b
        dbra    d5,1b
        rts

| ---- the aliens of this frame: slots 0 .. NAL - 1 of want[] (main.c, alien_wants_c) ----
| void alien_wants(const Alien *al, Obj *want, int anim, int challenge, int scroll)
| Alien is 68 bytes: x 0, y 4, st 8, type 12, hp 16, timer 20, ent 48 (checked in main.c). Obj is 3 words: id, x, y.
        .global alien_wants
alien_wants:
        movem.l d2-d6,-(sp)
        move.l  24(sp),a0               | al
        move.l  28(sp),a1               | want
        move.l  32(sp),d3               | anim
        move.l  36(sp),d4               | challenge
        move.l  40(sp),d5               | scroll
        add.w   #24,d5                  | screen x = x - 24 - scroll
        moveq   #NAL-1,d6
1:      move.l  8(a0),d0                | st
        beq.s   9f                      | A_DEAD
        cmp.l   #6,d0                   | A_ENTER, still waiting (ent 0)
        bne.s   2f
        tst.l   48(a0)
        beq.s   9f
2:      cmp.l   #4,d0                   | A_EXPLODE
        beq.s   6f
        move.l  12(a0),d1               | type
        bne.s   3f
        cmp.l   #1,16(a0)               | a boss that was hit once (not in a challenging stage): the purple one
        bne.s   3f
        tst.l   d4
        bne.s   3f
        moveq   #6,d2                   | SPR_BOSSP_A
        bra.s   4f
3:      add.w   d1,d1
        moveq   #4,d2
        sub.w   d1,d2                   | SPR_BOSS_A 4, SPR_BFLY_A 2, SPR_BEE_A 0
4:      add.w   d3,d2                   | the wing frame
        moveq   #0,d1                   | (an explosion is 2 lines higher: it is 24 lines, an alien 21)
5:      move.w  d2,(a1)+
        move.w  2(a0),d0
        sub.w   d5,d0
        move.w  d0,(a1)+
        move.w  6(a0),d0
        sub.w   #22,d0                  | screen y = y - 50 + TOP (28)
        sub.w   d1,d0
        move.w  d0,(a1)+
        bra.s   8f
6:      move.l  20(a0),d2               | the explosion: frame (G_EXPL_TICKS - timer) / 4, 0 .. 4
        neg.l   d2
        add.l   #20,d2                  | G_EXPL_TICKS
        asr.l   #2,d2
        bge.s   7f
        moveq   #0,d2
7:      cmp.l   #4,d2
        ble.s   71f
        moveq   #4,d2
71:     add.w   #12,d2                  | SPR_EXPL1
        moveq   #2,d1
        bra.s   5b
9:      move.w  #-1,(a1)+               | nothing
        clr.l   (a1)+                   | (x and y 0: the same slot in the next frame is the same sprite)
8:      lea     68(a0),a0
        dbra    d6,1b
        movem.l (sp)+,d2-d6
        rts

| ---- the sprites of a bitmap (video.c: Place, Slot, Dirt, draw_sprites; the C versions are the same, -DNOASM) ----
        .set    MAX_OBJ,55              | NAL + 3 + 4 + EBN (video.c checks)
        .set    OBJ_PAD,56
        .set    TOP,28
        .set    SCREEN_H,256
        .set    GUARD,64
        .set    PLACE_SIZE,36
        .set    SLOT_SIZE,76            | Slot: two Places, then the pointer to the current one
        .set    S_CUR,72
        | Place: r (xw, wd, y, h: words), dst, bob, mask, bits (longs), con0, size, mod (words), has, r0, r1 (bytes), rows (word)
        .set    P_DST,8
        .set    P_BOB,12
        .set    P_MASK,16
        .set    P_BITS,20
        .set    P_CON0,24
        .set    P_SIZE,26
        .set    P_MOD,28
        .set    P_HAS,30
        .set    P_R0,31
        .set    P_R1,32
        .set    P_ROWS,34

        .macro  WAITBLIT                | a5 = 0xdff000; the first read is only to let the busy bit get set
        btst    #6,2(a5)
1:      btst    #6,2(a5)
        bne.s   1b
        .endm

| int sprites_scan(Slot *sl, Obj *dr, const Obj *want, u8 *keep, u8 *hasv, u8 *todo, Dirt *dl, u32 base, const SpriteInfo *spr, const u16 *words)
| keep = hasv, todo = 0. For every slot that is not the same as the bitmap shows: a new place (the other one of its Slot), its entry in dl (the slot, the
| old place or 0), keep 0, hasv and todo = it has a place. Returns the length of dl.
        .set    A_SL,48
        .set    A_DR,52
        .set    A_WANT,56
        .set    A_KEEP,60
        .set    A_HASV,64
        .set    A_TODO,68
        .set    A_DL,72
        .set    A_BASE,76
        .set    A_SPR,80
        .set    A_WORDS,84
        .global sprites_scan
sprites_scan:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  A_BASE(sp),scan_base
        move.l  A_SPR(sp),scan_spr
        move.l  A_WORDS(sp),scan_words
        move.l  A_HASV(sp),a0           | keep = hasv, todo = 0
        move.l  A_KEEP(sp),a1
        move.l  A_TODO(sp),a2
        moveq   #OBJ_PAD/4-1,d0
1:      move.l  (a0)+,(a1)+
        clr.l   (a2)+
        dbra    d0,1b
        move.l  A_SL(sp),a0
        move.l  A_DR(sp),a1
        move.l  A_WANT(sp),a2
        move.l  A_DL(sp),a3
        move.w  #MAX_OBJ-1,d5
sc_a:   cmpm.l  (a1)+,(a2)+             | the same id and x ...
        bne.s   sc_d1
        cmpm.w  (a1)+,(a2)+             | ... and y: the slot is as it was
        bne.s   sc_d2
sc_n:   lea     SLOT_SIZE(a0),a0
        dbra    d5,sc_a
        move.l  a3,d0
        sub.l   A_DL(sp),d0
        lsr.l   #3,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts
sc_d1:  subq.l  #4,a1
        subq.l  #4,a2
        bra.s   sc_d
sc_d2:  subq.l  #6,a1
        subq.l  #6,a2
sc_d:   move.l  S_CUR(a0),a5            | old = the current place, new = the other one
        move.l  a0,a6
        cmp.l   a5,a6
        bne.s   1f
        lea     PLACE_SIZE(a0),a6
1:      move.l  a6,S_CUR(a0)
        move.l  a0,(a3)+
        tst.b   P_HAS(a5)
        beq.s   2f
        move.l  a5,(a3)+
        bra.s   3f
2:      clr.l   (a3)+
3:      move.l  (a2)+,(a1)+             | the slot of the bitmap now shows this sprite
        move.w  (a2)+,(a1)+
        move.w  d5,-(sp)
        bsr     place_fill              | a6 = the place, from the Obj before a1
        move.w  (sp)+,d5
        move.w  #MAX_OBJ-1,d4
        sub.w   d5,d4                   | the number of the slot
        move.b  P_HAS(a6),d0
        move.l  A_KEEP(sp),a5
        clr.b   0(a5,d4.w)
        move.l  A_HASV(sp),a5
        move.b  d0,0(a5,d4.w)
        move.l  A_TODO(sp),a5
        move.b  d0,0(a5,d4.w)
        bra.s   sc_n

| a6 = the Place to fill from the Obj at -6(a1) (id, x, y): the same as place_fill in video.c, for the playfield (clipped at TOP). Uses d0-d6 and a5.
place_fill:
        move.w  -6(a1),d0               | id
        bmi     pf_none
        move.w  -4(a1),d1
        add.w   #GUARD,d1               | xb
        bmi     pf_none
        move.w  -2(a1),d2               | y
        move.l  scan_spr,a5
        ext.l   d0
        move.l  d0,d3
        add.l   d3,d3
        add.l   d0,d3
        add.l   d3,d3                   | id * 6
        add.l   d3,a5                   | SpriteInfo: w, h (bytes), bob, mask (words)
        moveq   #0,d3
        move.b  (a5),d3                 | w
        move.w  d1,d0
        lsr.w   #4,d0                   | xw
        move.w  d0,d4
        add.w   d3,d4
        cmp.w   #27,d4                  | xw + w > STRIDE / 2 - 1: outside the bitmap
        bgt     pf_none
        moveq   #0,d4
        move.b  1(a5),d4                | h
        moveq   #0,d5                   | skip
        cmp.w   #TOP,d2
        bge.s   1f
        move.w  #TOP,d5
        sub.w   d2,d5                   | skip = TOP - y
        move.w  #TOP,d2
        cmp.w   d4,d5
        bge     pf_none                 | the whole sprite is above TOP
1:      move.w  d4,d6
        sub.w   d5,d6                   | h - skip
        move.w  #SCREEN_H,d4
        sub.w   d2,d4                   | the lines left below y
        cmp.w   d4,d6
        ble.s   2f
        move.w  d4,d6
2:      tst.w   d6
        ble     pf_none                 | d6: the lines to draw
        move.w  d0,(a6)                 | r.xw
        addq.w  #1,d3                   | d3: the width in words, w + 1
        move.w  d3,2(a6)                | r.wd
        move.w  d2,4(a6)                | r.y
        move.w  d6,6(a6)                | r.h
        move.w  d3,d4
        lsl.w   #2,d4
        add.w   d3,d4                   | the words in a row of the picture: 5 planes ...
        cmp.w   #6,video_npl+2
        bne.s   7f
        add.w   d3,d4                   | ... or 6
7:
        tst.w   d5
        beq.s   3f
        mulu    d4,d5                   | d5: skip * words in a row
3:      moveq   #0,d4
        move.w  2(a5),d4                | bob
        add.l   d5,d4
        add.l   d4,d4
        add.l   scan_words,d4
        move.l  d4,P_BOB(a6)
        moveq   #0,d4
        move.w  4(a5),d4                | mask
        add.l   d5,d4
        add.l   d4,d4
        add.l   scan_words,d4
        move.l  d4,P_MASK(a6)
        moveq   #0,d4
        move.w  d2,d4
        lsl.w   #2,d4
        lea     row_off,a5
        move.l  0(a5,d4.w),d4           | y * the bytes of a line
        add.l   scan_base,d4
        moveq   #0,d5
        move.w  d0,d5
        add.l   d5,d5
        add.l   d5,d4                   | + 2 * xw
        move.l  d4,P_DST(a6)
        moveq   #1,d4
        lsl.l   d3,d4
        subq.l  #1,d4
        lsl.l   d0,d4                   | the word columns: ((1 << wd) - 1) << xw
        move.l  d4,P_BITS(a6)
        move.w  d1,d4
        and.w   #15,d4
        moveq   #12,d5
        lsl.w   d5,d4
        or.w    #0x0fca,d4
        move.w  d4,P_CON0(a6)           | A B C D, D = A B + /A C, the shift of B
        move.w  d6,d4
        lsl.w   #2,d4
        add.w   d6,d4
        cmp.w   #6,video_npl+2
        bne.s   8f
        add.w   d6,d4
8:      lsl.w   #6,d4
        or.w    d3,d4
        move.w  d4,P_SIZE(a6)           | the lines of the planes, the words
        move.w  d3,d4
        add.w   d4,d4
        neg.w   d4
        add.w   #56,d4
        move.w  d4,P_MOD(a6)            | STRIDE - 2 * wd
        move.w  d2,d4
        lsr.w   #4,d4                   | r0
        move.b  d4,P_R0(a6)
        move.w  d2,d5
        add.w   d6,d5
        subq.w  #1,d5
        lsr.w   #4,d5                   | r1
        move.b  d5,P_R1(a6)
        moveq   #2,d6
        lsl.w   d5,d6
        moveq   #1,d5
        lsl.w   d4,d5
        sub.w   d5,d6                   | rows: a bit for each of r0 .. r1
        move.w  d6,P_ROWS(a6)
        move.b  #1,P_HAS(a6)
        rts
pf_none:
        clr.b   P_HAS(a6)
        rts

| int sprites_mark(Slot *sl, u32 *mark, u8 *keep, u8 *todo, Dirt *dl, int n, const Rect *ov_old, int nold, const Rect *ov_new, int nnew)
| The cells that something changes are marked (a bit for each word column, a u32 for each 16 lines): the places in dl, the rects of the texts. A sprite
| that stays and touches a marked cell is drawn again (keep 0, todo 1, added to dl with its place to clear), and marks its cells too. d6, d7: the
| columns and the rows that are marked anywhere, a quick test for most sprites. Returns the new length of dl.
        .set    M_SL,48
        .set    M_MARK,52
        .set    M_KEEP,56
        .set    M_TODO,60
        .set    M_DL,64
        .set    M_N,68
        .set    M_OVO,72
        .set    M_NOLD,76
        .set    M_OVN,80
        .set    M_NNEW,84
        .global sprites_mark
sprites_mark:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  M_MARK(sp),a1
        moveq   #SCREEN_H/16-1,d0
        move.l  a1,a4
1:      clr.l   (a4)+
        dbra    d0,1b
        moveq   #0,d6
        moveq   #0,d7
        move.l  M_OVO(sp),a4            | the rects of the texts of the last use of this bitmap, then the new ones
        move.w  M_NOLD+2(sp),d3
        bsr     mark_rects
        move.l  M_OVN(sp),a4
        move.w  M_NNEW+2(sp),d3
        bsr     mark_rects
        move.l  M_DL(sp),a5             | the places that change
        move.w  M_N+2(sp),d3
        beq.s   mk_x
        subq.w  #1,d3
mk_a:   move.l  (a5)+,a2                | the slot
        move.l  (a5)+,d0
        beq.s   mk_b
        move.l  d0,a4
        bsr     mark_pl
mk_b:   move.l  S_CUR(a2),a4
        tst.b   P_HAS(a4)
        beq.s   mk_c
        bsr     mark_pl
mk_c:   dbra    d3,mk_a
mk_x:   move.l  M_DL(sp),a4             | (a5 is the end of dl: new entries go here)
        move.w  M_N+2(sp),d0
        lsl.w   #3,d0
        lea     0(a4,d0.w),a5
mk_again:
        moveq   #0,d4                   | a sprite that stays: is a marked cell under it?
        move.l  M_SL(sp),a0
        move.l  M_KEEP(sp),a3
        move.l  M_TODO(sp),a2
        move.w  #MAX_OBJ-1,d3
mk_d:   tst.b   (a3)+
        beq.s   mk_g
        move.l  S_CUR(a0),a4
        move.w  P_ROWS(a4),d0
        and.w   d7,d0
        beq.s   mk_g
        move.l  P_BITS(a4),d0
        move.l  d0,d5
        and.l   d6,d5
        beq.s   mk_g
        moveq   #0,d1
        moveq   #0,d2
        move.b  P_R0(a4),d1
        move.b  P_R1(a4),d2
        sub.w   d1,d2
        lsl.w   #2,d1
mk_e:   move.l  0(a1,d1.w),d5
        and.l   d0,d5
        bne.s   mk_f
        addq.w  #4,d1
        dbra    d2,mk_e
        bra.s   mk_g
mk_f:   clr.b   -1(a3)                  | it is drawn again
        move.w  #MAX_OBJ-1,d1
        sub.w   d3,d1
        move.b  #1,0(a2,d1.w)
        move.l  a0,(a5)+
        move.l  a4,(a5)+                | and its place is cleared first
        bsr     mark_pl
        moveq   #1,d4
mk_g:   lea     SLOT_SIZE(a0),a0
        dbra    d3,mk_d
        tst.w   d4
        bne     mk_again
        move.l  a5,d0
        sub.l   M_DL(sp),d0
        lsr.l   #3,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

| a4 = a Place, a1 = mark: its bits into the rows r0 .. r1; d6, d7 grow. Uses d0-d2, a4 and a6.
mark_pl:
        move.l  P_BITS(a4),d0
        or.l    d0,d6
        or.w    P_ROWS(a4),d7
        moveq   #0,d1
        moveq   #0,d2
        move.b  P_R0(a4),d1
        move.b  P_R1(a4),d2
        sub.w   d1,d2
        lsl.w   #2,d1
        lea     0(a1,d1.w),a6
1:      or.l    d0,(a6)+
        dbra    d2,1b
        rts

| a4 = Rects (xw, wd, y, h), d3 = how many, a1 = mark; d6, d7 grow
mark_rects:
        subq.w  #1,d3
        bmi.s   3f
1:      move.w  2(a4),d1                | bits = ((1 << wd) - 1) << xw
        moveq   #1,d0
        lsl.l   d1,d0
        subq.l  #1,d0
        move.w  (a4),d1
        lsl.l   d1,d0
        or.l    d0,d6
        move.w  4(a4),d1                | rows y >> 4 .. (y + h - 1) >> 4
        move.w  d1,d2
        add.w   6(a4),d2
        subq.w  #1,d2
        lsr.w   #4,d1
        lsr.w   #4,d2
        moveq   #2,d4
        lsl.w   d2,d4
        moveq   #1,d5
        lsl.w   d1,d5
        sub.w   d5,d4
        or.w    d4,d7
        sub.w   d1,d2
        lsl.w   #2,d1
        lea     0(a1,d1.w),a6
2:      or.l    d0,(a6)+
        dbra    d2,2b
        addq.l  #8,a4
        dbra    d3,1b
3:      rts

| void sprites_clear(const Dirt *dl, int n): the old places
        .global sprites_clear
sprites_clear:
        movem.l a2/a5,-(sp)
        move.l  12(sp),a0
        move.w  18(sp),d1
        beq.s   cl_x
        subq.w  #1,d1
        lea     0xdff000,a5
cl_a:   addq.l  #4,a0
        move.l  (a0)+,d0
        beq.s   cl_b
        move.l  d0,a2
        WAITBLIT
        move.w  #0x0100,0x40(a5)        | D only, all minterm bits 0: clear
        clr.w   0x42(a5)
        move.w  P_MOD(a2),0x66(a5)
        move.l  P_DST(a2),0x54(a5)
        move.w  P_SIZE(a2),0x58(a5)
cl_b:   dbra    d1,cl_a
cl_x:   movem.l (sp)+,a2/a5
        rts

| void sprites_blit(const Slot *sl, const u8 *todo): the slots to draw, in the order of the slots (the later ones are in front); the blitter registers
| A and B modulo and the masks of A stay (video_init)
        .global sprites_blit
sprites_blit:
        movem.l a2/a5,-(sp)
        move.l  12(sp),a0
        move.l  16(sp),a1
        lea     0xdff000,a5
        move.w  #MAX_OBJ-1,d1
bl_a:   tst.b   (a1)+
        beq.s   bl_b
        move.l  S_CUR(a0),a2
        WAITBLIT
        move.w  P_CON0(a2),d0
        move.w  d0,0x40(a5)
        and.w   #0xf000,d0
        move.w  d0,0x42(a5)             | the shift of B
        move.w  P_MOD(a2),d0
        move.w  d0,0x60(a5)             | BLTCMOD
        move.w  d0,0x66(a5)             | BLTDMOD
        move.l  P_MASK(a2),0x50(a5)     | A
        move.l  P_BOB(a2),0x4c(a5)      | B
        move.l  P_DST(a2),d0
        move.l  d0,0x48(a5)             | C
        move.l  d0,0x54(a5)             | D
        move.w  P_SIZE(a2),0x58(a5)     | starts the blitter
bl_b:   lea     SLOT_SIZE(a0),a0
        dbra    d1,bl_a
        movem.l (sp)+,a2/a5
        rts

        .bss
        .even
scan_base:  .long 0
scan_spr:   .long 0
scan_words: .long 0
