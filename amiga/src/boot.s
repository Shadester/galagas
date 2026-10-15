| Bootblock: the Kickstart loads these 1024 bytes and calls them with a6 = ExecBase, a1 = the trackdisk request.
| It reads the game (LOADSIZE bytes from byte 1024 of the disk, filled in by tools/make_adf.py) into chip RAM, turns the
| operating system off and starts the game at 0x1000 (src/hw.s, _start).
        .text
        .ascii  "DOS"
        .byte   0
        .long   0                       | checksum: tools/make_adf.py
        .long   880                     | root block
        bra.s   start
        .word   0
loadsize:
        .long   0                       | patched by tools/make_adf.py (offset 16)
agasize:
        .long   0                       | the AGA data after the game: its size, 0: none (offset 20)
agamem:
        .long   0                       | the chip RAM that an AGA machine gets: the AGA data and the bitmaps (offset 24)
agaptr:
        .long   0                       | what AllocMem gave (a register may not survive DoIO)
start:  move.l  a1,a2                   | the request
        move.l  loadsize(pc),d0
        move.l  #2,d1                   | MEMF_CHIP
        jsr     -198(a6)                | AllocMem
        move.l  d0,a3
        beq     fail
        move.l  a3,40(a2)               | IO_DATA
        move.l  loadsize(pc),36(a2)     | IO_LENGTH
        move.l  #1024,44(a2)            | IO_OFFSET
        move.w  #2,28(a2)               | CMD_READ
        move.l  a2,a1
        jsr     -456(a6)                | DoIO
        move.w  0xdff07c,d0             | DENISEID: AGA Lisa $F8
        cmp.b   #0xf8,d0
        bne.s   noaga
        move.l  agasize(pc),d0
        beq.s   noaga
        move.l  agamem(pc),d0
        move.l  #0x40002,d1             | MEMF_CHIP | MEMF_REVERSE: from the top of the chip RAM, far above the game (it is copied to 0x1000 and up)
        jsr     -198(a6)                | AllocMem
        tst.l   d0
        beq.s   noaga
        lea     agaptr(pc),a0
        move.l  d0,(a0)
        move.l  d0,40(a2)               | IO_DATA
        move.l  agasize(pc),36(a2)      | IO_LENGTH
        move.l  loadsize(pc),d0
        add.l   #1024,d0
        move.l  d0,44(a2)               | IO_OFFSET: after the game
        move.w  #2,28(a2)               | CMD_READ
        move.l  a2,a1
        jsr     -456(a6)                | DoIO
noaga:  move.l  #0,36(a2)               | TD_MOTOR with length 0: motor off
        move.w  #9,28(a2)
        move.l  a2,a1
        jsr     -456(a6)
        jsr     -150(a6)                | SuperState: the game needs the supervisor mode (it sets the sr)
        lea     0xdff000,a6
        move.w  #0x7fff,0x9a(a6)        | INTENA off
        move.w  #0x7fff,0x9c(a6)        | INTREQ clear
        move.w  #0x7fff,0x96(a6)        | DMACON off
        move.l  4.w,a0                  | ExecBase (a6 is the custom chips now)
        moveq   #0,d7
        move.w  0x128(a0),d7            | AttnFlags of exec: the processor (68020 bit 1, 68030 bit 2, 68040 bit 3, 68060 bit 7); d7 goes to the game (hw.s)
        move.l  loadsize(pc),d6
        move.l  agaptr(pc),d5           | the AGA memory (0: none), for the game (hw.s)
        lea     stub(pc),a0             | The copy loop runs from 0x800: the bootblock itself may be in the place of the game (0x1000 and up).
        lea     0x800,a1                | (The OS is off: nothing uses this memory any more.)
        moveq   #(stubend-stub)/2-1,d0
1:      move.w  (a0)+,(a1)+
        dbra    d0,1b
        move.l  a3,a0
        bsr.s   clearcache
        jmp     0x800
| a 68020 / 68030 does not see in its instruction cache that code was written (the Kickstart turned the cache on): clear it. The game switches it on in hw.s.
clearcache:
        move.w  d7,d0
        and.w   #0x0006,d0
        beq.s   2f
        moveq   #8,d0
        .word   0x4e7b,0x0002           | movec d0,cacr (bit 3: clear the cache)
2:      move.w  d7,d0
        and.w   #0x0088,d0              | 68040 / 68060: push the data cache, clear all caches
        beq.s   3f
        .word   0xf4f8                  | cpusha bc
        .word   0xf4d8                  | cinva bc
3:      rts
| copied to 0x800 (position independent): a0 = the game as read, d6 = its size
stub:   lea     0x1000,a1
        lsr.l   #2,d6
4:      move.l  (a0)+,(a1)+
        subq.l  #1,d6
        bne.s   4b
        move.w  d7,d0
        and.w   #0x0006,d0
        beq.s   5f
        moveq   #8,d0
        .word   0x4e7b,0x0002
5:      move.w  d7,d0
        and.w   #0x0088,d0
        beq.s   6f
        .word   0xf4f8
        .word   0xf4d8
6:      jmp     0x1000
stubend:
fail:   move.w  #0x0f00,0xdff180        | no memory: a red screen
        bra.s   fail
