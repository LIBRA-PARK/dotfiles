#!/usr/bin/env bash
#
# 폰트 설치 (macOS / Linux)
#
#   bash font/install.sh              # 홈 폰트 디렉토리로 심볼릭 링크
#   bash font/install.sh --copy       # 링크 대신 복사 (링크를 못 읽는 앱이 있을 때)
#   bash font/install.sh --dry-run    # 실제 변경 없이 실행 내용만 출력
#   bash font/install.sh --list       # 레포의 폰트와 현재 설치 상태만 확인
#   bash font/install.sh --uninstall  # 이 스크립트가 설치한 것만 제거
#
# 기본   : JetBrainsMono Nerd Font      (영문 + Nerd 아이콘)
# fallback: D2KodingLigature Nerd Font  (한글 + Nerd 아이콘)
#
# 여러 번 실행해도 안전(idempotent)합니다.
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않습니다.

set -uo pipefail

FONT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=false
LIST_ONLY=false
UNINSTALL=false
USE_COPY=false

# fontconfig 설정이 링크될 이름. conf.d 는 파일명 순으로 읽히므로 숫자 접두사를 둔다.
FONTCONF_NAME="10-dotfiles-fonts.conf"

# ---------------------------------------------------------------- 출력 헬퍼 --

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

step()  { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
skip()  { printf '    %s-%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
warn()  { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
die()   { printf '\n%s오류:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

run() {
  if $DRY_RUN; then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# ------------------------------------------------------------------ OS 판별 --

OS="$(uname -s)"

# 이 OS 에서 사용자 폰트가 놓이는 디렉토리
target_font_dir() {
  case "$OS" in
    Darwin) printf '%s\n' "$HOME/Library/Fonts" ;;
    Linux)  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" ;;
    *)      return 1 ;;
  esac
}

# ------------------------------------------------------------------ 폰트 목록 --

# 레포 안의 .ttf 를 한 줄씩 출력한다. (bash 3.2 라 배열 대신 스트림으로 다룬다)
list_font_files() {
  find "$FONT_DIR/jetbrains-mono" "$FONT_DIR/d2coding" \
    -maxdepth 1 -type f -name '*.ttf' 2>/dev/null | sort
}

# ------------------------------------------------------------------- 설치 --

# link_font <레포 안 ttf 경로> <설치 디렉토리>
link_font() {
  local src="$1" dir="$2"
  local dst="$dir/$(basename "$src")"

  if $USE_COPY; then
    # 이미 같은 내용이면 건너뛴다.
    if [[ -f "$dst" && ! -L "$dst" ]] && cmp -s "$src" "$dst"; then
      skip "$(basename "$src") ${C_DIM}(이미 동일)${C_RESET}"
      return 0
    fi
    run cp -f "$src" "$dst" || return 1
    ok "$(basename "$src") ${C_DIM}(복사)${C_RESET}"
    return 0
  fi

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    skip "$(basename "$src") ${C_DIM}(이미 연결됨)${C_RESET}"
    return 0
  fi

  # 같은 이름의 파일/깨진 링크가 있으면 치운다. 원본은 레포에 있으므로 백업하지 않는다.
  if [[ -e "$dst" || -L "$dst" ]]; then
    warn "기존 파일 교체: $dst"
    run rm -f "$dst" || return 1
  fi

  run ln -s "$src" "$dst" || return 1
  ok "$(basename "$src")"
}

install_fonts() {
  local dir file count=0
  dir="$(target_font_dir)" || die "지원하지 않는 OS: $OS (macOS / Linux 만 지원)"

  step "폰트 설치 → $dir"
  run mkdir -p "$dir"

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    link_font "$file" "$dir"
    count=$((count + 1))
  done <<EOF
$(list_font_files)
EOF

  ((count > 0)) || die "레포에 폰트 파일이 없습니다: $FONT_DIR"
  info "$count 개 처리"
}

# fontconfig 설정 링크 (Linux 전용). macOS 는 fontconfig 를 쓰지 않는다.
install_fontconfig() {
  [[ "$OS" == "Linux" ]] || return 0

  local src="$FONT_DIR/fonts.conf"
  local dst="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d/$FONTCONF_NAME"

  step "fontconfig fallback 체인"

  if [[ ! -f "$src" ]]; then
    warn "fonts.conf 없음: $src"
    return 0
  fi

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    skip "$dst ${C_DIM}(이미 연결됨)${C_RESET}"
    return 0
  fi

  run mkdir -p "$(dirname "$dst")"
  [[ -e "$dst" || -L "$dst" ]] && run rm -f "$dst"
  run ln -s "$src" "$dst" || return 1
  ok "$dst -> $src"
}

refresh_cache() {
  step "폰트 캐시 갱신"

  if [[ "$OS" == "Linux" ]]; then
    if has fc-cache; then
      run fc-cache -f "$(target_font_dir)" || return 1
      ok "fc-cache 완료"
    else
      warn "fc-cache 없음. fontconfig 패키지를 설치하세요."
    fi
  else
    # macOS CoreText 는 ~/Library/Fonts 변경을 자동으로 반영한다.
    skip "macOS 는 자동 반영 (이미 열려 있던 앱은 재시작 필요)"
  fi
}

# 설치 결과 확인. fontconfig 가 실제로 어떤 순서로 폰트를 고르는지 보여준다.
# fc-match 는 최종 1개만, fc-match -s 는 우선순위 순 전체 목록을 낸다.
verify() {
  [[ "$OS" == "Linux" ]] || return 0
  has fc-match || return 0

  step "확인"

  # 기대: 1순위 JetBrainsMono, 2순위 D2Koding
  info "${C_BOLD}monospace fallback 순서${C_RESET}"
  fc-match -s -f '%{family[0]}\n' monospace 2>/dev/null | head -3 | cat -n | sed 's/^/     /'

  local first hangul
  first="$(fc-match -f '%{family[0]}' 'JetBrainsMono Nerd Font' 2>/dev/null)"
  # 한글 '가' 를 실제로 그릴 수 있는 폰트가 무엇으로 잡히는지
  hangul="$(fc-match -f '%{family[0]}' ':charset=AC00:family=JetBrainsMono Nerd Font' 2>/dev/null)"

  if [[ "$first" == "JetBrainsMono Nerd Font" ]]; then
    ok "영문 → $first"
  else
    warn "영문 → $first ${C_DIM}(JetBrainsMono Nerd Font 가 아님)${C_RESET}"
  fi

  if [[ "$hangul" == "D2KodingLigature Nerd Font" ]]; then
    ok "한글 → $hangul"
  else
    warn "한글 → $hangul ${C_DIM}(D2KodingLigature Nerd Font 가 아님)${C_RESET}"
  fi
}

# ----------------------------------------------------------------- 제거 --

uninstall_fonts() {
  local dir file dst removed=0
  dir="$(target_font_dir)" || die "지원하지 않는 OS: $OS"

  step "폰트 제거 ← $dir"

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    dst="$dir/$(basename "$file")"

    # 우리가 만든 링크이거나 레포 파일과 같은 내용일 때만 지운다.
    if [[ -L "$dst" && "$(readlink "$dst")" == "$file" ]]; then
      run rm -f "$dst" && { ok "$(basename "$file") ${C_DIM}(링크)${C_RESET}"; removed=$((removed + 1)); }
    elif [[ -f "$dst" ]] && cmp -s "$file" "$dst"; then
      run rm -f "$dst" && { ok "$(basename "$file") ${C_DIM}(복사본)${C_RESET}"; removed=$((removed + 1)); }
    else
      skip "$(basename "$file") ${C_DIM}(이 스크립트가 설치한 것이 아님)${C_RESET}"
    fi
  done <<EOF
$(list_font_files)
EOF

  if [[ "$OS" == "Linux" ]]; then
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d/$FONTCONF_NAME"
    if [[ -L "$conf" && "$(readlink "$conf")" == "$FONT_DIR/fonts.conf" ]]; then
      run rm -f "$conf" && ok "$FONTCONF_NAME"
    fi
  fi

  info "$removed 개 제거"
  refresh_cache
}

# ------------------------------------------------------------------ 목록 --

print_list() {
  local dir file dst mark state
  dir="$(target_font_dir)" || die "지원하지 않는 OS: $OS"

  printf '%s레포 폰트%s  (%s)\n\n' "$C_BOLD" "$C_RESET" "$FONT_DIR"

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    dst="$dir/$(basename "$file")"

    if [[ -L "$dst" && "$(readlink "$dst")" == "$file" ]]; then
      mark="${C_GREEN}✓${C_RESET}"; state="링크됨"
    elif [[ -f "$dst" ]] && cmp -s "$file" "$dst"; then
      mark="${C_GREEN}✓${C_RESET}"; state="복사됨"
    elif [[ -e "$dst" ]]; then
      mark="${C_YELLOW}!${C_RESET}"; state="다른 파일이 있음"
    else
      mark="${C_DIM}·${C_RESET}"; state="미설치"
    fi

    printf '  %s %-42s %s\n' "$mark" "$(basename "$file")" "${C_DIM}$state${C_RESET}"
  done <<EOF
$(list_font_files)
EOF

  printf '\n  설치 위치: %s\n' "$dir"
  if [[ "$OS" == "Linux" ]]; then
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d/$FONTCONF_NAME"
    [[ -L "$conf" ]] && printf '  fontconfig: %s %s(링크됨)%s\n' "$conf" "$C_DIM" "$C_RESET" \
                     || printf '  fontconfig: %s %s(미설치)%s\n' "$conf" "$C_DIM" "$C_RESET"
  fi
  printf '\n'
}

# -------------------------------------------------------------------- main --

usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^#\{0,1\} \{0,1\}//'; }

main() {
  while (($#)); do
    case "$1" in
      -n|--dry-run)   DRY_RUN=true ;;
      -l|--list)      LIST_ONLY=true ;;
      -u|--uninstall) UNINSTALL=true ;;
      -c|--copy)      USE_COPY=true ;;
      -h|--help)      usage; exit 0 ;;
      *)              die "알 수 없는 옵션: $1" ;;
    esac
    shift
  done

  case "$OS" in
    Darwin|Linux) ;;
    *) die "지원하지 않는 OS: $OS (macOS / Linux 만 지원)" ;;
  esac

  $LIST_ONLY && { print_list; exit 0; }

  $DRY_RUN && warn "dry-run 모드: 실제로 아무것도 변경하지 않습니다."

  if $UNINSTALL; then
    uninstall_fonts
    printf '\n%s제거 완료%s\n\n' "$C_BOLD$C_GREEN" "$C_RESET"
    exit 0
  fi

  install_fonts || exit 1
  install_fontconfig || exit 1
  refresh_cache
  $DRY_RUN || verify

  printf '\n%s폰트 설치 완료!%s\n' "$C_BOLD$C_GREEN" "$C_RESET"
  printf '  기본   : %sJetBrainsMono Nerd Font%s\n' "$C_BOLD" "$C_RESET"
  printf '  fallback: %sD2KodingLigature Nerd Font%s\n' "$C_BOLD" "$C_RESET"
  printf '  터미널/에디터 설정은 README 의 "앱별 설정" 을 참고하세요.\n\n'
}

main "$@"
