# galaga for the terminal (Rust)

Rust, one crate (`crossterm`). `README.md` has the controls, options and commands.
The rules (`src/game.rs`) are a translation of `../psp/game.c` (the arcade rules, 40 aliens), with the same names and order.
A change in `psp/game.c` needs the same change in `game.rs`: `tests/test_lockstep.py` compares the state after every tick with the C reference
(it builds `../thumby/tests/c_trace.c` and runs `examples/trace.rs`) and shows the first field that differs.
Two fields: the C64's landscape (320 x 200, `Game::new`) and the arcade's portrait (`Game::with_field(hi, true)`, the default of the program; C: `-DRULES_PORTRAIT`).
The numbers of a field are `game::Geo` (the G_* macros of `psp/game.h`, in lower case): never write a field number as a literal in `game.rs`. The 4 arcade tables
that differ are in `Game.arc`; `tools/gen_arcade_rs.py` makes `src/arcade_data_portrait.rs`. The lockstep test runs every scenario in both fields (`p_...`).
The renderer takes a `render::Field` (from `Geo`): sizes, origin and the 16 / 24 pixel sprite box. The web page (`web_init(.., portrait)`; the page plays the portrait field unless `?landscape`) and the oscilloscope (`scope.rs`: the `Pen` maps the field into the square box,
and scales the drawings that are made for 24 pixel sprites by `sprite / 24` around the centre of each object) have both fields.

## Build, run, test

```sh
cargo run --release -- --autoplay
python3 tests/test_lockstep.py 30000          # 8 scenarios, every tick equal to the C reference
python3 tests/test_terminal.py                # pseudo-terminal checks
cargo test --release
```

- The generated files are committed (`src/arcade_data.rs`, `src/art.rs`): run `tools/gen_arcade_rs.py` when `../psp/arcade_data.h` changes.
- To look at the screen without a terminal window, run the binary in a pseudo-terminal, read it with `pyte` and draw the cells (`tools/make_gif.py`
  has the code). A pseudo-terminal child that you kill must have its master closed first (`os.close(fd)`), or the kill does not end it.
- The browser version: `src/web.rs` has plain `extern "C"` exports (no wasm-bindgen), `tools/build_web.sh` builds `docs/tui/galaga.wasm` (committed), `docs/tui/index.html`
  draws the cells on a canvas. Build the library with `--no-default-features` (the feature `terminal` is `crossterm`). `tests/test_web.py` needs playwright
  (the scratchpad venv has it). The page picks the biggest cells (up to 12 x 24 CSS pixels) that still give the biggest picture (160 x 52 cells).
  After a change of the rules or the renderer: `tools/build_web.sh`, run the tests, commit `docs/tui/galaga.wasm` too.
- The oscilloscope version (`../scope`, page `docs/scope/index.html`) uses the same wasm file: `build_web.sh` copies it to `docs/scope/galaga.wasm` (committed). `src/scope.rs` makes the line segments
  (`web_lines`), `tests/test_scope.py` checks the page. The vector outlines follow the sprites; keep a frame under `scope::BUDGET` segments (a test checks it).
- `examples/octants_ppm.rs` writes a frame of the octant mode as a PPM (to see the colour clash without a terminal).
- Never push without the user's OK (global rule).

## How it works

- 50 ticks a second (`TICK_HZ`), a fixed step in `main.rs`; the screen is drawn at most every 33 ms, and only the cells that changed are written (`term.rs`).
- The play area is 320 x 200 game pixels (C64 sprite coordinates, x 24..343, y 50..249). `render::layout` picks the scale k (2, 3 or 4 game pixels for
  a canvas pixel) that fits the window; two canvas pixels are one cell (the half block `▀`: upper = foreground, lower = background).
- Sprites are the 16 x 16 art of `psp/art.h` (the colour letters), reduced to the size of the canvas with a box filter and cached for each size.
- Pixel mode (kitty, Ghostty; the default there; `--pixels`): the canvas goes out as an image of the kitty graphics protocol (`term::present_image`: 24 bit, zlib
  with `miniz_oxide`, base64). Each frame is a new image, id 1 and 2 in turn, and the old one is deleted after it is shown (the same id flashes). The play area cells
  are `clear` (default background: the image shows through; the boxes of the messages have a colour and cover it); `z` is under the cell backgrounds. All images are
  deleted on exit, on a resize and on a panic. `pixel_layout` picks the scale in steps of 1/12 (`PIXEL_MIN`..`PIXEL_MAX`) so the picture fills the window; the sprites are
  whole multiples of the 16 x 16 art, the positions follow the scale. `main.rs` falls back: pixels, octants, half blocks (a window too small, no cell size from the terminal).
- Octant mode (`--octants`): a cell is 2 x 4 canvas pixels (the octant characters of Unicode 16, `src/octant.rs` from
  `tools/gen_octants.py`). `Layout` has a scale `num / den` (canvas pixels for a game pixel; `px()` rounds towards zero, `pxf()` down); half blocks are 1 / k,
  `octant_layout` takes the biggest of `OCTANT_SCALES` that fits. `octant_cell` reduces the 8 pixels of a cell to 2 colours (the best pair of its own colours).
  Any change in `render.rs` must leave the half-block frames byte for byte the same (hash the cells of a game before and after: the web page uses them).
- Keys: a terminal gives no key release without the kitty keyboard protocol. `input.rs` uses the releases when the terminal has the protocol
  (`supports_keyboard_enhancement`), else a hold time (`HOLD_FIRST`, `HOLD_REPEAT`). Fire is a pulse of one tick for each press or repeat.
- The terminal is restored on exit and on a panic (`term::restore`, the panic hook). `crossterm` asks the terminal about the keyboard protocol at
  start-up and waits for the answer: a terminal that does not answer delays the start by about 2 seconds.

## Conventions

- Comments explain why and are short. README text is in Simplified Technical English. Keep commits small. Do not push without asking.
