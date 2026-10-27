; Hits, scoring, player death and stage progression
; Player bullet hit enemy X: boss survives one hit, everything else dies

hit_enemy:
    dec enemy_hp,x
    beq @kill
    lda #SPR_BOSSP          ; Damaged boss turns purple
    sta enemy_ptr,x
    clc
    adc anim
    sta spr_f,x
    jmp sound_shoot
@kill:
    stx hit_idx
    cpx cap_boss
    bne @plain
    lda cap_state
    beq @plain
    jsr boss_killed
    ldx hit_idx
@plain:
    lda in_chal
    beq @normal
    inc ch_hits                 ; Challenge stage: flat points per hit
    ldx chal_mid
    lda #0
    jmp @add
@normal:
    ldy enemy_type_tbl,x
    lda enemy_state,x
    cmp #2
    beq @dive_pts
    cmp #7
    beq @dive_pts               ; Entering aliens pay like divers
    lda pts_form_mid,y
    tax
    lda pts_form_lo,y
    jmp @add
@dive_pts:
    cpy #0
    bne @std_dive
    jsr count_escorts       ; Diving boss: 400 / 800 / 1600 with 0 / 1 / 2 escorts alive
    ldx #6                  ; no bombs for a while after a diving boss was shot
    stx arc_hold
    ldx hit_idx
    tay
    ldx esc_pts_mid,y
    lda #0
    jmp @add
@std_dive:
    lda pts_dive_mid,y
    tax
    lda pts_dive_lo,y
@add:
    jsr add_score
    ldx hit_idx
    jsr set_explode
    jmp sound_explosion

; Number of escorts of boss hit_idx still flying (A, 0..2); X = hit_idx

count_escorts:
    lda hit_idx
    clc
    adc #1
    sta esc_cmp
    lda #0
    sta esc_cnt
    ldx #MAX_ENEMIES-1
@loop:
    lda enemy_esc,x
    cmp esc_cmp
    bne @next
    lda enemy_state,x
    cmp #2
    beq @yes
    cmp #3
    bne @next
@yes:
    inc esc_cnt
@next:
    dex
    bpl @loop
    ldx hit_idx
    lda esc_cnt
    rts

; Add BCD points to the 6-digit score. In: A = low pair, X = middle pair

add_score:
    sta bcd_t                   ; (the 2A03 has no decimal mode: bcd_adc)
    lda score
    clc
    jsr bcd_adc
    sta score
    stx bcd_t
    lda score+1
    jsr bcd_adc
    sta score+1
    lda add_hi
    sta bcd_t
    lda score+2
    jsr bcd_adc
    sta score+2
    lda #0
    sta add_hi
    lda score+2             ; Bonus ship at 20,000, 70,000, then every 70,000
    cmp next_bonus
    bcc @rts
    lda next_bonus
    cmp #2
    bne @repeat
    lda #7
    bne @set_next
@repeat:
    ldx #7
    stx bcd_t
    clc
    jsr bcd_adc
@set_next:
    sta next_bonus
    lda lives
    cmp #9
    bcs @rts
    inc lives
    lda #jin_bonus-jin_data
    jmp play_jingle
@rts:
    rts



; A = A + bcd_t + carry, two BCD digits each; carry out. Keeps X and Y. (The 2A03 of the NES is a 6502 without the decimal mode.)
bcd_adc:
    php
    sta bcd_a
    and #$0f
    sta bcd_l
    lda bcd_t
    and #$0f
    plp
    adc bcd_l                   ; the low digits and the carry: 0..19
    cmp #10
    bcc @lo
    adc #5                      ; (carry set) + 6: $10..$19
@lo:
    sta bcd_l
    lda bcd_a
    and #$f0
    clc
    adc bcd_l
    sta bcd_l
    lda bcd_t
    and #$f0
    clc
    adc bcd_l
    bcs @over                   ; $100 or more
    cmp #$a0
    bcc @rts                    ; (carry clear)
    sbc #$a0                    ; (carry set: it stays set)
    rts
@over:
    adc #$5f                    ; (carry set) + $60
    sec
@rts:
    rts

; ===============================================
; LEVEL PROGRESSION
; ===============================================

; All enemies gone (and none still exploding)? Start the next stage.

check_level_complete:
    lda cap_state
    cmp #5
    beq @rts                ; A rescued ship is still on its way down
    ldx #MAX_ENEMIES-1
@loop:
    lda enemy_state,x
    bne @rts
    dex
    bpl @loop
    jmp next_level
@rts:
    rts


next_level:
    lda #1
    sta bcd_t
    lda level
    clc
    jsr bcd_adc
    sta level
    inc stage
    lda in_chal
    bne @capped                 ; A challenge stage doesn't make the game harder
    lda diff
    cmp #8
    bcs @capped
    inc diff
@capped:
    jmp enter_result            ; Shots / hits screen, then the next stage
