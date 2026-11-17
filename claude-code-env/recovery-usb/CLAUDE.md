# Recovery 환경에서 실행 중인 Claude Code

지금 너는 사용자의 해킨토시 노트북을 **macOS Recovery**(복구 USB로 부팅)에서 돕고 있다. 평소 macOS가 아니다.

## 사용자 지침 (평소와 같음)
- 모든 권한이 있으니 컴퓨터가 망가지지 않게 신중히 명령을 입력할 것
- 문제가 보이면 증상을 덮는 임시방편부터 하지 말고 근본 원인을 먼저 분석할 것. 코드·로그·펌웨어 등 근거로 원인을 확인한 뒤 고치고, 원인을 확정하지 못했으면 그렇다고 밝힐 것
- 쓸데없는 설명 없이 핵심만 간단히 말할 것
- 한국어로 답할 것

## Recovery 환경의 특징
- 모든 명령이 root로 실행된다. 루트 파일 시스템(BaseSystem)은 읽기 전용이고 RAM에서 돈다.
- 홈(HOME)은 RAM 디스크(`/private/var/tmp/claude-home`)여서 재부팅하면 지워진다. 남겨야 할 기록은 USB `/Volumes/RECOVERY/claude-recovery/logs/`나 내장 디스크에 쓴다.
- 사용할 수 없는 것: Homebrew, Command Line Tools(clang/otool), python3, 평소 설치한 `/usr/local/bin` 도구, Remote Control 자동 재개 장치.
- 사용할 수 있는 것: diskutil, mount, csrutil, nvram, bless, plutil, PlistBuddy(`/usr/libexec/PlistBuddy`), hdiutil, curl, cp/rsync, log, 디스크 유틸리티, macOS 재설치.
- 사용자가 노트북 앞에 있다. 부팅 메뉴 선택·재부팅은 사용자가 직접 한다.

## 이 기기 요약
- OpenCore 해킨토시: Lenovo IdeaPad 계열, i5-1135G7(Iris Xe, WhateverXe), NVIDIA MX450, Intel Wi-Fi(ForbiddenItlwm), SMBIOS MacBookPro16,2, macOS Tahoe 26.x.
- 내장 디스크: `disk0s1` = EFI(OpenCore), `disk0s2` = APFS 컨테이너. 시스템 볼륨 이름 `Hacintosh`, 데이터 볼륨 `Hacintosh - 데이터`. FileVault 꺼짐.
- 사용자 홈: `/Volumes/Hacintosh - 데이터/Users/user`(마운트 안 됐으면 `diskutil mount` 또는 `diskutil apfs list`로 찾기).
- 내장 EFI 백업: 홈 아래 `EFI-backup-<날짜>` 폴더들. 가장 최근 것이 직전 변경 전 상태.
- 복구 USB(이 USB): `s1` EFI = 2026-11-16 19:13 기준 내장 EFI 사본(검증된 판, 단 `DmgLoading=Any`), `s2` RECOVERY(FAT32) = 수정한 Tahoe Recovery + 이 폴더, `s3` ORIGINAL(FAT32) = Apple 원본 Recovery. 자세한 설명은 `notes/07-복구-USB.md`.
- USB EFI 를 내장 EFI 에 덮어쓸 때는 `DmgLoading` 을 내장 원래 값(`Signed`)으로 되돌릴 것.
- OpenCore Security: `SecureBootModel=Disabled`, `DmgLoading=Signed`, `Vault=Optional`, `ScanPolicy=0`.

## 자세한 기록
- `notes/`: 데스크톱 "레킨토시 프로젝트" 문서 사본. `01-기기와-현재-구성.md`(현재 구성), `03-문제별-해결-사전.md`(증상별 해결), `05-하지-말-것과-실패-기록.md`(반드시 먼저 읽을 것).
- `memory/`: 평소 Claude Code 메모리 사본(2026-11-16 기준). 최근 진행 중이던 작업과 되돌리는 방법이 들어 있다.
- 내장 디스크가 살아 있으면 최신 판은 `/Volumes/Hacintosh - 데이터/Users/user/Desktop/레킨토시 프로젝트/`와 `.../.claude/projects/-Users-user/memory/`에 있다. 이 사본보다 그쪽이 최신이다.

## 흔한 복구 작업
- 내장 EFI 마운트: `diskutil mount disk0s1` → `/Volumes/EFI`.
- 내장 EFI를 백업이나 USB EFI로 되돌리기: 현재 EFI를 먼저 다른 곳에 복사해 두고, 백업 폴더의 `EFI`를 통째로 덮어쓴다. 바꾼 뒤 `plutil -lint`로 config.plist를 검사한다.
- 부팅이 안 될 때 원인 찾기: 이전 부팅 로그 `log show --predicate ... --last boot`는 Recovery에서 내장 볼륨 로그를 직접 읽기 어렵다. 패닉 기록은 `/Volumes/Hacintosh - 데이터/Library/Logs/DiagnosticReports/`(`*.panic`)를 본다.
- 새로 넣은 kext 때문에 부팅이 안 되면 config.plist의 `Kernel.Add` 항목에서 `Enabled`를 false로 바꾼다(파일은 지우지 않음).
- macOS 재설치는 데이터를 지우지 않는 덮어쓰기 설치이지만, 하기 전에 사용자 확인을 받는다.
