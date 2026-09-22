#!/usr/bin/env bash

set -u

usage() {
    cat <<'EOF'
Usage: Tailscale_Status-Loop.sh [-i seconds] [-o] [-d] [-h]
  -i, --interval     Refresh interval in seconds (1-3600; default: 1)
  -o, --online-only  Hide offline peers
  -d, --detail       Show last handshake / last seen
  -h, --help         Show this help

Requires tailscale and jq. Stop with Ctrl+C.
EOF
}

interval=1
online_only=false
detail=false
while (($#)); do
    case $1 in
        -i|--interval)
            if (($# < 2)); then usage >&2; exit 2; fi
            interval=$2; shift 2 ;;
        -o|--online-only) online_only=true; shift ;;
        -d|--detail) detail=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
if [[ ! $interval =~ ^[0-9]+$ ]] || ((10#$interval < 1 || 10#$interval > 3600)); then
    printf 'Interval must be between 1 and 3600 seconds.\n' >&2
    exit 2
fi
interval=$((10#$interval))
for command_name in tailscale jq; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

declare -A previous_rx previous_tx previous_rate previous_direction
previous_time=0

format_bytes() {
    awk -v n="${1:-0}" 'BEGIN { split("B KB MB GB TB", unit); i=1; while (n>=1024 && i<5) { n/=1024; i++ } if (i==1) printf "%.0f B",n; else printf "%.2f %s",n,unit[i] }'
}
format_rate() {
    awk -v n="$1" 'BEGIN { split("bit/s Kbit/s Mbit/s Gbit/s",unit); i=1; while (n>=1000 && i<4) { n/=1000; i++ } if (i==1) printf "%.0f%s",n,unit[i]; else printf "%.1f%s",n,unit[i] }'
}
cell() {
    local value=$1 width=$2
    if ((${#value} > width)); then value="${value:0:width-1}…"; fi
    printf '%-*s ' "$width" "$value"
}
draw() {
    local line
    if [[ -t 1 ]]; then printf '\033[H\033[J'; fi
    for line in "${lines[@]}"; do printf '%s\n' "$line"; done
}

while :; do
    lines=()
    if ! status=$(tailscale status --json 2>&1); then
        lines+=("ERROR: $status")
        previous_rx=(); previous_tx=(); previous_rate=(); previous_direction=(); previous_time=0
        draw
        sleep "$interval"
        continue
    fi
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$status"; then
        lines+=("ERROR: invalid tailscale status JSON")
        previous_rx=(); previous_tx=(); previous_rate=(); previous_direction=(); previous_time=0
        draw
        sleep "$interval"
        continue
    fi

    if netcheck=$(tailscale netcheck --format=json 2>/dev/null) &&
       jq -e 'type == "object"' >/dev/null 2>&1 <<<"$netcheck"; then
        g6=$(jq -r 'if (.GlobalV6 // "") != "" and ((.GlobalV6 | tostring) | test("invalid IP:port|0\\.0\\.0\\.0:0|\\[?::\\]?:0") | not) then "G6 YES \(.GlobalV6)" elif .IPv6 then "G6 NO-ADDR" else "G6 NO" end' <<<"$netcheck")
    else
        g6='G6 ?'
    fi

    summary=$(jq -r '
        def peers: (.Peer // {} | [.[] | select(. != null)]);
        def path: if (.Online | not) then "OFFLINE" elif (.CurAddr // "") != "" then "DIRECT" elif (.PeerRelay // "") != "" then "PEER" elif .Active and (.Relay // "") != "" then "DERP" else "IDLE" end;
        def name: (.DNSName // "" | rtrimstr(".") | split(".")[0] | if . == null or . == "" then "(unknown)" else . end);
        def ip($v;$kind): ($v // [] | map(select(if $kind == 4 then contains(":") | not else contains(":") end)) | first // "-");
        (peers) as $p | ($p | map(select(.Online))) as $on |
        [(.Self | name), ip(.Self.TailscaleIPs;4), ip(.Self.TailscaleIPs;6),
         ($on|length), ($p|length), ($p|map(select(.Active))|length),
         ($on|map(select(path == "DIRECT"))|length), ($on|map(select(path == "DERP"))|length),
         ($on|map(select(path == "PEER"))|length), ($on|map(select(path == "IDLE"))|length),
         ($on|map(select((.PrimaryRoutes // [])|length > 0))|length),
         ($on|map(select(.ExitNodeOption))|length)] | join("\u001f")' <<<"$status")
    IFS=$'\x1f' read -r self_name self_v4 self_v6 online_count peer_count active_count direct_count derp_count relay_count idle_count route_count exit_count <<<"$summary"
    lines+=("[$(date '+%Y-%m-%d %H:%M:%S')] Tailscale Status :: $self_name")
    lines+=("Local $self_name | IPv4 $self_v4 | IPv6 $self_v6")
    lines+=("Peers $online_count/$peer_count online | $active_count active | Direct $direct_count | DERP $derp_count | PeerRelay $relay_count | Idle $idle_count | SubnetRoutes $route_count | ExitCandidates $exit_count")
    lines+=("$(printf '%*s' 120 '' | tr ' ' '-')")
    if $detail; then
        lines+=("$(cell ST 7)$(cell PATH 12)$(cell ADDR 22)$(cell HOST 20)$(cell OS 7)$(cell IP 15)$(cell RATE 13)$(cell RX 11)$(cell TX 11)$(cell LAST 16)DIAG")
    else
        lines+=("$(cell ST 7)$(cell PATH 12)$(cell ADDR 22)$(cell HOST 22)$(cell OS 7)$(cell IP 15)$(cell RATE 13)$(cell RX 11)$(cell TX 11)DIAG")
    fi

    now=$(date +%s.%N)
    declare -A current_rx=() current_tx=() current_rate=() current_direction=()
    while IFS=$'\x1f' read -r key state path address name os ip rx tx last diag; do
        [[ -z $key ]] && continue
        if $online_only && [[ $state == OFFLINE ]]; then continue; fi
        rate='-'
        rate_value=${previous_rate[$key]:-}
        direction=${previous_direction[$key]:-}
        if [[ -v previous_rx[$key] ]] && [[ $previous_time != 0 ]]; then
            result=$(awk -v rx="$rx" -v tx="$tx" -v prx="${previous_rx[$key]}" -v ptx="${previous_tx[$key]}" -v now="$now" -v before="$previous_time" 'BEGIN { dt=now-before; if(dt<=0) exit; a=(rx>=prx)?(rx-prx)*8/dt:-1; b=(tx>=ptx)?(tx-ptx)*8/dt:-1; if(a>b && a>0) printf "RX %.4f",a; else if(b>a && b>0) printf "TX %.4f",b }')
            if [[ -n $result ]]; then read -r direction rate_value <<<"$result"; fi
        fi
        if [[ -n $rate_value ]]; then
            if [[ $direction == RX ]]; then rate="↓$(format_rate "$rate_value")"; else rate="↑$(format_rate "$rate_value")"; fi
            current_rate[$key]=$rate_value
            current_direction[$key]=$direction
        fi
        current_rx[$key]=$rx; current_tx[$key]=$tx
        row="$(cell "$state" 7)$(cell "$path" 12)$(cell "$address" 22)"
        if $detail; then row+="$(cell "$name" 20)"; else row+="$(cell "$name" 22)"; fi
        row+="$(cell "$os" 7)$(cell "$ip" 15)$(cell "$rate" 13)$(cell "$(format_bytes "$rx")" 11)$(cell "$(format_bytes "$tx")" 11)"
        if $detail; then row+="$(cell "$last" 16)"; fi
        lines+=("$row$diag")
    done < <(jq -r '
        def name: (.DNSName // "" | rtrimstr(".") | split(".")[0] | if . == null or . == "" then "(unknown)" else . end);
        def ip: (.TailscaleIPs // [] | map(select(contains(":") | not)) | first // "-");
        def path: if (.Online | not) then "OFFLINE" elif (.CurAddr // "") != "" then "DIRECT" elif (.PeerRelay // "") != "" then "PEER-RELAY" elif .Active and (.Relay // "") != "" then "DERP(\(.Relay))" else "IDLE" end;
        def addr: if (.CurAddr // "") != "" then .CurAddr elif (.PeerRelay // "") != "" then .PeerRelay elif .Active and (.Relay // "") != "" then "DERP:\(.Relay)" else "-" end;
        def stamp: if . == null or . == "" or startswith("0001-") then "-" else (try (fromdateiso8601 | strflocaltime("%m-%d %H:%M:%S")) catch .) end;
        (.Peer // {} | [.[] | select(. != null)] | sort_by(if .Online and .Active then 0 elif .Online then 1 else 2 end, name)[]) |
        (if (.NodeID // "") != "" then "node:\(.NodeID)" elif (.PublicKey // "") != "" then "key:\(.PublicKey)" else "name:\(name)" end) as $key |
        [$key,
         (if .Online | not then "OFFLINE" elif .Active then "ACTIVE" else "ONLINE" end), path, addr, name, (.OS // ""), ip,
         (.RxBytes // 0), (.TxBytes // 0),
         (if .Online and .Active then .LastHandshake elif .Online | not then .LastSeen else null end | stamp),
         ([(if .Online and .Active and (.InNetworkMap | not) then "!MAP" else empty end),
           (if .Online and .Active and (.InMagicSock | not) then "!MAGIC" else empty end),
           (if .Online and .Active and (.InEngine | not) then "!ENGINE" else empty end),
           (if .Expired then "EXPIRED" else empty end)] | join(" "))] | map(tostring | gsub("[\\t\\r\\n\\u001f]"; " ")) | join("\u001f")' <<<"$status")
    lines+=("$(printf '%*s' 120 '' | tr ' ' '-')" "Local Netcheck | $g6")
    previous_rx=(); previous_tx=(); previous_rate=(); previous_direction=()
    for key in "${!current_rx[@]}"; do
        previous_rx[$key]=${current_rx[$key]}; previous_tx[$key]=${current_tx[$key]}
        if [[ -v current_rate[$key] ]]; then previous_rate[$key]=${current_rate[$key]}; previous_direction[$key]=${current_direction[$key]}; fi
    done
    previous_time=$now
    draw
    sleep "$interval"
done
