; Draw every visible virtual sprite. C64 sprite coordinates (x 24.., y 50.., 9-bit x) become Lynx screen
; pixels: (x - 24) / 2, (y - 50) / 2, as signed 16-bit numbers (aliens enter above and beside the screen).
.ifdef PORTRAIT
; Portrait: the box of a sprite at game (x, y) has its base point at the screen (122 - y / 2, x / 2): the upright picture has the HUD strip (30 rows) on
; top and the field below it; the picture is turned (screen X = 159 - upright y, screen Y = upright x). The sprites have the turned offsets.
draw_sprites:
        ldx #0
@loop:  lda spr_y,x
        cmp #$ff
        beq @next
        lsr
        sta dr_x
        lda #122
        sec
        sbc dr_x
        sta dr_x
        lda #0
        sbc #0
        sta dr_x+1
        lda spr_x,x
        sta dr_y
        lda spr_x_msb,x
        sta dr_y+1
        cmp #$80                        ; arithmetic shift right
        ror dr_y+1
        ror dr_y
        lda spr_f,x
        phx
        jsr add_sprite_id
        plx
@next:  inx
        cpx #MAX_SPRITES
        bne @loop
        rts
.else
draw_sprites:
        ldx #0
@loop:  lda spr_y,x
        cmp #$ff
        beq @next
        sec
        sbc #50
        sta dr_y
        lda #0
        sbc #0
        sta dr_y+1
        cmp #$80                        ; arithmetic shift right
        ror dr_y+1
        ror dr_y
        lda spr_x,x
        sec
        sbc #SCREEN_LEFT
        sta dr_x
        lda spr_x_msb,x
        sbc #0
        sta dr_x+1
        cmp #$80
        ror dr_x+1
        ror dr_x
        lda spr_f,x
        phx
        jsr add_sprite_id
        plx
@next:  inx
        cpx #MAX_SPRITES
        bne @loop
        rts
.endif

; The tractor beam: beam_len rows of checkerboard cells under boss cap_boss while it is on (cap_state 2 or 3).
; The C64 writes characters (one cell of 8 pixels is the finest place for the beam there); here it is drawn every frame at the pixel.
.ifdef PORTRAIT
; Portrait: row r of cells (4 x 4 pixels) is turned: 4 wide in the screen x (118 - y / 2 - 4 r), (2 hw + 1) * 4 high in the screen y (x / 2 + 2 - 4 hw).
draw_beam:
        lda cap_state
        cmp #2
        beq @on
        cmp #3
        bne @rts
@on:    lda beam_len
        beq @rts
        lda frame                   ; Colour phase, every 4 frames
        lsr
        lsr
        and #3
        sta bd_n
        stz bd_r
@row:   ldx bd_r
        cpx beam_len
        bcs @rts
        ldy cap_boss
        lda enemy_y,y               ; screen x = 118 - y / 2 - 4 r (16 bit)
        lsr
        sta dr_x
        txa
        asl
        asl
        clc
        adc dr_x
        sta dr_x
        lda #118
        sec
        sbc dr_x
        sta dr_x
        lda #0
        sbc #0
        sta dr_x+1
        lda enemy_x,y               ; screen y = x / 2 + 2 - 4 hw
        lsr
        clc
        adc #2
        sta dr_y
        lda hw_tbl,x
        asl
        asl
        sta bd_col
        lda dr_y
        sec
        sbc bd_col
        sta dr_y
        stz dr_y+1
        txa                         ; sprite = SP_BEAM + row * 4 + phase
        asl
        asl
        clc
        adc bd_n
        clc
        adc #SP_BEAM
        jsr add_sprite_id
        inc bd_r
        bra @row
@rts:   rts
.else
draw_beam:
        lda cap_state
        cmp #2
        beq @on
        cmp #3
        bne @rts
@on:    lda beam_len
        beq @rts
        ldx cap_boss
        lda enemy_x_msb,x           ; The beam is centred under the boss: its centre is the screen pixel x / 2 - 6 (the picture of the boss is 12 wide)
        lsr
        lda enemy_x,x
        ror
        sta bd_col                  ; x / 2
        lda enemy_y,x               ; First row: just under the boss
        sec
        sbc #36
        lsr
        lsr
        lsr
        sta bd_row0
        lda frame                   ; Colour phase, every 4 frames
        lsr
        lsr
        and #3
        sta bd_n
        stz bd_r
@row:   ldx bd_r
        cpx beam_len
        bcs @rts
        lda hw_tbl,x                ; the row is (2 hw + 1) * 4 wide: left edge = x / 2 - 6 - (2 hw + 1) * 2 = x / 2 - 8 - 4 hw
        asl
        asl
        clc
        adc #8
        sta dr_x
        lda bd_col
        sec
        sbc dr_x
        sta dr_x
        lda #0
        sbc #0
        sta dr_x+1
        lda bd_row0                 ; y = (first row + row) * 4
        clc
        adc bd_r
        asl
        asl
        sta dr_y
        stz dr_y+1
        txa                         ; sprite = SP_BEAM + row * 4 + phase
        asl
        asl
        clc
        adc bd_n
        clc
        adc #SP_BEAM
        jsr add_sprite_id
        inc bd_r
        bra @row
@rts:   rts
.endif
