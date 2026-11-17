import lldb, struct, os

OUT = os.path.dirname(os.path.abspath(__file__))
KEYS = [b"target-default-ppmm", b"default-resolution"]
MODS = ["IOKit", "CoreDisplay", "SkyLight", "CoreGraphics"]

def sections(mod, target):
    res = []
    def walk(sec):
        n = sec.GetNumSubSections()
        if n == 0:
            res.append(sec)
        for i in range(n):
            walk(sec.GetSubSectionAtIndex(i))
    for i in range(mod.GetNumSections()):
        walk(mod.GetSectionAtIndex(i))
    return res

def read(process, addr, size):
    err = lldb.SBError()
    data = b""
    step = 1 << 20
    off = 0
    while off < size:
        n = min(step, size - off)
        chunk = process.ReadMemory(addr + off, n, err)
        if not err.Success() or chunk is None:
            return None
        data += chunk
        off += n
    return data

def run(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    log = open(os.path.join(OUT, "findref.txt"), "w")
    def p(*a):
        s = " ".join(str(x) for x in a)
        print(s)
        log.write(s + "\n")

    for mod in target.module_iter():
        name = mod.GetFileSpec().GetFilename()
        if name not in MODS:
            continue
        secs = sections(mod, target)
        blobs = {}
        for s in secs:
            la = s.GetLoadAddress(target)
            if la == lldb.LLDB_INVALID_ADDRESS or s.GetByteSize() == 0:
                continue
            blobs[s.GetName()] = blobs.get(s.GetName(), []) + [(la, s.GetByteSize(), s)]
        for key in KEYS:
            straddrs = []
            for la, sz, s in blobs.get("__cstring", []):
                d = read(process, la, sz)
                if not d:
                    continue
                i = d.find(key + b"\0")
                while i >= 0:
                    if i == 0 or d[i - 1] == 0:
                        straddrs.append(la + i)
                    i = d.find(key + b"\0", i + 1)
            if not straddrs:
                continue
            p("== %s: \"%s\" cstring at %s" % (name, key.decode(), [hex(a) for a in straddrs]))
            targets = set(straddrs)
            for la, sz, s in blobs.get("__cfstring", []):
                d = read(process, la, sz)
                if not d:
                    continue
                for off in range(0, len(d) - 31, 8):
                    v = struct.unpack_from("<Q", d, off)[0]
                    if v in straddrs:
                        targets.add(la + off - 16)
                        p("   cfstring struct at", hex(la + off - 16))
            funcs = {}
            for la, sz, s in blobs.get("__text", []):
                d = read(process, la, sz)
                if not d:
                    continue
                for i in range(0, len(d) - 4):
                    disp = struct.unpack_from("<i", d, i)[0]
                    if la + i + 4 + disp in targets:
                        ref = la + i
                        a = target.ResolveLoadAddress(ref)
                        sym = a.GetSymbol()
                        fn = sym.GetName() if sym.IsValid() else "?"
                        st = sym.GetStartAddress().GetLoadAddress(target) if sym.IsValid() else 0
                        en = sym.GetEndAddress().GetLoadAddress(target) if sym.IsValid() else 0
                        p("   ref at %s in %s [%s-%s]" % (hex(ref), fn, hex(st), hex(en)))
                        if sym.IsValid():
                            funcs[fn] = (st, en)
            for fn, (st, en) in funcs.items():
                path = os.path.join(OUT, "dis-%s-%s.txt" % (name, "".join(c if c.isalnum() else "_" for c in fn)[:60]))
                ro = lldb.SBCommandReturnObject()
                debugger.GetCommandInterpreter().HandleCommand(
                    "disassemble --start-address %s --end-address %s" % (hex(st), hex(en)), ro)
                open(path, "w").write(ro.GetOutput() or "")
                p("   wrote", path, "(%d lines)" % (ro.GetOutput() or "").count("\n"))
    log.close()

def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f findref.run findref")
