#!/usr/bin/env bash
#
# scripts/ 공용 헬퍼. 다른 스크립트가 source 해서 쓴다. 단독 실행하지 않는다.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
#
# 제공: DOTFILES_DIR, 색상(C_*), 출력 함수(step/info/ok/skip/warn/fail/die),
#       has, run(DRY_RUN 존중)
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

# 스크립트 상단 주석(2번째 줄부터 지정한 줄까지)을 도움말로 출력한다.
# usage_from <파일> <마지막 줄>
usage_from() { sed -n "2,${2}p" "$1" | sed 's/^#\{0,1\} \{0,1\}//'; }
