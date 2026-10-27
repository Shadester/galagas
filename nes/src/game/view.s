; The picture of a frame (draw_frame, after the ticks): the formation into the background, the HUD, the sprites into the OAM page.
; Game units become NES pixels by two tables (tools/gen_gfx.py): x -> xmap[x + 35] (16 bit), y -> ymap[y] (the top line of a 16 unit box).
; An alien in the formation is four background tiles at the cell nearest to it (the NES Galaga does the same: 40 aliens are far too many
; sprites for 8 a line). Everything else is 8 x 16 sprites: a 16 x 16 picture is two (the right half of a symmetric one is the left half
; turned). The aliens that fly take turns at the front of the OAM page every frame, so that more than 8 on a line flicker instead of
; vanishing.

        .segment "DATA"
form_valid:     .byte 0                 ; 0: the name table has no formation (form_tx are not set yet)
form_tx:        .res MAX_ENEMIES        ; the cell of the alien in the name table (255: none) and its first tile
form_ty:        .res MAX_ENEMIES
form_k:         .res MAX_ENEMIES
want_tx:        .res MAX_ENEMIES        ; where it should be now
want_ty:        .res MAX_ENEMIES
want_k:         .res MAX_ENEMIES
form_chg:       .res MAX_ENEMIES        ; the aliens that have moved
form_nchg:      .byte 0
form_i:         .byte 0
col_tx:         .res 10                 ; the cell of every column and row now (row_ty follows col_tx: fs_cells is a copy of both)
row_ty:         .res 5
fs_cells:       .res 15                 ; what form_sync saw the last time: the cells, the game state, the aliens' states, the bosses' pictures
fs_over:        .byte 0
fs_state:       .res MAX_ENEMIES
fs_ptr:         .res 4
oam_i:          .byte 0                 ; the next free OAM byte (0: full, after the first)
oam_n:          .byte 0                 ; sprites in the page
rot:            .byte 0                 ; the alien at the front of the OAM page
v_y:            .byte 0                 ; put_vs: the sprite's OAM y, x (16 bit), first tile, flags
v_xl:           .byte 0
v_xh:           .byte 0
v_t:            .byte 0
v_f:            .byte 0
v_a:            .byte 0

        .code
draw_frame:
        lda game_state
        beq @title
        jsr form_sync
        jsr draw_hud
        jsr draw_beam
        jsr build_oam
        lda anim                        ; the wing frame of the formation: the background pattern table
        beq @a
        lda #CTRL_BG1
@a:     ora #CTRL_BASE
        sta ppu_ctrl
@title: jmp queue_jobs

; ---------------------------------------------------------------------------------------------
; The formation in the name table
; ---------------------------------------------------------------------------------------------
form_sync:
        lda form_valid
        bne @valid
        ldx #MAX_ENEMIES - 1           ; a new screen: nothing is in the name table
        lda #255
@inv:   sta form_tx,x
        sta fs_state,x                  ; (no state is 255: the first sync looks at everything)
        dex
        bpl @inv
        inc form_valid
@valid: ldx #9                          ; the cell of every column (slot_cache: x 4..218 in the portrait field, the high byte is 0)
@col:   lda colx_lo,x
        clc
        adc #35
        tay
        lda xmap_hi,y
        bne @cx
        lda xmap_lo,y
        clc
        adc #4
        bcs @cx
        lsr
        lsr
        lsr
        cmp #31
        bcc @cs
@cx:    lda #255
@cs:    sta col_tx,x
        dex
        bpl @col
        ldx #4                          ; the cell of every row: the nearest (the bosses: at or above it, so that they stay in the tile
@row:   ldy rowy_lo,x                  ; rows 2 and 3 of their palette)
        lda ymap,y
        cpx #0
        beq @boss
        clc
        adc #4
@boss:  lsr
        lsr
        lsr
        cmp #29
        bcc @rs
        lda #255
@rs:    sta row_ty,x
        dex
        bpl @row
        ldx #14                         ; nothing has moved, no alien has come or gone: nothing to do (most frames)
@same:  lda col_tx,x
        cmp fs_cells,x
        bne @diff
        dex
        bpl @same
        lda game_state
        cmp fs_over
        bne @diff
        ldx #MAX_ENEMIES - 1
@st:    lda enemy_state,x
        cmp fs_state,x
        bne @diff
        dex
        bpl @st
        ldx #3
@bp:    lda enemy_ptr,x
        cmp fs_ptr,x
        bne @diff
        dex
        bpl @bp
        rts
@diff:  ldx #14
@cp:    lda col_tx,x
        sta fs_cells,x
        dex
        bpl @cp
        lda game_state
        sta fs_over
        ldx #MAX_ENEMIES - 1
@cps:   lda enemy_state,x
        sta fs_state,x
        dex
        bpl @cps
        ldx #3
@cpp:   lda enemy_ptr,x
        sta fs_ptr,x
        dex
        bpl @cpp
        lda #0                          ; then every alien: where it should be (255: not in the formation); the changed ones go to
        sta form_nchg                   ; form_chg, the cells they leave are blanked first (an alien may move into a cell that another leaves)
        ldx #MAX_ENEMIES - 1
@al:    lda #255
        ldy game_state
        cpy #GS_GAMEOVER
        beq @want
        ldy enemy_state,x
        cpy #1
        bne @want
        ldy arc_slot_row,x
        lda row_ty,y
        sta want_ty,x
        ldy arc_slot_col,x
        lda col_tx,y
        cmp #255
        beq @want
        ldy want_ty,x
        cpy #255
        beq @want                       ; (A = 255)
        ldy enemy_type_tbl,x
        bne @k
        ldy enemy_ptr,x                 ; a boss: hit once?
        cpy #SPR_BOSSP
        bne @k0
        ldy #3
        jmp @k
@k0:    ldy #0
@k:     pha
        lda type_tile,y
        sta want_k,x
        pla
@want:  sta want_tx,x
        cmp form_tx,x                   ; changed?
        bne @chg
        cmp #255
        beq @next
        lda want_ty,x
        cmp form_ty,x
        bne @chg
        lda want_k,x
        cmp form_k,x
        beq @next
@chg:   ldy form_nchg
        txa
        sta form_chg,y
        inc form_nchg
        lda form_tx,x
        cmp #255
        beq @next
        jsr form_erase
@next:  dex
        bpl @al
        ldy form_nchg                   ; then draw the changed ones where they are now
        beq @rts
@dr:    dey
        sty form_i
        ldx form_chg,y
        lda want_tx,x
        sta form_tx,x
        lda want_ty,x
        sta form_ty,x
        lda want_k,x
        sta form_k,x
        lda form_tx,x
        cmp #255
        beq @dn
        jsr form_draw
@dn:    ldy form_i
        bne @dr
@rts:   rts

; nt_ptr = the shadow at the cell (form_tx, form_ty) of alien X; the two rows are dirty
form_cell:
        ldy form_ty,x
        lda #1
        sta row_dirty,y
        sta row_dirty+1,y
        lda shadow_lo,y
        clc
        adc form_tx,x
        sta nt_ptr
        lda shadow_hi,y
        adc #0
        sta nt_ptr+1
        rts

; Blank the four cells of alien X (only the formation's tiles: a message may be there)
form_erase:
        jsr form_cell
        ldy #0
        jsr @one
        ldy #1
        jsr @one
        ldy #32
        jsr @one
        ldy #33
@one:   lda (nt_ptr),y
        sec
        sbc #T_FORM
        cmp #16
        bcs @keep
        lda #0
        sta (nt_ptr),y
@keep:  rts

; Put the four tiles of alien X in (not over a message)
form_draw:
        jsr form_cell
        lda form_k,x
        sta v_t
        ldy #0
        jsr @one
        ldy #1
        jsr @one
        ldy #32
        jsr @one
        ldy #33
@one:   lda (nt_ptr),y
        beq @put
        sec
        sbc #T_FORM
        cmp #16
        bcs @keep
@put:   lda v_t
        sta (nt_ptr),y
        inc v_t
@keep:  rts

; ---------------------------------------------------------------------------------------------
; The sprites
; ---------------------------------------------------------------------------------------------
build_oam:
        lda #0
        sta oam_i
        sta oam_n
        lda game_state
        cmp #GS_TITLE
        beq @rest
        ldx #VS_PLAYER                  ; the ship(s) and the captive first: they never flicker
        jsr put_vs
        ldx #VS_DUAL
        jsr put_vs
        ldx #VS_CAPT
        jsr put_vs
        ldx #VS_PBUL
@shot:  lda spr_y,x                     ; the shots and the bombs
        cmp #255
        beq @sn
        jsr put_vs
@sn:    inx
        cpx #VS_EBUL + EBN
        bne @shot
        lda rot                         ; the aliens, from the one at the front (the ones in the formation are in the background)
        clc
        adc #7
        cmp #MAX_ENEMIES
        bcc @rok
        sbc #MAX_ENEMIES
@rok:   sta rot
        tax
@al:    lda spr_y,x
        cmp #255
        beq @an
        lda enemy_state,x
        cmp #1
        beq @an
        jsr put_vs
@an:    inx
        cpx #MAX_ENEMIES
        bne @aw
        ldx #0
@aw:    cpx rot
        bne @al
        jsr draw_stars
@rest:  ldx oam_i                       ; the rest of the page: off the screen
        lda oam_n
        cmp #64
        bcs @done
        lda #$ff
@h:     sta oam,x
        inx
        inx
        inx
        inx
        bne @h
@done:  rts

pv_rts: rts

; Virtual sprite X into the OAM page (nothing when it is hidden, in the formation or off the screen): one or two 8 x 16 sprites. Keeps X.
put_vs:
        ldy spr_y,x
        cpy #255
        beq pv_rts
        cpx #MAX_ENEMIES
        bcs @show
        lda enemy_state,x               ; an alien in the formation is in the background
        cmp #1
        beq pv_rts
@show:  lda ymap,y
        cmp #255
        beq pv_rts
        sec
        sbc #1                          ; the PPU shows a sprite one line below its y
        sta v_y
        lda spr_x,x
        clc
        adc #35
        tay
        lda spr_x_msb,x
        adc #0
        bne pv_rts
        lda xmap_lo,y
        sta v_xl
        lda xmap_hi,y
        sta v_xh
        ldy spr_f,x
        lda spr_tile,y
        sta v_t
        lda spr_flags,y
        sta v_f
        and #3
        sta v_a
        ldy oam_i
        lda v_xh                        ; the left half
        bne @right
        lda oam_n
        cmp #64
        bcs pv_rts
        inc oam_n
        lda v_y
        sta oam,y
        lda v_t
        sta oam+1,y
        lda v_a
        sta oam+2,y
        lda v_xl
        sta oam+3,y
        iny
        iny
        iny
        iny
@right: bit v_f
        bvs @end                        ; one column (a shot, a bomb)
        bmi @two
        lda v_a                         ; symmetric: the left half turned
        ora #$40
        sta v_a
        jmp @rx
@two:   inc v_t
        inc v_t
@rx:    lda v_xl
        clc
        adc #8
        sta v_xl
        lda v_xh
        adc #0
        bne @end
        lda oam_n
        cmp #64
        bcs @end
        inc oam_n
        lda v_y
        sta oam,y
        lda v_t
        sta oam+1,y
        lda v_a
        sta oam+2,y
        lda v_xl
        sta oam+3,y
        iny
        iny
        iny
        iny
@end:   sty oam_i
        rts

; The stars: one pixel each (the top left pixel of a sprite, behind the background), at the end of the page. They move down every frame.
draw_stars:
        ldx #NUM_STARS - 1
        ldy oam_i
@s:     lda oam_n
        cmp #64
        bcs @full
        inc oam_n
        lda paused
        bne @still                      ; Paused: the stars hold still
        lda star_y,x
        clc
        adc star_v,x
        cmp #232
        bcc @keep
        lda #8
@keep:  sta star_y,x
@still: lda star_y,x
        sta oam,y
        lda star_tile,x
        sta oam+1,y
        lda #$23                        ; palette S3, behind the background
        sta oam+2,y
        lda star_x,x
        sta oam+3,y
        iny
        iny
        iny
        iny
        dex
        bpl @s
@full:  sty oam_i
        rts

        .rodata
star_tile:                              ; the colour: yellow, red, white by the star
        .repeat NUM_STARS, n
        .byte S_STAR1 + 2 * (n .mod 3)
        .endrepeat
type_tile:      .byte T_FORM + 8, T_FORM + 4, T_FORM, T_FORM + 12    ; boss, butterfly, bee, hit boss

; ---------------------------------------------------------------------------------------------
; The tractor beam: up to 8 thin rings (2 for each of the beam_len rows of the rules) under the capture boss, as background tiles
; T_BEAM.. that the game draws into beam_buf at the pixel (centred under the boss) and copies to CHR RAM (2 tiles a frame, queue_jobs).
; The rings take turns at being the light one: the three colours of palette BG3 turn round every 4 ticks. Ring k is at the boss's
; y + 12 + 5 k: from under the boss to the bottom of the ship (the rules' beam is a row of the width (2 hw + 1) * 8 units every 8 units:
; the field below the formation has fewer lines than units, so the rings are spread over the ship too). Ring 1 of a row spans the row's
; width, ring 0 80 percent of it.
; ---------------------------------------------------------------------------------------------
        .segment "DATA"
beam_on:        .byte 0                 ; 0: no beam; 1: its tiles are being copied; 2: it is in the name table
beam_drawn:     .byte 0                 ; the beam_len of the picture in beam_buf
b_cx:           .byte 0                 ; the boss's centre (pixel), the rectangle of the beam (cells)
b_tx0:          .byte 0
b_ty0:          .byte 0
b_tw:           .byte 0
b_th:           .byte 0
b_by:           .byte 0
b_phase:        .byte 0
b_k:            .byte 0                 ; beam_compose: the ring, its row in its tile, the tile row, the first and last pixel, the colour
b_row:          .byte 0
b_tr:           .byte 0
b_x0:           .byte 0
b_x1:           .byte 0
b_c:            .byte 0
b_m:            .byte 0
b_tc:           .byte 0
b_mul:          .byte 0

        .code
draw_beam:
        lda cap_state
        cmp #2
        beq @on
        cmp #3
        beq @on
        lda beam_on                     ; no beam: take it away
        beq @rts
        cmp #2
        bne @off
        jsr beam_cells_clear
@off:   lda #0
        sta beam_on
        sta tq_left
@rts:   rts
@on:    lda beam_on
        bne @have
        jsr beam_setup
        lda #1
        sta beam_on
        lda #255
        sta beam_drawn
@have:  lda beam_len
        cmp beam_drawn
        beq @same
        sta beam_drawn
        jsr beam_compose
        lda #0
        sta tq_pos
        lda b_tw                        ; tiles: tw * th
        ldx b_th
        dex
@mul:   beq @tq
        clc
        adc b_tw
        dex
        jmp @mul
@tq:    sta tq_left
@same:  lda beam_on
        cmp #2
        beq @pal
        lda tq_left
        bne @pal                        ; the tiles are not all in CHR RAM yet
        jsr beam_cells_set
        lda #2
        sta beam_on
@pal:   lda frame                       ; the colours: phase (frame / 4) mod 3
        lsr
        lsr
        tax
        lda mod3,x
        cmp b_phase
        beq @done
        sta b_phase
        tax                             ; entry i of BG3 = colour (i - phase) mod 3
        lda beam_col,x
        sta pal_buf+13
        lda beam_col+2,x
        sta pal_buf+14
        lda beam_col+1,x
        sta pal_buf+15
        lda #1
        sta pal_dirty
@done:  rts

; The rectangle of the beam (for all 8 rings) under boss cap_boss
beam_setup:
        ldx cap_boss
        lda ay_lo,x
        sta b_by
        lda ax_lo,x                     ; the centre: x + 8
        clc
        adc #8 + 35
        tay
        lda xmap_lo,y
        sta b_cx
        sec
        sbc #32
        bcs @l
        lda #0
@l:     lsr
        lsr
        lsr
        sta b_tx0
        lda b_cx
        clc
        adc #32
        bcc @r
        lda #255
@r:     lsr
        lsr
        lsr
        sec
        sbc b_tx0
        clc
        adc #1
        sta b_tw
        lda b_by                        ; the rows: the line of ring 0 (y + 12) to the line of ring 7 (y + 47): ymap[p - 8] + 8
        clc
        adc #12 - 8
        tay
        lda ymap,y
        clc
        adc #8
        lsr
        lsr
        lsr
        sta b_ty0
        lda b_by
        clc
        adc #47 - 8
        tay
        lda ymap,y
        clc
        adc #8
        lsr
        lsr
        lsr
        sec
        sbc b_ty0
        clc
        adc #1
        sta b_th
        rts

; The picture of beam_drawn rows into beam_buf
beam_compose:
        lda #<beam_buf                  ; clear the 40 tiles
        sta nt_ptr
        lda #>beam_buf
        sta nt_ptr+1
        lda #0
        ldy #0
@c1:    sta (nt_ptr),y
        iny
        bne @c1
        inc nt_ptr+1
@c2:    sta (nt_ptr),y
        iny
        bne @c2
        inc nt_ptr+1
@c3:    sta (nt_ptr),y
        iny
        cpy #40 * 16 - 512
        bne @c3
        lda #0
        sta b_k
@ring:  lda beam_drawn
        asl
        cmp b_k
        beq @rts
        bcs @go
@rts:   rts
@go:    ldx b_k                         ; the line of ring k: the point y + 12 + 5 k (ymap[p - 8] + 8)
        lda b_k
        asl
        asl
        clc
        adc b_k
        clc
        adc b_by
        clc
        adc #12 - 8
        tay
        lda ymap,y
        clc
        adc #8
        pha
        and #7
        sta b_row
        pla
        lsr
        lsr
        lsr
        sec
        sbc b_ty0
        sta b_tr
        lda ring_col,x
        sta b_c
        lda b_tx0                       ; the first and last pixel, from the left edge of the rectangle
        asl
        asl
        asl
        sta b_m
        lda b_cx
        sec
        sbc ring_hw,x
        bcs @x0
        lda #0
@x0:    sec
        sbc b_m
        bcs @x0b
        lda #0
@x0b:   sta b_x0
        lda b_cx
        clc
        adc ring_hw,x
        bcc @x1
        lda #255
@x1:    sec
        sbc b_m
        sta b_x1
        lda b_tw                        ; at most the last pixel of the rectangle
        asl
        asl
        asl
        sec
        sbc #1
        cmp b_x1
        bcs @x1b
        sta b_x1
@x1b:   lda b_x0
        lsr
        lsr
        lsr
        sta b_tc
@tile:  lda #$ff                        ; the mask of the ring in tile column b_tc
        sta b_m
        lda b_x0
        lsr
        lsr
        lsr
        cmp b_tc
        bne @nl
        lda b_x0
        and #7
        tay
        lda lmask,y
        sta b_m
@nl:    lda b_x1
        lsr
        lsr
        lsr
        cmp b_tc
        bne @nr
        lda b_x1
        and #7
        tay
        lda rmask,y
        and b_m
        sta b_m
@nr:    lda b_tr                        ; the tile: tr * tw + tc; nt_ptr = beam_buf + tile * 16 + row
        ldx b_tw
        jsr mul8
        clc
        adc b_tc
        pha
        lsr
        lsr
        lsr
        lsr
        sta nt_ptr+1
        pla
        asl
        asl
        asl
        asl
        ora b_row
        clc
        adc #<beam_buf
        sta nt_ptr
        lda nt_ptr+1
        adc #>beam_buf
        sta nt_ptr+1
        ldy #0
        lda b_c
        lsr
        bcc @p1
        lda (nt_ptr),y
        ora b_m
        sta (nt_ptr),y
@p1:    lda b_c
        and #2
        beq @nt
        ldy #8
        lda (nt_ptr),y
        ora b_m
        sta (nt_ptr),y
@nt:    lda b_x1
        lsr
        lsr
        lsr
        cmp b_tc
        beq @next
        inc b_tc
        jmp @tile
@next:  inc b_k
        jmp @ring

; A = A * X (small numbers)
mul8:   sta b_mul
        lda #0
        cpx #0
        beq @r
@l:     clc
        adc b_mul
        dex
        bne @l
@r:     rts

; The cells of the rectangle: T_BEAM + its tiles, in the attributes palette 3
beam_cells_set:
        lda #0
        sta b_k                         ; the tile
        sta b_tr
@row:   lda b_ty0
        clc
        adc b_tr
        tay
        lda #1
        sta row_dirty,y
        lda shadow_lo,y
        clc
        adc b_tx0
        sta nt_ptr
        lda shadow_hi,y
        adc #0
        sta nt_ptr+1
        ldy #0
@cell:  lda b_k
        clc
        adc #T_BEAM
        sta (nt_ptr),y
        inc b_k
        sty b_tc
        tya                             ; the attribute of the cell: palette 3
        clc
        adc b_tx0
        tax
        lda b_ty0
        clc
        adc b_tr
        jsr attr_set3
        ldy b_tc
        iny
        cpy b_tw
        bne @cell
        inc b_tr
        lda b_tr
        cmp b_th
        bne @row
        lda #1
        sta attr_dirty
        rts

; Palette 3 for the 16 x 16 area of the cell (column X, row A)
attr_set3:
        sta b_m
        and #2                          ; the shift: (row & 2) * 2 + (column & 2)
        asl
        sta b_x0
        txa
        and #2
        ora b_x0
        tay
        lda b_m                         ; the byte: (row / 4) * 8 + column / 4
        lsr
        lsr
        asl
        asl
        asl
        sta b_x0
        txa
        lsr
        lsr
        ora b_x0
        tax
        lda attr_mask3,y
        ora attr_buf,x
        sta attr_buf,x
        rts

; Take the beam away: blank its cells, the attributes of the game again
beam_cells_clear:
        lda #0
        sta b_tr
@row:   lda b_ty0
        clc
        adc b_tr
        tay
        lda #1
        sta row_dirty,y
        lda shadow_lo,y
        clc
        adc b_tx0
        sta nt_ptr
        lda shadow_hi,y
        adc #0
        sta nt_ptr+1
        ldy #0
@cell:  lda (nt_ptr),y
        cmp #T_BEAM
        bcc @keep
        lda #0
        sta (nt_ptr),y
@keep:  iny
        cpy b_tw
        bne @cell
        inc b_tr
        lda b_tr
        cmp b_th
        bne @row
        ldx #63
@a:     lda attr_game,x
        sta attr_buf,x
        dex
        bpl @a
        lda #1
        sta attr_dirty
        rts

        .rodata
; the rings: half width (pixels: (2 hw + 1) * 4 units, ring 0 of a row 80 percent of it, * 8 / 7) and colour (1, 2, 3 in turn)
ring_hw:        .byte 10, 13, 10, 13, 18, 22, 25, 31
ring_col:       .byte 1, 2, 3, 1, 2, 3, 1, 2
lmask:          .byte $ff, $7f, $3f, $1f, $0f, $07, $03, $01
rmask:          .byte $80, $c0, $e0, $f0, $f8, $fc, $fe, $ff
attr_mask3:     .byte $03, 0, $0c, 0, $30, 0, $c0
beam_col:       .byte $31, $21, $11, $31, $21  ; light, middle, dark (twice: the phase is the start)
mod3:
        .repeat 64, n
        .byte n .mod 3
        .endrepeat
