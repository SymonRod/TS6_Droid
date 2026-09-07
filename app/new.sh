sudo pacman -R rust
sudo pacman -S rustup
rustup default stable
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk
