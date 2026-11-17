#!/bin/bash
O=/Users/user/tweak-backup-2026-11-12/acpi-dump; exec > "$O/usb-inspect.log" 2>&1
[ "$(diskutil info disk6 | awk -F': *' '/Device Location/{print $2}')" = External ] || { echo "disk6 이 외장이 아님"; exit 1; }
diskutil mount disk6s1 || exit 1
MP=$(diskutil info disk6s1 | awk -F': *' '/Mount Point/{print $2}'); echo "MP=$MP"
ls -la "$MP" "$MP/EFI" "$MP/EFI/OC" 2>&1 | head -40
ls "$MP/EFI/OC/Kexts" "$MP/EFI/OC/Drivers" "$MP/EFI/OC/Tools" 2>&1 | tr '\n' ' '; echo
ls -la "$MP/EFI/OC/OpenCore.efi"; shasum -a 256 "$MP/EFI/OC/OpenCore.efi"
for k in Misc.Debug.SysReport Misc.Debug.Target Misc.Debug.AppleDebug Misc.Debug.ApplePanic NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args; do echo "$k = $(plutil -extract $k raw -o - "$MP/EFI/OC/config.plist" 2>&1 | tail -1)"; done
ls -d "$MP/SysReport" "$MP"/opencore-*.txt 2>&1 | head -5
cp "$MP/EFI/OC/config.plist" "$O/usb-config.before.plist"; cp "$MP/EFI/OC/OpenCore.efi" "$O/usb-OpenCore.efi"
chown -R user:staff "$O"; df -h "$MP" | tail -1
diskutil unmount disk6s1
