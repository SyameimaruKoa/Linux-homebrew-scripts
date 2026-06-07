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
    -l, --lossless  PNGおよびBMPファイルのみを対象とし、ロスレス圧縮（可逆圧縮）モードで変換します。（JPG/JPEGはスキップされます）
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

# 必須コマンドに xargs と nproc を追加
require_commands convert cwebp find tr xargs nproc

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

    if [ "${fname}" = . ]; then
        echo 処理を始めます
        return
    fi

    echo "$fname" | grep -q "^/" && fname="."$fname
    
    # 拡張子を除いたベース名を取得
    local base="${fname%.*}"
    local outputfile="${base}.$output_extension"
    local fileNum=0
    
    # 安全な重複チェック処理
    while [ -e "$outputfile" ]; do
        fileNum=$((fileNum + 1))
        outputfile="${base}_${fileNum}.$output_extension"
    done
    
    # 拡張子を取得して小文字化
    local ext="${fname##*.}"
    local ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    # ロスレスモード時、非可逆圧縮フォーマットはスキップ
    if [ "$lossless_opt" -eq 1 ] && { [ "$ext_lower" = "jpg" ] || [ "$ext_lower" = "jpeg" ]; }; then
        echo "$fname は非可逆圧縮フォーマットのためスキップします"
        return
    fi
    
    echo "───────────────ファイル情報───────────────"
    echo "インプットファイル名：$fname"
    echo "アウトプットファイル名：$outputfile"
    echo "────────────────────────────────────────"
    
    #magick & cwebp
    if [ "$lossless_opt" -eq 1 ] && { [ "$ext_lower" = "png" ] || [ "$ext_lower" = "bmp" ]; }; then
        # 並列時にログが混ざらないよう -quiet を付与
        cwebp -quiet -lossless -q $quality -mt -metadata all "$fname" -o "$outputfile" &&
            touch -cr "$fname" "$outputfile" &&
            rm "$fname"
    else
        convert -define webp:thread-level=1 -quality $quality "$fname" "$outputfile" &&
            touch -cr "$fname" "$outputfile" &&
            rm "$fname"
    fi
}
# サブプロセス（xargs）から呼び出せるように関数をエクスポート
export -f process_image

# maxdepthを取り払い、グループ化して再帰処理に対応
find . -type f \( -iname "$filePattern1" \
    -or -iname "$filePattern2" \
    -or -iname "$filePattern3" \
    -or -iname "$filePattern4" \) |
    xargs -d '\n' -P $(nproc) -I {} bash -c 'process_image "$@"' _ {} "$lossless_opt" "$quality" "$output_extension"

Koa_Discord_Message.sh "$(hostname)で画像変換の実行が終わりました。 実行場所：$current_dir"
