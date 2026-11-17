#!/bin/bash
O=/Users/user/tweak-backup-2026-11-12/safari-mx450
exec > "$O/run.log" 2>&1
/bin/bash /Users/user/nvidia-trial/upstream/v2.9-src/package/safari_gpu_copy.sh install; echo "copy rc=$?"
/bin/bash /Users/user/nvidia-trial/upstream/v2.9-src/package/safari_gpu_copy.sh status
ls -la /System/Volumes/Preboot/Cryptexes/OS/Library/GPUBundles 2>&1
echo "ACPI Tables(root): $(ioreg -l -w0 | grep -c '"ACPI Tables"')"
ioreg -a -c AppleACPIPlatformExpert -r -d 1 > "$O/acpi-root.plist" 2>/dev/null; ls -la "$O/acpi-root.plist"
chown -R user:staff "$O"
