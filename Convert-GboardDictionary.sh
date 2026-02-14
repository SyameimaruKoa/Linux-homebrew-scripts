#!/bin/bash

# ==============================================================================
# Gboard・Google日本語入力 辞書変換スクリプト (Bash版)
# 作成者: わっち
# ==============================================================================

# ヘルプを表示する関数
show_help() {
    echo "使用法: $0 [オプション] <ファイルパス>"
    echo ""
    echo "説明:"
    echo "  GboardとGoogle日本語入力のユーザー辞書ファイル形式を相互に変換するのじゃ。"
    echo "  TSV形式のテキストファイル、またはそれを含むZIPファイルを指定できるぞ。"
    echo ""
    echo "  ZIPファイルを指定した場合:"
    echo "    内部の 'dictionary.txt' を変換し、ユーザーのダウンロードフォルダに出力する。"
    echo ""
    echo "  テキストファイルを指定した場合:"
    echo "    同じディレクトリに変換後のファイルを出力する。"
    echo ""
    echo "オプション:"
    echo "  -h, --help    このヘルプメッセージを表示する"
    echo ""
    echo "例:"
    echo "  $0 dictionary.txt"
    echo "  $0 archive.zip"
}

# 引数チェック
if [ -z "$1" ]; then
    show_help
    exit 1
fi

case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
esac

INPUT_PATH="$1"

# ファイル存在チェック
if [ ! -f "$INPUT_PATH" ]; then
    echo "エラー: 指定されたファイルが見つからんのじゃ！: $INPUT_PATH"
    exit 1
fi

# ZIP判定とパスの準備
FILENAME=$(basename -- "$INPUT_PATH")
EXTENSION="${FILENAME##*.}"
FILENAME_NO_EXT="${FILENAME%.*}"

IS_ZIP=false
TEMP_DIR=""
PROCESS_PATH="$INPUT_PATH"
OUTPUT_PATH=""

if [ "${EXTENSION,,}" == "zip" ]; then
    IS_ZIP=true
    echo "ZIPファイルを受け取ったぞ。展開して中身を確認するのじゃ..."
    
    # 一時ディレクトリ作成
    TEMP_DIR=$(mktemp -d)
    
    # ZIP展開 (unzipが必要じゃ)
    if ! unzip -q -j "$INPUT_PATH" "dictionary.txt" -d "$TEMP_DIR"; then
        echo "エラー: ZIPの展開に失敗したわ！壊れておらぬか？"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    PROCESS_PATH="$TEMP_DIR/dictionary.txt"
    
    if [ ! -f "$PROCESS_PATH" ]; then
        echo "エラー: ZIPの中に 'dictionary.txt' が見つからんぞ！ 構造を確認せい！"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # ダウンロードフォルダへのパス (xdg-user-dirがあれば使い、なければHOME/Downloads)
    if command -v xdg-user-dir > /dev/null 2>&1; then
        DOWNLOAD_DIR=$(xdg-user-dir DOWNLOAD)
    else
        DOWNLOAD_DIR="$HOME/Downloads"
    fi
    
    OUTPUT_PATH="$DOWNLOAD_DIR/${FILENAME_NO_EXT}_converted.txt"
else
    # 通常ファイルの出力パス設定
    DIRNAME=$(dirname "$INPUT_PATH")
    OUTPUT_PATH="$DIRNAME/${FILENAME_NO_EXT}_converted.${EXTENSION}"
fi

# メニュー表示ループ
while true; do
    echo "-----------------------------------------"
    echo " Gboard・Google日本語入力 辞書変換"
    echo "-----------------------------------------"
    echo "変換方向を選択するのじゃ"
    echo "  1: Gboard -> Google日本語入力"
    echo "  2: Google日本語入力 -> Gboard"
    echo "  Q: 終了"
    echo "-----------------------------------------"
    read -p ">> 番号を入力してくだされ: " CHOICE

    case "$CHOICE" in
        1)
            # Gboard(ja-JP) -> Google(品詞なし)
            # タブ文字の扱いに注意じゃ
            BEFORE=$'\tja-JP'
            AFTER=$'\t品詞なし\t'
            break
            ;;
        2)
            # Google(品詞なし) -> Gboard(ja-JP)
            BEFORE=$'\t品詞なし\t'
            AFTER=$'\tja-JP'
            break
            ;;
        [Qq])
            echo "処理を中断したのじゃ。"
            [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
            exit 0
            ;;
        *)
            echo "喝！ 1, 2, または Q のいずれかを入力するのじゃ！"
            sleep 1
            ;;
    esac
done

echo ""
echo "ファイルを処理中じゃ... しばし待たれよ。"

# 置換処理 (sedを使用)
# GNU sedを想定しておる。Macの場合は -i '' などの調整が必要かもしれんが、今回は標準出力経由で書き込むので安全じゃ。
sed "s/${BEFORE}/${AFTER}/g" "$PROCESS_PATH" > "$OUTPUT_PATH"

if [ $? -eq 0 ]; then
    echo "処理が完了したぞ！"
    echo "出力ファイル: $OUTPUT_PATH"
else
    echo "エラー: ファイルの書き込みに失敗したようじゃ..."
fi

# 後始末
[ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
