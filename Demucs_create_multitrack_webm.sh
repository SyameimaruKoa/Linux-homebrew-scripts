#!/bin/bash

#set -euo pipefail

# --- ヘルプメッセージを表示する関数 ---
show_help() {
    cat <<EOF
使用法: $(basename "$0") [オプション] <WebMファイル1> [<WebMファイル2> ...]

指定されたWebMファイルに対し、対応する vocals.flac と minus_vocals.flac を
検索し、それらを新しいOpusオーディオストリームとして追加した
マルチトラックWebMファイル（*_full_multitrack.webm）を生成します。

必須ファイル構造:
<ベースパス>/<ファイル名>.webm
<ベースパス>/separated/htdemucs_ft/<ファイル名>_vocals.flac
<ベースパス>/separated/htdemucs_ft/<ファイル名>_minus_vocals.flac

オプション:
    -h, --help    このヘルプメッセージを表示して終了します。

要件:
    ffmpeg, ffprobe, wc
EOF
}

# --- 引数のチェック ---
if [ $# -eq 0 ]; then
    echo "エラー: 処理対象のWebMファイルが指定されていません。" >&2
    echo ""
    show_help
    exit 1
fi

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# --- メイン処理ループ ---
# 引数で渡されたファイルを一つずつ処理する
for WEBM_FILE in "$@"; do
    echo "--------------------------------------------------"
    echo "処理開始: $WEBM_FILE"

    # --- 1. ファイルパスの解決 ---
    if [ ! -f "$WEBM_FILE" ]; then
        echo "  エラー: WebMファイルが見つかりません。スキップします。" >&2
        echo "    $WEBM_FILE"
        continue
    fi

    DIRNAME=$(dirname "$WEBM_FILE")
    BASENAME=$(basename "$WEBM_FILE" .webm)

    VOCALS_FILE="${DIRNAME}/separated/htdemucs_ft/${BASENAME}_vocals.flac"
    MINUS_FILE="${DIRNAME}/separated/htdemucs_ft/${BASENAME}_minus_vocals.flac"
    OUTPUT_FILE="${DIRNAME}/${BASENAME}_full_multitrack.webm"

    # --- 2. 必須ファイルの存在確認 ---
    if [ ! -f "$VOCALS_FILE" ]; then
        echo "  エラー: Vocalsファイルが見つかりません。スキップします。" >&2
        echo "    $VOCALS_FILE"
        continue
    fi
    if [ ! -f "$MINUS_FILE" ]; then
        echo "  エラー: Minus Vocalsファイルが見つかりません。スキップします。" >&2
        echo "    $MINUS_FILE"
        continue
    fi

    echo "  入力ファイルを確認しました:"
    echo "    Video/Audio: $WEBM_FILE"
    echo "    Vocals:      $VOCALS_FILE"
    echo "    Minus:       $MINUS_FILE"

    # --- 3. オーディオトラック数の動的カウント (N) ---
    echo "  元のWebMのオーディオトラック数をカウント中..."
    N=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$WEBM_FILE" | wc -l)
    # wc -l は改行コードでカウントするため、ストリームがない場合は 0 になるはずだが、
    # 念のためトリムしておく
    N=$(echo "$N" | tr -d '[:space:]')

    echo "  元のオーディオトラック数 (N): $N"

    # 新しいトラックのインデックスを計算
    VOCALS_INDEX=$N
    MINUS_INDEX=$((N + 1))

    echo "  新しいトラックインデックス:"
    echo "    Vocals (N):   $VOCALS_INDEX"
    echo "    Minus (N+1): $MINUS_INDEX"

    # --- 4. FFmpeg 実行 ---
    echo "  FFmpegによるマルチトラックファイルの生成を開始します..."
    echo "  出力ファイル: $OUTPUT_FILE"

    if ffmpeg -hide_banner -i "$WEBM_FILE" -i "$VOCALS_FILE" -i "$MINUS_FILE" \
        -map 0:v:0 \
        -map 0:a \
        -map 1:a:0 \
        -map 2:a:0 \
        -c:v copy \
        -c:a copy \
        -c:a:$VOCALS_INDEX libopus -application voip \
        -c:a:$MINUS_INDEX libopus -application audio \
        -metadata:s:a:$VOCALS_INDEX title="Vocals (Opus Voip)" \
        -metadata:s:a:$VOCALS_INDEX language="jpn" \
        -metadata:s:a:$MINUS_INDEX title="Minus Vocals (Opus Audio)" \
        -metadata:s:a:$MINUS_INDEX language="jpn" \
        -y "$OUTPUT_FILE"; then

        echo "  成功: ファイルの生成が完了しました。"
        echo "    $OUTPUT_FILE"
    else
        echo "  エラー: FFmpegの実行に失敗しました。" >&2
        # 失敗した場合、不完全な出力ファイルを削除する
        if [ -f "$OUTPUT_FILE" ]; then
            rm "$OUTPUT_FILE"
            echo "  不完全な出力ファイルを削除しました。"
        fi
    fi
done

echo "--------------------------------------------------"
echo "全ての処理が完了しました。"
