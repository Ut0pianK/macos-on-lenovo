# 화면 켤 때 검은 화면(DBUF 2 power up timeout) 정적 분석 요약 (2026-11-14, 서브에이전트, dis.txt 기준)

## 결론
- 검은 화면은 DC9 문제가 아님. 화면 끔은 Doze 상태라 DC9 분기(모든 프레임버퍼 Sleep)는 타지 않음 → `-noDC9` 는 이 버그와 무관.
- 원인(추정, 정적으로는 확정 불가): 기본값 `dc6config=1`(하드웨어 DC6)에서 Apple 드라이버가 올리는 DMC 가 **Ice Lake 계열**(첫 워드 0x0b004040, 0x8F074=0x6FC0, 0x8F004=0x00A40088 — Intel icl_dmc_ver1_09 와 동일 값)인데 Tiger Lake 는 tgl_dmc_ver2_12(0x0c004040, 0x8F074=0x86FC0, 0x8F004=0x01A40188, MMIO 쌍 6개 더)가 맞음. 드라이버는 DC6 종료 뒤 DMC 가 PG1/CDCLK/DBUF 를 되살렸다고 믿고 바로 DBUF 슬라이스 2 를 요청(10us 한 번 확인) → 실패.
- Apple 의 DC6 종료(disableHWDC6 0x48054)는 DC_STATE_EN 을 한 번만 쓰고 확인하지 않음(Linux 는 최대 100회 재기록·검증, CDCLK/DBUF 확인, 콤보 PHY 재초기화).

## 부트 인자 (getOSInformation 0x40db3 등)
- `-nodisplaysleepDC6`: 화면 끔(Doze)에서의 DC6 분기 전체를 끔. `-noDC9`: 전체 Sleep 분기만. 
- `dc6config`: 0 = 아무것도 안 함(DMC 도 안 올림), 1 = 하드웨어 DC6(DMC), 2 = **소프트웨어 DC6**(DMC 없이 드라이버가 직접 PG1·CDCLK·DBUF 를 내리고, 깨어날 때 enableDisplayEngine 전체 수행; pcode 메일박스 0x22), 3 = TCON PSR 용 fast DC6(Doze 에서는 2 와 같음).
- 화면 끔 버그만 보면 `-nodisplaysleepDC6` 또는 `dc6config=0` 하나만으로 충분.

## 고칠 후보 (순위)
1. `dc6config=2` + `-nodisplaysleepDC6` 제거(+`-noDC9` 유지): 코드 없이 부트 인자만. 화면 끔에서 드라이버가 디스플레이 엔진을 직접 끄고 켬. 더 내려가려면 setDCState 래핑으로 DC_STATE_EN bit3(DC9) 추가. 위험: PG1 ack 대기 20us 초과 시 패닉, 부팅 때 한 번도 안 타 본 경로, 메일박스 0x22 의미 불명.
2. DMC 를 Intel tgl_dmc_ver2_12 로 교체(hwInitializeCState 래핑, hwConfigureCustomAUX 무력화, disableHWDC6 에 검증 루프): 진짜 DC5/DC6. 더 크고 미검증.
3. dc6config=1 유지 + 깨어날 때 enableDisplayEngine 강제: 임시방편, 비권장.
- 먼저 할 읽기 전용 확인: DC6 를 한 번 켜고 검은 화면 중 0x45504, 0x45404, 0x46070, 0x45008, 0x44FE8, 0x101084/88 을 읽으면 추정이 확정됨(탐침에 0x46070·0x45008·0x44FE8 추가 필요).

## 미확정
- ICL 계열 DMC 가 TGL 에서 실제로 무엇을 하는지, 깨어난 뒤 DC_STATE_EN 이 0 으로 읽히는지, dc6config=2 를 이 기기에서 시도한 적이 있는지(TODO 기록상 DC6/DC9 재시험은 인자 3개를 한꺼번에 뺀 것 = dc6config 기본 1), PG1 ack 지연.
- 추출한 DMC: ~/deep-idle-analysis/dmc/ (Apple dmc_AX.bin, dmc_B0plus.bin, Intel 원본 dl/)
