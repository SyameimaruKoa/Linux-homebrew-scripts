#!/bin/bash

# ==============================================================================
# APNG Optimizer Script (Optimization & Commit Mode)
#
# 機能:
#   1. 通常モード: 指定したファイルを最適化し、*-optimize.apng を生成。
#   2. 確定モード(-d): *-optimize.apng を元ファイル名にリネームして置換。
# ==============================================================================

# ------------------------------------------------------------------------------
# 設定
# ------------------------------------------------------------------------------
FUZZ_FACTOR="3%"

# ------------------------------------------------------------------------------
# ヘルプ表示
# ------------------------------------------------------------------------------
show_help() {
    echo "使用法:"
    echo "  1. 最適化を実行 (確認用ファイルを作成)"
    echo "     $(basename "$0") <入力ファイル.png>"
    echo "       -> 入力名-optimize.apng が生成されます。"
    echo ""
    echo "  2. 最適化を適用 (*-optimize.apng を本番ファイルに置換)"
    echo "     $(basename "$0") -d"
    echo "       -> カレントディレクトリの *-optimize.apng を全て処理します。"
    echo "       -> 例: aa-optimize.apng を aa.apng にリネーム(上書き)します。"
    echo ""
    echo "オプション:"
    echo "  -h, --help    ヘルプを表示"
    echo "  -d, --delete  確定モード: optimizeファイルを元名義にリネームして置換する"
    echo "  -o, --output  (最適化時) 出力ファイル名を指定"
    echo "  -k, --keep    (最適化時) 作業ディレクトリを保持"
    echo ""
}

# ------------------------------------------------------------------------------
# 依存コマンド確認
# ------------------------------------------------------------------------------
check_dependency() {
    local missing=0
    for cmd in apngdis apngasm compare; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "エラー: 必須コマンド '$cmd' が見つかりません。"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        echo "以下のコマンドでインストールしてください:"
        echo "  sudo apt install apngdis apngasm imagemagick"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 引数解析
# ------------------------------------------------------------------------------
INPUT_FILE=""
OUTPUT_FILE=""
KEEP_TEMP=false
APPLY_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -d|--delete) APPLY_MODE=true; shift ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        -k|--keep) KEEP_TEMP=true; shift ;;
        -*) echo "不明なオプション: $1"; show_help; exit 1 ;;
        *) INPUT_FILE="$1"; shift ;;
    esac
done

# ------------------------------------------------------------------------------
# モード分岐 1: 確定モード (-d 指定 かつ 入力ファイルなし)
# ------------------------------------------------------------------------------
if [ "$APPLY_MODE" = true ] && [ -z "$INPUT_FILE" ]; then
    echo "--- 確定モード (-d) ---"
    echo "カレントディレクトリの *-optimize.apng を適用します..."
    
    count=0
    # glob展開ができず文字列そのままになるのを防ぐ nullglob
    shopt -s nullglob
    FILES=(*-optimize.apng)
    shopt -u nullglob

    if [ ${#FILES[@]} -eq 0 ]; then
        echo "エラー: *-optimize.apng ファイルが見つかりません。"
        exit 0
    fi

    for f in "${FILES[@]}"; do
        # aa-optimize.apng -> aa
        base_name="${f%-optimize.apng}"
        target_name="${base_name}.apng"
        
        echo "適用: $f -> $target_name"
        
        # リネーム（上書き）
        mv "$f" "$target_name"
        
        # もし元の拡張子が .png で残っていたら削除 (aa.png と aa.apng が重複しないように)
        if [ -f "${base_name}.png" ] && [ "${base_name}.png" != "$target_name" ]; then
            echo "      (旧ファイル削除: ${base_name}.png)"
            rm "${base_name}.png"
        fi
        
        ((count++))
    done
    
    echo "完了: $count 個のファイルを置換しました。"
    exit 0
fi

# ------------------------------------------------------------------------------
# モード分岐 2: 最適化モード (入力ファイル指定あり)
# ------------------------------------------------------------------------------

if [ -z "$INPUT_FILE" ]; then
    show_help
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "エラー: ファイル '$INPUT_FILE' が見つかりません。"
    exit 1
fi

if [ -z "$OUTPUT_FILE" ]; then
    filename=$(basename "$INPUT_FILE")
    # 拡張子を .apng に変更
    OUTPUT_FILE="${filename%.*}-optimize.apng"
fi

check_dependency

# 画像比較関数
is_duplicate() {
    local img1="$1"
    local img2="$2"
    compare -metric AE -fuzz "$FUZZ_FACTOR" "$img1" "$img2" null: >/dev/null 2>&1
    return $?
}

# 1. 作業ディレクトリ準備
WORK_DIR="./temp_apng_work_$(date +%s)"
mkdir -p "$WORK_DIR"
ABS_INPUT=$(realpath "$INPUT_FILE")
ABS_OUTPUT=$(realpath -m "$OUTPUT_FILE")
SCRIPT_PATH=$(realpath "$0")

echo "入力: $ABS_INPUT"
echo "出力: $ABS_OUTPUT"
echo "作業中..."

cd "$WORK_DIR" || exit 1

# 2. 分解
cp "$ABS_INPUT" "temp_source.png"
apngdis "temp_source.png" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "エラー: apngdis に失敗しました。"
    cd ..; rm -rf "$WORK_DIR"; exit 1
fi
rm "temp_source.png"

# 3. 重複フレームの削除
echo "--- 画像内容の比較を開始 ---"
PREV_FILE=""
DELETE_COUNT=0

get_png_files() {
    ls apngframe*.png 2>/dev/null || ls *.png | sort
}

for curr_file in $(get_png_files); do
    if [ -z "$PREV_FILE" ]; then
        PREV_FILE="$curr_file"
        continue
    fi
    if is_duplicate "$PREV_FILE" "$curr_file"; then
        echo "連続重複削除: $curr_file (類似)"
        rm "$curr_file"
        [ -f "${curr_file%.png}.txt" ] && rm "${curr_file%.png}.txt"
        ((DELETE_COUNT++))
    else
        PREV_FILE="$curr_file"
    fi
done

# 4. ループ重複の削除
FILES_ARRAY=($(get_png_files))
NUM_FILES=${#FILES_ARRAY[@]}
if [ "$NUM_FILES" -ge 2 ]; then
    FIRST_FILE="${FILES_ARRAY[0]}"
    LAST_FILE="${FILES_ARRAY[$((NUM_FILES-1))]}"
    if is_duplicate "$FIRST_FILE" "$LAST_FILE"; then
        echo "ループ重複削除: $LAST_FILE (先頭と類似)"
        rm "$LAST_FILE"
        [ -f "${LAST_FILE%.png}.txt" ] && rm "${LAST_FILE%.png}.txt"
        ((DELETE_COUNT++))
    fi
fi
echo "自動削除: $DELETE_COUNT 枚"

# 5. 手動確認
echo "--------------------------------------------------------"
echo "【手動確認モード】"
echo "フォルダを開きます。内容を確認・編集してください。"
if command -v xdg-open &> /dev/null; then
    xdg-open . 2>/dev/null
else
    echo "場所: $(pwd)"
fi
echo ""
read -p ">> 確認完了したら Enterキー を押してください... " dummy_input

# 6. 掃除 & リネーム
for txt in *.txt; do
    [ -e "$txt" ] || continue
    img="${txt%.txt}.png"
    if [ ! -f "$img" ]; then rm "$txt"; fi
done

COUNT=1
REMAINING_FILES=$(get_png_files)
if [ -z "$REMAINING_FILES" ]; then
    echo "エラー: 画像が全消滅しました。中止します。"
    cd ..; rm -rf "$WORK_DIR"; exit 1
fi

for f in $REMAINING_FILES; do
    NEW_NUM=$(printf "%02d" "$COUNT")
    NEW_NAME="final_frame${NEW_NUM}"
    if [ "$f" != "${NEW_NAME}.png" ]; then
        mv "$f" "${NEW_NAME}.png"
        [ -f "${f%.png}.txt" ] && mv "${f%.png}.txt" "${NEW_NAME}.txt"
    fi
    ((COUNT++))
done

# 7. 再結合
apngasm output_temp.apng final_frame*.png > /dev/null

if [ -f "output_temp.apng" ]; then
    mv "output_temp.apng" "$ABS_OUTPUT"
    echo "完了: $ABS_OUTPUT"
else
    echo "エラー: 再結合失敗"
    cd ..
    rm -rf "$WORK_DIR"
    exit 1
fi

# 後始末
cd ..
if [ "$KEEP_TEMP" = false ]; then
    rm -rf "$WORK_DIR"
fi