#!/bin/bash
set -u
T="$HOME/nvidia-trial"; PKG="$T/pkg/v2.9/pkgroot"; TAR="$T/download/v2.9/nullmoth-nvidia-2.9.tar.gz"
LOG="$T/logs/step3-preflight-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "===== step3-preflight $(date) ====="
WANT=b624bf07c78cea03043e096383d5c8b01e4fb2c804a6ba377a4e66a2566422ef
got=$(shasum -a 256 "$TAR" | cut -d' ' -f1)
[ "$got" = "$WANT" ] || { echo "!! 패키지 해시 불일치 ($got). 중단."; exit 1; }
echo "패키지 해시 OK: $got"
[ "$(shasum -a 256 "$PKG/install.sh" | cut -d' ' -f1)" = 31cf6e1b70184267999f509ed7a17c1ed72a3f77f4b149f8b509a08d03486d5b ] || { echo "!! install.sh 가 검토한 것과 다름. 중단."; exit 1; }
echo "install.sh 는 검토한 파일과 동일"
(cd "$PKG" && shasum -a 256 --strict -c SHA256SUMS --quiet) || { echo "!! 패키지 내부 해시 불일치. 중단."; exit 1; }
echo "패키지 내부 86개 파일 해시 OK"
before_le=$(ls /Library/Extensions | shasum | cut -d' ' -f1); before_kc=$(shasum -a 256 /Library/KernelCollections/AuxiliaryKernelExtensions.kc | cut -d' ' -f1)
echo; echo "##### install.sh CHECK=1"
sudo env CHECK=1 /bin/bash "$PKG/install.sh"; rc=$?
echo "종료 코드: $rc"
echo; echo "##### 변경 없음 확인"
after_le=$(ls /Library/Extensions | shasum | cut -d' ' -f1); after_kc=$(shasum -a 256 /Library/KernelCollections/AuxiliaryKernelExtensions.kc | cut -d' ' -f1)
[ "$before_le" = "$after_le" ] && echo "OK: /Library/Extensions 목록 그대로" || echo "!! /Library/Extensions 가 바뀜"
[ "$before_kc" = "$after_kc" ] && echo "OK: AuxKC 그대로 ($after_kc)" || echo "!! AuxKC 가 바뀜"
[ -e /Library/NullMoth ] && { echo "참고: /Library/NullMoth 가 생김:"; ls -la /Library/NullMoth; } || echo "OK: /Library/NullMoth 없음"
ls -d /var/tmp/nullmoth* 2>/dev/null && echo "참고: /var/tmp 에 임시 폴더가 남음" || echo "OK: /var/tmp 임시 폴더 없음"
echo; echo "===== 끝 (rc=$rc). 로그: $LOG ====="
