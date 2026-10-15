# galaga for the Amiga

Bare-metal Amiga 500 game (68000, OCS, PAL), a bootable ADF. The rules are `../psp/game.c` (the reference),
built here without floats. `README.md` has the status, controls, commands and the layout.

## Build, run, test

```sh
tools/setup-macos.sh                  # once: m68k-elf-gcc, binutils, FS-UAE, Pillow (Homebrew)
make                                  # build/galaga.adf (m68k-elf-gcc -O3, objcopy, tools/make_adf.py); NPL=4 builds 4 planes (speed test only: the art is for 5)
tools/run.sh                          # build and run it in FS-UAE (brew install --cask fs-uae-emulator)
make web                              # docs/galaga.adz for the play link in the READMEs
python3 tests/test_selftest.py [n]    # the 68000 in vAmigaWeb vs the Mac, 4 scenarios (about 10 s)
python3 tests/shots.py [--update] [case ...]   # screenshots in vAmigaWeb; look at new refs before you commit them
python3 tests/compare.py [--ref COMMIT] [--flags -DNOASM] [--quick]   # a speed change must not change a picture: builds the reference commit (worktree) and this tree, freezes both at 17 tick counts, compares pixels
```

- The tests need `playwright` (`pip install playwright pillow && playwright install chromium`) and `m68k-elf-gcc`.
- A change in `psp/game.c` is a change for all the ports. The Amiga build includes it (`src/game.c`). The rules are the arcade rules, see `../ARCADE.md`.
- The art is in `tools/art.py` (palette of 32 and the pixel art, with the shading rules); `tools/gen_assets.py [preview.png]` makes
  `src/assets.h` and a preview picture. Change the art there, not in `assets.h`.
- Palette: sprites 4 and 5 (the stars) use the colours 25, 26 and 27: keep them mid, dim and bright in `tools/art.py`.
- Generated and committed: `src/assets.h`, `docs/galaga.adz`, `docs/gameplay.gif`.
- `make` does not see a change of `EXTRA_CFLAGS`: the tests delete their build folder first; do `make clean` when you try flags by hand.
- Never push without the user's OK (global rule). Show a change and wait for the OK before you commit.

## Hardware facts that bit us

- **Supervisor mode:** the Kickstart calls the boot block in user mode. `move #x,sr` is privileged: the boot block calls
  `SuperState` (exec, -150) before it kills the OS. Without it the game hangs at the first `move.w #0x2700,sr` (grey screen).
- **Boot:** a1 = the trackdisk request, a6 = ExecBase. The boot block does `AllocMem`, `DoIO` (`CMD_READ` from byte 1024),
  motor off, then INTENA / INTREQ / DMACON off, copies the game to 0x1000 and jumps. `tools/make_adf.py` patches the load
  size into byte 16 and makes the checksum. The boot block must stay under 1024 bytes.
- **The blitter and the CPU:** the blitter works while the CPU runs. Wait for it (`wait_blit`, `DMACONR` bit 14, read it once
  first) before the CPU draws in the same bitmap or starts the next blit. A missing wait gave text that was cleared a moment
  after it was drawn, and sprites that were missing in every other frame.
- **Three bitmaps:** after `video_end` the copper shows the new bitmap at the next vertical blank. The code keeps `shown` (on the screen) and
  `pending` (handed over, not yet shown); `settle_display()` must run whenever a bitmap is chosen or handed over, because a vertical blank
  can come at any time. Without it the bitmap on the screen is taken for a free one, and the game draws in it (flicker, missing text:
  it showed up in 1 of 5 screenshots). The copper list is changed only after line 8 of the frame: the copper reads it at the top.
- **Copper scroll:** the play area (lines `TOP` and below) is shown shifted by `video_scroll(d)` = `formDx`. Each bitmap has its own copper list (`build_copper`): the hud lines use pointers at `bitmap + GUARD/8 - 2`, a `WAIT` at the end of line `TOP - 1` (horizontal 0xd9) sets the pointers again for the play area, `BPLCON1` = `(d & 15) * 0x11` and the pointers `- 2 * (d >> 4)` bytes. The fetch starts one word early (`DDFSTRT 0x30`, 21 words a line, the first one hidden). Everything below the hud is drawn at `x - d` (`SX` in `main.c`, `video_text`), so a formation alien stays still in the bitmap. Text is drawn at any pixel (`text_shifted`; `text_aligned` is the fast path when x is a multiple of 8). The lives are in the hud (the bottom is scrolled). Checked: the pictures are the same as without the scroll at 8 times (a git worktree of the commit before, `HALT` 300 .. 2600).
- **Bitmaps:** `NPL` = 5 interleaved bitplanes, 32 colours (a line = plane 0 .. 4 rows), so one blit draws a sprite in all planes
  (the height is `NPL` x the lines, the modulo is 56 - 2 x the width). The bitmap is 448 pixels wide (64 pixels of guard each side), so sprites need no
  clipping at the sides. Sprite data has one extra zero word on the right (the blitter shifts into it). A cookie-cut blit is
  minterm 0xca (A = mask, B = picture, C = screen).
- **PAL:** `DIWSTRT 0x2c81`, `DIWSTOP 0x2cc1` = 320 x 256 lines. The play area is C64 x 24..343, y 50..249 = screen x 0..319,
  y 28..227 (`SX`, `SY` in `main.c`); the hud is above it.
- **Paula:** a sample plays again and again. For a sample that plays once, set the pointer to a silent word after the DMA has
  started (`sfx` in `audio.c`). Minimum period 124. Not heard, only read.
- **Keyboard:** CIA-A serial port, level 2 interrupt (`kbd` in `hw.s`). The key code is `~(sdr rotated right by 1)`, bit 7 = release.
  Acknowledge it with a pulse of about 85 microseconds on bit 6 of CRA.
- **Speed:** all RAM is chip RAM and the screen DMA (5 bitplanes) takes most of its cycles: the 68000 runs at about 0.5 million
  instructions a second, and the blitter needs about 0.85 ms for a sprite and 0.35 ms to clear one. A tick of the game is 20 ms (its CPU cost 4-6 ms), so one tick
  and one picture must stay far below 20 ms. What is done about it:
  the stars are hardware sprites 4 and 5 (the CPU needed 25 ms for 24 star pixels); the hud is a static layer (`video_static_begin`, drawn again
  only when a number changes); a sprite that did not move is not drawn again, unless something is cleared or drawn over it (`draw_sprites`:
  slots, and a grid of 16 x 16 cells; `-DNOSKIP` draws everything, and the picture must be the same: compare the two at many `HALT` values);
  all CPU work in `draw_sprites` is kept small (no copies, no `%`); three bitmaps so the loop never waits; `game.o` is built with `-O2`;
  the formation slots are a table. The game catches up with up to 6 ticks a loop, so its speed is right (about 97 % in a busy autoplay run).
  Measure with `-DPROFILE -DHALT=900 -DAUTOPLAY -DTITLE_HOLD=0`: when the game stops it shows `LOOPS n Vm` = the loops of the main loop and
  the vertical blanks that 900 ticks needed (900 loops = 50 pictures a second; 400 = about 22). A busy autoplay run gives about 400: the
  formation moves 28 sprites at once every 9 ticks, and a 25 ms picture follows (now the copper scroll does the sway: while the aliens fly in and sway, 177 loops instead of 145 for 300 ticks; the other scenes are the same). Text is slow too (a line of 20 characters is about
  20 ms with the CPU): keep text out of the frames, do not print numbers every frame.
- **Where the time goes** (`-DPROFILE` also shows `T` = beam lines/16 that the ticks needed and `D` = the pictures): the game ticks alone keep 50 pictures a second; a picture with 30 moving aliens needs 20-25 ms, a still formation 6 ms. The blitter is not the whole story: with the blits switched off a busy scene reaches only 80 %. Tried and not kept: a copy blit (B to D, 2 channels) instead of the cookie cut for sprites that are alone in their cells: no faster. Text is slow because the CPU gets few chip RAM cycles (about 20 ms for 20 characters); a cache of unchanged text, or cells made in advance, would help the intro and result screens.
- **Where the time goes (2026-10, measured with `-DPROFILE -DPROFILE2 -DAUTOPLAY -DTITLE_HOLD=0 -DHALT=n [-DPROF_FROM=m]`)**: a tick of the game is 20 ms (one per vertical blank); its CPU cost is 4-6 ms. The 68000 gets about 0.6 million instructions a second: one unchanged sprite slot costs about 10 us even in assembly, a moving sprite about 1.4 ms (clear + cookie-cut, the blitter is the limit: it gets about 40 % of the chip bus cycles with 5 planes). A busy scene has 6-10 moving sprites a picture, so it misses the 50 fps beat in 1 of 4 pictures. 4 bitplanes would give about +20-27 % (tested with `make NPL=4`; rejected: 16 colours). `PROFILE2` also shows the loops that took 1, 2, 3 vertical blanks and the number of sprites that changed in a picture.
- **fast.s** (assembly, with the same code in C under `-DNOASM`): `stars_layer`, `alien_wants` (main.c), and the sprite passes of `draw_sprites`: `sprites_scan` (which slots changed; a `Place` has everything the blitter needs, computed once; a slot has two places, the new and the old one), `sprites_mark` (the 16 x 16 cells; a kept sprite in a marked cell is drawn again; quick test with the marked rows and columns), `sprites_clear`, `sprites_blit` (in slot order: later slots are in front). The struct offsets are checked by `_Static_assert`s in video.c and main.c. Text and the hud use the blitter too: every character is a sprite (`glyph_list` in tools/gen_assets.py); the hud draws a part again in a bitmap only when its value changed (`video_hud`).
- **16-bit friendly code:** a 32-bit `*` and `/` call libgcc (slow on a 68000). The scripted-game hash uses rotate / xor / add for this reason.

## vAmigaWeb (the test emulator)

- `https://vamigaweb.github.io/#AROS=true#navbar=hidden#<url of an ADF, ADZ>`: boots with its AROS ROM, no copyrighted ROM.
  `warpto=N#` in front of the link runs the first N frames at full speed (`tests/vamiga.py` uses it: the tests take seconds).
- Playwright answers the request for the ADF itself (`context.route`, service workers blocked), so no server and no CORS problem.
- The AROS boot takes about 30 s of real time. Without warp the floppy is loaded at normal speed, so wait long.
- The emulator canvas can be read only in a `requestAnimationFrame` callback that is registered after the emulator started
  (`tools/make_gif.py`). 4 canvas pixels are one Amiga pixel across, 2 are one down.
- The game freezes with `-DHALT=n`, so a screenshot is exact. Grey screen = the game did not start (a crash in the boot, or too early).

## Conventions

- Code that mirrors `game.c` is not changed here: change `psp/game.c` instead. Comments explain why and are short.
- README text is written in Simplified Technical English. Keep commits small. Do not push without asking.
