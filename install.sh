#!/usr/bin/env bash
# Phoenix standalone manager. No external tunnel-manager code or runtime dependencies.
# PHOENIX_STANDALONE_MENU_V1
set -uo pipefail
PHX_REV=standalone-14
PHX_JOURNAL_ROOT=/etc/systemd
PHX_VERSION=v0.1.0-dev.69
PHX_BASE=/opt/phoenix-tunnel
PHX_SAVE=/root/install.sh
PHX_UNITS=/etc/systemd/system
PHX_LOCK=/run/lock/phoenix-standalone.lock
PHX_RAW=https://raw.githubusercontent.com/realerfiw/PhoenixTunnel/main/install.sh
PHX_RELEASE=https://github.com/realerfiw/PhoenixTunnel/releases/download
PHX_SOURCE=${BASH_SOURCE[0]}

paint() {
    if [[ -t 1 && -n ${TERM:-} && ${TERM:-} != dumb && ! -v NO_COLOR ]]; then
        printf '\033[%sm%s\033[0m' "$1" "$2"
    else
        printf '%s' "$2"
    fi
}
notice() { paint "$1" "  $2"; printf '\n'; }
option() {
    local color=35
    [[ $1 != 0 ]] || color=31
    paint "$color" "  $1)"; printf ' %s\n' "$2"
}
separator() { printf '\n'; }
fail() { printf 'Phoenix: %s\n' "$*" >&2; return 1; }
need() { local c; for c; do command -v "$c" >/dev/null || { fail "Required command: $c"; return 1; }; done; }
ca_ready() { [[ -s /etc/ssl/certs/ca-certificates.crt ]]; }
quiet_package_step() (
    local log result=0
    log=$(mktemp /tmp/phoenix-packages.XXXXXXXX) || return 1
    trap 'rm -f -- "$log"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    "$@" > "$log" 2>&1 || result=$?
    if ((result != 0)); then
        notice 33 'Package error:' >&2
        tail -n 12 -- "$log" >&2
    fi
    return "$result"
)
missing_dependency_packages() {
    local entry cmd package
    local -A missing=()
    for entry in curl:curl jq:jq openssl:openssl flock:util-linux \
        systemctl:systemd journalctl:systemd grep:grep \
        update-ca-certificates:ca-certificates \
        base32:coreutils tr:coreutils sha256sum:coreutils timeout:coreutils \
        realpath:coreutils stat:coreutils install:coreutils mktemp:coreutils \
        chmod:coreutils cp:coreutils mv:coreutils rm:coreutils rmdir:coreutils \
        cat:coreutils dirname:coreutils uname:coreutils tail:coreutils; do
        cmd=${entry%%:*}; package=${entry#*:}
        command -v "$cmd" >/dev/null 2>&1 || missing[$package]=1
    done
    ca_ready || missing[ca-certificates]=1
    for package in curl jq openssl util-linux systemd grep ca-certificates coreutils; do
        [[ ! -v missing[$package] ]] || printf '%s\n' "$package"
    done
}
install_dependencies() {
    local -a packages=()
    mapfile -t packages < <(missing_dependency_packages)
    ((${#packages[@]})) || return 0
    command -v apt-get >/dev/null 2>&1 || {
        fail "Install required packages first: ${packages[*]} (automatic setup requires Ubuntu/Debian APT)."
        return 1
    }
    notice 36 'Installing dependencies...'
    # Never upgrade the OS, remove packages, bypass signatures or force APT locks.
    # List-only needrestart mode avoids restarting unrelated services.
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        quiet_package_step apt-get -o APT::Update::Error-Mode=any update || {
        fail 'Package index update failed. Core unchanged; retry Install / update core.'; return 1
    }
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        quiet_package_step apt-get -o DPkg::Lock::Timeout=60 install -y --no-install-recommends --no-remove "${packages[@]}" || {
        fail 'Dependency installation failed. Core unchanged; retry Install / update core.'; return 1
    }
    hash -r
    mapfile -t packages < <(missing_dependency_packages)
    ((${#packages[@]} == 0)) || {
        fail "Dependencies still unavailable: ${packages[*]}. Core unchanged."; return 1
    }
}
ask() {
    local prompt=$1 default=${3:-}
    printf '%s' "$prompt"
    IFS= read -r "$2" || return 1
    [[ ${!2} != :cancel ]] || return 1
    [[ -n ${!2} ]] || printf -v "$2" '%s' "$default"
}
confirm() {
    local answer
    while :; do
        ask "$1 (Y/n): " answer y || return 1
        case ${answer,,} in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) notice 33 'Please enter y or n (:cancel to return).' ;;
        esac
    done
}
pause() { local ignored; ask 'Press Enter to return...' ignored || :; }
clear_screen() {
    # Do not put terminal control bytes into redirected logs or test output.
    if [[ -t 1 && -n ${TERM:-} && ${TERM:-} != dumb ]]; then
        # Clear old screen AND scrollback so earlier menu statuses cannot linger.
        printf '\033[0m\033[2J\033[H\033[3J'
    fi
}
heading() {
    clear_screen
    local title=$1 line=''
    printf -v line '%*s' "$(( ${#title} + 4 ))" ''
    if [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *[Uu][Tt][Ff]* ]]; then
        paint 36 '╭─ '; paint '1;37' "$title"; paint 36 ' ─╮'; printf '\n'
        paint 36 "╰${line// /─}╯"; printf '\n'
    else
        paint 36 "+${line// /-}+"; printf '\n'
        paint '1;37' "|  $title  |"; printf '\n'
        paint 36 "+${line// /-}+"; printf '\n'
    fi
    printf '\n'
}
valid_host() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,252}$ || $1 =~ ^\[[0-9a-fA-F:]+\]$ ]]; }
public_ipv4() {
    local value=$1 part
    local -a octets=()
    [[ $value =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$value"
    for part in "${octets[@]}"; do
        [[ $part == 0 || $part != 0* ]] && ((10#$part <= 255)) || return 1
    done
    ((octets[0] > 0 && octets[0] < 224 && octets[0] != 10 && octets[0] != 127)) || return 1
    [[ $value != 169.254.* && $value != 192.168.* ]] || return 1
    ! (( (octets[0]==172 && octets[1]>=16 && octets[1]<=31) ||
         (octets[0]==100 && octets[1]>=64 && octets[1]<=127) ))
}
detect_public_ip() {
    local endpoint detected
    # Only called when creating Iran, never while opening or refreshing menus.
    # External IP services receive no configuration, credentials or connection code.
    for endpoint in https://api.ipify.org https://checkip.amazonaws.com; do
        detected=$(curl -4 --noproxy '*' --proto '=https' -fsS \
            --connect-timeout 1 --max-time 2 --max-filesize 64 "$endpoint" 2>/dev/null) || continue
        detected=${detected%$'\r'}
        if public_ipv4 "$detected"; then printf '%s' "$detected"; return 0; fi
    done
    return 1
}
ask_iran_address() {
    local detected=''
    detected=$(detect_public_ip) || detected=''
    if [[ -n $detected ]]; then
        ask "Public IP [$detected]: " host "$detected" || return 1
    else
        ask 'Public IP: ' host || return 1
    fi
    valid_host "$host" || { fail 'Invalid IP / hostname.'; return 1; }
}
valid_port() { [[ $1 =~ ^[0-9]{1,5}$ ]] && (( 10#$1 > 0 && 10#$1 <= 65535 )); }
unit_name() { printf 'phoenix-standalone-%s.service' "$1"; }
safe_dir() {
    local path=$1
    [[ $path == /* && $path != / && $path != *..* && $path != *[[:space:]%]* ]] || return 1
    [[ $(realpath -m -- "$path") == "$path" ]] || { fail "Symlink or noncanonical path: $path"; return 1; }
    if [[ -e $path ]]; then
        [[ -d $path && $(stat -c %u "$path") == 0 ]] || return 1
        (( (8#$(stat -c %a "$path") & 0022) == 0 )) || { fail "Directory is writable by others: $path"; return 1; }
    else
        install -d -m 0755 -- "$path" || return 1
    fi
}
layout() { safe_dir "$PHX_BASE" && safe_dir "$PHX_BASE/core" && safe_dir "$PHX_BASE/configs"; }
core() { printf '%s/core/phoenix' "$PHX_BASE"; }
core_ready() { [[ -f $(core) && ! -L $(core) && -x $(core) ]]; }
core_status() {
    if core_ready; then notice 32 'Core: Installed'; else notice 33 'Core: Not installed'; fi
}
require_core() { core_ready || { fail 'Choose Install core first.'; return 1; }; }
lock_action() {
    # Called as a direct command, not in an if/|| context: errexit applies inside.
    (
        set -e
        # util-linux may be missing on a minimal host; bootstrap only on Install.
        if [[ ${1:-} == install_core ]] && ! command -v flock >/dev/null 2>&1; then
            install_dependencies
        fi
        need flock
        [[ ! -L $PHX_LOCK ]]
        exec 9>"$PHX_LOCK"
        flock -n 9 || { fail 'Another Phoenix operation is running.'; exit 1; }
        "$@"
    )
}
fetch() { curl --proto '=https' --proto-redir '=https' -fLsS --connect-timeout 15 --max-time 180 --retry 2 "$1" -o "$2"; }
save_menu() (
    set -e
    need realpath stat install mktemp curl
    safe_dir "$(dirname "$PHX_SAVE")"
    [[ ! -L $PHX_SAVE ]] || { fail 'Refusing a symlink at the saved script path.'; exit 1; }
    if [[ -e $PHX_SAVE ]]; then
        [[ -f $PHX_SAVE ]] && grep -q '^# PHOENIX_STANDALONE_MENU_V1$' "$PHX_SAVE" ||
            { fail "$PHX_SAVE belongs to another script; it was not overwritten. Menu still available."; exit 1; }
    fi
    [[ $PHX_SOURCE != "$PHX_SAVE" ]] || exit 0
    local staged
    staged=$(mktemp "$(dirname "$PHX_SAVE")/.phoenix-menu.XXXXXXXX")
    trap 'rm -f -- "$staged"' EXIT
    if [[ -f $PHX_SOURCE && ! -L $PHX_SOURCE && $PHX_SOURCE != /dev/* && $PHX_SOURCE != /proc/* ]]; then
        cp -- "$PHX_SOURCE" "$staged"
    else
        fetch "$PHX_RAW?revision=$PHX_REV" "$staged"
    fi
    grep -qx "# PHOENIX_STANDALONE_MENU_V1" "$staged"
    grep -qx "PHX_REV=$PHX_REV" "$staged"
    bash -n "$staged"
    chmod 0755 "$staged"
    mv -fT -- "$staged" "$PHX_SAVE"
)
install_core() {
    heading 'Install / update Phoenix core'
    local arch asset digest tmp reported destination
    case $(uname -m) in
        x86_64|amd64) arch=amd64; digest=e1504be2242ca00992541dd31367b5335238d27db938d232b0fc9cc33cce4764 ;;
        aarch64|arm64) arch=arm64; digest=45a9265a1ab740a7d0f4f9278afee875bd6a7ca30606b23ec7be5141e3e3c871 ;;
        *) fail 'Supported architectures: amd64, arm64'; return 1 ;;
    esac
    install_dependencies || return 1
    need curl sha256sum install mktemp timeout
    layout
    # Selecting Install / update core is the user's confirmation.
    for destination in "$(core)" "$PHX_BASE/core/LICENSE" "$PHX_BASE/core/THIRD-PARTY-LICENSES.json"; do
        [[ ! -L $destination && ( ! -e $destination || -f $destination ) ]] ||
            { fail "Unsafe core destination: $destination"; return 1; }
    done
    tmp=$(mktemp -d "$PHX_BASE/core/.download.XXXXXXXX")
    PHX_TEMP=$tmp; trap 'rm -rf -- "$PHX_TEMP"' EXIT
    asset=phoenix-linux-$arch
    notice 36 'Downloading core...'
    fetch "$PHX_RELEASE/$PHX_VERSION/$asset" "$tmp/phoenix"
    printf '%s  %s\n' "$digest" "$tmp/phoenix" | sha256sum --check --strict --quiet -
    fetch "$PHX_RELEASE/$PHX_VERSION/LICENSE" "$tmp/LICENSE"
    fetch "$PHX_RELEASE/$PHX_VERSION/THIRD-PARTY-LICENSES-linux-$arch.json" "$tmp/THIRD-PARTY-LICENSES.json"
    notice 36 'Verifying files...'
    printf '%s  %s\n' 4ac2246b8a312640bc5da2a3d57c81dec1bfe813d2b2e5884883aaf95e753de7 "$tmp/LICENSE" d8fe863575b7eab50193c578392aadb8c3c6c6c6a312f2548b084e27588cb5f1 "$tmp/THIRD-PARTY-LICENSES.json" | sha256sum --check --strict --quiet -
    chmod 0755 "$tmp/phoenix"
    reported=$(timeout 10s "$tmp/phoenix" version)
    [[ $reported == "phoenix ${PHX_VERSION#v} "* ]] || { fail 'Unexpected core version'; return 1; }
    # Rename, never truncate an executable that an existing service may be using.
    mv -fT "$tmp/phoenix" "$(core)"
    install -m 0644 "$tmp/LICENSE" "$PHX_BASE/core/LICENSE"
    install -m 0644 "$tmp/THIRD-PARTY-LICENSES.json" "$PHX_BASE/core/THIRD-PARTY-LICENSES.json"
    notice 32 "Phoenix ${PHX_VERSION#v} installed."
    local unit
    for unit in "$PHX_UNITS"/phoenix-standalone-*.service; do
        if [[ -f $unit ]]; then
            notice 33 'Restart existing tunnels to use the updated core.'
            break
        fi
    done
}
automatic_name() {
    local role=$1 carrier=$2 port=$3 suffix candidate state
    [[ $role == iran || $role == kharej ]] || return 1
    [[ $carrier == auto || $carrier == h2 || $carrier == h3 ]] || return 1
    valid_port "$port" || return 1
    port=$((10#$port))
    for ((suffix=1; suffix<=9999; suffix++)); do
        candidate="$role-$carrier-$port"
        ((suffix == 1)) || candidate+="-$suffix"
        if name_available "$candidate"; then name=$candidate; return 0; else state=$?; fi
        ((state == 1)) || return "$state"
    done
    fail 'No free tunnel name available.'
}
name_available() {
    local name=$1 load_state
    local f
    for f in "$PHX_BASE/configs/$name".*; do
        [[ ! -e $f && ! -L $f ]] || return 1
    done
    [[ ! -e "$PHX_UNITS/$(unit_name "$name")" && ! -L "$PHX_UNITS/$(unit_name "$name")" ]] ||
        return 1
    load_state=$(systemctl show "$(unit_name "$name")" -p LoadState --value) || {
        fail 'Unable to check existing services.'; return 2;
    }
    case $load_state in
        not-found) return 0 ;;
        loaded|error|masked|merged|stub|bad-setting) return 1 ;;
        *) fail 'Unable to check existing services.'; return 2 ;;
    esac
}
connection_available() {
    local role=$1 address=$2 agent=${3:-} config result
    for config in "$PHX_BASE/configs/$role-"*.json; do
        [[ -e $config || -L $config ]] || continue
        [[ -f $config && ! -L $config ]] || { fail 'Unsafe existing configuration.'; return 1; }
        if jq -se --arg role "$role" --arg address "$address" --arg agent "$agent" '
            if length!=1 or (.[0]|type)!="object" then error("invalid configuration") else .[0] end |
            if $role=="iran" then .mode=="server" and (.server.carrier_listen|split(":")|last)==$address
            else .mode=="client" and .client.server_address==$address and .auth.agent_id==$agent end
        ' "$config" >/dev/null; then
            fail 'This tunnel connection is already configured.'; return 1
        else result=$?; fi
        ((result == 1)) || { fail 'Unable to check existing configuration.'; return 1; }
    done
    return 0
}
write_config() {
    local mode=$1 payload=$2 prefix=$3 output=$4
    jq --arg mode "$mode" --arg prefix "$prefix" '
        {version:1, mode:$mode, carrier:.carrier,
         limits:{carrier_max_age:"0s"},
         mappings:.mappings,
         auth:(if $mode=="server" then
           {agent_credentials:[{agent_id:.agent,token_env:"PHOENIX_TOKEN"}]}
           else {agent_id:.agent,token_env:"PHOENIX_TOKEN"} end)}
         + (if $mode=="server" then
             {server:{carrier_listen:("0.0.0.0:"+(.port|tostring)),
                certificate_file:($prefix+".crt"),private_key_file:($prefix+".key")}}
            else {client:{server_address:(.host+":"+(.port|tostring)),
                server_name:"phoenix.internal",ca_file:($prefix+".crt")}} end)
    ' "$payload" > "$output"
}
log_settings() {
    printf '%s\n' 'LogNamespace=phoenix-standalone' 'StandardOutput=journal' 'StandardError=journal' 'LogRateLimitIntervalSec=0' 'LogRateLimitBurst=0'
}
log_policy() {
    printf '%s\n' '# PHOENIX_STANDALONE_JOURNAL_V1' '[Journal]' \
        'Storage=persistent' 'Compress=yes' 'SystemMaxUse=100M' 'RuntimeMaxUse=20M' \
        'SystemMaxFileSize=8M' 'RuntimeMaxFileSize=4M' 'MaxRetentionSec=3day' \
        'MaxFileSec=1day' 'RateLimitIntervalSec=0' 'RateLimitBurst=0' \
        'ForwardToSyslog=no' 'ForwardToKMsg=no' 'ForwardToConsole=no' 'ForwardToWall=no'
}
log_support() {
    local version
    version=$(systemctl --version) || return 1
    version=${version#systemd }; version=${version%% *}; version=${version%%$'\n'*}
    [[ $version =~ ^[0-9]+$ ]] && ((version >= 245)) || { fail 'Log retention requires systemd 245 or newer.'; return 1; }
    systemctl cat systemd-journald@.service >/dev/null 2>&1 || { fail 'Journal namespaces are unavailable.'; return 1; }
}
prepare_log_policy() (
    set -e
    log_support || exit 1
    local directory="$PHX_JOURNAL_ROOT/journald@phoenix-standalone.conf.d" file path staged
    file="$directory/60-phoenix-retention.conf"
    # Refuse unknown namespace overrides instead of claiming a cap they can defeat.
    for path in "$PHX_JOURNAL_ROOT/journald@phoenix-standalone.conf" \
        /run/systemd/journald@phoenix-standalone.conf /usr/local/lib/systemd/journald@phoenix-standalone.conf /usr/lib/systemd/journald@phoenix-standalone.conf \
        "$directory"/*.conf /run/systemd/journald@phoenix-standalone.conf.d/*.conf \
        /usr/local/lib/systemd/journald@phoenix-standalone.conf.d/*.conf /usr/lib/systemd/journald@phoenix-standalone.conf.d/*.conf; do
        [[ ! -e $path && ! -L $path ]] && continue
        [[ $path == "$file" && -f $path && ! -L $path ]] || { fail 'Custom Phoenix journal policy needs review.'; exit 1; }
        [[ $(cat "$path") == "$(log_policy)" ]] || { fail 'Custom Phoenix journal policy needs review.'; exit 1; }
    done
    safe_dir "$PHX_JOURNAL_ROOT" || exit 1
    safe_dir "$directory" || exit 1
    if [[ ! -f $file ]]; then
        staged=$(mktemp "$directory/.policy.XXXXXXXX") || exit 1
        trap 'rm -f -- "$staged"' EXIT
        log_policy > "$staged" || exit 1
        chmod 0644 "$staged" || exit 1
        mv -fT -- "$staged" "$file" || exit 1
    fi
)
prepare_tunnel_logs() (
    set -e
    local name=$1 unit file staged
    owned "$name" || { fail 'Cannot update logging for a modified service.'; exit 1; }
    prepare_log_policy || exit 1
    unit=$(unit_name "$name"); file="$PHX_UNITS/$unit"
    if grep -qx 'LogNamespace=phoenix-standalone' "$file"; then exit 0; fi
    if grep -Eq '^[[:space:]]*(LogNamespace|StandardOutput|StandardError)[[:space:]]*=' "$file"; then
        fail 'Custom service logging needs review.'; exit 1
    fi
    staged=$(mktemp "$PHX_UNITS/.phoenix-log.XXXXXXXX") || exit 1
    trap 'rm -f -- "$staged"' EXIT
    cat "$file" > "$staged" || exit 1
    printf '\n[Service]\n' >> "$staged" || exit 1
    log_settings >> "$staged" || exit 1
    chmod 0644 "$staged" || exit 1
    mv -fT -- "$staged" "$file" || exit 1
    systemctl daemon-reload || exit 1
)
format_logs() {
    local color=false
    [[ ! -t 1 || ${TERM:-dumb} == dumb || -v NO_COLOR ]] || color=true
    jq --unbuffered -nRr --argjson color "$color" '
      def text: if type=="string" then . else tojson end;
      def safe: text | gsub("[\u0000-\u0008\u000b-\u001f\u007f]"; "") ;
      def redact: walk(if type=="object" then with_entries(
        if (.key|test("^(token|password|secret|authorization|private_key|connection_code|credential|credentials)$";"i"))
        then .value="[hidden]" else . end) else . end);
      def fields($prefix):
        if type=="object" and length>0 then to_entries[] |
          .key as $key | .value | fields(if $prefix=="" then $key else $prefix+"."+$key end)
        elif type=="array" and length>0 then to_entries[] |
          .key as $key | .value | fields($prefix+"["+($key|tostring)+"]")
        else ({mode:"Mode",carrier:"Transport",carrier_listen:"Listen",operations_listen:"Operations",
          mappings:"Mappings",tcp_mappings:"TCP mappings",udp_mappings:"UDP mappings",agent_id:"Agent",
          session_epoch:"Epoch",error:"Error",reason:"Reason",event:"Event",side:"Side",h2:"H2",h3:"H3"}[$prefix] // $prefix)
          +": "+(safe|gsub("\n"; "\n               ")) end;
      def pack:
        reduce .[] as $field ([];
          if length>0 and ((.[-1]|length)+($field|length)+3)<=105 then .[-1]+=" · "+$field
          else .+[$field] end);
      def display:
      . as $raw | (try fromjson catch {MESSAGE:$raw}) as $entry |
      (if ($entry|type)=="object" then $entry else {MESSAGE:$entry} end) as $j |
      (if $j|has("MESSAGE") then $j.MESSAGE else "" end) as $message |
      (if ($message|type)=="string" then (try ($message|fromjson) catch $message) else $message end | redact) as $body |
      (if ($body|type)=="object" then $body else {} end) as $o |
      (try (($j.__REALTIME_TIMESTAMP|tonumber)/1000000|floor|strftime("%Y-%m-%d %H:%M:%S")) catch "unknown date unknown time") as $time |
      (($o.level // (["ERROR","ERROR","ERROR","ERROR","WARN","NOTICE","INFO","DEBUG"][(try ($j.PRIORITY|tonumber) catch 6)] // "INFO"))|text|ascii_upcase|safe) as $level |
      (if $color then (if $level=="ERROR" then "\u001b[31m" elif $level=="WARN" then "\u001b[33m" else "\u001b[36m" end) else "" end) as $paint |
      (if ($body|type)=="object" then
         (if $body|has("msg") then $body.msg|safe else "Event" end)
       else $body|safe end | gsub("\n"; "\n               ")) as $message |
      ([if ($body|type)=="object" then
           $body|to_entries[]|select(.key!="msg" and .key!="level")|
           select(.key!="time" or (.value|type)!="string" or
             (.value|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$")|not)) |
           .key as $key | .value | fields($key)
         else empty end,
         if $j|has("MESSAGE") then empty else $j|redact|fields("journal") end,
         ($j.SYSLOG_IDENTIFIER // $j._COMM // "phoenix") as $source |
           if $source=="phoenix" or $source=="systemd" then empty else "Source: "+($source|safe) end] | pack) as $details |
      ("\($time[11:])  \($paint)\($level)\(if $color then "\u001b[0m" else "" end)  \($message)") as $header |
      {day:$time[0:10], lines:
        (if ($details|length)>0 and (($header|length)+($details[0]|length))<125 and ($message|contains("\n")|not)
         then [$header+" · "+$details[0]]+($details[1:]|map("               "+.))
         else [$header]+($details|map("               "+.)) end)};
      foreach inputs as $input ({day:null,lines:[]};
        ($input|display) as $row |
        {day:$row.day,lines:((if .day!=$row.day then [$row.day+" · UTC"] else [] end)+$row.lines)};
        .lines[])
    '
}
show_logs() {
    local unit=$1 live=${2:-false}
    local -a options=(--no-pager --all --no-tail --output=json --unit="$unit")
    need journalctl jq || return 1
    if journalctl --help | grep -q -- --namespace; then options+=(--namespace=+phoenix-standalone); fi
    [[ $live != true ]] || options+=(--follow)
    notice 37 'All retained entries · UTC'
    [[ $live != true ]] || notice 37 'Press Ctrl+C to return'
    local result=0
    journalctl "${options[@]}" | format_logs || result=$?
    ((result == 0)) || { fail 'Unable to read or format journal logs.'; return "$result"; }
}
write_unit() {
    local name=$1 mode=$2 output=$3 prefix="$PHX_BASE/configs/$1"
    printf '%s\n' '# PHOENIX_STANDALONE_UNIT_V1' '[Unit]' "Description=Phoenix Tunnel $name"         'Wants=network-online.target' 'After=network-online.target'         'StartLimitIntervalSec=60' 'StartLimitBurst=10' '' '[Service]'         'Type=simple' 'User=root' 'UMask=0077'         "EnvironmentFile=$prefix.env" "ExecStart=$(core) $mode --config $prefix.json"         'Restart=on-failure' 'RestartSec=3' 'TimeoutStopSec=10'         'LimitNOFILE=65536' 'NoNewPrivileges=true' 'PrivateTmp=true'         'ProtectSystem=strict' 'ProtectHome=true' 'PrivateDevices=true'         'ProtectKernelTunables=true' 'ProtectKernelModules=true' 'ProtectControlGroups=true'         'RestrictAddressFamilies=AF_INET AF_INET6' 'RestrictSUIDSGID=true'         'CapabilityBoundingSet=CAP_NET_BIND_SERVICE'         'LogRateLimitIntervalSec=30s' 'LogRateLimitBurst=200'         '' '[Install]' 'WantedBy=multi-user.target' > "$output"
    printf '\n[Service]\n' >> "$output"
    log_settings >> "$output"
}
commit_tunnel() {
    local mode=$1 name=$2 tmp=$3 suffix unit
    unit=$(unit_name "$name")
    # All paths are generated locally. Incoming codes cannot set file paths or units.
    write_config "$mode" "$tmp/payload" "$tmp/tls" "$tmp/validate.json"
    "$(core)" validate --mode "$mode" --config "$tmp/validate.json" --environment "$tmp/config.env"
    prepare_log_policy || return 1
    write_config "$mode" "$tmp/payload" "$PHX_BASE/configs/$name" "$tmp/config.json"
    write_unit "$name" "$mode" "$tmp/service"
    for suffix in json env; do install -m 0600 "$tmp/config.$suffix" "$PHX_BASE/configs/$name.$suffix"; done
    install -m 0600 "$tmp/tls.crt" "$PHX_BASE/configs/$name.crt"
    if [[ $mode == server ]]; then
        install -m 0600 "$tmp/tls.key" "$PHX_BASE/configs/$name.key"
        install -m 0600 "$tmp/code" "$PHX_BASE/configs/$name.code"
    fi
    install -m 0644 "$tmp/service" "$PHX_UNITS/$unit"
    systemctl daemon-reload
    systemctl enable --now "$unit"
    if ! systemctl is-active --quiet "$unit"; then
        fail "Created $unit, but startup failed. Check View logs."; return 1
    fi
    printf 'Created: %s\n' "$unit"
}
create_iran() {
    heading 'Create Iran tunnel'
    need jq openssl base32 tr systemctl timeout install chmod mktemp
    require_core
    layout
    safe_dir "$PHX_UNITS"
    local name host port carrier protocol listen target_host target_port more tmp agent token mappings='[]' count=0
    ask_iran_address || return
    ask 'Tunnel port [7845]: ' port 7845 || return
    valid_port "$port" || { fail 'Invalid port.'; return 1; }
    port=$((10#$port))
    ask 'Transport (auto/h2/h3) [auto]: ' carrier auto || return
    [[ $carrier == auto || $carrier == h2 || $carrier == h3 ]] || return 1
    connection_available iran "$port" || return 1
    automatic_name iran "$carrier" "$port" || return 1
    while :; do
        ask 'Protocol (tcp/udp) [tcp]: ' protocol tcp || return
        [[ $protocol == tcp || $protocol == udp ]] || return 1
        [[ $carrier != h3 || $protocol == udp ]] || { fail 'Use auto/h2 for TCP in this setup.'; return 1; }
        ask 'Iran public port: ' listen || return
        ask 'Kharej target IP [127.0.0.1]: ' target_host 127.0.0.1 || return
        ask 'Kharej target port: ' target_port || return
        valid_port "$listen" && valid_port "$target_port" && valid_host "$target_host" || { fail 'Invalid mapping.'; return 1; }
        listen=$((10#$listen)); target_port=$((10#$target_port))
        [[ $listen != "$port" ]] || { fail 'Public port must differ from tunnel port.'; return 1; }
        count=$((count+1)); ((count<=64)) || { fail 'At most 64 mappings.'; return 1; }
        mappings=$(printf '%s' "$mappings" | jq -c --arg name "port$count" --arg p "$protocol" --arg l "0.0.0.0:$listen" --arg t "$target_host:$target_port" '.+[{name:$name,protocol:$p,listen:$l,target:$t}]')
        ask 'Add another port? (y/N): ' more n || return
        [[ $more == y || $more == Y ]] || break
    done
    printf '\nIran: %s:%s | %s | %s mapping(s)\n' "$host" "$port" "$carrier" "$count"
    printf 'Creates and starts this tunnel; enables startup after reboot. Firewall unchanged.\n'
    confirm 'Create tunnel?' || return 0
    tmp=$(mktemp -d "$PHX_BASE/configs/.setup.XXXXXXXX"); chmod 0700 "$tmp"
    PHX_TEMP=$tmp; trap 'rm -rf -- "$PHX_TEMP"' EXIT
    umask 077
    agent=$(openssl rand -hex 16); token=$(openssl rand -hex 32)
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650         -subj /CN=phoenix.internal -addext subjectAltName=DNS:phoenix.internal         -keyout "$tmp/tls.key" -out "$tmp/tls.crt" >/dev/null 2>&1
    # Secret values travel through stdin, never command-line arguments.
    printf '%s\n' "$token" "$agent" "$host" "$port" "$carrier" "$mappings" |
        jq -Rn --rawfile ca "$tmp/tls.crt"         '{v:1,token:input,agent:input,host:input,port:(input|tonumber),carrier:input,mappings:(input|fromjson),ca:$ca}' > "$tmp/payload"
    printf 'PHOENIX_TOKEN=%s\n' "$token" > "$tmp/config.env"
    { printf PHX1; jq -c . "$tmp/payload" | base32 -w0 | tr -d '='; printf '\n'; } > "$tmp/code"
    commit_tunnel server "$name" "$tmp"
    printf '\nKharej connection code (private):\n'; cat "$tmp/code"
}
decode_code() {
    local code=$1 output=$2 raw padding
    [[ ${#code} -le 32768 && $code =~ ^PHX1[A-Z2-7]+$ ]] || { fail 'Invalid Phoenix connection code.'; return 1; }
    raw=${code#PHX1}; padding=$(( (8-${#raw}%8)%8 ))
    printf -v raw '%s%*s' "$raw" "$padding" ''
    printf '%s' "${raw// /=}" | base32 -d > "$output" || return 1
    jq -e '
      type=="object" and .v==1 and
      (.token|type=="string" and test("^[0-9a-f]{64}$")) and
      (.agent|type=="string" and test("^[0-9a-f]{32}$")) and
      (.host|type=="string" and length<254 and test("^[A-Za-z0-9][A-Za-z0-9.-]*$|^\\[[0-9a-fA-F:]+\\]$")) and
      (.port|type=="number" and floor==. and .>=1 and .<=65535) and
      (.carrier=="auto" or .carrier=="h2" or .carrier=="h3") and
      (.ca|type=="string" and length<8192 and startswith("-----BEGIN CERTIFICATE-----")) and
      (.mappings|type=="array" and length>=1 and length<=64) and
      all(.mappings[]; (keys|sort)==["listen","name","protocol","target"] and
          (.name|type=="string" and test("^[a-zA-Z0-9-]{1,32}$")) and
          (.protocol=="tcp" or .protocol=="udp") and
          (.listen|type=="string" and length<300 and test("^[ -~]+$")) and
          (.target|type=="string" and length<300 and test("^[ -~]+$")))
    ' "$output" >/dev/null || { fail 'Invalid connection settings.'; return 1; }
}
create_kharej() {
    heading 'Create Kharej tunnel'
    need jq openssl base32 systemctl install chmod mktemp
    require_core; layout; safe_dir "$PHX_UNITS"
    local name code tmp carrier port address agent
    ask 'Connection code: ' code || return
    tmp=$(mktemp -d "$PHX_BASE/configs/.setup.XXXXXXXX"); chmod 0700 "$tmp"
    PHX_TEMP=$tmp; trap 'rm -rf -- "$PHX_TEMP"' EXIT
    umask 077
    decode_code "$code" "$tmp/payload" || return 1
    carrier=$(jq -r .carrier "$tmp/payload")
    port=$(jq -r .port "$tmp/payload")
    address=$(jq -r '.host+":"+(.port|tostring)' "$tmp/payload")
    agent=$(jq -r .agent "$tmp/payload")
    connection_available kharej "$address" "$agent" || return 1
    automatic_name kharej "$carrier" "$port" || return 1
    jq -r .ca "$tmp/payload" > "$tmp/tls.crt"
    openssl x509 -in "$tmp/tls.crt" -noout >/dev/null
    jq -r '"PHOENIX_TOKEN="+.token' "$tmp/payload" > "$tmp/config.env"
    printf '\n'; jq -r '"Iran: "+.host+":"+(.port|tostring), (.mappings[]|.protocol+" "+.listen+" -> "+.target)' "$tmp/payload"
    notice 36 'Creating tunnel...'
    commit_tunnel client "$name" "$tmp"
}
owned_files() {
    local name=$1 unit
    [[ $name =~ ^(iran|kharej)-[a-z][a-z0-9-]{0,31}$ ]] || return 1
    unit=$(unit_name "$name")
    [[ -f "$PHX_UNITS/$unit" && ! -L "$PHX_UNITS/$unit" && ! -L "$PHX_BASE/configs/$name.json" ]] || return 1
    grep -qx '# PHOENIX_STANDALONE_UNIT_V1' "$PHX_UNITS/$unit" || return 1
    grep -Fqx "EnvironmentFile=$PHX_BASE/configs/$name.env" "$PHX_UNITS/$unit" || return 1
    local mode=server; [[ $name == iran-* ]] || mode=client
    grep -Fqx "ExecStart=$(core) $mode --config $PHX_BASE/configs/$name.json" "$PHX_UNITS/$unit" || return 1
}
owned() {
    local name=$1 unit
    owned_files "$name" || return 1
    unit=$(unit_name "$name")
    # Drop-ins may redirect the executable; do not manage such a service.
    [[ -z $(systemctl show "$unit" -p DropInPaths --value) ]] || return 1
    [[ $(systemctl show "$unit" -p FragmentPath --value) == "$PHX_UNITS/$unit" ]] || return 1
}
collect_tunnels() {
    # Display-only snapshot: one systemd query for the whole screen. Actions
    # revalidate ownership separately; a status label is never authorization.
    local path name unit snapshot key value id='' active='' load='' fragment='' drops='' index
    local -a units=()
    local -A indexes=()
    tunnel_names=(); tunnel_states=()
    for path in "$PHX_UNITS"/phoenix-standalone-*.service; do
        [[ -f $path && ! -L $path ]] || continue
        name=${path##*/phoenix-standalone-}; name=${name%.service}
        [[ $name =~ ^(iran|kharej)-[a-z][a-z0-9-]{0,31}$ ]] || continue
        grep -qx '# PHOENIX_STANDALONE_UNIT_V1' "$path" || continue
        unit=$(unit_name "$name")
        indexes[$unit]=${#tunnel_names[@]}
        tunnel_names+=("$name"); units+=("$unit")
        if owned_files "$name" && [[ -f $PHX_BASE/configs/$name.json && ! -L $PHX_BASE/configs/$name.json && -f $PHX_BASE/configs/$name.env && ! -L $PHX_BASE/configs/$name.env ]]; then
            tunnel_states+=(UNKNOWN)
        else tunnel_states+=(INCOMPLETE); fi
    done
    ((${#units[@]})) || return 0
    snapshot=$(systemctl show --no-pager --property=Id,LoadState,ActiveState,FragmentPath,DropInPaths -- "${units[@]}" 2>/dev/null) || return 0
    while IFS='=' read -r key value; do
        case $key in
            Id) id=$value ;;
            ActiveState) active=$value ;;
            LoadState) load=$value ;;
            FragmentPath) fragment=$value ;;
            DropInPaths) drops=$value ;;
            '')
                if [[ $id =~ ^phoenix-standalone-(iran|kharej)-[a-z][a-z0-9-]{0,31}\.service$ && -v indexes[$id] ]]; then
                    index=${indexes[$id]}
                    if [[ ${tunnel_states[index]} != INCOMPLETE && $load == loaded && $fragment == "$PHX_UNITS/$id" && -z $drops ]]; then
                        case $active in
                            active) tunnel_states[index]=UP ;;
                            inactive|failed) tunnel_states[index]=DOWN ;;
                            *) tunnel_states[index]=UNKNOWN ;;
                        esac
                    fi
                fi
                id=''; active=''; load=''; fragment=''; drops='' ;;
        esac
    done <<< "$snapshot"$'\n'
}
render_tunnels() {
    local index color state
    if ((${#tunnel_names[@]} == 0)); then
        notice 33 'No tunnels yet.'
        notice 37 'Choose Create tunnel to get started.'
        return 0
    fi
    for ((index=0; index<${#tunnel_names[@]}; index++)); do
        state=${tunnel_states[index]}
        case $state in UP) color=32 ;; DOWN) color=31 ;; *) color=33 ;; esac
        paint 35 "  $((index+1))) "
        paint 33 "$(unit_name "${tunnel_names[index]}")"
        printf ' ['; paint "$color" "$state"; printf ']\n'
    done
}
select_tunnel() {
    heading "${1:-Select Phoenix tunnel}"
    need systemctl || return
    local choice
    local -a tunnel_names=() tunnel_states=()
    collect_tunnels
    if ((${#tunnel_names[@]} == 0)); then render_tunnels; return 1; fi
    notice 37 'Existing Phoenix tunnels:'
    render_tunnels
    option 0 'Back'
    printf '\n'
    while :; do
        ask 'Select tunnel (0 Back): ' choice || return 1
        [[ $choice != 0 ]] || return 2
        if [[ $choice =~ ^[0-9]{1,5}$ ]] && ((10#$choice>0 && 10#$choice<=${#tunnel_names[@]})); then
            selected=${tunnel_names[10#$choice-1]}
            return 0
        fi
        notice 33 'Invalid tunnel number. Select a displayed number, or 0 to return.'
    done
}
manage_action() {
    local action=$1 selected unit mode suffix title result
    case $action in
        restart) title='Restart Phoenix Tunnel' ;; stop) title='Stop Phoenix Tunnel' ;;
        remove) title='Remove Phoenix Tunnel' ;; logs) title='Phoenix Tunnel Logs' ;;
        live) title='Live Phoenix Tunnel Logs' ;; details) title='Phoenix Tunnel Details' ;;
        check) title='Phoenix Health Check' ;; status) title='Phoenix Tunnel Status' ;;
        code) title='Kharej Connection Code' ;; *) return 1 ;;
    esac
    select_tunnel "$title" || { result=$?; [[ $result != 2 ]] || return 2; return 0; }
    owned "$selected" || { fail 'Tunnel configuration changed or needs review. No action taken.'; return 1; }
    unit=$(unit_name "$selected")
    separator
    notice 37 "Tunnel: $unit"
    case $action in
        restart|stop)
            if [[ $action == restart ]]; then prepare_tunnel_logs "$selected" || return 1; fi
            systemctl "$action" "$unit"
            notice 32 "$selected: $action completed." ;;
        remove)
            confirm "Remove tunnel '$unit'?" || return 0
            owned "$selected" || return 1
            systemctl stop "$unit"
            systemctl disable "$unit"
            rm -- "$PHX_UNITS/$unit"
            # Exact, generated filenames only. No recursive config deletion.
            for suffix in json env crt key code; do
                rm -f -- "$PHX_BASE/configs/$selected.$suffix"
            done
            systemctl daemon-reload
            notice 32 'Tunnel removed.' ;;
        logs) show_logs "$unit" ;;
        live) show_logs "$unit" true ;;
        status) systemctl --no-pager --full status "$unit" ;;
        details)
            need jq
            printf 'Service: %s\nConfig: %s/configs/%s.json\n' "$unit" "$PHX_BASE" "$selected"
            jq '{mode,carrier,mappings,server:(.server//null),client:(.client//null)}' "$PHX_BASE/configs/$selected.json" ;;
        check)
            require_core
            "$(core)" validate --config "$PHX_BASE/configs/$selected.json" --environment "$PHX_BASE/configs/$selected.env"
            systemctl is-active "$unit" ;;
        code)
            [[ $selected == iran-* && -f "$PHX_BASE/configs/$selected.code" ]] || { fail 'Select an Iran tunnel to display its code.'; return 1; }
            printf 'Private connection code:\n'; cat "$PHX_BASE/configs/$selected.code" ;;
    esac
}
directory_empty() (
    shopt -s nullglob dotglob
    local -a entries=("$1"/*)
    ((${#entries[@]} == 0))
)
remove_core() {
    heading 'Remove Phoenix core'
    local file removable=0
    # Validate existing directories without creating anything during removal.
    for file in "$PHX_BASE" "$PHX_BASE/core" "$PHX_BASE/configs"; do
        if [[ -e $file || -L $file ]]; then safe_dir "$file" || return 1; fi
    done
    for file in "$(core)" "$PHX_BASE/core/LICENSE" "$PHX_BASE/core/THIRD-PARTY-LICENSES.json"; do
        [[ ! -L $file && ( ! -e $file || -f $file ) ]] || { fail "Unsafe core file: $file"; return 1; }
        [[ ! -f $file ]] || removable=1
    done
    for file in "$PHX_BASE/core" "$PHX_BASE/configs" "$PHX_BASE"; do
        if [[ -d $file ]] && directory_empty "$file"; then removable=1; fi
    done
    if ((removable == 0)); then
        notice 33 'Nothing to remove.'
        return 0
    fi
    for file in "$PHX_UNITS"/phoenix-standalone-*.service; do
        [[ ! -e $file ]] || { fail 'Remove standalone tunnels first.'; return 1; }
    done
    confirm 'Remove Phoenix core?' || return 0
    rm -f -- "$(core)" "$PHX_BASE/core/LICENSE" "$PHX_BASE/core/THIRD-PARTY-LICENSES.json"
    # Never recursively delete configs, the saved menu, or shared OS packages.
    for file in "$PHX_BASE/core" "$PHX_BASE/configs" "$PHX_BASE"; do
        [[ ! -d $file ]] || rmdir -- "$file" 2>/dev/null || :
    done
    notice 32 'Removed.'
}
manage_menu() {
    local choice role action_status
    local -a tunnel_names=() tunnel_states=()
    while :; do
        if ! require_core; then
            pause
            return 0
        fi
        heading 'Phoenix Tunnel Management'
        collect_tunnels
        render_tunnels
        separator
        option 1 'Create tunnel'
        option 2 'Restart tunnel'
        option 3 'Stop tunnel'
        option 4 'Remove tunnel'
        option 5 'View logs'
        option 6 'View live logs'
        option 7 'View tunnel details'
        option 8 'Health Check'
        option 9 'Status'
        option 10 'Kharej connection code'
        option 0 'Back'
        printf '\n'
        ask 'Select option: ' choice || return
        case $choice in
            0) return ;;
            1)
                heading 'Create Phoenix Tunnel'
                option 1 'Iran   (server)'
                option 2 'Kharej (client)'
                option 0 'Back'
                printf '\n'
                ask 'Select role (1 Iran / 2 Kharej / 0 Back): ' role || return
                case $role in
                    1) lock_action create_iran ;;
                    2) lock_action create_kharej ;;
                    0) continue ;;
                    *) notice 33 'Invalid option.'; pause; continue ;;
                esac ;;
            2) lock_action manage_action restart ;;
            3) lock_action manage_action stop ;;
            4) lock_action manage_action remove ;;
            5) (set -e; manage_action logs) ;;
            6) (trap 'exit 130' INT; set -e; manage_action live) ;;
            7) (set -e; manage_action details) ;;
            8) (set -e; manage_action check) ;;
            9) (set -e; manage_action status) ;;
            10) (set -e; manage_action code) ;;
            *) notice 33 'Invalid option.'; pause; continue ;;
        esac
        action_status=$?
        ((action_status == 2)) || pause
    done
}
menu() {
    local choice
    while :; do
        heading 'Phoenix Tunnel Menu'
        core_status
        separator
        option 1 'Install / update core'
        option 2 'Manage tunnels'
        option 3 'Remove core'
        option 0 'Exit'
        printf '\n'
        ask 'Select option: ' choice || return 0
        case $choice in
            0|4) return 0 ;;
            1) lock_action install_core; pause ;;
            2) manage_menu ;;
            3) lock_action remove_core; pause ;;
            *) notice 33 'Invalid option.'; pause ;;
        esac
    done
}
main() {
    [[ $# == 0 ]] || { fail 'Run without arguments to open the menu.'; return 1; }
    [[ $(uname -s) == Linux && $EUID == 0 ]] || { fail 'Run with Bash as root on Linux.'; return 1; }
    need realpath stat install mktemp || return
    if [[ -e $PHX_BASE || -L $PHX_BASE ]]; then safe_dir "$PHX_BASE" || return 1; fi
    # Saving the menu is the only startup write. No core/config/service mutation.
    save_menu
    menu
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
