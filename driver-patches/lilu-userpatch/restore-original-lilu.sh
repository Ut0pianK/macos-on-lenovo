#!/bin/bash
D="$(cd "$(dirname "$0")" && pwd)"
osascript -e "do shell script \"diskutil mount disk0s1 && cp -X '$D/Lilu-original-1.7.3.kext/Contents/MacOS/Lilu' /Volumes/EFI/EFI/OC/Kexts/Lilu.kext/Contents/MacOS/Lilu && cp -X '$D/Lilu-original-1.7.3.kext/Contents/Info.plist' /Volumes/EFI/EFI/OC/Kexts/Lilu.kext/Contents/Info.plist && sync && shasum /Volumes/EFI/EFI/OC/Kexts/Lilu.kext/Contents/MacOS/Lilu\" with administrator privileges"
echo "원본 해시는 690d3693fa4c8f7e53ea649e2f33daa2673b8c0a 이어야 합니다. 재부팅하면 적용됩니다."
