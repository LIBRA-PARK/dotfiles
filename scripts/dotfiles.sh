#!/usr/bin/env bash
#
# dotfiles 단일 진입점 (TUI)
#
#   bash scripts/dotfiles.sh                     # 메뉴에서 작업 선택
#   bash scripts/dotfiles.sh setup [옵션]        # OS 별 초기 세팅 (scripts/<os>/setup.sh)
#   bash scripts/dotfiles.sh font [옵션]         # 폰트 설치/확인 (scripts/lib/font.sh)
#   bash scripts/dotfiles.sh theme [테마] [옵션] # 테마 적용 (scripts/lib/theme.sh)
#   bash scripts/dotfiles.sh themes-index [옵션] # themes/README.md 인덱스 갱신
#
# 옵션은 하위 스크립트에 그대로 넘긴다. 예) dotfiles.sh setup --dry-run
# 각 하위 스크립트는 단독으로 실행해도 동작한다.
#
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않는다.

set -uo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/ui.sh
source "$SCRIPTS_DIR/lib/ui.sh"

# 현재 OS 의 scripts/ 하위 디렉토리 이름 (macos | linux | windows)
os_dir() {
  local os
  os="$(ui_os)"
  [[ "$os" != "unknown" ]] || return 1
  printf '%s\n' "$os"
}

# 명령 이름 → 실행할 스크립트 경로. 없으면 1 을 반환한다.
script_for() {
  local os
  case "$1" in
    setup)
      os="$(os_dir)" || return 1
      printf '%s\n' "$SCRIPTS_DIR/$os/setup.sh" ;;
    font)         printf '%s\n' "$SCRIPTS_DIR/lib/font.sh" ;;
    theme)        printf '%s\n' "$SCRIPTS_DIR/lib/theme.sh" ;;
    themes-index) printf '%s\n' "$SCRIPTS_DIR/lib/themes-index.sh" ;;
    *)            return 1 ;;
  esac
}

dispatch() {
  local cmd="$1" script
  shift
  # die 대신 fail 을 쓴다. 메뉴에서 실패해도 메뉴로 돌아올 수 있게.
  if ! script="$(script_for "$cmd")"; then
    fail "알 수 없는 명령: $cmd (--help 참고)"; return 1
  fi
  if [[ ! -f "$script" ]]; then
    fail "아직 이 OS 용 스크립트가 없습니다: ${script#"$DOTFILES_DIR"/}"; return 1
  fi
  bash "$script" "$@"
}

# ------------------------------------------------------------------- 메뉴 --

# 라벨|명령|인자   (인자는 공백 구분, 비워도 된다. 라벨에 쉼표 금지)
MENU=(
  "초기 세팅|setup|"
  "초기 세팅 미리보기 (dry-run)|setup|--dry-run"
  "폰트 설치|font|"
  "폰트 설치 상태|font|--list"
  "테마 적용|theme|"
  "테마 지원 현황|theme|--list"
  "테마 인덱스 갱신|themes-index|"
)
MENU_QUIT="종료"

run_menu() {
  local labels=() entry choice cmd args i os
  for entry in "${MENU[@]}"; do labels+=("${entry%%|*}"); done
  os="$(os_dir 2>/dev/null || uname -s)"

  ui_gum_notice

  # 하위 스크립트(setup 의 체크리스트 등)가 끝나면 메뉴로 돌아온다.
  while :; do
    printf '\033[H\033[2J' >/dev/tty
    ui_title "dotfiles" "$os · ${DOTFILES_DIR/#$HOME/~}"
    choice="$(ui_choose "무엇을 할까요?" "${labels[@]}" "$MENU_QUIT")" || break
    [[ "$choice" == "$MENU_QUIT" ]] && break

    for ((i = 0; i < ${#MENU[@]}; i++)); do
      [[ "${labels[$i]}" == "$choice" ]] || continue
      entry="${MENU[$i]#*|}"
      cmd="${entry%%|*}"
      args="${entry#*|}"
      # shellcheck disable=SC2086  # args 는 공백 구분 옵션 목록이다
      dispatch "$cmd" $args
      ui_pause "아무 키나 누르면 메뉴로 돌아갑니다..."
    done
  done
}

main() {
  case "${1:-}" in
    -h|--help) usage_from "${BASH_SOURCE[0]}" 14; exit 0 ;;
    "")
      if [[ -t 1 ]] && (exec 3</dev/tty) 2>/dev/null; then
        run_menu
      else
        die "대화형 터미널이 아닙니다. 명령을 직접 지정하세요. (--help 참고)"
      fi ;;
    *) dispatch "$@" || exit $? ;;
  esac
}

main "$@"
