; Sound on the APU. The Lynx game's three voices: pulse 1 shoot / ship hit, the noise channel the explosions, pulse 2 the jingles, the dive
; swoop and the beam hum. Effects fade out by themselves: snd_tick lowers the volume every tick (each time by a part of it: a quick bang, a
; long tail) and slides the pitch down, so a shot is a "pew" and an explosion a noise that falls.
; The pitch of an effect is kept as the Lynx timer reload (rl: Hz = 41667 / (rl + 1)); the period of a pulse channel is about 2.7 * rl.

V_SHOOT         = 0
V_EXPL          = 1

        .segment "DATA"
snd_vol:        .res 2          ; fading voices 0 (pulse 1) and 1 (noise), 0..$7f
snd_dec:        .res 2          ; each tick: volume = volume - (volume >> snd_dec) - 1
snd_rl:         .res 2          ; the timer reload now
snd_rs:         .res 2          ; added to it each tick (0: no slide)
snd_t:          .res 1
snd_p:          .res 2          ; a period (pulse_period)
jin_vol:        .byte 0         ; the volume of the jingle note (0..15)

        .code
init_sound:
        lda #$0b                ; pulse 1, pulse 2, noise
        sta APU_STATUS
        lda #$30                ; all silent (constant volume 0)
        sta $4000
        sta $4004
        sta $400c
        lda #$08                ; no sweep
        sta $4001
        sta $4005
        lda #0
        sta snd_vol
        sta snd_vol+1
        rts

; snd_p = the period of a pulse channel for the Lynx reload A: A * 2.75
pulse_period:
        sta snd_p
        lda #0
        sta snd_p+1
        lda snd_p
        lsr
        sta snd_t               ; A / 2
        lsr                     ; A / 4
        clc
        adc snd_t
        sta snd_t               ; A * 0.75
        asl snd_p               ; A * 2
        rol snd_p+1
        lda snd_p
        clc
        adc snd_t
        sta snd_p
        bcc @r
        inc snd_p+1
@r:     rts

; Quick high beep
sound_shoot:
        stx tmpx                ; the callers keep X and Y (shoot_bullet loops on Y)
        sty tmpy
        lda #14                 ; 2.8 kHz, sliding down
        ldx #3
        ldy #3
        jmp snd_set0

; Lower descending tone
sound_player_hit:
        stx tmpx
        sty tmpy
        lda #70                 ; 590 Hz, sliding down
        ldx #4
        ldy #9
snd_set0:                       ; A = reload now, X = decay shift, Y = slide
        sta snd_rl
        stx snd_dec
        sty snd_rs
        lda #$60
        sta snd_vol
        lda snd_rl              ; a new note: the high byte (it starts the wave)
        jsr pulse_period
        lda snd_p
        sta $4002
        lda snd_p+1
        ora #$08
        sta $4003
        lda #$bc                ; 50 % duty, volume 12
        sta $4000
        ldx tmpx
        ldy tmpy
        rts

; Noise burst
sound_explosion:
        stx tmpx
        sty tmpy
        lda #5                  ; hiss, falling quickly
        ldx #2
        ldy #3
        jmp snd_set1

; The ship explodes: long low noise rumble
sound_player_die:
        stx tmpx
        sty tmpy
        lda #18
        ldx #4
        ldy #2
snd_set1:                       ; A = reload now, X = decay shift, Y = slide
        sta snd_rl+1
        stx snd_dec+1
        sty snd_rs+1
        lda #$7f
        sta snd_vol+1
        jsr noise_period
        lda #$3f
        sta $400c
        lda #$08
        sta $400f
        ldx tmpx
        ldy tmpy
        rts

; The noise period index for the reload snd_rl+1: 3 + rl / 4, at most 15
noise_period:
        lda snd_rl+1
        lsr
        lsr
        clc
        adc #3
        cmp #16
        bcc @p
        lda #15
@p:     sta $400e
        rts

; Pause: silence everything. Unpausing needs nothing: the next effect starts its voice again.
sound_mute:
        jsr init_sound
        lda #0
        sta jin_on
        sta swoop_cnt
        lda #$30
        sta $4004
        rts

sound_unmute:
        rts

; Start the jingle at offset A into jin_data
play_jingle:
        sta jin_pos
        lda #1
        sta jin_on
        lda #0
        sta jin_dur
        rts

; Every tick: fade voices 0 and 1, then pulse 2: the jingle player, or the dive swoop when silent
snd_tick:
        ldx #1
@fade:  lda snd_vol,x
        beq @next
        lda snd_rl,x            ; slide the pitch down
        clc
        adc snd_rs,x
        bcc @rl
        lda #255
@rl:    sta snd_rl,x
        lda snd_vol,x           ; volume = volume - (volume >> shift) - 1
        sta snd_t
        ldy snd_dec,x
@sh:    dey
        bmi @shd
        lsr snd_t
        jmp @sh
@shd:   lda snd_vol,x
        sec
        sbc snd_t
        beq @off
        bcc @off
        sec
        sbc #1
        beq @off
        sta snd_vol,x
        jsr snd_out
        jmp @next
@off:   lda #0
        sta snd_vol,x
        jsr snd_out
@next:  dex
        bpl @fade

        lda jin_on
        bne @jingle
        lda swoop_cnt
        beq @rts
        dec swoop_cnt
        beq @swoop_end
        tax
        lda swoop_tbl,x         ; Falling pitch
        jsr pulse_period
        lda snd_p
        sta $4006
        lda snd_p+1
        sta $4007
        lda #$b6                ; 50 % duty, volume 6
        sta $4004
@rts:   rts
@swoop_end:
        lda #$30
        sta $4004
        rts
@jingle:
        lda jin_dur
        beq @next_note
        dec jin_dur
        lda jin_vol             ; the note decays a little (SID: decay to the sustain level)
        cmp #8
        bcc @rts
        dec jin_vol
        lda jin_vol
        ora #$b0
        sta $4004
        rts
@next_note:
        ldx jin_pos
        lda jin_data+2,x        ; Duration, 0 ends the tune
        beq @jin_end
        sta jin_dur
        lda jin_data,x          ; the period
        sta $4006
        lda jin_data+1,x
        ora #$08
        sta $4007
        inx
        inx
        inx
        stx jin_pos
        lda #12
        sta jin_vol
        lda #$bc
        sta $4004
        rts
@jin_end:
        lda #0
        sta jin_on
        lda #$30
        sta $4004
        rts

; Voice X (0: pulse 1, 1: noise): its volume and pitch now. Keeps X.
snd_out:
        txa
        bne @noise
        lda snd_vol
        lsr
        lsr
        lsr
        ora #$b0
        sta $4000
        lda snd_rl
        jsr pulse_period
        lda snd_p               ; only the low byte: writing the high byte starts the wave again (a click)
        sta $4002
        rts
@noise: lda snd_vol+1
        lsr
        lsr
        lsr
        ora #$30
        sta $400c
        jmp noise_period

        .rodata
; Timer reload for the swoop (as the Lynx's): C64 SID frequency (swoop_cnt * 2 + 8) * 256 -> 15 Hz per step -> Hz = (2n + 8) * 15.03
swoop_tbl:
        .byte 0
        .repeat 24, n
        .byte .min(255, 41667 / (((n + 1) * 2 + 8) * 15) - 1)
        .endrepeat
