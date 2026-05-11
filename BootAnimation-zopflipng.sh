#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0")

Description:
    カレントディレクトリにある全てのPNGファイル (*.png) をzopflipngを使って最適化します。
    このスクリプトは引数を必要としません。

Options:
    -h, --help    このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

require_commands() {
    local missing=0
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "エラー: 必須コマンド '$cmd' が見つかりません。" >&2
            missing=1
        fi
    done
    if [ "$missing" -ne 0 ]; then
        exit 1
    fi
}

require_commands zopflipng

shopt -s nullglob
for fn in *.png; do
    zopflipng -m "$fn" "${fn}.new" && mv -f "${fn}.new" "$fn"
done
