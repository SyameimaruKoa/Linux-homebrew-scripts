#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0") <input_extension> [output_path]

Description:
    カレントディレクトリにある指定された拡張子の動画ファイルをHEVC(QSV)にエンコードします。
    エンコード後、元のファイルは削除されます。
    既にHEVCコーデックのファイルはスキップされます。

Arguments:
    input_extension   エンコード対象のファイルの拡張子 (例: mov, avi, mp4)。
    output_path       エンコード後のファイルの出力先フォルダ名 (任意、デフォルト: ffmpeg)。

Options:
    -h, --help        このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 必須の引数がない場合はヘルプを表示して終了
if [ -z "$1" ]; then
    echo "エラー: インプット拡張子が指定されていません。" >&2
    show_help
    exit 1
fi

current_dir=$(pwd)

echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"
echo "現在はここにいます"
echo "$current_dir"
echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"

#エンコード品質
gq=35
#インプット拡張子
input_extension=$1
#アウトプット拡張子
output_extension=mp4

#アウトプットパス
if [[ -z "$2" ]]; then
    outputpath=ffmpeg
else
    echo "アウトプットパスを設定します"
    echo "$2"
    outputpath="$2"
fi

#HDDの断片化対策でエンコード先を変更変更して後に移動
if [ -d "/mnt/ramdisk" ]; then
    # /mnt/ramdisk が存在する場合の処理
    echo "一時アウトプットパスを/mnt/ramdisk/ffmpegに設定します"
    temppath=/mnt/ramdisk/ffmpeg
else
    # /mnt/ramdisk が存在しない場合の処理
    echo "一時アウトプットパスを/tmp/ffmpegに設定します"
    temppath=/tmp/ffmpeg
fi

#エンコードコマンド
for importfile in *.$input_extension; do
    [ ! -f "$importfile" ] && continue
    filename="${importfile%.$input_extension}"
    inputfilename="$filename.$input_extension"
    outputfilename="$filename.$output_extension"
    echo "───────────────ファイル情報───────────────"
    ffprobe -loglevel error -show_entries stream=codec_type,codec_name -of default=noprint_wrappers=1 -i "$inputfilename"
    echo "インプットファイル名：$inputfilename"
    echo "アウトプットファイル名：$outputfilename"
    echo "────────────────────────────────────────"
    if [[ $(ffprobe -loglevel error -show_entries stream=codec_type,codec_name -of default=noprint_wrappers=1 -i "$inputfilename" | grep -Po "(?<=codec_name=).*") =~ hevc ]]; then
        #何もせずに次のステップに進む
        echo "HEVCコーデックです。当ファイルをスキップします。"
    else
        #HEVCファイルでない場合、エンコードする
        echo "HEVCコーデックではありません。エンコードします。"
        mkdir -p "$outputpath"
        mkdir -p "$temppath"
        ffmpeg -nostdin -hide_banner -y -i "$inputfilename" -f ffmetadata "$temppath/$filename.metadata.txt"
        ffmpeg -nostdin -hide_banner -y -hwaccel_output_format qsv -i "$inputfilename" -i "$temppath/$filename.metadata.txt" -map_metadata 1 -c:v hevc_qsv -global_quality $gq -fps_mode passthrough -g 150 -qcomp 0.7 -qmin 10 -qmax 51 -qdiff 4 -subq 6 -me_range 16 -i_qfactor 0.714286 -map_chapters -1 -c:a copy "$temppath/$outputfilename" &&
            mv "$temppath/$outputfilename" "$outputpath/$outputfilename" &&
            touch -cr "$inputfilename" "$outputpath/$outputfilename" &&
            rm "$inputfilename"
        rm "$temppath/$filename.metadata.txt"
    fi
done
echo "出力先のffmepgフォルダを削除します(空フォルダ削除用)"
rmdir --ignore-fail-on-non-empty "$outputpath"
bash ~/shellscript/LINEmessage.sh "PI335でffmpegの実行が終わりました。 実行場所：$current_dir"
