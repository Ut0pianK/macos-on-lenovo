#!/bin/bash
V=/usr/local/bin/alc-verb
w() { $V $1 SET_COEF_INDEX $2 >/dev/null 2>&1; $V $1 SET_PROC_COEF $3 >/dev/null 2>&1; }
A() { w 0x20 0x1b 0x0c2b; w 0x57 0x03 0x09a3; }
B() { w 0x20 0x1b 0x0c6b; w 0x57 0x03 0x8ea6; }
touch ~/.alc-verb-pause; sleep 3
if [ "${1:-}" = keepB ]; then B; echo "B 값으로 둠(감시 스크립트는 0x45 만 보므로 그대로 동작)"; rm -f ~/.alc-verb-pause; exit 0; fi
if [ "${1:-}" = A ]; then A; rm -f ~/.alc-verb-pause; echo "A 값으로 되돌림"; exit 0; fi
for i in 1 2 3 4; do
  A; echo "$(date +%T)  A (지금 값)"; say -v Yuna "에이" 2>/dev/null; sleep 7
  B; echo "$(date +%T)  B (Linux 값)"; say -v Yuna "비" 2>/dev/null; sleep 7
done
A; echo "끝 — A 로 되돌림"; rm -f ~/.alc-verb-pause
