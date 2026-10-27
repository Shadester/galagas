; The NES side of the game: the start, the MMC1, the NMI and the picture. The game (game.s) runs its ticks in the main loop and then
; builds the next picture (draw_frame): the sprites into the OAM page, the background into the shadow name table (shadow, in WRAM). The NMI
; copies the OAM page and the jobs of queue_jobs (changed rows of the shadow, the palette, the attributes, tiles of the tractor beam) to the
; PPU, only when the main loop has said that a picture is ready (nmi_ready), so it never copies a half-built one. The main loop changes the
; shadow and the buffers only when nmi_ready is 0.

        .zeropage
nmi_cnt:        .res 1                  ; counts NMIs
nmi_ready:      .res 1                  ; 1: the OAM page and the row queue are ready for the next NMI
ppu_off:        .res 1                  ; 1: the main loop writes to the PPU itself (rendering is off): the NMI does not touch it
ppu_ctrl:       .res 1
ppu_mask:       .res 1
tick_credit:    .res 1                  ; + credit_step every NMI (it wraps); a game tick costs 6 (50 ticks a second on a 60 Hz NES)
credit_step:    .res 1                  ; 5 on an NTSC NES, 6 on a PAL NES (50 Hz)
pal_dirty:      .res 1                  ; 1: the palette (pal_buf) has changed
attr_dirty:     .res 1                  ; 1: the attributes (attr_buf) have changed
nq_pal:         .res 1                  ; the jobs of the next NMI (queue_jobs): copy the palette, the attributes,
nq_attr:        .res 1
tq_n:           .res 1                  ; tq_n tiles of the tractor beam from tile tq_first (both pattern tables),
tq_first:       .res 1
nq_n:           .res 1                  ; nq_n rows of the shadow
nq_row:         .res ROWS_NMI
tq_pos:         .res 1                  ; the tiles of the beam that are still to be copied: from tq_pos, tq_left of them
tq_left:        .res 1
nt_ptr:         .res 2                  ; scratch pointers of the main loop
nt_ptr2:        .res 2
tp:             .res 2                  ; the NMI's pointer

        .segment "OAM"
oam:            .res 256

        .segment "WBSS"
shadow:         .res 960                ; the name table as the next picture shows it (at the start of a page: nmi_rows)
row_dirty:      .res 30                 ; 1: the row has changed since the NMI copied it
pal_buf:        .res 32
attr_buf:       .res 64                 ; the attribute table
beam_buf:       .res 40 * 16            ; the tiles of the tractor beam (view.s): tiles T_BEAM..T_BEAM + 39

        .segment "SAVE"
save_mark:      .res 4                  ; "GALA": the battery RAM has a hi-score
save_hi:        .res 3
save_sum:       .res 1

        .code
; ---------------------------------------------------------------------------------------------
; The MMC1: five writes of one bit each
; ---------------------------------------------------------------------------------------------
.macro mmc1 reg
        sta reg
        lsr
        sta reg
        lsr
        sta reg
        lsr
        sta reg
        lsr
        sta reg
.endmacro

MMC1_CTRL = $8000
MMC1_CHR0 = $A000
MMC1_PRG  = $E000

; A = the bank at $8000 (bit 4 clear: the battery RAM stays on)
set_bank:
        mmc1 MMC1_PRG
        rts

reset:  sei
        cld
        ldx #$40
        stx APU_FRAME                   ; no APU frame interrupt
        ldx #$ff
        txs
        inx
        stx PPUCTRL
        stx PPUMASK
        stx $4010                       ; no DMC interrupt
        bit PPUSTATUS
@vb1:   bit PPUSTATUS                   ; the PPU needs two vertical blanks to wake up
        bpl @vb1
        txa
@clr:   sta $00,x                       ; clear the RAM (the OAM page: all sprites off)
        sta $0100,x
        sta $0300,x
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        lda #$ff
        sta $0200,x
        lda #0
        inx
        bne @clr
        lda #$80                        ; the MMC1: reset the shift register, then control: vertical mirroring, $C000 fixed, 8 KB CHR
        sta MMC1_CTRL
        lda #$0e
        mmc1 MMC1_CTRL
        lda #0
        mmc1 MMC1_CHR0
        lda #0
        jsr set_bank
        jsr copy_data                   ; the variables (their first values) into the battery RAM, the rest of it cleared
@vb2:   bit PPUSTATUS
        bpl @vb2
        lda #1                          ; the NMI on, but away from the PPU
        sta ppu_off
        lda #CTRL_BASE
        sta ppu_ctrl
        sta PPUCTRL
        jsr detect_region
        jmp main

; WBSS cleared, then the DATA segment (the variables, from the ROM) to the battery RAM (WBSS comes first: its last page may reach into DATA)
        .import __DATA_LOAD__, __DATA_RUN__, __DATA_SIZE__, __WBSS_RUN__, __WBSS_SIZE__
copy_data:
        lda #<__WBSS_RUN__
        sta nt_ptr
        lda #>__WBSS_RUN__
        sta nt_ptr+1
        ldx #>(__WBSS_SIZE__ + 255)
        lda #0
        tay
@z:     sta (nt_ptr),y
        iny
        bne @z
        inc nt_ptr+1
        dex
        bne @z
        lda #<__DATA_LOAD__
        sta nt_ptr
        lda #>__DATA_LOAD__
        sta nt_ptr+1
        lda #<__DATA_RUN__
        sta nt_ptr2
        lda #>__DATA_RUN__
        sta nt_ptr2+1
        ldx #>__DATA_SIZE__
        ldy #0
        cpx #0
        beq @rest
@p:     lda (nt_ptr),y
        sta (nt_ptr2),y
        iny
        bne @p
        inc nt_ptr+1
        inc nt_ptr2+1
        dex
        bne @p
@rest:  cpy #<__DATA_SIZE__
        beq @done
        lda (nt_ptr),y
        sta (nt_ptr2),y
        iny
        bne @rest
@done:  rts

; NTSC or PAL (and Dendy): count the loops of 11 cycles between two NMIs (the NMI is on, ppu_off is set). NTSC: 29780 cycles, about 2700
; loops (10 in the high byte); PAL: 33247 (11), Dendy: 35464 (12: also a 50 Hz machine). Credit: 5 a frame on NTSC, 6 on PAL and Dendy.
detect_region:
        lda nmi_cnt
@w0:    cmp nmi_cnt
        beq @w0
        lda nmi_cnt
        ldx #0
        ldy #0
@l:     inx
        bne @n
        iny
@n:     cmp nmi_cnt
        beq @l
        lda #5
        cpy #11
        bcc @ntsc
        lda #6
@ntsc:  sta credit_step
        rts

; ---------------------------------------------------------------------------------------------
; The NMI: the OAM page, the palette, the queued rows and tiles, then the scroll and the control registers
; ---------------------------------------------------------------------------------------------
nmi:    pha
        txa
        pha
        tya
        pha
        inc nmi_cnt
        lda tick_credit                 ; (the main loop counts what it has used: credit_used)
        clc
        adc credit_step
        sta tick_credit
        lda ppu_off
        bne @out
        lda nmi_ready
        beq @regs
        lda #0
        sta OAMADDR
        lda #>oam
        sta OAMDMA
        lda nq_pal
        beq @attr
        jsr nmi_palette
@attr:  lda nq_attr
        beq @tiles
        jsr nmi_attr
@tiles: lda tq_n
        beq @rows
        jsr nmi_tiles
@rows:  ldx nq_n
        beq @done
        jsr nmi_rows
@done:  lda #0
        sta nmi_ready
@regs:  bit PPUSTATUS
        lda #0
        sta PPUSCROLL
        sta PPUSCROLL
        lda ppu_ctrl
        sta PPUCTRL
        lda ppu_mask
        sta PPUMASK
@out:   pla
        tay
        pla
        tax
        pla
irq:    rti

nmi_palette:
        lda #$3f
        sta PPUADDR
        lda #0
        sta PPUADDR
        .repeat 32, k
        lda pal_buf + k
        sta PPUDATA
        .endrepeat
        rts

nmi_attr:
        lda #$23
        sta PPUADDR
        lda #$c0
        sta PPUADDR
        .repeat 64, k
        lda attr_buf + k
        sta PPUDATA
        .endrepeat
        rts

; tq_n tiles of the beam from tile tq_first: beam_buf + i * 16 to the tile T_BEAM + i of both pattern tables (the formation's wing frame
; chooses the table of the background)
nmi_tiles:
        ldx tq_first
@tile:  txa                             ; the source: beam_buf + i * 16
        lsr
        lsr
        lsr
        lsr
        sta tp+1
        txa
        asl
        asl
        asl
        asl
        clc
        adc #<beam_buf
        sta tp
        lda tp+1
        adc #>beam_buf
        sta tp+1
        txa                             ; the tile: (T_BEAM + i) * 16
        clc
        adc #T_BEAM
        pha
        lsr
        lsr
        lsr
        lsr
        sta PPUADDR
        pla
        asl
        asl
        asl
        asl
        sta PPUADDR
        ldy #0
        .repeat 16
        lda (tp),y
        sta PPUDATA
        iny
        .endrepeat
        txa
        clc
        adc #T_BEAM
        pha
        lsr
        lsr
        lsr
        lsr
        ora #$10
        sta PPUADDR
        pla
        asl
        asl
        asl
        asl
        sta PPUADDR
        ldy #0
        .repeat 16
        lda (tp),y
        sta PPUDATA
        iny
        .endrepeat
        inx
        dec tq_n
        beq @r
        jmp @tile
@r:     rts

; The rows of the queue: row r is the 32 bytes at shadow + r * 32 (a row never crosses a page: the shadow starts at a page) to
; $2000 + r * 32. An unrolled copy for each of the 4 pages of the shadow: 8 cycles a byte, about 290 a row.
nmi_rows:
        dex
nmi_row:
        lda nq_row,x
        lsr
        lsr
        lsr
        ora #$20
        sta PPUADDR
        lda nq_row,x
        asl
        asl
        asl
        asl
        asl
        sta PPUADDR
        tay                             ; (row & 7) * 32: the row in its page
        lda nq_row,x
        cmp #8
        bcs @p1
        jmp rows_p0
@p1:    cmp #16
        bcs @p2
        jmp rows_p1
@p2:    cmp #24
        bcs @p3
        jmp rows_p2
@p3:    jmp rows_p3
nmi_row_next:
        dex
        bpl nmi_row
        lda #0
        sta nq_n
        rts

.macro rows_page p
        .repeat 32, k
        lda shadow + p * 256 + k, y
        sta PPUDATA
        .endrepeat
        jmp nmi_row_next
.endmacro
rows_p0:
        rows_page 0
rows_p1:
        rows_page 1
rows_p2:
        rows_page 2
rows_p3:
        rows_page 3

; ---------------------------------------------------------------------------------------------
; The main loop's side
; ---------------------------------------------------------------------------------------------
; Wait until the NMI has taken the last picture (then the shadow and the OAM page are free)
wait_nmi:
@w:     lda nmi_ready
        bne @w
        rts

; The picture is ready: the NMI takes it
frame_ready:
        lda #1
        sta nmi_ready
        rts

; The jobs of the next NMI, in about the time of ROWS_NMI rows (a row: about 290 cycles; two tiles of the beam: 800; the attributes: 520;
; the palette: 270): the tiles of the beam first, then the attributes, the palette and the changed rows from the top
queue_jobs:
        lda #ROWS_NMI
        sta nt_ptr                      ; what is left
        lda #0
        sta tq_n
        sta nq_attr
        sta nq_pal
        lda tq_left
        beq @attr
        lda tq_pos
        sta tq_first
        ldx #2
        lda tq_left
        cmp #2
        bcs @t2
        tax
@t2:    stx tq_n
        txa
        clc
        adc tq_pos
        sta tq_pos
        lda tq_left
        sec
        sbc tq_n
        sta tq_left
        lda #1
        sta nt_ptr
@attr:  lda attr_dirty
        beq @pal
        lda nt_ptr
        cmp #2
        bcc @pal
        sbc #2
        sta nt_ptr
        lda #1
        sta nq_attr
        lda #0
        sta attr_dirty
@pal:   lda pal_dirty
        beq @rows
        lda nt_ptr
        beq @rows
        dec nt_ptr
        lda #1
        sta nq_pal
        lda #0
        sta pal_dirty
@rows:  ldx #0
        ldy #0
        lda nt_ptr
        beq @full
@r:     lda row_dirty,x
        beq @n
        lda #0
        sta row_dirty,x
        txa
        sta nq_row,y
        iny
        cpy nt_ptr
        beq @full
@n:     inx
        cpx #30
        bne @r
@full:  sty nq_n
        rts

; Rendering off (the NMI keeps away from the PPU); rendering on again at the next vertical blank
ppu_disable:
        jsr wait_nmi
        lda #1
        sta ppu_off
        lda nmi_cnt
@w:     cmp nmi_cnt
        beq @w
        lda #0
        sta PPUMASK
        rts

ppu_enable:
        lda #0
        sta nq_n
        sta tq_n
        sta tq_left
        sta nq_attr
        sta nq_pal
        sta attr_dirty
        lda #1                          ; the next NMI copies the palette
        sta pal_dirty
        lda #$1e                        ; background and sprites, also in the left 8 pixels
        sta ppu_mask
        lda #0
        sta ppu_off
        rts

; Copy 4 KB from the graphics bank (bank 1) to the PPU: nt_ptr = the source, X = the PPU address high byte. Rendering must be off.
chr_copy:
        lda #1
        jsr set_bank
        bit PPUSTATUS
        stx PPUADDR
        lda #0
        sta PPUADDR
        ldx #16
        ldy #0
@p:     lda (nt_ptr),y
        sta PPUDATA
        iny
        bne @p
        inc nt_ptr+1
        dex
        bne @p
        lda #0
        jmp set_bank

; Clear the shadow and the dirty marks
shadow_clear:
        lda #<shadow
        sta nt_ptr
        lda #>shadow
        sta nt_ptr+1
        ldx #4
        ldy #0
        tya
@z:     sta (nt_ptr),y
        iny
        bne @z
        inc nt_ptr+1
        dex
        bne @z
        ldx #29
@d:     sta row_dirty,x
        dex
        bpl @d
        rts

; The shadow (960 bytes) and the attributes at nt_ptr2 (64 bytes) to the name table; rendering must be off
nt_upload:
        bit PPUSTATUS
        lda #$20
        sta PPUADDR
        lda #0
        sta PPUADDR
        lda #<shadow
        sta nt_ptr
        lda #>shadow
        sta nt_ptr+1
        ldx #4
        ldy #0
@p:     lda (nt_ptr),y
        sta PPUDATA
        iny
        bne @p
        inc nt_ptr+1
        dex
        bne @p
        bit PPUSTATUS
        lda #$23
        sta PPUADDR
        lda #$c0
        sta PPUADDR
        ldy #0
@a:     lda (nt_ptr2),y
        sta PPUDATA
        iny
        cpy #64
        bne @a
        rts

; Palette A (0: the game, 1: the title) to pal_buf
pal_load:
        tax
        beq @g
        ldx #31
@t:     lda pal_title_data,x
        sta pal_buf,x
        dex
        bpl @t
        rts
@g:     ldx #31
@gl:    lda pal_game_data,x
        sta pal_buf,x
        dex
        bpl @gl
        rts

; The title screen: pattern table 1 with the logo, the title's name table (into the shadow too: the messages go there), its palette
screen_title:
        jsr ppu_disable
        lda #<chr_title
        sta nt_ptr
        lda #>chr_title
        sta nt_ptr+1
        ldx #$10
        jsr chr_copy
        lda #1                          ; the name table of the title: 960 bytes to the shadow, the attributes stay in the bank
        jsr set_bank
        lda #<title_nam
        sta nt_ptr
        lda #>title_nam
        sta nt_ptr+1
        lda #<shadow
        sta nt_ptr2
        lda #>shadow
        sta nt_ptr2+1
        ldx #4
        ldy #0
@c:     lda (nt_ptr),y
        sta (nt_ptr2),y
        iny
        bne @c
        inc nt_ptr+1
        inc nt_ptr2+1
        dex
        bne @c
        lda #<(title_nam + 960)
        sta nt_ptr2
        lda #>(title_nam + 960)
        sta nt_ptr2+1
        jsr nt_upload
        lda #0
        jsr set_bank
        ldx #29
        lda #0
@d:     sta row_dirty,x
        dex
        bpl @d
        jsr oam_hide
        lda #1
        jsr pal_load
        lda #CTRL_BASE | CTRL_BG1
        sta ppu_ctrl
        jmp ppu_enable

; The game screen: both pattern tables of the game, an empty name table with the attributes of the game, the game's palette
screen_game:
        jsr ppu_disable
        lda #<chr_game
        sta nt_ptr
        lda #>chr_game
        sta nt_ptr+1
        ldx #$00
        jsr chr_copy
        lda #<(chr_game + $1000)
        sta nt_ptr
        lda #>(chr_game + $1000)
        sta nt_ptr+1
        ldx #$10
        jsr chr_copy
        jsr shadow_clear
        ldx #63
@ab:    lda attr_game,x
        sta attr_buf,x
        dex
        bpl @ab
        lda #<attr_game
        sta nt_ptr2
        lda #>attr_game
        sta nt_ptr2+1
        jsr nt_upload
        jsr oam_hide
        lda #0
        sta form_valid                  ; nothing of the formation is in the name table
        jsr pal_load
        lda #CTRL_BASE
        sta ppu_ctrl
        jmp ppu_enable

oam_hide:
        ldx #0
        lda #$ff
@h:     sta oam,x
        inx
        bne @h
        rts

        .rodata
; the shadow's rows
shadow_lo:
        .repeat 30, r
        .byte <(shadow + r * 32)
        .endrepeat
shadow_hi:
        .repeat 30, r
        .byte >(shadow + r * 32)
        .endrepeat

        .assert <shadow = 0, error, "the shadow name table must start at a page (nmi_rows)"
