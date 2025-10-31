#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0") <target_folder>

Description:
    指定したフォルダ内の全てのファイルとフォルダを、一つ上の階層（カレントディレクトリ）に移動します。
    その後、空になった指定フォルダを削除します。

Arguments:
    target_folder   中身を移動させたいフォルダの名前。

Options:
    -h, --help      このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 引数がない場合はヘルプを表示して終了
if [ -z "$1" ]; then
    echo "エラー: 対象フォルダが指定されていません。" >&2
    show_help
    exit 1
fi

# 対象フォルダを指定
target_folder="$1"

# フォルダの存在確認
if [ ! -d "$target_folder" ]; then
    echo "エラー: 指定されたフォルダ '$target_folder' が見つかりません。" >&2
    exit 1
fi

# 対象フォルダ内のファイルを全て一つ上のフォルダに移動
# * だと隠しファイルが移動されないので A と .[^.]* を使う
for file in "$target_folder"/{,.[^.]}*; do
    # ファイルが存在するか確認（空フォルダ対策）
    if [ -e "$file" ]; then
        mv "$file" .
    fi
done

# 空になったフォルダを削除
rmdir "$target_folder"
