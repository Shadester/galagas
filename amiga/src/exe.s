| The game as a program for a hard disk: a hunk file (tools/make_hunk.py) that holds the game and the AGA data. It does what the bootblock (boot.s) does, from the
| operating system: AGA data to the top of the chip RAM, the OS off, the game to 0x1000, go. There is no way back: reset the machine to leave the game.
| The image can be anywhere in memory (also over 0x1000 ..): the copy to 0x1000 runs from 0x800, and it copies backwards when the game is below its place.
        .text
        .equ    AGAEXTRA, 3*56*6*256        | the 3 bitmaps of 6 planes behind the AGA data (tools/make_adf.py)
start:  move.l  4.w,a6                  | ExecBase
        moveq   #0,d7
        move.w  0x128(a6),d7            | AttnFlags: the processor
        moveq   #0,d5
        move.w  0xdff07c,d0             | DENISEID: AGA Lisa $F8
        cmp.b   #0xf8,d0
        bne.s   noaga
        move.l  #(agaend-aga)+AGAEXTRA,d0
        move.l  #0x40002,d1             | MEMF_CHIP | MEMF_REVERSE: from the top of the chip RAM, far above the game
        jsr     -198(a6)                | AllocMem
        move.l  d0,d5
        beq.s   noaga
        move.l  d0,a1
        lea     start(pc),a0
        add.l   #aga-start,a0           | (pc relative reaches only 32 KB: the data is far)
        move.l  #(agaend-aga)/4,d0
1:      move.l  (a0)+,(a1)+
        subq.l  #1,d0
        bne.s   1b
noaga:  jsr     -120(a6)                | Disable
        jsr     -150(a6)                | SuperState: the game needs the supervisor mode
        move.w  d7,d0
        and.w   #0x0001,d0              | a 68010 or better: the vector table must be at 0 (the game writes the vectors there)
        beq.s   2f
        moveq   #0,d0
        .word   0x4e7b,0x0801           | movec d0,vbr
2:      lea     0xdff000,a6
        move.w  #0x7fff,0x9a(a6)        | INTENA off
        move.w  #0x7fff,0x9c(a6)        | INTREQ clear
        move.w  #0x7fff,0x96(a6)        | DMACON off
        lea     stub(pc),a0
        lea     0x800,a1
        moveq   #(stubend-stub)/2-1,d0
3:      move.w  (a0)+,(a1)+
        dbra    d0,3b
        lea     start(pc),a0
        add.l   #game-start,a0
        move.l  #gameend-game,d6
        bsr.s   clearcache
        jmp     0x800
| the caches do not see written code (as in boot.s): clear them
clearcache:
        move.w  d7,d0
        and.w   #0x0006,d0
        beq.s   4f
        moveq   #8,d0
        .word   0x4e7b,0x0002           | movec d0,cacr (bit 3: clear the cache)
4:      move.w  d7,d0
        and.w   #0x0088,d0
        beq.s   5f
        .word   0xf4f8                  | cpusha bc
        .word   0xf4d8                  | cinva bc
5:      rts
| copied to 0x800 (position independent): a0 = the game, d6 = its size
stub:   lea     0x1000,a1
        move.l  d6,d0
        lsr.l   #2,d0
        cmp.l   a1,a0
        bcc.s   7f                      | the game is above 0x1000: copy forward
        add.l   d6,a0
        add.l   d6,a1
6:      move.l  -(a0),-(a1)             | below: copy backwards
        subq.l  #1,d0
        bne.s   6b
        bra.s   9f
7:      move.l  (a0)+,(a1)+
        subq.l  #1,d0
        bne.s   7b
9:      move.w  d7,d0
        and.w   #0x0006,d0
        beq.s   10f
        moveq   #8,d0
        .word   0x4e7b,0x0002
10:     move.w  d7,d0
        and.w   #0x0088,d0
        beq.s   11f
        .word   0xf4f8
        .word   0xf4d8
11:     jmp     0x1000
stubend:
        .balign 4
game:   .incbin "build/game.bin"
        .balign 4
gameend:
aga:    .incbin "build/aga.bin"
agaend:
