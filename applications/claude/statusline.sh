#!/bin/bash
# Claude Code statusLine — Nerd Font 아이콘 기반 한 줄 상태바
# 표시: 디렉터리 · git 브랜치 · 모델 · 컨텍스트 바 · 세션 시간 · (사용 한도)
# 폰트: JetBrainsMono Nerd Font (bash scripts/dotfiles.sh font 로 설치)

input=$(cat)

# jq 한 번 호출로 필요한 값을 모두 추출 (탭 구분)
IFS=$'\t' read -r cwd model used_pct dur_ms five_h seven_d < <(
  echo "$input" | jq -r '[
    (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    (.context_window.used_percentage // ""),
    (.cost.total_duration_ms // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // "")
  ] | map(tostring) | join("\t")'
)

# Nerd Font 아이콘 (UTF-8 바이트; bash 3.2 호환을 위해 \u 대신 \x 사용)
I_DIR=$'\xef\x81\xbb'     # nf-fa-folder
I_GIT=$'\xee\x82\xa0'     # nf-pl-branch
I_MODEL=$'\xef\x84\xa1'   # nf-fa-code
I_CTX=$'\xef\x87\x80'     # nf-fa-database
I_TIME=$'\xef\x80\x97'    # nf-fa-clock_o
I_RATE=$'\xef\x83\xa4'    # nf-fa-tachometer

# 색상 (256color)
R=$'\033[0m'; DIM=$'\033[38;5;242m'
C_DIR=$'\033[38;5;75m'
C_OK=$'\033[38;5;114m'; C_WARN=$'\033[38;5;179m'; C_BAD=$'\033[38;5;203m'
C_MODEL=$'\033[38;5;141m'
C_TIME=$'\033[38;5;109m'

SEP=" ${DIM}│${R} "

# 퍼센트에 따라 초록 → 노랑 → 빨강
level_color() {
  local p=${1%.*}
  if   [ "${p:-0}" -ge 85 ]; then printf '%s' "$C_BAD"
  elif [ "${p:-0}" -ge 60 ]; then printf '%s' "$C_WARN"
  else printf '%s' "$C_OK"; fi
}

# 디렉터리: $HOME → ~, 마지막 두 단계만 표시
dir="${cwd/#$HOME/~}"; [ -z "$dir" ] && dir="~"
if [ "$(echo "$dir" | tr -cd '/' | wc -c)" -gt 2 ]; then
  dir="…/$(echo "$dir" | awk -F/ '{print $(NF-1)"/"$NF}')"
fi
out="${C_DIR}${I_DIR} ${dir}${R}"

# git 브랜치 + 변경 여부 (락 경합 방지)
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | head -1)" ]; then
      out+="${SEP}${C_WARN}${I_GIT} ${branch} ●${R}"
    else
      out+="${SEP}${C_OK}${I_GIT} ${branch}${R}"
    fi
  fi
fi

[ -n "$model" ] && out+="${SEP}${C_MODEL}${I_MODEL} ${model}${R}"

# 컨텍스트 사용량 바 (10칸)
if [ -n "$used_pct" ]; then
  pct=$(printf '%.0f' "$used_pct")
  filled=$(( pct / 10 )); [ "$filled" -gt 10 ] && filled=10
  col=$(level_color "$pct")
  # 채워진 칸은 level 색, 빈 칸은 DIM
  full=$(printf '━%.0s' $(seq 1 "$filled" 2>/dev/null))
  [ "$filled" -eq 0 ] && full=""
  empty=""; [ "$filled" -lt 10 ] && empty=$(printf '━%.0s' $(seq 1 $((10 - filled))))
  out+="${SEP}${col}${I_CTX} ${full}${DIM}${empty} ${col}${pct}%${R}"
fi

# 세션 시간 (1h 05m / 12m / 30s)
if [ -n "$dur_ms" ]; then
  s=$(( ${dur_ms%.*} / 1000 ))
  if   [ "$s" -ge 3600 ]; then t=$(printf '%dh %02dm' $((s/3600)) $((s%3600/60)))
  elif [ "$s" -ge 60 ];   then t="$((s/60))m"
  else t="${s}s"; fi
  out+="${SEP}${C_TIME}${I_TIME} ${t}${R}"
fi

# 사용 한도 (있을 때만)
rate=""
[ -n "$five_h" ]  && rate="5h $(printf '%.0f' "$five_h")%"
[ -n "$seven_d" ] && rate+="${rate:+ }7d $(printf '%.0f' "$seven_d")%"
[ -n "$rate" ] && out+="${SEP}${DIM}${I_RATE} ${rate}${R}"

printf '%s' "$out"
