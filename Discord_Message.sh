#!/bin/bash

# シンボリックリンクを解決して、このスクリプトの実体があるディレクトリの絶対パスを取得するのじゃ
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # -h オプションでシンボリックリンクをチェックじゃ
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    # リンク先が相対パスじゃったら、解決済みのディレクトリと結合するのじゃ
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

ENV_FILE="$SCRIPT_DIR/.env"

# 通常のヘルプメッセージを表示する関数
show_help() {
    cat <<EOF
Usage: $(basename "$0") [options] <message>

Description:
    引数で渡されたメッセージをDiscordの特定のWebhook URLに送信します。
    このスクリプトは .env ファイルから DISCORD_WEBHOOK_URL を読み込みます。
    複数の引数を指定した場合、それらは改行で連結されて一つのメッセージとして送信されます。

Arguments:
    message       Discordに送信するメッセージ文字列。

Options:
    -m, --mention 送信時に自分のDiscordユーザーIDでメンションを付加します。
                  メッセージ内の '@me' または '<@me>' も自動的に自身のメンションに置換されます。
                  ※IDは .env の DISCORD_USER_ID または git config --global discord.userid から読み込みます。
    -d, --dry-run 実際にDiscordへ送信せず、生成されるメッセージのペイロードを標準出力に表示します。
    -h, --help    このヘルプメッセージを表示して終了します。
EOF
}

# .envファイルのセットアップ方法を表示する関数じゃ
show_env_setup_help() {
    cat <<EOF
--------------------------------------------------
エラー: 設定ファイル (.env) が見つからんぞ！
--------------------------------------------------
スクリプトと同じ階層に.envファイルが必要じゃ。
以下のコマンドを使えば一発で作成できるぞ。
(実行する場所ではなく、スクリプトのある場所 '${SCRIPT_DIR}' に作成されるぞ)

【作成コマンド】
下のコマンドの各値を書き換えて、そのままターミナルに貼り付けて実行するのじゃ！

    cat << 'INNER_EOF' > "${ENV_FILE}"
DISCORD_WEBHOOK_URL="ここにそなたのWebhook URLを貼る"
DISCORD_USER_ID="ここにそなたのDiscordユーザーIDを貼る（任意）"
INNER_EOF

--------------------------------------------------
【重要】
.envファイルを作成したら、必ず.gitignoreに以下の1行を追加するのを忘れるな！
    .env
--------------------------------------------------
EOF
}

# オプション解析用の変数初期化
MENTION=false
DRY_RUN=false
ARG_MESSAGE=()

# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--mention)
            MENTION=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            ARG_MESSAGE+=("$1")
            shift
            ;;
    esac
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

require_commands curl grep sed xargs readlink

# メッセージ引数がない場合はヘルプを表示して終了
if [ ${#ARG_MESSAGE[@]} -eq 0 ]; then
    echo "エラー: 送信するメッセージがありません。" >&2
    show_help
    exit 1
fi

# スクリプト自身の隣にある.envファイルを探すように変更したぞ
if [ ! -f "$ENV_FILE" ]; then
    show_env_setup_help
    exit 1
fi

# ここもフルパスで.envファイルを指定するのじゃ
export $(grep -v '^#' "$ENV_FILE" | grep -v '^$' | xargs)

# 環境変数にWebhook URLが設定されているか確認じゃ
if [ -z "$DISCORD_WEBHOOK_URL" ]; then
    echo "エラー: ${ENV_FILE} にDISCORD_WEBHOOK_URLが設定されておらん！" >&2
    exit 1
fi

# DISCORD_USER_IDの取得
# 1. すでに環境変数にあるか、.envから読み込まれていればそれを使う
# 2. なければ git config から取得を試みる
if [ -z "$DISCORD_USER_ID" ]; then
    DISCORD_USER_ID=$(git config --global discord.userid 2>/dev/null)
fi

# 受け取ったメッセージ用引数を改行でつないで一つのメッセージにするのじゃ
MESSAGE=""
for arg in "${ARG_MESSAGE[@]}"; do
    MESSAGE="$MESSAGE$arg"$'\n'
done
MESSAGE="${MESSAGE%$'\n'}"

# プレースホルダーの置換（@me と <@me> を <@DISCORD_USER_ID> に置換）
if [ -n "$DISCORD_USER_ID" ]; then
    MESSAGE="${MESSAGE//<@me>/<@$DISCORD_USER_ID>}"
    MESSAGE="${MESSAGE//@me/<@$DISCORD_USER_ID>}"
fi

# -m / --mention オプションが指定された場合、メッセージの先頭にメンションを追加する
if [ "$MENTION" = true ]; then
    if [ -n "$DISCORD_USER_ID" ]; then
        MESSAGE="<@$DISCORD_USER_ID> $MESSAGE"
    else
        echo "警告: メンションが指定されましたが、DISCORD_USER_IDが設定されていません。" >&2
    fi
fi

# メッセージ内の特殊文字をJSONエスケープするのじゃ
# 1. バックスラッシュ (\) -> (\\)
MESSAGE="${MESSAGE//\\/\\\\}"
# 2. ダブルクォート (") -> (\")
MESSAGE="${MESSAGE//\"/\\\"}"
# 3. 改行 (\n) -> (\n)
MESSAGE="${MESSAGE//$'\n'/\\n}"
# 4. キャリッジリターン (\r) -> (\r)
MESSAGE="${MESSAGE//$'\r'/\\r}"
# 5. タブ (\t) -> (\t)
MESSAGE="${MESSAGE//$'\t'/\\t}"

if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN ---"
    echo "Webhook URL: $DISCORD_WEBHOOK_URL"
    echo "Payload: {\"content\": \"$MESSAGE\"}"
else
    # curlコマンドでDiscordに送信じゃ
    curl \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"$MESSAGE\"}" \
        "$DISCORD_WEBHOOK_URL"
fi
