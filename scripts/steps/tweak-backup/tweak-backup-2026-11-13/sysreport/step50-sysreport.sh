#!/bin/bash
set -u
MODE=${1:-}; INT=disk0s1; D=/Users/user/tweak-backup-2026-11-13/sysreport
DBG=$D/OpenCore-DEBUG-8d8d690.efi; DBG_SHA=298be0bf72b6a97900c18334f2fe17f454409aff240ecbd6d0bb6710a5923f74
REL_SHA=c90ff751c5a798457ceb7981b3e7b0bf93803e397d298c088cc0e998d1458a1f
stop() { echo "!! $* — 중단"; sync; exit 1; }
[ "$(id -u)" = 0 ] || stop "root 필요"
mount | grep -q "^/dev/$INT " || diskutil mount "$INT" >/dev/null || stop "EFI 마운트 실패"
MP="$(diskutil info "$INT" | awk -F': *' '/Mount Point/{print $2}')"; OC="$MP/EFI/OC"; C="$OC/config.plist"; BK="$OC/backup-before-sysreport"
case "$MODE" in
apply)
  [ "$(shasum -a 256 "$DBG" | cut -d' ' -f1)" = "$DBG_SHA" ] || stop "DEBUG 파일 해시 불일치"
  [ "$(shasum -a 256 "$OC/OpenCore.efi" | cut -d' ' -f1)" = "$REL_SHA" ] || stop "EFI 의 OpenCore.efi 가 예상한 RELEASE 가 아님"
  [ -e "$MP/SysReport" ] && { mv "$MP/SysReport" "$MP/SysReport.old-$(date +%s)" || stop "기존 SysReport 치우기 실패"; }
  TS=$(date +%Y-%m-%d-%H%M%S); cp -Rp "$MP/EFI" "/Users/user/EFI-backup-$TS" && chown -R user:staff "/Users/user/EFI-backup-$TS" || stop "EFI 백업 실패"
  mkdir -p "$BK" && cp -p "$OC/OpenCore.efi" "$BK/OpenCore.efi" && cp -p "$C" "$BK/config.plist" || stop "백업 실패"
  cp "$DBG" "$OC/OpenCore.efi" || { cp -p "$BK/OpenCore.efi" "$OC/OpenCore.efi"; stop "교체 실패 → 되돌림"; }
  plutil -replace Misc.Debug.SysReport -bool true "$C" && plutil -lint "$C" >/dev/null || { cp -p "$BK/config.plist" "$C"; cp -p "$BK/OpenCore.efi" "$OC/OpenCore.efi"; stop "config 실패 → 되돌림"; }
  echo "apply 완료 (백업 ~/EFI-backup-$TS). 재부팅하면 EFI 루트에 SysReport 생성" ;;
collect)
  [ -d "$MP/SysReport" ] || stop "SysReport 폴더 없음"
  rm -rf "$D/SysReport"; cp -R "$MP/SysReport" "$D/SysReport" && chown -R user:staff "$D/SysReport"
  ls "$D/SysReport" "$D/SysReport/ACPI" | head -50 ;;
restore)
  [ -f "$BK/OpenCore.efi" ] || stop "백업 없음"
  cp -p "$BK/OpenCore.efi" "$OC/OpenCore.efi" && [ "$(shasum -a 256 "$OC/OpenCore.efi" | cut -d' ' -f1)" = "$REL_SHA" ] || stop "OpenCore 복구 실패"
  plutil -replace Misc.Debug.SysReport -bool false "$C" && plutil -lint "$C" >/dev/null || stop "config 복구 실패"
  [ -d "$MP/SysReport" ] && rm -rf "$MP/SysReport"
  echo "restore 완료: OpenCore RELEASE, SysReport=false" ;;
*) stop "사용법: $0 apply|collect|restore";;
esac
sync
