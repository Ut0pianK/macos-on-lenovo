#!/usr/bin/env python3
import subprocess, re, struct, sys
m = re.search(r'"WhateverXeHdaTrace" = <([0-9a-f]+)>', subprocess.run(["ioreg","-l","-d1","-w0"],capture_output=True,text=True).stdout)
if not m: sys.exit("WhateverXeHdaTrace 없음")
b = bytes.fromhex(m.group(1)); q = struct.unpack("<%dQ" % (len(b)//8), b)
print(f"기록 {q[0]&0xffffffff}개, 놓침 표시 {q[0]>>32}")
V12 = {0x701:"SET_CONNECT_SEL",0x705:"SET_POWER_STATE",0x706:"SET_STREAM_ID",0x707:"SET_PIN_CTL",0x708:"SET_UNSOL",0x709:"SET_PIN_SENSE",0x70c:"SET_EAPD",0x70d:"SET_DIGI1",0x715:"SET_GPIO_DATA",0x716:"SET_GPIO_MASK",0x717:"SET_GPIO_DIR",0x7ff:"FUNC_RESET",
       0xf00:"GET_PARAM",0xf01:"GET_CONNECT_SEL",0xf02:"GET_CONN_LIST",0xf05:"GET_POWER_STATE",0xf06:"GET_STREAM_ID",0xf07:"GET_PIN_CTL",0xf08:"GET_UNSOL",0xf09:"GET_PIN_SENSE",0xf0c:"GET_EAPD",0xf1c:"GET_CONFIG_DEFAULT",0x71c:"SET_CFG0",0x71d:"SET_CFG1",0x71e:"SET_CFG2",0x71f:"SET_CFG3"}
V4 = {0x2:"SET_STREAM_FORMAT",0x3:"SET_AMP_GAIN_MUTE",0x4:"SET_PROC_COEF",0x5:"SET_COEF_INDEX",0xa:"GET_STREAM_FORMAT",0xb:"GET_AMP_GAIN_MUTE",0xc:"GET_PROC_COEF",0xd:"GET_COEF_INDEX"}
prev = 0
for e in q[1:]:
    icw = e >> 63; us = (e >> 32) & 0x7fffffff; v = e & 0xffffffff
    cad, nid, cmd = v >> 28, (v >> 20) & 0xff, v & 0xfffff
    if (cmd >> 8) in V12: name, param = V12[cmd >> 8], cmd & 0xff
    elif (cmd >> 16) in V4: name, param = V4[cmd >> 16], cmd & 0xffff
    else: name, param = f"verb {cmd>>8:#x}", cmd & 0xff
    print(f"{us/1000:9.1f}ms (+{(us-prev)/1000:6.1f}) {'ICW ' if icw else ''}codec {cad} node {nid:#04x} {name} {param:#x}")
    prev = us
