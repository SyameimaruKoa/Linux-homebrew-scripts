#!/bin/sh

# ヘルプメッセージを表示する関数
show_help() {
  cat << EOF
Usage: $(basename "$0")

Description:
  Ubuntuの起動モードをGUI (graphical.target) と CUI (multi-user.target) の間で切り替えます。
  スクリプトは対話形式で実行され、sudo権限が必要です。

Options:
  -h, --help    このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  show_help
  exit 0
fi

echo "set GUI"
echo "e) enable GUI"
echo "d) disable GUI"

read ANS

case "$ANS" in

	[eE]) # 大文字のEも受け付けるようにしたぞ

		sudo systemctl set-default graphical.target
		echo "Boot GUI Mode"
		;;

	[dD]) # 大文字のDも受け付けるようにしたぞ

		sudo systemctl set-default multi-user.target
		echo "Boot CUI Mode"
		;;

	*)

		# 何もしない
		echo "無効な選択じゃ。スクリプトを終了するぞ。"
		;;

esac
