#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0")

Description:
    カレントディレクトリ内で180日以上前に更新されたJPGファイル (*.jpg) を検索し、
    ファイルリストを "ls180.txt" に、カレントディレクトリの全ファイルリストを "lsフル.txt" に出力します。
    このスクリプトは画像の変換や削除は行いません。

Options:
    -h, --help    このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

current_dir=$(pwd)

echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"
echo "現在はここにいます"
echo "$current_dir"
echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"
ls -lh >"lsフル.txt"
#コンバート品質
quality=90
#アウトプット拡張子
output_extension=webp

filePattern1="*.jpg" # filePattern2が使われていないため、filePattern1のみに修正
find . -maxdepth 1 -iname "$filePattern1" \
    -mtime +180 |
    while read -r fname; do
        if [ "${fname}" = . ]; then
            echo 処理を始めます
        else
            echo "$fname" | grep -q "^/" && fname="."$fname
            outputfile="${fname%.*}.$output_extension"
            fileNum=0
            while ls | grep -w "${outputfile##*/}" >/dev/null; do
                fileNum=$(expr $fileNum + 1)
                outputfile=${outputfile/.webp/}_${fileNum}.$output_extension
            done
            ls -lh "$fname" >>"ls180.txt"
        fi
    done

Discord_Message.sh "$(hostname)でffmpegの実行が終わりました。 実行場所：$current_dir"