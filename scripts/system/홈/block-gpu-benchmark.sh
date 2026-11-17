#!/bin/bash
cmd=$(/usr/bin/jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

lower=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')

block=0
if printf '%s' "$lower" | /usr/bin/grep -Eq 'geekbench[^|;&]*[[:space:]]--(compute|gpu)([[:space:]=]|$)'; then
  block=1
elif printf '%s' "$lower" | /usr/bin/grep -Eq '(gfxbench|gputest|furmark|heaven|valley)[^|;&/]*\.app/contents/macos/'; then
  block=1
fi

FLAG="$HOME/.claude/allow-gpu-benchmark-once"
if [ "$block" = 1 ] && [ -f "$FLAG" ]; then
  rm -f "$FLAG"; exit 0
fi

if [ "$block" = 1 ]; then
  echo "차단됨: 이 해킨토시(Iris Xe + WhateverXe 0.8.0)에서 GPU 연산 벤치마크는 GPU 행 → WindowServer 멈춤을 일으킨다(2026-11-11 Geekbench 6 --compute Metal로 화면 전체 정지, 강제 종료). CPU 벤치마크(geekbench6 --cpu)만 실행할 것. 사용자가 위험을 알고 명시적으로 요청한 경우에만 사용자가 직접 실행하도록 안내." >&2
  exit 2
fi
exit 0
