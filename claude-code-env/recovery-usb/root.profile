# 레킨토시 복구 USB가 넣은 파일: Recovery 터미널에서 claude 만 입력하면 Claude Code 실행
claude() {
  for s in /Volumes/*/claude-recovery/start-claude.sh; do
    [ -f "$s" ] && { /bin/sh "$s" "$@"; return $?; }
  done
  # USB 데이터 파티션이 자동으로 안 붙었으면 붙여 보고 다시 찾는다
  /usr/sbin/diskutil mount RECOVERY >/dev/null 2>&1
  for s in /Volumes/*/claude-recovery/start-claude.sh; do
    [ -f "$s" ] && { /bin/sh "$s" "$@"; return $?; }
  done
  echo "복구 USB의 claude-recovery 폴더를 찾지 못했습니다. USB 연결을 확인하세요." >&2
  return 1
}
Claude() { claude "$@"; }
CLAUDE() { claude "$@"; }

echo "복구 도우미: Wi-Fi 연결 후 claude 를 입력하면 Claude Code가 실행됩니다."
