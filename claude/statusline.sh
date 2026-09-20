#!/usr/bin/env bash
# Reads Claude Code's status line JSON from stdin.

input=$(cat)

# --- Parse fields ---
model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
cwd=$(echo "$input" | jq -r '.cwd // ""')
dir="${cwd/#$HOME/\~}"
ctx_window_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
used_percentage=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
cur_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
cur_cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')
cur_cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
total_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# --- ANSI colors ---
green="\033[32m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

# --- Git branch + staged/modified counts ---
git_branch=""
git_file_str=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2> /dev/null || git -C "$cwd" rev-parse --short HEAD 2> /dev/null)
  staged=$(git -C "$cwd" diff --cached --numstat 2> /dev/null | wc -l | tr -d ' ')
  modified=$(git -C "$cwd" diff --numstat 2> /dev/null | wc -l | tr -d ' ')
  [ "$staged" -gt 0 ] && git_file_str="${git_file_str}${green}+${staged}${reset}"
  [ "$modified" -gt 0 ] && git_file_str="${git_file_str}${yellow}~${modified}${reset}"
fi

# --- Session lines added/removed: shown as (+N -N), hidden if both 0 ---
session_lines_str=""
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
  inner=""
  [ "$lines_added" -gt 0 ] && inner="${inner}${green}+${lines_added}${reset}"
  [ "$lines_removed" -gt 0 ] && inner="${inner}${red}-${lines_removed}${reset}"
  session_lines_str="(${inner})"
fi

# --- Autocompact-relative context percentage ---
# autocompact threshold = context_window_size - 33000
# used_tokens: prefer current_usage sum, fallback to used_percentage * window_size / 100
autocompact_pct=$(awk \
  -v win="$ctx_window_size" \
  -v buf=33000 \
  -v ci="${cur_input:-}" \
  -v cc="${cur_cache_create:-}" \
  -v cr="${cur_cache_read:-}" \
  -v up="$used_percentage" \
  'BEGIN {
        threshold = win - buf
        if (threshold <= 0) threshold = 1
        if (ci != "") {
            used = ci + cc + cr
        } else {
            used = up * win / 100
        }
        pct = int(used / threshold * 100)
        if (pct > 100) pct = 100
        print pct
    }')

# --- Context color based on autocompact_pct ---
if [ "$autocompact_pct" -ge 90 ]; then
  ctx_color="$red"
elif [ "$autocompact_pct" -ge 60 ]; then
  ctx_color="$yellow"
else
  ctx_color="$green"
fi

# --- Cost ---
cost=$(awk -v c="$cost_usd" 'BEGIN { printf "%.4f", c }')

# --- Total elapsed time from cost.total_duration_ms ---
elapsed=$(awk -v ms="$total_duration_ms" 'BEGIN {
    s = int(ms / 1000)
    printf "%d:%02d", int(s / 60), s % 60
}')

# --- API duration: shown as (🏃‍➡️M:SS), hidden if 0 ---
api_str=""
if [ "$api_duration_ms" -gt 0 ]; then
  api_elapsed=$(awk -v ms="$api_duration_ms" 'BEGIN {
        s = int(ms / 1000)
        printf "%d:%02d", int(s / 60), s % 60
    }')
  api_str="(🏃‍➡️${api_elapsed})"
fi

# --- Rate limits (5h / 7d) from native stdin JSON ---
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

five_h_str=""
seven_d_str=""

limit_color() {
  local val=$1
  local int_val=${val%.*}
  if [ "$int_val" -ge 90 ] 2> /dev/null; then
    echo "$red"
  elif [ "$int_val" -ge 80 ] 2> /dev/null; then
    echo "$yellow"
  else echo "$green"; fi
}

# GNU date takes -d @epoch; BSD date takes -r epoch.
if date --version > /dev/null 2>&1; then
  epoch_fmt() { TZ=Asia/Tokyo date -d "@$1" "+$2"; }
else
  epoch_fmt() { TZ=Asia/Tokyo date -r "$1" "+$2"; }
fi

if [ -n "$five_h" ]; then
  fc=$(limit_color "$five_h")
  five_h_int=${five_h%.*}
  five_h_str="${fc}${five_h_int}%${reset}"
  if [ -n "$five_h_reset" ]; then
    fr=$(epoch_fmt "$five_h_reset" "%H:%M" 2> /dev/null)
    [ -n "$fr" ] && five_h_str="${five_h_str}@${fr}"
  fi
fi
if [ -n "$seven_d" ]; then
  sc=$(limit_color "$seven_d")
  seven_d_int=${seven_d%.*}
  seven_d_str="${sc}${seven_d_int}%${reset}"
  if [ -n "$seven_d_reset" ]; then
    # %-m is a GNU extension; strip the zeros in the shell instead.
    IFS=/ read -r mo dy tm <<< "$(epoch_fmt "$seven_d_reset" "%m/%d/%H:%M" 2> /dev/null)"
    [ -n "$tm" ] && seven_d_str="${seven_d_str}@${mo#0}/${dy#0} $tm"
  fi
fi

# --- Line 1: [model] | 📦 37%* | 🕰️ 27:52(🏃‍➡️7:00) ---
printf "[${model}] | 📦 %b%d%%*%b | 🕰️ %s%s\n" \
  "$ctx_color" "$autocompact_pct" "$reset" \
  "$elapsed" "$api_str"

# --- Line 2: 📁 ~/path | 🌿 branch +7~15(+157 -49) ---
line2="📁 ${dir}"
if [ -n "$git_branch" ]; then
  branch_part="🌿 ${git_branch}"
  if [ -n "$git_file_str" ] && [ -n "$session_lines_str" ]; then
    printf "%b\n" "${line2} | ${branch_part} ${git_file_str}${session_lines_str}"
  elif [ -n "$git_file_str" ]; then
    printf "%b\n" "${line2} | ${branch_part} ${git_file_str}"
  elif [ -n "$session_lines_str" ]; then
    printf "%b\n" "${line2} | ${branch_part} ${session_lines_str}"
  else
    printf "%s\n" "${line2} | ${branch_part}"
  fi
else
  printf "%s\n" "$line2"
fi

# --- Line 3: 💰 $0.0042 | 5h 12%@15:00 | 7d 35%@3/15 15:00 ---
line3=$(printf "💰 \$%s" "$cost")
[ -n "$five_h_str" ] && line3=$(printf "%b | 5h %b" "$line3" "$five_h_str")
[ -n "$seven_d_str" ] && line3=$(printf "%b | 7d %b" "$line3" "$seven_d_str")
printf "%b\n" "$line3"
