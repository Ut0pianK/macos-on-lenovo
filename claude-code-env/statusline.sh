#!/bin/bash
D=~/.claude/usage; in=$(cat)
rl=$(printf '%s' "$in" | jq -c --argjson now "$(date +%s)" 'select(.rate_limits != null and .rate_limits != {}) | {rate_limits, model: (.model.display_name // ""), at: $now}' 2>/dev/null)
[ -n "$rl" ] && printf '%s' "$rl" > "$D/limits.json.tmp" && mv "$D/limits.json.tmp" "$D/limits.json"
fmt() { jq -r --arg k "$1" '.rate_limits[$k] // empty | "\(.used_percentage|floor)% (\(.resets_at|strflocaltime("%m/%d %H:%M")))"' "$D/limits.json" 2>/dev/null; }
h=$(fmt five_hour); w=$(fmt seven_day)
m=$(printf '%s' "$in" | jq -r '.model.display_name // empty')
printf '%s │ 5시간 %s │ 주간 %s\n' "${m:-Claude}" "${h:-–}" "${w:-–}"
