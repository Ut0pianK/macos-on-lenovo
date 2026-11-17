#!/usr/bin/env python3
import subprocess, re, struct, sys
m = re.search(r'"WhateverXeDcStat" = <([0-9a-f]+)>', subprocess.run(["ioreg","-l","-d1","-w0"],capture_output=True,text=True).stdout)
if not m: sys.exit("WhateverXeDcStat 없음 (dmc1 빌드인지 확인)")
q = struct.unpack("<16Q", bytes.fromhex(m.group(1))[:128])
print(f"DMC 적재: {['안 함','성공','읽기 불일치'][q[9]&0xff] if (q[9]&0xff)<3 else q[9]&0xff}  DC 허용 중={q[9]>>32}")
if q[1]: print(f"  적재 전 0x80000={q[0]>>32:#x} DC_STATE_EN={q[0]&0xffffffff:#x} → 적재 후 첫 워드 {q[1]>>32:#x}, 불일치 {q[1]&0xffff}워드/MMIO {(q[1]>>16)&0xffff}개, DC_STATE_DEBUG={q[2]:#x}")
if q[3]: print(f"  마지막 허용: 값 {q[3]>>32} (그 전 DC_STATE_EN {q[3]&0xffffffff:#x})")
if q[8]: print(f"  해제 {q[8]}회. 마지막: 계기 {q[4]>>32:#x}, 해제 전 {q[4]&0xffffffff:#x}, 재기록 {q[5]>>32}회, 복원 대기 {(q[5]&0xffffffff)/10:.1f}ms → PWR_WELL {q[6]>>32:#x} DC_STATE_EN {q[6]&0xffffffff:#x} CDCLK_PLL {q[7]>>32:#x} DBUF_S1 {q[7]&0xffffffff:#x}")
print(f"DC5 진입 {q[10]}회, DC6 진입 {q[11]}회 | 지금 DC_STATE_EN={q[12]:#x} PWR_WELL={q[13]:#x} CDCLK_PLL={q[14]:#x} DBUF_S1={q[15]:#x}")
