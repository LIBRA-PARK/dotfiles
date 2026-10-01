#!/usr/bin/env bash
#
# themes/README.md 의 인덱스 표를 디렉토리 구조에서 다시 생성한다.
#
#   bash scripts/lib/themes-index.sh            # README.md 의 인덱스 구간을 갱신
#   bash scripts/lib/themes-index.sh --stdout   # 갱신하지 않고 표만 출력
#   bash scripts/lib/themes-index.sh --check    # 갱신이 필요한지만 확인 (종료코드 1이면 필요)
#
# 구조: themes/<앱>/app.conf (적용 정보) + themes/<앱>/<테마>.<THEME_EXT>
# 앱이나 테마 파일을 추가한 뒤 이 스크립트를 돌리면 README 의
# 파일 링크가 자동으로 맞춰진다.
#
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않는다.

set -uo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

README="$THEMES_DIR/README.md"

# 이 두 마커 사이만 교체한다. 나머지 문서는 손대지 않는다.
MARK_START="<!-- INDEX:START -->"
MARK_END="<!-- INDEX:END -->"

MODE="write"

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

# ------------------------------------------------------------- 앱 메타데이터 --

# 앱 = app.conf 가 있는 하위 디렉토리. 디렉토리 이름 순으로 출력한다.
all_app_dirs() {
  local dir
  for dir in "$THEMES_DIR"/*/; do
    [[ -f "${dir}app.conf" ]] && basename "$dir"
  done
}

# app_field <앱 디렉토리> <변수명>
# app.conf 를 서브셸에서 source 해 값 하나를 꺼낸다. 현재 셸은 오염되지 않는다.
app_field() {
  ( # shellcheck disable=SC1090
    source "$THEMES_DIR/$1/app.conf" && eval "printf '%s\n' \"\${$2:-}\"" )
}

# 테마 = 어느 앱이든 <테마>.<THEME_EXT> 파일이 있는 이름. 중복 없이 정렬한다.
# 이 목록이 표의 열이 된다.
all_themes() {
  local app ext file name
  for app in $(all_app_dirs); do
    ext="$(app_field "$app" THEME_EXT)"
    for file in "$THEMES_DIR/$app/"*."$ext"; do
      [[ -f "$file" ]] || continue
      name="$(basename "$file")"
      # Ghostty 처럼 THEME_EXT 가 conf 인 앱은 app.conf 도 걸리므로 뺀다.
      # 따라서 "app" 은 테마 이름으로 쓸 수 없다.
      [[ "$name" == "app.conf" ]] && continue
      printf '%s\n' "${name%.*}"
    done
  done | sort -u
}

# ------------------------------------------------------------------ 생성 --

# 앱(행) x 테마(열) 행렬을 그린다.
# 빈 칸이 곧 "그 앱에 그 테마가 없다" 는 뜻이라 누락이 바로 보인다.
# 앱/테마 이름에는 공백을 쓰지 않는다 (아래 단어 분리에 의존).
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

  local apps themes app theme ext label method
  apps="$(all_app_dirs)"
  if [[ -z "$apps" ]]; then
    printf '_아직 앱이 없습니다._\n'
    return 0
  fi

  themes="$(all_themes)"
  if [[ -z "$themes" ]]; then
    printf '_아직 테마 파일이 없습니다._\n'
    return 0
  fi

  # 헤더
  printf '| 앱 | 적용 방식 |'
  for theme in $themes; do printf ' %s |' "$theme"; done
  printf '\n| --- | --- |'
  for theme in $themes; do printf ' :---: |'; done
  printf '\n'

  # 본문: 파일이 있으면 링크, 없으면 em dash
  for app in $apps; do
    label="$(app_field "$app" APP_NAME)"
    method="$(app_field "$app" APPLY_METHOD)"
    ext="$(app_field "$app" THEME_EXT)"
    printf '| [%s](%s/%s/app.conf) | `%s` |' "${label:-$app}" "$base_blob" "$app" "$method"
    for theme in $themes; do
      if [[ -f "$THEMES_DIR/$app/$theme.$ext" ]]; then
        printf ' [✓](%s/%s/%s.%s) |' "$base_blob" "$app" "$theme" "$ext"
      else
        printf ' — |'
      fi
    done
    printf '\n'
  done

  printf '\n앱 이름을 누르면 적용 정보(app.conf), ✓ 를 누르면 테마 파일로 이동합니다. — 는 아직 없는 조합입니다.\n'
}

# ------------------------------------------------------------------ 반영 --

splice_readme() {
  local body="$1" tmp
  [[ -f "$README" ]] || die "README.md 가 없습니다: $README"
  grep -qF "$MARK_START" "$README" || die "마커를 찾지 못했습니다: $MARK_START"
  grep -qF "$MARK_END"   "$README" || die "마커를 찾지 못했습니다: $MARK_END"

  tmp="$(mktemp)"
  # 시작 마커까지 출력 -> 새 본문 -> 끝 마커부터 출력
  # body 는 개행을 포함하므로 -v 대신 환경변수로 넘긴다. (macOS awk 는 -v 값의 개행을 거부한다)
  BODY="$body" awk -v s="$MARK_START" -v e="$MARK_END" '
    index($0, s) { print; print ""; printf "%s\n\n", ENVIRON["BODY"]; skip = 1; next }
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
      -h|--help) usage_from "${BASH_SOURCE[0]}" 13; exit 0 ;;
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
    rm -f "$tmp"; printf '인덱스 갱신이 필요합니다. bash scripts/lib/themes-index.sh 를 실행하세요.\n'; exit 1
  fi

  if cmp -s "$tmp" "$README"; then
    rm -f "$tmp"; printf '변경 없음 (이미 최신)\n'; exit 0
  fi
  mv "$tmp" "$README"
  printf 'themes/README.md 인덱스를 갱신했습니다.\n'
}

main "$@"
