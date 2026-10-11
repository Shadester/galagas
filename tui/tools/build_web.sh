#!/bin/sh
# Build the WebAssembly module of the browser versions: docs/tui/galaga.wasm and docs/scope/galaga.wasm (committed, the same file). Needs: rustup target add wasm32-unknown-unknown
cd "$(dirname "$0")/.." || exit 1
cargo build --release --lib --no-default-features --target wasm32-unknown-unknown -q || exit 1
mkdir -p ../docs/tui ../docs/scope
cp target/wasm32-unknown-unknown/release/galaga_tui.wasm ../docs/tui/galaga.wasm
cp ../docs/tui/galaga.wasm ../docs/scope/galaga.wasm
ls -l ../docs/tui/galaga.wasm | awk '{print $5, "bytes: docs/tui/galaga.wasm"}'
