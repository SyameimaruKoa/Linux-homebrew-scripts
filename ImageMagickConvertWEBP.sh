#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0") [Options]

Description:
    カレントディレクトリ以下の画像ファイル (jpg, jpeg, png, bmp) を再帰的に検索し、WebP形式に変換します。
    変換後、元のファイルは削除されます。
    変換品質はスクリプト内で quality=70 に設定されています。

Options:
    -h, --help      このヘルプメッセージを表示して終了します。
    -l, --lossless  PNGおよびBMPファイルのみを検索し、ロスレス圧縮（可逆圧縮）モードで変換します。
EOF
}

lossless_opt=0

# 引数の解析
for arg in "$@"; do
    if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
        show_help
        exit 0
    elif [[ "$arg" == "-l" ]] || [[ "$arg" == "--lossless" ]]; then
        lossless_opt=1
    fi
done

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

# 必須コマンド
require_commands convert cwebp find xargs nproc

current_dir=$(pwd)

echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"
echo "現在はここにいます"
echo "$current_dir"
echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"

#コンバート品質
quality=70
#アウトプット拡張子
output_extension=webp

filePattern1="*.jpg"
filePattern2="*.jpeg"
filePattern3="*.png"
filePattern4="*.bmp"

# ---------------------------------------------------------
# 並列処理のために while read 内の処理を関数として定義する
# ---------------------------------------------------------
process_image() {
    local fname="$1"
    local lossless_opt="$2"
    local quality="$3"
    local output_extension="$4"

    # 拡張子を除いたベース名を取得
    local base="${fname%.*}"
    local outputfile="${base}.$output_extension"
    local fileNum=0
    
    # 安全な重複チェック処理
    while [ -e "$outputfile" ]; do
        fileNum=$((fileNum + 1))
        outputfile="${base}_${fileNum}.$output_extension"
    done
    
    echo "───────────────ファイル情報───────────────"
    echo "インプットファイル名：$fname"
    echo "アウトプットファイル名：$outputfile"
    echo "────────────────────────────────────────"
    
    #magick & cwebp
    if [ "$lossless_opt" -eq 1 ]; then
        # 並列時にログが混ざらないよう -quiet を付与
        cwebp -quiet -lossless -q "$quality" -metadata all "$fname" -o "$outputfile" &&
            touch -cr "$fname" "$outputfile" &&
            rm "$fname"
    else
        convert -define webp:thread-level=1 -quality "$quality" "$fname" "$outputfile" &&
            touch -cr "$fname" "$outputfile" &&
            rm "$fname"
    fi
}
# 1回の走査で対象を拾い、NUL区切りで特殊文字を含むファイル名も安全に渡す。
# ロスレス時は検索段階で JPG/JPEG を除外する。
export lossless_opt quality output_extension
export -f process_image
if [ "$lossless_opt" -eq 1 ]; then
    patterns=( -iname "$filePattern3" -o -iname "$filePattern4" )
else
    patterns=( -iname "$filePattern1" -o -iname "$filePattern2" -o -iname "$filePattern3" -o -iname "$filePattern4" )
fi
find . -type f \( "${patterns[@]}" \) -print0 |
    xargs -0 -r -P "$(nproc)" -n 16 bash -c '
        for fname do
            process_image "$fname" "$lossless_opt" "$quality" "$output_extension"
        done
    ' _

Koa_Discord_Message.sh "$(hostname)で画像変換の実行が終わりました。 実行場所：$current_dir"
