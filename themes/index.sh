#!/usr/bin/env bash
#
# themes/README.md 의 인덱스 표를 디렉토리 구조에서 다시 생성한다.
#
#   bash themes/index.sh            # README.md 의 인덱스 구간을 갱신
#   bash themes/index.sh --stdout   # 갱신하지 않고 표만 출력
#   bash themes/index.sh --check    # 갱신이 필요한지만 확인 (종료코드 1이면 필요)
#
# 테마를 추가하거나 파일을 넣은 뒤 이 스크립트를 돌리면 README 의
# 파일 링크가 자동으로 맞춰진다.
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

# 모든 테마에서 발견된 앱 이름을 중복 없이 정렬해 출력한다.
# 이 목록이 표의 행이 된다.
all_apps() {
  local theme_dir file
  {
    for theme_dir in "$THEMES_DIR"/*/; do
      [[ -d "$theme_dir" ]] || continue
      for file in "$theme_dir"*; do
        [[ -f "$file" ]] || continue
        app_for_file "$(basename "$file")" || continue
      done
    done
  } | sort -u
}

# file_for_app <테마 디렉토리> <앱 이름>
# 해당 앱의 파일명을 출력한다. 없으면 1 을 반환한다.
file_for_app() {
  local theme_dir="$1" want="$2" file name app
  for file in "$theme_dir"*; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    app="$(app_for_file "$name")" || continue
    if [[ "$app" == "$want" ]]; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  return 1
}

# 앱(행) x 테마(열) 행렬을 그린다.
# 빈 칸이 곧 "그 앱에 그 테마가 없다" 는 뜻이라 누락이 바로 보인다.
# 테마 디렉토리 이름에는 공백을 쓰지 않는다 (아래 단어 분리에 의존).
render_index() {
  local slug branch base_blob
  slug="$(repo_slug)" || die "git remote 'origin' 을 찾지 못했습니다."
  branch="$(repo_branch)"
  # 파일 페이지(blob)로 보낸다. 내용을 바로 볼 수 있고, 필요하면
  # 그 페이지의 "Download raw file" 버튼으로 받을 수도 있다.
  #
  # raw 직링크는 쓰지 않는다. GitHub 은 텍스트 파일에 text/plain 을 붙이므로
  # 브라우저가 내려받지 않고 내용을 표시만 한다. (측정으로 확인)
  base_blob="https://github.com/$slug/blob/$branch/themes"

  local themes="" theme_dir theme apps app name

  for theme_dir in "$THEMES_DIR"/*/; do
    [[ -d "$theme_dir" ]] || continue
    themes="$themes $(basename "$theme_dir")"
  done
  themes="${themes# }"

  if [[ -z "$themes" ]]; then
    printf '_아직 테마가 없습니다._\n'
    return 0
  fi

  apps="$(all_apps)"
  if [[ -z "$apps" ]]; then
    printf '_아직 설정 파일이 없습니다._\n'
    return 0
  fi

  # 헤더
  printf '| 앱 |'
  for theme in $themes; do printf ' %s |' "$theme"; done
  printf '\n| --- |'
  for theme in $themes; do printf ' :---: |'; done
  printf '\n'

  # 본문: 파일이 있으면 링크, 없으면 em dash
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    printf '| %s |' "$app"
    for theme in $themes; do
      if name="$(file_for_app "$THEMES_DIR/$theme/" "$app")"; then
        printf ' [✓](%s/%s/%s) |' "$base_blob" "$theme" "$name"
      else
        printf ' — |'
      fi
    done
    printf '\n'
  done <<EOF
$apps
EOF

  printf '\n✓ 를 누르면 해당 파일로 이동합니다. — 는 아직 없는 조합입니다.\n'
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
