#!/bin/bash
#
# separated/htdemucs_ft/ 内の分割FLACセグメントをベース名ごとに連結するスクリプト。
#
# このスクリプトは、"split_ベース名_XXX" という形式のディレクトリ群を探し、
# それぞれに含まれる "vocals.flac" と "minus_vocals.flac" を
# FFmpegを使って連結し、"ベース名_vocals.flac" などとして出力する。

# --- ヘルプ表示関数 ---
# ...existing code...
# --- ヘルプ関数の定義 ---
# (ユーザー設定に基づき、-h または --help で呼び出される)
show_help() {
    cat << EOF
使い方: $(basename "$0") <in_path> [オプション]... [target_file_name]

概要:
    Demucs の事前分割用途にも使える、FFmpeg ベースの音声分割スクリプト。

引数:
    <in_path>            処理対象ファイルがあるディレクトリ。
    [target_file_name]   (任意) <in_path> 内の特定のファイル名。
                        これを指定しない場合は -b で一括処理する。

オプション:
    -b, --batch              ディレクトリ内の全オーディオを一括処理
    -d, --duration <秒>      分割秒数 (既定: 600)
    -f, --format <形式>      出力形式: flac | wav_16bit | copy (既定: wav_16bit)
    -p, --prefix <接頭辞>    出力の接頭辞 (既定: split_)
    -r, --delete-original    分割成功後に元ファイルを削除 (既定: オン)
        --no-delete          元ファイルを削除しない
    -i, --install-ffmpeg     sudo apt で ffmpeg をインストール
    -h, --help               このヘルプを表示

例:
    # ディレクトリ内の全ファイルを 10 分ごとに WAV(16bit) で分割
    $(basename "$0") /path/to/in -b -d 600 -f wav_16bit

    # 特定ファイルのみ分割（接頭辞を変更）
    $(basename "$0") /path/to/in "target.m4a" -d 300 -p split_

Demucs との併用:
    1) 本スクリプトで長尺音源を分割
    2) 分割ファイル群に対して demucs を実行
    3) 分離後は Demucs_concat_flac_segments.sh で連結
EOF
}
# ...existing code...
使用法: $(basename "$0") [-h|--help]

Demucs (htdemucs_ft) によって 'split_...' ディレクトリに分割されたFLACファイルを、
ベース名ごとに 'vocals' と 'minus_vocals' の2つのファイルに連結します。

このスクリプトは、'separated/htdemucs_ft/' ディレクトリの
**内部**で実行する必要があります。

必須要件:
    ffmpeg : FLACファイルの連結に使用されます。
    sort   : GNU sort (sort -V) が必要です（自然順ソートのため）。

オプション:
    -h, --help    このヘルプメッセージを表示して終了します。

処理の流れ:
    1. 'split_...' ディレクトリ名をスキャンし、重複しないベース名を特定します。
    2. ベース名ごとに、関連する全セグメント (split_..._000, _001, ...) を探します。
    3. セグメント内の 'vocals.flac' と 'minus_vocals.flac' のパスをリスト化します。
    4. FFmpeg を使い、リストに基づいてファイルを連結します（再エンコードあり）。
    5. 成功後、関連した 'split_...' ディレクトリ群を削除するか対話式で確認します。

EOF
}

# --- 引数の解析 ---
# ヘルプオプションが指定されたか確認
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# --- メイン処理 ---

# スクリプトの堅牢性を高める設定
# set -e: コマンドが失敗したら即終了
# set -o pipefail: パイプの途中で失敗しても即終了
set -e
set -o pipefail

# スクリプトが配置されているディレクトリ (separated/htdemucs_ft/) に移動する
# これにより、相対パスが常に正しく解決される
# ↓↓↓ この行を削除する ↓↓↓
# cd "$(dirname "$0")"

echo "処理を開始します..."
echo "実行ディレクトリ: $(pwd)"
echo

# --- 1. ベース名の特定 ---
echo "処理対象のベース名を特定中..."

# 一時ファイル名
BASENAME_LIST_FILE="basenames.list.tmp"

# スクリプト終了時に一時ファイルを必ず削除する
# EXIT, INT, TERM シグナルをトラップする
trap 'rm -f "$BASENAME_LIST_FILE"; exec 3<&-; echo "処理を中断しました。";' EXIT INT TERM

# 'split_' で始まり '_NNN' (NNNは3桁の数字) で終わるディレクトリを検索
# sedで 'split_' と '_NNN' を取り除き、ベース名を抽出
# sort -u で重複を排除し、一時ファイルに書き出す
find . -maxdepth 1 -type d -name "split_*_[0-9][0-9][0-9]" | \
    sed -E 's/^\.\/split_//; s/_[0-9]{3}$//' | \
    sort -u > "$BASENAME_LIST_FILE"

# ベース名が見つからなかった場合のガード処理
if [ ! -s "$BASENAME_LIST_FILE" ]; then
    echo "  エラー: 'split_ベース名_NNN' 形式のディレクトリが見つかりません。"
    echo "  このスクリプトは 'separated/htdemucs_ft/' ディレクトリ内で実行してください。"
    rm -f "$BASENAME_LIST_FILE"
    exit 1
fi

echo "以下のベース名が見つかりました:"
cat "$BASENAME_LIST_FILE"
echo "----------------------------------------"

# --- 2. ベース名ごとのループ処理 ---

# BASENAME_LIST_FILE をファイルディスクリプタ 3 (FD 3) で開く
# これにより、標準入力(FD 0)を消費しなくなるため、
# ループ内で read -p (標準入力) を使っても安全になる。
exec 3< "$BASENAME_LIST_FILE"

# FD 3 から1行ずつ読み込む (read -u 3 でも良いが、<&3 の方が一般的)
while IFS= read -r basename <&3; do
    # basenameが空の場合（ファイル終端などで）スキップ
    if [ -z "$basename" ]; then
        continue
    fi

    echo "処理中のベース名: $basename"
    
    # ファイル定義
    vocals_list="vocals_list.txt"
    minus_list="minus_list.txt"
    output_vocals="${basename}_vocals.flac"
    output_minus="${basename}_minus_vocals.flac"
    
    # (ループの開始時に古いリストを削除)
    rm -f "$vocals_list" "$minus_list"

    # --- 3. 連結リストの作成 ---
    echo "  連結リストを作成中..."
    file_count=0
    
    # 変数に格納せず、プロセス置換 (< <(...)) を使って
    # パイプラインの結果を直接 while ループに渡す
    # (セグメント数が数千になってもシェルの変数限界を超えないため)
    
    # IFS（区切り文字）を一時的に改行のみに変更
    # (スペースを含むファイルパスを正しく扱うため)
    OLD_IFS=$IFS
    IFS=$'\n'

    # find/grep/sort の結果を1行ずつ読み込む
    # find: 'split_*' ディレクトリを検索
    # grep -F: 特殊文字を含む $basename をリテラル(文字列)として安全に検索
    # sort -V: 自然順ソート ('_10' が '_2' より後に来るように)
    while IFS= read -r dir; do
        # dir が空ならスキップ (パイプラインの終端などで)
        if [ -z "$dir" ]; then
            continue
        fi
        
        # vocals.flac のリストアップ
        vocal_path="$dir/vocals.flac"
        if [ -f "$vocal_path" ]; then
            # シングルクォートのエスケープ処理 (例: ' -> '\'' )
            # ffmpeg の concat リスト ('file' ... の書式) を壊さないため
            vocal_path_escaped=$(echo "$vocal_path" | sed "s/'/'\\\\''/g")
            echo "file '$vocal_path_escaped'" >> "$vocals_list"
            file_count=$((file_count + 1))
        else
            echo "  警告: $vocal_path が見つかりません。"
        fi
        
        # minus_vocals.flac のリストアップ
        minus_path="$dir/minus_vocals.flac"
        if [ -f "$minus_path" ]; then
            # シングルクォートのエスケープ処理
            minus_path_escaped=$(echo "$minus_path" | sed "s/'/'\\\\''/g")
            echo "file '$minus_path_escaped'" >> "$minus_list"
        else
            echo "  警告: $minus_path が見つかりません。"
        fi
        
    done < <(find . -maxdepth 1 -type d -name "split_*" | grep -F "split_${basename}_" | sort -V)
    
    # IFSを元に戻す
    IFS=$OLD_IFS

    # ファイルが一つも見つからなかった場合はスキップ
    if [ $file_count -eq 0 ]; then
        echo "  警告: ${basename} の関連ファイルが一つも見つかりません。スキップします。"
        rm -f "$vocals_list" "$minus_list" # 空のリストファイルを削除
        echo "----------------------------------------"
        continue
    fi

    # --- 4. 連結 (FFmpeg) ---
    vocals_success=false
    minus_success=false

    echo "  FFmpeg (vocals) 連結実行中 -> $output_vocals"
    # -y : 既に出力ファイルが存在する場合、確認なしで上書きする
    # -f concat -safe 0 : concat デマルチプレクサを使用し、安全でないパスも許可する
    # -c:a copy (削除済) : 異なる仕様(長さなど)のセグメントを安全に連結するため、再エンコードする
    if ffmpeg -y -f concat -safe 0 -i "$vocals_list" "$output_vocals" -loglevel error; then
        echo "    ... 成功: $output_vocals"
        vocals_success=true
    else
        echo "    ... エラー: $output_vocals の連結に失敗しました。"
    fi

    echo "  FFmpeg (minus_vocals) 連結実行中 -> $output_minus"
    if ffmpeg -y -f concat -safe 0 -i "$minus_list" "$output_minus" -loglevel error; then
        echo "    ... 成功: $output_minus"
        minus_success=true
    else
        echo "    ... エラー: $output_minus の連結に失敗しました。"
    fi

    # --- 5. クリーンアップ ---
    if $vocals_success && $minus_success; then
        echo "  連結処理が正常に完了しました。"
        
        # 対話式の確認
        # '< /dev/tty' を使い、標準入力(FD 0)が FD 3 (ファイル) ではなく
        # 端末 (キーボード) になるよう強制する
        read -p "  ${basename} の関連ソース（split_* ディレクトリ群と *.txt リスト）を削除しますか？ (y/N): " confirm < /dev/tty
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo "  クリーンアップを実行中..."
            
            # 1. 一時連結リストの削除
            rm -f "$vocals_list" "$minus_list"
            echo "    ... $vocals_list, $minus_list を削除しました。"
            
            # 2. 関連する split ディレクトリ群の削除
            # find -name のエスケープ問題を避けるため、grep -F (リテラル検索) で対象を絞り込む
            # xargs -d '\n' で改行区切りのまま、rm -rf に安全に渡す
            find . -maxdepth 1 -type d -name "split_*" | \
                grep -F "split_${basename}_" | \
                xargs -d '\n' rm -rf
            
            echo "    ... split_${basename}_* ディレクトリ群を削除しました。"
        else
            echo "  クリーンアップをスキップしました。"
            echo "  (一時ファイル $vocals_list, $minus_list が残っています)"
        fi
    else
        echo "  連結処理に失敗したため、クリーンアップをスキップしました。"
        echo "  (一時ファイル $vocals_list, $minus_list が残っています)"
    fi

    echo "----------------------------------------"
done # while read basename ループの終了

# ループが完了したので、FD 3 を閉じる
exec 3<&-

# スクリプト終了時にトラップを解除し、一時ファイルを削除
trap - EXIT INT TERM
rm -f "$BASENAME_LIST_FILE"

echo "すべての処理が完了しました。"



