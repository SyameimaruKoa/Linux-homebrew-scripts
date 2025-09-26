#!/bin/bash
#
# このスクリプトは、スクリプト自身が置かれているディレクトリにある .sh ファイルの
# シンボリックリンクを /usr/local/bin に作成（接頭辞 "Koa_" を付与）、または削除します。
# 自分自身のスクリプトは対象外です。
#

# ヘルプメッセージを表示する関数
show_help() {
    cat << EOF
Usage: sudo $(basename "$0") [option]

Description:
  このスクリプトは、スクリプト自身が置かれているディレクトリにある '.sh' 拡張子を持つファイルへの
  シンボリックリンクを /usr/local/bin に作成、または削除します。
  このスクリプト自身は対象外となります。

Options:
  -i, --install   インストールモードで実行します。
                  シンボリックリンクは 'Koa_' という接頭辞付きで作成されます。
                  例: 'myscript.sh' -> '/usr/local/bin/Koa_myscript.sh'

  -u, --uninstall アンインストールモードで実行します。
                  このスクリプトのディレクトリ内のスクリプトに対応するシンボリックリンクを
                  /usr/local/bin から削除します。

  -h, --help      このヘルプメッセージを表示して終了します。

注意: このスクリプトはシステムのディレクトリに変更を加えるため、
      root権限（sudo）で実行する必要があります。
EOF
}

# --- メイン処理 ---

# rootユーザーで実行されているか確認
if [ "$(id -u)" -ne 0 ]; then
    echo "エラー: このスクリプトはroot権限で実行する必要があります。" >&2
    echo "コマンドの前に 'sudo' を付けて再実行してください。" >&2
    echo ""
    show_help
    exit 1
fi

# 自分自身のスクリプト名と、それが置かれているディレクトリの絶対パスを取得
self_name=$(basename "$0")
# readlink -f でシンボリックリンクを解決し、dirnameでディレクトリパスを取得
script_dir=$(dirname "$(readlink -f "$0")")


# --- インストール処理 ---
install_links() {
    echo "以下のスクリプトのシンボリックリンクを /usr/local/bin に作成します..."
    echo "(対象ディレクトリ: $script_dir)"
    echo "(接頭辞 'Koa_' が付きます)"
    echo "--------------------------------------------------"
    # 自分自身を除外してリスト表示
    find "$script_dir" -maxdepth 1 -type f -name '*.sh' -not -name "$self_name" -exec basename {} \;
    echo "--------------------------------------------------"
    read -p "よろしいですか？ (y/N): "

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "処理を中断しました。"
        exit 0
    fi

    # find を使って自分自身以外の .sh ファイルを安全に処理する
    find "$script_dir" -maxdepth 1 -type f -name "*.sh" -not -name "$self_name" -print0 | while IFS= read -r -d $'\0' file; do
        filename=$(basename "$file")
        linkname="Koa_$filename"
        echo "処理中: $filename -> $linkname"

        # 実行権限を付与
        chmod +x "$file"

        # /usr/local/bin にシンボリックリンクを作成
        # $file には既に絶対パスが入っている
        if ln -svf "$file" "/usr/local/bin/$linkname"; then
            echo " -> '$linkname' のシンボリックリンクを作成しました。"
        else
            echo " -> エラー: '$linkname' のシンボリックリンク作成に失敗しました。" >&2
        fi
    done
    echo "--------------------------------------------------"
    echo "すべての処理が完了しました。"
}

# --- アンインストール処理 ---
uninstall_links() {
    echo "以下のスクリプトに対応するシンボリックリンクを /usr/local/bin から削除します..."
    echo "(対象ディレクトリ: $script_dir)"
    echo "--------------------------------------------------"
    find "$script_dir" -maxdepth 1 -type f -name "*.sh" -not -name "$self_name" -print0 | while IFS= read -r -d $'\0' file; do
        filename=$(basename "$file")
        linkname="Koa_$filename"
        linkpath="/usr/local/bin/$linkname"
        if [ -L "$linkpath" ]; then
            echo "$linkname  (-> $(readlink "$linkpath"))"
        fi
    done
    echo "--------------------------------------------------"
    read -p "本当に削除しますか？ (y/N): "

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "処理を中断しました。"
        exit 0
    fi

    find "$script_dir" -maxdepth 1 -type f -name "*.sh" -not -name "$self_name" -print0 | while IFS= read -r -d $'\0' file; do
        filename=$(basename "$file")
        linkname="Koa_$filename"
        linkpath="/usr/local/bin/$linkname"

        if [ -L "$linkpath" ]; then
            echo "削除中: $linkname"
            if rm -v "$linkpath"; then
                echo " -> '$linkname' を削除しました。"
            else
                echo " -> エラー: '$linkname' の削除に失敗しました。" >&2
            fi
        fi
    done
    echo "--------------------------------------------------"
    echo "すべての処理が完了しました。"
}

# --- 引数に応じて処理を分岐 ---

# 対象の.shファイルが存在するか確認
if [ -z "$(find "$script_dir" -maxdepth 1 -type f -name '*.sh' -not -name "$self_name" -print -quit)" ]; then
    # アンインストール時にもメッセージが出ないように、引数がない場合のみメッセージを出す
    if [ -z "$1" ]; then
        echo ".sh ファイルが見つかりませんでした（このスクリプトを除く）。"
    fi
    # アンインストール対象がない場合もあるので、ここで終了するのはアンインストール時以外
    if [[ "$1" != "-u" && "$1" != "--uninstall" ]]; then
       exit 0
    fi
fi


case "$1" in
    -i|--install)
        install_links
        ;;
    -u|--uninstall)
        uninstall_links
        ;;
    -h|--help)
        show_help
        ;;
    "")
        echo "エラー: オプションが指定されていません。" >&2
        show_help
        exit 1
        ;;
    *)
        echo "エラー: 不明なオプションです: $1" >&2
        show_help
        exit 1
        ;;
esac

exit 0


