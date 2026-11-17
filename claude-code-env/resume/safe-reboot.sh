#!/bin/bash
self="$1"
[ -z "$self" ] && { echo "거부: 세션 ID 필요"; exit 1; }
idle=$(( $(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF; exit}') / 1000000000 ))
if [ "$idle" -lt 600 ]; then echo "거부: 사용자 입력 ${idle}초 전 (10분 미만)"; exit 1; fi
busy=$(find ~/.claude/projects -name '*.jsonl' -mmin -5 ! -name "${self}.jsonl" ! -path '*/subagents/*' 2>/dev/null)
if [ -n "$busy" ]; then echo "거부: 다른 세션 작업 중:"; echo "$busy"; exit 1; fi
echo "통과: 재부팅"
sudo -n shutdown -r +0
