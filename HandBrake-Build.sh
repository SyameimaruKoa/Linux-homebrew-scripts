#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat << EOF
Usage: $(basename "$0")

Description:
    Windows向けのHandBrake CUIをビルドするための環境を構築し、ビルドを実行します。
    依存関係のインストール、MinGW-w64ツールチェーンのビルド、HandBrakeのビルドを自動で行います。
    実行にはsudo権限が必要です。

Options:
    -h, --help    このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

echo アップデート
sudo apt-get update
echo 依存関係をインストール
sudo apt install automake autoconf autopoint build-essential cmake gcc git intltool libtool libtool-bin m4 make meson nasm ninja-build patch pkg-config tar zlib1g-dev clang curl
curl https://sh.rustup.rs -sSf | sh
source "$HOME/.cargo/env"
cargo install cargo-c
rustup target add x86_64-pc-windows-gnu

echo MinGW-w64 ツールチェーン
sudo apt-get install bison bzip2 curl flex g++ gzip pax
echo ビルドするファイルをダウンロード
git clone https://github.com/HandBrake/HandBrake.git && cd HandBrake

echo MinGW-w64ツールチェーンビルド
scripts/mingw-w64-build x86_64 ~/toolchains/

HandBrake CUIをビルド
./configure --cross=x86_64-w64-mingw32 --launch-jobs=$(nproc) --enable-fdk-aac --launch
