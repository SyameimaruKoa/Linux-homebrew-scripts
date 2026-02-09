#!/bin/bash

# --- ヘルプ表示関数 ---
show_help() {
    echo "使用法: $(basename "$0") [オプション] <ディレクトリ>"
    echo ""
    echo "指定されたディレクトリ以下の全てのMatroskaファイル(.mkv, .webm)に対し、"
    echo "統計情報タグ(Statistics Tags)を追加または更新するのじゃ。"
    echo ""
    echo "オプション:"
    echo "  -h, --help    このヘルプを表示して終了する"
    echo ""
    echo "引数:"
    echo "  <ディレクトリ>  処理対象のディレクトリパス"
    echo "                 (サブディレクトリも再帰的に検索するぞ)"
}

# --- 引数チェック ---

# 引数が空の場合はヘルプを表示して終了
if [ -z "$1" ]; then
    show_help
    exit 1
fi

# ヘルプオプションの処理
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        TARGET_DIR="$1"
        ;;
esac

# --- ディレクトリ存在確認 ---
if [ ! -d "$TARGET_DIR" ]; then
    echo "エラー: 指定されたディレクトリ '$TARGET_DIR' が見つからぬか、ディレクトリではないようじゃ。"
    exit 1
fi

# --- メイン処理 ---
echo "ディレクトリ '$TARGET_DIR' 以下のファイルを検索中..."

# findコマンドで .mkv と .webm を検索し、whileループで回す
# プロセス置換を使って安全性高めておくぞ
find "$TARGET_DIR" -type f \( -name "*.mkv" -o -name "*.webm" \) -print0 | while IFS= read -r -d '' file; do
    echo "--------------------------------------------------"
    echo "処理中: $file"
    
    # mkvpropeditの実行
    # 出力を抑制したい場合は > /dev/null を末尾に付けるが、今回は見えるようにしておく
    mkvpropedit "$file" --add-track-statistics-tags
    
    # 終了ステータスの確認
    if [ $? -eq 0 ]; then
        echo "成功: 統計情報を更新したぞ。"
    else
        echo "警告: このファイルの処理中にエラーが出たようじゃ。"
    fi
done

echo "--------------------------------------------------"
echo "全ての処理が完了したはずじゃ。"
