#!/usr/bin/env bash
#
# Windows 초기 세팅 (Git Bash 에서 실행)
#
#   bash scripts/windows/setup.sh               # 설정 파일 링크 + 에디터 확장 설치
#   bash scripts/windows/setup.sh --dry-run     # 실제 변경 없이 실행 내용만 출력
#   bash scripts/windows/setup.sh --list        # 링크 대상과 현재 상태만 확인
#
# 준비물: Git for Windows (Git Bash), 심볼릭 링크 권한.
#   권한은 설정 → 시스템 → 개발자용 → "개발자 모드" 를 켜면 생긴다.
#   (또는 Git Bash 를 관리자 권한으로 실행)
#
# 모든 작업은 여러 번 실행해도 안전(idempotent)합니다.

set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/ui.sh
source "$SCRIPTS_DIR/lib/ui.sh"

BACKUP_SUFFIX="bak.$(date +%Y%m%d%H%M%S)"
LIST_ONLY=false

# Git Bash 의 ln -s 는 기본 동작이 "복사" 다. 복사본은 git pull 을 따라가지 않으므로
# 진짜 심볼릭 링크를 만들게 하고, 권한이 없으면 복사로 넘어가지 않고 실패하게 한다.
export MSYS=winsymlinks:nativestrict
export CYGWIN=winsymlinks:nativestrict

# ------------------------------------------------------------- 심볼릭 링크 --

# 링크 목록. 한 줄에 "<applications/ 안 경로>|<설치될 경로>"
#
# keybindings 는 OS 마다 수식키가 달라(macOS cmd ↔ Windows ctrl) 파일을 따로 둔다.
# Windows 는 keybindings.windows.json 을 쓴다.
link_targets() {
  local cfg
  cfg="$(app_config_dir)"
  printf '%s|%s\n' \
    "git/.gitconfig"                   "$HOME/.gitconfig" \
    "git/.gitignore_global"            "$HOME/.gitignore_global" \
    "cursor/settings.json"             "$cfg/Cursor/User/settings.json" \
    "cursor/keybindings.windows.json"  "$cfg/Cursor/User/keybindings.json" \
    "vscode/settings.json"             "$cfg/Code/User/settings.json" \
    "vscode/keybindings.windows.json"  "$cfg/Code/User/keybindings.json"
}

# 이 셸에서 진짜 심볼릭 링크를 만들 수 있는지 임시 디렉토리에서 확인한다.
can_symlink() {
  local dir rc=1
  dir="$(mktemp -d)" || return 1
  : >"$dir/src"
  ln -s "$dir/src" "$dir/dst" 2>/dev/null && [[ -L "$dir/dst" ]] && rc=0
  rm -rf "$dir"
  return $rc
}

# dst 가 src 를 가리키는 링크인지. readlink 출력은 경로 표기(C:\ ↔ /c/)가 갈릴 수 있어
# 문자열 대신 같은 파일인지(-ef)로 비교한다.
is_linked() { [[ -L "$2" && "$2" -ef "$1" ]]; }

# link <applications/ 안 경로> <설치될 경로>
# 원본이 없으면 건너뛰고, 기존 파일이 있으면 백업한 뒤 링크한다.
link() {
  local src="$APPS_DIR/$1" dst="$2"

  if [[ ! -e "$src" ]]; then
    skip "$1 ${C_DIM}(레포에 아직 파일 없음)${C_RESET}"
    return 0
  fi

  if is_linked "$src" "$dst"; then
    skip "$dst ${C_DIM}(이미 연결됨)${C_RESET}"
    return 0
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    warn "기존 파일 백업: $dst -> $dst.$BACKUP_SUFFIX"
    run mv "$dst" "$dst.$BACKUP_SUFFIX" || return 1
  fi

  run mkdir -p "$(dirname "$dst")"
  if ! run ln -s "$src" "$dst"; then
    fail "링크 실패: $dst"
    return 1
  fi
  ok "$dst -> $src"
}

install_links() {
  local src dst rc=0

  if ! can_symlink; then
    fail "심볼릭 링크를 만들 권한이 없습니다."
    info "설정 → 시스템 → 개발자용 → 개발자 모드 를 켠 뒤 다시 실행하세요."
    info "(또는 Git Bash 를 관리자 권한으로 실행)"
    # dry-run 은 무엇을 할지 보여 주는 게 목적이라 계속 진행한다.
    $DRY_RUN || return 1
  fi

  while IFS='|' read -r src dst; do
    link "$src" "$dst" || rc=1
  done < <(link_targets)
  return $rc
}

# ------------------------------------------------------------- 에디터 확장 --

install_extensions() {
  local editor list ext
  for editor in code cursor; do
    if [[ "$editor" == "code" ]]; then
      list="$APPS_DIR/vscode/extensions.txt"
    else
      list="$APPS_DIR/cursor/extensions.txt"
    fi

    [[ -f "$list" ]] || { skip "$editor ${C_DIM}(extensions.txt 없음)${C_RESET}"; continue; }
    if ! has "$editor"; then
      warn "$editor CLI 없음. 에디터를 설치할 때 'PATH 에 추가' 를 켜고 Git Bash 를 다시 여세요."
      continue
    fi

    while read -r ext; do
      ext="${ext%$'\r'}"   # CRLF 로 체크아웃된 경우 대비
      [[ -n "$ext" && "$ext" != \#* ]] || continue
      run "$editor" --install-extension "$ext" --force
    done <"$list"
    ok "$editor 확장 설치 완료"
  done
}

# -------------------------------------------------------------------- main --

print_list() {
  local src dst mark note
  printf '%s링크 대상%s\n\n' "$C_BOLD" "$C_RESET"
  while IFS='|' read -r src dst; do
    if [[ ! -e "$APPS_DIR/$src" ]]; then
      mark="${C_DIM}·${C_RESET}"; note="레포에 아직 파일 없음"
    elif is_linked "$APPS_DIR/$src" "$dst"; then
      mark="${C_GREEN}✓${C_RESET}"; note="연결됨"
    elif [[ -e "$dst" || -L "$dst" ]]; then
      mark="${C_YELLOW}!${C_RESET}"; note="다른 파일이 있음 (실행하면 백업 후 교체)"
    else
      mark="${C_DIM}·${C_RESET}"; note="아직 연결 안 됨"
    fi
    printf '  %s %s\n      %s%s  (%s)%s\n' "$mark" "$src" "$C_DIM" "$dst" "$note" "$C_RESET"
  done < <(link_targets)
  printf '\n'
}

usage() { usage_from "${BASH_SOURCE[0]}" 13; }

main() {
  while (($#)); do
    case "$1" in
      -a|--all)     ;;   # macOS 스크립트와 옵션을 맞추기 위해 받기만 한다. 항상 전체를 실행한다.
      -n|--dry-run) DRY_RUN=true ;;
      -l|--list)    LIST_ONLY=true ;;
      -h|--help)    usage; exit 0 ;;
      *)            die "알 수 없는 옵션: $1" ;;
    esac
    shift
  done

  [[ "$(ui_os)" == "windows" ]] \
    || die "이 스크립트는 Windows(Git Bash) 전용입니다. (현재: $(uname -s))"

  $LIST_ONLY && { print_list; exit 0; }

  info "dotfiles: $DOTFILES_DIR"
  $DRY_RUN && warn "dry-run 모드: 실제로 아무것도 변경하지 않습니다."

  local failed=false
  step "[1/2] dotfiles 링크"
  install_links || failed=true
  step "[2/2] 에디터 확장"
  install_extensions || failed=true

  if $failed; then
    printf '\n'
    fail "일부 항목이 실패했습니다. 위 메시지를 확인하세요."
    exit 1
  fi
  printf '\n%s세팅 완료!%s 에디터를 다시 열어 확인하세요.\n\n' "$C_BOLD$C_GREEN" "$C_RESET"
}

main "$@"
