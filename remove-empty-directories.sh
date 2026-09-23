#!/bin/bash
# encoding: UTF-8

show_help() {
    cat <<EOF
使い方: $(basename "$0") [オプション] [対象ディレクトリ]

対象ディレクトリ以下にある空ディレクトリを、深い階層から順に削除します。
既定では候補を表示するだけで、--execute を指定した場合のみ削除します。

オプション:
    -x, --execute       実際に削除します。
    -i, --include-root  対象ディレクトリ自身も、空なら削除対象にします。
    -h, --help          このヘルプを表示します。

例:
    $(basename "$0") /path/to/tree
    $(basename "$0") --execute --include-root ./work
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

require_commands find rmdir

execute=false
include_root=false
target=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -x|--execute) execute=true ;;
        -i|--include-root) include_root=true ;;
        -h|--help) show_help; exit 0 ;;
        -*) die "不明なオプションです: $1" ;;
        *)
            [ -z "$target" ] || die "対象ディレクトリは1つだけ指定できます。"
            target="$1"
            ;;
    esac
    shift
done

target="${target:-.}"
[ -d "$target" ] || die "ディレクトリが見つかりません: $target"
target="$(cd "$target" && pwd -P)" || exit 1

if $include_root; then
    min_depth=0
else
    min_depth=1
fi

if $execute; then
    count=0
    while true; do
        removed_this_pass=0
        while IFS= read -r -d '' directory; do
            if rmdir -- "$directory"; then
                echo "削除: $directory"
                ((count += 1))
                ((removed_this_pass += 1))
            fi
        done < <(find "$target" -depth -mindepth "$min_depth" -type d -empty -print0)
        [ "$removed_this_pass" -gt 0 ] || break
        [ -d "$target" ] || break
    done
    echo "完了: ${count} 個の空ディレクトリを削除しました。"
else
    echo "削除候補（dry-run）:"
    find "$target" -depth -mindepth "$min_depth" -type d -empty -print
    echo "実際に削除するには --execute を指定してください。"
fi
