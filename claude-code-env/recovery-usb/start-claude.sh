#!/bin/sh

D="$(cd "$(dirname "$0")" && pwd)"
BIN="$D/claude"
BASE=https://downloads.claude.ai/claude-code-releases
PLATFORM=darwin-x64
TEAM=Q6L2SF6YDW

H=/private/var/tmp/claude-home
if ! mkdir -p "$H/.claude" 2>/dev/null || ! touch "$H/.w" 2>/dev/null; then
  H="$D/home"
  mkdir -p "$H/.claude"
  echo "주의: RAM 디스크에 쓸 수 없어 USB($H)에 로그인 정보를 저장합니다."
  echo "      복구가 끝나면 이 폴더를 지우세요:  rm -rf \"$H\""
fi
rm -f "$H/.w"
export HOME="$H"
cp "$D/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
mkdir -p "$D/logs"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TERM=xterm-256color
export DISABLE_AUTOUPDATER=1

if ! curl -sS -m 8 -o /dev/null https://api.anthropic.com 2>/dev/null; then
  echo "인터넷에 연결되지 않았습니다. 화면 오른쪽 위 Wi-Fi 메뉴에서 먼저 연결하세요."
  exit 1
fi

signed_ok() {
  /usr/bin/codesign -v -R="anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\"" "$1" 2>/dev/null
}

cur=$("$BIN" --version 2>/dev/null | cut -d' ' -f1)
latest=$(curl -fsS -m 15 "$BASE/latest" 2>/dev/null)
case "$latest" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) latest="" ;;
esac
if [ -n "$latest" ] && [ "$latest" != "$cur" ]; then
  echo "Claude Code 업데이트: ${cur:-없음} → $latest (약 360MB 받는 중)"
  size=$(curl -fsS -m 15 "$BASE/$latest/manifest.json" 2>/dev/null | tr -d ' \n' \
         | grep -o "\"$PLATFORM\":{[^}]*}" | grep -o '"size":[0-9]*' | cut -d: -f2)
  NEW="$D/claude.new"
  rm -f "$NEW"
  if curl -f -# -o "$NEW" "$BASE/$latest/$PLATFORM/claude" \
     && [ -n "$size" ] && [ "$(stat -f %z "$NEW")" = "$size" ] \
     && chmod +x "$NEW" && signed_ok "$NEW" \
     && [ "$("$NEW" --version 2>/dev/null | cut -d' ' -f1)" = "$latest" ]; then
    mv -f "$NEW" "$BIN"
    echo "업데이트 완료: $latest"
    echo "$(date '+%F %T') updated $cur -> $latest" >> "$D/logs/update.log"
  else
    rm -f "$NEW"
    echo "업데이트 실패(크기·서명·버전 확인 불통과). 기존 ${cur:-?} 로 실행합니다."
    echo "$(date '+%F %T') update to $latest FAILED" >> "$D/logs/update.log"
  fi
fi

if ! signed_ok "$BIN"; then
  echo "USB의 claude 파일 서명이 올바르지 않아 실행하지 않습니다: $BIN" >&2
  exit 1
fi

cd "$D"
exec "$BIN" "$@"
