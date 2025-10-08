#!/bin/bash

# シェルスクriptはUTF-8で保存すること！
# A capture script that allows interactive selection of devices, formats, and codecs.
# Version 20.0 - The final, stable version. The cursed "Capture+Preview" mode has been removed.

# ヘルプ表示用の関数
show_help() {
cat << EOF
使用法: ./capture.sh [オプション]
対話的にキャプチャデバイス、フォーマット、コーデックを選択して録画を開始するスクリプト。
安定性を重視し、高速なCPUエンコードを使用します。

動作モード:
 1. 録画のみ: ファイルに映像を録画します。
 2. プレビューのみ: 録画せず、映像を表示するだけです。

オプション:
  -h, --help    このヘルプメッセージを表示します。
EOF
}

# 引数なし、またはヘルプオプションが指定された場合はヘルプを表示
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

echo "--- 万能キャプチャスクリプト ---"

# --- 動作モードの選択 ---
echo ""
echo "どのモードで実行するんじゃ？"
OPERATION_MODES=("録画のみ" "プレビューのみ")
PS3="動作モードの番号: "
select mode_name in "${OPERATION_MODES[@]}"; do
    if [[ -n "$mode_name" ]]; then
        OPERATION_MODE=$REPLY
        echo "» ${mode_name} モードじゃな。"
        break
    else
        echo "不正な選択じゃ。もう一度選ぶのじゃ。"
    fi
done

# --- 映像キャプチャモードの選択 ---
echo ""
echo "どのモードでキャプチャするんじゃ？ 全てのデバイスの性能を調べておる..."

AWK_PARSER_SCRIPT='
/\[[0-9]+\]:/{
    if (match($0, /'\''[A-Z0-9]+'\''/)) {
        current_format = substr($0, RSTART + 1, RLENGTH - 2);
    }
}
/Size: Discrete/{
    current_resolution = $3;
}
/Interval: Discrete/{
    if (match($0, /\([0-9.]+ fps\)/)) {
        fps_part = substr($0, RSTART + 1, RLENGTH - 2);
        sub(/ fps/, "", fps_part);
        fps = fps_part;
    }
    if (current_format != "" && current_resolution != "" && fps != "") {
        print current_format"|"current_resolution"|"fps;
    }
}
'

CAPTURE_MODES=()
VIDEO_DEVICE_PATHS=($(LC_ALL=C v4l2-ctl --list-devices | grep -oP '^\s+/dev/video\d+'))

for device_path in "${VIDEO_DEVICE_PATHS[@]}"; do
    device_name=$(LC_ALL=C v4l2-ctl --list-devices | grep -B1 "$device_path" | head -n1 | sed -e 's/^\s*//' -e 's/:.*//')
    while IFS='|' read -r format resolution fps; do
        if [[ -n "$format" && -n "$resolution" && -n "$fps" ]]; then
            CAPTURE_MODES+=("${device_name} (${device_path}) - ${resolution} ${format} @ ${fps}fps")
        fi
    done < <(LC_ALL=C v4l2-ctl -d "$device_path" --list-formats-ext | awk "$AWK_PARSER_SCRIPT" | sort -t'|' -k2,2Vr -k1,1 -k3,3nr)
done


if [ ${#CAPTURE_MODES[@]} -eq 0 ]; then
    echo "致命的エラー: 映像デバイスの性能を読み取れんかった。すまぬが、わっちの力ではここまでじゃ..."
    exit 1
fi

PS3="キャプチャモードの番号: "
select mode_choice in "${CAPTURE_MODES[@]}"; do
    if [[ -n "$mode_choice" ]]; then
        VIDEO_DEVICE=$(echo "$mode_choice" | grep -oP '\(\K/dev/video\d+(?=\))')
        VIDEO_SIZE=$(echo "$mode_choice" | awk -F'- ' '{print $2}' | awk '{print $1}')
        INPUT_FORMAT_CODE=$(echo "$mode_choice" | awk -F'- ' '{print $2}' | awk '{print $2}')
        FRAMERATE=$(echo "$mode_choice" | grep -oP '@ \K[0-9.]+')
        
        if [ "$INPUT_FORMAT_CODE" == "YUYV" ]; then
            INPUT_FORMAT_FFMPEG="yuyv422"
        elif [ "$INPUT_FORMAT_CODE" == "MJPG" ]; then
            INPUT_FORMAT_FFMPEG="mjpeg"
        else
            INPUT_FORMAT_FFMPEG="mjpeg"
        fi
        
        echo "» ${mode_choice} を選んだのじゃな。"
        break
    else
        echo "不正な選択じゃ。もう一度選ぶのじゃ。"
    fi
done

# プレビューのみモード(2)でなければ、音声やコーデックを選択
if [ "$OPERATION_MODE" -ne 2 ]; then
    # --- 音声デバイスの選択 ---
    echo ""
    echo "次はどの音声デバイスを使う？"
    AUDIO_DEVICES_MENU=()
    AUDIO_DEVICES_ID=()
    while IFS= read -r line; do
        card_num=$(echo "$line" | grep -oP 'card \K[0-9]+')
        device_name=$(echo "$line" | grep -oP '\[\K[^\]]+')
        identifier="hw:${card_num},0"
        menu_item="${identifier} (${device_name})"
        AUDIO_DEVICES_ID+=("$identifier")
        AUDIO_DEVICES_MENU+=("$menu_item")
    done < <(LC_ALL=C arecord -l | grep "^card")

    PS3="音声デバイスの番号: "
    select audio_choice_menu in "${AUDIO_DEVICES_MENU[@]}"; do
        if [[ -n "$audio_choice_menu" ]]; then
            AUDIO_DEVICE="${AUDIO_DEVICES_ID[$REPLY - 1]}"
            echo "» ${audio_choice_menu} を選んだのじゃな。"
            break
        else
            echo "不正な選択じゃ。もう一度選ぶのじゃ。"
        fi
    done

    # --- 映像コーデックの選択 ---
    echo ""
    echo "映像コーデックはどうするんじゃ？ 低負荷・高画質優先で設定してやるぞ。"
    VIDEO_CODECS=("H.264(超高速CPU)" "AV1(高速CPU)" "VP9(高速CPU)")
    PS3="映像コーデックの番号: "
    declare -a VIDEO_CODEC_OPTS
    select vcodec_choice in "${VIDEO_CODECS[@]}"; do
        case $REPLY in
            1)
                echo "» 信頼性重視！ CPU超高速エンコード(libx264)を選ぶぞ。"
                VIDEO_CODEC_OPTS=("-c:v" "libx264" "-preset" "ultrafast" "-crf" "20" "-pix_fmt" "yuv420p")
                break;;
            2)
                echo "» AV1じゃな。新しいコーデックじゃが、負荷は高めじゃぞ。"
                VIDEO_CODEC_OPTS=("-c:v" "libsvtav1" "-preset" "8" "-crf" "25" "-pix_fmt" "yuv420p"); break;;
            3)
                echo "» VP9じゃな。YouTubeが得意なやつじゃ。"
                VIDEO_CODEC_OPTS=("-c:v" "libvpx-vp9" "-deadline" "realtime" "-cpu-used" "8" "-crf" "22" "-b:v" "0" "-pix_fmt" "yuv420p"); break;;
            *) echo "不正な選択じゃ。もう一度選ぶのじゃ。";;
        esac
    done

    # --- 音声コーデックの選択 ---
    echo ""
    echo "音声コーデックは何がよいかの？"
    AUDIO_CODECS=("FLAC(無劣化)" "Opus(高音質)" "MP3(互換性重視)")
    PS3="音声コーデックの番号: "
    declare -a AUDIO_CODEC_OPTS
    select acodec_choice in "${AUDIO_CODECS[@]}"; do
        case $REPLY in
            1) AUDIO_CODEC_OPTS=("-c:a" "flac"); break;;
            2) AUDIO_CODEC_OPTS=("-c:a" "libopus" "-b:a" "192k"); break;;
            3) AUDIO_CODEC_OPTS=("-c:a" "libmp3lame" "-q:a" "2"); break;;
            *) echo "不正な選択じゃ。もう一度選ぶのじゃ。";;
        esac
    done

    # --- ファイル名の設定 ---
    FILENAME="capture-$(date +%Y%m%d-%H%M%S).mkv"
    echo ""
    read -p "出力ファイル名を入力するのじゃ (デフォルト: ${FILENAME}): " user_filename
    if [[ -n "$user_filename" ]]; then
        FILENAME="$user_filename"
    fi
fi

# --- 最終確認と実行 ---
echo ""
echo "--- 以下の設定で実行する。よろしいか？ ---"
echo "  動作モード        : ${mode_name}"
echo "  キャプチャモード: ${mode_choice}"
if [ "$OPERATION_MODE" -ne 2 ]; then
    echo "  音声入力        : ${audio_choice_menu}"
    echo "  映像コーデック    : ${vcodec_choice}"
    echo "  音声コーデック    : ${acodec_choice}"
    echo "  出力先          : ${FILENAME}"
fi
echo "------------------------------------------------"
read -p "開始するにはEnterキーを、中止するにはCtrl+Cを押すのじゃ..."

# OPERATION_MODEが1なら録画、2ならプレビュー
if [ "$OPERATION_MODE" -eq 1 ]; then
    echo "録画開始！ 終了するにはこの端末で 'q' キーを押すのじゃぞ。"
    sleep 1
    ffmpeg -thread_queue_size 512 \
        -f v4l2 -input_format "$INPUT_FORMAT_FFMPEG" -framerate "$FRAMERATE" -video_size "$VIDEO_SIZE" -i "$VIDEO_DEVICE" \
        -f alsa -i "$AUDIO_DEVICE" \
        "${VIDEO_CODEC_OPTS[@]}" \
        "${AUDIO_CODEC_OPTS[@]}" \
        "$FILENAME"
else # OPERATION_MODE is 2
    echo "プレビューを開始する！ 終了するにはプレビューウィンドウを閉じるか 'q' キーを押すのじゃ。"
    ffplay -f v4l2 -input_format "$INPUT_FORMAT_FFMPEG" -framerate "$FRAMERATE" -video_size "$VIDEO_SIZE" -i "$VIDEO_DEVICE"
fi

echo ""
echo "--- 処理を終了したぞ。お疲れさんじゃったな！ ---"
