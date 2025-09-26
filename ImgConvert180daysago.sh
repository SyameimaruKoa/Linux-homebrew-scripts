#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
  cat << EOF
Usage: $(basename "$0")

Description:
  カレントディレクトリ内で180日以上前に更新された画像ファイル (jpg, jpeg, png, bmp) を
  WebP形式に変換します。変換後、元のファイルは削除されます。
  変換品質はスクリプト内で quality=90 に設定されています。

Options:
  -h, --help    このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  show_help
  exit 0
fi

current_dir=`pwd`

echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"
echo "現在はここにいます"
echo "$current_dir"
echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"

#コンバート品質
quality=90
#アウトプット拡張子
output_extension=webp

filePattern1="*.jpg"
filePattern2="*.jpeg"
filePattern3="*.png"
filePattern4="*.bmp"
find . -maxdepth 1 -iname "$filePattern1" \
-or -iname "$filePattern2" \
-or -iname "$filePattern3" \
-or -iname "$filePattern4" \
-mtime +180 \
| while read -r fname
do
if [ "${fname}" = . ]; then
echo 処理を始めます
else
  echo "$fname" | grep -q "^/" && fname="."$fname
  outputfile="${fname%.*}.$output_extension"
  fileNum=0
  while ls | grep -w "${outputfile##*/}" >/dev/null; do
   fileNum=`expr $fileNum + 1`
   outputfile=${outputfile/.webp}_${fileNum}.$output_extension
  done
 echo "───────────────ファイル情報───────────────"
 echo "インプットファイル名：$fname"
 echo "アウトプットファイル名：$outputfile"
 echo "────────────────────────────────────────"
   convert -quality $quality "$fname" "$outputfile"\
  && touch -cr "$fname" "$outputfile" \
  && rm "$fname"
fi
done
   
bash ~/shellscript/LINEmessage.sh "PI335でffmpegの実行が終わりました。 実行場所：$current_dir"
