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
# --- Gist へのバックアップ処理 ---
backup_to_gist() {
    local env_file="$1"
    local run_user="$2"
    local user_home="$3"
    
    # 引数が足りない場合のフォールバック
    if [ -z "$user_home" ]; then
        user_home=$(getent passwd "$run_user" | cut -d: -f6)
        if [ -z "$user_home" ]; then
            user_home="$HOME"
        fi
    fi
    local gist_url=""
    local use_gh=false

    # 一般ユーザー権限で gh コマンドがインストールされ、かつ gh にログインしている場合のみ自動作成を試みる
    if sudo -u "$run_user" env HOME="$user_home" command -v gh >/dev/null 2>&1 && \
       sudo -u "$run_user" env HOME="$user_home" gh auth status >/dev/null 2>&1; then
        use_gh=true
    fi

    if [ "$use_gh" = true ]; then
        echo "GitHub CLI (gh) を使用して Secret Gist を自動作成中..."
        gist_url=$(sudo -u "$run_user" env HOME="$user_home" gh gist create -f ".env.homebrew-scripts" -d "Discord environment variables for homebrew-scripts" < "$env_file" 2>/dev/null)
        
        if [ -n "$gist_url" ]; then
            echo "-> Secret Gist の自動作成に成功しました！"
            echo "   URL: $gist_url"
            local gist_id
            gist_id=$(echo "$gist_url" | grep -oE '[a-fA-F0-9]{32,}' || echo "$gist_url")
            sudo -u "$run_user" env HOME="$user_home" git config --global discord.envgist "$gist_id"
            echo "-> Gist ID を Git グローバル設定 (discord.envgist) に保存しました。"
            return 0
        else
            echo "警告: gh コマンドによる Gist の自動作成に失敗しました。"
        fi
    else
        echo "GitHub CLI (gh) がインストールされていないか、ログインしていません（または sudo による keyring アクセス制限のため認証情報にアクセスできません）。"
        echo "※ gh にログインしているのにこのエラーが出る場合は、以下のコマンドで gh のセキュアストレージを無効化（ファイル保存へ変更）して再ログインしてください："
        echo "   gh config set secure_auth false && gh auth login"
    fi

    # gh があるがログインしていない、または認証エラーの場合の手動トークン入力フロー
    if sudo -u "$run_user" env HOME="$user_home" command -v gh >/dev/null 2>&1; then
        echo "--------------------------------------------------"
        echo "GitHub CLI (gh) はインストールされています。"
        echo "GitHub のパーソナルアクセストークン (PAT) を使用して Gist を作成できます。"
        echo "※ トークンには 'gist' スコープが必要です。"
        echo "--------------------------------------------------"
        local use_pat=""
        read -p "GitHub パーソナルアクセストークン (PAT) を入力して Gist を作成しますか？ (y/N): " use_pat
        if [[ "$use_pat" =~ ^[Yy]$ ]]; then
            local pat_token=""
            read -s -p "GitHub トークンを入力してください: " pat_token
            echo "" # 改行
            if [ -n "$pat_token" ]; then
                echo "トークンを使用して Secret Gist を作成中..."
                gist_url=$(sudo -u "$run_user" env HOME="$user_home" GH_TOKEN="$pat_token" gh gist create -f ".env.homebrew-scripts" -d "Discord environment variables for homebrew-scripts" < "$env_file" 2>/dev/null)
                if [ -n "$gist_url" ]; then
                    echo "-> Secret Gist の作成に成功しました！"
                    echo "   URL: $gist_url"
                    local gist_id
                    gist_id=$(echo "$gist_url" | grep -oE '[a-fA-F0-9]{32,}' || echo "$gist_url")
                    sudo -u "$run_user" env HOME="$user_home" git config --global discord.envgist "$gist_id"
                    echo "-> Gist ID を Git グローバル設定 (discord.envgist) に保存しました。"
                    return 0
                else
                    echo "エラー: トークンを使用した Gist の作成に失敗しました。"
                fi
            fi
        fi
    fi

    # 完全に手動で作成する場合の案内
    echo "--------------------------------------------------"
    echo "手動で Secret Gist を作成し、その URL または ID を登録してください。"
    echo "手順:"
    echo "  1. ブラウザで https://gist.github.com/ にアクセスします。"
    echo "  2. Filename including extension... に「.env.homebrew-scripts」と入力します。"
    echo "  3. ファイルの内容として以下を貼り付けます:"
    echo "--------------------------------------------------"
    cat "$env_file"
    echo "--------------------------------------------------"
    echo "  4. 「Create secret gist」ボタンをクリックして作成します（公開しないようご注意ください）。"
    echo "  5. 作成後、ブラウザのアドレスバーから URL をコピーします。"
    echo "--------------------------------------------------"
    
    local input_gist=""
    read -p "作成した Gist の URL または ID を入力してください (スキップするには Enter): " input_gist
    if [ -n "$input_gist" ]; then
        local gist_id
        gist_id=$(echo "$input_gist" | grep -oE '[a-fA-F0-9]{32,}' || echo "$input_gist")
        sudo -u "$run_user" env HOME="$user_home" git config --global discord.envgist "$gist_id"
        echo "-> Gist ID を Git グローバル設定 (discord.envgist) に保存しました。"
    else
        echo "Gist の登録をスキップしました。"
    fi
}

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

    local user_home
    user_home=$(getent passwd "$run_user" | cut -d: -f6)
    if [ -z "$user_home" ]; then
        user_home="$HOME"
    fi

    local restore_success=false

    # Git グローバル設定から Gist ID を取得
    local gist_id
    gist_id=$(sudo -u "$run_user" env HOME="$user_home" git config --global discord.envgist 2>/dev/null)

    # 一般ユーザー権限で gh コマンドがインストールされ、かつ gh にログインしている場合のみ Gist 復元を試みる
    local gh_available=false
    if sudo -u "$run_user" env HOME="$user_home" command -v gh >/dev/null 2>&1 && \
       sudo -u "$run_user" env HOME="$user_home" gh auth status >/dev/null 2>&1; then
        gh_available=true
    fi

    # Gist ID が登録されていない場合、入力を促す
    if [ -z "$gist_id" ]; then
        echo "--------------------------------------------------"
        echo "設定ファイル (.env) が見つかりません。"
        echo "GitHub Secret Gist から自動的に設定ファイルを復元できます。"
        echo "--------------------------------------------------"
        local input_gist=""
        read -p "すでに作成済みの Secret Gist ID (または URL) があれば入力してください (スキップして新規登録する場合は Enter): " input_gist
        if [ -n "$input_gist" ]; then
            # URLが入力された場合、ID部分(32桁以上の16進数)だけを抽出する
            gist_id=$(echo "$input_gist" | grep -oE '[a-fA-F0-9]{32,}' || echo "$input_gist")
            
            # Git グローバル設定に保存
            sudo -u "$run_user" env HOME="$user_home" git config --global discord.envgist "$gist_id"
            echo "Gist ID を Git グローバル設定 (discord.envgist) に保存しました。"
        fi
    fi

    if [ -n "$gist_id" ]; then
        echo "Secret Gist ($gist_id) から .env ファイルの復元を試みます..."

        if [ "$gh_available" = true ]; then
            # 通常の自動復元 (ghが使えてログイン済み)
            echo "GitHub CLI (gh) を使用してダウンロード中..."
            local tmp_env="/tmp/env_restore_$$"
            if sudo -u "$run_user" env HOME="$user_home" gh gist view "$gist_id" -f .env.homebrew-scripts > "$tmp_env" 2>/dev/null || \
               sudo -u "$run_user" env HOME="$user_home" gh gist view "$gist_id" -f .env > "$tmp_env" 2>/dev/null || \
               sudo -u "$run_user" env HOME="$user_home" gh gist view "$gist_id" > "$tmp_env" 2>/dev/null; then
                mv "$tmp_env" "$env_file"
                chmod 600 "$env_file"
                chown "$run_user:$run_user" "$env_file"
                echo "-> .env ファイルを正常に復元しました！"
                restore_success=true
            else
                rm -f "$tmp_env"
                echo "警告: gh コマンドによる Gist からの自動復元に失敗しました。"
            fi
        fi

        # 自動復元が失敗した、あるいは gh のログイン情報がない場合の手動/トークンフォールバック
        if [ "$restore_success" = false ]; then
            echo "--------------------------------------------------"
            echo "GitHub CLI (gh) による自動復元ができません（未インストール、未ログイン、または権限の問題）。"
            echo "※ gh にログインしているのにこのエラーが出る場合は、以下のコマンドで gh のセキュアストレージを無効化（ファイル保存へ変更）して再ログインしてください："
            echo "   gh config set secure_auth false && gh auth login"
            echo "--------------------------------------------------"
            echo "以下のいずれかの方法で Gist から設定を復元できます："
            echo "  1) GitHub パーソナルアクセストークン (PAT) を入力して gh でダウンロードする"
            echo "  2) ブラウザで Gist を開き、その内容を手動でここに貼り付ける"
            echo "  3) スキップして新規に設定ファイルを作成する"
            echo "--------------------------------------------------"
            
            local restore_choice=""
            read -p "選択してください (1/2/3): " restore_choice

            if [ "$restore_choice" = "1" ]; then
                if sudo -u "$run_user" env HOME="$user_home" command -v gh >/dev/null 2>&1; then
                    local pat_token=""
                    read -s -p "GitHub パーソナルアクセストークン (PAT) を入力してください: " pat_token
                    echo "" # 改行
                    if [ -n "$pat_token" ]; then
                        echo "トークンを使用して Secret Gist からダウンロード中..."
                        local tmp_env="/tmp/env_restore_$$"
                        if sudo -u "$run_user" env HOME="$user_home" GH_TOKEN="$pat_token" gh gist view "$gist_id" -f .env.homebrew-scripts > "$tmp_env" 2>/dev/null || \
                           sudo -u "$run_user" env HOME="$user_home" GH_TOKEN="$pat_token" gh gist view "$gist_id" -f .env > "$tmp_env" 2>/dev/null || \
                           sudo -u "$run_user" env HOME="$user_home" GH_TOKEN="$pat_token" gh gist view "$gist_id" > "$tmp_env" 2>/dev/null; then
                            mv "$tmp_env" "$env_file"
                            chmod 600 "$env_file"
                            chown "$run_user:$run_user" "$env_file"
                            echo "-> .env ファイルを正常に復元しました！"
                            restore_success=true
                        else
                            rm -f "$tmp_env"
                            echo "エラー: トークンを使用したダウンロードに失敗しました。"
                        fi
                    fi
                else
                    echo "エラー: GitHub CLI (gh) がインストールされていないため、トークンを使用したダウンロードは行えません。"
                fi
            elif [ "$restore_choice" = "2" ]; then
                echo "--------------------------------------------------"
                echo "手動貼り付け手順:"
                echo "  1. ブラウザで以下の URL にアクセスします："
                echo "     https://gist.github.com/$gist_id"
                echo "  2. 表示された内容（DISCORD_WEBHOOK_URL など）をすべてコピーします。"
                echo "  3. コピーした内容をここに貼り付け、最後に Ctrl+D を押してください。"
                echo "--------------------------------------------------"
                local tmp_env="/tmp/env_restore_$$"
                cat > "$tmp_env"
                if [ -s "$tmp_env" ]; then
                    mv "$tmp_env" "$env_file"
                    chmod 600 "$env_file"
                    chown "$run_user:$run_user" "$env_file"
                    echo "-> 貼り付けられた内容から .env ファイルを作成しました！"
                    restore_success=true
                else
                    rm -f "$tmp_env"
                    echo "エラー: 内容が空だったため、作成をスキップしました。"
                fi
            else
                echo "Gist からの復元をスキップします。"
            fi
        fi

        # 復元に成功した場合の Discord ユーザーIDの設定
        if [ "$restore_success" = true ] && [ -f "$env_file" ]; then
            # DiscordユーザーIDがグローバルに登録されていなければ登録を促す
            local discord_uid
            discord_uid=$(grep -E '^DISCORD_USER_ID=' "$env_file" | sed -E 's/^DISCORD_USER_ID=["'\'']?(.*)["'\'']?$/\1/')
            if [ -n "$discord_uid" ]; then
                local current_git_uid
                current_git_uid=$(sudo -u "$run_user" env HOME="$user_home" git config --global discord.userid 2>/dev/null)
                if [ -z "$current_git_uid" ]; then
                    sudo -u "$run_user" env HOME="$user_home" git config --global discord.userid "$discord_uid"
                    echo "-> DiscordユーザーID ($discord_uid) を Git グローバル設定 (discord.userid) に保存しました。"
                fi
            fi
        fi
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
            sudo -u "$run_user" env HOME="$user_home" git config --global discord.userid "$input_userid"
            echo "-> DiscordユーザーID ($input_userid) を Git グローバル設定 (discord.userid) に保存しました。"
        fi
        echo "--------------------------------------------------"

        # バックアップの確認
        local backup_confirm=""
        read -p "作成した設定 (.env) を GitHub Secret Gist にバックアップして、次回以降の自動復元に利用しますか？ (y/N): " backup_confirm
        if [[ "$backup_confirm" =~ ^[Yy]$ ]]; then
            backup_to_gist "$env_file" "$run_user" "$user_home"
        fi
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
