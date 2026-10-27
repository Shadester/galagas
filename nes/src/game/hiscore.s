; Hi-score in the battery RAM (SAVE segment, $7F00): a mark ("GALA"), the three BCD bytes and their sum, so that empty or other RAM is
; not taken for a hi-score. Without a battery (or in an emulator that does not keep it) the hi-score lasts until the power is off.

        .segment "DATA"
hs_dirty:       .byte 0

        .code
load_hiscore:
        ldx #3
@m:     lda save_mark,x
        cmp hs_mark,x
        bne @none
        dex
        bpl @m
        jsr hs_sum
        cmp save_sum
        bne @none
        lda save_hi
        sta hiscore
        lda save_hi+1
        sta hiscore+1
        lda save_hi+2
        sta hiscore+2
@none:  rts

save_hiscore:
        lda hiscore
        sta save_hi
        lda hiscore+1
        sta save_hi+1
        lda hiscore+2
        sta save_hi+2
        jsr hs_sum
        sta save_sum
        ldx #3
@m:     lda hs_mark,x
        sta save_mark,x
        dex
        bpl @m
        lda #0
        sta hs_dirty
        rts

; A = the check byte of save_hi: the sum of its bytes, + $5a
hs_sum:
        lda #$5a
        clc
        adc save_hi
        clc
        adc save_hi+1
        clc
        adc save_hi+2
        rts

        .rodata
hs_mark:        .byte "GALA"
