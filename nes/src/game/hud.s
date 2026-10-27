; Messages, HUD and starfield. A message is a string at a name table cell (column, row) in a small list; it is written into the shadow name
; table when it is added and blanked when it is cleared. The HUD is in the top rows of the name table (written when a number changes).

MAX_MSG = 8

        .segment "DATA"
msg_n:          .byte 0
msg_lo:         .res MAX_MSG
msg_hi:         .res MAX_MSG
msg_x:          .res MAX_MSG
msg_y:          .res MAX_MSG

; Number buffers for print_num / draw_bcd (print_num writes 3 characters, 'ratio' adds a '%')
num_a:          .byte 32, 32, 32, 0, 0
num_b:          .byte 32, 32, 32, 0, 0
num_c:          .byte 32, 32, 32, 0, 0
num_d:          .byte 32, 32, 0

hud_sig:        .byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff   ; what the HUD shows now: score, hi-score, lives, level (no BCD byte is $ff)
hud_on:         .byte 0                         ; 1: the game screen (the HUD is drawn)
hcol:           .byte 0
hcnt:           .byte 0

        .code
; Add the message at zp_src; zp_dst = column, zp_dst+1 = row; write it into the shadow
msg_add:
        ldx msg_n
        cpx #MAX_MSG
        bcs @full
        lda zp_src
        sta msg_lo,x
        lda zp_src+1
        sta msg_hi,x
        lda zp_dst
        sta msg_x,x
        lda zp_dst+1
        sta msg_y,x
        inc msg_n
        lda #0
        jmp msg_write
@full:  rts

; Write message X into the shadow (A = 0) or blank its cells (A = 1); keeps X
msg_write:
        sta hcnt
        stx tmpx
        lda msg_lo,x
        sta zp_src
        lda msg_hi,x
        sta zp_src+1
        ldy msg_y,x
        lda #1
        sta row_dirty,y
        lda shadow_lo,y
        clc
        adc msg_x,x
        sta nt_ptr
        lda shadow_hi,y
        adc #0
        sta nt_ptr+1
        ldy #0
@c:     lda (zp_src),y
        beq @end
        sec
        sbc #32
        ldx hcnt
        beq @put
        lda #0
@put:   sta (nt_ptr),y
        iny
        bne @c
@end:   ldx tmpx
        rts

msg_clear_all:
        lda #0
        ldx #29
        jmp msg_clear_y

; Remove the messages with ymin <= row <= ymax (A = ymin, X = ymax) and blank their cells
msg_clear_y:
        sta ov_t
        stx ov_by
        ldx #0                          ; read index
        ldy #0                          ; write index
@next:  cpx msg_n
        bcs @done
        lda msg_y,x
        cmp ov_t
        bcc @keep
        cmp ov_by
        beq @drop
        bcc @drop
@keep:  lda msg_lo,x
        sta msg_lo,y
        lda msg_hi,x
        sta msg_hi,y
        lda msg_x,x
        sta msg_x,y
        lda msg_y,x
        sta msg_y,y
        iny
        jmp @nx
@drop:  sty tmpy
        lda #1
        jsr msg_write
        ldy tmpy
@nx:    inx
        jmp @next
@done:  sty msg_n
        rts

clear_screen = msg_clear_all

; Blank the message rows: 16 (stage intro) and 20 (READY, FIGHTER CAPTURED)
clear_stage_row:
        lda #MSG_ROW(16)
        ldx #MSG_ROW(20)
        jmp msg_clear_y

clear_result:
        lda #MSG_ROW(9)
        ldx #MSG_ROW(13)
        jmp msg_clear_y

; Draw BCD byte A as two digits at zp_dst (a buffer), then advance zp_dst by 2
draw_bcd:
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #48
        ldy #0
        sta (zp_dst),y
        pla
        and #$0f
        clc
        adc #48
        iny
        sta (zp_dst),y
        lda zp_dst
        clc
        adc #2
        sta zp_dst
        bcc @done
        inc zp_dst+1
@done:  rts

; ---- The HUD: row 1 the labels, row 2 the score (left) and the hi-score (right), row 3 the spare ships (left) and the stage badges (right) ----
HUD_SCORE = 2 * 32 + 1                  ; cells of the shadow
HUD_HI    = 2 * 32 + 25
HUD_LIVES = 3 * 32 + 1
HUD_BADGE = 3 * 32 + 31                 ; the badges run to the left from here

; A = the tile, X = the cell (0..255): put it into the shadow
.macro hud_put
        sta shadow,x
.endmacro

; The screens: the title (no HUD), the game (the HUD's labels)
show_title:
        lda #0
        sta hud_on
        jmp screen_title

show_game:
        jsr screen_game

hud_labels:
        ldx #0
@l:     lda hud_txt,x
        beq @r
        sec
        sbc #32
        sta shadow + 32 + 1,x
        inx
        bne @l
@r:     ldx #0
@h:     lda hud_txt2,x
        beq @d
        sec
        sbc #32
        sta shadow + 32 + 21,x
        inx
        bne @h
@d:     lda #1
        sta row_dirty+1
        lda #$ff
        ldx #7
@s:     sta hud_sig,x
        dex
        bpl @s
        lda #1
        sta hud_on
        rts

draw_hud:
        lda hud_on
        bne @on
        rts
@on:    ldx #2
@s:     lda score,x
        cmp hud_sig,x
        bne @score
        dex
        bpl @s
        jmp @hi
@score: ldx #2
        ldy #HUD_SCORE
@sc:    lda score,x
        sta hud_sig,x
        jsr hud_two
        dex
        bpl @sc
        lda #1
        sta row_dirty+2
@hi:    ldx #2
@h:     lda hiscore,x
        cmp hud_sig+3,x
        bne @hinew
        dex
        bpl @h
        jmp @lives
@hinew: ldx #2
        ldy #HUD_HI
@hs:    lda hiscore,x
        sta hud_sig+3,x
        jsr hud_two
        dex
        bpl @hs
        lda #1
        sta row_dirty+2
@lives: lda lives
        cmp hud_sig+6
        beq @level
        sta hud_sig+6
        ldy lives                       ; the spare ships: lives - 1 (at most 8)
        beq @l0
        dey
@l0:    sty hcnt
        ldx #0
@lv:    lda #T_LIFE
        cpx hcnt
        bcc @lput
        lda #0
@lput:  sta shadow + HUD_LIVES,x
        inx
        cpx #8
        bne @lv
        lda #1
        sta row_dirty+3
@level: lda level                       ; the badges: a 10 for every ten, a 5, a 1 for the rest
        cmp hud_sig+7
        beq @done
        sta hud_sig+7
        ldx #HUD_BADGE
        lda #0
@clr:   sta shadow,x
        dex
        cpx #HUD_BADGE - 10
        bne @clr
        ldx #HUD_BADGE
        lda level
        lsr
        lsr
        lsr
        lsr
        sta hcnt
        lda #T_B10
        jsr @put
        lda level
        and #$0f
        cmp #5
        bcc @ones
        sbc #5
        pha
        lda #1
        sta hcnt
        lda #T_B5
        jsr @put
        pla
@ones:  sta hcnt
        lda #T_B1
        jsr @put
        lda #1
        sta row_dirty+3
@done:  rts
@put:   ldy hcnt                        ; hcnt badges of tile A, to the left from X (not past the column 22)
        beq @pd
@pl:    cpx #HUD_BADGE - 10
        beq @pd
        sta shadow,x
        dex
        dey
        bne @pl
@pd:    rts

; The two digits of BCD byte A at shadow + Y (Y advances by 2); keeps X
hud_two:
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #'0' - 32
        sta shadow,y
        pla
        and #$0f
        clc
        adc #'0' - 32
        sta shadow+1,y
        iny
        iny
        rts

        .rodata
hud_txt:        .asciiz "1UP"
hud_txt2:       .asciiz "HIGH SCORE"

; ---- Starfield: 12 stars scroll down at 1..3 pixels a frame (not on the title) ----
        .segment "DATA"
star_x:         .res NUM_STARS
star_y:         .res NUM_STARS
star_v:         .res NUM_STARS

        .code
init_stars:
        ldx #NUM_STARS - 1
@s:     jsr rand
        sta star_x,x
        jsr rand
        cmp #232
        bcc @yok
        sbc #232
@yok:   sta star_y,x
        jsr rand
        and #3
        bne @v
        lda #1
@v:     sta star_v,x
        dex
        bpl @s
        rts

; 8-bit Galois LFSR (the C64 game's), result in A
rand:   lda rnd
        asl
        bcc @done
        eor #$1d
@done:  sta rnd
        rts
