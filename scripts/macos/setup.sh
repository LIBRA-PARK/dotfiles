#!/usr/bin/env bash
#
# macOS 초기 세팅 인스톨러 (TUI)
#
#   bash scripts/macos/setup.sh                 # 체크리스트에서 골라 설치
#   bash scripts/macos/setup.sh --all           # 전체 항목을 질문 없이 설치
#   bash scripts/macos/setup.sh --only brew,node
#   bash scripts/macos/setup.sh --dry-run       # 실제 변경 없이 실행 내용만 출력
#   bash scripts/macos/setup.sh --list          # 설치 항목과 현재 상태만 확인
#
# 모든 항목은 여러 번 실행해도 안전(idempotent)합니다.
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않습니다.

set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/ui.sh
source "$SCRIPTS_DIR/lib/ui.sh"

BACKUP_SUFFIX="bak.$(date +%Y%m%d%H%M%S)"
BREW_PREFIX=""

ASSUME_YES=false
LIST_ONLY=false
ONLY_KEYS=""

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
  "font|Fonts|JetBrainsMono + D2Coding (Nerd Font 아이콘 포함)"
  "dotfiles|dotfiles 링크|applications/ 의 설정 파일을 홈에 심볼릭 링크"
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
    font)        [[ -e "$HOME/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf" ]] ;;
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

# 체크리스트에 보일 한 줄. ui_choose_multi 는 쉼표를 구분자로 쓰므로 설명의 쉼표는 바꾼다.
item_display() {
  local i="$1" desc state=""
  desc="${ITEM_DESCS[$i]//, / · }"
  item_installed "${ITEM_KEYS[$i]}" && state="  [설치됨]"
  printf '%s — %s%s\n' "${ITEM_LABELS[$i]}" "$desc" "$state"
}

# 체크리스트에서 고른 결과를 SELECTED 에 반영한다. 취소하면 1 을 반환한다.
select_interactive() {
  local i displays=() preselected="" picked

  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
    displays[$i]="$(item_display "$i")"
    [[ "${SELECTED[$i]}" == "1" ]] && preselected="$preselected${displays[$i]}"$'\n'
  done

  ui_gum_notice
  printf '\033[H\033[2J' >/dev/tty
  ui_title "macOS 초기 세팅" "설치할 항목을 고르세요 · 설치된 항목은 기본 해제"
  picked="$(ui_choose_multi "설치 항목" "$preselected" "${displays[@]}")" || return 1

  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
    SELECTED[$i]=0
    printf '%s\n' "$picked" | grep -qxF "${displays[$i]}" && SELECTED[$i]=1
  done
  return 0
}

# ------------------------------------------------------------- 심볼릭 링크 --

# link <applications/ 안 경로> <설치될 경로>
# 원본이 없으면 건너뛰고, 기존 파일이 있으면 백업한 뒤 링크한다.
# 이 레포를 가리키던 옛 링크(경로 이동 등으로 깨진 것 포함)는 백업 없이 교체한다.
link() {
  local src="$APPS_DIR/$1" dst="$2" cur

  if [[ ! -e "$src" ]]; then
    skip "$1 ${C_DIM}(레포에 아직 파일 없음)${C_RESET}"
    return 0
  fi

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    skip "$dst ${C_DIM}(이미 연결됨)${C_RESET}"
    return 0
  fi

  cur=""
  [[ -L "$dst" ]] && cur="$(readlink "$dst")"

  if [[ "$cur" == "$DOTFILES_DIR/"* ]]; then
    info "옛 링크 교체: $dst ${C_DIM}(was ${cur#"$DOTFILES_DIR"/})${C_RESET}"
    run rm -f "$dst"
  elif [[ -e "$dst" || -L "$dst" ]]; then
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

  local brewfile="$APPS_DIR/homebrew/Brewfile"
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

  if [[ -f "$APPS_DIR/shell/.zshrc" ]]; then
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

# 폰트는 macOS/Linux 공용이라 scripts/lib/font.sh 에 로직을 두고 여기서는 위임만 한다.
install_font() {
  local script="$SCRIPTS_DIR/lib/font.sh"

  if [[ ! -f "$script" ]]; then
    warn "scripts/lib/font.sh 가 없습니다: $script"
    return 1
  fi

  # 하위 스크립트가 자체적으로 진행 상황을 출력한다.
  if $DRY_RUN; then
    bash "$script" --dry-run || return 1
  else
    bash "$script" || return 1
  fi
}

install_dotfiles() {
  local app_support="$HOME/Library/Application Support"

  link "git/.gitconfig"          "$HOME/.gitconfig"
  link "git/.gitignore_global"   "$HOME/.gitignore_global"
  link "shell/.zshrc"            "$HOME/.zshrc"
  link "shell/.zprofile"         "$HOME/.zprofile"
  link "shell/aliases.zsh"       "$HOME/.config/zsh/aliases.zsh"
  link "ghostty/config"          "$HOME/.config/ghostty/config"
  link "claude/statusline.sh"    "$HOME/.claude/statusline-command.sh"
  # keybindings 는 OS 마다 수식키가 달라(macOS cmd ↔ Windows ctrl) 파일을 따로 둔다.
  link "cursor/settings.json"          "$app_support/Cursor/User/settings.json"
  link "cursor/keybindings.macos.json" "$app_support/Cursor/User/keybindings.json"
  link "vscode/settings.json"          "$app_support/Code/User/settings.json"
  link "vscode/keybindings.macos.json" "$app_support/Code/User/keybindings.json"

  local editor list ext
  for editor in code cursor; do
    if [[ "$editor" == "code" ]]; then
      list="$APPS_DIR/vscode/extensions.txt"
    else
      list="$APPS_DIR/cursor/extensions.txt"
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
    font)        install_font ;;
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

usage() { usage_from "${BASH_SOURCE[0]}" 15; }

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
      select_interactive || { printf '\n취소했습니다.\n'; exit 0; }
    else
      die "대화형 터미널이 아닙니다. --all 또는 --only 를 사용하세요."
    fi
  fi

  local i count=0
  for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
    [[ "${SELECTED[$i]}" == "1" ]] && ((count++))
  done
  ((count > 0)) || { printf '\n선택한 항목이 없습니다.\n'; exit 0; }

  # 체크리스트로 골랐을 때만 한 번 더 확인한다. (--all / --only 는 바로 진행)
  if [[ -z "$ONLY_KEYS" ]] && ! $ASSUME_YES && ! $DRY_RUN; then
    ui_confirm "$count 개 항목을 설치할까요?" || { printf '\n취소했습니다.\n'; exit 0; }
  fi

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
