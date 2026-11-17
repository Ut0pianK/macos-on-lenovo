#!/bin/bash
set -u
T="$HOME/nvidia-trial"; MODE="${1:-check}"
LOG="$T/logs/step8-mtl-leakfix-$(date +%Y%m%d-%H%M%S).log"; mkdir -p "$T/logs"
exec > >(tee -a "$LOG") 2>&1
echo "===== step8-mtl-leakfix $(date) ($MODE) ====="
BD=/Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle
BIN=Contents/MacOS/AppleIntelTGLGraphicsMTLDriver; RES=Contents/_CodeSignature/CodeResources
ORIG_SHA=1e5e4f5bd76ff567a102125dfa3c74a255934d45c753a88aedcbfac7dab53c6c
OFF=$((0x7ed82)); OLD=41803c0600750de87afa0100; NEW=41803c06009090e87afa0100
BK="$T/backup-mtl-driver"
put() { sudo cp "$1" "$2.new" && sudo chown root:wheel "$2.new" && sudo chmod "$3" "$2.new" && sudo mv -f "$2.new" "$2"; }
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
W=$(mktemp -d /tmp/mtl-leakfix.XXXXXX); WB="$W/AppleIntelTGLGraphicsMTLDriver.bundle"; mkdir -p "$WB"
cp -Rp "$BD/Contents" "$WB/" 2>/dev/null; [ -f "$WB/$BIN" ] || { echo "!! 작업 사본 실패"; rm -rf "$W"; exit 1; }
python3 -I - "$WB/$BIN" $OFF $OLD $NEW <<'EOF' || { echo "!! 패치 실패. 변경 없음."; rm -rf "$W"; exit 1; }
import sys
p, off, old, new = sys.argv[1], int(sys.argv[2]), bytes.fromhex(sys.argv[3]), bytes.fromhex(sys.argv[4])
d = bytearray(open(p, 'rb').read()); n0 = len(d)
assert len(old) == len(new) and bytes(d[off:off+len(old)]) == old, "원본 바이트가 예상과 다름"
d[off:off+len(new)] = new; assert len(d) == n0; open(p, 'wb').write(d)
EOF
echo "원본 대비 바뀐 바이트 수(서명 전): $(cmp -l "$BD/$BIN" "$WB/$BIN" | wc -l | tr -d ' ') (2 여야 함)"
[ "$(cmp -l "$BD/$BIN" "$WB/$BIN" | wc -l | tr -d ' ')" = 2 ] || { echo "!! 예상과 다름. 변경 없음."; rm -rf "$W"; exit 1; }
codesign -f -s - --preserve-metadata=identifier,flags "$WB" 2>&1 | tail -1
codesign --verify --verbose=1 "$WB" 2>&1 | tail -1; codesign --verify "$WB" 2>/dev/null || { echo "!! 서명 검증 실패. 변경 없음."; rm -rf "$W"; exit 1; }
for n in descriptor.dylib impostor.dylib libigdmd.dylib; do
  cmp -s "$BD/Contents/MacOS/$n" "$WB/Contents/MacOS/$n" && echo "  $n: 그대로" || echo "  !! $n: 바뀜"
done
echo "-- 패치본 디스어셈블 (dealloc 의 해당 부분)"
lldb -b -o "target create '$WB/$BIN'" -o "disassemble -s 0x7ed6b -c 10 -b" 2>&1 | grep '\[0x' | sed 's/^.*\[0x/  [0x/' | cut -c1-112
echo "패치본 sha256: $(shasum -a 256 "$WB/$BIN" | cut -d' ' -f1)"
if [ "$MODE" != apply ]; then echo "check 모드: 설치하지 않음."; rm -rf "$W"; echo "===== 끝. 로그: $LOG ====="; exit 0; fi
if [ ! -f "$BK/$BIN" ]; then mkdir -p "$BK" && cp -Rp "$BD/Contents" "$BK/" 2>/dev/null; echo "백업: $BK"; fi
[ "$(shasum -a 256 "$BK/$BIN" | cut -d' ' -f1)" = "$ORIG_SHA" ] || { echo "!! 백업 확인 실패. 변경 없음."; rm -rf "$W"; exit 1; }
sudo -v || { rm -rf "$W"; exit 1; }
put "$WB/$BIN" "$BD/$BIN" 755 && put "$WB/$RES" "$BD/$RES" 644 || echo "!! 설치 실패"
rm -rf "$W"
codesign --verify --verbose=1 "$BD" 2>&1 | tail -1
echo "설치됨. sha256: $(shasum -a 256 "$BD/$BIN" | cut -d' ' -f1)"
echo "※ 아직 재부팅하지 말 것. 새 앱이 정상인지 먼저 확인."
echo "===== 끝. 로그: $LOG ====="
