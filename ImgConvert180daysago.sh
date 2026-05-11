#!/bin/bash

show_help() {
    cat <<EOF
Usage: $(basename "$0")

Description:
    180日以上更新されていない画像をWebPに一括変換する。
    GNU Parallelを使用し、全CPUコアで並列処理を行うのじゃ。

Options:
    -h, --help    このヘルプを表示して終了する。
EOF
}

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

current_dir=$(pwd)
quality=90

# 1. 変換対象のファイルを検索
# 2. 検索結果をNULL文字区切りでParallelに渡す
# 3. Parallel内で変換・タイムスタンプ同期・削除を順に実行
find . -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" \) \
    -mtime +180 -print0 | \
    parallel -0 --jobs 100% \
        "magick -quality $quality {} {.}.webp && \
         touch -cr {} {.}.webp && \
         rm {}"

Discord_Message.sh "$(hostname)で画像変換が終わりました。 実行場所：$current_dir"
