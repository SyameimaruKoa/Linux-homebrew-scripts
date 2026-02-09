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

shopt -s nullglob
for fn in *.png; do
    zopflipng -m "$fn" "${fn}.new" && mv -f "${fn}.new" "$fn"
done
