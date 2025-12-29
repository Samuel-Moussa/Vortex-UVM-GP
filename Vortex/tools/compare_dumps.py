#!/usr/bin/env python3
import sys, os
def compare(a,b):
    if not os.path.exists(a) or not os.path.exists(b):
        print("ERROR: missing file(s)", a if not os.path.exists(a) else "", b if not os.path.exists(b) else ""); sys.exit(2)
    sa, sb = os.path.getsize(a), os.path.getsize(b)
    print(f"A: {a} ({sa} bytes)\\nB: {b} ({sb} bytes)")
    diffs = 0
    with open(a,'rb') as fa, open(b,'rb') as fb:
        pos = 0
        while True:
            ba = fa.read(65536); bb = fb.read(65536)
            if not ba and not bb: break
            m = min(len(ba), len(bb))
            for i in range(m):
                if ba[i] != bb[i]:
                    if diffs < 16: print(f"diff @ 0x{pos+i:08x}: A={ba[i]:02x} B={bb[i]:02x}")
                    diffs += 1
            if len(ba) != len(bb):
                longer = ba if len(ba) > len(bb) else bb
                for i in range(m, len(longer)):
                    if diffs < 16: print(f"diff @ 0x{pos+i:08x}: extra byte {longer[i]:02x}")
                    diffs += 1
            pos += m
    print(f"Total differing bytes: {diffs}")
    return 0 if diffs==0 else 1

if __name__=="__main__":
    if len(sys.argv)<3: print('Usage: compare_dumps.py <simx_bin> <rtlsim_bin>'); sys.exit(2)
    sys.exit(compare(sys.argv[1], sys.argv[2]))
