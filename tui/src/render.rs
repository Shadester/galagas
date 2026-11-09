//! Drawing: the game state becomes a grid of terminal cells. The play area is a canvas of pixels (320 x 200 game pixels divided by the
//! scale k), two canvas pixels in one cell: the half block "▀" has the upper pixel as its colour and the lower one as its background.
//! In the pixel mode (a terminal with the kitty graphics protocol) the canvas is bigger and is not made into cells: `term.rs` sends it as
//! an image, and the cells of the play area are clear (the image shows through). The sprites are whole multiples of the 16 x 16 art.
//! In the octant mode (Unicode 16) a cell is 2 x 4 canvas pixels, drawn with the octant block characters: 4 times the
//! pixels of the half blocks. A cell has two colours only, so the colours of its 8 pixels are reduced to the best two (`octant_cell`).
//! Text (HUD, messages) is put on the cells afterwards. No terminal code here: `term.rs` writes the cells.
use crate::art::*;
use crate::game::*;
use crate::octant::OCTANT;
use std::collections::HashMap;

pub type Rgb = [u8; 3];

#[derive(Clone, Copy, PartialEq)]
pub struct Cell {
    pub ch: char,
    pub fg: Rgb,
    pub bg: Rgb,
    pub clear: bool, // the default background: an image under the cell shows through
}

pub const BLANK: Cell = Cell { ch: ' ', fg: [255, 255, 255], bg: [0, 0, 0], clear: false };

/// The cells of the whole window.
pub struct Frame {
    pub cols: usize,
    pub rows: usize,
    pub cells: Vec<Cell>,
}

impl Frame {
    pub fn new(cols: usize, rows: usize) -> Frame {
        Frame { cols, rows, cells: vec![BLANK; cols * rows] }
    }

    /// Put text at a cell (the background stays, unless `bg` is given).
    pub fn text(&mut self, col: i32, row: i32, s: &str, fg: Rgb, bg: Option<Rgb>) {
        if row < 0 || row as usize >= self.rows {
            return;
        }
        for (i, ch) in s.chars().enumerate() {
            let c = col + i as i32;
            if c < 0 || c as usize >= self.cols {
                continue;
            }
            let cell = &mut self.cells[row as usize * self.cols + c as usize];
            cell.ch = ch;
            cell.fg = fg;
            if let Some(b) = bg {
                cell.bg = b;
                cell.clear = false;
            }
        }
    }

    pub fn ctext(&mut self, row: i32, s: &str, fg: Rgb, bg: Option<Rgb>) {
        let col = (self.cols as i32 - s.chars().count() as i32) / 2;
        self.text(col, row, s, fg, bg);
    }
}

/// Where the play area is, in game coordinates (from the `Geo` of the game): the top left corner, the size, the size of a sprite.
/// The landscape field is the C64's (x 24..343, y 50..249, sprites 24 wide); the portrait field is the arcade's own (x 0..203, y 0..259, sprites 16).
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Field {
    pub x0: i32,
    pub y0: i32,
    pub w: i32,
    pub h: i32,
    pub sprite: i32,
    pub portrait: bool,
}

impl Field {
    pub fn of(geo: &Geo) -> Field {
        Field { x0: geo.x0, y0: geo.y0, w: geo.width, h: geo.height, sprite: geo.sprite, portrait: geo.portrait }
    }
    /// A length of the landscape field (24 pixel sprites) in this field.
    fn sc(&self, v: i32) -> i32 {
        v * self.sprite / 24
    }
}

/// The frame for a window that is too small for the game: a message.
pub fn too_small(field: Field, cols: usize, rows: usize) -> Frame {
    let mut f = Frame::new(cols, rows);
    let (mc, mr) = min_size(field);
    f.ctext((rows / 2) as i32, &format!("Please make the window at least {} x {} (now {} x {})", mc, mr, cols, rows), [255, 255, 255], None);
    f
}

/// Sizes of the smallest window (half blocks, 4 game pixels for a canvas pixel): 80 x 27 cells for the landscape field, 51 x 35 for the portrait.
pub fn min_size(field: Field) -> (usize, usize) {
    let w = (field.w as usize + 3) / 4;
    let h = ((field.h as usize + 3) / 4 + 1) & !1;
    (w, h / 2 + HUD_ROWS)
}

/// How the play area fits the window: `num / den` canvas pixels for one game pixel (half blocks: 1 / k with k = 2, 3, 4).
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Layout {
    pub field: Field,
    pub k: i32,
    pub num: i32,
    pub den: i32,
    pub octant: bool, // cells of 2 x 4 pixels (octant characters), not 1 x 2 (half blocks)
    pub pixels: bool, // the canvas goes out as an image (kitty graphics protocol), not as cells
    pub w: usize,     // canvas width in pixels
    pub h: usize,     // canvas height in pixels (a whole number of cells)
    pub cw: usize,    // the cells the canvas covers
    pub ch: usize,
    pub cell_w: usize, // pixels of a cell: 1 (half blocks: the width is in cells), 2 (octants), or the real size (pixels)
    pub cell_h: usize,
    pub col0: usize,
    pub row0: usize, // the first rows are the HUD
}

impl Layout {
    /// A length in game pixels as canvas pixels (rounded towards zero).
    pub fn px(&self, v: i32) -> i32 {
        v * self.num / self.den
    }
    /// The same, rounded down (a position that can be negative: a sprite that is partly outside).
    fn pxf(&self, v: i32) -> i32 {
        (v * self.num).div_euclid(self.den)
    }
    /// Finer sizes for the thin things (shots, rings, stars) than a half block cell allows.
    fn fine(&self) -> bool {
        self.octant || self.pixels
    }
    /// The row of the window for a canvas pixel row (relative to the first row of the canvas).
    fn row_of(&self, y: i32) -> i32 {
        self.row0 as i32 + y / self.cell_h as i32
    }
}

pub const HUD_ROWS: usize = 2;

/// The smallest scale (the biggest picture) that fits the window, or None when the window is too small.
pub fn layout(field: Field, cols: usize, rows: usize) -> Option<Layout> {
    for k in [2, 3, 4] {
        let w = (field.w as usize + k - 1) / k;
        let h = ((field.h as usize + k - 1) / k + 1) & !1;
        if cols >= w && rows >= h / 2 + HUD_ROWS {
            return Some(Layout { field, k: k as i32, num: 1, den: k as i32, octant: false, pixels: false, w, h, cw: w, ch: h / 2, cell_w: 1, cell_h: 2, col0: (cols - w) / 2, row0: HUD_ROWS });
        }
    }
    None
}

/// The scales of the octant mode (canvas pixels for a game pixel), the biggest first: 3/2 is a canvas of 480 x 300 pixels, 1/2 is 160 x 100.
/// At 4/3 and 2/3 the 16 x 16 art is drawn 2 and 1 times as big, whole pixels; the other scales take it between.
const OCTANT_SCALES: [(i32, i32); 7] = [(3, 2), (4, 3), (7, 6), (1, 1), (5, 6), (2, 3), (1, 2)];

/// The biggest octant layout that fits the window, or None when the window is too small (the same as for the half blocks: `min_size`).
pub fn octant_layout(field: Field, cols: usize, rows: usize) -> Option<Layout> {
    for (num, den) in OCTANT_SCALES {
        let (cw, ch) = (((field.w * num + den - 1) / den + 1) as usize / 2, ((field.h * num + den - 1) / den + 3) as usize / 4);
        if cols >= cw && rows >= ch + HUD_ROWS {
            return Some(Layout { field, k: 0, num, den, octant: true, pixels: false, w: cw * 2, h: ch * 4, cw, ch, cell_w: 2, cell_h: 4, col0: (cols - cw) / 2, row0: HUD_ROWS });
        }
    }
    None
}

/// The scale of the pixel mode goes in steps of 1/12 canvas pixel for a game pixel: from 4/3 (the art twice as big, a canvas of 427 x 267) to 20/3 (up to 2133 x 1333).
const PIXEL_DEN: i32 = 12;
const PIXEL_MAX: i32 = 80;
/// The biggest canvas of the pixel mode (2133 x 1333 pixels): a frame must be drawn and compressed in about 30 ms.
const PIXEL_AREA: i32 = 2133 * 1333;

/// The biggest pixel layout for a window of `cols` x `rows` cells of `cell_w` x `cell_h` pixels, or None when even the smallest does not fit
/// (then use `octant_layout` or `layout`). The steps are small, so the picture nearly fills the window.
pub fn pixel_layout(field: Field, cols: usize, rows: usize, cell_w: usize, cell_h: usize) -> Option<Layout> {
    if cell_w == 0 || cell_h == 0 {
        return None;
    }
    let min = (32 * PIXEL_DEN + field.sprite - 1) / field.sprite; // the smallest scale: a sprite is 2 x its art (32 pixels)
    for num in (min..=PIXEL_MAX).rev() {
        let (w, h) = ((field.w * num / PIXEL_DEN) as usize, (field.h * num / PIXEL_DEN) as usize);
        if w as i32 * h as i32 > PIXEL_AREA {
            continue;
        }
        let (cw, ch) = ((w + cell_w - 1) / cell_w, (h + cell_h - 1) / cell_h);
        if cols >= cw && rows >= ch + HUD_ROWS {
            return Some(Layout { field, k: 0, num, den: PIXEL_DEN, octant: false, pixels: true, w, h, cw, ch, cell_w, cell_h, col0: (cols - cw) / 2, row0: HUD_ROWS });
        }
    }
    None
}

pub struct Canvas {
    pub w: usize,
    pub h: usize,
    pub px: Vec<Rgb>,
}

impl Canvas {
    fn new(w: usize, h: usize) -> Canvas {
        Canvas { w, h, px: vec![[0, 0, 0]; w * h] }
    }
    fn set(&mut self, x: i32, y: i32, c: Rgb) {
        if x >= 0 && y >= 0 && (x as usize) < self.w && (y as usize) < self.h {
            self.px[y as usize * self.w + x as usize] = c;
        }
    }
    fn rect(&mut self, x: i32, y: i32, w: i32, h: i32, c: Rgb) {
        for yy in y..y + h {
            for xx in x..x + w {
                self.set(xx, yy, c);
            }
        }
    }
}

// ---- sprites: our own 16 x 16 art (art.rs), reduced to the size of the canvas ----
type Variant = [Rgb; 3];
const V_BEE: Variant = [[70, 130, 255], [150, 200, 255], [30, 60, 190]];
const V_BFLY: Variant = [[255, 60, 60], [255, 150, 130], [160, 20, 40]];
const V_BOSS: Variant = [[60, 220, 90], [170, 255, 160], [20, 130, 50]];
const V_BOSSP: Variant = [[170, 80, 255], [215, 165, 255], [100, 40, 170]];

fn letter_color(ch: u8, v: &Variant) -> Option<Rgb> {
    Some(match ch {
        b'm' => v[0],
        b'M' => v[1],
        b'n' => v[2],
        b'y' => [255, 220, 60],
        b'Y' => [200, 140, 20],
        b'c' => [80, 230, 255],
        b'w' => [255, 255, 255],
        b'k' => [25, 25, 50],
        b'o' => [255, 140, 30],
        b'r' => [255, 60, 60],
        b'b' => [60, 110, 255],
        b'g' => [170, 170, 190],
        _ => return None,
    })
}

/// A picture from the art rows (the left half only): reduced to `size` (even) pixels wide and as high as the art's rows need (all 16 rows without `crop`). The left half is reduced
/// and mirrored, so the picture is symmetric. An output pixel is clear when less than half of its source pixels are opaque; else it takes the colour
/// that is most frequent among them, a detail colour (yellow, cyan, white, orange, red) counting double, so that an antenna or an eye does not go grey.
/// Returns (pixels, width, height).
fn scale_art(rows: &[&str; 16], v: &Variant, size: usize, crop: bool) -> (Vec<Option<Rgb>>, usize, usize) {
    let used: Vec<usize> = (0..16).filter(|&y| rows[y].bytes().any(|c| c != b'.')).collect();
    let (y0, y1) = if crop { (used[0], used[used.len() - 1] + 1) } else { (0, 16) };
    let h = ((y1 - y0) * size + 8) / 16;
    let h = h.max(2);
    let half = size / 2;
    let mut out = vec![None; size * h];
    for ty in 0..h {
        let sy0 = y0 + ty * (y1 - y0) / h;
        let sy1 = (y0 + (ty + 1) * (y1 - y0) / h).max(sy0 + 1);
        for tx in 0..half {
            let sx0 = tx * 8 / half;
            let sx1 = ((tx + 1) * 8 / half).max(sx0 + 1);
            let mut tally: Vec<(u8, u32)> = Vec::new();
            let (mut n, mut opaque) = (0u32, 0u32);
            for sy in sy0..sy1 {
                for sx in sx0..sx1 {
                    n += 1;
                    let ch = rows[sy].as_bytes()[sx];
                    if letter_color(ch, v).is_some() {
                        opaque += 1;
                        let w = if b"ywcroY".contains(&ch) { 2 } else { 1 };
                        match tally.iter_mut().find(|t| t.0 == ch) {
                            Some(t) => t.1 += w,
                            None => tally.push((ch, w)),
                        }
                    }
                }
            }
            if n > 0 && opaque * 2 >= n {
                let best = tally.iter().max_by_key(|t| t.1).unwrap().0;
                let c = letter_color(best, v);
                out[ty * size + tx] = c;
                out[ty * size + size - 1 - tx] = c;
            }
        }
    }
    (out, size, h)
}

/// A burst (single pixels, 16 x 16 letters): a pixel of the picture is lit when any source pixel in its box is, so the dots do not vanish at a small scale.
fn scale_burst(rows: &[&str; 16], v: &Variant, size: usize) -> (Vec<Option<Rgb>>, usize, usize) {
    let mut out = vec![None; size * size];
    for ty in 0..size {
        let (sy0, sy1) = (ty * 16 / size, ((ty + 1) * 16 / size).max(ty * 16 / size + 1));
        for tx in 0..size {
            let (sx0, sx1) = (tx * 16 / size, ((tx + 1) * 16 / size).max(tx * 16 / size + 1));
            let mut best: Option<u8> = None;
            for sy in sy0..sy1 {
                for sx in sx0..sx1 {
                    let ch = rows[sy].as_bytes()[sx];
                    if letter_color(ch, v).is_some() && (best.is_none() || ch == b'w' || ch == b'y') {
                        best = Some(ch);
                    }
                }
            }
            out[ty * size + tx] = best.and_then(|ch| letter_color(ch, v));
        }
    }
    (out, size, size)
}

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
enum Spr {
    Bee(usize),
    Bfly(usize),
    Boss(usize),
    BossP(usize),
    Player,
    Xa(usize),
    Xp(usize),
}

fn art_of(s: Spr) -> (&'static [&'static str; 16], &'static Variant) {
    match s {
        Spr::Bee(f) => (if f == 0 { &ART_BEE_A } else { &ART_BEE_B }, &V_BEE),
        Spr::Bfly(f) => (if f == 0 { &ART_BFLY_A } else { &ART_BFLY_B }, &V_BFLY),
        Spr::Boss(f) => (if f == 0 { &ART_BOSS_A } else { &ART_BOSS_B }, &V_BOSS),
        Spr::BossP(f) => (if f == 0 { &ART_BOSS_A } else { &ART_BOSS_B }, &V_BOSSP),
        Spr::Player => (&ART_PLAYER, &V_BEE),
        Spr::Xa(f) => ([&ARTF_XA0, &ARTF_XA1, &ARTF_XA2, &ARTF_XA3, &ARTF_XA4][f], &V_BEE),
        Spr::Xp(f) => ([&ARTF_XP0, &ARTF_XP1, &ARTF_XP2, &ARTF_XP3, &ARTF_XP4, &ARTF_XP5][f], &V_BEE),
    }
}

/// The renderer: the scale, the sprites reduced to it, and the little state a picture needs.
pub struct Renderer {
    pub layout: Layout,
    cache: HashMap<(Spr, usize, bool), (Vec<Option<Rgb>>, usize, usize)>,
}

impl Renderer {
    pub fn new(layout: Layout) -> Renderer {
        Renderer { layout, cache: HashMap::new() }
    }

    /// Draw a sprite `gsize` game pixels wide with its centre at the game coordinates (cx, cy).
    fn sprite(&mut self, cv: &mut Canvas, s: Spr, cx: i32, cy: i32, gsize: i32) {
        let l = self.layout;
        let exact = ((gsize * l.num + l.den / 2) / l.den).max(4) as usize & !1; // even (rounded down): the picture is symmetric about its middle
        let size = if l.pixels {
            // a whole multiple of the 16 x 16 art: sharp pixels, unless that is more than a tenth off (then the nearest pixels of the art)
            let m = ((l.px(gsize) as usize + 8) / 16 * 16).max(16);
            if m.abs_diff(exact) * 10 <= exact { m } else { exact }
        } else {
            exact
        };
        let crop = !l.field.portrait; // the portrait field: the whole 16 x 16 art is the sprite box, and it is placed by its corner
        let (pic, w, h) = self.cache.entry((s, size, crop)).or_insert_with(|| {
            let (rows, v) = art_of(s);
            if matches!(s, Spr::Xa(_) | Spr::Xp(_)) { scale_burst(rows, v, size) } else { scale_art(rows, v, size, crop) }
        });
        let (w, h) = (*w, *h);
        let x0 = l.pxf(cx - l.field.x0) - w as i32 / 2;
        let y0 = l.pxf(cy - l.field.y0) - h as i32 / 2;
        for ty in 0..h {
            for tx in 0..w {
                if let Some(c) = pic[ty * w + tx] {
                    cv.set(x0 + tx as i32, y0 + ty as i32, c);
                }
            }
        }
    }

    fn fighter(&mut self, cv: &mut Canvas, x: i32, y: i32) {
        let f = self.layout.field;
        self.sprite(cv, Spr::Player, x + f.sprite / 2, y + if f.portrait { f.sprite / 2 } else { 7 }, f.sprite);
    }

    fn stars(&self, cv: &mut Canvas, frame: i32) {
        let l = self.layout;
        let sz = l.px(1).max(1);
        for i in 0..70u32 {
            let h = i.wrapping_mul(2654435761);
            let layer = if i < 8 { 0 } else if i < 24 { 1 } else if i < 48 { 2 } else { 3 };
            let speed = [100, 60, 40, 25][layer]; // 1/100 game pixel a tick
            let x = l.px(((h >> 8) % l.field.w as u32) as i32);
            let y = l.px((((h >> 20) % l.field.h as u32) as i32 * 100 + frame * speed) % (l.field.h * 100) / 100);
            let b = [230u32, 180, 130, 90][layer];
            let tw = 70 + ((frame as u32 / 6 + i * 7) % 4) * 10; // twinkle
            let v = (b * tw / 100) as u8;
            let v34 = (v as u16 * 3 / 4) as u8;
            let col = if i % 5 == 0 { [v, v34, v / 3] } else if i % 7 == 0 { [v / 2, v34, v] } else { [v, v, v] };
            cv.rect(x, y, sz, sz, col);
        }
    }

    /// The tractor beam: a cone of thin rings (a ring every 2 canvas pixels), bowed near the boss, the ends curled up, teal -> cyan -> blue, and a bright ring that runs down it.
    fn beam(&self, cv: &mut Canvas, g: &Game) {
        let b = &g.al[g.cap_boss as usize];
        let n = if g.cap == C_BEAM { g.beam_len } else { 4 };
        let l = self.layout;
        let gap = if l.fine() { 4 } else { 2 * l.k }; // game pixels between the rings (2 canvas pixels in half blocks)
        let unit = if l.fine() { l.px(2).max(1) } else { 1 }; // thickness of a ring, and how far its ends curl
        let rings = n * 8 / gap;
        for i in 0..rings {
            let gy = i * gap; // game pixels below the top of the beam
            let hw = l.px(l.field.sc((2 * 4 + 4) + gy / 2)); // 12 game pixels at the top, 32 at the bottom (4 rows); the portrait field is 2/3 of it
            let lit = (i - (g.frame >> 2)).rem_euclid(4) == 0;
            let t = (i * 100 / (4 * 8 / gap).max(1)).min(100);
            let c: Rgb = if lit { [210, 255, 255] } else { [(60 + t / 5) as u8, (215 - t) as u8, 255] };
            let y = l.px(b.y + l.field.sc(14) + gy - l.field.y0);
            let cx = l.px(b.x + l.field.sprite / 2 - l.field.x0);
            for x in (cx - hw)..(cx + hw) {
                // 2 hw pixels, like the (even) picture of the boss: the middle is between the pixels cx - 1 and cx, so the ring is symmetric about the boss
                let ends = (2 * (x - cx) + 1).abs() > hw; // the outer half of a ring
                let end = x == cx - hw || x == cx + hw - 1;
                let dy = if i < 3 && ends { unit } else { 0 } - if end { unit } else { 0 }; // the first rings bow down at the ends, every ring curls up at its ends
                cv.rect(x, y + dy, 1, unit, c);
            }
        }
    }

    /// The picture of the play area for the state of the game.
    fn draw_world(&mut self, cv: &mut Canvas, g: &Game) {
        let l = self.layout;
        let f = l.field;
        // the background: a dark blue that gets darker towards the bottom
        for y in 0..cv.h {
            let t = y as u32 * 255 / cv.h as u32;
            let c = [(6 - 6 * t / 255) as u8, (8 - 8 * t / 255) as u8, (30 - 24 * t / 255) as u8];
            for x in 0..cv.w {
                cv.px[y * cv.w + x] = c;
            }
        }
        self.stars(cv, g.frame);
        if g.state == S_TITLE {
            title_logo(cv);
            return;
        }
        if (g.cap == C_BEAM && g.beam_len > 0) || g.cap == C_PULL {
            self.beam(cv, g);
        }
        let flap = ((g.frame >> 4) & 1) as usize;
        for i in 0..NAL {
            let a = &g.al[i];
            if a.st == A_DEAD || (a.st == A_ENTER && a.ent == 0) {
                continue;
            }
            let (cx, cy) = (a.x + f.sprite / 2, a.y + if f.portrait { f.sprite / 2 } else { 6 });
            if a.st == A_EXPLODE {
                let step = ((G_EXPL_TICKS - a.timer) >> 2).clamp(0, 4) as usize;
                self.sprite(cv, Spr::Xa(step), cx, cy, f.sc(36));
                continue;
            }
            let s = match a.typ {
                T_BOSS => {
                    if a.hp == 1 && g.challenge == 0 { Spr::BossP(flap) } else { Spr::Boss(flap) }
                }
                T_BUTTERFLY => Spr::Bfly(flap),
                _ => Spr::Bee(flap),
            };
            self.sprite(cv, s, cx, cy, f.sc(if a.typ == T_BOSS { 26 } else { 24 }));
            if a.typ == T_BOSS && g.cap == C_CARRY && g.cap_boss == i as i32 && a.y - g.geo.capt_dy >= f.y0 - f.sprite - 10 {
                self.fighter(cv, a.x, a.y - g.geo.capt_dy);
            }
        }
        for b in g.ps.iter().filter(|b| b.act != 0) {
            // the shot starts above the ship: its x is the ship's centre, its y the ship's top (landscape: 6 below the shot's y, and 3 above its top)
            let (x, y) = (l.px(b.x + f.sprite / 2 - g.geo.shot_dx - f.x0), l.px(b.y + if f.portrait { 0 } else { 6 } - f.y0));
            cv.rect(x, y - if f.portrait { 0 } else { l.px(3) }, l.px(2).max(1), l.px(12).max(2), [220, 250, 255]);
        }
        for b in g.eb.iter().filter(|b| b.act != 0) {
            let (x, y) = (l.px(b.x + f.sprite / 2 - f.x0), l.px(b.y + if f.portrait { 0 } else { 4 } - f.y0));
            cv.rect(x, y - l.px(4).max(2), l.px(4).max(1), l.px(10).max(2), [255, 150, 120]);
            let d = if l.fine() { l.px(2).max(1) } else { 1 };
            cv.rect(x, y, d, d, [255, 240, 160]);
        }
        // the ship
        let show = matches!(g.state, S_INTRO | S_PLAY | S_RESULT | S_CAPTURED);
        if g.state == S_DYING && g.dying_quiet == 0 {
            let step = ((G_DIE_TICKS - g.state_timer) >> 3).max(0) as usize;
            if step < 6 {
                self.sprite(cv, Spr::Xp(step), g.px + f.sprite / 2 + if g.dual != 0 { g.geo.dual_dx / 2 } else { 0 }, g.py + if f.portrait { f.sprite / 2 } else { 7 }, f.sc(56));
            }
        } else if show && !(g.state == S_PLAY && (g.invuln & 4) != 0) {
            self.fighter(cv, g.px, g.py);
            if g.dual != 0 {
                self.fighter(cv, g.px + g.geo.dual_dx, g.py);
            }
            if g.cap == C_RESCUE {
                self.fighter(cv, g.rx, g.ry);
            }
        }
    }

    /// Draw the whole window: the play area, the HUD, the messages of the state.
    pub fn draw(&mut self, g: &Game, cols: usize, rows: usize) -> Frame {
        self.draw_with_canvas(g, cols, rows).0
    }

    /// The window as cells, and the canvas. In the pixel mode the cells of the play area are clear, and the canvas is the image to put there.
    pub fn draw_with_canvas(&mut self, g: &Game, cols: usize, rows: usize) -> (Frame, Canvas) {
        let l = self.layout;
        let mut cv = Canvas::new(l.w, l.h);
        self.draw_world(&mut cv, g);
        let mut f = Frame::new(cols, rows);
        if l.pixels {
            for cy in 0..l.ch {
                for cx in 0..l.cw {
                    f.cells[(l.row0 + cy) * cols + l.col0 + cx].clear = true;
                }
            }
        } else if l.octant {
            for cy in 0..l.ch {
                for cx in 0..l.cw {
                    let at = |i: usize| cv.px[(4 * cy + i / 2) * l.w + 2 * cx + i % 2];
                    let (ch, fg, bg) = octant_cell([at(0), at(1), at(2), at(3), at(4), at(5), at(6), at(7)]);
                    f.cells[(l.row0 + cy) * cols + l.col0 + cx] = Cell { ch, fg, bg, clear: false };
                }
            }
        } else {
            for cy in 0..l.h / 2 {
                for cx in 0..l.w {
                    let top = cv.px[(2 * cy) * l.w + cx];
                    let bot = cv.px[(2 * cy + 1) * l.w + cx];
                    f.cells[(l.row0 + cy) * cols + l.col0 + cx] = Cell { ch: '▀', fg: top, bg: bot, clear: false };
                }
            }
        }
        draw_text_layer(&mut f, g, &l);
        (f, cv)
    }
}

fn dist2(a: Rgb, b: Rgb) -> i32 {
    (0..3).map(|i| (a[i] as i32 - b[i] as i32).pow(2)).sum()
}

/// One cell from its 8 pixels (octant n = pixel n - 1: 1 2 / 3 4 / 5 6 / 7 8 in rows): the character, the colour of its set octants and the
/// colour of the others. With 2 colours or less the cell is exact. With more, the pair of the cell's own colours with the least total error
/// is taken and each pixel goes to the nearer one (a colour clash: a sprite edge keeps its shape, and its colours are reduced).
/// The brighter colour is the character's colour, so a cell that changes a little does not change its character.
pub fn octant_cell(px: [Rgb; 8]) -> (char, Rgb, Rgb) {
    let mut cols: Vec<Rgb> = Vec::with_capacity(8);
    for p in px {
        if !cols.contains(&p) {
            cols.push(p);
        }
    }
    if cols.len() == 1 {
        return (' ', cols[0], cols[0]);
    }
    let (mut a, mut b) = (cols[0], cols[1]);
    if cols.len() > 2 {
        let mut best = i32::MAX;
        for i in 0..cols.len() {
            for j in i + 1..cols.len() {
                let err: i32 = px.iter().map(|&p| dist2(p, cols[i]).min(dist2(p, cols[j]))).sum();
                if err < best {
                    best = err;
                    (a, b) = (cols[i], cols[j]);
                }
            }
        }
    }
    let sum = |c: Rgb| c[0] as u32 + c[1] as u32 + c[2] as u32;
    let (fg, bg) = if sum(a) >= sum(b) { (a, b) } else { (b, a) };
    let mut mask = 0usize;
    for (i, &p) in px.iter().enumerate() {
        if dist2(p, fg) <= dist2(p, bg) {
            mask |= 1 << i;
        }
    }
    (OCTANT[mask], fg, bg)
}

/// GALAGA in block letters (our own 5 x 5 letters) across the upper part of the canvas
fn title_logo(cv: &mut Canvas) {
    const G: [&str; 5] = [".###.", "#....", "#.##.", "#...#", ".###."];
    const A: [&str; 5] = [".###.", "#...#", "#####", "#...#", "#...#"];
    const L: [&str; 5] = ["#....", "#....", "#....", "#....", "#####"];
    let word = [G, A, L, A, G, A];
    let ps = (cv.w / 40).max(2) as i32; // the size of one letter pixel
    let total = word.len() as i32 * 6 * ps - ps;
    let (x0, y0) = ((cv.w as i32 - total) / 2, (cv.h as i32) / 8);
    for (n, letter) in word.iter().enumerate() {
        for (ry, row) in letter.iter().enumerate() {
            let t = ry as u32 * 255 / 4;
            let c = [255, (230 - 110 * t / 255) as u8, (70 - 60 * t / 255) as u8];
            for (rx, ch) in row.bytes().enumerate() {
                if ch == b'#' {
                    cv.rect(x0 + (n as i32 * 6 + rx as i32) * ps, y0 + ry as i32 * ps, ps, ps, c);
                }
            }
        }
    }
}

const RED: Rgb = [255, 80, 80];
const WHITE: Rgb = [255, 255, 255];
const YELLOW: Rgb = [255, 220, 60];
const CYAN: Rgb = [80, 230, 255];
const DARK: Rgb = [0, 0, 24];

/// A game row of the C64 screen (0..24, 8 game pixels each; a field of another height has the same 25 rows) as a row of the window.
fn grow(l: &Layout, row: i32) -> i32 {
    l.row_of(l.px((row * 8 + 4) * l.field.h / 200))
}

fn draw_text_layer(f: &mut Frame, g: &Game, l: &Layout) {
    let (c0, w) = (l.col0 as i32, l.cw as i32);
    if g.state != S_TITLE {
        f.text(c0, 0, "SCORE", RED, Some([0, 0, 0]));
        f.text(c0 + w * 3 / 10, 0, "HI-SCORE", RED, Some([0, 0, 0]));
        f.text(c0 + w * 7 / 10, 0, "STAGE", RED, Some([0, 0, 0]));
        f.text(c0 + w * 85 / 100, 0, "LIVES", RED, Some([0, 0, 0]));
        f.text(c0, 1, &format!("{:06}", g.score), WHITE, Some([0, 0, 0]));
        f.text(c0 + w * 3 / 10, 1, &format!("{:06}", g.hi), WHITE, Some([0, 0, 0]));
        f.text(c0 + w * 7 / 10, 1, &format!("{:02}", g.stage), WHITE, Some([0, 0, 0]));
        f.text(c0 + w * 85 / 100, 1, &"▲".repeat(g.lives.clamp(0, 9) as usize), CYAN, Some([0, 0, 0]));
    }
    let mid = l.row0 as i32 + l.ch as i32 / 2;
    match g.state {
        S_TITLE => {
            f.ctext(mid - 4, "T E R M I N A L", CYAN, Some(DARK));
            f.ctext(mid, &format!("HI-SCORE  {:06}", g.hi), WHITE, Some(DARK));
            f.ctext(mid + 4, "PRESS SPACE TO START", YELLOW, Some(DARK));
            if f.cols >= 64 {
                f.ctext(mid + 6, "LEFT / RIGHT or A / D: move   SPACE: fire   P: pause   Q: quit", [170, 170, 190], Some(DARK));
            } else {
                f.ctext(mid + 6, "LEFT / RIGHT or A / D: move   SPACE: fire", [170, 170, 190], Some(DARK));
                f.ctext(mid + 8, "P: pause   Q: quit", [170, 170, 190], Some(DARK));
            }
        }
        S_INTRO => {
            if g.challenge != 0 {
                f.ctext(grow(l, 16), "CHALLENGING STAGE", WHITE, Some(DARK));
            } else {
                f.ctext(grow(l, 16), &format!("STAGE {:02}", g.stage), WHITE, Some(DARK));
            }
        }
        S_READY => f.ctext(grow(l, 20), "READY", WHITE, Some(DARK)),
        S_DYING if g.dying_quiet != 0 => f.ctext(grow(l, 20), "FIGHTER CAPTURED", RED, Some(DARK)),
        S_RESULT => {
            if g.challenge != 0 {
                f.ctext(grow(l, 9), &format!("NUMBER OF HITS  {:3}", g.chal_hits), WHITE, Some(DARK));
                if g.chal_hits == NAL as i32 {
                    f.ctext(grow(l, 11), "PERFECT!", YELLOW, Some(DARK));
                    f.ctext(grow(l, 13), "BONUS 10000", WHITE, Some(DARK));
                }
            } else {
                let ratio = if g.shots > 0 { (g.hits * 100 / g.shots).min(100) } else { 0 };
                f.ctext(grow(l, 9), &format!("SHOTS  {:3}", g.shots), WHITE, Some(DARK));
                f.ctext(grow(l, 11), &format!("HITS   {:3}", g.hits), WHITE, Some(DARK));
                f.ctext(grow(l, 13), &format!("RATIO  {:3}%", ratio), WHITE, Some(DARK));
            }
        }
        S_GAMEOVER => {
            f.ctext(grow(l, 11), "GAME OVER", WHITE, Some(DARK));
            if g.state_timer == 0 {
                f.ctext(grow(l, 14), "PRESS SPACE", WHITE, Some(DARK));
            }
        }
        _ => {}
    }
    if g.paused != 0 {
        f.ctext(grow(l, 20), "PAUSED", WHITE, Some(DARK));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn land() -> Field {
        Field::of(&LANDSCAPE)
    }
    fn port() -> Field {
        Field::of(&PORTRAIT)
    }

    #[test]
    fn layouts() {
        assert_eq!(layout(land(), 79, 40), None);
        assert_eq!(layout(land(), 80, 26), None);
        assert_eq!(layout(land(), 80, 27).unwrap().k, 4);
        assert_eq!(layout(land(), 107, 36).unwrap().k, 3);
        assert_eq!(layout(land(), 160, 52).unwrap().k, 2);
        assert_eq!(layout(land(), 200, 60).unwrap().k, 2);
    }

    #[test]
    fn pixel_layouts() {
        assert_eq!(pixel_layout(land(), 80, 27, 0, 0), None);
        let l = pixel_layout(land(), 160, 52, 10, 20).unwrap(); // 1600 x 1040 pixels: 160 x 50 cells and the HUD rows: the window is filled
        assert_eq!((l.w, l.h, l.cw, l.ch, l.col0, l.row0), (1600, 1000, 160, 50, 0, 2));
        assert!(l.pixels && l.px(24) == 120);
        let l = pixel_layout(land(), 100, 40, 8, 16).unwrap(); // 800 x 640 pixels: the width limits (scale 2.5)
        assert_eq!((l.w, l.h), (800, 500));
        let l = pixel_layout(land(), 60, 30, 8, 16).unwrap(); // 480 x 480 pixels
        assert_eq!((l.w, l.h), (480, 300));
        assert_eq!(pixel_layout(land(), 50, 30, 8, 16), None); // 400 pixels wide: too small
        let l = pixel_layout(land(), 400, 120, 12, 24).unwrap(); // a huge window: the biggest scale
        assert_eq!((l.w, l.h), (2133, 1333));
        for (cols, rows) in [(60, 20), (90, 30), (120, 45), (200, 60), (333, 99)] {
            let l = pixel_layout(land(), cols, rows, 9, 18).unwrap();
            assert!(l.cw <= cols && l.ch + HUD_ROWS <= rows && l.w <= cols * 9 && l.h <= (rows - HUD_ROWS) * 18);
            // the next step does not fit: the picture nearly fills the window
            let more = (l.num + 1) * 320 / PIXEL_DEN;
            assert!(l.num == PIXEL_MAX || more as usize > cols * 9 || ((l.num + 1) * 200 / PIXEL_DEN) as usize > (rows - HUD_ROWS) * 18);
        }
    }

    #[test]
    fn pixel_sprites_are_whole_multiples() {
        // at 4/3 and 2 canvas pixels for a game pixel the art is exactly 2 and 3 times as big; in between a sprite is a whole multiple when
        // that is within a tenth of its size, else the nearest size (the nearest pixels of the art)
        for (cols, rows, cw, ch, exact) in [(43, 16, 10, 20, true), (64, 24, 10, 20, true), (60, 30, 8, 16, false), (100, 40, 8, 16, false), (160, 52, 10, 20, false), (230, 70, 11, 22, false)] {
            let l = pixel_layout(land(), cols, rows, cw, ch).unwrap();
            let mut r = Renderer::new(l);
            let mut cv = Canvas::new(l.w, l.h);
            r.sprite(&mut cv, Spr::Bee(0), 100, 100, 24);
            for gsize in [26, 36, 56] {
                r.sprite(&mut cv, Spr::Xa(1), 100, 100, gsize);
            }
            assert!(!r.cache.is_empty());
            for ((spr, size, _), (_, w, _)) in &r.cache {
                assert!(*w == *size && size % 2 == 0, "size {}", size);
                if exact && matches!(spr, Spr::Bee(_)) {
                    assert!(size % 16 == 0, "size {} at {}/{}", size, l.num, l.den);
                }
            }
        }
    }

    #[test]
    fn draws_all_states_in_pixels() {
        let (cols, rows) = (100, 40);
        let l = pixel_layout(land(), cols, rows, 8, 16).unwrap();
        let mut r = Renderer::new(l);
        let mut g = Game::new(1234);
        let press = Input { fire: true, ..Default::default() };
        g.tick(&press, 0);
        for t in 0..3000 {
            let inp = game_autoplay(&g);
            g.tick(if t == 0 { &press } else { &inp }, 0);
            if t % 97 == 0 {
                let (f, cv) = r.draw_with_canvas(&g, cols, rows);
                assert_eq!((cv.w, cv.h), (l.w, l.h));
                assert!(cv.px.iter().any(|p| *p != [0, 0, 0]));
                // the play area is clear for the image (but for the boxes of the messages), the HUD rows are not
                assert!(f.cells[(l.row0 + l.ch - 1) * cols + l.col0].clear);
                assert!(!f.cells[0].clear);
                assert!(f.cells.iter().all(|c| c.ch != '▀'));
            }
        }
    }

    #[test]
    fn octant_layouts() {
        assert_eq!(octant_layout(land(), 79, 40), None);
        assert_eq!(octant_layout(land(), 80, 26), None);
        let l = octant_layout(land(), 80, 27).unwrap(); // the smallest window: 160 x 100 pixels
        assert_eq!((l.w, l.h, l.cw, l.ch, l.px(24)), (160, 100, 80, 25, 12));
        assert_eq!(octant_layout(land(), 107, 36).unwrap().px(24), 16); // the art as it is
        let l = octant_layout(land(), 160, 52).unwrap(); // 320 x 200 pixels: a game pixel is a canvas pixel
        assert_eq!((l.w, l.h, l.cw, l.ch, l.col0, l.row0), (320, 200, 160, 50, 0, 2));
        let l = octant_layout(land(), 214, 69).unwrap(); // the art twice as big
        assert_eq!((l.cw, l.ch, l.px(24)), (214, 67, 32));
        let l = octant_layout(land(), 300, 100).unwrap(); // bigger windows keep the biggest scale (3/2)
        assert_eq!((l.w, l.h, l.col0), (480, 300, 30));
        for cols in 80..260 {
            for rows in 27..90 {
                let l = octant_layout(land(), cols, rows).unwrap();
                assert!(l.cw <= cols && l.ch + HUD_ROWS <= rows && l.w >= 160 && l.h % 4 == 0 && l.w % 2 == 0);
            }
        }
    }

    #[test]
    fn octant_cells_are_exact_with_two_colours() {
        let (a, b) = ([200, 100, 50], [10, 20, 30]);
        for mask in 0..256usize {
            let px: [Rgb; 8] = std::array::from_fn(|i| if mask >> i & 1 == 1 { a } else { b });
            let (ch, fg, bg) = octant_cell(px);
            match mask {
                0 => assert_eq!((ch, fg, bg), (' ', b, b)),
                255 => assert_eq!((ch, fg, bg), (' ', a, a)),
                _ => assert_eq!((ch, fg, bg), (crate::octant::OCTANT[mask], a, b)),
            }
        }
        assert_eq!(crate::octant::OCTANT[0b0000_1111], '\u{2580}' as char); // the 4 upper pixels (octants 1 to 4) are the upper half block
        assert_eq!(crate::octant::OCTANT[0b1111_0000], '\u{2584}'); // the 4 lower ones
        assert_eq!(crate::octant::OCTANT[0b0101_0101], '\u{258c}'); // the left column
        assert_eq!(crate::octant::OCTANT[0b0000_0001], '\u{1cea8}'); // octant 1 only: the left half of the upper quarter
        assert_eq!(crate::octant::OCTANT[0b0000_0010], '\u{1ceab}'); // octant 2 only: the right half
    }

    #[test]
    fn octant_cell_with_three_colours_keeps_the_shape() {
        // 6 pixels red, 1 almost red, 1 blue: the pair red / blue, the almost red one goes to red
        let (red, red2, blue) = ([255, 0, 0], [250, 10, 0], [0, 0, 255]);
        let px = [red, red, red, red2, red, red, blue, blue];
        let (ch, fg, bg) = octant_cell(px);
        assert_eq!(bg, blue);
        assert_eq!(fg, red);
        assert_eq!(ch, crate::octant::OCTANT[0b0011_1111]);
    }

    #[test]
    fn draws_all_states_in_octants() {
        for (cols, rows) in [(80, 27), (107, 36), (160, 52), (200, 70)] {
            let l = octant_layout(land(), cols, rows).unwrap();
            let mut r = Renderer::new(l);
            let mut g = Game::new(1234);
            let press = Input { fire: true, ..Default::default() };
            g.tick(&press, 0);
            for t in 0..3000 {
                let inp = game_autoplay(&g);
                g.tick(if t == 0 { &press } else { &inp }, 0);
                if t % 97 == 0 {
                    let f = r.draw(&g, cols, rows);
                    assert_eq!(f.cells.len(), cols * rows);
                    // the play area has octant characters and colours, and no half block of the old kind
                    assert!(f.cells.iter().any(|c| ('\u{1cd00}'..='\u{1cde5}').contains(&c.ch) && c.fg != c.bg));
                    assert!(f.cells.iter().all(|c| c.ch != '▀' || c.fg != c.bg));
                }
            }
        }
    }

    #[test]
    fn draws_all_states() {
        for (cols, rows) in [(80, 27), (107, 36), (160, 52)] {
            let l = layout(land(), cols, rows).unwrap();
            let mut r = Renderer::new(l);
            let mut g = Game::new(1234);
            let none = Input::default();
            let press = Input { fire: true, ..Default::default() };
            let f = r.draw(&g, cols, rows);
            assert_eq!(f.cells.len(), cols * rows);
            g.tick(&press, 0);
            for t in 0..3000 {
                let inp = game_autoplay(&g);
                g.tick(if t == 0 { &press } else { &inp }, 0);
                if t % 97 == 0 {
                    let f = r.draw(&g, cols, rows);
                    // the play area has pixels that are not black, and the HUD text is there
                    assert!(f.cells.iter().any(|c| c.ch == '▀' && c.fg != [0, 0, 0]));
                }
            }
            let _ = none;
        }
    }

    #[test]
    fn portrait_layouts() {
        assert_eq!(min_size(land()), (80, 27));
        assert_eq!(min_size(port()), (51, 35)); // 204 x 260 game pixels: 4 for a canvas pixel
        assert_eq!(layout(port(), 50, 40), None);
        assert_eq!(layout(port(), 51, 34), None);
        assert_eq!(layout(port(), 51, 35).unwrap().k, 4);
        assert_eq!(layout(port(), 68, 46).unwrap().k, 3);
        let l = layout(port(), 102, 67).unwrap();
        assert_eq!((l.k, l.w, l.h, l.cw, l.ch), (2, 102, 130, 102, 65));
        let l = octant_layout(port(), 51, 35).unwrap(); // the smallest window: 102 x 130 pixels
        assert_eq!((l.w, l.h, l.cw, l.ch), (102, 132, 51, 33));
        let l = octant_layout(port(), 160, 60).unwrap(); // 58 rows of 4 pixels = 232: the scale 5/6 (170 x 217) is the biggest that fits
        assert!(l.ch + HUD_ROWS <= 60 && (l.num, l.den) == (5, 6));
        // the pixel mode: the sprite is at least 2 x the art, the canvas follows the window
        let l = pixel_layout(port(), 41, 28, 10, 20).unwrap();
        assert_eq!((l.w, l.h), (408, 520));
        assert_eq!(pixel_layout(port(), 40, 28, 10, 20), None);
        let l = pixel_layout(port(), 100, 60, 10, 20).unwrap(); // 1000 x 1160 pixels
        assert!(l.pixels && l.w <= 1000 && l.h <= 58 * 20 && (l.num + 1) * 260 / PIXEL_DEN > 58 * 20); // the height limits: the next step does not fit
    }

    #[test]
    fn draws_all_states_in_the_portrait_field() {
        for (name, l, cols, rows) in [
            ("blocks", layout(port(), 102, 67), 102, 67),
            ("octants", octant_layout(port(), 80, 50), 80, 50),
            ("pixels", pixel_layout(port(), 80, 50, 8, 16), 80, 50),
        ] {
            let l = l.unwrap();
            let mut r = Renderer::new(l);
            let mut g = Game::with_field(1234, true);
            let press = Input { fire: true, ..Default::default() };
            g.tick(&press, 0);
            for t in 0..4000 {
                let inp = game_autoplay(&g);
                g.tick(if t == 0 { &press } else { &inp }, if t > 2000 { 3 } else { 0 });
                if t % 53 == 0 {
                    let (f, cv) = r.draw_with_canvas(&g, cols, rows);
                    assert_eq!(f.cells.len(), cols * rows, "{}", name);
                    assert!(cv.px.iter().any(|p| *p != [0, 0, 0]), "{}", name);
                }
            }
        }
        // the sprite boxes are 16 x 16 and sit on the formation slots: an alien in the formation is drawn at its slot
        let l = layout(port(), 102, 67).unwrap();
        assert_eq!(l.px(16), 8);
    }
}
