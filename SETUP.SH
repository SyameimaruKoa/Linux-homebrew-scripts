#!/bin/bash
#
# このスクリプトは、スクリプト自身が置かれているディレクトリにある .sh ファイルの
# シンボリックリンクを /usr/local/bin に作成（接頭辞 "Koa_" を付与）、または削除します。
# 自分自身のスクリプトは対象外です。
#

# ヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: sudo $(basename "$0") [option]

Description:
    このスクリプトは、スクリプト自身が置かれているディレクトリにある '.sh' 拡張子を持つファイルへの
    シンボリックリンクを /usr/local/bin に作成、または削除します。
    このスクリプト自身は対象外となります。

Options:
    -i, --install   インストールモードで実行します。
                    まず、ディレクトリから削除されたスクリプトに対応する古いリンクを掃除してから、
                    現在のスクリプトのシンボリックリンクを作成・更新します。
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

require_commands id basename dirname readlink find ln chmod rm

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

# --- .env ファイルのセットアップ処理 ---
setup_env_file() {
    local env_file="$script_dir/.env"
    
    # すでに .env ファイルが存在する場合は何もしない
    if [ -f "$env_file" ]; then
        return 0
    fi

    # SUDO_USER が設定されているか確認 (sudo 経由で実行された場合の一般ユーザー)
    local run_user="$SUDO_USER"
    if [ -z "$run_user" ]; then
        run_user=$(whoami)
    fi

    local restore_success=false

    # 一般ユーザー権限で gh コマンドがインストールされ、かつ gh にログインしている場合のみ Gist 復元を試みる
    if sudo -u "$run_user" command -v gh >/dev/null 2>&1 && sudo -u "$run_user" gh auth status >/dev/null 2>&1; then
        echo "--------------------------------------------------"
        echo "設定ファイル (.env) が見つかりません。"
        echo "GitHub Secret Gist から自動的に設定ファイルを復元できます。"
        echo "--------------------------------------------------"

        # Git グローバル設定から Gist ID を取得
        local gist_id
        gist_id=$(sudo -u "$run_user" git config --global discord.envgist 2>/dev/null)

        if [ -z "$gist_id" ]; then
            echo "Git グローバル設定に自動復元用の Gist ID が登録されていません。"
            read -p "Secret Gist ID (または URL) を入力してください (スキップして新規登録する場合は Enter): " input_gist
            if [ -n "$input_gist" ]; then
                # URLが入力された場合、ID部分(32桁以上の16進数)だけを抽出する
                gist_id=$(echo "$input_gist" | grep -oE '[a-fA-F0-9]{32,}' || echo "$input_gist")
                
                # Git グローバル設定に保存
                sudo -u "$run_user" git config --global discord.envgist "$gist_id"
                echo "Gist ID を Git グローバル設定 (discord.envgist) に保存しました。"
            fi
        fi

        if [ -n "$gist_id" ]; then
            echo "Secret Gist ($gist_id) から .env ファイルをダウンロード中..."
            
            # gh gist view で取得し、一時ファイルに書き出してから移動 (権限設定のため)
            local tmp_env="/tmp/env_restore_$$"
            if sudo -u "$run_user" gh gist view "$gist_id" -f .env > "$tmp_env" 2>/dev/null || sudo -u "$run_user" gh gist view "$gist_id" > "$tmp_env" 2>/dev/null; then
                mv "$tmp_env" "$env_file"
                chmod 600 "$env_file"
                chown "$run_user:$run_user" "$env_file"
                echo "-> .env ファイルを正常に復元しました！"
                restore_success=true
                
                # DiscordユーザーIDがグローバルに登録されていなければ登録を促す
                export $(grep -v '^#' "$env_file" | grep -v '^$' | xargs)
                if [ -n "$DISCORD_USER_ID" ]; then
                    local current_git_uid
                    current_git_uid=$(sudo -u "$run_user" git config --global discord.userid 2>/dev/null)
                    if [ -z "$current_git_uid" ]; then
                        sudo -u "$run_user" git config --global discord.userid "$DISCORD_USER_ID"
                        echo "-> DiscordユーザーID ($DISCORD_USER_ID) を Git グローバル設定 (discord.userid) に保存しました。"
                    fi
                fi
            else
                rm -f "$tmp_env"
                echo "エラー: Gist からの復元に失敗しました。アクセス権または Gist ID を確認してください。"
                echo "※登録されている Gist ID を削除するには以下を実行してください:"
                echo "  git config --global --unset discord.envgist"
            fi
        fi
        echo "--------------------------------------------------"
    fi

    # Gist から復元できなかった場合は、手動で Discord 設定の登録を促す
    if [ "$restore_success" = false ]; then
        echo "--------------------------------------------------"
        echo "設定ファイル (.env) を手動で作成します。"
        echo "DiscordのWebhook URLとユーザーIDを登録してください。"
        echo "--------------------------------------------------"

        local input_webhook=""
        while [ -z "$input_webhook" ]; do
            read -p "Discord Webhook URL を入力してください (必須): " input_webhook
            if [ -z "$input_webhook" ]; then
                echo "エラー: Webhook URL は必須です。入力してください。"
            fi
        done

        local input_userid=""
        read -p "Discord ユーザーID を入力してください (任意、スキップするには Enter): " input_userid

        # .env ファイルの新規作成
        cat << EOF > "$env_file"
DISCORD_WEBHOOK_URL="$input_webhook"
DISCORD_USER_ID="$input_userid"
EOF
        
        # 権限と所有者の設定
        chmod 600 "$env_file"
        chown "$run_user:$run_user" "$env_file"
        echo "-> .env ファイルを作成し、保存しました！"

        # Discord ユーザーIDが入力された場合、Git グローバル設定にも保存
        if [ -n "$input_userid" ]; then
            sudo -u "$run_user" git config --global discord.userid "$input_userid"
            echo "-> DiscordユーザーID ($input_userid) を Git グローバル設定 (discord.userid) に保存しました。"
        fi
        echo "--------------------------------------------------"
    fi
}

# --- インストール処理 ---
install_links() {
    # --- .env セットアップ ---
    setup_env_file

    # --- クリーンアップ処理 ---
    echo "最初に、管理下から削除されたスクリプトの古いリンクをクリーンアップします..."
    cleaned_count=0
    # 現在のスクリプトのリストを連想配列に格納
    declare -A current_scripts
    for file in "$script_dir"/*.sh; do
        [ -f "$file" ] || continue
        current_scripts["$(basename "$file")"]=1
    done

    # /usr/local/bin にある Koa_* リンクをチェック
    for linkpath in /usr/local/bin/Koa_*.sh; do
        [ -L "$linkpath" ] || continue # シンボリックリンクでなければスキップ

        # リンクのターゲットがこのスクリプトの管理下にあるか確認
        if [[ "$(readlink -f "$linkpath")" == "$script_dir"/* ]]; then
            linkname=$(basename "$linkpath")
            sourcename=${linkname#Koa_}
            # 元のファイルが現在のスクリプトリストに存在しないなら、孤立リンクと判断
            if [[ ! -v current_scripts["$sourcename"] ]]; then
                echo "孤立したリンクを削除中: $linkname"
                if rm -v "$linkpath"; then
                    echo " -> 削除しました。"
                    ((cleaned_count++))
                else
                    echo " -> エラー: 削除に失敗しました。" >&2
                fi
            fi
        fi
    done

    if [ $cleaned_count -gt 0 ]; then
        echo "クリーンアップが完了しました。"
    else
        echo "クリーンアップ対象の古いリンクはありませんでした。"
    fi
    echo "--------------------------------------------------"
    echo ""

    # --- インストール本体 ---
    echo "以下のスクリプトのシンボリックリンクを /usr/local/bin に作成・更新します..."
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

        # /usr/local/bin にシンボリックリンクを作成（-f で上書き）
        # $file には既に絶対パスが入っている
        if ln -svf "$file" "/usr/local/bin/$linkname"; then
            echo " -> '$linkname' のシンボリックリンクを作成・更新しました。"
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
-i | --install)
    install_links
    ;;
-u | --uninstall)
    uninstall_links
    ;;
-h | --help)
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
