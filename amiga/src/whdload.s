| WHDLoad Slave: loads the game (data/galaga.bin) to 0x1000 and starts it, like the bootblock (boot.s) does. The game is built with -DWHDLOAD -DNOCACHE (make whd):
| WHDLoad switches the cache on, and the quit key of the game goes to resload_Abort (hw.s). AGA: also data/galaga.aga to AGABASE, and d5 = its address (1 MB of memory).
| The file is wrapped in a hunk by tools/make_hunk.py.
        .text
base:   moveq   #-1,d0                  | ws_Security
        rts
        .ascii  "WHDLOADS"              | ws_ID
        .word   10                      | ws_Version
        .ifdef  AGA
        .word   0x22                    | ws_Flags: NoError, ReqAGA
        .long   0x100000                | ws_BaseMemSize: the game (0x1000 .. 0x68000), the stack (0x80000) and the AGA data (0x80000 ..)
        .else
        .word   0x02                    | NoError
        .long   0x80000
        .endif
        .long   0                       | ws_ExecInstall
        .word   start-base              | ws_GameLoader
        .word   dir-base                | ws_CurrentDir
        .word   0                       | ws_DontCache
        .byte   0                       | ws_keydebug
keyexit:.byte   0x59                    | ws_keyexit: F10 (WHDLoad puts its QuitKey here)
        .long   0                       | ws_ExpMem
        .word   name-base
        .word   copy-base
        .word   info-base
        .ifdef  AGA
name:   .asciz  "Galaga (AGA)"
        .else
name:   .asciz  "Galaga"
        .endif
copy:   .asciz  "2026 Erik Lindberg"
info:   .asciz  "A Galaga clone for the Amiga, F10 quits"
dir:    .asciz  "data"
binname:.asciz  "galaga.bin"
aganame:.asciz  "galaga.aga"
        .even
start:  move.l  a0,a2                   | resload
        move.l  a0,0x404.w              | for the quit key of the game
        move.b  keyexit(pc),0x400.w
        moveq   #1,d0                   | CACRF_EnableI: the game does not touch the cache (NOCACHE)
        moveq   #1,d1
        jsr     16(a2)                  | resload_SetCACR
        lea     binname(pc),a0
        lea     0x1000,a1
        jsr     8(a2)                   | resload_LoadFile
        moveq   #0,d5
        .ifdef  AGA
        lea     aganame(pc),a0
        lea     AGABASE,a1
        jsr     8(a2)
        move.l  #AGABASE,d5             | the AGA memory for the game (hw.s)
        .endif
        jsr     32(a2)                  | resload_FlushCache
        moveq   #0,d7                   | the processor flags: not used (NOCACHE)
        move.w  #0x7fff,0xdff09a        | INTENA, DMACON, INTREQ off, like the bootblock
        move.w  #0x7fff,0xdff096
        move.w  #0x7fff,0xdff09c
        jmp     0x1000
