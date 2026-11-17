#!/usr/bin/env python3
import subprocess, re, struct, sys, time
def rd():
    o = subprocess.run(["ioreg","-l","-d1","-w0"],capture_output=True,text=True).stdout
    p = struct.unpack("<28Q", bytes.fromhex(re.search(r'"WhateverXePsr1Stat" = <([0-9a-f]+)>', o).group(1))[:224])
    q = struct.unpack("<32Q", bytes.fromhex(re.search(r'"WhateverXePsrStat" = <([0-9a-f]+)>', o).group(1))[:256])
    return p, q[4] & 0xffffffff
n = int(sys.argv[1]) if len(sys.argv) > 1 else 60
a, pa = rd(); t = time.time(); time.sleep(n); b, pb = rd(); dt = time.time() - t
h = [b[6+i]-a[6+i] for i in range(8)]; tot = sum(h) or 1
print(f"{dt:.0f}s: 표본 {tot}, " + ", ".join(f"{i}:{h[i]*100/tot:.1f}%" for i in range(8) if h[i]) + f" | PSR 체류(PERF) {(pb-pa)/1000:.1f}s = {(pb-pa)/10/dt:.1f}% | 켬 {b[3]&0xffffffff}회 끔 {b[3]>>32}회")
