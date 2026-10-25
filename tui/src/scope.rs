//! The oscilloscope picture: the state of the game as line segments, for the X/Y mode of a scope (left channel = X, right channel = Y).
//! A scope draws one colour and no filled shapes, so every object is a few strokes: our own line drawings with the silhouettes of the sprites.
//! The segments are in a square box 0..4095 (y up). The play area (320 x 200 game pixels) keeps its shape and sits in the middle of the box,
//! the numbers of the HUD are above it. A frame must stay under `BUDGET` segments: the beam of a scope needs time for every line, so more lines
//! make a slower refresh (flicker). Everything else stays the same as in `render.rs`: same object positions, same states.
use crate::game::*;

/// One line: x0, y0, x1, y1.
pub type Seg = [i16; 4];

/// The most segments a frame should have (the beam draws about 2 samples for each one at 48 kHz and 50 frames a second).
pub const BUDGET: usize = 480;

const BOX: f32 = 4095.0;
const SCALE: f32 = BOX / 320.0; // box units for one game pixel
const HUD: f32 = 26.0; // game pixels above the play area (the numbers)

struct Pen<'a> {
    out: &'a mut Vec<Seg>,
    ids: &'a mut Vec<u16>, // the drawing (object) of each segment: a new number for every alien, shot, digit ...
    obj: u16,
}

impl Pen<'_> {
    fn next(&mut self) {
        self.obj += 1;
    }

    /// A line in game pixels of the play area (0,0 = top left, 320 x 200); the HUD is at y < 0.
    fn line(&mut self, x0: f32, y0: f32, x1: f32, y1: f32) {
        let m = |x: f32, y: f32| {
            let bx = x * SCALE;
            let by = BOX - ((y + HUD) * SCALE + (BOX - (200.0 + HUD) * SCALE) / 2.0);
            (bx.clamp(0.0, BOX) as i16, by.clamp(0.0, BOX) as i16)
        };
        let (a, b) = (m(x0, y0), m(x1, y1));
        if a != b {
            self.out.push([a.0, a.1, b.0, b.1]);
            self.ids.push(self.obj);
        }
    }

    /// Points around (cx, cy), scaled; `close` joins the last point to the first.
    fn poly(&mut self, cx: f32, cy: f32, s: f32, pts: &[(f32, f32)], close: bool) {
        for w in pts.windows(2) {
            self.line(cx + w[0].0 * s, cy + w[0].1 * s, cx + w[1].0 * s, cy + w[1].1 * s);
        }
        if close && pts.len() > 2 {
            let (a, b) = (pts[pts.len() - 1], pts[0]);
            self.line(cx + a.0 * s, cy + a.1 * s, cx + b.0 * s, cy + b.1 * s);
        }
    }

    /// The same points mirrored left to right.
    fn mirrored(&mut self, cx: f32, cy: f32, pts: &[(f32, f32)]) {
        let m: Vec<(f32, f32)> = pts.iter().map(|p| (-p.0, p.1)).collect();
        self.poly(cx, cy, 1.0, &m, false);
    }

    fn ship(&mut self, cx: f32, cy: f32, s: f32) {
        self.next();
        const P: [(f32, f32); 10] = [(0.0, -9.0), (3.0, -1.0), (9.0, 6.0), (9.0, 9.0), (3.0, 6.0), (0.0, 8.0), (-3.0, 6.0), (-9.0, 9.0), (-9.0, 6.0), (-3.0, -1.0)];
        self.poly(cx, cy, s, &P, true);
    }

    fn bee(&mut self, cx: f32, cy: f32, flap: i32) {
        self.next();
        self.poly(cx, cy, 1.0, &[(-3.0, -6.0), (3.0, -6.0), (5.0, 0.0), (0.0, 8.0), (-5.0, 0.0)], true);
        let up = if flap == 0 { -7.0 } else { 3.0 };
        let wing = [(-5.0, -1.0), (-11.0, up), (-5.0, 3.0)];
        self.poly(cx, cy, 1.0, &wing, false);
        self.mirrored(cx, cy, &wing);
    }

    fn butterfly(&mut self, cx: f32, cy: f32, flap: i32) {
        self.next();
        let (a, b) = if flap == 0 { (-8.0, 7.0) } else { (-3.0, 4.0) };
        let wing = [(-2.0, -1.0), (-11.0, a), (-10.0, b), (-2.0, 3.0)];
        self.poly(cx, cy, 1.0, &wing, false);
        self.mirrored(cx, cy, &wing);
        self.line(cx, cy - 5.0, cx, cy + 6.0);
        self.line(cx - 2.0, cy - 7.0, cx, cy - 5.0);
        self.line(cx + 2.0, cy - 7.0, cx, cy - 5.0);
    }

    fn boss(&mut self, cx: f32, cy: f32, flap: i32, hurt: bool) {
        self.next();
        self.poly(cx, cy, 1.0, &[(-7.0, -6.0), (-5.0, -10.0), (-2.0, -6.0), (0.0, -10.0), (2.0, -6.0), (5.0, -10.0), (7.0, -6.0)], false);
        self.poly(cx, cy, 1.0, &[(-7.0, -6.0), (-10.0, 0.0), (-6.0, 7.0), (0.0, 9.0), (6.0, 7.0), (10.0, 0.0), (7.0, -6.0)], false);
        let leg = if flap == 0 { 10.0 } else { 7.0 };
        self.line(cx - 6.0, cy + 7.0, cx - 9.0, cy + leg);
        self.line(cx + 6.0, cy + 7.0, cx + 9.0, cy + leg);
        if hurt {
            self.line(cx - 8.0, cy - 1.0, cx + 8.0, cy - 1.0); // the second line: it has been hit once
        }
    }

    /// A burst of the arcade: `n` short radial dashes (single pixels on a raster screen) between the radii r0 and r1; `seed` makes every step another scatter.
    fn burst(&mut self, cx: f32, cy: f32, n: i32, r0: f32, r1: f32, seed: i32) {
        self.next();
        for j in 0..n {
            let t = j as f32 * 2.399_963 + seed as f32 * 1.7;
            let r = r0 + (r1 - r0) * (((j * 7 + seed * 3) % n.max(1)) as f32 / n.max(1) as f32);
            self.line(cx + t.cos() * r, cy + t.sin() * r, cx + t.cos() * (r + 1.6), cy + t.sin() * (r + 1.6));
        }
    }

    /// The first step of a burst: a small cross.
    fn star(&mut self, cx: f32, cy: f32, r: f32) {
        self.next();
        self.line(cx - r, cy, cx + r, cy);
        self.line(cx, cy - r, cx, cy + r);
    }

    /// The tractor beam: a cone of thin rings (one every 2 game pixels), the first ones bowed; a ring that is lit is drawn twice (the beam rests twice on it: brighter), and which ones are lit runs down.
    fn beam(&mut self, g: &Game) {
        self.next();
        let b = &g.al[g.cap_boss as usize];
        let n = if g.cap == C_BEAM { g.beam_len } else { 4 };
        let (cx, y0) = (b.x as f32 - 12.0, b.y as f32 - 44.0 + 14.0);
        for i in 0..n * 4 {
            let y = y0 + i as f32 * 2.0;
            let hw = 12.0 + i as f32 * 1.4;
            let lit = (i - (g.frame >> 2)).rem_euclid(4) == 0;
            for _ in 0..if lit { 2 } else { 1 } {
                if i < 3 {
                    self.line(cx - hw, y + 1.0, cx, y);
                    self.line(cx, y, cx + hw, y + 1.0);
                } else {
                    self.line(cx - hw, y, cx + hw, y);
                }
            }
        }
    }

    /// A text of the stroke font, `u` game pixels for a font unit (a letter is 4 x 6 units). `x` is the left end.
    fn text(&mut self, x: f32, y: f32, u: f32, s: &str) {
        let mut x = x;
        for ch in s.chars() {
            self.next();
            for stroke in glyph(ch.to_ascii_uppercase()).split('|').filter(|t| !t.is_empty()) {
                let pts: Vec<(f32, f32)> = stroke
                    .split(' ')
                    .map(|p| {
                        let b = p.as_bytes();
                        (x + (b[0] - b'0') as f32 * u, y + (b[1] - b'0') as f32 * u)
                    })
                    .collect();
                for w in pts.windows(2) {
                    self.line(w[0].0, w[0].1, w[1].0, w[1].1);
                }
            }
            x += 6.0 * u;
        }
    }

    fn ctext(&mut self, y: f32, u: f32, s: &str) {
        let w = s.chars().count() as f32 * 6.0 * u - 2.0 * u;
        self.text((320.0 - w) / 2.0, y, u, s);
    }
}

/// The strokes of a letter on a grid of 4 x 6 units: points as two digits (x y), a space between points, `|` between strokes.
fn glyph(c: char) -> &'static str {
    match c {
        'A' => "06 02 10 30 42 46|04 44",
        'B' => "00 30 41 42 33 03|33 44 45 36 06 00",
        'C' => "41 30 10 01 05 16 36 45",
        'D' => "00 30 41 45 36 06 00",
        'E' => "40 00 06 46|03 33",
        'F' => "40 00 06|03 33",
        'G' => "41 30 10 01 05 16 36 45 44 24",
        'H' => "00 06|40 46|03 43",
        'I' => "10 30|16 36|20 26",
        'J' => "40 45 36 16 05",
        'K' => "00 06|40 03 46",
        'L' => "00 06 46",
        'M' => "06 00 23 40 46",
        'N' => "06 00 46 40",
        'O' => "10 30 41 45 36 16 05 01 10",
        'P' => "06 00 30 41 42 33 03",
        'Q' => "10 30 41 45 36 16 05 01 10|34 46",
        'R' => "06 00 30 41 42 33 03|23 46",
        'S' => "41 30 10 01 02 13 33 44 45 36 16 05",
        'T' => "00 40|20 26",
        'U' => "00 05 16 36 45 40",
        'V' => "00 26 40",
        'W' => "00 16 23 36 40",
        'X' => "00 46|40 06",
        'Y' => "00 23 40|23 26",
        'Z' => "00 40 06 46",
        '0' => "10 30 41 45 36 16 05 01 10|05 41",
        '1' => "10 20 26|16 36",
        '2' => "01 10 30 41 42 06 46",
        '3' => "00 40 23 33 44 45 36 16 05",
        '4' => "30 03 43|30 36",
        '5' => "40 00 03 33 44 45 36 16 05",
        '6' => "40 20 03 05 16 36 45 44 33 03",
        '7' => "00 40 26",
        '8' => "10 30 41 42 33 13 02 01 10|13 04 05 16 36 45 44 33",
        '9' => "10 30 41 42 33 13 02 01 10|42 45 36 16",
        '-' => "03 43",
        '!' => "20 24|26 26",
        '%' => "00 40|01 11|35 45",
        _ => "",
    }
}

/// The digits of a number without leading zeros, so a score of 120 draws three digits.
fn number(n: i32) -> String {
    n.max(0).to_string()
}

/// The length of all the jumps of the beam between the lines (the beam starts and ends in the middle of the box).
pub fn jump_length(v: &[Seg]) -> f32 {
    let (mut x, mut y) = (2047.5f32, 2047.5f32);
    let mut sum = 0.0;
    for s in v {
        sum += ((s[0] as f32 - x).powi(2) + (s[1] as f32 - y).powi(2)).sqrt();
        x = s[2] as f32;
        y = s[3] as f32;
    }
    sum + ((x - 2047.5).powi(2) + (y - 2047.5).powi(2)).sqrt()
}

/// Put the lines in an order that makes the beam jump less: from the end of a line, take the line whose start (or end: the line is then turned round) is nearest.
/// A line that goes on where the last one ended costs no jump, so strokes of one drawing stay together. About `n * n / 2` distance tests for n lines.
fn order(v: &mut Vec<Seg>) {
    let n = v.len();
    let mut done = vec![false; n];
    let mut out = Vec::with_capacity(n);
    let (mut x, mut y) = (2047.5f32, 2047.5f32);
    let d2 = |ax: f32, ay: f32, bx: i16, by: i16| (ax - bx as f32).powi(2) + (ay - by as f32).powi(2);
    for _ in 0..n {
        let (mut best, mut flip, mut bd) = (0, false, f32::MAX);
        for (i, s) in v.iter().enumerate().filter(|(i, _)| !done[*i]) {
            let (a, b) = (d2(x, y, s[0], s[1]), d2(x, y, s[2], s[3]));
            if a < bd {
                (best, flip, bd) = (i, false, a);
            }
            if b < bd {
                (best, flip, bd) = (i, true, b);
            }
        }
        done[best] = true;
        let s = v[best];
        let s = if flip { [s[2], s[3], s[0], s[1]] } else { s };
        x = s[2] as f32;
        y = s[3] as f32;
        out.push(s);
    }
    *v = out;
}

/// Make the line segments of the picture for the state of the game, in an order that is short for the beam. `out` is cleared first.
pub fn build(g: &Game, out: &mut Vec<Seg>) {
    build_unordered(g, out);
    order(out);
}

/// The same lines in the order of the drawing code (the HUD, the beam, the aliens by slot, the shots, the ship, the text).
pub fn build_unordered(g: &Game, out: &mut Vec<Seg>) {
    build_tagged(g, out, &mut Vec::new());
}

/// The lines in the order of the drawing code, and the number of the drawing of each line.
pub fn build_tagged(g: &Game, out: &mut Vec<Seg>, ids: &mut Vec<u16>) {
    out.clear();
    ids.clear();
    let mut p = Pen { out, ids, obj: 0 };
    if g.state == S_TITLE {
        p.ctext(34.0, 7.0, "GALAGA");
        p.ctext(112.0, 2.0, &format!("HI-SCORE {}", number(g.hi)));
        p.ctext(150.0, 2.0, "PRESS SPACE");
        return;
    }
    // the numbers above the play area: score at the left, the hi-score in the middle, stage and lives at the right
    p.text(4.0, -20.0, 2.6, &number(g.score));
    let hs = number(g.hi);
    p.text(130.0 - hs.len() as f32 * 7.8 / 2.0, -20.0, 2.6, &hs);
    p.text(250.0, -20.0, 2.6, &number(g.stage));
    for i in 0..g.lives.clamp(0, 5) {
        p.ship(296.0 + i as f32 * 8.0 - 12.0, -12.0, 0.45);
    }
    if (g.cap == C_BEAM && g.beam_len > 0) || g.cap == C_PULL {
        p.beam(g);
    }
    let flap = (g.frame >> 4) & 1;
    for i in 0..NAL {
        let a = &g.al[i];
        if a.st == A_DEAD || (a.st == A_ENTER && a.ent == 0) {
            continue;
        }
        let (cx, cy) = (a.x as f32 - 12.0, a.y as f32 - 44.0);
        if a.st == A_EXPLODE {
            let f = ((G_EXPL_TICKS - a.timer) >> 2).clamp(0, 4);
            match f {
                0 => p.star(cx, cy, 2.0),
                1 => p.burst(cx, cy, 10, 2.0, 6.0, f),
                2 => p.burst(cx, cy, 16, 3.0, 9.0, f),
                3 => p.burst(cx, cy, 22, 7.0, 13.0, f),
                _ => p.burst(cx, cy, 12, 10.0, 15.0, f),
            }
            continue;
        }
        match a.typ {
            T_BOSS => p.boss(cx, cy, flap, a.hp == 1 && g.challenge == 0),
            T_BUTTERFLY => p.butterfly(cx, cy, flap),
            _ => p.bee(cx, cy, flap),
        }
        if a.typ == T_BOSS && g.cap == C_CARRY && g.cap_boss == i as i32 && a.y >= 32 {
            p.ship(a.x as f32 - 12.0, a.y as f32 - 16.0 - 44.0 + 7.0, 0.7); // the captured fighter hangs under the boss
        }
    }
    for b in g.ps.iter().filter(|b| b.act != 0) {
        p.next();
        let (x, y) = (b.x as f32 + 9.0 - 24.0, b.y as f32 + 6.0 - 50.0);
        p.line(x, y - 4.0, x, y + 4.0);
    }
    for b in g.eb.iter().filter(|b| b.act != 0) {
        p.next();
        let (x, y) = (b.x as f32 + 12.0 - 24.0, b.y as f32 + 4.0 - 50.0);
        p.poly(x, y, 1.0, &[(0.0, -3.0), (1.5, 0.0), (0.0, 3.0), (-1.5, 0.0)], true);
    }
    let show = matches!(g.state, S_INTRO | S_PLAY | S_RESULT | S_CAPTURED);
    if g.state == S_DYING && g.dying_quiet == 0 {
        let f = ((G_DIE_TICKS - g.state_timer) >> 3).max(0);
        let (sx, sy) = (g.px as f32 + 12.0 - 24.0 + if g.dual != 0 { 8.0 } else { 0.0 }, g.py as f32 + 7.0 - 50.0);
        match f {
            0 => p.star(sx, sy, 4.0),
            1 => p.burst(sx, sy, 14, 2.0, 8.0, f),
            2 => p.burst(sx, sy, 20, 3.0, 11.0, f),
            3 => p.burst(sx, sy, 24, 6.0, 13.0, f),
            4 => p.burst(sx, sy, 14, 9.0, 15.0, f),
            5 => p.burst(sx, sy, 8, 12.0, 17.0, f),
            _ => {}
        }
    } else if show && !(g.state == S_PLAY && (g.invuln & 4) != 0) {
        let (sx, sy) = (g.px as f32 + 12.0 - 24.0, g.py as f32 + 7.0 - 50.0);
        p.ship(sx, sy, 1.0);
        if g.dual != 0 {
            p.ship(sx + 16.0, sy, 1.0);
        }
        if g.cap == C_RESCUE {
            p.ship(g.rx as f32 + 12.0 - 24.0, g.ry as f32 + 7.0 - 50.0, 1.0);
        }
    }
    match g.state {
        S_INTRO => p.ctext(128.0, 2.4, &if g.challenge != 0 { "CHALLENGING STAGE".to_string() } else { format!("STAGE {}", number(g.stage)) }),
        S_READY => p.ctext(160.0, 2.4, "READY"),
        S_DYING if g.dying_quiet != 0 => p.ctext(160.0, 2.4, "FIGHTER CAPTURED"),
        S_RESULT => {
            if g.challenge != 0 {
                p.ctext(72.0, 2.4, &format!("NUMBER OF HITS {}", g.chal_hits));
                if g.chal_hits == NAL as i32 {
                    p.ctext(100.0, 2.4, "PERFECT!");
                    p.ctext(128.0, 2.4, "BONUS 10000");
                }
            } else {
                let ratio = if g.shots > 0 { (g.hits * 100 / g.shots).min(100) } else { 0 };
                p.ctext(72.0, 2.4, &format!("SHOTS {}", g.shots));
                p.ctext(100.0, 2.4, &format!("HITS {}", g.hits));
                p.ctext(128.0, 2.4, &format!("RATIO {}%", ratio));
            }
        }
        S_GAMEOVER => {
            p.ctext(88.0, 3.2, "GAME OVER");
            if g.state_timer == 0 {
                p.ctext(124.0, 2.0, "PRESS SPACE");
            }
        }
        _ => {}
    }
    if g.paused != 0 {
        p.ctext(160.0, 2.4, "PAUSED");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(ticks: i32, god: bool, stage: i32) -> (Game, usize, usize) {
        let mut g = Game::new(1234);
        let mut v = Vec::new();
        let (mut most, mut sum) = (0, 0);
        for _ in 0..ticks {
            if god {
                g.invuln = 100;
            }
            let inp = game_autoplay(&g);
            g.tick(&inp, stage);
            g.snd = 0;
            g.save_req = 0;
            build(&g, &mut v);
            assert!(v.iter().all(|s| s.iter().all(|&c| (0..=4095).contains(&c))), "a segment is outside the box");
            most = most.max(v.len());
            sum += v.len();
        }
        (g, most, sum / ticks as usize)
    }

    #[test]
    fn the_order_is_shorter_and_keeps_every_line() {
        let mut g = Game::new(1234);
        let (mut before, mut after) = (0.0, 0.0);
        let (mut a, mut b) = (Vec::new(), Vec::new());
        for t in 0..4000 {
            g.invuln = 100;
            let inp = game_autoplay(&g);
            g.tick(&inp, 0);
            g.snd = 0;
            if t % 20 != 0 || g.state != S_PLAY {
                continue;
            }
            build_unordered(&g, &mut a);
            build(&g, &mut b);
            assert_eq!(a.len(), b.len());
            let key = |s: &Seg| if (s[0], s[1]) <= (s[2], s[3]) { *s } else { [s[2], s[3], s[0], s[1]] };
            let (mut ka, mut kb): (Vec<Seg>, Vec<Seg>) = (a.iter().map(key).collect(), b.iter().map(key).collect());
            ka.sort();
            kb.sort();
            assert_eq!(ka, kb, "the order must not change the picture");
            before += jump_length(&a);
            after += jump_length(&b);
        }
        assert!(before > 0.0 && after < before * 0.6, "jumps: {before} before, {after} after");
    }

    #[test]
    fn every_glyph_is_on_its_grid() {
        for c in ('A'..='Z').chain('0'..='9').chain("-!%".chars()) {
            let s = glyph(c);
            assert!(!s.is_empty(), "{c}");
            for p in s.split(|ch| ch == ' ' || ch == '|') {
                let b = p.as_bytes();
                assert!(b.len() == 2 && b[0] <= b'4' && b[1] <= b'6', "{c} {p}");
            }
        }
    }

    #[test]
    fn a_game_stays_inside_the_box_and_the_budget() {
        let (g, most, avg) = run(6000, true, 0);
        assert!(g.score > 0);
        assert!(most > 100, "the picture is empty: {most}");
        assert!(most <= BUDGET, "most segments in a frame: {most}");
        assert!(avg > 60, "average {avg}");
    }

    #[test]
    fn a_late_stage_with_a_full_formation_stays_in_the_budget() {
        let (_, most, _) = run(3000, true, 7);
        assert!(most <= BUDGET, "most segments in a frame: {most}");
    }
}
