#!/usr/bin/env bash
#
# 테마 적용 — themes/<앱>/<테마>.<확장자> 를 각 앱에 적용한다.
#
#   bash scripts/lib/theme.sh                          # 테마와 앱을 골라서 적용 (TUI)
#   bash scripts/lib/theme.sh <테마>                   # 지원하는 모든 앱에 적용
#   bash scripts/lib/theme.sh <테마> --only cursor,ghostty
#   bash scripts/lib/theme.sh <테마> --dry-run         # 변경 없이 바뀔 내용만 출력
#   bash scripts/lib/theme.sh <테마> --force           # 실행 중인 앱도 적용 (Orca 등)
#   bash scripts/lib/theme.sh --list                   # 테마 x 앱 지원 현황
#
# 앱별 적용 방식은 themes/<앱>/app.conf 의 APPLY_METHOD 를 따른다.
#   link        테마 파일을 TARGET 에 심볼릭 링크
#   merge-json  jq 로 TARGET 의 JSON_PATH 에 병합 (순수 JSON 대상)
#   merge-jsonc 최상위 키를 한 줄씩 바꾸거나 추가 (주석 있는 settings.json 대상)
#   manual      자동 적용 불가. 안내만 출력
#
# macOS 기본 bash 3.2 에서 동작하도록 연관배열/mapfile 등은 쓰지 않는다.

set -uo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=ui.sh
source "$SCRIPTS_DIR/lib/ui.sh"

BACKUP_SUFFIX="bak.$(date +%Y%m%d%H%M%S)"
FORCE=false
ONLY_APPS=""

# ------------------------------------------------------------ 앱 / 테마 목록 --

# app.conf 가 있는 하위 디렉토리 = 앱
theme_apps() {
  local dir
  for dir in "$THEMES_DIR"/*/; do
    [[ -f "${dir}app.conf" ]] && basename "$dir"
  done
}

# app.conf 를 현재 셸에 읽는다. 이전 앱의 값이 남지 않도록 먼저 비운다.
load_app() {
  unset APP_NAME THEME_EXT PLATFORM APPLY_METHOD TARGET JSON_PATH NOTE \
        EXT_CLI THEME_EXTENSIONS PROCESS
  # shellcheck disable=SC1090
  source "$THEMES_DIR/$1/app.conf"
}

# 어느 앱이든 <테마>.<THEME_EXT> 가 있는 이름 = 테마
theme_names() {
  local app file name
  for app in $(theme_apps); do
    ( load_app "$app"
      for file in "$THEMES_DIR/$app/"*."$THEME_EXT"; do
        [[ -f "$file" ]] || continue
        name="$(basename "$file")"
        [[ "$name" == "app.conf" ]] && continue
        printf '%s\n' "${name%.*}"
      done )
  done | sort -u
}

# 현재 OS 가 app.conf 의 PLATFORM 에 들어 있는지
platform_ok() { [[ " ${PLATFORM:-} " == *" $(ui_os) "* ]]; }

# --------------------------------------------------------------- 적용 방식 --
# apply_* 는 0(적용 또는 이미 적용됨), 1(실패), 2(대상이 없어 건너뜀) 를 반환한다.

backup_file() {
  run cp -p "$1" "$1.$BACKUP_SUFFIX" && info "백업: $1.$BACKUP_SUFFIX"
}

# 내용을 TARGET 에 쓴다. TARGET 이 레포 파일로의 링크여도 링크를 유지한 채 내용만 바꾼다.
write_target() {
  local tmp="$1"
  if cmp -s "$tmp" "$TARGET"; then
    skip "이미 적용됨"
    return 0
  fi
  if $DRY_RUN; then
    diff -u "$TARGET" "$tmp" | sed -n '3,$p' | sed 's/^/      /'
    return 0
  fi
  cat "$tmp" >"$TARGET" || return 1
  ok "$TARGET"
}

apply_link() {
  local file="$1" cur=""
  [[ -L "$TARGET" ]] && cur="$(readlink "$TARGET")"

  if [[ "$cur" == "$file" ]]; then
    skip "이미 적용됨"
    return 0
  fi
  # 우리가 만든 테마 링크가 아닌 실제 파일이면 백업한다.
  if [[ -e "$TARGET" && "$cur" != "$THEMES_DIR/"* ]]; then
    warn "기존 파일 백업: $TARGET -> $TARGET.$BACKUP_SUFFIX"
    run mv "$TARGET" "$TARGET.$BACKUP_SUFFIX" || return 1
  fi
  run mkdir -p "$(dirname "$TARGET")"
  run ln -sfn "$file" "$TARGET" || return 1
  ok "$TARGET -> ${file#"$DOTFILES_DIR"/}"
}

apply_merge_json() {
  local file="$1" tmp rc
  has jq || { warn "jq 가 필요합니다. 설치: $(jq_install_hint)"; return 1; }
  [[ -f "$TARGET" ]] || { skip "대상 파일 없음 (앱을 한 번 실행한 뒤 다시 시도): $TARGET"; return 2; }

  tmp="$(mktemp)"
  jq --slurpfile t "$file" "${JSON_PATH:-.} |= (. + \$t[0])" "$TARGET" >"$tmp" \
    && jq -e . "$tmp" >/dev/null || { rm -f "$tmp"; warn "JSON 병합 실패: $TARGET"; return 1; }

  if ! cmp -s "$tmp" "$TARGET" && ! $DRY_RUN; then backup_file "$TARGET"; fi
  write_target "$tmp"; rc=$?
  rm -f "$tmp"
  return $rc
}

# jsonc_upsert <파일> <키> <JSON 값>
# 최상위 키 한 줄을 바꾸거나, 없으면 마지막 } 앞에 추가한다. 주석과 다른 줄은 그대로 둔다.
# 값이 한 줄짜리(문자열/숫자/불리언)인 평범한 settings.json 을 전제로 한다.
# 닫는 } 만 있는 줄이 없으면({} 한 줄 등) 아무것도 바꾸지 않고 2 를 반환한다.
jsonc_upsert() {
  local file="$1" tmp
  tmp="$(mktemp)"
  K="$2" V="$3" awk '
    { line[NR] = $0 }
    END {
      k = ENVIRON["K"]; v = ENVIRON["V"]; q = "\"" k "\""; found = 0
      for (i = 1; i <= NR; i++) {
        s = line[i]; sub(/^[ \t]+/, "", s)
        if (index(s, q) == 1 && substr(s, length(q) + 1) ~ /^[ \t]*:/) { found = i; break }
      }
      if (found) {
        match(line[found], /^[ \t]*/); indent = substr(line[found], 1, RLENGTH)
        comma = (line[found] ~ /,[ \t]*(\/\/.*)?$/) ? "," : ""
        line[found] = indent q ": " v comma
        for (i = 1; i <= NR; i++) print line[i]
        exit
      }
      # 없으면: 마지막 } 바로 앞에 넣고, 앞의 의미 있는 줄에 쉼표를 보장한다.
      for (last = NR; last > 0; last--) if (line[last] ~ /^[ \t]*}[ \t]*$/) break
      if (last == 0) exit 2
      for (p = last - 1; p > 0; p--) {
        t = line[p]; sub(/[ \t]+$/, "", t); u = t; sub(/^[ \t]+/, "", u)
        if (u != "" && u !~ /^\/\//) break
      }
      if (p > 0 && t !~ /[,{]$/) line[p] = t ","
      for (i = 1; i <= NR; i++) {
        if (i == last) print "  " q ": " v
        print line[i]
      }
    }' "$file" >"$tmp"
  local rc=$?
  if ((rc == 0)); then mv "$tmp" "$file"; else rm -f "$tmp"; fi
  return $rc
}

apply_merge_jsonc() {
  local file="$1" tmp key val rc
  has jq || { warn "jq 가 필요합니다. 설치: $(jq_install_hint)"; return 1; }
  [[ -f "$TARGET" ]] || { skip "대상 파일 없음 (앱 미설치?): $TARGET"; return 2; }

  tmp="$(mktemp)"
  cat "$TARGET" >"$tmp"
  while IFS=$'\t' read -r key val; do
    [[ -n "$key" ]] || continue
    jsonc_upsert "$tmp" "$key" "$val" && continue
    # 줄 단위로 못 넣는 모양({} 한 줄 등)은 주석이 없는 순수 JSON 일 때만 jq 로 병합한다.
    if jq -e . "$tmp" >/dev/null 2>&1; then
      jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$tmp" >"$tmp.jq" && mv "$tmp.jq" "$tmp"
    else
      rm -f "$tmp"; warn "settings.json 형식을 해석하지 못했습니다: $TARGET"; return 1
    fi
  done < <(jq -r 'to_entries[] | [.key, (.value | tojson)] | @tsv' "$file")

  write_target "$tmp"; rc=$?
  rm -f "$tmp"
  return $rc
}

# THEME_EXTENSIONS 에서 이 테마의 확장을 찾아 설치한다.
install_theme_extension() {
  local theme="$1" pair ext=""
  for pair in ${THEME_EXTENSIONS:-}; do
    [[ "${pair%%=*}" == "$theme" ]] && ext="${pair#*=}"
  done
  [[ -n "$ext" && -n "${EXT_CLI:-}" ]] || return 0

  if ! has "$EXT_CLI"; then
    warn "$EXT_CLI CLI 가 없어 확장($ext)을 설치하지 못했습니다. 에디터에서 직접 설치하세요."
    return 0
  fi
  if "$EXT_CLI" --list-extensions 2>/dev/null | grep -qix "$ext"; then
    skip "확장 $ext ${C_DIM}(이미 설치됨)${C_RESET}"
    return 0
  fi
  if $DRY_RUN; then
    run "$EXT_CLI" --install-extension "$ext"
    return 0
  fi
  "$EXT_CLI" --install-extension "$ext" >/dev/null 2>&1 && ok "확장 설치: $ext" \
    || warn "확장 설치 실패: $ext"
}

# ---------------------------------------------------------------- 앱 하나 --

# 결과를 RESULT 에 담는다: applied | skipped | manual | failed
apply_app() {
  local app="$1" theme="$2" file
  load_app "$app"
  step "${APP_NAME:-$app}  ${C_DIM}(${APPLY_METHOD})${C_RESET}"
  RESULT="skipped"

  file="$THEMES_DIR/$app/$theme.$THEME_EXT"
  if [[ ! -f "$file" ]]; then
    skip "이 앱용 $theme 테마 파일이 아직 없습니다."
    return 0
  fi
  if ! platform_ok; then
    skip "이 OS($(ui_os))에서는 적용할 수 없습니다. (지원: $PLATFORM)"
    return 0
  fi
  if [[ -n "${PROCESS:-}" ]] && pgrep -f "$PROCESS" >/dev/null 2>&1 && ! $FORCE; then
    warn "${APP_NAME} 가 실행 중이라 건너뜁니다. 실행 중에는 앱이 설정 파일을 덮어씁니다."
    info "앱을 완전히 종료한 뒤: bash scripts/dotfiles.sh theme $theme --only $app"
    return 0
  fi

  local rc
  case "$APPLY_METHOD" in
    link)        apply_link "$file" ;;
    merge-json)  apply_merge_json "$file" ;;
    merge-jsonc) apply_merge_jsonc "$file" ;;
    manual)
      info "자동 적용을 지원하지 않습니다."
      info "파일: ${file#"$DOTFILES_DIR"/}"
      info "대상: $TARGET"
      [[ -n "${NOTE:-}" ]] && info "$NOTE"
      RESULT="manual"
      return 0 ;;
    *) warn "알 수 없는 APPLY_METHOD: $APPLY_METHOD"; false ;;
  esac
  rc=$?
  ((rc == 2)) && return 0
  ((rc == 0)) || { RESULT="failed"; return 1; }

  install_theme_extension "$theme"
  [[ -n "${NOTE:-}" ]] && info "${C_DIM}${NOTE}${C_RESET}"
  RESULT="applied"
}

# -------------------------------------------------------------------- 목록 --

print_list() {
  local theme app ext mark
  printf '%s테마 x 앱%s  %s(✓ 적용 가능 · ✋ 수동 · — 파일 없음 · ✗ 이 OS 미지원)%s\n\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  for theme in $(theme_names); do
    printf '  %s%-20s%s' "$C_BOLD" "$theme" "$C_RESET"
    for app in $(theme_apps); do
      load_app "$app"
      if [[ ! -f "$THEMES_DIR/$app/$theme.$THEME_EXT" ]]; then mark="—"
      elif ! platform_ok; then mark="✗"
      elif [[ "$APPLY_METHOD" == "manual" ]]; then mark="✋"
      else mark="✓"; fi
      printf '  %s %s' "$mark" "$app"
    done
    printf '\n'
  done
  printf '\n'
}

# -------------------------------------------------------------------- main --

usage() { usage_from "${BASH_SOURCE[0]}" 18; }

# 테마와 앱을 TUI 로 고른다. THEME, ONLY_APPS 를 채운다. 취소하면 1.
select_interactive() {
  local apps=() app pre="" picked
  ui_gum_notice
  ui_title "테마 적용" "themes/ 의 테마를 각 앱에 적용합니다"
  THEME="$(ui_choose "테마" $(theme_names))" || return 1

  for app in $(theme_apps); do
    load_app "$app"
    [[ -f "$THEMES_DIR/$app/$THEME.$THEME_EXT" ]] || continue
    apps+=("$app")
    # 자동 적용 가능한 앱만 기본 선택
    platform_ok && [[ "$APPLY_METHOD" != "manual" ]] && pre="$pre$app"$'\n'
  done
  ((${#apps[@]} > 0)) || { warn "$THEME 테마 파일이 있는 앱이 없습니다."; return 1; }

  picked="$(ui_choose_multi "적용할 앱" "$pre" "${apps[@]}")" || return 1
  [[ -n "$picked" ]] || return 1
  ONLY_APPS="$(printf '%s' "$picked" | paste -sd, -)"
  ui_confirm "$THEME 테마를 적용할까요? ($ONLY_APPS)"
}

main() {
  local list_only=false
  THEME=""
  while (($#)); do
    case "$1" in
      -l|--list)    list_only=true ;;
      -n|--dry-run) DRY_RUN=true ;;
      -f|--force)   FORCE=true ;;
      -o|--only)    shift; ONLY_APPS="${1:-}"; [[ -n "$ONLY_APPS" ]] || die "--only 에 앱이 필요합니다." ;;
      --only=*)     ONLY_APPS="${1#*=}" ;;
      -h|--help)    usage; exit 0 ;;
      -*)           die "알 수 없는 옵션: $1" ;;
      *)            THEME="$1" ;;
    esac
    shift
  done

  $list_only && { print_list; exit 0; }

  if [[ -z "$THEME" ]]; then
    if [[ -t 1 ]] && (exec 3</dev/tty) 2>/dev/null; then
      select_interactive || { printf '\n취소했습니다.\n'; exit 0; }
    else
      die "테마 이름이 필요합니다. 목록: $(theme_names | paste -sd' ' -)"
    fi
  fi

  theme_names | grep -qxF "$THEME" || die "없는 테마: $THEME (목록: $(theme_names | paste -sd' ' -))"

  local app wanted applied="" skipped="" manual="" failed=""
  for wanted in $(printf '%s' "$ONLY_APPS" | tr ',' ' '); do
    [[ -f "$THEMES_DIR/$wanted/app.conf" ]] || die "없는 앱: $wanted (목록: $(theme_apps | paste -sd' ' -))"
  done

  printf '\n%s%s%s 테마를 적용합니다.\n' "$C_BOLD" "$THEME" "$C_RESET"
  $DRY_RUN && warn "dry-run 모드: 실제로 아무것도 변경하지 않습니다."

  for app in $(theme_apps); do
    if [[ -n "$ONLY_APPS" ]] && [[ ",$ONLY_APPS," != *",$app,"* ]]; then continue; fi
    apply_app "$app" "$THEME"
    case "$RESULT" in
      applied) applied="$applied $app" ;;
      manual)  manual="$manual $app" ;;
      failed)  failed="$failed $app" ;;
      *)       skipped="$skipped $app" ;;
    esac
  done

  step "요약"
  if $DRY_RUN; then
    [[ -n "$applied" ]] && ok "적용 예정:$applied"
  else
    [[ -n "$applied" ]] && ok "적용:$applied"
  fi
  [[ -n "$manual" ]]  && warn "수동 적용 필요:$manual"
  [[ -n "$skipped" ]] && skip "건너뜀:$skipped"
  [[ -n "$failed" ]]  && fail "실패:$failed"
  printf '\n'
  [[ -z "$failed" ]]
}

main "$@"
