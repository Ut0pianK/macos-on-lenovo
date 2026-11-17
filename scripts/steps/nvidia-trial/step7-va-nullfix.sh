#!/bin/bash
set -u
T="$HOME/nvidia-trial"; MODE="${1:-check}"
LOG="$T/logs/step7-va-nullfix-$(date +%Y%m%d-%H%M%S).log"; mkdir -p "$T/logs"
exec > >(tee -a "$LOG") 2>&1
echo "===== step7-va-nullfix $(date) ($MODE) ====="
BD=/Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle
BIN=Contents/MacOS/AppleIntelTGLGraphicsVADriver; RES=Contents/_CodeSignature/CodeResources
ORIG_SHA=a972cdb7ddd56bcf38c3ab71e874b73efc34bc683d30e49f0a1a1919625a726d
OFF=$((0x1336e1))
OLD=4881c2b02c0000488b4dd8488bb91009000048895708
NEW=488bba100900004885ff740448894f08909090909090
BK="$T/backup-va-driver"
put() {
  sudo cp "$1" "$2.new" && sudo chown root:wheel "$2.new" && sudo chmod "$3" "$2.new" && sudo mv -f "$2.new" "$2"
}
if [ "$MODE" = undo ]; then
  [ -f "$BK/$BIN" ] && [ -f "$BK/$RES" ] || { echo "!! 백업 없음: $BK"; exit 1; }
  [ "$(shasum -a 256 "$BK/$BIN" | cut -d' ' -f1)" = "$ORIG_SHA" ] || { echo "!! 백업 파일이 원본과 다름. 중단."; exit 1; }
  sudo -v || exit 1
  put "$BK/$BIN" "$BD/$BIN" 755 && put "$BK/$RES" "$BD/$RES" 644
  codesign --verify --verbose=1 "$BD" 2>&1 | tail -1
  echo "복원됨. sha256: $(shasum -a 256 "$BD/$BIN" | cut -d' ' -f1)"; echo "===== 끝. 로그: $LOG ====="; exit 0
fi
cur=$(shasum -a 256 "$BD/$BIN" | cut -d' ' -f1); echo "현재 sha256: $cur"
[ "$cur" = "$ORIG_SHA" ] || { echo "!! 드라이버가 분석한 원본과 다름 (이미 패치됐거나 다른 버전). 변경 없음."; exit 1; }
got=$(xxd -s $OFF -l 22 -p "$BD/$BIN" | tr -d '\n'); echo "현재 바이트: $got"
[ "$got" = "$OLD" ] || { echo "!! 패치 위치의 바이트가 예상과 다름. 변경 없음."; exit 1; }
W=$(mktemp -d /tmp/va-nullfix.XXXXXX); cp -Rp "$BD" "$W/"; WB="$W/$(basename "$BD")"
python3 -I - "$WB/$BIN" $OFF "$NEW" <<'EOF' || { echo "!! 패치 실패"; rm -rf "$W"; exit 1; }
import sys
p, off, new = sys.argv[1], int(sys.argv[2]), bytes.fromhex(sys.argv[3])
d = bytearray(open(p, 'rb').read()); assert len(new) == 22
d[off:off+22] = new; open(p, 'wb').write(d)
EOF
echo "바뀐 바이트 수: $(cmp -l "$BD/$BIN" "$WB/$BIN" | wc -l | tr -d ' ') (22 이하여야 함), 크기 동일: $([ "$(stat -f%z "$BD/$BIN")" = "$(stat -f%z "$WB/$BIN")" ] && echo 예 || echo 아니오)"
codesign -f -s - --preserve-metadata=identifier,flags "$WB" 2>&1 | tail -1
codesign --verify --verbose=1 "$WB" 2>&1 | tail -2 || { echo "!! 서명 검증 실패"; rm -rf "$W"; exit 1; }
codesign --verify "$WB" 2>/dev/null || { echo "!! 서명 검증 실패. 변경 없음."; rm -rf "$W"; exit 1; }
echo "-- 패치본 디스어셈블 (0x1336c7~)"
lldb -b -o "target create '$WB/$BIN'" -o "disassemble -s 0x1336c7 -c 15 -b" 2>&1 | grep '\[0x' | sed 's/^.*\[0x/  [0x/' | cut -c1-110
echo "패치본 sha256: $(shasum -a 256 "$WB/$BIN" | cut -d' ' -f1)"
if [ "$MODE" != apply ]; then echo "check 모드: 설치하지 않음."; rm -rf "$W"; echo "===== 끝. 로그: $LOG ====="; exit 0; fi
if [ ! -f "$BK/$BIN" ]; then mkdir -p "$BK" && cp -Rp "$BD/Contents" "$BK/" && echo "백업: $BK ($(shasum -a 256 "$BK/$BIN" | cut -c1-16)…)"; fi
[ "$(shasum -a 256 "$BK/$BIN" | cut -d' ' -f1)" = "$ORIG_SHA" ] || { echo "!! 백업 확인 실패. 변경 없음."; rm -rf "$W"; exit 1; }
sudo -v || { rm -rf "$W"; exit 1; }
put "$WB/$BIN" "$BD/$BIN" 755 && put "$WB/$RES" "$BD/$RES" 644 || echo "!! 설치 실패 → bash step7-va-nullfix.sh undo"
rm -rf "$W"
codesign --verify --verbose=1 "$BD" 2>&1 | tail -1
echo "설치됨. sha256: $(shasum -a 256 "$BD/$BIN" | cut -d' ' -f1)"
echo "===== 끝. 로그: $LOG ====="
