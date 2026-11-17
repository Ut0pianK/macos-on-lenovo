# 깊은 절전 분석 노트 (2026-11-14)

## 기준 전력 (배터리, 밝기 75%, NVIDIA RTD3 동작, PSR1 링크 유지 모드)
- 화면 켬: 약 8.1W, 패키지 1.71W, PC8 54%, PC9/PC10 0%
- 화면 끔: 약 6.3W, 패키지 1.51W, PC8 59~67%, PC9/PC10 0%
- 주의: NVIDIA 부트 가드가 걸려 드라이버가 꺼진 부팅(강제 종료 뒤)에서는 26~29W. 전력 측정 전 `ioreg -r -c NVAccel` 확인.

## PC9/PC10 차단 요인 (14:25, pmcstat/psrstat)
- 화면 끔 상태 디스플레이 레지스터: PIPECONF_A 0x24(파이프 꺼짐), 0x46010=0(DPLL 꺼짐), **PWR_WELL 0x45400/0x45404 = 3 그대로, DC_STATE_EN 0x45504 = 0**.
  → 화면을 꺼도 디스플레이 전원 우물 1 이 켜져 있고 DC9 허용이 꺼져 있음. TGL 에서 PC9/PC10 은 디스플레이가 DC9(화면 끔) 또는 DC6(화면 켬+PSR)여야 들어감.
  → 원인은 우리가 넣은 boot-args `-nodisplaysleepDC6 -noDC9 dc6config=0` (화면 켤 때 DBUF power up timeout → 검은 화면 우회책). 즉 PC10 은 그 검은 화면 문제를 고쳐야 열림.
- PCH LTR: 장치 요구가 PC10 을 막을 수준은 아님(화면 끔: SOUTHPORT_A(SD 리더 쪽) 3.0ms, XHCI 0.41ms, SOUTHPORT_C(NVMe) 요구 없음). PKGC IRTL MSR 6개는 전부 0(펌웨어 미설정).
- PCIe: NVMe(03:00.0)·SD 리더(02:00.0)와 루트 포트는 ASPM L1 켜짐, 그러나 **L1 하위 상태(L1.1/L1.2) 켬 = 0**(지원 0x1f), CLKREQ 꺼짐. PEG0/MX450 은 L1SS 0xf. → L1.2 를 켜면 PC8 에서도 플랫폼 쪽 절감 여지(위험: NVMe 는 부팅 디스크).
- SLP_S0 체류 카운터 0 (S0ix 한 번도 없음).

## EPB·PSR A/B (14:30~14:59, master.sh, launchd 로 분리 실행)
- 첫 구간(화면 켬): 8.98W, 패키지 1.51W. 둘째 구간부터는 화면 잠자기(10분 유휴)로 **화면 끔 상태**: 5.03~5.20W, 패키지 1.26~1.39W, PC8 69~73%.
- EPB 0 / 6 / 15 (화면 끔): 5.05 / 5.03~5.09 / 5.11W, 패키지 1.27 / 1.28~1.39 / 1.32W → **유휴 전력에 차이 없음**(측정 오차 안). HWP 가 켜져 있어 예상대로.
- PSR 켬/끔 구간은 화면이 꺼져 있어 무효(PSR 은 화면 켬에서만 동작). 다시 재려면 `caffeinate -d` 로 화면을 켜 두고 psr=0/1 만 반복.
- 화면 끔 유휴 5.05W 는 14:07 측정(6.3W, 내려가는 중)보다 낮음: 완전히 가라앉은 값 + 이어폰 감시를 이벤트 방식으로 바꾼 뒤.
- 교훈: 관리자 osascript 로 오래 도는 스크립트를 직접 띄우면 osascript 가 CPU 12% 를 쓰며 기다림 → `launchctl submit` 으로 분리(start-master.sh). 그 아래에서는 SIGTERM 이 안 먹어 pkill -9.

## L1 하위 상태 실행 중 켜기 (15:24, l1ss 빌드 6b1a5eed, sysctl debug.wexl1ss)
- SD 리더 쌍: ctl1 포트 0x40a7780f / 장치 0x40a7000f, ctl2 0xb0 (공통 0xf, 임계 167×1024ns). NVMe 쌍: 포트 0x4058280f / 장치 0x4058000f, ctl2 0xb0 (임계 88×1024ns).
- 켠 뒤 2·10·30·30·45초 쉬고 64MB 쓰기+읽기: 모두 정상(0.07~0.09s), 커널 오류 로그 없음.
- 재부팅하면 펌웨어 상태(끔)로 돌아감. 전력 비교는 l1ss-ab.sh(배터리).

## macOS 가 EPP 를 정하는 방식 (15:48, X86PlatformPlugin Mac-5F9802EFE386AA28.plist 분석)
- IOPlatformPowerProfile.FrequencyVectors: 7668바이트 블롭 2개(동일, Frequencies 3800/4100 용). 끝부분(오프셋 7092~)에 36바이트짜리 "이름+값" 항목들:
  hwp=1, **epp=0x80**, perf-bias=7, utility-tlvl=0x40, non-focal-tlvl=0xfb, ratioratelimit=100000, io_core_cst_lim=3, io_hints=1, iocs_cstflr=8, iocs_disengage=15625, iocs_engage=2000000, iocs_rtrigger=100, **lpm_ratio=0x18(24)**.
  앞부분 5764~ 에 QoS 등급별 표(BACKGROUND, REALTIME_SHORT, KERNEL, THRU_TIER2~5).
- 즉 EPP 는 기종 표의 단일 값(128). 저전력 모드는 lpm_ratio(최고 배수 24 = 2.4GHz)만 적용하고 EPP 는 안 바꿈(오늘 배터리+저전력 모드 측정 내내 HWP_REQUEST EPP=0x80).
- 실행 중 스위치: sysctl machdep.xcpm.epp_override(현재 0), machdep.xcpm.io_epp_boost_enabled(0). epp_override 동작은 미검증.
- perf-bias=7 인데 MSR 0x1B0 은 0 으로 읽힘 → HWP 에서는 XCPM 이 EPB 를 쓰지 않는 듯.
- pmset: 배터리 lowpowermode=1 이었음(사용자가 15:46 에 끔), lessbright=0. 전원 전환 시 밝기 변화는 저전력 모드 탓으로 추정.
- 추출본: ~/deep-idle-analysis/xcpm/fv0.bin

## XCPM 의 EPP 계산 (커널 25.6.0 xnu-12377.161.15 디스어셈블, 16:10)
- 표의 "epp" 키 처리(_xcpm_cpu_control+0x1fa0, 0xffffff800040e3e0): 값(≤255)을 `*(_xcpm_qos_table) + 0x94` 바이트에 저장하고 `_xcpm_hwp_idle_epp` 를 그 이상으로 올림. 두 심볼 모두 커널 심볼 표에 있음.
- 패키지 EPP(MSR 0x774 에 쓰는 값) = 모든 CPU 의 요청 EPP(xcpm_cpus[i]+0xC0, 구조체 0x380 바이트) 중 최솟값. 
- `machdep.xcpm.epp_override`(= _xcpm_config+0x210, 읽기 전용 sysctl): 0 이 아니고 목표 P-state 가 _xcpm_pst_metadata+0x38 과 같을 때만 그 값으로 대체 → "특정(최고) 구간 전용" 값이지 일반 덮어쓰기가 아님. xcpm_cpu_control 의 다른 명령으로 설정됨.
- 결론: 배터리/충전별 EPP 는 커널 확장에서 `*(_xcpm_qos_table)+0x94` 를 바꾸는 것이 XCPM 자신의 "epp" 설정과 같은 동작. (FrequencyVectors 의 epp 를 CPUFriend 로 바꾸는 것과 같은 자리)

## 전원별 EPP 설치 (16:09)
- `sysctl debug.wexepp` 검증: 192 → HWP_REQUEST EPP 0xc0, 64 → 0x40, 128 → 0x80 (즉시 반영).
- `/usr/local/libexec/turbo-ac.sh`(백업 .bak-20261114-epp)가 5초 주기 전원 확인에 맞춰 EPP 를 씀. `/usr/local/etc/turbo-ac.conf`: EPP_AC=64, EPP_BATT=192 (0 이면 안 건드림).
- 발견: `/var/db/turbo-off.pending` 이 13:43(링크 끄기 실패 뒤 감시 데몬 재부팅 때)부터 남아 turbo-ac 데몬이 "아무것도 안 함" 상태였음 → 15:23, 16:07 부팅은 터보가 켜져 있었음(HWP max 42). 표식 지우고 재시작 → 터보 끔 확인(0x1A0 bit38=1).

## DMC 1·2단계 (2026-11-14 17:28~17:31, dmc1 빌드 9dc8af46)
- 1단계 `sysctl debug.wexdmc=1`: Intel tgl_dmc 2.12 주 프로그램 적재 성공. 0x80000 첫 워드 0xaa0ad7d7 → 0x0c004040, 프로그램 4460워드·MMIO 9개 읽기 일치, DC_STATE_DEBUG=2. 20초 뒤 PWR_WELL/CDCLK/DBUF 그대로, DC5/DC6 진입 0.
- 2단계 화면 끔 + `debug.wexdc=2` 30초: **DC5 진입 12회, DC6 0회**. 해제(`=0`)는 재기록 0회·복원 대기 0ms, PWR_WELL 3·CDCLK PLL 잠김·DBUF S1 켜짐. 화면 켬 정상(PIPECONF 0xc0000024, DBUF S2 0xc0000000, "DBUF 2 power up timeout" 없음). → 올바른 DMC 로는 DC 진입·복귀가 됨.
- 그러나 이 구간 내내 PC8 0%(패키지 4.4~5.2W)라 PC9/PC10·전력 효과는 못 봄. 원인: 커널 스레드가 CPU 70% 를 씀 — spindump 상 `thread call high` 가 AppleHDA → AppleHDAController 안에서 계속 도는 중(AppleHDAController 스레드도 바쁨). 이어폰 감시 에이전트를 내려도, 소리를 재생해도 그대로.
  DMC 적재 때문인지, DC 허용 때문인지, 무관한지 미확정(시험 전 기준 구간에서도 이미 PC8 0%). 가설: 디스플레이 오디오(iDisp) 코덱이 DMC/DC 전환에 영향받아 AppleHDA 가 명령 재시도를 반복. Linux 는 오디오가 코덱과 통신할 때 DC 상태를 막음(POWER_DOMAIN_AUDIO).
- 다음: 재부팅 → ① 아무것도 안 한 상태의 kernel_task·PC8 기준 ② DMC 만 올리고 관찰 ③ DC 허용 후 관찰. 단계별로 kernel_task CPU 를 기록.

## 커널 CPU 70% 의 정체와 DC6 재시험 (2026-11-14 17:36~18:21)
- kernel_task 70%(AppleHDA 스레드)는 DMC 와 무관: DMC 를 안 올린 부팅에서도 발생, 이어폰을 뽑아도 그대로. **완전 종료 후 켜니 사라짐** → 17:10 이어폰 A/B(코덱 계수 번갈아 쓰기) 뒤 오디오 코덱 상태가 틀어졌고 웜 재부팅으로는 초기화되지 않았던 것. `ab.sh` 는 다시 쓰지 말 것.
- 이어폰 지지직: 재부팅 뒤 0x45=d489 는 남고 0x1b 만 기본값(0x0a4b) → `headset-ctia-once.sh` 가 0x1b 도 확인하게 고침.
- 깨끗한 상태 단계 시험(dmc-staged.sh dc, 충전기 연결, PSYS):
  | 단계 | PSYS | 패키지 | PC8 | DC5/DC6 진입 |
  | 화면 켬 기준 | 5.8W | 1.73W | 48% | 0/0 |
  | DMC 적재 후(+40초) | 4.8W | 1.52W | 56% | 0/0 |
  | 화면 끔 + DC6 허용 | 3.08~3.27W | 1.33~1.47W | 8% (PC9/PC10 로 내려간 것으로 보임; psys.pl 은 PC8 만 표시) | 12 / 2066 (30초) |
  | DC6 해제(화면 끔) | 3.47W | 1.48W | 63% | — |
  | 화면 켬 뒤 | 5.2W | 1.63W | 53% | — |
- 결론: Intel tgl_dmc 2.12 로는 화면 끔 DC6 진입(초당 약 70회)·복귀 모두 정상, 검은 화면·DBUF 오류 없음, kernel_task 1.5%. 화면 끔 유휴에서 약 0.2~0.4W 절감(PSYS 기준). PSYS 절대값은 배터리 측정(화면 켬 8.6W)보다 낮게 나오므로 상대 비교용.
- 다음: 자동화 — 부팅 때 DMC 적재, `AppleIntelFramebufferController::setDCState(bool)` 을 감싸 Doze 진입 뒤 DC6 허용 / Wake 맨 처음에 해제.

## 2026-11-14 저녁 결과
- **자동 DC6**(dc6auto2 → hdasniff → depop 빌드에 포함, boot-args -wex-dc6): 부팅 60초 뒤 DMC 적재, `setDCState` 훅으로 화면 끔 때 DC6 허용·깨어날 때 해제. 화면 끔·켬 3회 정상, 회당 DC6 약 1000회, PC9 약 15% 처음 관측(PC10 0%).
- **DMC 잔존 + 웜 재부팅 → AppleHDA 스레드 CPU 70%**: 종료·재시동 직전 DMC 를 지우는 처리(커널 general interest + turbo-ac.sh 의 TERM trap → `sysctl debug.wexdmc=0`)를 넣은 뒤 20:05 웜 재시동에서 폭주 없음(로그 `TERM: DMC unload` 20:05:07, 부팅 뒤 kernel_task 정상, PC8 16%). 강제 종료 뒤 재시동에서는 지울 기회가 없으니 재발 가능 → 그때는 완전 종료 후 켜기.
- **이어폰 "틱" 해결**(depop 빌드 5f520f0f, -wex-depop): `IOHDACodecFunction::executeVerb` route 성공(`WexHdaDepopRouted = Yes`), AFG D0 뒤 30ms·핀 0x21 제어 앞 85ms·뒤 100ms 대기 → 사용자 확인 "틱 소리 안 남". 근거 기록 `~/Projects/HeadsetCTIA/trace-play1.txt`.
