#!/usr/bin/env python3
"""Emit pdp9x.casm: casmeleon language definition for the 18-bit machine."""

MEM = [("TAD", "TADX", 0), ("TAS", "TASX", 1), ("AND", "ANDX", 2),
       ("XOR", "XORX", 3), ("DAC", "DIX", 4), ("LAC", "LIX", 5),
       ("SAD", "SXD", 6), ("IOR", "IORX", 7)]
JMPC = [("CAL", 8), ("JMP", 9), ("ISZ", 10), ("DSZ", 11)]

MODES = [("{{ a }}", "( a : Ints )", 0, 0),
         ("{{ a , x }}", "( a : Ints, x : XReg )", 0, 1),
         ("{{ ( a ) }}", "( a : Ints )", 1, 0),
         ("{{ ( a ) , x }}", "( a : Ints, x : XReg )", 1, 1)]

G1 = [("CLA", 11), ("CLL", 10), ("CMA", 9), ("CML", 8),
      ("RLA", 7), ("RRA", 6), ("SHA", 5), ("SRA", 4),
      ("IAC", 3), ("IXC", 2), ("HLT", 0)]
G1_COMBO = [("NOP", []), ("CLC", ["CLA", "CMA"]), ("STL", ["CLL", "CML"]),
            ("CLAL", ["CLA", "CLL"]), ("CIA", ["CMA", "IAC"]),
            ("LSR", ["CLL", "RRA"]), ("LSL", ["CLL", "RLA"]),
            ("GLK", ["CLA", "RLA"]),
            ("ONEA", ["CLA", "IAC"]), ("ONEX", ["CLA", "IXC"])]
# The skip group, with the conditions the 18-bit family had: minus, zero and
# link, OR'd together, with one bit inverting the result.  Skip-on-interrupts-
# enabled was ours and DEC had no such thing; it belongs with the processor's
# other state, which is device 0 in the IO group, so it lives there now and its
# bit here goes to the sign.
#
# The DEC mnemonics are kept as aliases, because the combinations are what make
# the group worth having and they are documented under those names: SMA+SZA is
# "AC <= 0", SPA+SNA is "AC > 0".
G2 = [("SKZ", 0, 1), ("SKNZ", 1, 1), ("SKL", 0, 2), ("SKNL", 1, 2),
      ("SKM", 0, 4), ("SKNM", 1, 4), ("SKP", 1, 0),
      ("SZA", 0, 1), ("SNA", 1, 1), ("SNL", 0, 2), ("SZL", 1, 2),
      ("SMA", 0, 4), ("SPA", 1, 4),
      # The combinations are the point of an OR'd condition group, and the
      # assembler emits one word per mnemonic, so they need names of their own.
      ("SKLE", 0, 5), ("SKGT", 1, 5),      # AC <= 0, and AC > 0
      ("SKLZ", 0, 6), ("SKGZ", 1, 6)]     # minus or link, and neither

out = []
w = out.append

w("// 18-bit accumulator machine, PDP-9 derived.")
w("// Assemble with: casmeleon -lang=pdp9x.casm -byteSize=32 -endian=big -export=bin f.s")
w("")
w('.num 16 "0x" ""')
w('.num 2 "0b" ""')
w('.num 8 "0o" ""')
w("")
w(".set XReg {")
w("    X;")
w("}")
w("")
w("// bit position of each register inside the G3 stack mask")
w(".set SReg {")
w("    SP;")
w("    LPC;")
w("    IX;")
w("    AC;")
w("}")
w("")

w(".inline MR")
w(".with ( op : Ints, ind : Ints, idx : Ints, r : Ints, a : Ints ) -> {")
w("    .if a < 0 || a > 2047 {")
w('        .error a, "memory reference address outside the 11 bit zero page";')
w("    }")
w("    .return ( op << 14 ) + ( ind << 13 ) + ( idx << 12 ) + ( r << 11 ) + a;")
w("}")
w("")
w(".inline JPC")
w(".with ( op : Ints, a : Ints, here : Ints ) -> {")
w("    // a == 0 means the label is still unresolved on the first pass;")
w("    // casmeleon re-evaluates it later, so an .error here would be fatal.")
w("    .if a != 0 && ( a >> 12 ) != ( here >> 12 ) {")
w('        .error a, "CAL/JMP direct is PC-page relative: target is in another 4K page";')
w("    }")
w("    .return ( op << 14 ) + ( a & 4095 );")
w("}")
w("")
w(".inline JC")
w(".with ( op : Ints, ind : Ints, idx : Ints, a : Ints ) -> {")
w("    .if a < 0 || a > 4095 {")
w('        .error a, "jump class address outside the 12 bit zero page";')
w("    }")
w("    .return ( op << 14 ) + ( ind << 13 ) + ( idx << 12 ) + a;")
w("}")
w("")

for names, op in [((a, b), c) for a, b, c in MEM]:
    pass

for mn_ac, mn_ix, op in MEM:
    for r, mn in ((0, mn_ac), (1, mn_ix)):
        for pat, args, ind, idx in MODES:
            w(".opcode %s %s" % (mn, pat))
            w(".with %s -> {" % args)
            w("    .out [ .expr MR(%d, %d, %d, %d, a) ];" % (op, ind, idx, r))
            w("}")
            w("")

for mn, op in JMPC:
    for pat, args, ind, idx in MODES:
        w(".opcode %s %s" % (mn, pat))
        w(".with %s -> {" % args)
        if op <= 9 and ind == 0 and idx == 0:
            # CAL/JMP mm=00 is PC-page: EA = { PC[16:12], addr12 }
            w("    .out [ .expr JPC(%d, a, .addr) ];" % op)
        else:
            w("    .out [ .expr JC(%d, %d, %d, a) ];" % (op, ind, idx))
        w("}")
        w("")

w("// ---- IOT ----")
w("//  17..14  13..11  10..8   7..4   3    2     1     0")
w("//   1110   dev(3)  sub(3)  ----  CLA  IOP4  IOP2  IOP1")
w(".opcode IO {{ a }}")
w(".with ( a : Ints ) -> {")
w("    .out [ 0x38000 + a ];")
w("}")
w("")
IOT = 0x38000
def iot(dev, sub, iop1=0, iop2=0, iop4=0, cla=0):
    return IOT | (dev << 11) | (sub << 8) | (cla << 3) | (iop4 << 2) | (iop2 << 1) | iop1
for mn, val in (
        ("SCROLL", iot(1, 0, iop4=1)),      # start a one line scroll
        ("SKBSY",  iot(1, 0, iop1=1)),      # skip if the blitter is busy
        ("SKRDY",  iot(1, 1, iop1=1)),      # skip if the blitter is idle
        ("TARM",   iot(2, 0, iop4=1)),
        ("TACK",   iot(2, 1, iop4=1)),
        ("TLOAD",  iot(2, 2, iop4=1)),      # AC[7:0] -> counter high byte
        ("SKIRQ",  iot(2, 0, iop1=1)),
        ("KRAW",   iot(3, 0, iop2=1, cla=1)),   # raw code of the last key
        ("KMOD",   iot(3, 1, iop2=1, cla=1)),   # modifiers held with it
        ("SKKB",   iot(3, 2, iop1=1)),          # skip if a keystroke is waiting
        ("KACK",   iot(3, 3, iop4=1)),          # collected: resume scanning
        ("LEDS",   iot(4, 0, iop4=1)),
        # device 0 is the processor: its only register is the interrupt mask
        ("IMRD",   iot(0, 0, iop2=1, cla=1)),
        ("IMWR",   iot(0, 0, iop4=1)),
        ("IMSET",  iot(0, 1, iop4=1)),   # let the lines in AC through
        ("IMCLR",  iot(0, 2, iop4=1)),   # mask the lines in AC
        ("SKI",    iot(0, 4, iop1=1)),   # skip when interrupts are on
        ("SKNI",   iot(0, 5, iop1=1)),   # and when they are off
        ("WAIT",   iot(0, 3, iop4=1)),   # stop fetching until a request arrives
        # device 5 is the bare-CPU test harness
        ("HTON",   iot(5, 0, iop4=1)),
        ("HTOFF",  iot(5, 1, iop4=1)),
        ("HOUT",   iot(5, 2, iop4=1)),
        ("HACK",   iot(5, 3, iop4=1))):
    w(".opcode %s {{ }}" % mn)
    w(".with ( ) -> {")
    w("    .out [ 0x%X ];" % val)
    w("}")
    w("")

w("// ---- OPR group 1: AC / L ----")
OPRG1 = 0x3C000
for mn, bit in G1:
    w(".opcode %s {{ }}" % mn)
    w(".with ( ) -> {")
    w("    .out [ 0x%X ];" % (OPRG1 | (1 << bit)))
    w("}")
    w("")
for mn, parts in G1_COMBO:
    v = OPRG1
    for p in parts:
        v |= 1 << dict(G1)[p]
    w(".opcode %s {{ }}" % mn)
    w(".with ( ) -> {")
    w("    .out [ 0x%X ];" % v)
    w("}")
    w("")

w("// ---- OPR group 2: skips.  bit11 = invert, bits 2:0 = I,L,Z ----")
OPRG2 = 0x3D000
for mn, n, mask in G2:
    w(".opcode %s {{ }}" % mn)
    w(".with ( ) -> {")
    w("    .out [ 0x%X ];" % (OPRG2 | (n << 11) | mask))
    w("}")
    w("")

w("// ---- OPR group 3: stack.  bit11 = pop, bits 10:9 = I field ----")
OPRG3 = 0x3E000
w(".inline G3")
w(".with ( d : Ints, ifield : Ints, mask : Ints ) -> {")
w("    .return 0x3E000 + ( d << 11 ) + ( ifield << 9 ) + mask;")
w("}")
w("")
for mn, d in (("PSH", 0), ("POP", 1)):
    for n in range(1, 5):
        regs = ["r%d" % i for i in range(n)]
        pat = " , ".join(regs)
        args = ", ".join("%s : SReg" % r for r in regs)
        mask = " + ".join("( 1 << %s )" % r for r in regs)
        w(".opcode %s {{ %s }}" % (mn, pat))
        w(".with ( %s ) -> {" % args)
        w("    .out [ .expr G3(%d, 0, %s) ];" % (d, mask))
        w("}")
        w("")
for mn, val in (("RET", OPRG3 | (1 << 11) | (1 << 1)),
                ("RTI", OPRG3 | (1 << 11) | (2 << 9) | (1 << 1)),
                ("EI", OPRG3 | (2 << 9)),
                ("DI", OPRG3 | (1 << 9))):
    w(".opcode %s {{ }}" % mn)
    w(".with ( ) -> {")
    w("    .out [ 0x%X ];" % val)
    w("}")
    w("")

text = "\n".join(out)
open("pdp9x.casm", "w").write(text + "\n")
print("wrote pdp9x.casm,", len(text.splitlines()), "lines")
