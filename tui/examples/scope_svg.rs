//! Debug: play `ticks` ticks (autoplay, unhittable ship) and write the scope picture of that frame as an SVG.
//! Usage: cargo run --release --example scope_svg --no-default-features -- 1500 out.svg [stage]
use galaga_tui::game::*;
use galaga_tui::scope::build;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let ticks: i32 = a.get(1).and_then(|s| s.parse().ok()).unwrap_or(1500);
    let stage: i32 = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(0);
    let mut g = Game::new(1234);
    for _ in 0..ticks {
        g.invuln = 100;
        let inp = game_autoplay(&g);
        g.tick(&inp, stage);
        g.snd = 0;
    }
    let mut v = Vec::new();
    build(&g, &mut v);
    let mut s = String::from("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 4096 4096' width='900' height='900'><rect width='4096' height='4096' fill='#001408'/><g stroke='#4f8' stroke-width='9' stroke-linecap='round'>");
    for l in &v {
        s += &format!("<line x1='{}' y1='{}' x2='{}' y2='{}'/>", l[0], 4095 - l[1], l[2], 4095 - l[3]);
    }
    s += "</g></svg>";
    std::fs::write(a.get(2).map(String::as_str).unwrap_or("scope.svg"), s).unwrap();
    println!("{} segments, state {}", v.len(), g.state);
}
