#!/bin/bash
# encoding: UTF-8

show_help() {
    cat <<EOF
使い方: $(basename "$0") [オプション] <パターン> [パターン...]

カレントディレクトリ直下でパターンに一致するフォルダの全ファイルを、
ディレクトリ構造を破棄してカレントディレクトリへ移動します。
空になった対象フォルダは削除します。既定は dry-run です。

オプション:
    -x, --execute       実際に移動・削除します。
    -h, --help          このヘルプを表示します。

例（シェルによる展開を防ぐためパターンを引用符で囲みます）:
    $(basename "$0") 'album-*'
    $(basename "$0") --execute 'album-*' 'disc?'

安全仕様:
    同名ファイルがカレントに存在する、または複数の対象内で名前が重複する場合は、
    何も変更せずエラー終了します。シンボリックリンクはファイルとして移動します。
EOF
}

die() {
    echo "エラー: $*" >&2
    exit 1
}

require_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "必須コマンド '$cmd' が見つかりません。"
    done
}

require_commands find mv

execute=false
patterns=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -x|--execute) execute=true ;;
        -h|--help) show_help; exit 0 ;;
        -*) die "不明なオプションです: $1" ;;
        *) patterns+=("$1") ;;
    esac
    shift
done

[ "${#patterns[@]}" -gt 0 ] || { show_help; exit 1; }

work_dir="$(pwd -P)"
declare -A selected_dirs=()
for pattern in "${patterns[@]}"; do
    matched=false
    while IFS= read -r -d '' directory; do
        selected_dirs["$directory"]=1
        matched=true
    done < <(find "$work_dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" -print0)
    $matched || echo "警告: パターンに一致するフォルダがありません: $pattern" >&2
done

[ "${#selected_dirs[@]}" -gt 0 ] || die "対象フォルダがありません。"

declare -A destinations=()
sources=()
for directory in "${!selected_dirs[@]}"; do
    while IFS= read -r -d '' source; do
        relative="${source#"$directory"/}"
        name="${source##*/}"
        destination="$work_dir/$name"
        if [ -e "$destination" ] || [ -L "$destination" ]; then
            die "移動先に同名項目があります: $destination（元: $relative）"
        fi
        if [ -n "${destinations[$destination]+set}" ]; then
            die "対象内でファイル名が重複しています: $name"
        fi
        destinations["$destination"]="$source"
        sources+=("$source")
    done < <(find "$directory" -mindepth 1 \( -type f -o -type l \) -print0)
done

echo "対象フォルダ数: ${#selected_dirs[@]}"
echo "移動ファイル数: ${#sources[@]}"
for source in "${sources[@]}"; do
    echo "${source#"$work_dir"/} -> ${source##*/}"
done

if ! $execute; then
    echo "dry-run: 実際に処理するには --execute を指定してください。"
    exit 0
fi

for source in "${sources[@]}"; do
    mv -- "$source" "$work_dir/${source##*/}" || die "移動に失敗しました: $source"
done

for directory in "${!selected_dirs[@]}"; do
    find "$directory" -depth -type d -empty -delete
done
echo "完了しました。"
