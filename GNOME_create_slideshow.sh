#!/bin/bash

# --- 設定項目 ---
# 画像一枚あたりの表示時間（秒）
PICTURE_DURATION=120
# 画像が切り替わる時のアニメーション時間（秒）
TRANSITION_DURATION=5.0
# 出力するXMLファイル名（カレントディレクトリに作成）
OUTPUT_FILE="slideshow.xml"
# --- 設定ここまで ---

# ヘルプメッセージを表示する関数
show_help() {
  cat << EOF
Usage: $(basename "$0") <image_directory>

Description:
  指定したフォルダ内の画像からGNOMEの壁紙用スライドショーXMLファイルを生成し、壁紙に設定します。
  gnome-tweaksがインストールされていない場合は、インストールを試みます。

Arguments:
  image_directory   スライドショーに使用する画像が格納されているフォルダのパス。

Options:
  -h, --help        このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  show_help
  exit 0
fi

# 引数が指定されているかチェック
if [ -z "$1" ]; then
  echo "エラー: 画像フォルダが指定されていません。" >&2
  show_help
  exit 1
fi

IMAGE_DIR=$(realpath "$1")
OUTPUT_FILE_PATH="$(pwd)/$OUTPUT_FILE"

# フォルダが存在するかチェック
if [ ! -d "$IMAGE_DIR" ]; then
  echo "エラー: 指定されたフォルダ '$IMAGE_DIR' が見つかりません。" >&2
  exit 1
fi

# 画像ファイルを探す
IMAGE_FILES=()
while IFS= read -r -d $'\0'; do
  IMAGE_FILES+=("$REPLY")
done < <(find "$IMAGE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) -print0 | sort -z -R)

# 画像が見つからなかった場合
if [ ${#IMAGE_FILES[@]} -eq 0 ]; then
  echo "エラー: 指定されたフォルダ '$IMAGE_DIR' に画像ファイルが見つかりません。" >&2
  exit 1
fi

# XMLファイルを作成開始
(
  echo '<background>'
  echo '  <starttime>'
  echo '    <year>2020</year>'
  echo '    <month>01</month>'
  echo '    <day>01</day>'
  echo '    <hour>00</hour>'
  echo '    <minute>00</minute>'
  echo '    <second>00</second>'
  echo '  </starttime>'

  PREV_IMAGE=""
  for (( i=0; i<${#IMAGE_FILES[@]}; i++ )); do
    CURRENT_IMAGE="${IMAGE_FILES[$i]}"

    if [ $i -ne 0 ]; then
      echo '  <transition>'
      echo "    <duration>$TRANSITION_DURATION</duration>"
      echo "    <from>$PREV_IMAGE</from>"
      echo "    <to>$CURRENT_IMAGE</to>"
      echo '  </transition>'
    fi

    echo '  <static>'
    echo "    <duration>$PICTURE_DURATION</duration>"
    echo "    <file>$CURRENT_IMAGE</file>"
    echo '  </static>'

    PREV_IMAGE="$CURRENT_IMAGE"
  done

  # 最後の画像から最初の画像へのtransition
  echo '  <transition>'
  echo "    <duration>$TRANSITION_DURATION</duration>"
  echo "    <from>${IMAGE_FILES[-1]}</from>"
  echo "    <to>${IMAGE_FILES[0]}</to>"
  echo '  </transition>'

  echo '</background>'
) > "$OUTPUT_FILE_PATH"

echo "スライドショーファイル '$OUTPUT_FILE_PATH' を作成しました。"
echo "${#IMAGE_FILES[@]} 枚の画像が含まれています。"

# --- gnome-tweaksのインストールと壁紙設定 ---

# gnome-tweaksがインストールされているか確認
if ! command -v gnome-tweaks &> /dev/null; then
  echo "gnome-tweaksが見つかりません。インストールを試みます..."
  # sudoで実行するため、パスワードの入力が必要になる場合がある
  sudo apt update && sudo apt install -y gnome-tweaks
  if [ $? -ne 0 ]; then
    echo "エラー: gnome-tweaksのインストールに失敗しました。手動でインストールしてください。" >&2
    exit 1
  fi
  echo "gnome-tweaksのインストールが完了しました。"
fi

# gsettingsを使って壁紙を設定
echo "壁紙を設定しています..."
gsettings set org.gnome.desktop.background picture-uri "file://$OUTPUT_FILE_PATH"
gsettings set org.gnome.desktop.background picture-options 'zoom' # 'centered', 'scaled', 'spanned', 'wallpaper' なども可

echo "壁紙の設定が完了しました。gnome-tweaksを起動します。"

# gnome-tweaksをバックグラウンドで起動
gnome-tweaks &

echo "スクリプトは完了じゃ。gnome-tweaksの外観タブで設定を確認するがよい。"
