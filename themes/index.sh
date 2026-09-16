#!/usr/bin/env bash
#
# themes/README.md 의 인덱스 표를 디렉토리 구조에서 다시 생성한다.
#
#   bash themes/index.sh            # README.md 의 인덱스 구간을 갱신
#   bash themes/index.sh --stdout   # 갱신하지 않고 표만 출력
#   bash themes/index.sh --check    # 갱신이 필요한지만 확인 (종료코드 1이면 필요)
#
# 테마를 추가하거나 파일을 넣은 뒤 이 스크립트를 돌리면 README 의
# 보기/내려받기 링크가 자동으로 맞춰진다.
#
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않는다.

set -uo pipefail

THEMES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="$THEMES_DIR/README.md"

# 이 두 마커 사이만 교체한다. 나머지 문서는 손대지 않는다.
MARK_START="<!-- INDEX:START -->"
MARK_END="<!-- INDEX:END -->"

MODE="write"

die() { printf 'oops: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------- 저장소 정보 --

# git remote 에서 "USER/REPO" 를 뽑는다. SSH/HTTPS 두 형태를 모두 받는다.
repo_slug() {
  local url
  url="$(git -C "$THEMES_DIR" remote get-url origin 2>/dev/null)" || return 1
  [[ -n "$url" ]] || return 1
  url="${url%.git}"
  case "$url" in
    git@*:*)   printf '%s\n' "${url#*:}" ;;
    ssh://*)   url="${url#ssh://}"; url="${url#*@}"; printf '%s\n' "${url#*/}" ;;
    https://*) url="${url#https://}"; printf '%s\n' "${url#*/}" ;;
    *)         return 1 ;;
  esac
}

# 링크가 가리킬 브랜치. 원격 기본 브랜치를 우선하고, 없으면 현재 브랜치.
repo_branch() {
  local b
  b="$(git -C "$THEMES_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  b="${b#origin/}"
  [[ -z "$b" ]] && b="$(git -C "$THEMES_DIR" branch --show-current 2>/dev/null)"
  [[ -z "$b" ]] && b="main"
  printf '%s\n' "$b"
}

# ------------------------------------------------------------- 앱 이름 매핑 --

# 파일명으로 어느 앱 설정인지 정한다. README.md 등 인덱스에서 뺄 파일은 1 을 반환.
app_for_file() {
  case "$1" in
    README.md|.gitkeep)        return 1 ;;
    *.mxtcolors)               printf 'MobaXterm\n' ;;
    ghostty*)                  printf 'Ghostty\n' ;;
    vscode*)                   printf 'VS Code\n' ;;
    cursor*)                   printf 'Cursor\n' ;;
    alacritty*)                printf 'Alacritty\n' ;;
    wezterm*)                  printf 'WezTerm\n' ;;
    kitty*)                    printf 'kitty\n' ;;
    *.itermcolors)             printf 'iTerm2\n' ;;
    windows-terminal*)         printf 'Windows Terminal\n' ;;
    *.Xresources|*.xresources) printf 'X11\n' ;;
    *)                         printf '%s\n' "${1%.*}" ;;
  esac
}

# ------------------------------------------------------------------ 생성 --

# shields.io 배지 라벨용 이스케이프. '-' 는 '--', 공백은 '_' 로 바꾼다.
badge_label() {
  local t="$1"
  t="${t//-/--}"
  t="${t// /_}"
  printf '%s\n' "$t"
}

render_index() {
  local slug branch base_blob
  slug="$(repo_slug)" || die "git remote 'origin' 을 찾지 못했습니다."
  branch="$(repo_branch)"
  # raw 는 텍스트에 text/plain 을 붙여 브라우저가 표시만 한다.
  # blob 페이지에는 "Download raw file" 버튼이 있어 실제로 파일로 받힌다.
  base_blob="https://github.com/$slug/blob/$branch/themes"

  local theme_dir theme file name app count line badge any_theme=false

  for theme_dir in "$THEMES_DIR"/*/; do
    [[ -d "$theme_dir" ]] || continue
    theme="$(basename "$theme_dir")"
    any_theme=true

    printf '### %s\n\n' "$theme"

    # 배지 하나가 앱 하나의 다운로드 버튼이 된다.
    # GitHub 의 개행 처리에 상관없이 가로로 늘어서도록 한 줄에 모은다.
    count=0
    line=""
    for file in "$theme_dir"*; do
      [[ -f "$file" ]] || continue
      name="$(basename "$file")"
      app="$(app_for_file "$name")" || continue
      badge="$(printf '[![%s](https://img.shields.io/badge/%s-download-4C566A?style=for-the-badge)](%s/%s/%s)' \
        "$app" "$(badge_label "$app")" "$base_blob" "$theme" "$name")"
      if [[ -z "$line" ]]; then line="$badge"; else line="$line $badge"; fi
      count=$((count + 1))
    done

    if ((count == 0)); then
      printf '_아직 설정 파일이 없습니다._\n'
    else
      printf '%s\n' "$line"
    fi
    printf '\n'
  done

  $any_theme || printf '_아직 테마가 없습니다._\n'
}

# ------------------------------------------------------------------ 반영 --

splice_readme() {
  local body="$1" tmp
  [[ -f "$README" ]] || die "README.md 가 없습니다: $README"
  grep -qF "$MARK_START" "$README" || die "마커를 찾지 못했습니다: $MARK_START"
  grep -qF "$MARK_END"   "$README" || die "마커를 찾지 못했습니다: $MARK_END"

  tmp="$(mktemp)"
  # 시작 마커까지 출력 -> 새 본문 -> 끝 마커부터 출력
  awk -v s="$MARK_START" -v e="$MARK_END" -v body="$body" '
    index($0, s) { print; print ""; printf "%s\n\n", body; skip = 1; next }
    index($0, e) { skip = 0; print substr($0, index($0, e)); next }
    !skip        { print }
  ' "$README" >"$tmp" || { rm -f "$tmp"; die "README 생성 실패"; }
  printf '%s\n' "$tmp"
}

main() {
  while (($#)); do
    case "$1" in
      --stdout) MODE="stdout" ;;
      --check)  MODE="check" ;;
      -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^#\{0,1\} \{0,1\}//'; exit 0 ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
    shift
  done

  local body
  body="$(render_index)" || exit 1

  if [[ "$MODE" == "stdout" ]]; then
    printf '%s\n' "$body"
    exit 0
  fi

  local tmp
  tmp="$(splice_readme "$body")" || exit 1

  if [[ "$MODE" == "check" ]]; then
    if cmp -s "$tmp" "$README"; then
      rm -f "$tmp"; printf '인덱스가 최신입니다.\n'; exit 0
    fi
    rm -f "$tmp"; printf '인덱스 갱신이 필요합니다. bash themes/index.sh 를 실행하세요.\n'; exit 1
  fi

  if cmp -s "$tmp" "$README"; then
    rm -f "$tmp"; printf '변경 없음 (이미 최신)\n'; exit 0
  fi
  mv "$tmp" "$README"
  printf 'themes/README.md 인덱스를 갱신했습니다.\n'
}

main "$@"
