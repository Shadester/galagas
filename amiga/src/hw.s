| Start-up, vertical blank interrupt. The game is linked at 0x1000 (link.ld); the bootblock jumps here with the OS off.
        .section .text.start
        .global _start
_start: move.w  #0x2700,sr
        lea     0x7fff0,sp              | top of 512 KB chip RAM
        lea     _bss_start,a0           | clear the bss
        lea     _bss_end,a1
1:      cmp.l   a1,a0
        bcc.s   2f
        clr.l   (a0)+
        bra.s   1b
2:      move.l  d5,aga_block            | the memory of an AGA machine (bootblock): the AGA data, then the bitmaps; 0: none
        move.w  d7,hw_attn              | the processor (AttnFlags of exec, d7 from the bootblock): 68020 bit 1, 68030 bit 2, 68040 bit 3, 68060 bit 7
        move.w  0xdff07c,d0             | DENISEID: AGA Lisa $F8 (ECS Denise $FC, OCS: no ID)
        cmp.b   #0xf8,d0
        bne.s   3f
4:      move.b  #1,hw_aga
3:      .ifdef  NOCACHE
        bra.s   6f
        .endif
        move.w  hw_attn,d1              | the instruction cache of a 68020 / 68030 / 68040 / 68060 (the data cache stays off: it would hold the custom
        move.w  d1,d0                   | registers and the chip RAM that the blitter writes)
        and.w   #0x0006,d0
        beq.s   5f
        moveq   #9,d0                   | CACR: enable the instruction cache, clear it
        .word   0x4e7b,0x0002           | movec d0,cacr
5:      move.w  d1,d0
        and.w   #0x0088,d0
        beq.s   6f
        .word   0xf4f8                  | cpusha bc: write back the data cache before it goes off
        .word   0xf4d8                  | cinva bc
        move.l  #0x8000,d0              | CACR: instruction cache on (68040: ICE, 68060: EIC), data cache off
        .word   0x4e7b,0x0002           | movec d0,cacr
6:      lea     vbl(pc),a0              | level 3 autovector: the vertical blank
        move.l  a0,0x6c
        lea     idle(pc),a0             | the other vectors do nothing
        lea     0x64,a1
        move.l  a0,(a1)+                | level 1
        lea     kbd(pc),a2
        move.l  a2,(a1)+                | level 2: the keyboard (CIA-A serial port)
        addq.l  #4,a1
        move.l  a0,(a1)+                | level 4
        move.l  a0,(a1)+                | level 5
        move.l  a0,(a1)+                | level 6
        move.b  #0x7f,0xbfed01          | CIA-A: all interrupts off, then only the serial port (keyboard) on
        move.b  #0x88,0xbfed01
        move.w  #0xc028,0xdff09a        | INTENA: enable, vertical blank (level 3), ports (level 2)
        move.w  #0x2000,sr              | interrupts on
        jsr     main
3:      bra.s   3b

vbl:    move.w  #0x0020,0xdff09c        | INTREQ: clear the vertical blank request
        addq.l  #1,vbl_count
        rte
idle:   rte

| Keyboard: a key code arrives in the serial data register of CIA-A: bit 7 of the decoded code is 1 for a key release.
| The key must be acknowledged by a pulse (about 85 microseconds) on the handshake line (bit 6 of CRA).
kbd:    movem.l d0-d1/a0,-(sp)
        move.w  #0x0008,0xdff09c        | INTREQ: clear the ports request
        move.b  0xbfed01,d0             | CIA-A interrupt control: reading it clears it
        btst    #3,d0                   | the serial port?
        beq.s   9f
        move.b  0xbfec01,d0
        not.b   d0
        ror.b   #1,d0                   | the key code, 0..127, and bit 7 = release
        move.b  d0,d1
        and.w   #0x7f,d1
        lea     keys,a0                 | (a0 is free: it is saved below)
        tst.b   d0
        smi     d0
        not.b   d0                      | 0xff if the key is down
        and.b   #1,d0
        move.b  d0,0(a0,d1.w)
        or.b    #0x40,0xbfee01          | the handshake: output mode
        moveq   #60,d1
8:      dbra    d1,8b
        and.b   #0xbf,0xbfee01
9:      movem.l (sp)+,d0-d1/a0
        rte

        .bss
        .global vbl_count, keys, hw_attn, hw_aga, aga_block
vbl_count: .long 0
keys:   .space 128                      | 1 for a key that is down, by key code
hw_attn: .word 0                        | the processor flags (see _start)
hw_aga: .byte 0                         | 1: an AGA machine (A1200, A4000)
        .even
aga_block: .long 0
