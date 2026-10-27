; NES Galaga: the game rules of the Lynx portrait game (../lynx/src/game, one translation unit), on the NES. The rules are a translation of
; psp/game.c (RULES_PORTRAIT); nes.s is the NES side (start, NMI, the picture), view.s turns the game into sprites and background tiles.
        .include "constants.inc"
        .import xmap_lo, xmap_hi, ymap
        .export ax_lo, ax_hi, ay_lo, ay_hi, enemy_flag, form_pos, form_fdx, form_breathe, form_bstep, a_dly_lo, a_dly_hi
        .export player_x_msb, enemy_state, enemy_timer, enemy_hp, enemy_dir, enemy_esc, spr_x, spr_x_msb, spr_y, score, level, eb_x, eb_msb, eb_y, eb_dx, eb_active, eb_ax, pbul_x, pbul_msb, pbul_y
        .export main, frame, game_state, msg_n, anim, paused, player_x, lives, cap_state, beam_len, go_timer, pbul_active, shots, in_chal, msg_y, msg_x, msg_lo, msg_hi
        .export nmi, reset, irq, hiscore, credit_step

        .zeropage
zp_src:         .res 2                  ; string source
zp_dst:         .res 2                  ; destination (print_num / draw_bcd buffer)
sp:             .res 2                  ; the arcade rules: the bit stream of a flight path
scur:           .res 1
scnt:           .res 1
tgt:            .res 2                  ; a slot: x, y
tgy:            .res 2
rnd:            .res 1
tmpx:           .res 1                  ; scratch for the 65C02's phx / phy (the 6502 has no such instructions)
tmpy:           .res 1
credit_used:    .res 1
.ifdef PROFILE
prof_loops:     .res 2
prof_late:      .res 2
prof_nmi:       .res 1
.endif
pad:            .res 1                  ; the buttons now (read_pad)
ticked:         .res 1                  ; a tick has run since the last picture                  ; game ticks run: 6 for every tick (tick_credit - credit_used = the ticks that are due, times 6)

        .code
; Message macros: the C64 text positions (SCREEN_RAM + row * 40 + column) become name table cells: the column - 4 (40 columns -> 32),
; the rows of the field below the formation (msg_row)
.define MSG_ROW(r) (((r) <= 14) * ((r) + 9) + ((r) = 16) * 21 + ((r) > 16) * 22)
.macro print msg, addr, col
        lda #<msg
        sta zp_src
        lda #>msg
        sta zp_src+1
        lda #(((addr) .mod 40) - 4)
        sta zp_dst
        lda #MSG_ROW((addr) / 40)
        sta zp_dst+1
        jsr msg_add
.endmacro

; A message at the name table cell (column xx, row yy)
.macro print_xy msg, xx, yy, col
        lda #<msg
        sta zp_src
        lda #>msg
        sta zp_src+1
        lda #xx
        sta zp_dst
        lda #yy
        sta zp_dst+1
        jsr msg_add
.endmacro

.macro setnum buf
        lda #<buf
        sta zp_dst
        lda #>buf
        sta zp_dst+1
.endmacro

        .include "nes.s"
        .include "game/data.s"
        .include "game/hud.s"
        .include "game/view.s"
        .include "game/sound.s"
        .include "game/hiscore.s"
        .include "game/player.s"
        .include "game/sprites.s"
        .include "game/progress.s"
        .include "game/challenge.s"
        .include "game/capture.s"
        .include "game/states.s"
        .segment "CODE0"
        .include "game/arc.s"
        .code

main:   lda #$a5                        ; the random numbers (a Galois LFSR: never 0)
        sta rnd
        jsr init_slots
        jsr load_hiscore
        jsr init_sound
        jsr init_stars
        jsr enter_title

; The loop: the ticks that are due (50 a second: 5 in 6 frames on an NTSC NES), then the next picture
game_loop:
        jsr wait_nmi                    ; the last picture is shown: the shadow and the OAM page are free
@tick:  lda tick_credit
        sec
        sbc credit_used
        cmp #13                         ; far behind (a long tick): drop the ticks above 2
        bcc @due
        lda tick_credit
        sbc #12
        sta credit_used
        lda #12
@due:   cmp #6
        bcc @draw
        lda credit_used
        clc
        adc #6
        sta credit_used
.ifdef PROFILE
        lda ticked                      ; the first tick of the picture: the time starts
        bne @pt
        lda nmi_cnt
        sta prof_nmi
@pt:
.endif
        jsr game_tick
        lda #1
        sta ticked
        jmp @tick
@draw:  lda ticked                      ; no tick since the last picture: it stays (on an NTSC NES 1 frame in 6)
        beq @same
        lda #0
        sta ticked
        jsr draw_frame
.ifdef PROFILE
        inc prof_loops                  ; -DPROFILE=1: main loops (a picture each); and late ones: an NMI came since the loop began
        bne @pl
        inc prof_loops+1
@pl:    lda nmi_cnt
        cmp prof_nmi
        beq @pok
        inc prof_late
        bne @pok
        inc prof_late+1
@pok:
.endif
        jsr frame_ready
@same:  jmp game_loop

; One tick of the game (the game loop of the Lynx game)
game_tick:
.ifdef HALT
        lda halted
        beq @h_on
        rts
@h_on:  inc halt_cnt                    ; -DHALT=n: freeze after n ticks (screenshot tests)
        bne @h_lo
        inc halt_cnt+1
@h_lo:  lda halt_cnt
        cmp #<HALT
        bne @h_go
        lda halt_cnt+1
        cmp #>HALT
        bne @h_go
        lda #1
        sta paused                      ; the stars hold still
        sta halted
        rts
@h_go:
.endif
        inc frame
        lda frame
        lsr
        lsr
        lsr
        lsr
        and #1
        cmp anim
        beq @same_anim
        sta anim                        ; Wing flap toggles every 16 frames
        jsr refresh_anim
@same_anim:
        jsr read_joystick
        jsr check_pause
        jsr check_quit
        lda paused
        bne @idle                       ; Paused: only keep the screen going
        jsr snd_tick
        jsr run_state
        lda joystick_state              ; game.c keeps the state of the button in every state: a button that is held when the play starts
        and #$10                        ; (the intro, the READY) is not a press
        bne @fire_up
        lda #1
        sta fire_pressed
@fire_up:
@idle:  jmp update_sprite_data

run_state:
        ldx game_state
        beq @title
        dex
        beq @intro
        dex
        beq @play
        dex
        beq @dying
        dex
        beq @over
        dex
        beq @capt
        dex
        beq @result
        jmp st_ready
@result: jmp st_result
@capt:  jmp st_captured
@over:  jmp st_gameover
@title: jmp st_title
@intro: jmp st_intro
@play:  jmp st_play
@dying: jmp st_dying

        .rodata
        .include "gfx_data.inc"
        .segment "CODE0"
        .include "arcade_data_portrait.s"

; The graphics (bank 1): copied to CHR RAM and the name table when the screen changes (nes.s)
        .segment "GFX"
chr_game:       .incbin "../gfx/game.chr"
chr_title:      .incbin "../gfx/title.chr"
title_nam:      .incbin "../gfx/title.nam"

; The start stub of every bank: at power-on the MMC1 may show any bank at $C000 (32 KB mode). The stub resets the MMC1 (the fixed bank 3
; comes to $C000) and jumps to reset there. The vectors of banks 0..2 point to the stub as it is seen at $FFE0.
.macro stub seg
        .segment seg
        sei
        ldx #$ff
        txs
        lda #$80
        sta $8000
        jmp reset
        .res $1a - 12, $ff
        .word $ffe0, $ffe0, $ffe0
.endmacro
        stub "STUB0"
        stub "STUB1"
        stub "STUB2"
        .segment "STUB3"
        sei
        ldx #$ff
        txs
        lda #$80
        sta $8000
        jmp reset
        .res $1a - 12, $ff
        .word nmi, $ffe0, irq

        .segment "HEADER"
        .byte "NES", $1a
        .byte 4                         ; 4 x 16 KB PRG ROM
        .byte 0                         ; CHR RAM
        .byte $12                       ; mapper 1 (MMC1), battery RAM
        .byte $00
        .byte 1                         ; 8 KB PRG RAM
        .res 7, 0
