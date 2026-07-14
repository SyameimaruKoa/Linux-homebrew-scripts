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
Usage: $(basename "$0") [options] [<message>...]
       または標準入力からメッセージを渡すこともできます。

Description:
    引数で渡されたメッセージ、または標準入力から渡されたメッセージをDiscordの特定のWebhook URLに送信します。
    このスクリプトは .env ファイルから DISCORD_WEBHOOK_URL を読み込みます。
    複数の引数を指定した場合、それらは改行で連結されて一つのメッセージとして送信されます。
    引数が指定されず、かつ標準入力がパイプなどの場合は、標準入力からメッセージを読み込みます。

Arguments:
    message       Discordに送信するメッセージ文字列。

Options:
    -s, --stdin   標準入力からメッセージを強制的に読み込みます。
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
STDIN=false
ARG_MESSAGE=()

# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--stdin)
            STDIN=true
            shift
            ;;
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

# (メッセージの有無はメッセージ構築後にチェックするのじゃ)

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

# 引数か標準入力からメッセージを取得するのじゃ
if [ "$STDIN" = true ] || { [ ${#ARG_MESSAGE[@]} -eq 0 ] && [ ! -t 0 ]; }; then
    MESSAGE=$(cat)
else
    MESSAGE=""
    for arg in "${ARG_MESSAGE[@]}"; do
        MESSAGE="$MESSAGE$arg"$'\n'
    done
    MESSAGE="${MESSAGE%$'\n'}"
fi

# 送信するメッセージがない場合はヘルプを表示して終了するのじゃ
if [ -z "$MESSAGE" ]; then
    echo "エラー: 送信するメッセージがありません。" >&2
    show_help
    exit 1
fi

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

# ホスト名の取得とエスケープ（Webhookのユーザー名に指定するため）
HOST_NAME=$(hostname 2>/dev/null || echo "$HOSTNAME")
HOST_NAME="${HOST_NAME//\\/\\\\}"
HOST_NAME="${HOST_NAME//\"/\\\"}"

# 各チャンク（メッセージ分割された一部）を送信する関数
send_chunk() {
    local chunk_content="$1"

    # メッセージ内の特殊文字をJSONエスケープするのじゃ
    chunk_content="${chunk_content//\\/\\\\}"
    chunk_content="${chunk_content//\"/\\\"}"
    chunk_content="${chunk_content//$'\n'/\\n}"
    chunk_content="${chunk_content//$'\r'/\\r}"
    chunk_content="${chunk_content//$'\t'/\\t}"

    if [ "$DRY_RUN" = true ]; then
        echo "--- DRY RUN ---"
        echo "Webhook URL: $DISCORD_WEBHOOK_URL"
        echo "Payload: {\"content\": \"$chunk_content\", \"username\": \"$HOST_NAME\"}"
    else
        # curlコマンドでDiscordに送信じゃ
        curl \
            -X POST \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"$chunk_content\", \"username\": \"$HOST_NAME\"}" \
            "$DISCORD_WEBHOOK_URL"
        
        # 分割送信の場合にレートリミットを回避するため、少しスリープを入れるのじゃ
        sleep 0.5
    fi
}

# Discordの文字数制限は2000文字じゃが、安全のため1950文字をしきい値とするのじゃ
LIMIT=1950

if [ "${#MESSAGE}" -le "$LIMIT" ]; then
    send_chunk "$MESSAGE"
else
    current_chunk=""
    # 行ごとに分割して読み込み、チャンクを組み立てるのじゃ
    while IFS= read -r line || [ -n "$line" ]; do
        line_len=${#line}

        # 1行自体が制限を超える場合は、文字単位で分割するのじゃ
        if [ "$line_len" -gt "$LIMIT" ]; then
            if [ -n "$current_chunk" ]; then
                send_chunk "$current_chunk"
                current_chunk=""
            fi

            remaining_line="$line"
            while [ "${#remaining_line}" -gt "$LIMIT" ]; do
                sub_chunk="${remaining_line:0:$LIMIT}"
                send_chunk "$sub_chunk"
                remaining_line="${remaining_line:$LIMIT}"
            done
            current_chunk="$remaining_line"
        else
            # 現在のチャンクにこの行を追加した場合の長さを計算するのじゃ
            if [ -z "$current_chunk" ]; then
                new_chunk="$line"
            else
                new_chunk="$current_chunk"$'\n'"$line"
            fi

            if [ "${#new_chunk}" -gt "$LIMIT" ]; then
                send_chunk "$current_chunk"
                current_chunk="$line"
            else
                current_chunk="$new_chunk"
            fi
        fi
    done <<< "$MESSAGE"

    # 残りのチャンクがあれば送信するのじゃ
    if [ -n "$current_chunk" ]; then
        send_chunk "$current_chunk"
    fi
fi
