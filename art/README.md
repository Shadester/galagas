# The creatures of the PSP and Amiga versions

The aliens, the fighter and the explosions of the **PSP** (32 x 32), the **Amiga OCS** (24 x 24, 32 colours) and the **Amiga AGA** (24 x 24, 64 colours) are drawn by hand, as scripts. They are our own art: the shapes are
in the spirit of the arcade game (a bee, a butterfly, a boss with horns, a white fighter), nothing is copied from the arcade sprites. The other ports (C64, Lynx, Thumby, PICO-8, the terminal) still use the 16 x 16 art of `psp/art.h` for the creatures. Their explosions come from here too: `explode.py` also writes them at 16 and 12 pixels (`xa.16.txt`, `xa.12.txt`, `xp.16.txt`, `xp.12.txt`) for the terminal, the Lynx portrait, Thumby and PICO-8; `c64/tools/gen_expl.py` makes the C64 sprites (and so the Lynx landscape sprites) from the 24 pixel files.

```
art/master/bee.py, bfly.py, boss.py, ship.py                the drawings (shapes with lit tones and outlines, light from the upper left)
art/master/explode.py                                      the explosions: scattered single pixels like the arcade burst (an alien: 5 steps, the fighter: 6), no solid blob; seeded, so the same every run
art/master/NAME.txt, NAME.24.txt, NAME.16.txt              what the scripts write: the same drawing at 32, 24 and 16 pixels (commit them: the generators read these)
tools/sprites/paint.py                                     the painter: ellipses, polygons, lines in a design space of 32 units; the pixels are made at the size you ask for
tools/sprites/master.py                                    reads a master file (digits 0 .. 6 = the tones of the main colour, h .. n = the second colour, y w C K ... = fixed colours)
tools/sprites/reduce.py                                    the OCS palette has 4 tones for each colour, the AGA palette 7: `to_ocs`
tools/sprites/preview.py NAME [out.png]                    a sheet: the 32 px master, the 24 px AGA and OCS drawings, and the real size
```

After a change in a script: `python3 art/master/NAME.py`, then `python3 tools/sprites/preview.py NAME`, then regenerate what uses it:

```sh
python3 psp/tools/gen_art32.py         # psp/art32.h (then make in psp/)
python3 amiga/tools/gen_assets.py      # amiga/src/assets.h (then make in amiga/; the AGA data is built by make: build/aga.bin)
```

The colours are in one place, `amiga/tools/art.py` (the palette and the 7 tones of each of the four colours). The fighter is a hardware sprite on the Amiga: it may only use the tones 1, 3, 5 of blue and red, the greys, white, cyan and yellow
(palette entries 17 .. 31), see the notes at the top of `art/master/ship.py`.
