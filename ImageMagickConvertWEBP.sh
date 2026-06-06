#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0") [Options]

Description:
    カレントディレクトリにある画像ファイル (jpg, jpeg, png, bmp) をWebP形式に変換します。
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

require_commands convert find tr

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

find . -maxdepth 1 -iname "$filePattern1" \
    -or -iname "$filePattern2" \
    -or -iname "$filePattern3" \
    -or -iname "$filePattern4" |
    while read -r fname; do
        if [ "${fname}" = . ]; then
            echo 処理を始めます
        else
            echo "$fname" | grep -q "^/" && fname="."$fname
            outputfile="${fname%.*}.$output_extension"
            fileNum=0
            #while ls | grep -w "${outputfile##*/}" >/dev/null; do
            while ls | grep -F -w "${outputfile##*/}" >/dev/null; do
                fileNum=$(expr $fileNum + 1)
                outputfile=${outputfile/.webp/}_${fileNum}.$output_extension
            done
            
            # 拡張子を取得して小文字化
            ext="${fname##*.}"
            ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
            
            # ロスレスモード時、非可逆圧縮フォーマットはスキップ
            if [ "$lossless_opt" -eq 1 ] && { [ "$ext_lower" = "jpg" ] || [ "$ext_lower" = "jpeg" ]; }; then
                echo "$fname は非可逆圧縮フォーマットのためスキップします"
                continue
            fi
            
            echo "───────────────ファイル情報───────────────"
            echo "インプットファイル名：$fname"
            echo "アウトプットファイル名：$outputfile"
            echo "────────────────────────────────────────"
            
            #magick
            if [ "$lossless_opt" -eq 1 ] && { [ "$ext_lower" = "png" ] || [ "$ext_lower" = "bmp" ]; }; then
                convert -define webp:lossless=true -quality $quality "$fname" "$outputfile" &&
                    touch -cr "$fname" "$outputfile" &&
                    rm "$fname"
            else
                convert -quality $quality "$fname" "$outputfile" &&
                    touch -cr "$fname" "$outputfile" &&
                    rm "$fname"
            fi
        fi
    done

Koa_Discord_Message.sh "$(hostname)で画像変換の実行が終わりました。 実行場所：$current_dir"
