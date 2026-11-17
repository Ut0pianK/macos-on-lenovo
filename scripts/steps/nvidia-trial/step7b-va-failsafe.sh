#!/bin/bash
set -u
T="$HOME/nvidia-trial"; MODE="${1:-check}"
LOG="$T/logs/step7b-va-failsafe-$(date +%Y%m%d-%H%M%S).log"; mkdir -p "$T/logs"
exec > >(tee -a "$LOG") 2>&1
echo "===== step7b-va-failsafe $(date) ($MODE) ====="
BD=/Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle
BIN=Contents/MacOS/AppleIntelTGLGraphicsVADriver; RES=Contents/_CodeSignature/CodeResources
ORIG_SHA=a972cdb7ddd56bcf38c3ab71e874b73efc34bc683d30e49f0a1a1919625a726d
V1_SHA=c41d90fb7b8dea645fdf9aff830a32d6b818ae218b5a3d7a03c97744402cc64f
BK="$T/backup-va-driver"
A_OFF=$((0x1336e1)); A_OLD=4881c2b02c0000488b4dd8488bb910090000488957088b45e44883c4305dc3
A_NEW=488bba100900008b45e44885ff740648894f08eb05b805000000c9c3909090
B_OFF=$((0x130e80)); B_OLD=488b45a08b88bc09000083c10089c989ca488bbcd010090000488b55f04889c6
B_NEW=488b45a08b88bc090000488bbcc8100900004885ff74c6488b55f04889c69090
put() { sudo cp "$1" "$2.new" && sudo chown root:wheel "$2.new" && sudo chmod "$3" "$2.new" && sudo mv -f "$2.new" "$2"; }
cur=$(shasum -a 256 "$BD/$BIN" | cut -d' ' -f1); echo "현재 설치본 sha256: $cur"
case "$cur" in "$ORIG_SHA") echo "  (원본)";; "$V1_SHA") echo "  (1차 패치본)";; *) echo "!! 알 수 없는 상태. 변경 없음."; exit 1;; esac
if [ ! -f "$BK/$BIN" ]; then
  [ "$cur" = "$ORIG_SHA" ] || { echo "!! 원본 백업이 없음. 중단."; exit 1; }
  mkdir -p "$BK" && cp -Rp "$BD/Contents" "$BK/" 2>/dev/null; echo "백업 생성: $BK"
fi
[ "$(shasum -a 256 "$BK/$BIN" | cut -d' ' -f1)" = "$ORIG_SHA" ] || { echo "!! 백업이 원본과 다름. 중단."; exit 1; }
W=$(mktemp -d /tmp/va-failsafe.XXXXXX); WB="$W/AppleIntelTGLGraphicsVADriver.bundle"; mkdir -p "$WB"
cp -Rp "$BK/Contents" "$WB/" 2>/dev/null; [ -f "$WB/$BIN" ] || { echo "!! 작업 사본 실패"; rm -rf "$W"; exit 1; }
python3 -I - "$WB/$BIN" $A_OFF $A_OLD $A_NEW $B_OFF $B_OLD $B_NEW <<'EOF' || { echo "!! 패치 실패. 변경 없음."; rm -rf "$W"; exit 1; }
import sys
p = sys.argv[1]; d = bytearray(open(p, 'rb').read()); n0 = len(d)
for off, old, new in ((sys.argv[2], sys.argv[3], sys.argv[4]), (sys.argv[5], sys.argv[6], sys.argv[7])):
    off = int(off); old = bytes.fromhex(old); new = bytes.fromhex(new)
    assert len(old) == len(new), "길이 다름"
    assert bytes(d[off:off+len(old)]) == old, "원본 바이트가 예상과 다름 @0x%x" % off
    d[off:off+len(new)] = new
assert len(d) == n0; open(p, 'wb').write(d)
EOF
echo "원본 대비 바뀐 바이트 수(서명 전): $(cmp -l "$BK/$BIN" "$WB/$BIN" | wc -l | tr -d ' ')"
codesign -f -s - --preserve-metadata=identifier,flags "$WB" 2>&1 | tail -1
codesign --verify "$WB" 2>&1 | tail -1; codesign --verify "$WB" 2>/dev/null || { echo "!! 서명 검증 실패. 변경 없음."; rm -rf "$W"; exit 1; }
echo "-- 패치본 디스어셈블 A (0x1336d6~)"
lldb -b -o "target create '$WB/$BIN'" -o "disassemble -s 0x1336d6 -c 15 -b" -o "disassemble -s 0x130e7b -c 10 -b" 2>&1 | grep '\[0x' | sed 's/^.*\[0x/  [0x/' | cut -c1-108
echo "패치본 sha256: $(shasum -a 256 "$WB/$BIN" | cut -d' ' -f1)"
if [ "$MODE" != apply ]; then echo "check 모드: 설치하지 않음."; rm -rf "$W"; echo "===== 끝. 로그: $LOG ====="; exit 0; fi
sudo -v || { rm -rf "$W"; exit 1; }
put "$WB/$BIN" "$BD/$BIN" 755 && put "$WB/$RES" "$BD/$RES" 644 || echo "!! 설치 실패"
rm -rf "$W"
codesign --verify --verbose=1 "$BD" 2>&1 | tail -1
echo "설치됨. sha256: $(shasum -a 256 "$BD/$BIN" | cut -d' ' -f1)"
echo "===== 끝. 로그: $LOG ====="
