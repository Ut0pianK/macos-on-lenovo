#!/bin/bash

input=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)

shorten() {
  python3 -I -c 'import sys; s=" ".join(sys.argv[1].split()); n=int(sys.argv[2]); print(s if len(s)<=n else s[:n-1]+"…")' "$1" "$2"
}

title="" last_prompt=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  title=$(tail -n 400 "$transcript" | jq -r 'select(.type=="ai-title" or .type=="custom-title") | (.customTitle // .aiTitle // empty)' 2>/dev/null | tail -n 1)
  last_prompt=$(tail -n 400 "$transcript" | jq -r 'select(.type=="last-prompt") | .lastPrompt // empty' 2>/dev/null | tail -n 1)
fi
[ -z "$title" ] && title=$(basename "${cwd:-$PWD}")

sound="Glass"
case "$event" in
  Stop)
    task=${last_prompt:-$title}
    head="✅ 작업 완료"
    body="'$(shorten "$task" 70)' 작업이 완료되었습니다"
    ;;
  PreToolUse)
    q=$(jq -r '.tool_input.questions[0].question // empty' <<<"$input" 2>/dev/null)
    head="❓ 질문이 있습니다"
    body=$(shorten "${q:-응답이 필요합니다}" 120)
    sound="Ping"
    ;;
  Notification)
    ntype=$(jq -r '.notification_type // empty' <<<"$input" 2>/dev/null)
    msg=$(jq -r '.message // empty' <<<"$input" 2>/dev/null)
    if [ "$ntype" = "idle_prompt" ] || [[ "$msg" == *"waiting for your input"* ]]; then
      exit 0
    fi
    head="🔔 확인이 필요합니다"
    body=$(shorten "${msg:-Claude Code 가 입력을 기다립니다}" 120)
    sound="Ping"
    ;;
  *) exit 0 ;;
esac

app="$HOME/Applications/Claude Code Notifier.app"
queue="$HOME/.claude/hooks/notify-queue"
subtitle=$(shorten "$title" 60)
if [ -d "$app" ]; then
  mkdir -p "$queue"
  tmp="$queue/.$$.$RANDOM"
  printf '%s\n%s\n%s\n%s\n' "$head" "$subtitle" "$body" "$sound" > "$tmp" && mv "$tmp" "$queue/$(date +%s).$$.txt"
  open -g "$app" >/dev/null 2>&1
else
  osascript - "Claude Code · $head" "$subtitle" "$body" "$sound" >/dev/null 2>&1 <<'EOF'
on run argv
  display notification (item 3 of argv) with title (item 1 of argv) subtitle (item 2 of argv) sound name (item 4 of argv)
end run
EOF
fi
exit 0
