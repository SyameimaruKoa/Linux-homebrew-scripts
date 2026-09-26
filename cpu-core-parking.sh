#!/bin/bash
# encoding: UTF-8

show_help() {
    cat <<EOF
使い方: $(basename "$0") <status|park|unpark|cstate|uncstate> [オプション]

Linux の sysfs を使い、論理 CPU（コア／スレッド）の状態確認、停止、再開を行います。

コマンド:
    status              CPU 構成、ハイブリッド構成、オンライン状態を表示します。
    park                指定した論理 CPU をオフラインにします（root 権限が必要）。
    unpark              指定した論理 CPU をオンラインにします（root 権限が必要）。
    cstate              指定 CPU で、指定した C-state より深い idle state を無効にします。
    uncstate            指定 CPU で、指定した C-state より深い idle state を有効にします。

オプション:
    -c, --cpus LIST     対象 CPU。例: 1,3-5,8（park/unpark/cstate/uncstate で必須）。
    -s, --state NAME    C-state 名（例: C3, C6）。cstate/uncstate で必須。
    -h, --help          このヘルプを表示します。

例:
    $(basename "$0") status
    sudo $(basename "$0") park --cpus 4-7
    sudo $(basename "$0") unpark --cpus 4,6
    sudo $(basename "$0") cstate --cpus 4-7 --state C3
    sudo $(basename "$0") uncstate --cpus 4-7 --state C3

注意:
    CPU 0、および online ファイルを持たない CPU は停止できません。
    offline 前に cstate を設定すると、unpark 後にその CPU へ設定を適用します。
    cstate C3 は C3 より深い state を無効化します（C3 自体は利用可能です）。
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
        local max_freq
        max_freq="$(<"$freq_file")"
        printf 'max=%sMHz\n' "$(( (max_freq + 500) / 1000 ))"
    else
        echo "unknown"
    fi
}

show_status() {
    local cpu_dir cpu package core sibling kind state
    local kinds=""
    local cpu_dirs=()
    mapfile -t cpu_dirs < <(printf '%s\n' /sys/devices/system/cpu/cpu[0-9]* | sort -V)
    printf '%-6s %-8s %-8s %-16s %-16s %s\n' "CPU" "PACKAGE" "CORE" "SIBLINGS" "TYPE/FREQ" "STATE"
    for cpu_dir in "${cpu_dirs[@]}"; do
        [ -d "$cpu_dir" ] || continue
        cpu="${cpu_dir##*cpu}"
        package="-"
        core="-"
        sibling="-"
        [ -r "$cpu_dir/topology/physical_package_id" ] && package="$(<"$cpu_dir/topology/physical_package_id")"
        [ -r "$cpu_dir/topology/core_id" ] && core="$(<"$cpu_dir/topology/core_id")"
        [ -r "$cpu_dir/topology/thread_siblings_list" ] && sibling="$(<"$cpu_dir/topology/thread_siblings_list")"
        kind="$(cpu_kind "$cpu")"
        state="$(cpu_state "$cpu")"
        kinds+="$kind"$'\n'
        printf '%-6s %-8s %-8s %-16s %-16s %s\n' "$cpu" "$package" "$core" "$sibling" "$kind" "$state"
    done
    echo
    echo "論理 CPU 数: $(find /sys/devices/system/cpu -maxdepth 1 -type d -name 'cpu[0-9]*' | wc -l)"
    echo "物理コア数: $(for cpu_dir in "${cpu_dirs[@]}"; do
        [ -r "$cpu_dir/topology/physical_package_id" ] && [ -r "$cpu_dir/topology/core_id" ] || continue
        printf '%s:%s\n' "$(<"$cpu_dir/topology/physical_package_id")" "$(<"$cpu_dir/topology/core_id")"
    done | sort -u | wc -l)"
    if [ "$(printf '%s' "$kinds" | sed '/^$/d' | sort -u | wc -l)" -gt 1 ]; then
        echo "ハイブリッド構成: 検出（TYPE/FREQ が複数種類）"
    else
        echo "ハイブリッド構成: 未検出"
    fi
    show_cstate_status
}

show_cstate_status() {
    local cpu_dir state_dir name disabled cpu disabled_states pending
    local found=0
    echo
    echo "C-state:"
    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -d "$cpu_dir" ] || continue
        cpu="${cpu_dir##*cpu}"
        if [ ! -d "$cpu_dir/cpuidle" ]; then
            printf '  CPU %-4s offline / cpuidle 情報なし\n' "$cpu"
            continue
        fi
        disabled_states=""
        for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
            [ -d "$state_dir" ] || continue
            found=1
            name="$(<"$state_dir/name")"
            disabled="$(<"$state_dir/disable")"
            [ "$disabled" = 1 ] && disabled_states+="${disabled_states:+,}$name"
        done
        pending=""
        if [ -r "/run/cpu-core-parking/cpu${cpu}.state" ]; then
            read -r name disabled < "/run/cpu-core-parking/cpu${cpu}.state"
            pending="保留:$nameより深いstateを$([ "$disabled" = 1 ] && echo 無効化 || echo 有効化)"
        fi
        printf '  CPU %-4s 無効: %s%s\n' "$cpu" "${disabled_states:-なし}" "${pending:+ / $pending}"
    done
    [ "$found" -eq 1 ] || echo "  cpuidle 情報を取得できません"
}

set_cstate() {
    local action="$1"
    local list="$2"
    local target="$3"
    local cpu cpu_dir state_dir name latency residency target_latency target_residency disable_file desired label changed=0 verify
    local cpus=()
    local -A selected=()

    [ -n "$target" ] || die "$action には --state NAME が必要です。"
    [ "$(id -u)" -eq 0 ] || die "$action には root 権限が必要です。sudo で実行してください。"
    validate_cpu_list "$list"
    target="${target^^}"
    [[ "$target" =~ ^(POLL|C[0-9]+[S]?)$ ]] || die "不正な C-state 名です: $target"
    mapfile -t cpus < <(expand_cpu_list "$list")

    for cpu in "${cpus[@]}"; do
        [ -d "/sys/devices/system/cpu/cpu${cpu}" ] || die "CPU $cpu は存在しません。"
        cpu_dir="/sys/devices/system/cpu/cpu${cpu}"
        if [ -d "$cpu_dir/cpuidle" ]; then
            for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
                [ -d "$state_dir" ] || continue
                name="$(<"$state_dir/name")"
                if [ "${name^^}" = "$target" ]; then
                    selected["$cpu:latency"]="$(<"$state_dir/latency")"
                    selected["$cpu:residency"]="$(<"$state_dir/residency")"
                    break
                fi
            done
            [ -n "${selected[$cpu:latency]:-}" ] || die "CPU $cpu に C-state '$target' はありません。"
        elif [ -f "/run/cpu-core-parking/cpu${cpu}.state" ]; then
            selected["$cpu:offline"]=1
        else
            die "CPU $cpu は offline で cpuidle 情報がありません。先に cstate --cpus $cpu --state $target を実行してください。"
        fi
    done

    if [ "$action" = "cstate" ]; then
        desired=1
        label="無効化"
    else
        desired=0
        label="有効化"
    fi

    for cpu in "${cpus[@]}"; do
        cpu_dir="/sys/devices/system/cpu/cpu${cpu}"
        if [ -n "${selected[$cpu:offline]:-}" ]; then
            mkdir -p /run/cpu-core-parking || die "C-state 設定の保存先を作成できません。"
            printf '%s %s\n' "$target" "$desired" > "/run/cpu-core-parking/cpu${cpu}.state"
            echo "CPU $cpu は offline のため、unpark 後に適用する設定を保存しました。"
            continue
        fi
        target_latency="${selected[$cpu:latency]}"
        target_residency="${selected[$cpu:residency]}"
        changed=0
        for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
            [ -d "$state_dir" ] || continue
            name="$(<"$state_dir/name")"
            latency="$(<"$state_dir/latency")"
            residency="$(<"$state_dir/residency")"
            [ "$latency" -gt "$target_latency" ] || [ "$residency" -gt "$target_residency" ] || continue
            disable_file="$state_dir/disable"
            [ -w "$disable_file" ] || die "${cpu_dir##*/} $name を変更できません: $disable_file"
        done
        for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
            [ -d "$state_dir" ] || continue
            name="$(<"$state_dir/name")"
            latency="$(<"$state_dir/latency")"
            residency="$(<"$state_dir/residency")"
            [ "$latency" -gt "$target_latency" ] || [ "$residency" -gt "$target_residency" ] || continue
            printf '%s' "$desired" > "$state_dir/disable" || die "${cpu_dir##*/} $name の変更に失敗しました。"
            verify="$(<"$state_dir/disable")"
            [ "$verify" = "$desired" ] || die "${cpu_dir##*/} $name の設定を確認できません（disable=$verify）。"
            changed=$((changed + 1))
        done
        printf 'CPU %s: %sより深いstateを%d個%s、sysfsで確認%s。\n' "$cpu" "$target" "$changed" "$label" "$([ "$changed" -gt 0 ] && echo 'しました' || echo '対象なし')"
    done
}

set_cpu_state() {
    local action="$1"
    local list="$2"
    local value cpu online_file label saved_state saved_name saved_setting state_dir
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
        if [ "$action" = "park" ] && [ -d "/sys/devices/system/cpu/cpu${cpu}/cpuidle" ]; then
            : > "/run/cpu-core-parking/cpu${cpu}.saved"
            for state_dir in "/sys/devices/system/cpu/cpu${cpu}"/cpuidle/state[0-9]*; do
                [ -d "$state_dir" ] || continue
                printf '%s %s\n' "$(<"$state_dir/name")" "$(<"$state_dir/disable")" >> "/run/cpu-core-parking/cpu${cpu}.saved"
            done
        fi
        printf '%s' "$value" > "$online_file" || die "CPU $cpu の変更に失敗しました。"
        echo "CPU $cpu を${label}しました。"
        if [ "$action" = "unpark" ] && [ -r "/run/cpu-core-parking/cpu${cpu}.state" ]; then
            read -r saved_name saved_setting < "/run/cpu-core-parking/cpu${cpu}.state"
            apply_cstate_to_cpu "$cpu" "$saved_name" "$saved_setting"
            rm -f "/run/cpu-core-parking/cpu${cpu}.state"
        elif [ "$action" = "unpark" ] && [ -r "/run/cpu-core-parking/cpu${cpu}.saved" ]; then
            while read -r saved_name saved_setting; do
                for state_dir in "/sys/devices/system/cpu/cpu${cpu}"/cpuidle/state[0-9]*; do
                    [ -d "$state_dir" ] || continue
                    [ "$(<"$state_dir/name")" = "$saved_name" ] || continue
                    printf '%s' "$saved_setting" > "$state_dir/disable" || die "CPU $cpu $saved_name の設定を復元できません。"
                done
            done < "/run/cpu-core-parking/cpu${cpu}.saved"
            rm -f "/run/cpu-core-parking/cpu${cpu}.saved"
        fi
    done
}

apply_cstate_to_cpu() {
    local cpu="$1" target="$2" desired="$3"
    local cpu_dir="/sys/devices/system/cpu/cpu${cpu}" state_dir name latency residency target_latency target_residency
    target_latency=""
    target_residency=""
    for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
        [ -d "$state_dir" ] || continue
        name="$(<"$state_dir/name")"
        [ "${name^^}" = "$target" ] || continue
        target_latency="$(<"$state_dir/latency")"
        target_residency="$(<"$state_dir/residency")"
        break
    done
    [ -n "$target_latency" ] || die "unpark 後の CPU $cpu に C-state '$target' がありません。"
    for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
        [ -d "$state_dir" ] || continue
        name="$(<"$state_dir/name")"
        latency="$(<"$state_dir/latency")"
        residency="$(<"$state_dir/residency")"
        [ "$latency" -gt "$target_latency" ] || [ "$residency" -gt "$target_residency" ] || continue
        printf '%s' "$desired" > "$state_dir/disable" || die "CPU $cpu $name の設定に失敗しました。"
        echo "CPU $cpu $name を$([ "$desired" = 1 ] && echo 無効化 || echo 有効化)しました。"
    done
}

require_commands find sort sed wc id

action="${1:-}"
case "$action" in
    -h|--help)
        show_help
        exit 0
        ;;
    status|park|unpark|cstate|uncstate)
        shift
        ;;
    *)
        show_help
        [ -n "$action" ] && echo "エラー: 不明なコマンドです: $action" >&2
        exit 1
        ;;
esac

cpu_list=""
state_name=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -c|--cpus)
            [ "$#" -ge 2 ] || die "$1 には値が必要です。"
            cpu_list="$2"
            shift 2
            ;;
        -s|--state)
            [ "$#" -ge 2 ] || die "$1 には値が必要です。"
            state_name="$2"
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
    [ -z "$cpu_list" ] && [ -z "$state_name" ] || die "status ではオプションを指定できません。"
    show_status
elif [ "$action" = "cstate" ] || [ "$action" = "uncstate" ]; then
    [ -n "$cpu_list" ] || die "$action には --cpus LIST が必要です。"
    set_cstate "$action" "$cpu_list" "$state_name"
else
    [ -z "$state_name" ] || die "$action では --state を指定できません。"
    [ -n "$cpu_list" ] || die "$action には --cpus LIST が必要です。"
    set_cpu_state "$action" "$cpu_list"
fi
