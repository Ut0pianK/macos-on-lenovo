#!/bin/bash
set -e
MODE="$1"; D=$(cd "$(dirname "$0")" && pwd)
diskutil mount disk0s1 >/dev/null
M=$(diskutil info disk0s1 | awk -F': *' '/Mount Point/{print $2}')
C="$M/EFI/OC/config.plist"; P="PciRoot(0x0)/Pci(0x6,0x0)/Pci(0x0,0x0)"
PB=/usr/libexec/PlistBuddy
case "$MODE" in
apply)
  [ -f "$D/config.plist.before-classcode" ] || cp -p "$C" "$D/config.plist.before-classcode"
  cp -p "$C" "$M/EFI/OC/config.plist.before-classcode"
  /usr/bin/python3 -I - "$C" "$P" <<'PY'
import plistlib,sys
c,p=sys.argv[1],sys.argv[2]
with open(c,'rb') as f: d=plistlib.load(f)
d.setdefault('DeviceProperties',{}).setdefault('Add',{}).setdefault(p,{})['class-code']=bytes([0,0,3,0])
o=d['UEFI']['Output']; o['UIScale']=2 if isinstance(o.get('UIScale'),int) else bytes([2])
with open(c,'wb') as f: plistlib.dump(d,f)
PY
  ;;
undo)
  cp -p "$D/config.plist.before-classcode" "$C" ;;
*) echo "apply|undo"; exit 1;;
esac
plutil -lint "$C"
$PB -c "Print :DeviceProperties:Add:$P" "$C" 2>&1 | head; $PB -c "Print :UEFI:Output:UIScale" "$C" | xxd | head -2
echo "결과: $MODE 완료"
