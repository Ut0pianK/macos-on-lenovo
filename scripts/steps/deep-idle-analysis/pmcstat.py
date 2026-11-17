#!/usr/bin/env python3
import subprocess, re, struct, sys
if len(sys.argv) > 1: h = open(sys.argv[1]).read().strip()
else:
    m = re.search(r'"WhateverXePmcStat" = <([0-9a-f]+)>', subprocess.run(["ioreg","-l","-d1","-w0"],capture_output=True,text=True).stdout)
    if not m: sys.exit("WhateverXePmcStat 없음 (-wex-pmcstat 부팅인지 확인)")
    h = m.group(1)
b = bytes.fromhex(h); q = struct.unpack("<%dQ" % (len(b)//8), b)
reg = {v >> 32: v & 0xffffffff for v in q[16:227]}
print(f"PMC 매핑={q[1]&1} PCI {(q[1]>>8)&0xff}개(조사 {(q[1]>>16)&0xff}회) EPB 설정={struct.unpack('<i', struct.pack('<I', q[1]>>32))[0]}")
def irtl(v):
    u = [1, 32, 1024, 32768, 1048576, 33554432][(v >> 10) & 7] if ((v >> 10) & 7) < 6 else 0
    return f"{'유효' if v & 0x8000 else '무효'} {(v & 0x3ff) * u / 1000:.0f}us"
for n, v in zip(["PKGC3","PKGC6","PKGC7","PKGC8","PKGC9","PKGC10"], q[2:8]): print(f"  {n}_IRTL = {v:#x} ({irtl(v)})")
def ltr(v):
    def one(x):
        if not x & 0x8000: return "요구 없음"
        sc = [1, 32, 1024, 32768, 1048576, 33554432, 0, 0][(x >> 10) & 7]
        return f"{(x & 0x3ff) * sc / 1000:.1f}us"
    return f"snoop {one(v & 0xffff)}, no-snoop {one(v >> 16)}"
names = {0x1B50:"현재 플랫폼 LTR",0x1B54:"현재 집계 LTR",0x1B60:"SOUTHPORT_A",0x1B64:"SOUTHPORT_B",0x1B68:"SATA",0x1B6C:"기가비트 LAN",0x1B70:"XHCI(USB)",0x1B78:"ME",0x1B7C:"EVA",0x1B80:"SOUTHPORT_C",0x1B84:"HD 오디오",0x1B8C:"LPSS(I2C/UART)",0x1B90:"카메라",0x1B94:"SOUTHPORT_D",0x1B98:"SOUTHPORT_E",0x1B9C:"eSPI",0x1BA0:"SCC",0x1BA4:"ISH",0x1BA8:"UFS",0x1BAC:"eMMC",0x1BB0:"CNVi(무선)",0x1BB4:"WiGig",0x1BB8:"THC0",0x1BBC:"THC1"}
print(f"LTR 무시 마스크 0x1B0C = {reg.get(0x1B0C,0):#010x}")
for off, n in names.items():
    v = reg.get(off, 0)
    if v: print(f"  {n:16} {v:#010x}  {ltr(v)}")
print(f"SLP_S0 디버그 0x10B4/B8/BC = {reg.get(0x10B4,0):#x} {reg.get(0x10B8,0):#x} {reg.get(0x10BC,0):#x}  PM_CFG={reg.get(0x1818,0):#x}  SLP_S0 체류 카운터={reg.get(0x193C,0)}")
print("LPM 영역(0x1C20~0x1D40, 0 아닌 값): " + " ".join(f"{o:#x}={reg[o]:#x}" for o in range(0x1C20, 0x1D40, 4) if reg.get(o)))
print("PPFEAR/기타(0x1D80~0x1E2C): " + " ".join(f"{o:#x}={reg[o]:#x}" for o in range(0x1D40, 0x1E30, 4) if reg.get(o)))
print("PCI 장치 (ASPM: LNKCTL 비트0=L0s 1=L1 / L1SS CTL1 비트0~3=PCI-PM L1.2,L1.1,ASPM L1.2,L1.1 / LTR 켬=DEVCTL2 비트10):")
for i in range((q[1] >> 8) & 0xff):
    d = q[228 + i*8: 236 + i*8]
    bus, dev, fn, vid, did = (d[0]>>48)&0xff, (d[0]>>40)&0xff, (d[0]>>32)&0xff, d[0]&0xffff, (d[0]>>16)&0xffff
    lnkcap, lnkctl = d[2] & 0xffffffff, (d[2] >> 32) & 0xffff
    devctl2 = (d[3] >> 32) & 0xffff; pmcsr = d[4] & 0xffff
    s = f"  {bus:02x}:{dev:02x}.{fn} {vid:04x}:{did:04x} class {d[1]>>8:06x} D{pmcsr&3}"
    if d[2]: s += f" | ASPM 지원 {(lnkcap>>10)&3} 켬 {lnkctl&3} CLKREQ {(lnkctl>>8)&1} LTR켬 {(devctl2>>10)&1}"
    if d[5]: s += f" | L1SS 지원 {d[5]&0x1f:#x} 켬 {(d[5]>>32)&0xf:#x}"
    if d[7]: s += f" | LTR max {d[7]&0xffff:#x}/{(d[7]>>16)&0xffff:#x}"
    print(s)

if len(sys.argv) < 2:
    m = re.search(r'"WhateverXeL1ssStat" = <([0-9a-f]+)>', subprocess.run(["ioreg","-l","-d1","-w0"],capture_output=True,text=True).stdout)
    if m:
        w = struct.unpack("<16Q", bytes.fromhex(m.group(1))[:128])
        S = {0:"안 건드림",1:"진행 중",2:"켬",3:"끔",0x10:"포트 없음",0x11:"장치 없음",0x12:"기능 없음/전원 꺼짐",0x13:"공통 지원 상태 없음"}
        for i, n in enumerate(["SD 리더(RP04)", "NVMe(RP09)"]):
            s = w[i*8:(i+1)*8]
            print(f"L1SS {n}: {S.get(s[7], hex(s[7]))} | 전 ctl1 포트 {s[1]>>32:#010x} 장치 {s[1]&0xffffffff:#010x} → 후 포트 {s[3]>>32:#010x} 장치 {s[3]&0xffffffff:#010x}, ctl2 {s[4]>>32:#x}/{s[4]&0xffffffff:#x}, 공통 {s[6]:#x}")
