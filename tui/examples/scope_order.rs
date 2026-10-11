//! Compare orders of the scope lines on real game frames: how far the beam jumps, how many samples (so how fast the picture repeats),
//! and how stable the order is from one frame to the next.
//! Usage: cargo run --release --example scope_order --no-default-features -- [ticks] [stage]
use galaga_tui::game::*;
use galaga_tui::scope::{build_tagged, Seg};

const C: f32 = 2047.5;

fn hilbert(mut x: u32, mut y: u32) -> u32 {
    // the index of a point (0..4095, 0..4095) along the Hilbert curve of order 12
    let n: u32 = 4096;
    let mut d = 0;
    let mut s = n / 2;
    while s > 0 {
        let rx = u32::from(x & s > 0);
        let ry = u32::from(y & s > 0);
        d += s * s * ((3 * rx) ^ ry);
        if ry == 0 {
            if rx == 1 {
                x = n - 1 - x;
                y = n - 1 - y;
            }
            std::mem::swap(&mut x, &mut y);
        }
        s /= 2;
    }
    d
}

fn dist(ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    ((ax - bx).powi(2) + (ay - by).powi(2)).sqrt()
}

fn jumps(v: &[Seg]) -> f32 {
    let (mut x, mut y, mut sum) = (C, C, 0.0);
    for s in v {
        sum += dist(x, y, s[0] as f32, s[1] as f32);
        x = s[2] as f32;
        y = s[3] as f32;
    }
    sum + dist(x, y, C, C)
}

/// The samples the page makes (docs/scope/index.html `trace`): a jump at 6 times the line speed, at least 2 samples a move.
fn samples(v: &[Seg]) -> usize {
    const SPEED: f32 = 130.0;
    let (mut x, mut y, mut n) = (C, C, 0usize);
    let mv = |d: f32, step: f32| ((d / step).ceil() as usize).max(2);
    for s in v {
        n += mv(dist(x, y, s[0] as f32, s[1] as f32), SPEED * 6.0);
        n += mv(dist(s[0] as f32, s[1] as f32, s[2] as f32, s[3] as f32), SPEED);
        x = s[2] as f32;
        y = s[3] as f32;
    }
    n
}

fn mid(s: &Seg) -> (u32, u32) {
    (((s[0] as i32 + s[2] as i32) / 2) as u32, ((s[1] as i32 + s[3] as i32) / 2) as u32)
}

/// Turn each line so that it starts at the end that is nearer to where the beam is.
fn flip_fit(v: &[Seg]) -> Vec<Seg> {
    let (mut x, mut y) = (C, C);
    v.iter()
        .map(|s| {
            let t = if dist(x, y, s[2] as f32, s[3] as f32) < dist(x, y, s[0] as f32, s[1] as f32) { [s[2], s[3], s[0], s[1]] } else { *s };
            x = t[2] as f32;
            y = t[3] as f32;
            t
        })
        .collect()
}

/// A: Hilbert order of the midpoints of single lines.
fn hilbert_lines(v: &[Seg], _ids: &[u16]) -> Vec<Seg> {
    let mut idx: Vec<usize> = (0..v.len()).collect();
    idx.sort_by_key(|&i| { let m = mid(&v[i]); hilbert(m.0, m.1) });
    flip_fit(&idx.iter().map(|&i| v[i]).collect::<Vec<_>>())
}

/// B: whole drawings in Hilbert order of the centre of their box; inside a drawing the order of the drawing code, lines turned to fit.
fn hilbert_objects(v: &[Seg], ids: &[u16]) -> Vec<Seg> {
    let mut objs: Vec<(u32, Vec<Seg>)> = Vec::new();
    let mut last = u16::MAX;
    for (s, &id) in v.iter().zip(ids) {
        if id != last {
            objs.push((0, Vec::new()));
            last = id;
        }
        objs.last_mut().unwrap().1.push(*s);
    }
    for o in objs.iter_mut() {
        let (mut x0, mut y0, mut x1, mut y1) = (i32::MAX, i32::MAX, 0i32, 0i32);
        for s in &o.1 {
            for (x, y) in [(s[0], s[1]), (s[2], s[3])] {
                x0 = x0.min(x as i32);
                x1 = x1.max(x as i32);
                y0 = y0.min(y as i32);
                y1 = y1.max(y as i32);
            }
        }
        o.0 = hilbert(((x0 + x1) / 2) as u32, ((y0 + y1) / 2) as u32);
    }
    objs.sort_by_key(|o| o.0);
    flip_fit(&objs.into_iter().flat_map(|o| o.1).collect::<Vec<_>>())
}

/// C: Hilbert order of the drawings, then greedy nearest line inside each drawing.
fn hilbert_objects_greedy(v: &[Seg], ids: &[u16]) -> Vec<Seg> {
    let mut objs: Vec<(u32, Vec<Seg>)> = Vec::new();
    let mut last = u16::MAX;
    for (s, &id) in v.iter().zip(ids) {
        if id != last {
            objs.push((0, Vec::new()));
            last = id;
        }
        objs.last_mut().unwrap().1.push(*s);
    }
    for o in objs.iter_mut() {
        let (sx, sy): (i32, i32) = o.1.iter().fold((0, 0), |a, s| (a.0 + (s[0] as i32 + s[2] as i32) / 2, a.1 + (s[1] as i32 + s[3] as i32) / 2));
        o.0 = hilbert((sx / o.1.len() as i32) as u32, (sy / o.1.len() as i32) as u32);
    }
    objs.sort_by_key(|o| o.0);
    let (mut x, mut y) = (C, C);
    let mut out = Vec::new();
    for (_, mut segs) in objs {
        while !segs.is_empty() {
            let (mut bi, mut bf, mut bd) = (0, false, f32::MAX);
            for (i, s) in segs.iter().enumerate() {
                let (a, b) = (dist(x, y, s[0] as f32, s[1] as f32), dist(x, y, s[2] as f32, s[3] as f32));
                if a < bd { (bi, bf, bd) = (i, false, a); }
                if b < bd { (bi, bf, bd) = (i, true, b); }
            }
            let s = segs.swap_remove(bi);
            let s = if bf { [s[2], s[3], s[0], s[1]] } else { s };
            x = s[2] as f32;
            y = s[3] as f32;
            out.push(s);
        }
    }
    out
}

/// The same lines tagged with their index in the drawing order (a stable name), in the order of `f`.
fn order_of(v: &[Seg], ids: &[u16], f: &dyn Fn(&[Seg], &[u16]) -> Vec<Seg>) -> Vec<usize> {
    let key = |s: &Seg| if (s[0], s[1]) <= (s[2], s[3]) { *s } else { [s[2], s[3], s[0], s[1]] };
    let ordered = f(v, ids);
    let mut pos = std::collections::HashMap::new();
    for (i, s) in v.iter().enumerate() {
        pos.entry(key(s)).or_insert_with(Vec::new).push(i);
    }
    ordered.iter().map(|s| pos.get_mut(&key(s)).and_then(|l| l.pop()).unwrap_or(usize::MAX)).collect()
}

/// The share of neighbours in the order at tick t that are neighbours again at tick t + 1 (in either direction).
fn stability(a: &[usize], b: &[usize]) -> f32 {
    if a.len() != b.len() || a.len() < 3 {
        return f32::NAN;
    }
    let nb: std::collections::HashSet<(usize, usize)> = b.windows(2).flat_map(|w| [(w[0], w[1]), (w[1], w[0])]).collect();
    a.windows(2).filter(|w| nb.contains(&(w[0], w[1]))).count() as f32 / (a.len() - 1) as f32
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let ticks: i32 = a.get(1).and_then(|s| s.parse().ok()).unwrap_or(6000);
    let stage: i32 = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(0);
    let names = ["drawing order (no sort)", "greedy nearest line (committed)", "Hilbert: single lines", "Hilbert: whole drawings", "Hilbert drawings + greedy inside"];
    let sorters: Vec<Box<dyn Fn(&[Seg], &[u16]) -> Vec<Seg>>> = vec![
        Box::new(|v, _| v.to_vec()),
        Box::new(|v, _| greedy(v)),
        Box::new(hilbert_lines),
        Box::new(hilbert_objects),
        Box::new(hilbert_objects_greedy),
    ];
    let mut g = Game::new(1234);
    let (mut v, mut ids) = (Vec::new(), Vec::new());
    let mut sum_j = [0.0f64; 5];
    let mut sum_s = [0.0f64; 5];
    let mut sum_st = [0.0f64; 5];
    let (mut frames, mut pairs) = (0u32, 0u32);
    let mut prev: Option<Vec<Vec<usize>>> = None;
    let mut sink = Vec::new();
    let mut maxs = [0usize; 5];
    for t in 0..ticks {
        g.invuln = 100;
        let inp = game_autoplay(&g);
        g.tick(&inp, stage);
        g.snd = 0;
        if g.state != S_PLAY {
            prev = None;
            continue;
        }
        build_tagged(&g, &mut v, &mut ids);
        let mut orders = Vec::new();
        for (k, f) in sorters.iter().enumerate() {
            let o = f(&v, &ids);
            sum_j[k] += jumps(&o) as f64;
            let sm = samples(&o);
            sum_s[k] += sm as f64;
            maxs[k] = maxs[k].max(sm);
            orders.push(order_of(&v, &ids, f));
        }
        if let Some(p) = &prev {
            for k in 0..5 {
                let st = stability(&p[k], &orders[k]);
                if !st.is_nan() {
                    sum_st[k] += st as f64;
                }
            }
            pairs += 1;
        }
        prev = Some(orders);
        frames += 1;
        sink.push(v.len());
    }
    let n = frames as f64;
    println!("{} frames of play (every tick), {} frame pairs, mean {:.0} lines a frame\n", frames, pairs, sink.iter().sum::<usize>() as f64 / n);
    println!("{:<34} {:>12} {:>9} {:>8} {:>9} {:>11}", "order", "jumps (units)", "samples", "worst", "repeat Hz", "stability");
    for k in 0..5 {
        println!("{:<34} {:>12.0} {:>9.0} {:>8} {:>9.1} {:>10.0}%", names[k], sum_j[k] / n, sum_s[k] / n, maxs[k], 48000.0 / (sum_s[k] / n), sum_st[k] / pairs.max(1) as f64 * 100.0);
    }
}

fn greedy(v: &[Seg]) -> Vec<Seg> {
    // the committed order (scope::build does the same on the same lines): rebuilt here from the unordered lines
    let mut left: Vec<Seg> = v.to_vec();
    let (mut x, mut y) = (C, C);
    let mut out = Vec::with_capacity(v.len());
    while !left.is_empty() {
        let (mut bi, mut bf, mut bd) = (0, false, f32::MAX);
        for (i, s) in left.iter().enumerate() {
            let (a, b) = (dist(x, y, s[0] as f32, s[1] as f32), dist(x, y, s[2] as f32, s[3] as f32));
            if a < bd { (bi, bf, bd) = (i, false, a); }
            if b < bd { (bi, bf, bd) = (i, true, b); }
        }
        let s = left.remove(bi);
        let s = if bf { [s[2], s[3], s[0], s[1]] } else { s };
        x = s[2] as f32;
        y = s[3] as f32;
        out.push(s);
    }
    out
}
