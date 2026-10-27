# galaga for the NES

The NES game in 6502 assembly (ca65/ld65). The rules are the Lynx portrait game's (`../lynx/src/game`, a translation of `../psp/game.c` with
`RULES_PORTRAIT`), copied to `src/game/` and made plain 6502; the NES side (`src/nes.s`, `src/game/view.s`, `hud.s`, `sound.s`, `hiscore.s`)
is new. `README.md` has the design (formation as background tiles, the screen mapping, the cartridge), controls, flags and the source layout.

## Build, run, test

```sh
make                      # build/galaga.nes (cc65)
tests/run.py [case ...]   # screenshot tests, headless cynes (pip install cynes), 4 cases at a time
tests/run.py --update [case ...]   # regenerate tests/ref/*.png after an intended change; look at them first
python3 ../tools/compare_6502.py nes SCENARIO   # the rules against psp/game.c -DRULES_PORTRAIT (all 8 must be equal)
python3 tools/make_gif.py # re-record docs/gameplay.gif
python3 tools/gen_gfx.py  # after a change of the art, the font, the palettes or the screen mapping
```

- `make` with other `CAFLAGS`: use another `BUILD=` directory or `make clean` (the Makefile does not see the flags).
- `-g` is on: `build/galaga.lbl` has every label. `tools/dbg.py ROM FRAMES label[:n] ...` prints them; `tools/prof.py ROM FRAME routine ...`
  counts the cycles of routines (cynes memory into py65; the PPU reads as 0).
- After a change of `src/`: copy `build/galaga.nes` to `../docs/nes/galaga.nes` (the web page).
- Never push without the user's OK (global rule).

## Things to know

- **Ticks and frames:** the NMI adds `credit_step` (5 NTSC, 6 PAL: `detect_region`) to `tick_credit`; the main loop runs a tick for every 6
  (`credit_used`), so the game keeps 50 ticks a second. After the ticks it builds the picture (`draw_frame`) and sets `nmi_ready`; it
  touches the shadow name table, the OAM page and the buffers only while `nmi_ready` is 0. A frame without a tick keeps the last picture.
- **The NMI's time:** vertical blank is about 2270 cycles (NTSC). OAM DMA 513, a row of the name table about 290 (`nmi_rows`, unrolled
  per page of the shadow: the shadow must start at a page), 2 beam tiles about 800, the attributes 520, the palette 270. `queue_jobs`
  gives each frame about `ROWS_NMI` rows' worth. Too much and writes land after the vertical blank: the picture breaks (missing letters).
- **CPU time:** a tick is about 14k cycles (17k in the stage-1 fly-in), a picture about 7k; an NTSC frame has about 27k after the NMI.
  `-DPROFILE=1` counts late pictures (`prof_loops`, `prof_late`). In the fly-in about 15 % of the pictures are late (the ticks catch up).
  The NES-only shortcuts that keep it in time: `slot_cache` (the slot of every column and row, not of every alien), `form_sync` does
  nothing when nothing moved, `arc_sync_aliens` skips the formation, `ship_rams` calls `ram_one` only for divers and flyers.
- **Variables** are in the DATA segment (battery RAM at `$6000`, copied from the ROM at the start): the Lynx keeps them in its code.
  A variable in `.code` or `.rodata` is ROM on the NES: it cannot be written.
- **Banks:** bank 0 (`CODE0`: `arc.s`, the arcade data) is at `$8000` while the game runs; bank 1 (`GFX`) only during `chr_copy` and
  `screen_title`; bank 3 is fixed. `CODE` + `RODATA` + the DATA image must fit in bank 3 (16 KB).
- **Messages** keep the C64 text positions: `print` maps the column to `column - 4` and the row with `MSG_ROW` (rows 18..23, below the
  formation, above the beam's attribute area). Letters are red and digits white (palette 0); there is one font.
- **Attributes:** the boss row must stay in tile rows 2 and 3 (palette 2); `form_sync` puts a boss in the cell at or above it.
- **No decimal mode:** `sed` does nothing on the 2A03. Use `bcd_adc`.
- **cynes** (the test emulator) reads the battery RAM as garbage before `copy_data` has run: wait some frames before reading labels.

## Conventions

- `arc.s` follows `../psp/game.c` (as the Lynx's): keep its names, and check a change with `compare_6502.py nes`.
- Comments explain why, are short, and match the surrounding style. README text is in Simplified Technical English.
- Keep commits small. Do not push without asking.
