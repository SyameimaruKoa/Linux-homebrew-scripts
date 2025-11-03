#!/bin/bash
#
# audio_splitter.sh
#
# Google Colab Pythonスクリプトから変換した、音声ファイル分割スクリプトじゃ。
# FFmpegを使用して、指定されたディレクトリの音声ファイルを指定秒数ごとに分割するぞ。
#

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

# --- デフォルト値の設定 ---
install_ffmpeg=false
segment_duration_seconds=600
output_format="wav_16bit"
output_prefix="split_"
batch_processing_mode=false
delete_original_file=true # Pythonスクリプトのデフォルト
in_path=""
target_file_name=""

# --- 引数解析 ---
positional_args=()

# while/case を使って、--long-option も解析できるようにする
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    -h | --help)
        show_help
        exit 0
        ;;
    -i | --install-ffmpeg)
        install_ffmpeg=true
        shift # オプションを消費
        ;;
    -b | --batch)
        batch_processing_mode=true
        shift
        ;;
    -r | --delete-original)
        delete_original_file=true
        shift
        ;;
    --no-delete)
        # 元のスクリプトにはないが、-rを無効化する安全策として追加
        delete_original_file=false
        shift
        ;;
    -d | --duration)
        if [[ -n "$2" && ! "$2" =~ ^- ]]; then
            segment_duration_seconds="$2"
            shift
            shift # オプションと値を消費
        else
            echo "エラー: $1 には値（秒数）が必要じゃ。" >&2
            exit 1
        fi
        ;;
    -f | --format)
        if [[ -n "$2" && ! "$2" =~ ^- ]]; then
            output_format="$2"
            shift
            shift
        else
            echo "エラー: $1 には値（形式）が必要じゃ。" >&2
            exit 1
        fi
        ;;
    -p | --prefix)
        if [[ -n "$2" && ! "$2" =~ ^- ]]; then
            output_prefix="$2"
            shift
            shift
        else
            echo "エラー: $1 には値（接頭辞）が必要じゃ。" >&2
            exit 1
        fi
        ;;
    -*)
        # 不明なオプション
        echo "不明なオプション: $1" >&2
        show_help
        exit 1
        ;;
    *)
        # オプション以外の引数（位置引数）
        positional_args+=("$1")
        shift
        ;;
    esac
done

# --- 位置引数の割り当て ---
in_path="${positional_args[0]}"
target_file_name="${positional_args[1]}" # 空かもしれん

# --- (1) 初期バリデーションとファイル一覧表示 ---
if [ -z "$in_path" ]; then
    echo "エラー: <in_path> (入力ディレクトリ) が指定されておらん。" >&2
    show_help
    exit 1
fi

# $in_path の末尾のスラッシュを削除 (find での重複パスを避けるため)
in_path="${in_path%/}"

if [ ! -d "$in_path" ]; then
    echo "エラー: ディレクトリが見つからん: $in_path" >&2
    exit 1
fi

echo "📁 $in_path にある【未分割】のファイル一覧じゃ:"
echo "--------------------------------------------------"

audio_extensions="m4a|mp3|wav|ogg|flac|opus|webm"
found_files_names=()
# find と while read ループを使い、特殊文字を含むファイル名にも対応
# 2025-10-31 修正: -iregex は環境依存で不安定なことがあるため、
# -iname と -o (OR) を使う、より堅牢な方法に変更じゃ。
while IFS= read -r f; do
    found_files_names+=("$(basename "$f")")
done < <(find "$in_path" -maxdepth 1 -type f \
    \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.flac" -o -iname "*.opus" -o -iname "*.webm" \) \
    -not -name "${output_prefix}*")

if [ ${#found_files_names[@]} -eq 0 ]; then
    echo "   (処理対象の未分割ファイルが見つからんかったぞ)"
else
    # 一覧を表示 (PythonのHTMLボタンの代わり)
    printf "   %s\n" "${found_files_names[@]}"
fi
echo "--------------------------------------------------"

# --- (2) FFmpegのインストール ---
ffmpeg_installed=false
has_files_to_process_flag=false # 処理すべきファイルがあるか

if [ "$batch_processing_mode" = true ] && [ ${#found_files_names[@]} -gt 0 ]; then
    has_files_to_process_flag=true
elif [ -n "$target_file_name" ]; then
    has_files_to_process_flag=true
fi

if [ "$has_files_to_process_flag" = true ]; then
    if [ "$install_ffmpeg" = true ]; then
        echo "🚀 FFmpegをインストール中じゃ... (sudoが必要じゃ)"
        if ! command -v sudo >/dev/null; then
            echo "❌ sudo コマンドが見つからん。apt を実行できんぞ。" >&2
            exit 1
        fi
        # apt update は失敗することがあるが、致命的ではない場合もある
        sudo apt update || echo "   (apt update に少し失敗したかもしれんが、ffmpegインストールを試みるぞ)"

        if sudo apt install -y ffmpeg; then
            echo "✅ FFmpegのインストール完了じゃ。"
            ffmpeg_installed=true
        else
            echo "❌ FFmpegのインストールに失敗したようじゃ。" >&2
        fi
    else
        echo "ℹ️ FFmpegのインストールはスキップされたぞ。"
    fi

    # ffmpegコマンドが使えるか最終確認
    if command -v ffmpeg >/dev/null; then
        ffmpeg_installed=true
    else
        if [ "$install_ffmpeg" = false ]; then
            echo "❌ FFmpegが見つからん！ --install-ffmpeg を試すか、手動でインストールするのじゃ。" >&2
        fi
        ffmpeg_installed=false # 失敗を明記
    fi
fi

# --- (3) 処理対象リストの決定 ---
files_to_process=()
if [ "$batch_processing_mode" = true ]; then
    if [ ${#found_files_names[@]} -eq 0 ]; then
        echo "🤷 一括処理がONじゃが、処理対象のファイルが見当たらんかったぞ。"
    else
        echo "🔥 一括処理モードON！ ${#found_files_names[@]}個のファイルを処理するぞ。"
        files_to_process=("${found_files_names[@]}")
    fi
elif [ -z "$target_file_name" ]; then
    if [ ${#found_files_names[@]} -gt 0 ]; then
        echo "⚠️ 一括処理がOFFじゃ。分割したいファイル名を引数に指定するのじゃ。"
        echo "   (例: $0 \"$in_path\" \"${found_files_names[0]}\")"
    fi
elif [ -n "$target_file_name" ]; then
    # ファイルが一覧にあるかチェック (Pythonスクリプト同様、警告のみ)
    found=false
    for f in "${found_files_names[@]}"; do
        if [ "$f" = "$target_file_name" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo "⚠️ 指定されたファイル「$target_file_name」は一覧に見当たらんが、処理を試行するぞ。"
    fi
    echo "🔥 単一ファイル処理モード！「$target_file_name」を処理するぞ。"
    files_to_process=("$target_file_name")
fi

# --- (4) 時間チェック ---
if [ ${#files_to_process[@]} -gt 0 ] && [[ ! "$segment_duration_seconds" -gt 0 ]]; then
    echo "⚠️ 分割時間は0より大きい値を指定せい。処理を中断するぞ。" >&2
    files_to_process=() # 処理リストを空にする
fi

# --- (5) メインループ処理 ---
total_processed_count=0
total_failed_count=0

if [ ${#files_to_process[@]} -gt 0 ] && [ "$ffmpeg_installed" = true ]; then

    total_files=${#files_to_process[@]}
    current_file_num=0

    for current_file_name in "${files_to_process[@]}"; do
        ((current_file_num++))
        echo
        echo "=================================================="
        echo "⏳ ($current_file_num / $total_files) ファイル分割を開始するぞ: $current_file_name"
        echo "=================================================="

        input_file_path="$in_path/$current_file_name"

        if [ ! -f "$input_file_path" ]; then
            echo "❌ エラー: ファイルが見つからんぞ: $input_file_path" >&2
            ((total_failed_count++))
            continue # 次のファイルへ
        fi

        # ファイル名から拡張子とベース名を取得
        base_name="${current_file_name%.*}"
        suffix="${current_file_name##*.}"

        codec_args=()
        output_extension=""

        # 出力形式に応じてコーデックと拡張子を決定
        case "$output_format" in
        "copy")
            output_extension=".$suffix"
            codec_args=("-c:a" "copy")
            ;;
        "flac")
            output_extension=".flac"
            codec_args=("-c:a" "flac")
            ;;
        "wav_16bit")
            output_extension=".wav"
            codec_args=("-c:a" "pcm_s16le")
            ;;
        *)
            echo "❌ 不正な出力形式 ($output_format) じゃ。スキップするぞ。" >&2
            ((total_failed_count++))
            continue
            ;;
        esac

        # 出力パターンを決定
        output_pattern="${in_path}/${output_prefix}${base_name}_%03d${output_extension}"

        # FFmpeg コマンドを配列で組み立てる (特殊文字対応)
        cmd=("ffmpeg" "-i" "$input_file_path" "-f" "segment" "-segment_time" "$segment_duration_seconds" "-reset_timestamps" "1" "-map" "0:a")
        cmd+=("${codec_args[@]}") # コーデック引数を追加
        cmd+=("$output_pattern")

        echo "🏃 実行コマンド (進捗はstderrに出るぞ):"
        # 実行するコマンドを安全に表示 (printf %q を使用)
        printf "  %q" "${cmd[@]}"
        echo
        echo "--- FFmpeg 実行ログ (進捗) ---"

        # コマンド実行。ffmpegは進捗をstderrに出すため、そのままターミナルに表示させる
        if "${cmd[@]}"; then
            # 成功
            return_code=0
        else
            # 失敗
            return_code=$?
        fi

        echo "--- 実行ログ終了 ---"

        # Pythonスクリプトの glob.escape と split_count のチェックは、
        # シェルでは複雑になるため、ffmpegの終了コード($?)のみで判定する。

        if [ $return_code -eq 0 ]; then
            echo
            echo "✅ 分割が正常に完了したぞ！"
            # (分割数のカウントは省略し、ffmpegの成功を信頼する)
            ((total_processed_count++))

            if [ "$delete_original_file" = true ]; then
                if rm "$input_file_path"; then
                    echo "🗑️  元ファイルを削除しました: $current_file_name"
                else
                    echo "❌  元ファイルの削除に失敗しました: $input_file_path" >&2
                fi
            else
                echo "ℹ️ 元ファイルは削除されんかったぞ。"
            fi
        else
            echo
            echo "❌ FFmpegエラーじゃ (コード: $return_code)。" >&2
            echo "   (↑ ログを遡ってエラー原因を確認するのじゃ)" >&2
            ((total_failed_count++))
        fi

    done # --- ループ終了 ---

    # --- 全ループ終了後のサマリー ---
    if [ $total_files -gt 0 ]; then
        echo
        echo "=================================================="
        echo "🎉 全ての分割処理が完了したぞ！"
        echo "   -> 合計 $total_files 個中、 $total_processed_count 個の処理が成功、$total_failed_count 個が失敗した。"
        echo "=================================================="
    fi

elif [ "$has_files_to_process_flag" = false ]; then
    # 処理すべきファイルが最初からなかった場合
    echo "ℹ️ 分割処理は実行されんかったぞ。（対象ファイルなし）"

elif [ "$ffmpeg_installed" = false ]; then
    echo "❌ FFmpegのインストールに失敗、または見つからんかったため、分割処理を実行できんかったぞ。" >&2
fi
