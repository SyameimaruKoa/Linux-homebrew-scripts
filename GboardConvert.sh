#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0") <filepath>

Description:
    Gboard用の辞書ファイルと想定されるテキストファイル内の "ja-JP" という文字列を "名詞" に置換し、
    元のファイル名に "_convert" を付加した新しいファイルを作成します。

Arguments:
    filepath      処理対象のファイルパスを指定します。

Options:
    -h, --help    このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 引数がない場合はヘルプを表示して終了
if [ -z "$1" ]; then
    echo "エラー: ファイルパスが指定されていません。" >&2
    show_help
    exit 1
fi

# ファイルパスを取得
filepath=$1

# 拡張子を取得
extension="${filepath##*.}"

# 追加するファイル名を取得
addname=_convert

# 拡張子前に_convertを追加
new_filepath="${filepath%.*}$addname.${extension}"

# 新しいファイルパスを表示
echo "$new_filepath"

sed -e "s/	ja-JP/	名詞	/g" "$1" >>"$new_filepath"
