#!/bin/bash
# encoding: UTF-8

show_help() {
    cat <<EOF
使い方: $(basename "$0") <status|park|unpark> [オプション]

Linux の sysfs を使い、論理 CPU（コア／スレッド）の状態確認、停止、再開を行います。

コマンド:
    status              CPU 構成、ハイブリッド構成、オンライン状態を表示します。
    park                指定した論理 CPU をオフラインにします（root 権限が必要）。
    unpark              指定した論理 CPU をオンラインにします（root 権限が必要）。

オプション:
    -c, --cpus LIST     対象 CPU。例: 1,3-5,8（park/unpark では必須）。
    -h, --help          このヘルプを表示します。

例:
    $(basename "$0") status
    sudo $(basename "$0") park --cpus 4-7
    sudo $(basename "$0") unpark --cpus 4,6

注意:
    CPU 0、および online ファイルを持たない CPU は停止できません。
    ハイブリッド判定は sysfs の core_type を優先し、無い環境では最大周波数差を参考表示します。
EOF
}

die() {
    echo "エラー: $*" >&2
    exit 1
}

require_commands() {
    local missing=0
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "エラー: 必須コマンド '$cmd' が見つかりません。" >&2
            missing=1
        fi
    done
    [ "$missing" -eq 0 ] || exit 1
}

validate_cpu_list() {
    local list="$1"
    local item start end
    [[ "$list" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || die "CPU リストの形式が不正です: $list"
    IFS=',' read -ra items <<< "$list"
    for item in "${items[@]}"; do
        if [[ "$item" == *-* ]]; then
            start="${item%-*}"
            end="${item#*-}"
            [ "$start" -le "$end" ] || die "CPU 範囲が逆順です: $item"
        fi
    done
}

expand_cpu_list() {
    local list="$1"
    local item start end cpu
    IFS=',' read -ra items <<< "$list"
    for item in "${items[@]}"; do
        if [[ "$item" == *-* ]]; then
            start="${item%-*}"
            end="${item#*-}"
            for ((cpu = start; cpu <= end; cpu++)); do
                echo "$cpu"
            done
        else
            echo "$item"
        fi
    done | sort -n -u
}

cpu_state() {
    local cpu="$1"
    local online_file="/sys/devices/system/cpu/cpu${cpu}/online"
    if [ -r "$online_file" ]; then
        [ "$(<"$online_file")" = "1" ] && echo "online" || echo "parked"
    else
        echo "online (固定)"
    fi
}

cpu_kind() {
    local cpu="$1"
    local type_file="/sys/devices/system/cpu/cpu${cpu}/topology/core_type"
    local freq_file="/sys/devices/system/cpu/cpu${cpu}/cpufreq/cpuinfo_max_freq"
    if [ -r "$type_file" ]; then
        case "$(<"$type_file")" in
            1) echo "Atom/E-core" ;;
            2) echo "Core/P-core" ;;
            *) echo "type=$(<"$type_file")" ;;
        esac
    elif [ -r "$freq_file" ]; then
        echo "max=$(<"$freq_file")kHz"
    else
        echo "unknown"
    fi
}

show_status() {
    local cpu_dir cpu package core sibling kind state
    local kinds=""
    printf '%-6s %-8s %-8s %-16s %-16s %s\n' "CPU" "PACKAGE" "CORE" "SIBLINGS" "TYPE/FREQ" "STATE"
    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -d "$cpu_dir" ] || continue
        cpu="${cpu_dir##*cpu}"
        package="$(<"$cpu_dir/topology/physical_package_id")"
        core="$(<"$cpu_dir/topology/core_id")"
        sibling="$(<"$cpu_dir/topology/thread_siblings_list")"
        kind="$(cpu_kind "$cpu")"
        state="$(cpu_state "$cpu")"
        kinds+="$kind"$'\n'
        printf '%-6s %-8s %-8s %-16s %-16s %s\n' "$cpu" "$package" "$core" "$sibling" "$kind" "$state"
    done
    echo
    echo "論理 CPU 数: $(find /sys/devices/system/cpu -maxdepth 1 -type d -name 'cpu[0-9]*' | wc -l)"
    echo "物理コア数: $(for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do printf '%s:%s\n' "$(<"$cpu_dir/topology/physical_package_id")" "$(<"$cpu_dir/topology/core_id")"; done | sort -u | wc -l)"
    if [ "$(printf '%s' "$kinds" | sed '/^$/d' | sort -u | wc -l)" -gt 1 ]; then
        echo "ハイブリッド構成: 検出（TYPE/FREQ が複数種類）"
    else
        echo "ハイブリッド構成: 未検出"
    fi
}

set_cpu_state() {
    local action="$1"
    local list="$2"
    local value cpu online_file label
    local cpus=()
    validate_cpu_list "$list"
    [ "$(id -u)" -eq 0 ] || die "$action には root 権限が必要です。sudo で実行してください。"
    if [ "$action" = "park" ]; then
        value=0
        label="停止"
    else
        value=1
        label="再開"
    fi
    mapfile -t cpus < <(expand_cpu_list "$list")
    for cpu in "${cpus[@]}"; do
        [ -d "/sys/devices/system/cpu/cpu${cpu}" ] || die "CPU $cpu は存在しません。"
        [ "$cpu" != "0" ] || die "CPU 0 は停止・変更対象にできません。"
        online_file="/sys/devices/system/cpu/cpu${cpu}/online"
        [ -w "$online_file" ] || die "CPU $cpu の状態は変更できません: $online_file"
    done
    for cpu in "${cpus[@]}"; do
        online_file="/sys/devices/system/cpu/cpu${cpu}/online"
        printf '%s' "$value" > "$online_file" || die "CPU $cpu の変更に失敗しました。"
        echo "CPU $cpu を${label}しました。"
    done
}

require_commands find sort sed wc id

action="${1:-}"
case "$action" in
    -h|--help)
        show_help
        exit 0
        ;;
    status|park|unpark)
        shift
        ;;
    *)
        show_help
        [ -n "$action" ] && echo "エラー: 不明なコマンドです: $action" >&2
        exit 1
        ;;
esac

cpu_list=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -c|--cpus)
            [ "$#" -ge 2 ] || die "$1 には値が必要です。"
            cpu_list="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            die "不明なオプションです: $1"
            ;;
    esac
done

if [ "$action" = "status" ]; then
    [ -z "$cpu_list" ] || die "status では --cpus を指定できません。"
    show_status
else
    [ -n "$cpu_list" ] || die "$action には --cpus LIST が必要です。"
    set_cpu_state "$action" "$cpu_list"
fi
