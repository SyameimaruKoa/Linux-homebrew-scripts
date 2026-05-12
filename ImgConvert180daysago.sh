#!/bin/bash

show_help() {
    cat <<EOF
Usage: $(basename "$0")

Description:
    180日以上更新されていない画像をWebPに一括変換するのじゃ。
    一時ファイルを /tmp に作成し、一度のスキャンで効率的に処理を行う。
    GNU Parallelを使用して全CPUコアで並列処理を行う。

Options:
    -h, --help    このヘルプを表示して終了する。
EOF
}

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

require_commands parallel magick find awk Discord_Message.sh

current_dir=$(pwd)
quality=90
days=180
threshold_sec=$((days * 86400))
current_time=$(date +%s)
limit_time=$((current_time - threshold_sec))

# 一時ファイルを /tmp に作成するのじゃ。XXXXXXはランダムな文字列に置き換わるぞ。
list_file=$(mktemp /tmp/img_convert_list.XXXXXX)
# 終了時やエラー時に必ず削除するように罠を張っておくのじゃ。
trap 'rm -f "$list_file"' EXIT

# --- 1回のスキャンで統計取得とリスト作成を同時にこなすのじゃ ---
stats=$(find . -maxdepth 1 -type f -printf "%T@ %p\n" | awk -v limit="$limit_time" -v list="$list_file" '
BEGIN {
    total_all = 0;
    total_ext = 0;
    total_target = 0;
}
{
    total_all++;
    # 拡張子判定（大文字小文字を問わずチェックじゃ）
    if ($2 ~ /\.(jpg|jpeg|png|bmp|JPG|JPEG|PNG|BMP)$/) {
        total_ext++;
        # 指定秒数より古いか判定
        if ($1 < limit) {
            total_target++;
            print $2 > list;
        }
    }
}
END {
    # カンマ区切りで値を返すのじゃ
    print total_all "," total_ext "," total_target;
}')

# 統計情報を変数に展開するのじゃ
IFS=',' read -r total_all total_ext total_target <<< "$stats"

echo "------------------------------------------"
echo "実行場所: $current_dir"
echo "全ファイル数（スキップ含め）: $total_all"
echo "対象拡張子ファイル総数      : $total_ext"
echo "変換対象ファイル数（${days}日前）: $total_target"
echo "------------------------------------------"

if [ "$total_target" -eq 0 ]; then
    echo "変換対象のファイルが見つからなかったのじゃ。処理を終了するぞ。"
    exit 0
fi

# /tmp に保存したリストを使って並列処理の開始じゃ
cat "$list_file" | parallel --jobs 100% -d '\n' \
    "magick -quality $quality {} {.}.webp && \
     touch -cr {} {.}.webp && \
     rm {}"

Koa_Discord_Message.sh \
    "$(hostname) での画像変換が完了したのじゃ！" \
    "実行場所：$current_dir" \
    "全ファイル数：$total_all" \
    "対象拡張子：$total_ext" \
    "変換実施数：$total_target"