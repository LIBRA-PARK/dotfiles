#!/usr/bin/env bash
#
# scripts/ 공용 TUI 컴포넌트. common.sh 다음에 source 한다. 단독 실행하지 않는다.
#
#   ui_title    <제목> [부제]                   상단 제목 박스
#   ui_choose   <헤더> <항목>...                하나 고르기     → 고른 항목을 stdout
#   ui_choose_multi <헤더> <기본선택> <항목>... 여러 개 고르기 → 고른 항목들을 줄 단위로 stdout
#                                               (기본선택: 항목을 줄바꿈으로 이은 문자열)
#   ui_confirm  <질문>                          예/아니오       → 종료코드 0/1
#   ui_input    <질문> [기본값] [예시]          한 줄 입력      → 입력값을 stdout
#   ui_spin     <안내문> <출력 파일> <명령>...  명령이 도는 동안 스피너 → 명령의 종료코드
#   ui_pause    [안내문]                        아무 키 대기
#
# gum(https://github.com/charmbracelet/gum)이 있으면 gum 으로 그리고,
# 없으면 경고와 OS 별 설치 방법을 한 번 보여준 뒤 순수 bash TUI 로 그린다.
# 새 머신에서는 gum 을 설치할 Homebrew 조차 없으므로 fallback 은 꼭 필요하다.
#
# 취소(esc, q, ctrl+c)하면 고르기 함수는 1 을 반환한다.
# 항목 이름에는 쉼표를 쓰지 않는다. (gum --selected 가 쉼표로 구분)
# 화면은 /dev/tty 에 그리므로 $(...) 로 결과를 받아도 된다.
#
# DOTFILES_NO_GUM=1 이면 gum 이 있어도 fallback 을 쓴다.

[[ -n "${_DOTFILES_UI_LOADED:-}" ]] && return 0
_DOTFILES_UI_LOADED=1

# Nord 팔레트 (themes/ 의 기본 테마와 맞춘다)
UI_ACCENT="#88C0D0"   # nord8  frost
UI_BORDER="#81A1C1"   # nord9
UI_MUTED="#616E88"    # nord3 밝은 쪽
UI_TEXT="#D8DEE9"     # nord4
UI_WARN="#EBCB8B"     # nord13

use_gum() { [[ "${DOTFILES_NO_GUM:-}" != "1" ]] && has gum; }

# --------------------------------------------------------------- gum 안내 --

# 현재 OS 이름: macos | linux | windows | unknown
ui_os() {
  case "$(uname -s)" in
    Darwin)                     printf 'macos\n' ;;
    Linux)                      printf 'linux\n' ;;
    MINGW*|MSYS*|CYGWIN*)       printf 'windows\n' ;;
    *)                          printf 'unknown\n' ;;
  esac
}

# OS(와 Linux 배포판의 패키지 매니저)에 맞는 gum 설치 명령을 출력한다.
gum_install_hint() {
  case "$(ui_os)" in
    macos)
      printf '  brew install gum\n' ;;
    linux)
      if has apt-get; then
        cat <<'EOF'
  # Debian / Ubuntu (Charm 공식 apt 저장소)
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    | sudo tee /etc/apt/sources.list.d/charm.list
  sudo apt update && sudo apt install gum
EOF
      elif has dnf || has yum; then
        cat <<'EOF'
  # Fedora / RHEL (Charm 공식 yum 저장소)
  echo '[charm]
  name=Charm
  baseurl=https://repo.charm.sh/yum/
  enabled=1
  gpgcheck=1
  gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
  sudo rpm --import https://repo.charm.sh/yum/gpg.key
  sudo dnf install gum
EOF
      elif has pacman; then
        printf '  sudo pacman -S gum          # Arch\n'
      elif has apk; then
        printf '  sudo apk add gum            # Alpine\n'
      else
        printf '  brew install gum            # Homebrew on Linux\n'
        printf '  go install github.com/charmbracelet/gum@latest\n'
      fi ;;
    windows)
      printf '  winget install charmbracelet.gum   # 또는\n'
      printf '  scoop install charm-gum\n'
      printf '  (설치 후 Git Bash 를 새로 열어야 PATH 에 잡힙니다)\n' ;;
    *)
      printf '  go install github.com/charmbracelet/gum@latest\n' ;;
  esac
  printf '\n  다른 방법: https://github.com/charmbracelet/gum#installation\n'
}

# gum 이 없으면 경고와 설치 방법을 보여준다.
# 하위 스크립트로 넘어가도 다시 뜨지 않도록 환경변수로 한 번만 표시한다.
ui_gum_notice() {
  use_gum && return 0
  [[ "${DOTFILES_NO_GUM:-}" == "1" ]] && return 0
  [[ -n "${DOTFILES_GUM_NOTICE_SHOWN:-}" ]] && return 0
  export DOTFILES_GUM_NOTICE_SHOWN=1

  {
    printf '\n %s⚠ Warning%s  gum 이 설치돼 있지 않습니다.\n' "$C_BOLD$C_YELLOW" "$C_RESET"
    printf '   %s기본 TUI 로 계속합니다. gum 을 설치하면 더 보기 좋은 화면으로 바뀝니다.%s\n\n' "$C_DIM" "$C_RESET"
    printf ' %s설치 방법 (%s)%s\n' "$C_BOLD" "$(ui_os)" "$C_RESET"
    gum_install_hint
    printf '\n'
  } >/dev/tty
  ui_pause "계속하려면 아무 키나 누르세요..."
}

# 하위 스크립트도 같은 색을 쓰도록 gum 기본 스타일을 환경변수로 내보낸다.
if use_gum; then
  export GUM_CHOOSE_CURSOR_FOREGROUND="$UI_ACCENT"
  export GUM_CHOOSE_SELECTED_FOREGROUND="$UI_ACCENT"
  export GUM_CHOOSE_HEADER_FOREGROUND="$UI_MUTED"
  export GUM_CHOOSE_ITEM_FOREGROUND="$UI_TEXT"
  export GUM_CONFIRM_PROMPT_FOREGROUND="$UI_TEXT"
  export GUM_CONFIRM_SELECTED_BACKGROUND="$UI_BORDER"
  export GUM_CONFIRM_SELECTED_FOREGROUND="#2E3440"
  export GUM_INPUT_HEADER_FOREGROUND="$UI_TEXT"
  export GUM_INPUT_PROMPT_FOREGROUND="$UI_ACCENT"
  export GUM_INPUT_CURSOR_FOREGROUND="$UI_ACCENT"
  export GUM_SPIN_SPINNER_FOREGROUND="$UI_ACCENT"
  export GUM_SPIN_TITLE_FOREGROUND="$UI_MUTED"
fi

# ------------------------------------------------------------------- 제목 --

ui_title() {
  local title="$1" sub="${2:-}"
  if use_gum; then
    gum style --border rounded --border-foreground "$UI_BORDER" \
      --padding "0 2" --margin "1 0 1 1" \
      "$(gum style --bold --foreground "$UI_ACCENT" "$title")" \
      ${sub:+"$(gum style --foreground "$UI_MUTED" "$sub")"} >/dev/tty
  else
    printf '\n %s %s %s' "$C_BOLD$C_REV" "$title" "$C_RESET" >/dev/tty
    [[ -n "$sub" ]] && printf '  %s%s%s' "$C_DIM" "$sub" "$C_RESET" >/dev/tty
    printf '\n\n' >/dev/tty
  fi
}

# ------------------------------------------------------------- 하나 고르기 --

ui_choose() {
  local header="$1"; shift
  if use_gum; then
    gum choose --header "$header" --cursor "▸ " "$@"
    return $?
  fi
  _ui_choose_fallback "$header" "$@"
}

_ui_choose_fallback() {
  local header="$1"; shift
  local items=("$@") n=$# cursor=0 i key rest

  printf '\033[?25l' >/dev/tty
  trap 'printf "\033[?25h" >/dev/tty' EXIT INT TERM
  _ui_draw_choose() {
    printf '  %s%s%s   %s↑/↓ 이동 · enter 선택 · q 취소%s\n' \
      "$C_DIM" "$header" "$C_RESET" "$C_DIM" "$C_RESET"
    for ((i = 0; i < n; i++)); do
      if ((i == cursor)); then
        printf '\033[2K %s▸ %s%s\n' "$C_CYAN$C_BOLD" "${items[$i]}" "$C_RESET"
      else
        printf '\033[2K   %s\n' "${items[$i]}"
      fi
    done
  }

  _ui_draw_choose >/dev/tty
  while :; do
    IFS= read -rsn1 key </dev/tty || { _ui_choose_end; return 1; }
    if [[ "$key" == $'\033' ]]; then
      IFS= read -rsn2 -t 1 rest </dev/tty
      key="$key${rest:-}"
    fi
    case "$key" in
      # 끝에서 반대쪽 끝으로 순환. ((cursor++)) 는 증가 전 값(0)을 결과로 돌려줘
      # && / || 체인에서 거짓으로 취급되므로 쓰지 않는다.
      $'\033[A'|k) cursor=$(( (cursor - 1 + n) % n )) ;;
      $'\033[B'|j) cursor=$(( (cursor + 1) % n )) ;;
      q|Q|$'\033') _ui_choose_end; return 1 ;;
      ''|$'\n'|$'\r') break ;;
    esac
    # 커서를 목록 시작(헤더 포함 n+1 줄 위)으로 올려 다시 그린다.
    printf '\033[%dA' $((n + 1)) >/dev/tty
    _ui_draw_choose >/dev/tty
  done
  _ui_choose_end
  printf '%s\n' "${items[$cursor]}"
}

_ui_choose_end() { printf '\033[?25h' >/dev/tty; trap - EXIT INT TERM; }

# ---------------------------------------------------------- 여러 개 고르기 --

ui_choose_multi() {
  local header="$1" preselected="$2"; shift 2
  if use_gum; then
    local sel
    sel="$(printf '%s' "$preselected" | paste -sd, -)"
    gum choose --no-limit --header "$header" --cursor "▸ " \
      --cursor-prefix "○ " --selected-prefix "● " --unselected-prefix "○ " \
      ${sel:+--selected="$sel"} "$@"
    return $?
  fi
  _ui_choose_multi_fallback "$header" "$preselected" "$@"
}

_ui_choose_multi_fallback() {
  local header="$1" preselected="$2"; shift 2
  local items=("$@") n=$# cursor=0 i key rest mark
  local flags=()

  for ((i = 0; i < n; i++)); do
    flags[$i]=0
    printf '%s\n' "$preselected" | grep -qxF "${items[$i]}" && flags[$i]=1
  done

  printf '\033[?25l' >/dev/tty
  trap 'printf "\033[?25h" >/dev/tty' EXIT INT TERM
  _ui_draw_multi() {
    printf '  %s%s%s\n' "$C_DIM" "$header" "$C_RESET"
    printf '  %s↑/↓ 이동 · space 선택 · a 전체 · n 해제 · enter 확인 · q 취소%s\n' "$C_DIM" "$C_RESET"
    for ((i = 0; i < n; i++)); do
      if [[ "${flags[$i]}" == "1" ]]; then mark="${C_GREEN}●${C_RESET}"; else mark="${C_DIM}○${C_RESET}"; fi
      if ((i == cursor)); then
        printf '\033[2K %s▸%s %s %s%s%s\n' "$C_CYAN" "$C_RESET" "$mark" "$C_BOLD" "${items[$i]}" "$C_RESET"
      else
        printf '\033[2K   %s %s\n' "$mark" "${items[$i]}"
      fi
    done
  }

  _ui_draw_multi >/dev/tty
  while :; do
    IFS= read -rsn1 key </dev/tty || { _ui_choose_end; return 1; }
    if [[ "$key" == $'\033' ]]; then
      IFS= read -rsn2 -t 1 rest </dev/tty
      key="$key${rest:-}"
    fi
    case "$key" in
      $'\033[A'|k) cursor=$(( (cursor - 1 + n) % n )) ;;
      $'\033[B'|j) cursor=$(( (cursor + 1) % n )) ;;
      ' '|x)       if [[ "${flags[$cursor]}" == "1" ]]; then flags[$cursor]=0; else flags[$cursor]=1; fi ;;
      a|A)         for ((i = 0; i < n; i++)); do flags[$i]=1; done ;;
      n|N)         for ((i = 0; i < n; i++)); do flags[$i]=0; done ;;
      q|Q|$'\033') _ui_choose_end; return 1 ;;
      ''|$'\n'|$'\r') break ;;
    esac
    printf '\033[%dA' $((n + 2)) >/dev/tty
    _ui_draw_multi >/dev/tty
  done
  _ui_choose_end
  for ((i = 0; i < n; i++)); do
    [[ "${flags[$i]}" == "1" ]] && printf '%s\n' "${items[$i]}"
  done
  return 0
}

# ------------------------------------------------------------- 확인 / 대기 --

ui_confirm() {
  local q="$1" ans
  if use_gum; then
    gum confirm --affirmative "예" --negative "아니오" "$q"
    return $?
  fi
  printf '  %s%s%s %s[y/N]%s ' "$C_BOLD" "$q" "$C_RESET" "$C_DIM" "$C_RESET" >/dev/tty
  IFS= read -r ans </dev/tty || return 1
  [[ "$ans" == [yY]* ]]
}

ui_pause() {
  local msg="${1:-아무 키나 누르면 계속합니다...}"
  if use_gum; then
    gum style --foreground "$UI_MUTED" --margin "1 0 0 2" "$msg" >/dev/tty
  else
    printf '\n  %s%s%s' "$C_DIM" "$msg" "$C_RESET" >/dev/tty
  fi
  IFS= read -rsn1 _ </dev/tty
  printf '\n' >/dev/tty
}

# ------------------------------------------------------------ 입력 / 스피너 --

# 기본값이 있으면 입력 칸에 미리 채워 둔다. 취소하면 1 을 반환한다.
ui_input() {
  local q="$1" def="${2:-}" hint="${3:-}" ans
  if use_gum; then
    gum input --header "$q" --prompt "▸ " --value "$def" --placeholder "$hint"
    return $?
  fi
  printf '  %s%s%s' "$C_BOLD" "$q" "$C_RESET" >/dev/tty
  [[ -n "$def" ]]  && printf ' %s[%s]%s' "$C_DIM" "$def" "$C_RESET" >/dev/tty
  [[ -z "$def" && -n "$hint" ]] && printf ' %s(예: %s)%s' "$C_DIM" "$hint" "$C_RESET" >/dev/tty
  printf ' ' >/dev/tty
  IFS= read -r ans </dev/tty || return 1
  printf '%s\n' "${ans:-$def}"
}

# 명령의 stdout/stderr 는 화면에 내지 않고 출력 파일에 담는다. 실패 원인은 호출한 쪽이 그 파일에서 읽는다.
# 명령은 별도 프로세스로 돌기 때문에 셸 함수는 넘길 수 없다.
ui_spin() {
  local title="$1" out="$2"; shift 2
  if use_gum && [[ -t 2 ]]; then
    gum spin --spinner dot --title "$title" -- bash -c '"$@" >"$0" 2>&1' "$out" "$@"
    return $?
  fi
  printf '    %s%s%s\n' "$C_DIM" "$title" "$C_RESET" >&2
  "$@" >"$out" 2>&1
}
