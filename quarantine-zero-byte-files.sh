#!/bin/bash
# encoding: UTF-8

show_help() {
    cat <<EOF
使い方: ${0##*/} [オプション] [対象フォルダまたはパターン ...]

指定フォルダ以下の0Bの通常ファイルを、フォルダ構成を維持して
カレント内に新しく作る zero-byte-files-XXXXXX フォルダへ退避します。
指定省略時はカレント以下が対象です。複数指定・ワイルドカードに対応します。
カレント外のファイルは退避先の _external/ 以下に絶対パスの階層で保存します。
既定では候補表示のみです。0B以外の破損判定は行いません。
シンボリックリンクと、名前が zero-byte-files-* または zero-byte-files.* のディレクトリは対象外です。
指定に含まれる通常ファイルは読み飛ばし、フォルダだけを対象にします。
空ファイルが正常な用途もあるため、候補を確認してから実行してください。

オプション:
    -x, --execute  実際に退避します。
    -h, --help     このヘルプを表示します。
    --            以降をフォルダ指定として扱います。

例:
    ${0##*/}
    ${0##*/} --execute
    ${0##*/} 'album-*' './写真/*'
    ${0##*/} --execute folder1 /path/to/folder2
EOF
}

die() {
    echo "エラー: $*" >&2
    exit 1
}

execute=false
patterns=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -x|--execute) execute=true ;;
        -h|--help) show_help; exit 0 ;;
        --) shift; patterns+=("$@"); break ;;
        -*) die "不明なオプションです: $1" ;;
        *) patterns+=("$1") ;;
    esac
    shift
done
[ "${#patterns[@]}" -gt 0 ] || patterns=(.)

for cmd in find mktemp mkdir mv rm; do
    command -v "$cmd" >/dev/null 2>&1 || die "必須コマンド '$cmd' が見つかりません。"
done

work_dir=$(pwd -P) || die "カレントディレクトリを取得できません。"
declare -A selected_dirs=()
shopt -s nullglob dotglob
for pattern in "${patterns[@]}"; do
    # 実在する名前を優先し、引用されたパターンもシェルのglobで展開する。
    if [ -e "$pattern" ] || [ -L "$pattern" ]; then
        matches=("$pattern")
    else
        old_ifs=$IFS
        IFS=''
        matches=( $pattern )
        IFS=$old_ifs
    fi
    matched=false
    for directory in "${matches[@]}"; do
        [ -e "$directory" ] || [ -L "$directory" ] || continue
        matched=true
        [ -d "$directory" ] && [ ! -L "$directory" ] || continue
        directory=$(cd -- "$directory" && pwd -P) || die "フォルダを参照できません。"
        selected_dirs["$directory"]=1
    done
    $matched || die "指定に一致する項目がありません: $pattern"
done
[ "${#selected_dirs[@]}" -gt 0 ] || die "対象フォルダがありません。"

# 一覧を先に取得し、探索失敗時はファイルを移動しない。
file_list=$(mktemp) || die "候補一覧を作成できません。"
trap 'rm -f -- "$file_list"' EXIT
for directory in "${!selected_dirs[@]}"; do
    find "$directory" -type d \( -name 'zero-byte-files-*' -o -name 'zero-byte-files.*' \) -prune -o \
        -type f -size 0c -print0 >> "$file_list" || die "ファイルの探索に失敗しました。"
done

sources=()
relatives=()
declare -A seen_sources=() destinations=()
while IFS= read -r -d '' source; do
    [ -z "${seen_sources[$source]+set}" ] || continue
    seen_sources["$source"]=1
    if [[ "$source" == "${work_dir%/}/"* ]]; then
        relative=${source#"${work_dir%/}/"}
    else
        relative="_external/${source#/}"
    fi
    [ -z "${destinations[$relative]+set}" ] || die "退避先のパスが重複します: $relative"
    destinations["$relative"]=1
    sources+=("$source")
    relatives+=("$relative")
done < "$file_list"

echo "退避候補: ${#sources[@]} 個"
for index in "${!sources[@]}"; do
    printf '  %q -> %q\n' "${sources[$index]}" "${relatives[$index]}"
done

if ! $execute; then
    echo "dry-run: 実際に退避するには --execute を指定してください。"
    exit 0
fi
[ "${#sources[@]}" -gt 0 ] || exit 0

destination_root=$(mktemp -d ./zero-byte-files-XXXXXX) || die "退避フォルダを作成できません。"
printf '退避先: %q\n' "$destination_root"
count=0
for index in "${!sources[@]}"; do
    source=${sources[$index]}
    # 探索後に内容が書き込まれたファイルやリンクへの置換は移動しない。
    if [ ! -f "$source" ] || [ -L "$source" ] || [ -s "$source" ]; then
        printf 'スキップ（状態変更）: %q\n' "$source" >&2
        continue
    fi
    relative=${relatives[$index]}
    destination="$destination_root/$relative"
    mkdir -p -- "${destination%/*}" || die "退避先の階層を作成できません: $relative"
    mv -n -- "$source" "$destination" || die "移動に失敗しました: $relative"
    [ ! -e "$source" ] && [ ! -L "$source" ] || die "元ファイルが残っています: $relative"
    ((count += 1))
done
echo "完了: ${count} 個のファイルを退避しました。"
