#!/usr/bin/env python3
import subprocess, re, struct, sys
h = sys.argv[1] if len(sys.argv) > 1 else re.search(r'"WhateverXePsrStat" = <([0-9a-f]+)>', subprocess.run(["ioreg","-l","-d1","-w0"],capture_output=True,text=True).stdout).group(1)
q = struct.unpack("<32Q", bytes.fromhex(h)[:256])
names = ["PSR_CTL","PSR_STATUS","PSR_PERF","PSR_DEBUG","PSR_IMR","PSR_IIR","DC_STATE_EN","PWR_WELL1","PWR_WELL2","DC5cnt","DC6cnt","DC3CO","0x8F074","0x8F004","0x46010","PIPECONF_A"]
for i, n in enumerate(names):
    v = q[2+i]; print(f"{n:11} {v>>32:#08x} = {v&0xffffffff:#010x}" + (f"  state={(v&0xffffffff)>>29}" if n=="PSR_STATUS" else ""))
if any(q[24:32]):
    mn = ["CDCLK_PLL 0x46070","DBUF_S1 0x45008","DBUF_S2 0x44FE8","DMC 0x8F034","DMC[0] 0x80000","DMC_DBG 0x45520","CDCLK_CTL 0x46000","PWR_WELL_DBG 0x45408"]
    print("엔진/DMC: " + "  ".join(f"{n}={v&0xffffffff:#x}" for n, v in zip(mn, q[24:32])))
print(f"probe state={q[18]}  DPCD070={q[20]&0xffff:#06x} res={q[20]>>32:#x}")

m = re.search(r'"WhateverXePsr1Stat" = <([0-9a-f]+)>', subprocess.run(["ioreg","-l","-d1","-w0"],capture_output=True,text=True).stdout) if len(sys.argv) < 2 else None
if m:
    p = struct.unpack("<28Q", bytes.fromhex(m.group(1))[:224])
    f = p[1]; R = {0:"-",4:"파이프/DDI 이상",5:"시간 제한",7:"링크 훈련",8:"disableDisplay",9:"enablePipe",10:"sysctl 끔",11:"패널 재읽기(0x060)"}
    print("\n== PSR1 상시 모드 ==")
    print(f"스위치={'켬' if f&1 else '끔'} 링크끄기={'예' if f&2 else '아니오'} 싱크준비={'예' if f&4 else '아니오'} 단계={'동작' if (f>>8)&0xff==2 else '대기'} 마지막 멈춤 이유={R.get((f>>16)&0xff,(f>>16)&0xff)}")
    print(f"싱크 쓰기 {p[2]&0xffffffff}회(결과 {p[2]>>32:#x})  켬 {p[3]&0xffffffff}회 / 끔 {p[3]>>32}회 / 켜기 보류 {p[15]>>32}회  PSR_CTL={p[14]>>32:#010x}")
    tot = sum(p[6:14]) or 1
    print(f"켜져 있던 시간 {p[4]/1e9:.0f}s, 표본 {p[5]}")
    print("상태 분포: " + ", ".join(f"{i}:{p[6+i]*100/tot:.1f}%" for i in range(8)) + "  (0=IDLE, 6=PSR 안)")
    print("멈춤 이유별: " + ", ".join(f"{R.get(i,i)}={p[16+i]}" for i in range(12) if p[16+i]))
