#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0") <input_extension> [output_path]

Description:
    カレントディレクトリにある指定された拡張子の動画ファイルのうち、
    HEVCコーデックではないファイルを指定されたフォルダに移動します。

Arguments:
    input_extension   処理対象のファイルの拡張子 (例: mp4, mkv)。
    output_path       ファイルの移動先フォルダ名 (任意、デフォルト: Move)。

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

#インプット拡張子
input_extension=$1
#アウトプット拡張子
output_extension=mp4

#アウトプットパス
if [[ -z "$2" ]]; then
    outputpath=Move
else
    echo "アウトプットパスを設定します"
    echo "$2"
    outputpath="$2"
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
        #HEVCファイルでない場合、移動する
        echo "HEVCコーデックではありません。移動します。"
        mkdir -p "$outputpath"
        mv "$inputfilename" "$outputpath/$inputfilename"
    fi
done
echo "出力先のフォルダを削除します(空フォルダ削除用)"
rmdir --ignore-fail-on-non-empty "$outputpath"
Discord_Message.sh "$(hostname)でffmpegの実行が終わりました。 実行場所：$current_dir"