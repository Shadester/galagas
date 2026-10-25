; The game's own character set (RAM at RAM_CHARSET): a copy of the ROM set, with 7 characters for the tractor beam.
; The beam is a cone of thin rings: a ring is a horizontal line of a text cell, every second line. The cells of a row of the beam:
;   the middle one FULL, the two next to the edge of the cone have the upper rings cut short (NEXT_L / NEXT_R, in the first row
;   LOWNEXT: the rings sit one line lower there, so the first rings bow down at the ends), the outer ones EDGE_L / EDGE_R have the lower rings only.
;   The ends of a ring curl up by one pixel.

BEAM_CHR        = $f8           ; FULL, NEXT_L, NEXT_R, EDGE_L, EDGE_R, LOWNEXT_L, LOWNEXT_R

!zone init_charset
init_charset:
    sei
    lda $01
    pha
    and #$fb                    ; CHAREN off: the character ROM is at $d000 for the CPU
    sta $01
    ldx #0
.copy:
    lda $d000,x
    sta RAM_CHARSET,x
    lda $d100,x
    sta RAM_CHARSET+$100,x
    lda $d200,x
    sta RAM_CHARSET+$200,x
    lda $d300,x
    sta RAM_CHARSET+$300,x
    lda $d400,x
    sta RAM_CHARSET+$400,x
    lda $d500,x
    sta RAM_CHARSET+$500,x
    lda $d600,x
    sta RAM_CHARSET+$600,x
    lda $d700,x
    sta RAM_CHARSET+$700,x
    inx
    bne .copy
    pla
    sta $01                     ; I/O is back
    ldx #7*8-1
.patch:
    lda beam_chars,x
    sta RAM_CHARSET+BEAM_CHR*8,x
    dex
    bpl .patch
    lda #$1a                    ; screen at $0400, characters at RAM_CHARSET
    sta VIC_MEMORY
    cli
    rts

beam_chars:
    !byte $ff, $00, $ff, $00, $ff, $00, $ff, $00        ; FULL
    !byte $ff, $80, $ff, $00, $ff, $00, $ff, $00        ; NEXT_L
    !byte $ff, $01, $ff, $00, $ff, $00, $ff, $00        ; NEXT_R
    !byte $00, $00, $00, $80, $ff, $80, $ff, $00        ; EDGE_L
    !byte $00, $00, $00, $01, $ff, $01, $ff, $00        ; EDGE_R
    !byte $80, $ff, $80, $ff, $00, $ff, $00, $ff        ; LOWNEXT_L
    !byte $01, $ff, $01, $ff, $00, $ff, $00, $ff        ; LOWNEXT_R

; The character of cell Y of the row bd_r of the beam: A. The boss is in the column bd_col, the row starts at bd_c0, its half width is bd_hw.
!zone beam_chr
beam_chr:
    tya
    clc
    adc bd_c0
    sec
    sbc bd_col                  ; the distance to the middle: negative = left
    bcs .right
    eor #$ff
    clc
    adc #1
    ldx #0
    beq .have
.right:
    ldx #1
.have:
    cmp #0
    beq .full
    cmp bd_hw
    beq .edge
    clc
    adc #1
    cmp bd_hw
    bne .full
    lda bd_r                    ; the cell before the edge
    beq .lownext
    lda #BEAM_CHR+1
    bne .side
.lownext:
    lda #BEAM_CHR+5
    bne .side
.edge:
    lda #BEAM_CHR+3
.side:
    sta temp
    txa
    clc
    adc temp
    rts
.full:
    lda #BEAM_CHR
    rts
