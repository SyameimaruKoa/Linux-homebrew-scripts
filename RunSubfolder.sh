#!/bin/bash
# encoding: UTF-8

# ヘルプメッセージを表示する関数
show_help() {
  cat << EOF
Usage: $(basename "$0") <script_to_run> [script_arguments...]

Description:
  カレントディレクトリ配下の全てのサブディレクトリに移動し、
  指定されたスクリプトを、指定された引数と共に実行します。

Arguments:
  script_to_run      各サブディレクトリで実行するシェルスクリプトのパス。
  script_arguments   実行するスクリプトに渡す引数 (任意)。

Options:
  -h, --help         このヘルプメッセージを表示して終了します。
EOF
}

# -h または --help が引数として渡された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  show_help
  exit 0
fi

# 必須の引数がない場合はヘルプを表示して終了
if [ -z "$1" ]; then
  echo "エラー: 実行するスクリプトが指定されていません。" >&2
  show_help
  exit 1
fi

# bash ［このファイル］ ［各フォルダ内で実行したいスクリプト］ ［スクリプトへの引数］
# 現在のディレクトリからサブディレクトリを列挙し、各サブディレクトリ内で指定されたスクリプトを実行するのじゃ。

# 実行するスクリプトと、それに渡す引数を変数に格納
main_script_to_run="$1"
shift
script_args=("$@")

find . -mindepth 1 -type d | while read -r subdir; do
  # メインスクリプトからの出力であることを明確にするのじゃ。
  echo "[メインスクリプト] 「$subdir」に移動してスクリプトを実行するのじゃ"

  # サブシェル内でディレクトリを移動し、スクリプトを実行するのじゃ。
  # これにより、メインのスクリプトの現在の作業ディレクトリは変わらないままなのじゃ。
  (cd "$subdir" && bash "$main_script_to_run" "${script_args[@]}")

  # 空行を出力するのじゃ。
  echo
done
