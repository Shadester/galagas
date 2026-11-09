//! The terminal: raw mode, the alternate screen, and writing a `Frame` as the cells that changed since the last one.
use crate::render::{Canvas, Cell, Frame, Rgb};
use crossterm::event::{KeyboardEnhancementFlags, PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags};
use crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::{cursor, execute};
use std::fmt::Write as _;
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};

static ACTIVE: AtomicBool = AtomicBool::new(false);
static IMAGE: AtomicBool = AtomicBool::new(false); // an image of the kitty graphics protocol is on the screen

/// The command that deletes all images and frees their data (the alternate screen is ours).
const DELETE_IMAGE: &str = "\x1b_Ga=d,d=A,q=2\x1b\\";

/// Give the terminal back (also from the panic hook): the cursor, the normal screen, the keys.
pub fn restore() {
    if ACTIVE.swap(false, Ordering::SeqCst) {
        let mut out = io::stdout();
        if IMAGE.swap(false, Ordering::SeqCst) {
            let _ = out.write_all(DELETE_IMAGE.as_bytes());
        }
        let _ = execute!(out, PopKeyboardEnhancementFlags, cursor::Show, LeaveAlternateScreen);
        let _ = terminal::disable_raw_mode();
    }
}

pub struct Term {
    prev: Option<Frame>,
    prev_image: Option<Vec<Rgb>>,
    image_id: u32, // 1 or 2: each picture is a new image, and the old one is deleted after it is shown (the same id flashes)
    pub truecolor: bool,
    pub enhanced: bool,
}

/// Kitty or Ghostty (they have the kitty graphics protocol and draw the octant block characters), and not inside tmux or screen (which
/// hide the terminal that is behind them and do not pass images on).
pub fn detect_kitty() -> bool {
    let var = |k: &str| std::env::var(k).unwrap_or_default();
    let mux = std::env::var_os("TMUX").is_some() || var("TERM").starts_with("screen");
    let kitty = var("TERM") == "xterm-kitty" || std::env::var_os("KITTY_WINDOW_ID").is_some();
    let ghostty = var("TERM_PROGRAM") == "ghostty" || std::env::var_os("GHOSTTY_RESOURCES_DIR").is_some();
    !mux && (kitty || ghostty)
}

impl Term {
    pub fn new() -> io::Result<Term> {
        terminal::enable_raw_mode()?;
        let mut out = io::stdout();
        execute!(out, EnterAlternateScreen, cursor::Hide)?;
        ACTIVE.store(true, Ordering::SeqCst);
        let enhanced = terminal::supports_keyboard_enhancement().unwrap_or(false);
        if enhanced {
            execute!(out, PushKeyboardEnhancementFlags(KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES | KeyboardEnhancementFlags::REPORT_EVENT_TYPES))?;
        }
        let ct = std::env::var("COLORTERM").unwrap_or_default();
        let truecolor = ct.contains("truecolor") || ct.contains("24bit");
        let prev_hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            restore();
            prev_hook(info);
        }));
        Ok(Term { prev: None, prev_image: None, image_id: 1, truecolor, enhanced })
    }

    /// The size of a cell in pixels, or (0, 0) when the terminal does not tell.
    pub fn cell_px(&self) -> (usize, usize) {
        match terminal::window_size() {
            Ok(w) if w.columns > 0 && w.rows > 0 => (w.width as usize / w.columns as usize, w.height as usize / w.rows as usize),
            _ => (0, 0),
        }
    }

    pub fn size(&self) -> (usize, usize) {
        let (c, r) = terminal::size().unwrap_or((80, 24));
        (c as usize, r as usize)
    }

    /// Forget the last frame: the next one is written whole (after a resize, or after a message that covered the screen).
    pub fn invalidate(&mut self) {
        self.prev = None;
        self.prev_image = None;
        if IMAGE.swap(false, Ordering::SeqCst) {
            let _ = io::stdout().write_all(DELETE_IMAGE.as_bytes());
        }
        let _ = execute!(io::stdout(), terminal::Clear(terminal::ClearType::All));
    }

    /// Write the cells that differ from the last frame, in one write.
    pub fn present(&mut self, f: Frame) -> io::Result<()> {
        let mut s = String::with_capacity(16 * 1024);
        let full = match &self.prev {
            Some(p) => p.cols != f.cols || p.rows != f.rows,
            None => true,
        };
        let mut cur: Option<(Rgb, Rgb, bool)> = None;
        let mut at: Option<(usize, usize)> = None; // where the cursor is after the last cell
        for y in 0..f.rows {
            for x in 0..f.cols {
                let c = f.cells[y * f.cols + x];
                if !full && self.prev.as_ref().map(|p| p.cells[y * f.cols + x] == c).unwrap_or(false) {
                    continue;
                }
                if at != Some((x, y)) {
                    let _ = write!(s, "\x1b[{};{}H", y + 1, x + 1);
                }
                if cur != Some((c.fg, c.bg, c.clear)) {
                    self.colors(&mut s, &c);
                    cur = Some((c.fg, c.bg, c.clear));
                }
                s.push(c.ch);
                at = Some((x + 1, y));
            }
        }
        if !s.is_empty() {
            s.push_str("\x1b[0m");
            let mut out = io::stdout().lock();
            out.write_all(s.as_bytes())?;
            out.flush()?;
        }
        self.prev = Some(f);
        Ok(())
    }

    /// Show the canvas as an image whose top left corner is the cell (col, row), under the text. The picture is a new image (the id
    /// alternates), and the old one is deleted after it: with the same id some terminals delete the old picture first and flash.
    /// Call it after `present`. It sends nothing when the picture has not changed.
    pub fn present_image(&mut self, cv: &Canvas, col: usize, row: usize) -> io::Result<()> {
        if self.prev_image.as_deref() == Some(&cv.px[..]) {
            return Ok(());
        }
        let old = self.image_id;
        self.image_id = 3 - old;
        let mut s = image_command(cv, col, row, self.image_id);
        if self.prev_image.is_some() {
            let _ = write!(s, "\x1b_Ga=d,d=I,i={},q=2\x1b\\", old);
        }
        let mut out = io::stdout().lock();
        out.write_all(s.as_bytes())?;
        out.flush()?;
        IMAGE.store(true, Ordering::SeqCst);
        self.prev_image = Some(cv.px.clone());
        Ok(())
    }

    fn colors(&self, s: &mut String, c: &Cell) {
        if c.clear {
            // the default background: the image under the cell shows through
            if self.truecolor {
                let _ = write!(s, "\x1b[38;2;{};{};{}m\x1b[49m", c.fg[0], c.fg[1], c.fg[2]);
            } else {
                let _ = write!(s, "\x1b[38;5;{}m\x1b[49m", nearest_256(c.fg));
            }
        } else if self.truecolor {
            let _ = write!(s, "\x1b[38;2;{};{};{};48;2;{};{};{}m", c.fg[0], c.fg[1], c.fg[2], c.bg[0], c.bg[1], c.bg[2]);
        } else {
            let _ = write!(s, "\x1b[38;5;{};48;5;{}m", nearest_256(c.fg), nearest_256(c.bg));
        }
    }
}

impl Drop for Term {
    fn drop(&mut self) {
        restore();
    }
}

/// The escape sequences of the kitty graphics protocol for a canvas: 24 bit RGB, zlib, base64, in chunks of 4096 bytes. `z` below -2^30 puts the
/// image under the cell backgrounds, so the boxes of the messages are drawn over it; `C=1` leaves the cursor where it is.
pub fn image_command(cv: &Canvas, col: usize, row: usize, id: u32) -> String {
    let mut raw = Vec::with_capacity(cv.px.len() * 3);
    for p in &cv.px {
        raw.extend_from_slice(p);
    }
    let b64 = base64(&miniz_oxide::deflate::compress_to_vec_zlib(&raw, 1));
    let mut s = format!("\x1b[{};{}H", row + 1, col + 1);
    let chunks: Vec<&str> = b64.as_bytes().chunks(4096).map(|c| std::str::from_utf8(c).unwrap()).collect();
    for (i, c) in chunks.iter().enumerate() {
        let more = if i + 1 < chunks.len() { 1 } else { 0 };
        if i == 0 {
            let _ = write!(s, "\x1b_Ga=T,f=24,s={},v={},o=z,i={},p=1,q=2,C=1,z=-1073741825,m={};{}\x1b\\", cv.w, cv.h, id, more, c);
        } else {
            let _ = write!(s, "\x1b_Gm={};{}\x1b\\", more, c);
        }
    }
    s
}

pub fn base64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::with_capacity((data.len() + 2) / 3 * 4);
    for c in data.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        s.push(T[(n >> 18) as usize & 63] as char);
        s.push(T[(n >> 12) as usize & 63] as char);
        s.push(if c.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' });
        s.push(if c.len() > 2 { T[n as usize & 63] as char } else { '=' });
    }
    s
}

/// The nearest colour of the 256 colour palette: the 6 x 6 x 6 cube or the 24 greys.
pub fn nearest_256(c: Rgb) -> u8 {
    let level = |v: u8| -> u32 { if v < 48 { 0 } else if v < 115 { 1 } else { (v as u32 - 35) / 40 } };
    let (r, g, b) = (level(c[0]), level(c[1]), level(c[2]));
    let cube = |l: u32| -> i32 { if l == 0 { 0 } else { 55 + 40 * l as i32 } };
    let cube_idx = 16 + 36 * r + 6 * g + b;
    let d_cube = (cube(r) - c[0] as i32).pow(2) + (cube(g) - c[1] as i32).pow(2) + (cube(b) - c[2] as i32).pow(2);
    let avg = (c[0] as i32 + c[1] as i32 + c[2] as i32) / 3;
    let gi = ((avg - 8).max(0) / 10).min(23);
    let gv = 8 + 10 * gi;
    let d_grey = (gv - c[0] as i32).pow(2) + (gv - c[1] as i32).pow(2) + (gv - c[2] as i32).pow(2);
    if d_grey < d_cube { (232 + gi) as u8 } else { cube_idx as u8 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_known() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn image_chunks() {
        let mut cv = Canvas { w: 64, h: 64, px: vec![[0, 0, 0]; 64 * 64] };
        for (i, p) in cv.px.iter_mut().enumerate() {
            *p = [(i * 7) as u8, (i * 13 >> 3) as u8, (i * 31 >> 5) as u8]; // not flat: several chunks
        }
        let s = image_command(&cv, 4, 2, 2);
        assert!(s.starts_with("\x1b[3;5H\x1b_Ga=T,f=24,s=64,v=64,o=z,i=2,p=1,q=2,C=1,z=-1073741825,m=1;"));
        let cmds: Vec<&str> = s.split("\x1b_G").skip(1).collect();
        assert!(cmds.len() > 1);
        for (i, c) in cmds.iter().enumerate() {
            let (head, body) = c.split_once(';').unwrap();
            assert!(body.ends_with("\x1b\\") && body.len() - 2 <= 4096);
            assert!(head.ends_with(if i + 1 < cmds.len() { "m=1" } else { "m=0" }));
        }
    }

    #[test]
    fn palette() {
        assert_eq!(nearest_256([0, 0, 0]), 16);
        assert_eq!(nearest_256([255, 255, 255]), 231);
        assert_eq!(nearest_256([255, 0, 0]), 196);
        assert!((232..=255).contains(&nearest_256([128, 128, 128])));
    }
}
