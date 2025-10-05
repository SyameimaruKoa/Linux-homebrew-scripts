#!/bin/bash

# シンボリックリンクを解決して、このスクリプトの実体があるディレクトリの絶対パスを取得するのじゃ
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # -h オプションでシンボリックリンクをチェックじゃ
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  # リンク先が相対パスじゃったら、解決済みのディレクトリと結合するのじゃ
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

ENV_FILE="$SCRIPT_DIR/.env"

# 通常のヘルプメッセージを表示する関数
show_help() {
  cat << EOF
Usage: $(basename "$0") <message>

Description:
  引数で渡されたメッセージをDiscordの特定のWebhook URLに送信します。
  このスクリプトは .env ファイルから DISCORD_WEB_HOOK_URL を読み込みます。
  複数の引数を指定した場合、それらは改行で連結されて一つのメッセージとして送信されます。

Arguments:
  message       Discordに送信するメッセージ文字列。

Options:
  -h, --help    このヘルプメッセージを表示して終了します。
EOF
}

# .envファイルのセットアップ方法を表示する関数じゃ
show_env_setup_help() {
  cat << EOF
--------------------------------------------------
エラー: 設定ファイル (.env) が見つからんぞ！
--------------------------------------------------
スクリプトと同じ階層に.envファイルが必要じゃ。
以下のコマンドを使えば一発で作成できるぞ。

【作成コマンド】
下のコマンドの 'ここにそなたのWebhook URLを貼る' の部分を書き換えて、
そのままターミナルに貼り付けて実行するのじゃ！
(実行する場所ではなく、スクリプトのある場所 '${SCRIPT_DIR}' に作成されるぞ)

   echo 'DISCORD_WEBHOOK_URL="ここにそなたのWebhook URLを貼る"' > "${ENV_FILE}"

--------------------------------------------------
【重要】
.envファイルを作成したら、必ず.gitignoreに以下の1行を追加するのを忘れるな！
   .env
--------------------------------------------------
EOF
}


# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  show_help
  exit 0
fi

# 引数がない場合はヘルプを表示して終了
if [ $# -eq 0 ]; then
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


# 受け取った全ての引数を改行でつないで一つのメッセージにするのじゃ
MESSAGE=""
for arg in "$@"; do
    MESSAGE="$MESSAGE$arg\n"
done
MESSAGE="${MESSAGE%\\n}"


# curlコマンドでDiscordに送信じゃ
curl \
-X POST \
-H "Content-Type: application/json" \
-d "{\"content\": \"$MESSAGE\"}" \
"$DISCORD_WEBHOOK_URL"
