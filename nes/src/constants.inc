; Hardware, memory and the game's shared limits

PPUCTRL     = $2000
PPUMASK     = $2001
PPUSTATUS   = $2002
OAMADDR     = $2003
PPUSCROLL   = $2005
PPUADDR     = $2006
PPUDATA     = $2007
OAMDMA      = $4014
JOY1        = $4016
JOY2        = $4017
APU_STATUS  = $4015
APU_FRAME   = $4017

; PPUCTRL: NMI on, 8 x 16 sprites, the background in pattern table 0 or 1 (the wing frame, see draw_frame)
CTRL_BASE   = $A0
CTRL_BG1    = $10

NUM_STARS   = 12

        .include "gfx.inc"

; ---- Game constants: the rules run in the units of the Lynx portrait field (psp/game.c RULES_PORTRAIT), x 0..203, y 0..253 ----
MAX_ENEMIES     = 40            ; the arcade formation: 4 bosses, 16 butterflies, 20 bees
EBN             = 8             ; enemy bombs on the screen
VS_PLAYER       = MAX_ENEMIES
VS_PBUL         = VS_PLAYER+1   ; 4 slots
VS_EBUL         = VS_PBUL+4     ; EBN slots
VS_DUAL         = VS_EBUL+EBN   ; second ship of the dual fighter
VS_CAPT         = VS_DUAL+1     ; captured ship carried by a boss
MAX_SPRITES     = VS_CAPT+3     ; ship + enemies + 4 player bullets + enemy bullets + extras
VS_NONE         = MAX_SPRITES

; The geometry of the field: the same names as the G_* macros of psp/game.h (the RULES_PORTRAIT block)
PORTRAIT        = 1
PLAYER_Y        = 242
SCREEN_LEFT     = 4
SCREEN_RIGHT    = 186           ; the ship's biggest x (a dual fighter: less DUAL_DX)
SHIP_X0         = 95
SHIP_V          = 1
SHOT_DX         = 7
SHOT_DY         = 12
SHOT_TOP        = 4
OFF_Y           = 250
RET_Y0          = -16           ; a diver returns from above the screen
BEAM_Y          = 208
BOMB_LOW_Y      = 149
BOMB_DY         = 6
MID_X           = 95
CAPT_DY         = 12
HOME_V          = 2
HOME_NEAR       = 2
PEEL_VX         = 1
PEEL_VY         = 1
TAIL_VY         = 2
PULL_DONE       = 14
HB_SHOT_Y       = 5
HB_SHOT_XL      = 4
HB_SHOT_XR      = 8
HB_BOMB_Y0      = -2
HB_BOMB_Y1      = 7
HB_BOMB_XL      = 4
HB_BOMB_XR      = 5
HB_RAM_Y0       = 5
HB_RAM_Y1       = 5
HB_RAM_X        = 5
HB_BEAM_XL      = 13
HB_BEAM_XR      = 12
HB_DOCK_L       = 3
HB_DOCK_R       = 2
RET_V           = 2             ; a diver returning from the top
CDIVE_V0        = 2             ; a capture dive (stage 1-4, later)
CDIVE_V1        = 3
SHOT_V          = 4             ; a shot's speed
DUAL_DX         = 16            ; the second ship of a dual fighter, a docked captive
RESC_VY         = 3             ; a rescued ship flies down ...
RESC_VX         = 2             ; ... and sideways
PULL_V          = 2             ; the captured ship is pulled up

; Sprite ids (gfx.inc); +1 = second animation frame, explosions are consecutive
SPR_PLAYER      = SP_PLAYER
SPR_PBUL        = SP_PBUL
SPR_EBUL        = SP_EBUL
SPR_BEE         = SP_BEE_A
SPR_BFLY        = SP_BFLY_A
SPR_BOSS        = SP_BOSS_A
SPR_BOSSP       = SP_BOSSP_A    ; the boss after one hit (violet)
SPR_EXPL1       = SP_EXPL1
SPR_PEXP        = SP_PEXP1

; Game states
GS_TITLE        = 0
GS_INTRO        = 1
GS_PLAY         = 2
GS_DYING        = 3
GS_GAMEOVER     = 4
GS_CAPTURED     = 5             ; Player is being pulled up by a tractor beam
GS_RESULT       = 6             ; Shots / hits / ratio screen after a stage
GS_READY        = 7             ; "READY" before the ship respawns

; Joystick: the pad as the C64's active-low bits
JS_LEFT         = $04
JS_RIGHT        = $08
JS_FIRE         = $10

PAD_A           = $80           ; the pad (read_pad)
PAD_B           = $40
PAD_SELECT      = $20
PAD_START       = $10
PAD_LEFT        = $02
PAD_RIGHT       = $01

SCREEN_RAM      = 0             ; The C64 text positions (row * 40 + column) survive as message positions

ROWS_NMI        = 4             ; name table rows the NMI copies at most (about 390 cycles each)
