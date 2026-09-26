#!/bin/bash
# encoding: UTF-8

show_help() {
    cat <<EOF
使い方: $(basename "$0") <status|park|unpark|cstate|uncstate|freq> [オプション]

Linux の sysfs を使い、論理 CPU（コア／スレッド）の状態確認、停止、再開を行います。

コマンド:
    status              CPU 構成、ハイブリッド構成、オンライン状態を表示します。
    park                指定した論理 CPU をオフラインにします（root 権限が必要）。
    unpark              指定した論理 CPU をオンラインにします（root 権限が必要）。
    cstate              指定したオンライン CPU で浅い idle state を無効にし、深い state を選びやすくします。
    uncstate            指定したオンライン CPU で、対象 state より浅い state を再有効化します。
    freq                指定 CPU の最小・最大クロックを制限します（root 権限が必要）。

オプション:
    -c, --cpus LIST     対象 CPU。例: 1,3-5,8（park/unpark/cstate/uncstate/freq で必須）。
    -s, --state NAME    C-state 名（例: C3, C6）。cstate/uncstate で必須。
    --min-mhz VALUE     最低クロック（MHz）。freq で任意。
    --max-mhz VALUE     最高クロック（MHz）。freq で任意。
    -h, --help          このヘルプを表示します。

例:
    $(basename "$0") status
    sudo $(basename "$0") park --cpus 4-7
    sudo $(basename "$0") unpark --cpus 4,6
    sudo $(basename "$0") cstate --cpus 4-7 --state C3
    sudo $(basename "$0") uncstate --cpus 4-7 --state C3
    sudo $(basename "$0") freq --cpus 4-7 --max-mhz 1800

注意:
    CPU 0、および online ファイルを持たない CPU は停止できません。
    C-state はオンライン CPU の idle 時にのみ選択されます。offline CPU には設定できません。
    C-state は idle 時の選択候補を制限します。実行中の CPU を特定 state に強制滞在させる機能ではありません。
    freq は CPUFreq policy を変更します。同じ policy を共有する CPU にも反映されます。
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
    show_frequency_status
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
        printf '  CPU %-4s 無効: %s%s\n' "$cpu" "${disabled_states:-なし}" "${pending:+ / $pending}"
    done
    [ "$found" -eq 1 ] || echo "  cpuidle 情報を取得できません"
}

show_frequency_status() {
    local cpu_dir cpu policy min max current
    echo
    echo "クロック制限 (MHz):"
    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -d "$cpu_dir" ] || continue
        cpu="${cpu_dir##*cpu}"
        policy="$(readlink -f "$cpu_dir/cpufreq" 2>/dev/null)"
        [ -n "$policy" ] && [ -r "$policy/scaling_min_freq" ] && [ -r "$policy/scaling_max_freq" ] || {
            printf '  CPU %-4s 未対応\n' "$cpu"
            continue
        }
        min="$(<"$policy/scaling_min_freq")"
        max="$(<"$policy/scaling_max_freq")"
        current="-"
        [ ! -r "$policy/scaling_cur_freq" ] || current="$(<"$policy/scaling_cur_freq")"
        if [ "$current" = - ]; then current_mhz=-; else current_mhz="$((current / 1000))"; fi
        printf '  CPU %-4s min=%s max=%s current=%s\n' "$cpu" "$((min / 1000))" "$((max / 1000))" "$current_mhz"
    done
}

set_frequency() {
    local list="$1" min_mhz="$2" max_mhz="$3"
    local cpu cpu_dir policy min_khz max_khz old_min old_max actual current_mhz
    local cpus=() policies=()
    local -A seen=()
    [ -n "$min_mhz" ] || [ -n "$max_mhz" ] || die "freq には --min-mhz または --max-mhz が必要です。"
    [ "$(id -u)" -eq 0 ] || die "freq には root 権限が必要です。sudo で実行してください。"
    validate_cpu_list "$list"
    for value in "$min_mhz" "$max_mhz"; do
        [ -z "$value" ] || [[ "$value" =~ ^[0-9]+$ ]] || die "クロック値は正の整数 MHz で指定してください: $value"
        [ -z "$value" ] || [ "$value" -gt 0 ] || die "クロック値は 0 より大きくしてください。"
    done
    [ -z "$min_mhz" ] || [ -z "$max_mhz" ] || [ "$min_mhz" -le "$max_mhz" ] || die "最小クロックは最大クロック以下にしてください。"
    mapfile -t cpus < <(expand_cpu_list "$list")
    for cpu in "${cpus[@]}"; do
        cpu_dir="/sys/devices/system/cpu/cpu${cpu}"
        [ -d "$cpu_dir" ] || die "CPU $cpu は存在しません。"
        [ ! -r "$cpu_dir/online" ] || [ "$(<"$cpu_dir/online")" = 1 ] || die "CPU $cpu は offline です。"
        policy="$(readlink -f "$cpu_dir/cpufreq" 2>/dev/null)"
        [ -n "$policy" ] && [ -r "$policy/scaling_min_freq" ] && [ -r "$policy/scaling_max_freq" ] || die "CPU $cpu に変更可能な cpufreq policy がありません。"
        if [ -z "${seen[$policy]:-}" ]; then policies+=("$policy"); seen[$policy]=1; fi
    done
    for policy in "${policies[@]}"; do
        old_min="$(<"$policy/scaling_min_freq")"
        old_max="$(<"$policy/scaling_max_freq")"
        min_khz="$old_min"; max_khz="$old_max"
        [ -z "$min_mhz" ] || min_khz="$((min_mhz * 1000))"
        [ -z "$max_mhz" ] || max_khz="$((max_mhz * 1000))"
        [ "$min_khz" -le "$max_khz" ] || die "${policy##*/}: 最小クロックが最大クロックを超えています。"
        [ -w "$policy/scaling_min_freq" ] && [ -w "$policy/scaling_max_freq" ] || die "${policy##*/} のクロック制限を変更できません。"
    done
    for policy in "${policies[@]}"; do
        old_min="$(<"$policy/scaling_min_freq")"; old_max="$(<"$policy/scaling_max_freq")"
        min_khz="$old_min"; max_khz="$old_max"
        [ -z "$min_mhz" ] || min_khz="$((min_mhz * 1000))"
        [ -z "$max_mhz" ] || max_khz="$((max_mhz * 1000))"
        # 制限範囲が交差する場合は、先に反対側の値を動かして矛盾を避ける。
        if [ "$max_khz" -lt "$old_min" ]; then
            printf '%s' "$min_khz" > "$policy/scaling_min_freq" || die "${policy##*/}: 最小値を先に調整できません。"
        elif [ "$min_khz" -gt "$old_max" ]; then
            printf '%s' "$max_khz" > "$policy/scaling_max_freq" || die "${policy##*/}: 最大値を先に調整できません。"
        fi
        if [ -n "$min_mhz" ]; then
            printf '%s' "$min_khz" > "$policy/scaling_min_freq" 2>/dev/null || die "${policy##*/}: 最小値を書き込めませんでした。"
        fi
        if [ -n "$max_mhz" ]; then
            printf '%s' "$max_khz" > "$policy/scaling_max_freq" 2>/dev/null || die "${policy##*/}: 最大値を書き込めませんでした。"
        fi
        actual="$(<"$policy/scaling_min_freq")"
        old_min="$actual"
        actual="$(<"$policy/scaling_max_freq")"
        if { [ -z "$min_mhz" ] || [ "$old_min" = "$min_khz" ]; } && { [ -z "$max_mhz" ] || [ "$actual" = "$max_khz" ]; }; then
            printf '%s: min=%d MHz max=%d MHz 適用確認済み\n' "${policy##*/}" "$((old_min / 1000))" "$((actual / 1000))"
        else
            printf '%s: 要求 min=%s max=%s MHz / 実際 min=%d max=%d MHz（未適用またはカーネル補正）\n' "${policy##*/}" "${min_mhz:--}" "${max_mhz:--}" "$((old_min / 1000))" "$((actual / 1000))" >&2
        fi
    done
}

set_cstate() {
    local action="$1"
    local list="$2"
    local target="$3"
    local cpu cpu_dir state_dir name state_index target_index disable_file desired label changed=0 verify online_file disabled_list="" deeper_available
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
        online_file="$cpu_dir/online"
        if [ -r "$online_file" ] && [ "$(<"$online_file")" != 1 ]; then
            rm -f "/run/cpu-core-parking/cpu${cpu}.state"
            die "CPU $cpu は offline です。省電力目的の C-state 設定は online CPU にだけ適用できます。"
        fi
        if [ -d "$cpu_dir/cpuidle" ]; then
            for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
                [ -d "$state_dir" ] || continue
                name="$(<"$state_dir/name")"
                if [ "${name^^}" = "$target" ]; then
                    selected["$cpu:target_index"]="${state_dir##*state}"
                    break
                fi
            done
            [ -n "${selected[$cpu:target_index]:-}" ] || die "CPU $cpu に C-state '$target' はありません。"
        else
            die "CPU $cpu の cpuidle 情報がありません。"
        fi
    done

    if [ "$action" = "cstate" ]; then
        desired=1
        label="浅いstateを無効化"
    else
        desired=0
        label="浅いstateを再有効化"
    fi

    for cpu in "${cpus[@]}"; do
        cpu_dir="/sys/devices/system/cpu/cpu${cpu}"
        target_index="${selected[$cpu:target_index]}"
        changed=0
        for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
            [ -d "$state_dir" ] || continue
            name="$(<"$state_dir/name")"
            state_index="${state_dir##*state}"
            if [ "$state_index" -lt "$target_index" ]; then
                [ "$(<"$state_dir/disable")" = "$desired" ] || continue
            else
                continue
            fi
            disable_file="$state_dir/disable"
            [ -w "$disable_file" ] || die "${cpu_dir##*/} $name を変更できません: $disable_file"
        done
        for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
            [ -d "$state_dir" ] || continue
            name="$(<"$state_dir/name")"
            state_index="${state_dir##*state}"
            if [ "$state_index" -lt "$target_index" ]; then
                [ "$(<"$state_dir/disable")" = "$desired" ] || continue
            else
                continue
            fi
            printf '%s' "$desired" > "$state_dir/disable" || die "${cpu_dir##*/} $name の変更に失敗しました。"
            verify="$(<"$state_dir/disable")"
            [ "$verify" = "$desired" ] || die "${cpu_dir##*/} $name の設定を確認できません（disable=$verify）。"
            changed=$((changed + 1))
            disabled_list+="${disabled_list:+,}$name"
        done
        if [ "$action" = "cstate" ]; then
            deeper_available=0
            for state_dir in "$cpu_dir"/cpuidle/state[0-9]*; do
                [ -d "$state_dir" ] || continue
                state_index="${state_dir##*state}"
                [ "$state_index" -gt "$target_index" ] || continue
                deeper_available=1
                if [ "$(<"$state_dir/disable")" != 0 ]; then
                    die "CPU $cpu: $target より深い state $(<"$state_dir/name") が無効です。浅い state を閉じても深い idle state を選べません。"
                fi
            done
            if [ "$deeper_available" -eq 0 ]; then
                echo "注意: CPU $cpu の $target は最深 state のため、それより浅い state の無効化だけでは $target を選びやすくできません。" >&2
            fi
        fi
        printf 'CPU %s: %sより浅いstate %d個を%s%s（sysfs確認済み）。\n' "$cpu" "$target" "$changed" "$label" "${disabled_list:+: $disabled_list}"
        disabled_list=""
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
        [ "$latency" -lt "$target_latency" ] || [ "$residency" -lt "$target_residency" ] || continue
        printf '%s' "$desired" > "$state_dir/disable" || die "CPU $cpu $name の設定に失敗しました。"
        verify="$(<"$state_dir/disable")"
        [ "$verify" = "$desired" ] || die "CPU $cpu $name の設定を確認できません（disable=$verify）。"
    done
}

require_commands find sort sed wc id

action="${1:-}"
case "$action" in
    -h|--help)
        show_help
        exit 0
        ;;
    status|park|unpark|cstate|uncstate|freq)
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
min_mhz=""
max_mhz=""
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
        --min-mhz)
            [ "$#" -ge 2 ] || die "$1 には値が必要です。"
            min_mhz="$2"
            shift 2
            ;;
        --max-mhz)
            [ "$#" -ge 2 ] || die "$1 には値が必要です。"
            max_mhz="$2"
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
elif [ "$action" = "freq" ]; then
    [ -z "$state_name" ] || die "freq では --state を指定できません。"
    [ -n "$cpu_list" ] || die "freq には --cpus LIST が必要です。"
    set_frequency "$cpu_list" "$min_mhz" "$max_mhz"
elif [ "$action" = "cstate" ] || [ "$action" = "uncstate" ]; then
    [ -n "$cpu_list" ] || die "$action には --cpus LIST が必要です。"
    set_cstate "$action" "$cpu_list" "$state_name"
else
    [ -z "$state_name" ] && [ -z "$min_mhz" ] && [ -z "$max_mhz" ] || die "$action では state/freq オプションを指定できません。"
    [ -n "$cpu_list" ] || die "$action には --cpus LIST が必要です。"
    set_cpu_state "$action" "$cpu_list"
fi
