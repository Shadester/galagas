//! Debug: play `ticks` ticks (autoplay, unhittable ship) and write the pixel mode canvas of that frame as a PPM; print the size of the
//! kitty graphics command and the time to draw and compress a frame.
//! Usage: [PORTRAIT=1] cargo run --release --example pixels_ppm -- 1500 out.ppm [cols rows cell_w cell_h] [stage]   (PORTRAIT=1: the arcade's portrait field)
use galaga_tui::game::*;
use galaga_tui::render::*;
use galaga_tui::term::image_command;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let n = |i: usize, d: usize| a.get(i).and_then(|s| s.parse().ok()).unwrap_or(d);
    let (cols, rows, cw, ch) = (n(3, 160), n(4, 52), n(5, 10), n(6, 20));
    let stage = n(7, 0) as i32;
    let mut g = Game::with_field(1234, std::env::var_os("PORTRAIT").is_some());
    let l = pixel_layout(Field::of(g.geo), cols, rows, cw, ch).expect("window too small");
    let mut r = Renderer::new(l);
    for _ in 0..n(1, 1500) {
        g.invuln = 100;
        let inp = game_autoplay(&g);
        g.tick(&inp, stage);
        g.snd = 0;
    }
    let t0 = std::time::Instant::now();
    let (_, cv) = r.draw_with_canvas(&g, cols, rows);
    let t1 = std::time::Instant::now();
    let s = image_command(&cv, l.col0, l.row0, 1);
    let t2 = std::time::Instant::now();
    println!("scale {}/{}: canvas {} x {} in {} x {} cells, draw {:?}, compress {:?}, {} bytes sent", l.num, l.den, cv.w, cv.h, l.cw, l.ch, t1 - t0, t2 - t1, s.len());
    let mut out = format!("P6\n{} {}\n255\n", cv.w, cv.h).into_bytes();
    for p in &cv.px {
        out.extend_from_slice(p);
    }
    std::fs::write(a.get(2).map(String::as_str).unwrap_or("pixels.ppm"), out).unwrap();
}
