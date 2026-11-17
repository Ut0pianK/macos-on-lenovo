# PSR 분석 (2026-11-14)

대상: /Library/Extensions/AppleIntelTGLGraphicsFramebuffer.kext (GPUDriversIntel-16.0.32), 디스어셈블 dis.txt

## Apple PSR 구조
- PSR 코드는 TCON 클래스(CamelliaBase → CamelliaTcon2, BanksiaTcon)에만 있음. 일반 경로(AppleIntelFramebufferController)에는 PSR 함수 없음.
- 생성: AppleIntelFramebufferController::start 0x40216: `cmpl $0x2, 0x190(platform@0xd40)` → CamelliaTcon2, `$0x3` → BanksiaTcon. 그 밖의 값이면 TCON 없음 = PSR 없음.
- 생성 뒤 InitTconSW(vtable+0x120)가 0 이 아니면 객체 버림.
- TCON 판별: CamelliaBase::IsThisBanksia — WriteCamelliaReg(0x10400ff)/ReadCamelliaReg(0x10400f0), 칩 ID 0x0805/0x0845 비교 (애플 전용 TCON 레지스터, AUX 경유).
- BanksiaTcon::InitTconHW: Camellia 전용 레지스터 0x1060002, 0x1090000 등 + AUX 쓰기.
- SRDEnter/EDPPSREnter: 표준 인텔 SRD 레지스터(0x60800 SRD_CTL, 0x60840, 0x60860)도 쓰지만, enableHWDC6·disableCDClock·EnablePsrDC6(disableDisplay 로 파이프를 끔) 등 애플 TCON 의 프레임 버퍼 보유 기능에 의존.
- 결론: 플랫폼 값을 2/3 으로 속이면 TCON 전용 레지스터 응답이 없어 실패하거나, 파이프를 끄는 PSR-DC6 경로로 검은 화면 위험. 그대로 켤 수 없음.

## DMC(CSR) 펌웨어
- _CSR_PATCH_AX/_CSR_PATCH_B0plus 내장, hwInitializeCState(0x43972)에서 무조건 적재. -disablegfxfirmware 와 무관.

## 패널
- BOE NV140DRM-N61 (product 0x0931), 2240x1400 eDP.

## 가능한 길: WhateverXe 에 일반 eDP PSR1 구현 (Linux i915 방식)
1단계(읽기 전용 진단): DPCD 0x070/0x071(PSR 지원·버전), SRD_CTL 0x60800, SRD_STATUS 0x60840, DC_STATE_EN 0x45504, DMC DC5/DC6 카운터(0x101084/0x101088) 를 레지스트리로 노출.
2단계(시험): 부트 인자로 PSR1 켬(싱크 DPCD 0x170 쓰기 + SRD_CTL 설정, DC6 는 끈 채). 화면 멈춤 대비 자동 해제 타이머 필요.
예상 이득: 화면 켜진 유휴 시 0.5~1W 정도(8.3W 중). PC10 은 DC6 가 필요해 여전히 어려움.

## 1단계 진단 결과 (2026-11-14 12:07 부팅, WhateverXe 128a480b + -wex-psrprobe)
표식 PSRPST, BAR 매핑 1, 탐침 상태 2(완료). 레지스터 q[2..17]는 ioreg 로 읽을 때마다 새로 읽는 실시간 값(소스 확인). DPCD 와 q19(탐침 시각)만 부팅 때 한 번.

| 레지스터 | 값 | 해석 |
|---|---|---|
| 0x60800 PSR_CTL | 0x00100001 | 비트31(켬)=0 → PSR 꺼짐 |
| 0x60840 PSR_STATUS | 0x04000000 | 상태 IDLE(31:29=0) |
| 0x60844 PERF | 0 | PSR 진입 이력 없음 |
| 0x60860 PSR_DEBUG | 0x04008000 | |
| 0x60814 IMR / 0x60818 IIR | 0xf / 0 | PSR 인터럽트 모두 가림, 대기 없음 |
| 0x45504 DC_STATE_EN | 0 | DC5/DC6 모두 꺼짐 (dc6config=0, -noDC9 영향) |
| 0x45400/0x45404 PWR_WELL | 3 / 3 | |
| 0x101084 DC5 / 0x101088 DC6 / 0x101090 DC3CO | 0 / 0 / 0 | 한 번도 진입 안 함 |
| 0x46010 | 0xcc000000 | |
| 0x70008 PIPECONF A | 0xc0000024 | 파이프 켜짐·동작 중 |

DPCD (AUX 읽기 모두 성공, 결과 비트 0):
- 0x070 = 0x03 → **PSR2 + Y좌표 지원 (PSR1 도 당연히 지원)**
- 0x071 = 0x1b → 종료 시 링크 재훈련 불필요(비트0), 설정 시간 코드 5 = 55µs, Y좌표 필수(비트4), SU 단위 제약 없음(비트5=0)
- 0x700 = 0x04 (eDP 1.4a 계열), 0x701 = 0xfb, 0x702 = 0xc5, 0x703 = 0x02
- 0x2006-0x2008 = 0

DC5/DC6 화면 켬·끔 비교: 레지스터는 실시간이지만 DC_STATE_EN=0(boot-args dc6config=0, -noDC9)이라 화면을 꺼도 카운터는 0 그대로일 수밖에 없음. DC 시험은 PSR1 확인 뒤 따로.

### 판단: TCON 수정 대신 직접 구현
- 패널(BOE NV140DRM-N61)은 표준 VESA PSR1/PSR2 를 지원 → 애플 Camellia/Banksia TCON 없이 i915 방식으로 가능.
- 애플 경로(플랫폼 값 2/3 위장)는 TCON 전용 AUX 레지스터(0x10400f0 칩 ID 등)에 패널이 응답하지 않아 InitTconSW 실패 → 쓸 수 없음.
- 순서 제안: (a) 탐침을 주기 갱신형으로 바꿈 → (b) PSR1 만 시험(DPCD 0x170=0x01 쓰기, PSR_CTL 켬, 유휴 프레임 6, DC 는 꺼 둔 채, 자동 해제 타이머) → (c) PERF 0x60844 증가·STATUS 상태로 진입 확인 → (d) 이후 DC5 만 따로 시험. PSR2(선택 갱신)는 그 뒤.

## 2단계: PSR1 시간 제한 시험 빌드 (2026-11-14)
- 소스 ~/nvidia-trial/build/wex-0.8.0-psr1-src (psrprobe 사본 + kern_xe.cpp 에 wexPsr1*), 결과물 wex-0.8.0-psr1-RELEASE, WhateverXe sha256 0208584b…
- 부트 인자 -wex-psr1 (기존 -wex-psrprobe 유지). 적용/되돌림: sudo bash ~/nvidia-trial/step55-psr1.sh apply|undo, 로그 /var/log/psr1.log
- 순서(i915 display ver 12, 트랜스코더 A):
  1. 싱크: 드라이버 자신의 DPCD 0x060 16바이트 읽기 직후(같은 스레드), 0x070≠0 이면 0x170=0x06(MAIN_LINK_ACTIVE|CRC) → 0x07(+ENABLE). 매번 다시 씀(패널 전원 꺼졌다 켜지면 초기화되므로).
  2. 소스: 첫 싱크 켬 뒤 120초 동안 화면 경로(링크 훈련·enablePipe·disableDisplay)가 조용하면, PIPECONF_A 켜짐·TRANS_DDI_FUNC_CTL_A(DDI A, DP SST) 확인 후 PSR_DEBUG=HPD 만 가림(MEMUP·레지스터 쓰기·MAX_SLEEP 는 PSR 종료를 일으키게 둠, i915 보다 보수적), PSR_CTL=ENABLE|LINK_STANDBY|MAX_SLEEP 0x1F|CRC|TP1/TP2 500us|IDLE 6 (=0x89F00406).
  3. 감시: 250ms 마다 PSR_STATUS 상태 분포 기록, 파이프/DDI 이상이면 끔.
  4. 멈춤(재부팅 전까지 다시 안 켬): 10분 경과, disableDisplay, enablePipe, 링크 훈련. 끌 때 PSR_CTL.ENABLE 지우고 IDLE 까지 최대 2초 기다림. 싱크 0x170 은 그대로 둠(소스가 진입 신호를 안 보내면 무해).
- 링크는 켠 채(LINK_STANDBY): 1차 시험은 진입·종료가 제대로 되는지만 본다. 절전 효과는 링크 끄기·DC5 가 붙어야 커짐.
- 감시 데몬: 5분 못 버티면 다음 부팅에서 자동 undo+재부팅. 18분 동안 caffeinate -d 로 화면 잠자기 막음(화면 끔 경로가 PSR 과 겹치지 않게), 1분마다 stat 기록.
- 해독: ~/psr-analysis/psrstat.py [hex]. q24=요청<<63|이유<<8|단계, q25=싱크 쓰기 결과<<32|횟수, q26=켤 때 PSR_CTL<<32|DDI_FUNC_CTL_A, q27/q28=켠/끈 시각 ns, q29=표본 수, q30/q31=상태 분포(IDLE,SRDONACK,SRDENT,BUFOFF / BUFON)+켤 때 PERF+0x070.
- 성공 판정: 상태 분포에 SRDENT(2)/BUFOFF(3)가 나오고 PERF 가 늘며, 그동안 화면이 멈추지 않을 것(마우스·영상 갱신 정상).

## 2단계 결과 (2026-11-14 12:34 부팅, PSR1 켬 12:36:58 ~ 끔 12:46:58)
- 싱크 0x170 쓰기 3회 모두 성공, 소스 켬 성공(PSR_CTL 0x89f00406, TRANS_DDI_FUNC_CTL_A 0x8a010006 = DDI A·DP SST), 10분 시간 제한으로 정상 종료(PSR_CTL 0x09f00406, 상태 IDLE). 부팅 5분 감시 통과.
- 250ms 표본 2392개: IDLE 1686(70%), SRDONACK 61(3%), 나머지 645(27%)는 상태 5~7(이번 빌드는 0~4 만 셌음. 실시간 표본에서 state=6 확인: PSR_STATUS 0xc4040006).
- PERF 0x60844: 0 → 0x28602(165378). 밀리초로 보면 165초 = 600초의 27.6% → 상태 5~7 비율과 일치. 즉 이 칩에서는 PSR 안에 있을 때 상태값이 6 으로 읽히고, **PSR 에 실제로 27% 머물렀다**.
- 조건: 시험 내내 터미널(Claude Code)·iStat 이 화면을 계속 갱신. MEMUP·레지스터 쓰기 가림 없음, 유휴 6프레임, 링크 켠 채.
- IIR 0, AUX 오류 비트(15) 관찰 없음. 화면 멈춤 여부는 사용자 확인 필요.
- 다음: (a) 상태 5~7 도 세도록 분포 확장 (b) 시간 제한 없이 상시 켜되 화면 끔/재훈련 뒤 다시 켜기 (c) 링크 끄기(LINK_STANDBY 해제) (d) DC5 와 조합 — 전력 측정은 (b) 이후 배터리에서.
- 시험 뒤 `step55-psr1.sh undo` 로 psrprobe(128a480b) 상태로 되돌림(다음 재부팅은 MX450 vramstat 시험 전용).

## 3단계 빌드: 상시 켜기 psr1b (2026-11-14 12:59 적용)
- 소스 wex-0.8.0-psr1b-src, sha256 7b3c0794…, 적용 step57-psr1b.sh. boot-args: -wex-psr1 (링크 끄기는 -wex-psr1-linkoff 추가 시).
- 달라진 점: 시간 제한 없음(debug.wexpsr1_max 로 줄 수 있음), 멈춘 뒤 조건이 되면 다시 켬(조용한 시간 debug.wexpsr1_delay 기본 30초), 실시간 스위치 sysctl debug.wexpsr1, 켬/끔은 스핀락으로 직렬화, 상태 0~7 전부 집계, 별도 속성 WhateverXePsr1Stat(u64[28]).
- 싱크 준비 플래그: 0x170 쓰기 성공 시 참, disableDisplay 때 거짓(패널 전원이 내려갈 수 있으므로) → 다음 0x060 읽기에서 다시 써야 재진입.
- 링크 끄기 모드: 싱크 0x170=0x05, PSR_CTL 에서 LINK_STANDBY 빼고 TP1/TP2 2.5ms.

## psr1b 결과 (2026-11-14 13:02 부팅)
- 13:03:44 PSR 켜짐(부팅 약 2분). 첫 67초 분포: IDLE 44~39%, SRDONACK 2%, 상태6 1%, **상태7 53~57%** → 이 칩은 PSR 안에서 상태 7(가끔 6)로 읽힘. 1단계의 "5~7 = 27%"와 같은 범주, 이번엔 화면이 더 조용해서 비율이 높음.
- 화면 끔(pmset displaysleepnow, 13:05:05): disableDisplay 훅으로 즉시 멈춤(이유 8), PSR_CTL 0x09f00406, 상태 IDLE. 17초 뒤 화면 켬 정상(Complete modeset + 링크 훈련, 검은 화면 없음 — 전원 상태 4 복귀 기준, 눈으로는 사용자 확인 필요).
- 결함: 화면 켬 경로는 DPCD 0x060 을 읽지 않음 → 싱크준비 플래그가 거짓으로 남아 PSR 재진입 안 함.
- 수정 psr1c(67483039): 드라이버 링크 훈련이 성공으로 끝난 직후 같은 스레드에서 0x170 을 다시 씀(wexPsr1SinkEnable 공용 함수). step58-psr1c.sh.

## psr1c 결과 (2026-11-14 13:08 부팅)
- 화면 끔→켬(13:10): 끔 때 이유 8 로 멈춤, 켬 뒤 링크 훈련 직후 0x170 재기록(싱크 쓰기 4회째 성공), 약 30초 뒤 자동 재진입(켬 2회). 재진입 결함 해결.
- 유휴 60초 측정(psrdelta.py, 터미널 진행 표시 없는 상태): 상태 7 68.8% + 상태 6 1.2%, PERF 증가 42.6s = **70.6% PSR 체류**. → PERF 0x60844 단위는 ms, 상태 6·7 이 PSR 안임이 확정.
- 터미널 스피너·진행 표시가 도는 동안은 3% 안팎(유휴 6프레임을 못 채우거나 1프레임 만에 깨어남). 측정은 반드시 백그라운드로.
- 남은 것: 배터리 전력 비교(sysctl debug.wexpsr1=0/1), 링크 끄기(-wex-psr1-linkoff), DC5.
## 링크 끄기 시험 (2026-11-14 13:16 적용): step59-psr1-linkoff.sh, boot-args += -wex-psr1-linkoff. 기대 PSR_CTL 0x81f00626, 싱크 0x170=0x05.

## 링크 끄기 결과 (2026-11-14 13:39 부팅) — 실패, 화면 멈춤
- 13:40 PSR 켜짐(PSR_CTL 0x81f00626, 싱크 0x170=0x05). 첫 60초: IDLE 80.5%, SRDONACK 10.4%, 상태5 5.8%, 상태6 3.3%, **상태 7(안정적 PSR)은 한 번도 없음**, PERF 6.3s(10.4%).
- 이후 화면이 멈춰 사용자가 강제 종료(13:42쯤). 다음 부팅에서 감시 데몬이 5분 미통과를 보고 자동으로 -wex-psr1-linkoff 제거 + 재부팅(13:43) → 지금은 psr1c 링크 유지 모드.
- 해석(미검증): 링크를 끈 뒤 깨어날 때 TP1/TP2 2.5ms 로는 패널이 링크를 다시 못 잡음. 링크 유지 모드에서는 문제없으므로 원인은 종료 시 링크 재동기 절차. 후보: TP2 대신 TP3 선택(PSR_CTL bit 11), 종료 전 AUX wake/프레임 동기, Apple 드라이버가 정한 전압·프리엠퍼시스가 빠른 재훈련 조건을 못 채움.
- 결정: 링크 끄기는 보류. 다시 시험하려면 멈춤을 감수해야 하므로 사용자 입회·승인 필요. debug.wexpsr1_max 로 짧은 시간 제한을 걸고 시험할 것.

## PSR1 전력 효과 (2026-11-14 15:03~15:18, 화면 켬 유지, 배터리, psr-ab.sh, 구간 150초 × 6)
- PSR 끔: PC8 16.1 / 16.7 / 16.9 %, 패키지 1.84 / 1.82 / 1.73 W, 배터리 9.31 / 8.94 / 8.94 W
- PSR 켬: PC8 59.7 / 58.1 / 57.8 %, 패키지 1.42 / 1.42 / 1.47 W, 배터리 8.53 / 8.55 / 8.78 W
- → 화면 켠 유휴에서 PSR 이 PC8 체류를 16% → 58% 로 올리고, 패키지 −0.36W, 배터리 평균 9.06 → 8.62W(−0.44W, 약 5%). **PSR1(링크 유지) 유지 결정.**
- 화면 켬 시 PSR 체류 55%(상태 7). 화면 끔 3회 모두 깨끗이 멈추고 재진입.

## 링크 끄기 재시험 (2026-11-14 17:01·17:03, epp 빌드의 실행 중 전환, loctl 0xA20 = TP3 선택 + TP1/TP3 2.5ms, PSR_CTL 0x81f00e26)
- 절차: debug.wexpsr1_max=N → debug.wexpsr1_linkoff=1 → 화면 끔·켬(재훈련, 패널 0x170=0x05) → 30초 뒤 PSR 켜짐 → N초 뒤 자동 끔 → linkoff=0 → 화면 끔·켬. 스크립트 linkoff-trial.sh <loctl> <초>.
- 30초 창(터미널 갱신 중): 진입 6회, 체류 약 0.05초. 60초 창(조용): PERF 0x35e08→0x361fb = 1.0초(1.7%), 진입·종료를 초당 한 번꼴로 반복하고 매번 약 1프레임 만에 나옴. 상태 7(안정 체류)은 늘지 않음.
- 화면 멈춤·깜빡임 없음(사용자 확인: 화면 꺼짐 2회뿐). 시스템 정상, 링크 유지 모드로 복귀해 PSR 재진입.
- 해석: TP3 로 바꾸니 멈춤은 사라졌지만 링크 끄기 모드에서는 PSR 에 머물지 못함(링크 유지 모드는 같은 조건에서 55~70%). 원인 미확인 — 패널이 PSR 오류를 올리는지 보려면 깨어난 직후 DPCD 0x2006/0x2008 을 읽어야 함(드라이버 스레드에서만 AUX 가능).
- 결정: 링크 끄기는 이득 없음 → 보류. 링크 유지 PSR 유지.
