#!/usr/bin/env bash
#
# macOS 초기 세팅 인스톨러 (TUI)
#
#   bash setup/macos/install.sh                 # 체크리스트에서 골라 설치
#   bash setup/macos/install.sh --all           # 전체 항목을 질문 없이 설치
#   bash setup/macos/install.sh --only brew,node
#   bash setup/macos/install.sh --dry-run       # 실제 변경 없이 실행 내용만 출력
#   bash setup/macos/install.sh --list          # 설치 항목과 현재 상태만 확인
#
# 모든 항목은 여러 번 실행해도 안전(idempotent)합니다.
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않습니다.

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_SUFFIX="bak.$(date +%Y%m%d%H%M%S)"
BREW_PREFIX=""

ASSUME_YES=false
DRY_RUN=false
LIST_ONLY=false
ONLY_KEYS=""

# ---------------------------------------------------------------- 출력 헬퍼 --

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_REV=$'\033[7m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_REV=""
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

step()  { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
skip()  { printf '    %s-%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
warn()  { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail()  { printf '    %s✗%s %s\n' "$C_RED" "$C_RESET" "$*"; }
die()   { printf '\n%s오류:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

# --dry-run 이면 명령을 출력만 하고 실행하지 않는다.
run() {
  if $DRY_RUN; then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# 원격 설치 스크립트를 내려받아 실행한다.
# run() 에 넘기면 명령 치환이 먼저 평가돼 dry-run 에서도 네트워크를 타므로 따로 둔다.
run_remote_script() {
  local url="$1" desc="$2" shell="${3:-bash}"
  if $DRY_RUN; then
    printf '    %s[dry-run]%s %s ← %s\n' "$C_DIM" "$C_RESET" "$desc" "$url"
    return 0
  fi
  local script
  script="$(curl -fsSL "$url")" || return 1
  shift 3 2>/dev/null || shift $#
  "$shell" -c "$script" "$@"
}

# ------------------------------------------------------------- 설치 항목 정의 --

# key|라벨|설명   (위에서부터 순서대로 설치되므로 의존 관계 순으로 나열한다)
ITEMS=(
  "xcode|Xcode Command Line Tools|git, 컴파일러 등 기본 개발 도구"
  "homebrew|Homebrew|패키지 매니저 (아래 대부분의 항목이 의존)"
  "brewfile|Brewfile 패키지|ripgrep, fzf, bat 등 CLI 도구 모음"
  "ghostty|Ghostty|GPU 가속 터미널 에뮬레이터"
  "ohmyzsh|Oh My Zsh|zsh 프레임워크 (플러그인, 테마)"
  "node|Node.js (fnm)|fnm 버전 매니저 + 최신 LTS"
  "claude|Claude Code|Anthropic 공식 CLI"
  "codex|Codex|OpenAI CLI (npm, Node.js 필요)"
  "herdr|Herdr|herdr.dev 설치 스크립트"
  "antigravity|Antigravity|Google Antigravity CLI"
  "sdkman|SDKMAN|JVM 툴체인 매니저"
  "dotfiles|dotfiles 링크|이 저장소의 설정 파일을 홈에 심볼릭 링크"
  "shell|기본 셸을 zsh 로|chsh 로 로그인 셸 변경"
  "macos|macOS 기본 설정|키 반복 속도, Finder, Dock, 스크린샷 위치"
)

ITEM_KEYS=()
ITEM_LABELS=()
ITEM_DESCS=()
SELECTED=()

parse_items() {
  local entry key label desc
  for entry in "${ITEMS[@]}"; do
    key="${entry%%|*}"
    entry="${entry#*|}"
    label="${entry%%|*}"
    desc="${entry#*|}"
    ITEM_KEYS+=("$key")
    ITEM_LABELS+=("$label")
    ITEM_DESCS+=("$desc")
  done
}

# 이미 설치돼 있으면 0. 매번 확인하는 항목(설정 적용 등)은 1을 반환한다.
item_installed() {
  case "$1" in
    xcode)       xcode-select -p >/dev/null 2>&1 ;;
    homebrew)    has brew ;;
    ghostty)     [[ -d "/Applications/Ghostty.app" ]] ;;
    ohmyzsh)     [[ -d "$HOME/.oh-my-zsh" ]] ;;
    node)        has fnm ;;
    claude)      has claude ;;
    codex)       has codex ;;
    herdr)       has herdr ;;
    antigravity) has antigravity ;;
    sdkman)      [[ -d "$HOME/.sdkman" ]] ;;
    *)           return 1 ;;
  esac
}

# 기본 선택값: 아직 설치되지 않은 항목만 켠다.
init_selection() {
  local i
  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
    if item_installed "${ITEM_KEYS[$i]}"; then
      SELECTED[$i]=0
    else
      SELECTED[$i]=1
    fi
  done
}

select_only_keys() {
  local i key wanted found=false
  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do SELECTED[$i]=0; done
  for wanted in $(printf '%s' "$1" | tr ',' ' '); do
    found=false
    for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
      key="${ITEM_KEYS[$i]}"
      if [[ "$key" == "$wanted" ]]; then
        SELECTED[$i]=1
        found=true
      fi
    done
    $found || die "알 수 없는 항목: $wanted (--list 로 확인하세요)"
  done
}

# -------------------------------------------------------------------- TUI --

tui_restore() { printf '\033[?25h\033[?1049l'; }

tui_render() {
  local cursor="$1" i mark label state line
  printf '\033[H\033[2J'
  printf '%s macOS 초기 세팅 %s\n\n' "$C_BOLD$C_REV" "$C_RESET"
  printf '  %s↑/↓%s 이동   %s space%s 선택   %s a%s 전체   %s n%s 해제   %s enter%s 설치   %s q%s 취소\n\n' \
    "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" \
    "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"

  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
    if [[ "${SELECTED[$i]}" == "1" ]]; then
      mark="${C_GREEN}[x]${C_RESET}"
    else
      mark="[ ]"
    fi

    state=""
    item_installed "${ITEM_KEYS[$i]}" && state=" ${C_DIM}(이미 설치됨)${C_RESET}"

    label="${ITEM_LABELS[$i]}"
    if ((i == cursor)); then
      line=$(printf ' %s▸%s %s %s%s%s%s' "$C_CYAN" "$C_RESET" "$mark" "$C_BOLD" "$label" "$C_RESET" "$state")
    else
      line=$(printf '   %s %s%s' "$mark" "$label" "$state")
    fi
    printf '%s\n' "$line"
  done

  printf '\n  %s%s%s\n' "$C_DIM" "${ITEM_DESCS[$cursor]}" "$C_RESET"
}

tui_select() {
  local cursor=0 n=${#ITEM_KEYS[@]} key rest i

  printf '\033[?1049h\033[?25l'
  trap 'tui_restore' EXIT INT TERM

  while :; do
    tui_render "$cursor"

    IFS= read -rsn1 key </dev/tty || { tui_restore; trap - EXIT INT TERM; return 1; }

    # 방향키는 ESC [ A 형태의 3바이트 시퀀스로 들어온다.
    if [[ "$key" == $'\033' ]]; then
      IFS= read -rsn2 rest </dev/tty
      key="$key$rest"
    fi

    case "$key" in
      $'\033[A'|k) ((cursor > 0)) && ((cursor--)) || cursor=$((n - 1)) ;;
      $'\033[B'|j) ((cursor < n - 1)) && ((cursor++)) || cursor=0 ;;
      ' ')
        if [[ "${SELECTED[$cursor]}" == "1" ]]; then
          SELECTED[$cursor]=0
        else
          SELECTED[$cursor]=1
        fi ;;
      a|A) for ((i = 0; i < n; i++)); do SELECTED[$i]=1; done ;;
      n|N) for ((i = 0; i < n; i++)); do SELECTED[$i]=0; done ;;
      q|Q) tui_restore; trap - EXIT INT TERM; return 1 ;;
      # Enter 는 터미널 설정에 따라 빈 문자열/\n/\r 중 하나로 들어온다.
      ''|$'\n'|$'\r') break ;;
    esac
  done

  tui_restore
  trap - EXIT INT TERM
  return 0
}

# ------------------------------------------------------------- 심볼릭 링크 --

# link <레포 안 경로> <설치될 경로>
# 원본이 없으면 건너뛰고, 기존 파일이 있으면 백업한 뒤 링크한다.
link() {
  local src="$DOTFILES_DIR/$1" dst="$2"

  if [[ ! -e "$src" ]]; then
    skip "$1 ${C_DIM}(레포에 아직 파일 없음)${C_RESET}"
    return 0
  fi

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    skip "$dst ${C_DIM}(이미 연결됨)${C_RESET}"
    return 0
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    warn "기존 파일 백업: $dst -> $dst.$BACKUP_SUFFIX"
    run mv "$dst" "$dst.$BACKUP_SUFFIX"
  fi

  run mkdir -p "$(dirname "$dst")"
  run ln -s "$src" "$dst"
  ok "$dst -> $src"
}

# zsh 설정 파일에 한 줄을 중복 없이 추가한다.
append_once() {
  local file="$1" line="$2" marker="$3"

  if [[ -f "$file" ]] && grep -qF "$marker" "$file"; then
    skip "$(basename "$file") 에 이미 등록됨: $marker"
    return 0
  fi

  if $DRY_RUN; then
    printf '    %s[dry-run]%s %s 에 추가: %s\n' "$C_DIM" "$C_RESET" "$(basename "$file")" "$line"
  else
    printf '\n%s\n' "$line" >>"$file"
  fi
  ok "$(basename "$file") 에 추가: $line"
}

# ------------------------------------------------------------------ 설치 함수 --

install_xcode() {
  if xcode-select -p >/dev/null 2>&1; then
    skip "이미 설치됨"
    return 0
  fi

  info "설치 창이 뜨면 완료될 때까지 기다려 주세요."
  run xcode-select --install || true
  $DRY_RUN && return 0

  until xcode-select -p >/dev/null 2>&1; do
    sleep 10
  done
  ok "설치 완료"
}

# brew 를 현재 셸 PATH 에 올린다. 성공하면 BREW_PREFIX 를 채운다.
load_brew_env() {
  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      eval "$("$candidate" shellenv)"
      BREW_PREFIX="$candidate"
      return 0
    fi
  done
  has brew && { BREW_PREFIX="$(command -v brew)"; return 0; }
  return 1
}

install_homebrew() {
  if has brew; then
    skip "이미 설치됨 ($(brew --prefix))"
  else
    run_remote_script \
      "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" \
      "Homebrew 설치 스크립트 실행" || return 1
    ok "설치 완료"
  fi

  # Apple Silicon 은 /opt/homebrew, Intel 은 /usr/local 에 설치된다.
  if load_brew_env; then
    append_once "$HOME/.zprofile" "eval \"\$($BREW_PREFIX shellenv)\"" "$BREW_PREFIX shellenv"
  elif ! $DRY_RUN; then
    warn "brew 실행 파일을 찾지 못했습니다."
    return 1
  fi
}

require_brew() {
  has brew && return 0
  load_brew_env && return 0
  $DRY_RUN && return 0
  warn "brew 가 없어 건너뜁니다. Homebrew 항목을 먼저 설치하세요."
  return 1
}

install_brewfile() {
  require_brew || return 1

  local brewfile="$DOTFILES_DIR/setup/macos/Brewfile"
  [[ -f "$brewfile" ]] || { warn "Brewfile 없음: $brewfile"; return 1; }

  info "Brewfile: $brewfile"
  run brew update
  run brew bundle --file "$brewfile" || return 1
  ok "Brewfile 패키지 설치 완료"
}

install_ghostty() {
  if [[ -d "/Applications/Ghostty.app" ]]; then
    skip "이미 설치됨"
    return 0
  fi
  require_brew || return 1
  run brew install --cask ghostty || return 1
  ok "설치 완료"
}

install_ohmyzsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    skip "이미 설치됨"
    return 0
  fi

  # --unattended: 설치 후 zsh 로 전환하거나 chsh 를 실행하지 않는다.
  # (셸 변경은 'shell' 항목에서 따로 처리한다.)
  run_remote_script \
    "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" \
    "Oh My Zsh 설치 스크립트 실행" \
    sh "" --unattended || return 1
  ok "설치 완료"

  if [[ -f "$DOTFILES_DIR/shell/.zshrc" ]]; then
    warn "Oh My Zsh 가 만든 ~/.zshrc 는 dotfiles 링크 단계에서 백업 후 교체됩니다."
  fi
}

install_node() {
  if has fnm; then
    skip "fnm 이미 설치됨"
  else
    require_brew || return 1
    run brew install fnm || return 1
    ok "fnm 설치 완료"
  fi

  append_once "$HOME/.zshrc" 'eval "$(fnm env --use-on-cd --shell zsh)"' "fnm env"

  if $DRY_RUN; then
    printf '    %s[dry-run]%s fnm install --lts && fnm default lts-latest\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  eval "$(fnm env --shell bash)" 2>/dev/null || true
  fnm install --lts || return 1
  fnm default lts-latest || true
  ok "Node.js $(node --version 2>/dev/null || echo LTS) 설치 완료"
}

install_claude() {
  if has claude; then
    skip "이미 설치됨"
    return 0
  fi
  run_remote_script "https://claude.ai/install.sh" "Claude Code 설치 스크립트 실행" || return 1
  ok "설치 완료"
}

install_codex() {
  if has codex; then
    skip "이미 설치됨"
    return 0
  fi

  if ! has npm; then
    # fnm 을 방금 설치했다면 현재 셸에 아직 반영되지 않았을 수 있다.
    has fnm && eval "$(fnm env --shell bash)" 2>/dev/null || true
  fi
  if ! has npm && ! $DRY_RUN; then
    warn "npm 이 없어 건너뜁니다. Node.js 항목을 먼저 설치하세요."
    return 1
  fi

  run npm install -g @openai/codex || return 1
  ok "설치 완료"
}

install_herdr() {
  if has herdr; then
    skip "이미 설치됨"
    return 0
  fi
  run_remote_script "https://herdr.dev/install.sh" "Herdr 설치 스크립트 실행" sh || return 1
  ok "설치 완료"
}

install_antigravity() {
  if has antigravity; then
    skip "이미 설치됨"
    return 0
  fi
  run_remote_script "https://antigravity.google/cli/install.sh" "Antigravity 설치 스크립트 실행" || return 1
  ok "설치 완료"
}

install_sdkman() {
  if [[ -d "$HOME/.sdkman" ]]; then
    skip "이미 설치됨"
    return 0
  fi
  run_remote_script "https://get.sdkman.io" "SDKMAN 설치 스크립트 실행" || return 1
  ok "설치 완료 (새 셸에서 'sdk version' 으로 확인)"
}

install_dotfiles() {
  local app_support="$HOME/Library/Application Support"

  link "git/.gitconfig"          "$HOME/.gitconfig"
  link "git/.gitignore_global"   "$HOME/.gitignore_global"
  link "shell/.zshrc"            "$HOME/.zshrc"
  link "shell/.zprofile"         "$HOME/.zprofile"
  link "shell/aliases.zsh"       "$HOME/.config/zsh/aliases.zsh"
  link "ghostty/config"          "$HOME/.config/ghostty/config"
  link "cursor/settings.json"    "$app_support/Cursor/User/settings.json"
  link "cursor/keybindings.json" "$app_support/Cursor/User/keybindings.json"
  link "vscode/settings.json"    "$app_support/Code/User/settings.json"
  link "vscode/keybindings.json" "$app_support/Code/User/keybindings.json"

  local editor list ext
  for editor in code cursor; do
    if [[ "$editor" == "code" ]]; then
      list="$DOTFILES_DIR/vscode/extensions.txt"
    else
      list="$DOTFILES_DIR/cursor/extensions.txt"
    fi

    [[ -f "$list" ]] || { skip "$editor ${C_DIM}(extensions.txt 없음)${C_RESET}"; continue; }
    if ! has "$editor"; then
      warn "$editor CLI 없음. 에디터에서 'Shell Command: Install ... command' 를 먼저 실행하세요."
      continue
    fi

    while read -r ext; do
      [[ -n "$ext" && "$ext" != \#* ]] || continue
      run "$editor" --install-extension "$ext" --force
    done <"$list"
    ok "$editor 확장 설치 완료"
  done
}

install_shell() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  [[ -n "$zsh_path" ]] || { warn "zsh 를 찾을 수 없습니다."; return 1; }

  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    skip "기본 셸이 이미 $zsh_path"
    return 0
  fi

  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    info "/etc/shells 에 등록이 필요합니다 (sudo 비밀번호를 물어봅니다)."
    if $DRY_RUN; then
      printf '    %s[dry-run]%s echo %s | sudo tee -a /etc/shells\n' "$C_DIM" "$C_RESET" "$zsh_path"
    else
      printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null || return 1
    fi
  fi

  run chsh -s "$zsh_path" || return 1
  ok "기본 셸을 $zsh_path 로 변경 (새 터미널부터 적용)"
}

install_macos() {
  info "키 반복 속도, Finder, Dock 설정을 변경합니다."

  # 키 반복을 빠르게 (Vim 등에서 체감이 큼)
  run defaults write NSGlobalDomain KeyRepeat -int 2
  run defaults write NSGlobalDomain InitialKeyRepeat -int 15
  # 키를 길게 누를 때 악센트 팝업 대신 키 반복
  run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

  # Finder: 확장자/경로 표시, 숨김 파일 표시
  run defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  run defaults write com.apple.finder AppleShowAllFiles -bool true
  run defaults write com.apple.finder ShowPathbar -bool true
  run defaults write com.apple.finder ShowStatusBar -bool true
  run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

  # Dock 자동 숨김 + 표시 지연 제거, 최근 사용한 앱 영역 끄기
  run defaults write com.apple.dock autohide -bool true
  run defaults write com.apple.dock autohide-delay -float 0
  run defaults write com.apple.dock show-recents -bool false

  # 스크린샷을 ~/Screenshots 에 저장
  run mkdir -p "$HOME/Screenshots"
  run defaults write com.apple.screencapture location "$HOME/Screenshots"

  run killall Finder || true
  run killall Dock || true
  run killall SystemUIServer || true

  ok "적용 완료 (일부는 재로그인 후 반영)"
  warn "되돌리려면 'defaults delete <domain> <key>' 를 사용하세요."
}

install_item() {
  case "$1" in
    xcode)       install_xcode ;;
    homebrew)    install_homebrew ;;
    brewfile)    install_brewfile ;;
    ghostty)     install_ghostty ;;
    ohmyzsh)     install_ohmyzsh ;;
    node)        install_node ;;
    claude)      install_claude ;;
    codex)       install_codex ;;
    herdr)       install_herdr ;;
    antigravity) install_antigravity ;;
    sdkman)      install_sdkman ;;
    dotfiles)    install_dotfiles ;;
    shell)       install_shell ;;
    macos)       install_macos ;;
    *)           fail "알 수 없는 항목: $1"; return 1 ;;
  esac
}

# -------------------------------------------------------------------- main --

print_list() {
  local i mark
  printf '%s설치 항목%s\n\n' "$C_BOLD" "$C_RESET"
  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
    if item_installed "${ITEM_KEYS[$i]}"; then
      mark="${C_GREEN}✓${C_RESET}"
    else
      mark="${C_DIM}·${C_RESET}"
    fi
    # 한글은 printf 고정폭이 바이트 기준이라 정렬이 깨진다. ASCII 인 key 만 고정폭으로 둔다.
    printf '  %s %-12s %s\n' "$mark" "${ITEM_KEYS[$i]}" "${ITEM_LABELS[$i]}"
  done
  printf '\n  %s✓%s = 이미 설치됨\n' "$C_GREEN" "$C_RESET"
  printf '  --only 로 항목을 직접 지정할 수 있습니다. 예) --only homebrew,node,claude\n\n'
}

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^#\{0,1\} \{0,1\}//'; }

main() {
  while (($#)); do
    case "$1" in
      -a|--all)     ASSUME_YES=true ;;
      -n|--dry-run) DRY_RUN=true ;;
      -l|--list)    LIST_ONLY=true ;;
      -o|--only)    shift; ONLY_KEYS="${1:-}"; [[ -n "$ONLY_KEYS" ]] || die "--only 에 항목이 필요합니다." ;;
      --only=*)     ONLY_KEYS="${1#*=}" ;;
      -h|--help)    usage; exit 0 ;;
      *)            die "알 수 없는 옵션: $1" ;;
    esac
    shift
  done

  [[ "$(uname -s)" == "Darwin" ]] || die "이 스크립트는 macOS 전용입니다. (현재: $(uname -s))"

  parse_items

  $LIST_ONLY && { print_list; exit 0; }

  if [[ -n "$ONLY_KEYS" ]]; then
    select_only_keys "$ONLY_KEYS"
  elif $ASSUME_YES; then
    local i
    for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do SELECTED[$i]=1; done
  else
    init_selection
    # TUI 는 /dev/tty 를 직접 읽는다. 파일이 있어도 열리지 않는 환경이 있어 열기까지 확인한다.
    if [[ -t 1 ]] && (exec 3</dev/tty) 2>/dev/null; then
      tui_select || { printf '\n취소했습니다.\n'; exit 0; }
    else
      die "대화형 터미널이 아닙니다. --all 또는 --only 를 사용하세요."
    fi
  fi

  local i count=0
  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
    [[ "${SELECTED[$i]}" == "1" ]] && ((count++))
  done
  ((count > 0)) || { printf '\n선택한 항목이 없습니다.\n'; exit 0; }

  printf '\n%s%d개 항목을 설치합니다.%s\n' "$C_BOLD" "$count" "$C_RESET"
  info "dotfiles: $DOTFILES_DIR"
  $DRY_RUN && warn "dry-run 모드: 실제로 아무것도 변경하지 않습니다."

  local done_list="" fail_list="" n=0
  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
    [[ "${SELECTED[$i]}" == "1" ]] || continue
    ((n++))
    step "[$n/$count] ${ITEM_LABELS[$i]}"
    if install_item "${ITEM_KEYS[$i]}"; then
      done_list="$done_list ${ITEM_KEYS[$i]}"
    else
      fail "실패: ${ITEM_LABELS[$i]}"
      fail_list="$fail_list ${ITEM_KEYS[$i]}"
    fi
  done

  step "요약"
  [[ -n "$done_list" ]] && ok "완료:$done_list"
  if [[ -n "$fail_list" ]]; then
    fail "실패:$fail_list"
    warn "실패한 항목만 다시 시도: --only $(printf '%s' "${fail_list# }" | tr ' ' ',')"
  fi

  printf '\n%s세팅 완료!%s 새 터미널을 열어 확인하세요.\n\n' "$C_BOLD$C_GREEN" "$C_RESET"
  [[ -z "$fail_list" ]]
}

main "$@"
