#!/usr/bin/env bash
#
# SSH 호스트 등록과 SFTP 설정 (macOS / Linux / Windows Git Bash)
#
#   bash scripts/lib/ssh.sh                   # 메뉴에서 작업 선택
#   bash scripts/lib/ssh.sh add               # 호스트 등록: 연결 확인 → 키 등록 → ~/.ssh/config 에 추가
#   bash scripts/lib/ssh.sh list              # 등록된 호스트 목록
#   bash scripts/lib/ssh.sh check [호스트...] # 헬스체크: 서버 응답 → SSH 인증 → SFTP
#   bash scripts/lib/ssh.sh sftp [호스트]     # 프로젝트에 .vscode/sftp.json 생성 (natizyskunk.sftp 확장용)
#
# 옵션
#   add   : --name <별칭> --host <주소> --user <사용자> --port <포트> --key <개인 키 경로>
#   check : --all (등록된 호스트 전부)
#   sftp  : --dir <프로젝트 폴더> --remote <서버 경로>
#   공통  : -y/--yes (확인 질문에 모두 예) · -n/--dry-run (설정 파일을 쓰지 않음) · -h/--help
#
# 설정 파일은 실제 연결이 확인된 뒤에만 쓴다. 헬스체크가 실패하면 아무것도 저장하지 않는다.
# 비밀번호는 받거나 저장하지 않는다. 필요할 때 ssh 가 직접 묻는다.
# 접속 정보는 이 레포가 아니라 ~/.ssh/config 와 <프로젝트>/.vscode/sftp.json 에 남는다.
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않습니다.

set -uo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=ui.sh
source "$SCRIPTS_DIR/lib/ui.sh"

# DOTFILES_SSH_DIR 은 테스트용이다. 지정하면 그 디렉토리의 config / known_hosts 만 쓴다.
SSH_DIR="${DOTFILES_SSH_DIR:-$HOME/.ssh}"
SSH_CONFIG="$SSH_DIR/config"
KNOWN_HOSTS="$SSH_DIR/known_hosts"

ASSUME_YES=false
CONNECT_TIMEOUT=8
BACKUP_SUFFIX="bak.$(date +%Y%m%d%H%M%S)"
TMP=""

# 헬스체크 단계가 채우는 값
REMOTE_PWD=""           # SFTP 로 접속했을 때의 서버 쪽 현재 디렉토리
REACH_PENDING=""        # 이미 아는 서버라 1단계 판정을 2단계 접속으로 미룬 경우 "<주소> <포트>"
AUTH_FAIL=""            # 인증 실패 원인 (check_auth 참고)
AUTH_INTERACTIVE=false  # 키 암호를 물어야 해서 배치 모드로는 접속할 수 없는 경우

# ------------------------------------------------------------------- 공용 --

# 사람에게 물어볼 수 있는 상황인지. $(...) 안에서도 불리므로 stdout 이 아니라 stderr 로 판단한다.
has_tty() { [[ -t 2 ]] && (exec 3</dev/tty) 2>/dev/null; }

confirm() { $ASSUME_YES && return 0; has_tty || return 1; ui_confirm "$1"; }

# ssh / sftp / ssh-keyscan 에 공통으로 붙일 옵션을 BASE 배열에 채운다.
# bash 3.2 는 빈 배열 전개를 오류로 보므로 항상 한 개 이상 넣는다.
set_base_opts() {
  BASE=(-o "ConnectTimeout=$CONNECT_TIMEOUT")
  if [[ -n "${DOTFILES_SSH_DIR:-}" ]]; then
    if [[ -f "$SSH_CONFIG" ]]; then BASE+=(-F "$SSH_CONFIG"); else BASE+=(-F /dev/null); fi
    BASE+=(-o "UserKnownHostsFile=$KNOWN_HOSTS")
  fi
}

# 출력 파일에서 원인으로 보여 줄 마지막 줄을 꺼낸다.
last_line() {
  grep -v -i -e '^[[:space:]]*$' -e 'permanently added' "$1" 2>/dev/null | tail -n 1
}

# 별칭·주소·사용자는 ssh 명령의 인자로 들어가므로 옵션처럼 보이는 값(-로 시작)을 막는다.
valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
valid_host() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.:_-]*$ ]]; }
valid_user() { [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9._@-]*$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }

# 사용자 기본값으로 제안할 로컬 계정 이름. 서버 계정으로 쓸 수 없는 모양이면 비운다.
# (Windows 의 Entra 계정은 "AzureAD+홍길동(Hong)" 처럼 나와 valid_user 를 통과하지 못한다)
default_user() {
  local u
  u="$(id -un 2>/dev/null)" && valid_user "$u" && printf '%s\n' "$u"
  return 0
}

# ask <변수 설명> <옵션 이름> <현재 값> <기본값> <예시> <검사 함수>
# 값이 비어 있으면 물어보고, 검사를 통과할 때까지 다시 묻는다. 결과는 stdout.
ask() {
  local label="$1" flag="$2" value="$3" def="$4" hint="$5" check="$6"
  if [[ -n "$value" ]]; then
    "$check" "$value" || die "$label 값이 올바르지 않습니다: $value"
    printf '%s\n' "$value"; return 0
  fi
  has_tty || die "$label 값이 필요합니다. ($flag 로 지정)"
  while :; do
    value="$(ui_input "$label" "$def" "$hint")" || return 1
    if [[ -n "$value" ]] && "$check" "$value"; then
      printf '%s\n' "$value"; return 0
    fi
    warn "$label 값이 올바르지 않습니다. 다시 입력하세요." >/dev/tty
  done
}

# ~ 로 시작하는 경로를 홈 디렉토리로 편다.
expand_home() {
  case "$1" in
    "~")   printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#"~/"}" ;;
    *)     printf '%s\n' "$1" ;;
  esac
}

# 홈 아래 경로를 ~ 로 줄인다. (ssh config 에 적을 때 기기마다 같은 표기가 되도록)
tilde_path() {
  case "$1" in
    "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
    *)         printf '%s\n' "$1" ;;
  esac
}

# 개인 키에 암호가 걸려 있는지. (빈 암호로 공개 키를 꺼낼 수 없으면 걸려 있는 것)
key_encrypted() { ! ssh-keygen -y -P "" -f "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------ ssh config --

# config 에 적힌 호스트 별칭을 한 줄씩 출력한다. 와일드카드 패턴(*, ?, !)은 뺀다.
list_hosts() {
  [[ -f "$SSH_CONFIG" ]] || return 0
  awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/ && !seen[$i]++) print $i }' "$SSH_CONFIG"
}

host_exists() { list_hosts | grep -qxF "$1"; }

# ssh 가 실제로 쓰게 될 값을 꺼낸다. host_field <별칭> <키(소문자)>
host_field() {
  set_base_opts
  ssh "${BASE[@]}" -G "$1" 2>/dev/null | awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }'
}

# 별칭에 걸린 IdentityFile 중 실제로 있는 첫 번째 파일.
host_key_file() {
  local f
  set_base_opts
  while IFS= read -r f; do
    f="$(expand_home "$f")"
    [[ -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
  done < <(ssh "${BASE[@]}" -G "$1" 2>/dev/null | awk '$1 == "identityfile" { $1 = ""; sub(/^ /, ""); print }')
  return 1
}

# ---------------------------------------------------------------- 헬스체크 --
#
# 세 단계로 나눠 어디서 막히는지 드러낸다.
#   1. 서버 응답   주소·포트에서 SSH 서버가 응답하는지
#   2. SSH 인증    키로 로그인되는지
#   3. SFTP        SFTP 서브시스템이 열리는지
#
# 인증 없이 끊는 접속이 쌓이면 요즘 OpenSSH 서버(9.8+, PerSourcePenalties)는 그 IP 를 한동안 막는다.
# 그래서 1단계만을 위한 접속은 처음 보는 서버(호스트 키를 받아 와야 할 때)에만 하고,
# 이미 아는 서버는 2단계 접속의 결과로 1단계를 함께 판정한다.

# 서버까지 닿지 못했을 때 ssh 가 내는 메시지
NET_ERRORS='connection refused|timed out|could not resolve|no route to host|network is unreachable|connection reset|connection closed by|kex_exchange_identification'

known_host() {
  local lookup="$1"
  [[ "$2" != "22" ]] && lookup="[$1]:$2"
  [[ -f "$KNOWN_HOSTS" ]] && ssh-keygen -F "$lookup" -f "$KNOWN_HOSTS" >/dev/null 2>&1
}

reach_ok()   { ok "서버 응답  ${C_DIM}$1:$2 에서 SSH 서버가 응답합니다${C_RESET}"; }
reach_fail() {
  fail "서버 응답  ${3:-$1:$2 에 연결할 수 없습니다}"
  info "${C_DIM}주소와 포트, 방화벽, VPN 연결을 확인하세요.${C_RESET}"
}

# check_reach <주소> <포트>
# 처음 보는 서버면 호스트 키를 받아 지문을 보여 주고 known_hosts 에 넣을지 묻는다.
# 이미 아는 서버면 접속하지 않고 REACH_PENDING 만 세워, check_auth 가 결과를 대신 알리게 한다.
check_reach() {
  local host="$1" port="$2" types
  REACH_PENDING=""
  if known_host "$host" "$port"; then
    REACH_PENDING="$host $port"
    skip "${C_DIM}이미 아는 서버입니다. 다음 접속에서 함께 확인합니다.${C_RESET}"
    return 0
  fi

  # 키 종류마다 접속이 하나씩 생기므로 가장 흔한 ed25519 부터 하나씩만 묻는다.
  : >"$TMP/scan"
  for types in ed25519 ecdsa rsa; do
    ui_spin "서버 응답 확인 중  $host:$port" "$TMP/scan.raw" \
      ssh-keyscan -T "$CONNECT_TIMEOUT" -t "$types" -p "$port" "$host"
    grep -v '^#' "$TMP/scan.raw" 2>/dev/null | grep -E ' (ssh-|ecdsa-)' >"$TMP/scan"
    [[ -s "$TMP/scan" ]] && break
    # 아예 연결이 안 되면 다른 키 종류를 물어도 같다.
    grep -qiE "$NET_ERRORS" "$TMP/scan.raw" && break
  done
  if [[ ! -s "$TMP/scan" ]]; then
    reach_fail "$host" "$port"
    return 1
  fi
  reach_ok "$host" "$port"

  warn "처음 접속하는 서버입니다. 호스트 키 지문:"
  ssh-keygen -lf "$TMP/scan" 2>/dev/null | sed 's/^/        /'
  info "${C_DIM}서버 관리자가 알려 준 지문과 같은지 확인하세요.${C_RESET}"
  if ! confirm "이 서버를 신뢰하고 known_hosts 에 추가할까요?"; then
    fail "호스트 키를 신뢰하지 않아 중단합니다."
    return 1
  fi
  mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
  cat "$TMP/scan" >>"$KNOWN_HOSTS" && chmod 600 "$KNOWN_HOSTS"
  ok "known_hosts 에 추가했습니다."
}

# check_auth <개인 키 경로 또는 빈 값> <ssh 대상 인자...>
# 실패하면 원인을 AUTH_FAIL 에 남긴다: network(서버에 닿지 않음) | locked(키 암호를 물을 수 없음) | denied | other
check_auth() {
  local key="$1" err pending="${REACH_PENDING:-}"; shift
  AUTH_INTERACTIVE=false
  AUTH_FAIL=""
  REACH_PENDING=""
  set_base_opts

  # shellcheck disable=SC2086  # pending 은 "<주소> <포트>" 두 단어다
  if ui_spin "연결 확인 중" "$TMP/auth.out" ssh "${BASE[@]}" -n -o BatchMode=yes "$@" true; then
    [[ -n "$pending" ]] && reach_ok $pending
    ok "SSH 인증  ${C_DIM}키로 로그인됩니다${C_RESET}"
    return 0
  fi
  err="$(last_line "$TMP/auth.out")"

  if grep -qiE "$NET_ERRORS" "$TMP/auth.out"; then
    AUTH_FAIL=network
    reach_fail "" "" "${err:-서버에 연결할 수 없습니다}"
    return 1
  fi
  # shellcheck disable=SC2086
  [[ -n "$pending" ]] && reach_ok $pending

  # 키에 암호가 걸려 있으면 배치 모드로는 열 수 없다. 암호를 직접 입력받아 다시 시도한다.
  if grep -qi 'permission denied' "$TMP/auth.out" && [[ -n "$key" ]] && key_encrypted "$key"; then
    if ! has_tty; then
      AUTH_FAIL=locked
      fail "SSH 인증  키에 암호가 걸려 있어 터미널 없이는 확인할 수 없습니다"
      info "${C_DIM}ssh-add $(tilde_path "$key") 로 키를 올린 뒤 다시 실행하세요.${C_RESET}"
      return 1
    fi
    info "키에 암호가 걸려 있습니다. 암호를 입력하세요. ${C_DIM}($(tilde_path "$key"))${C_RESET}"
    if ssh "${BASE[@]}" -o PreferredAuthentications=publickey -o PasswordAuthentication=no \
         -o KbdInteractiveAuthentication=no "$@" true </dev/tty 2>"$TMP/auth.out"; then
      AUTH_INTERACTIVE=true
      ok "SSH 인증  ${C_DIM}키로 로그인됩니다 (암호 입력 필요)${C_RESET}"
      info "${C_DIM}매번 묻지 않게 하려면: ssh-add $(tilde_path "$key")${C_RESET}"
      return 0
    fi
    err="$(last_line "$TMP/auth.out")"
  fi

  if grep -qi 'permission denied' "$TMP/auth.out"; then AUTH_FAIL=denied; else AUTH_FAIL=other; fi
  fail "SSH 인증  ${err:-로그인하지 못했습니다}"
  return 1
}

# check_sftp <서버 경로 또는 빈 값> <sftp 대상 인자...>
# 서버 경로를 주면 그 디렉토리로 들어갈 수 있는지까지 본다. 성공하면 REMOTE_PWD 를 채운다.
check_sftp() {
  local path="$1" err rc; shift
  REMOTE_PWD=""
  set_base_opts

  : >"$TMP/batch"
  [[ -n "$path" ]] && printf 'cd "%s"\n' "$path" >>"$TMP/batch"
  printf 'pwd\n' >>"$TMP/batch"

  if $AUTH_INTERACTIVE; then
    sftp "${BASE[@]}" -q -o PreferredAuthentications=publickey "$@" <"$TMP/batch" >"$TMP/sftp.out" 2>&1
    rc=$?
  else
    ui_spin "SFTP 연결 확인 중" "$TMP/sftp.out" sftp "${BASE[@]}" -b "$TMP/batch" -o BatchMode=yes "$@"
    rc=$?
  fi

  REMOTE_PWD="$(sed -n 's/^Remote working directory: //p' "$TMP/sftp.out" | tail -n 1)"
  if ((rc == 0)) && [[ -n "$REMOTE_PWD" ]]; then
    ok "SFTP      ${C_DIM}연결됩니다 (서버 경로: $REMOTE_PWD)${C_RESET}"
    return 0
  fi
  err="$(last_line "$TMP/sftp.out")"
  fail "SFTP      ${err:-연결하지 못했습니다}"
  return 1
}

# 등록된 별칭 하나를 세 단계로 확인한다. health_check <별칭>
health_check() {
  local name="$1" host port user proxy key rc=0
  host="$(host_field "$name" hostname)"
  port="$(host_field "$name" port)"
  user="$(host_field "$name" user)"
  key="$(host_key_file "$name" || true)"
  step "$name  ${C_DIM}${user}@${host}:${port}${C_RESET}"

  # 경유 서버를 거치는 호스트는 이 기기에서 직접 닿지 않으므로 1단계를 건너뛴다.
  proxy="$(host_field "$name" proxyjump)$(host_field "$name" proxycommand)"
  if [[ -n "${proxy//none/}" ]]; then
    skip "서버 응답  ${C_DIM}경유 서버(ProxyJump/ProxyCommand)를 쓰는 호스트라 건너뜁니다${C_RESET}"
  else
    check_reach "$host" "$port" || return 1
  fi

  check_auth "$key" "$name" || rc=1
  # 서버에 닿지 않았거나 키를 열 수 없으면 SFTP 도 같은 이유로 실패하므로 다시 접속하지 않는다.
  # 그 밖의 실패는 SFTP 만 허용하는 서버(SSH 명령 실행 차단)일 수 있어 따로 확인한다.
  case "$AUTH_FAIL" in network|locked) return 1 ;; esac
  check_sftp "" "$name" || rc=1
  return $rc
}

# ------------------------------------------------------------------- add --

# 쓸 개인 키를 고르거나 새로 만든다. 결과 경로를 KEY 에 넣는다.
# choose_key <별칭>
choose_key() {
  local name="$1" pub priv choice new_label="새 키 만들기 (ed25519)"
  local labels=()

  for pub in "$SSH_DIR"/*.pub; do
    priv="${pub%.pub}"
    [[ -f "$pub" && -f "$priv" ]] && labels+=("$(tilde_path "$priv")")
  done

  if ((${#labels[@]} > 0)) && has_tty && ! $ASSUME_YES; then
    choice="$(ui_choose "어떤 키로 접속할까요?" "${labels[@]}" "$new_label")" || return 1
  elif ((${#labels[@]} > 0)); then
    choice="${labels[0]}"
  else
    choice="$new_label"
  fi

  if [[ "$choice" != "$new_label" ]]; then
    KEY="$(expand_home "$choice")"
    return 0
  fi

  KEY="$SSH_DIR/id_ed25519"
  [[ -e "$KEY" ]] && KEY="$SSH_DIR/id_ed25519_$name"
  [[ -e "$KEY" ]] && die "키 파일이 이미 있습니다: $KEY (--key 로 지정하세요)"

  info "새 키를 만듭니다: $(tilde_path "$KEY")"
  run mkdir -p "$SSH_DIR"
  $DRY_RUN || chmod 700 "$SSH_DIR"
  if $ASSUME_YES || ! has_tty; then
    run ssh-keygen -q -t ed25519 -N "" -C "$(id -un)@$(hostname -s 2>/dev/null || hostname)" -f "$KEY" || return 1
  else
    info "${C_DIM}키 암호를 묻습니다. 비워 두면 암호 없이 만들어집니다.${C_RESET}"
    run ssh-keygen -q -t ed25519 -C "$(id -un)@$(hostname -s 2>/dev/null || hostname)" -f "$KEY" </dev/tty || return 1
  fi
  ok "키 생성 완료"
}

# 서버의 authorized_keys 에 공개 키를 넣는다. 이미 있으면 다시 넣지 않는다.
# ssh-copy-id 는 Git for Windows 에 없을 수 있어 같은 일을 직접 한다.
# shellcheck disable=SC2016  # 서버에서 펼쳐져야 하는 변수다
REMOTE_ADD_KEY='umask 077; mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && k=$(cat) && { grep -qxF "$k" ~/.ssh/authorized_keys || printf "%s\n" "$k" >> ~/.ssh/authorized_keys; }'

# register_key <개인 키 경로> <ssh 대상 인자...>
register_key() {
  local key="$1"; shift
  [[ -f "$key.pub" ]] || { fail "공개 키가 없습니다: $key.pub"; return 1; }
  has_tty || { fail "비밀번호를 입력할 터미널이 없어 공개 키를 등록할 수 없습니다."; return 1; }
  set_base_opts
  info "서버 비밀번호를 묻습니다. ${C_DIM}(스크립트는 비밀번호를 보거나 저장하지 않습니다)${C_RESET}"
  # 표준 입력은 공개 키가 차지하고, 비밀번호는 ssh 가 터미널에서 직접 읽는다.
  if ssh "${BASE[@]}" -o PubkeyAuthentication=no \
       -o PreferredAuthentications=keyboard-interactive,password "$@" "$REMOTE_ADD_KEY" <"$key.pub"; then
    ok "공개 키를 서버에 등록했습니다."
    return 0
  fi
  fail "공개 키를 등록하지 못했습니다."
  info "${C_DIM}서버가 비밀번호 로그인을 막고 있다면, 아래 공개 키를 서버 관리자에게 전달하세요.${C_RESET}"
  sed 's/^/        /' "$key.pub"
  return 1
}

# config 에 붙일 Host 블록을 출력한다.
host_block() {
  local name="$1" host="$2" user="$3" port="$4" key="$5" keypath
  keypath="$(tilde_path "$key")"
  [[ "$keypath" == *" "* ]] && keypath="\"$keypath\""
  cat <<EOF
# dotfiles ssh add · $(date +%Y-%m-%d)
Host $name
  HostName $host
  User $user
  Port $port
  IdentityFile $keypath
  IdentitiesOnly yes
EOF
}

# 기존 내용은 건드리지 않고 끝에 덧붙인다. 바꾸기 전에 백업한다.
append_host_block() {
  local block="$1"
  if $DRY_RUN; then
    info "${C_DIM}[dry-run] $(tilde_path "$SSH_CONFIG") 에 추가할 내용:${C_RESET}"
    printf '%s\n' "$block" | sed 's/^/        /'
    return 0
  fi
  mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR" || return 1
  if [[ -s "$SSH_CONFIG" ]]; then
    cp -p "$SSH_CONFIG" "$SSH_CONFIG.$BACKUP_SUFFIX" || return 1
    info "${C_DIM}백업: $(tilde_path "$SSH_CONFIG.$BACKUP_SUFFIX")${C_RESET}"
    # 마지막 줄이 줄바꿈으로 끝나지 않으면 앞 블록에 붙어 버린다.
    [[ -n "$(tail -c 1 "$SSH_CONFIG")" ]] && printf '\n' >>"$SSH_CONFIG"
    printf '\n' >>"$SSH_CONFIG"
  fi
  printf '%s\n' "$block" >>"$SSH_CONFIG" && chmod 600 "$SSH_CONFIG"
}

cmd_add() {
  local name="" host="" user="" port="" target=()
  KEY=""

  while (($#)); do
    case "$1" in
      --name) name="${2:-}"; shift ;;
      --host) host="${2:-}"; shift ;;
      --user) user="${2:-}"; shift ;;
      --port) port="${2:-}"; shift ;;
      --key)  KEY="$(expand_home "${2:-}")"; shift ;;
      *)      die "알 수 없는 옵션: $1" ;;
    esac
    shift
  done

  has_tty && ui_title "SSH 호스트 등록" "연결 확인 → 키 등록 → $(tilde_path "$SSH_CONFIG")"
  $DRY_RUN && warn "dry-run 모드: 설정 파일을 쓰지 않습니다. (연결 확인은 실제로 합니다)"

  name="$(ask "별칭" --name "$name" "" "dev-server" valid_name)" || return 1
  host_exists "$name" && die "이미 등록된 별칭입니다: $name ($(tilde_path "$SSH_CONFIG"))"
  host="$(ask "서버 주소" --host "$host" "" "203.0.113.10 또는 example.com" valid_host)" || return 1
  # 터미널이 없으면 물어볼 수 없으니 기본값을 쓴다.
  if ! has_tty; then user="${user:-$(default_user)}"; port="${port:-22}"; fi
  user="$(ask "사용자" --user "$user" "$(default_user)" "" valid_user)" || return 1
  port="$(ask "포트" --port "$port" "22" "" valid_port)" || return 1

  step "[1/4] 서버 응답"
  check_reach "$host" "$port" || return 1

  step "[2/4] SSH 인증"
  if [[ -n "$KEY" ]]; then
    [[ -f "$KEY" ]] || die "키 파일이 없습니다: $KEY"
  else
    choose_key "$name" || return 1
  fi
  info "키: $(tilde_path "$KEY")"
  if $DRY_RUN && [[ ! -f "$KEY" ]]; then
    warn "dry-run 이라 키를 만들지 않았습니다. 인증 확인은 건너뜁니다."
    return 0
  fi

  # 별칭이 아직 config 에 없으므로 같은 값을 옵션으로 직접 넘겨 확인한다.
  target=(-o "Port=$port" -o "User=$user" -o "IdentityFile=$KEY" -o IdentitiesOnly=yes "$host")
  if ! check_auth "$KEY" "${target[@]}"; then
    [[ "$AUTH_FAIL" == denied ]] || return 1
    confirm "이 키로는 로그인되지 않습니다. 공개 키를 서버에 등록할까요?" || return 1
    if $DRY_RUN; then
      warn "dry-run 이라 공개 키를 등록하지 않았습니다."
      return 0
    fi
    register_key "$KEY" -o "Port=$port" -o "User=$user" "$host" || return 1
    check_auth "$KEY" "${target[@]}" || return 1
  fi

  step "[3/4] SFTP"
  check_sftp "" "${target[@]}" \
    || warn "SSH 는 되지만 SFTP 는 열리지 않습니다. 서버의 Subsystem sftp 설정을 확인하세요."

  step "[4/4] 저장"
  append_host_block "$(host_block "$name" "$host" "$user" "$port" "$KEY")" || { fail "저장 실패"; return 1; }
  $DRY_RUN && return 0
  ok "$(tilde_path "$SSH_CONFIG") 에 ${C_BOLD}$name${C_RESET} 을(를) 추가했습니다."

  # 저장한 별칭 그대로 한 번 더 접속해, 다른 Host 블록에 가려지지 않았는지 본다.
  if ! check_auth "$KEY" "$name"; then
    warn "저장은 했지만 별칭으로는 접속되지 않습니다. config 의 다른 Host 블록이 값을 덮는지 확인하세요."
    return 1
  fi

  printf '\n%s등록 완료!%s\n' "$C_BOLD$C_GREEN" "$C_RESET"
  info "터미널   ssh $name"
  info "Cursor   명령 팔레트 → Remote-SSH: Connect to Host... → $name"
  info "SFTP     bash scripts/dotfiles.sh ssh sftp $name"
  printf '\n'
}

# ------------------------------------------------------------------ list --

cmd_list() {
  local name rows="" n=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    rows+="$name|$(host_field "$name" hostname)|$(host_field "$name" user)|$(host_field "$name" port)"$'\n'
    n=$((n + 1))
  done < <(list_hosts)

  if ((n == 0)); then
    info "등록된 호스트가 없습니다. ${C_DIM}($(tilde_path "$SSH_CONFIG"))${C_RESET}"
    info "추가: bash scripts/dotfiles.sh ssh add"
    return 0
  fi

  if use_gum && [[ -t 1 ]]; then
    printf '%s' "$rows" | gum table --print --separator "|" --columns "별칭,주소,사용자,포트" \
      --border rounded --border.foreground "$UI_BORDER"
  else
    printf '\n  %s%-20s %-28s %-14s %s%s\n' "$C_BOLD" "별칭" "주소" "사용자" "포트" "$C_RESET"
    printf '%s' "$rows" | awk -F'|' '{ printf "  %-20s %-28s %-14s %s\n", $1, $2, $3, $4 }'
    printf '\n'
  fi
}

# ----------------------------------------------------------------- check --

cmd_check() {
  local all=false name picked failed="" passed=0 total=0
  local names=()

  while (($#)); do
    case "$1" in
      --all) all=true ;;
      -*)    die "알 수 없는 옵션: $1" ;;
      *)     host_exists "$1" || die "등록되지 않은 호스트: $1"; names+=("$1") ;;
    esac
    shift
  done

  if ((${#names[@]} == 0)); then
    while IFS= read -r name; do [[ -n "$name" ]] && names+=("$name"); done < <(list_hosts)
    ((${#names[@]} > 0)) || { info "등록된 호스트가 없습니다. 추가: bash scripts/dotfiles.sh ssh add"; return 0; }

    if ! $all && has_tty && ((${#names[@]} > 1)); then
      ui_title "SSH / SFTP 헬스체크" "서버 응답 → SSH 인증 → SFTP"
      picked="$(ui_choose_multi "확인할 호스트를 고르세요" "$(printf '%s\n' "${names[@]}")" "${names[@]}")" || return 1
      names=()
      while IFS= read -r name; do [[ -n "$name" ]] && names+=("$name"); done <<<"$picked"
      ((${#names[@]} > 0)) || { info "고른 호스트가 없습니다."; return 0; }
    fi
  fi

  for name in "${names[@]}"; do
    total=$((total + 1))
    if health_check "$name"; then passed=$((passed + 1)); else failed+=" $name"; fi
  done

  step "요약"
  if [[ -z "$failed" ]]; then
    ok "$total 개 호스트 모두 정상입니다."
    return 0
  fi
  ok "정상: $passed / $total"
  fail "문제 있음:$failed"
  return 1
}

# ------------------------------------------------------------------ sftp --

json_str() {
  local s="${1//\\/\\\\}"
  printf '"%s"' "${s//\"/\\\"}"
}

# 에디터 확장(Node.js)이 읽을 수 있는 경로로 바꾼다. Git Bash 의 /c/Users/... 는 C:/Users/... 로.
native_path() {
  if [[ "$(ui_os)" == "windows" ]] && has cygpath; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

valid_remote_path() { [[ "$1" == /* && "$1" != *'"'* && "$1" != *$'\n'* ]]; }
valid_dir()         { [[ -d "$(expand_home "$1")" ]]; }

cmd_sftp() {
  local name="" dir="" remote="" key host port user target json first
  local names=()

  while (($#)); do
    case "$1" in
      --dir)    dir="${2:-}"; shift ;;
      --remote) remote="${2:-}"; shift ;;
      -*)       die "알 수 없는 옵션: $1" ;;
      *)        name="$1" ;;
    esac
    shift
  done

  has_tty && ui_title "SFTP 설정 만들기" "연결 확인 → <프로젝트>/.vscode/sftp.json"
  $DRY_RUN && warn "dry-run 모드: 설정 파일을 쓰지 않습니다. (연결 확인은 실제로 합니다)"

  if [[ -z "$name" ]]; then
    while IFS= read -r first; do [[ -n "$first" ]] && names+=("$first"); done < <(list_hosts)
    ((${#names[@]} > 0)) || die "등록된 호스트가 없습니다. 먼저: bash scripts/dotfiles.sh ssh add"
    has_tty || die "호스트를 지정하세요. (예: ssh sftp ${names[0]})"
    name="$(ui_choose "어느 서버에 연결할까요?" "${names[@]}")" || return 1
  fi
  host_exists "$name" || die "등록되지 않은 호스트: $name"

  # 연결이 안 되는 서버의 설정 파일은 만들지 않는다.
  health_check "$name" || { fail "연결이 확인되지 않아 sftp.json 을 만들지 않았습니다."; return 1; }

  step "서버 경로"
  remote="$(ask "서버 쪽 프로젝트 경로" --remote "$remote" "$REMOTE_PWD" "/var/www/app" valid_remote_path)" || return 1
  check_sftp "$remote" "$name" || { fail "서버에 그 경로가 없거나 들어갈 수 없습니다: $remote"; return 1; }

  step "프로젝트 폴더"
  dir="$(ask "로컬 프로젝트 폴더" --dir "$dir" "$PWD" "" valid_dir)" || return 1
  dir="$(cd "$(expand_home "$dir")" && pwd)"
  target="$dir/.vscode/sftp.json"
  info "$target"

  host="$(host_field "$name" hostname)"
  port="$(host_field "$name" port)"
  user="$(host_field "$name" user)"
  key="$(host_key_file "$name" || true)"

  # 확장이 ~/.ssh/config 를 읽지 못하는 환경에서도 동작하도록 접속 값을 풀어서 적는다.
  json="{
  \"name\": $(json_str "$name"),
  \"host\": $(json_str "$host"),
  \"protocol\": \"sftp\",
  \"port\": $port,
  \"username\": $(json_str "$user"),"
  if [[ -n "$key" ]]; then
    json+="
  \"privateKeyPath\": $(json_str "$(native_path "$key")"),"
    key_encrypted "$key" && json+="
  \"passphrase\": true,"
  fi
  json+="
  \"remotePath\": $(json_str "$REMOTE_PWD"),
  \"uploadOnSave\": false,
  \"ignore\": [\".vscode\", \".git\", \".DS_Store\"]
}"

  if $DRY_RUN; then
    info "${C_DIM}[dry-run] 만들 내용:${C_RESET}"
    printf '%s\n' "$json" | sed 's/^/        /'
    return 0
  fi

  if [[ -e "$target" ]]; then
    confirm "sftp.json 이 이미 있습니다. 백업하고 새로 만들까요?" || return 1
    mv "$target" "$target.$BACKUP_SUFFIX" || return 1
    info "${C_DIM}백업: $target.$BACKUP_SUFFIX${C_RESET}"
  fi
  mkdir -p "$dir/.vscode" && printf '%s\n' "$json" >"$target" || { fail "쓰기 실패: $target"; return 1; }
  ok "sftp.json 을 만들었습니다."

  # 서버 주소와 경로가 들어 있으므로 저장소에 올라가지 않게 한다. (백업 파일 포함)
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
     && ! git -C "$dir" check-ignore -q "$target" 2>/dev/null; then
    if confirm ".vscode/sftp.json 을 이 프로젝트의 .gitignore 에 추가할까요?"; then
      [[ -s "$dir/.gitignore" && -n "$(tail -c 1 "$dir/.gitignore")" ]] && printf '\n' >>"$dir/.gitignore"
      printf '.vscode/sftp.json*\n' >>"$dir/.gitignore"
      ok ".gitignore 에 추가했습니다."
    else
      warn "sftp.json 이 git 에 올라가지 않도록 직접 관리하세요."
    fi
  fi

  printf '\n%s완료!%s Cursor 에서 이 폴더를 열고 명령 팔레트의 SFTP: 명령을 쓰면 됩니다.\n\n' "$C_BOLD$C_GREEN" "$C_RESET"
}

# -------------------------------------------------------------------- main --

MENU_ADD="호스트 등록"
MENU_LIST="호스트 목록"
MENU_CHECK="연결 확인 (헬스체크)"
MENU_SFTP="SFTP 설정 만들기"

run_menu() {
  local choice
  ui_title "SSH / SFTP" "$(tilde_path "$SSH_CONFIG")"
  choice="$(ui_choose "무엇을 할까요?" "$MENU_ADD" "$MENU_LIST" "$MENU_CHECK" "$MENU_SFTP")" || return 0
  case "$choice" in
    "$MENU_ADD")   cmd_add ;;
    "$MENU_LIST")  cmd_list ;;
    "$MENU_CHECK") cmd_check ;;
    "$MENU_SFTP")  cmd_sftp ;;
  esac
}

usage() { usage_from "${BASH_SOURCE[0]}" 19; }

main() {
  local cmd="" rc=0
  local args=()

  while (($#)); do
    case "$1" in
      -y|--yes)     ASSUME_YES=true ;;
      -n|--dry-run) DRY_RUN=true ;;
      -h|--help)    usage; exit 0 ;;
      add|list|check|sftp)
        if [[ -z "$cmd" ]]; then cmd="$1"; else args+=("$1"); fi ;;
      *)            args+=("$1") ;;
    esac
    shift
  done

  has ssh && has ssh-keygen && has ssh-keyscan && has sftp \
    || die "OpenSSH 클라이언트(ssh, ssh-keygen, ssh-keyscan, sftp)가 필요합니다."

  TMP="$(mktemp -d)" || die "임시 디렉토리를 만들 수 없습니다."

  case "$cmd" in
    add)   cmd_add   ${args[@]+"${args[@]}"} || rc=1 ;;
    list)  cmd_list  || rc=1 ;;
    check) cmd_check ${args[@]+"${args[@]}"} || rc=1 ;;
    sftp)  cmd_sftp  ${args[@]+"${args[@]}"} || rc=1 ;;
    "")
      if ((${#args[@]} > 0)); then
        rm -rf "$TMP"; die "알 수 없는 명령: ${args[0]} (--help 참고)"
      elif has_tty; then
        run_menu || rc=1
      else
        rm -rf "$TMP"; die "대화형 터미널이 아닙니다. 명령을 직접 지정하세요. (--help 참고)"
      fi ;;
  esac

  rm -rf "$TMP"
  exit $rc
}

main "$@"
