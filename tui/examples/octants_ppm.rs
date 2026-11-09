//! Debug: play `ticks` ticks (autoplay, unhittable ship), draw the frame in the octant mode and write the play area as a PPM, each cell
//! expanded to its 2 x 4 pixels with only the two colours of the cell: how the colour clash looks.
//! Usage: [PORTRAIT=1] cargo run --release --example octants_ppm --no-default-features -- 1500 out.ppm [cols rows] [stage]   (PORTRAIT=1: the portrait field)
use galaga_tui::game::*;
use galaga_tui::octant::OCTANT;
use galaga_tui::render::*;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let n = |i: usize, d: usize| a.get(i).and_then(|s| s.parse().ok()).unwrap_or(d);
    let (cols, rows, stage) = (n(3, 160), n(4, 52), n(5, 0) as i32);
    let mut g = Game::with_field(1234, std::env::var_os("PORTRAIT").is_some());
    let l = octant_layout(Field::of(g.geo), cols, rows).expect("window too small");
    let mut r = Renderer::new(l);
    for _ in 0..n(1, 1500) {
        g.invuln = 100;
        let inp = game_autoplay(&g);
        g.tick(&inp, stage);
        g.snd = 0;
    }
    let f = r.draw(&g, cols, rows);
    let (w, h) = (l.cw * 2, l.ch * 4);
    let mut img = vec![[0u8; 3]; w * h];
    let mut clash = 0;
    for cy in 0..l.ch {
        for cx in 0..l.cw {
            let c = f.cells[(l.row0 + cy) * cols + l.col0 + cx];
            let mask = OCTANT.iter().position(|&o| o == c.ch).unwrap_or(0);
            clash += (c.fg != c.bg) as usize;
            for i in 0..8 {
                img[(4 * cy + i / 2) * w + 2 * cx + i % 2] = if mask >> i & 1 == 1 { c.fg } else { c.bg };
            }
        }
    }
    let mut out = format!("P6\n{} {}\n255\n", w, h).into_bytes();
    for p in &img {
        out.extend_from_slice(p);
    }
    std::fs::write(a.get(2).map(String::as_str).unwrap_or("octants.ppm"), out).unwrap();
    println!("scale {}/{}: canvas {} x {} pixels in {} x {} cells, {} cells with two colours", l.num, l.den, w, h, l.cw, l.ch, clash);
}
