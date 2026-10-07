#!/usr/bin/env bash
#
# scripts/ 공용 헬퍼. 다른 스크립트가 source 해서 쓴다. 단독 실행하지 않는다.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
#
# 제공: DOTFILES_DIR, 색상(C_*), 출력 함수(step/info/ok/skip/warn/fail/die),
#       has, run(DRY_RUN 존중), jq_install_hint, wsl_notice, app_config_dir
#
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않는다.

# 두 번 source 돼도 한 번만 초기화한다.
[[ -n "${_DOTFILES_COMMON_LOADED:-}" ]] && return 0
_DOTFILES_COMMON_LOADED=1

# 이 파일은 scripts/lib/ 에 있으므로 두 단계 위가 레포 루트다.
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS_DIR="$DOTFILES_DIR/applications"
ASSETS_DIR="$DOTFILES_DIR/assets"
THEMES_DIR="$DOTFILES_DIR/themes"
SCRIPTS_DIR="$DOTFILES_DIR/scripts"

DRY_RUN="${DRY_RUN:-false}"

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

# DRY_RUN=true 이면 명령을 출력만 하고 실행하지 않는다.
run() {
  if $DRY_RUN; then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# jq 가 없을 때 보여 줄 OS 별 설치 방법.
jq_install_hint() {
  case "$(uname -s)" in
    Darwin)               printf 'brew install jq\n' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'winget install jqlang.jq (설치 후 Git Bash 를 새로 여세요)\n' ;;
    *)                    printf '패키지 매니저로 jq 설치 (예: sudo apt install jq)\n' ;;
  esac
}

# WSL 안에서 Windows 드라이브(/mnt/c 등)에 있는 레포를 실행했는지.
# PowerShell / cmd 의 bash 는 Git Bash 가 아니라 WSL 이라, Windows 에서 그대로 치면 이 경우가 된다.
is_wsl_on_windows_drive() {
  [[ "$DOTFILES_DIR" == /mnt/[a-z]/* ]] || return 1
  [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

# 위 경우에는 Linux 로 동작해 Windows 가 아니라 WSL 홈에 적용된다. 모르고 지나가지 않게 한 번 알린다.
# 하위 스크립트로 넘어가도 다시 뜨지 않도록 환경변수로 한 번만 표시한다.
wsl_notice() {
  is_wsl_on_windows_drive || return 0
  [[ -n "${DOTFILES_WSL_NOTICE_SHOWN:-}" ]] && return 0
  export DOTFILES_WSL_NOTICE_SHOWN=1
  {
    warn "WSL 에서 실행 중입니다. Linux 로 동작하며 Windows 가 아니라 WSL 홈($HOME)에 적용됩니다."
    info "Windows 에 적용하려면 Git Bash 로 실행하세요. PowerShell / cmd 의 bash 는 WSL 입니다."
    info '  & "C:\Program Files\Git\bin\bash.exe" scripts/dotfiles.sh'
  } >&2
}
wsl_notice

# 앱 설정이 모이는 OS 별 루트 디렉토리.
#   macOS   ~/Library/Application Support
#   Windows %APPDATA% (Git Bash 경로로 변환. 예: /c/Users/<이름>/AppData/Roaming)
#   Linux   ${XDG_CONFIG_HOME:-~/.config}
# VS Code 계열 에디터는 이 아래 <앱>/User/ 에 settings.json 을 둔다.
app_config_dir() {
  case "$(uname -s)" in
    Darwin) printf '%s\n' "$HOME/Library/Application Support" ;;
    MINGW*|MSYS*|CYGWIN*)
      if [[ -n "${APPDATA:-}" ]] && has cygpath; then
        cygpath -u "$APPDATA"
      else
        printf '%s\n' "$HOME/AppData/Roaming"
      fi ;;
    *) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
  esac
}

# 스크립트 상단 주석(2번째 줄부터 지정한 줄까지)을 도움말로 출력한다.
# usage_from <파일> <마지막 줄>
usage_from() { sed -n "2,${2}p" "$1" | sed 's/^#\{0,1\} \{0,1\}//'; }
