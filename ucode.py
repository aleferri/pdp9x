#!/usr/bin/env python3
"""Microcode for the 18-bit machine: field definitions, the microprogram, an
assembler that emits ROM images, and an engine that executes them.

The engine exists so that the microprogram can be checked against `sim.py`
instruction by instruction.  Two independent descriptions that agree are worth
more than one that is merely plausible, and a divergence is a bug with an
address on it rather than a suspicion.

    python3 ucode.py            assemble, report sizes, self test
    python3 ucode.py roms       print the base64 blobs for LogicCircuit
"""
import base64
import sys

W = 0o777777          # 18 bits
A17 = 0x1FFFF

# --------------------------------------------------------------- fields
# name, width, symbolic values.  36 bits, which is two machine words: the
# control store is two ROMs of 128 by 18 rather than one of an odd width the
# component may not offer.
FIELDS = [
    ("ASRC",  3, "NONE AC IX SP T PC FROMIR"),
    ("BSRC",  2, "DI IRF11 IRF12 DEV"),
    ("ALU",   4, "ADD AND OR XOR PASSA PASSB SHL SHR ROL ROR CMA FROMIR DEC ADD1 PASSB1 G1"),
    ("DOSRC", 3, "HOLD FROMIR LPC ALU AC IX SP"),
    ("RDST",  3, "NONE AC IX SP T PC DO FROMIR"),
    ("LCTL",  2, "HOLD FROMALU FROMDI"),
    ("ARSRC", 3, "HOLD ALU PC PCNEXT DI PAGE STACK STACKR"),
    ("MEM",   2, "IDLE RD WR IO"),
    
    ("ICTL",  2, "IHOLD ICLR ISET IFROMIR"),
    ("SEQ",   3, "NEXT JUMP MAP MAP2 BRANCH SKIPF MAPMASK SKIPC"),
    ("CC",    2, "NEVER Z NZ G2"),
    ("SPUP",  1, "U0 U1"),
    ("NA",    7, ""),
]

POS, SYM = {}, {}
_bit = 0
for _n, _w, _v in FIELDS:
    POS[_n] = (_bit, _w)
    _bit += _w
    if _v:
        for _i, _s in enumerate(_v.split()):
            SYM[(_n, _s)] = _i
assert _bit in (36, 37), _bit
UWIDTH = _bit


def uword(**kw):
    """One microinstruction from named fields."""
    v = 0
    for name, val in kw.items():
        shift, width = POS[name]
        if isinstance(val, str):
            val = SYM[(name, val)]
        assert 0 <= val < (1 << width), "%s=%s does not fit %d bits" % (name, val, width)
        v |= val << shift
    return v


def ufield(w, name):
    shift, width = POS[name]
    return (w >> shift) & ((1 << width) - 1)


# --------------------------------------------------------------- program
# Written as (label, fields).  Labels resolve to microaddresses; NA may name a
# label and is patched in a second pass, exactly like the macro assembler.
U = []
LBL = {}


def u(label=None, **kw):
    if label:
        LBL[label] = len(U)
    U.append(kw)


# ---- fetch ----------------------------------------------------------
# AR already holds PC: every terminal microinstruction leaves it that way,
# which is what makes the fetch one cycle.
u("FETCH", MEM="RD", ARSRC="PCNEXT", SEQ="MAP")

# The fetch that also finishes the instruction before it.  One of these, not
# one per opcode, because ALU and RDST can say "read it out of IR".
u("FETCH_A", MEM="RD", ARSRC="PCNEXT", SEQ="MAP",
  ASRC="FROMIR", BSRC="DI", ALU="FROMIR", RDST="FROMIR", LCTL="FROMALU")

# The operate group needs no operand and never disturbs AR, so the whole
# instruction is the fetch after it: one cycle at steady state.
u("FETCH_G", MEM="RD", ARSRC="PCNEXT", SEQ="MAP",
  ASRC="AC", ALU="G1")

# ---- effective address ----------------------------------------------
u("EA_ZP",  ARSRC="ALU", ASRC="FROMIR", BSRC="IRF11", ALU="PASSB", DOSRC="FROMIR", SEQ="MAP2")
u("EA_IDX", ARSRC="ALU", ASRC="IX", BSRC="IRF11", ALU="ADD", DOSRC="FROMIR", SEQ="MAP2")
u("EA_IN1", ARSRC="ALU", ASRC="NONE", BSRC="IRF11", ALU="PASSB", SEQ="NEXT")
u(          MEM="RD", SEQ="NEXT")
u("EA_IN3", ARSRC="DI", ASRC="FROMIR", DOSRC="FROMIR", SEQ="MAP2")
u("EA_IX1", ARSRC="ALU", ASRC="NONE", BSRC="IRF11", ALU="PASSB", SEQ="NEXT")
u(          MEM="RD", SEQ="NEXT")
u("EA_IX3", ARSRC="ALU", ASRC="IX", BSRC="DI", ALU="ADD", DOSRC="FROMIR", SEQ="MAP2")

# the jump class carries twelve bits and mm=00 means the PC page
u("JMP_PG", ARSRC="PAGE", RDST="PC", SEQ="JUMP", NA="FETCH")
u("JMP_IDX",ARSRC="ALU", ASRC="IX", BSRC="IRF12", ALU="ADD", RDST="PC",
            SEQ="JUMP", NA="FETCH")
u("JMP_IN1",ARSRC="ALU", ASRC="NONE", BSRC="IRF12", ALU="PASSB", SEQ="NEXT")
u(          MEM="RD", SEQ="NEXT")
u(          ARSRC="DI", RDST="PC", SEQ="JUMP", NA="FETCH")
u("JMP_IX1",ARSRC="ALU", ASRC="NONE", BSRC="IRF12", ALU="PASSB", SEQ="NEXT")
u(          MEM="RD", SEQ="NEXT")
u(          ARSRC="ALU", ASRC="IX", BSRC="DI", ALU="ADD", RDST="PC",
            SEQ="JUMP", NA="FETCH")

u("JA_PG",  ARSRC="PAGE", SEQ="MAP2")
u("JA_ZP",  ARSRC="ALU", ASRC="NONE", BSRC="IRF12", ALU="PASSB", SEQ="MAP2")
u("JA_IDX", ARSRC="ALU", ASRC="IX", BSRC="IRF12", ALU="ADD", SEQ="MAP2")
u("JA_IN1", ARSRC="ALU", ASRC="NONE", BSRC="IRF12", ALU="PASSB", SEQ="NEXT")
u(          MEM="RD", SEQ="NEXT")
u("JA_IN3", ARSRC="DI", SEQ="MAP2")
u("JA_IX1", ARSRC="ALU", ASRC="NONE", BSRC="IRF12", ALU="PASSB", SEQ="NEXT")
u(          MEM="RD", SEQ="NEXT")
u("JA_IX3", ARSRC="ALU", ASRC="IX", BSRC="DI", ALU="ADD", SEQ="MAP2")

# ---- operations ------------------------------------------------------
# the tail folds into the next fetch
u("OP_RD",  MEM="RD", ARSRC="PC", SEQ="JUMP", NA="FETCH_A")
u("OP_DAC", MEM="WR", ARSRC="PC", SEQ="JUMP", NA="FETCH")

# a comparison decides a skip, so it cannot fold: four cycles either way
# SKIPC increments PC when the condition holds and goes straight to the fetch,
# so the comparison needs no state of its own after it: the incrementer feeds
# the AR mux inside the same cycle.
u("OP_SAD", MEM="RD", SEQ="NEXT")
u(          ASRC="FROMIR", BSRC="DI", ALU="XOR", ARSRC="PC", SEQ="SKIPC", CC="NZ")
u("SKIP",   ARSRC="PCNEXT", SEQ="JUMP", NA="FETCH")  # PCNEXT is the increment

u("OP_JMP", ASRC="NONE", ALU="PASSB", RDST="PC", ARSRC="HOLD", SEQ="NEXT")
u(          ARSRC="PC", SEQ="JUMP", NA="FETCH")

u("OP_ISZ", MEM="RD", SEQ="NEXT")
u(          ASRC="NONE", BSRC="DI", ALU="FROMIR", DOSRC="ALU", SEQ="NEXT")
u(          MEM="WR", SEQ="BRANCH", CC="Z", NA="SKIP")
u(          ARSRC="PC", SEQ="JUMP", NA="FETCH")

# ---- operate ---------------------------------------------------------
# Group 1 is dedicated logic, not a general ALU function: one microinstruction
# applies every selected microoperation to AC, L and IX at once, which is why
# it does not go through RDST.
u("G1",     ASRC="AC", ALU="G1", ARSRC="PC", SEQ="JUMP", NA="FETCH")
# The skip folds as well, by the same trick the interrupt check uses: the
# fetch reads the next word speculatively and, when the condition turns out to
# hold, suppresses the IR load, steps PC once more and reads again.  Not taken
# costs nothing, taken costs one cycle.
u("FETCH_S", MEM="RD", ARSRC="PCNEXT", SEQ="SKIPF", CC="G2")
# Group 2 of OPR, the stack.  The mask is reduced one bit at a time: the
# dispatch picks a bit, clears it, runs the two cycles for that register and
# comes straight back, so the cost is the population count and nothing else.
# Push takes the lowest bit set, pop the highest, which is what makes
# PSH m ; POP m the identity.
u("G3",     SEQ="MAPMASK")

u("PSH_SP", ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="SP", SEQ="NEXT")
u(          MEM="WR", ICTL="IFROMIR", SEQ="MAPMASK")
u("PSH_LPC",ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="LPC", SEQ="NEXT")
u(          MEM="WR", ICTL="IFROMIR", SEQ="MAPMASK")
u("PSH_IX", ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="IX", SEQ="NEXT")
u(          MEM="WR", ICTL="IFROMIR", SEQ="MAPMASK")
u("PSH_AC", ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="AC", SEQ="NEXT")
u(          MEM="WR", ICTL="IFROMIR", SEQ="MAPMASK")

u("POP_AC", ARSRC="STACKR", SEQ="NEXT")
u(          MEM="RD", SPUP="U1", SEQ="NEXT")
u(          BSRC="DI", ALU="PASSB", RDST="AC", ICTL="IFROMIR", SEQ="MAPMASK")
u("POP_IX", ARSRC="STACKR", SEQ="NEXT")
u(          MEM="RD", SPUP="U1", SEQ="NEXT")
u(          BSRC="DI", ALU="PASSB", RDST="IX", ICTL="IFROMIR", SEQ="MAPMASK")
u("POP_LPC",ARSRC="STACKR", SEQ="NEXT")
u(          MEM="RD", SPUP="U1", SEQ="NEXT")
u(          ARSRC="DI", RDST="PC", LCTL="FROMDI", ICTL="IFROMIR", SEQ="MAPMASK")
u("POP_SP", ARSRC="STACKR", SEQ="NEXT")
u(          MEM="RD", SEQ="NEXT")
u(          BSRC="DI", ALU="PASSB", RDST="SP", ICTL="IFROMIR", SEQ="MAPMASK")

# CAL pushes first and forms the target afterwards, so it needs nowhere to keep
# it: the address sequences already load PC, and there are four of them because
# the exit differs by addressing mode.
u("CAL_PG", ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="LPC", SEQ="NEXT")
u(          MEM="WR", SEQ="JUMP", NA="JMP_PG")
u("CAL_IX", ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="LPC", SEQ="NEXT")
u(          MEM="WR", SEQ="JUMP", NA="JMP_IDX")
u("CAL_IN", ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="LPC", SEQ="NEXT")
u(          MEM="WR", SEQ="JUMP", NA="JMP_IN1")
u("CAL_XI", ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="LPC", SEQ="NEXT")
u(          MEM="WR", SEQ="JUMP", NA="JMP_IX1")
u("FETCH_I",MEM="RD", ARSRC="PCNEXT", ICTL="IFROMIR", SEQ="MAP")

# ---- interrupt entry --------------------------------------------------
# Interrupt entry.  The fetch that detected it suppressed the IR load and the
# increment, so PC still names the instruction thrown away, which is exactly
# what has to be pushed.  The vector entry is the device number, which comes
# from the priority encoder and therefore needs a bus source of its own.
u("IRQ",    ASRC="SP", ALU="DEC", RDST="SP", ARSRC="STACK", DOSRC="LPC",
            ICTL="ICLR", SEQ="NEXT")
u(          MEM="WR", SEQ="NEXT")
u(          BSRC="DEV", ALU="PASSB", ARSRC="ALU", SEQ="NEXT")
u(          MEM="RD", SEQ="NEXT")
u(          ARSRC="DI", RDST="PC", SEQ="JUMP", NA="FETCH")

u("IOT",    MEM="IO", ARSRC="PC", SEQ="JUMP", NA="FETCH")
u("TRAP",   ARSRC="PC", SEQ="JUMP", NA="FETCH")   # reserved opcodes: no-op for now


def assemble():
    words = []
    for m in U:
        kw = dict(m)
        if isinstance(kw.get("NA"), str):
            kw["NA"] = LBL[kw["NA"]]
        words.append(uword(**kw))
    return words


# --------------------------------------------------------------- map ROMs
def maps():
    """MAP1 is indexed by IR[17:12]: the opcode plus the two bits below it,
    which are the addressing mode for opcodes 0..11 and the group selector for
    OPR.  One dispatch therefore resolves all three."""
    ea = ["EA_ZP", "EA_IDX", "EA_IN1", "EA_IX1"]
    ja = ["JA_PG", "JA_IDX", "JA_IN1", "JA_IX1"]
    jz = ["JA_ZP", "JA_IDX", "JA_IN1", "JA_IX1"]
    m1 = []
    for op in range(16):
        for mm in range(4):
            if op <= 7:
                m1.append(LBL[ea[mm]])
            elif op == 9:                         # JMP resolves in the EA cycle
                m1.append(LBL[["JMP_PG", "JMP_IDX", "JMP_IN1", "JMP_IX1"][mm]])
            elif op == 8:                         # CAL: push, then the address
                m1.append(LBL[["CAL_PG", "CAL_IX", "CAL_IN", "CAL_XI"][mm]])
            elif op in (10, 11):                  # ISZ and DSZ keep the zero page
                m1.append(LBL[jz[mm]])
            elif op in (12, 13):
                m1.append(LBL["TRAP"])
            elif op == 14:
                m1.append(LBL["IOT"])
            else:
                m1.append(LBL[["FETCH_G", "FETCH_S", "G3", "TRAP"][mm]])
    m2 = []
    for op in range(16):
        m2.append({0: "OP_RD", 1: "OP_RD", 2: "OP_RD", 3: "OP_RD",
                   4: "OP_DAC", 5: "OP_RD", 6: "OP_SAD", 7: "OP_RD",
                   8: "OP_JMP", 9: "OP_JMP", 10: "OP_ISZ", 11: "OP_ISZ"}.get(op, "TRAP"))
    return m1, [LBL[x] for x in m2]


# --------------------------------------------------------------- ROM images
def rom_blob(words, data_bits):
    """LogicCircuit stores a memory as little endian cells of ceil(bits/8)
    bytes, trailing zeros omitted."""
    n = (data_bits + 7) // 8
    out = bytearray()
    for v in words:
        out += int(v).to_bytes(n, "little")
    while out and out[-1] == 0:
        out.pop()
    return base64.b64encode(bytes(out)).decode()


def images():
    cs = assemble()
    lo = [w & 0xFFFFFF for w in cs]
    hi = [(w >> 24) & 0xFFFFFF for w in cs]
    m1, m2 = maps()
    return {
        "CS low  (128 x 24)": rom_blob(lo, 24),
        "CS high (128 x 24)": rom_blob(hi, 24),
        "MAP1     (64 x 8)": rom_blob(m1, 8),
        "MAP2     (16 x 8)": rom_blob(m2, 8),
    }


def hex_files(prefix="rtl/"):
    """Emit $readmemh files for the Verilog model."""
    import os
    os.makedirs(prefix, exist_ok=True)
    cs = assemble()
    m1, m2 = maps()
    with open(prefix + "ucode.hex", "w") as f:
        for w in cs + [0] * (128 - len(cs)):
            f.write("%010x\n" % w)
    with open(prefix + "map1.hex", "w") as f:
        for v in m1:
            f.write("%02x\n" % v)
    with open(prefix + "map2.hex", "w") as f:
        for v in m2:
            f.write("%02x\n" % v)
    # the field layout, so the Verilog cannot drift from the assembler
    with open(prefix + "ufields.vh", "w") as f:
        f.write("// generated by ucode.py -- do not edit\n")
        for n, w, _ in FIELDS:
            lo, wd = POS[n]
            f.write("`define F_%-6s uw[%d:%d]\n" % (n, lo + wd - 1, lo))
        for (fld, sym), val in sorted(SYM.items()):
            f.write("`define %s_%-8s %d\n" % (fld, sym, val))
        f.write("`define UW_WIDTH %d\n" % UWIDTH)
        for k, v in sorted(LBL.items()):
            f.write("`define L_%-9s %d\n" % (k, v))
    return prefix


if __name__ == "__main__":
    cs = assemble()
    print("microword %d bit, %d microinstructions used of 128" % (UWIDTH, len(cs)))
    print("campi:", ", ".join("%s:%d" % (n, w) for n, w, _ in FIELDS))
    if len(sys.argv) > 1 and sys.argv[1] == "hex":
        print("scritti in", hex_files())
    elif len(sys.argv) > 1 and sys.argv[1] == "roms":
        for k, v in images().items():
            print("\n%s\n%s" % (k, v))
    else:
        for k, v in images().items():
            print("  %-20s %d base64 chars" % (k, len(v)))


# --------------------------------------------------------------- engine
class Micro:
    """Executes the control store against a memory, so the microprogram can be
    compared with sim.py rather than trusted."""

    def __init__(self, mem, io=None):
        self.m = mem
        self.io = io
        self.cs = assemble()
        self.map1, self.map2 = maps()
        self.ac = self.ix = self.t = self.di = self.do = 0
        self.sp = 0
        self.pc = 0
        self.ar = 0
        self.ir = 0
        self.l = 0
        self.i = 0
        self.msk = 0
        self.req = [False] * 8
        self.imask = 0xFF
        self.upc = LBL["FETCH"]
        self.cycles = 0
        self.instrs = 0
        self.halted = False
        self.bd = 0
        self.pgl = 0
        self.irq_dev = 0

    def reset(self):
        self.i = 0
        self.sp = 0
        self.pc = self.m[0] & A17
        self.ar = self.pc
        self.upc = LBL["FETCH"]

    # ---- the ALU, including the codes that read their function from IR ----
    def alu(self, op, a, b, cin=0):
        if op == SYM[("ALU", "FROMIR")]:
            # The ALU produces carry and overflow both; the decode picks which
            # one drives ALU_L, which is the whole difference between TAD and
            # TAS and is not visible in the four bit function field.
            name = {0: "ADD", 1: "ADDV", 2: "AND", 3: "XOR", 5: "PASSB",
                    7: "OR", 10: "ADD1", 11: "DEC"}.get((self.ir >> 14) & 0xF, "PASSB")
            if name == "ADDV":
                s = (a + b) & W
                v = 1 if ((a >> 17) & 1) == ((b >> 17) & 1) and ((s >> 17) & 1) != ((a >> 17) & 1) else 0
                return s, v
            op = SYM[("ALU", name)]
        n = ["ADD", "AND", "OR", "XOR", "PASSA", "PASSB", "SHL", "SHR",
             "ROL", "ROR", "CMA", "FROMIR", "DEC", "ADD1", "PASSB1", "G1"][op]
        if n == "G1":
            return self.group1(a)
        if n == "ADD1":
            s = a + b + 1
            return s & W, 1 if s > W else 0
        if n == "PASSB1":
            return (b + 1) & W, self.l
        if n == "ADD":
            s = a + b + cin
            return s & W, 1 if s > W else 0
        if n == "DEC":
            s = a + W + cin
            return s & W, 1 if s > W else 0
        if n == "AND":
            return a & b, self.l
        if n == "OR":
            return a | b, self.l
        if n == "XOR":
            return a ^ b, self.l
        if n == "PASSA":
            return a, self.l
        if n == "PASSB":
            s = b + cin
            return s & W, self.l
        if n == "CMA":
            return a ^ W, self.l
        raise NotImplementedError(n)

    def group1(self, a):
        """The operate group, in the order the specification fixes: clear,
        complement, increment, then shift or rotate."""
        w, l = self.ir, self.l
        ac = a
        if (w >> 11) & 1:
            ac = 0
        if (w >> 10) & 1:
            l = 0
        if (w >> 9) & 1:
            ac ^= W
        if (w >> 8) & 1:
            l ^= 1
        if (w >> 3) & 1:
            ac = (ac + 1) & W
        if (w >> 2) & 1:
            self.ix = (self.ix + 1) & W
        if (w >> 7) & 1:
            n = ((ac << 1) | l) & W
            l = (ac >> 17) & 1
            ac = n
        if (w >> 6) & 1:
            n = ((l << 17) | (ac >> 1)) & W
            l = ac & 1
            ac = n
        if (w >> 5) & 1:
            ac = (ac << 1) & W
        if (w >> 4) & 1:
            ac = ((ac >> 1) | (ac & 0o400000)) & W
        if w & 1:
            self.halted = True
        self.ac = ac
        self.l = l
        return ac, l

    def reg_of_ir(self):
        return "IX" if (self.ir >> 11) & 1 else "AC"

    def cycle(self):
        w = self.cs[self.upc]
        f = lambda k: ufield(w, k)

        # ---- interrupt check, only at the fetch, and it costs no cycle
        irq_now = False
        if self.upc in (LBL["FETCH"], LBL["FETCH_A"], LBL["FETCH_G"],
                        LBL["FETCH_S"], LBL["FETCH_I"]) and self.i:
            for d in range(1, 8):
                if self.req[d] and (self.imask >> d) & 1:
                    irq_now = True
                    self.irq_dev = d
                    break

        # ---- bus A
        asrc = ["NONE", "AC", "IX", "SP", "T", "PC", "FROMIR"][f("ASRC")]
        if asrc == "FROMIR":
            asrc = self.reg_of_ir()
        a = {"NONE": 0, "AC": self.ac, "IX": self.ix, "SP": self.sp,
             "T": self.t, "PC": (self.l << 17) | self.pc}[asrc]

        # ---- bus B
        b = {0: self.di, 1: self.ir & 0o3777, 2: self.ir & 0o7777,
             3: self.irq_dev}[f("BSRC")]

        r, lout = self.alu(f("ALU"), a, b)

        # ---- memory
        if f("MEM") == SYM[("MEM", "RD")]:
            self.bd = self.m[self.ar & A17] & W
            self.di = self.bd
        elif f("MEM") == SYM[("MEM", "WR")]:
            self.m[self.ar & A17] = self.do & W
        elif f("MEM") == SYM[("MEM", "IO")] and self.io:
            self.io(self)

        # DO selects straight from the register file rather than off a bus, so
        # a push can capture what it means to write while bus A carries SP
        ds = f("DOSRC")
        if ds == SYM[("DOSRC", "FROMIR")]:
            self.do = self.ix if (self.ir >> 11) & 1 else self.ac
        elif ds == SYM[("DOSRC", "LPC")]:
            self.do = (self.l << 17) | self.pc
        elif ds == SYM[("DOSRC", "ALU")]:
            self.do = r
        elif ds == SYM[("DOSRC", "AC")]:
            self.do = self.ac
        elif ds == SYM[("DOSRC", "IX")]:
            self.do = self.ix
        elif ds == SYM[("DOSRC", "SP")]:
            self.do = self.sp            # the value at the start, not the
                                         # decremented one: PSH SP pushes what
                                         # SP held when the instruction began
        # ---- writes from bus R, and the fetch's own IR load
        # A skip that turns out to be taken discards the word just read, the
        # same way the interrupt check discards it: suppress the IR load.
        skipping = (self.upc == LBL["FETCH_S"] and self.cond(f("CC")))
        fetching = self.upc in (LBL["FETCH"], LBL["FETCH_A"], LBL["FETCH_G"],
                                LBL["FETCH_S"], LBL["FETCH_I"])
        if fetching and not irq_now and not skipping:
            newir = self.bd
        else:
            newir = None

        dst = ["NONE", "AC", "IX", "SP", "T", "PC", "DO", "FROMIR"][f("RDST")]
        if dst == "FROMIR":
            dst = self.reg_of_ir()
        if dst == "AC":
            self.ac = r
        elif dst == "IX":
            self.ix = r
        elif dst == "SP":
            self.sp = r & 0xFFF
        elif dst == "T":
            self.t = r
        elif dst == "PC":
            pc_pending = True

        if f("ALU") == SYM[("ALU", "G1")]:
            dst = "NONE"
        if f("LCTL") == SYM[("LCTL", "FROMALU")]:
            self.l = lout
        elif f("LCTL") == SYM[("LCTL", "FROMDI")]:
            self.l = (self.di >> 17) & 1

        if f("ICTL") == SYM[("ICTL", "ICLR")]:
            self.i = 0
        elif f("ICTL") == SYM[("ICTL", "ISET")]:
            self.i = 1
        elif f("ICTL") == SYM[("ICTL", "IFROMIR")]:
            fld = (self.ir >> 9) & 3         # the I field of group 2 of OPR
            if fld == 1:
                self.i = 0
            elif fld == 2:
                self.i = 1

        if f("SPUP"):
            self.sp = (self.sp + 1) & 0xFFF      # a pop steps SP as it reads
        if f("ARSRC") == SYM[("ARSRC", "PCNEXT")] and not irq_now:
            self.pc = (self.pc + 1) & A17

        # ---- AR mux, four dedicated paths
        pc_pending = dst == "PC"
        ars = f("ARSRC")
        if ars == SYM[("ARSRC", "ALU")]:
            self.ar = r & A17
        elif ars == SYM[("ARSRC", "PC")]:
            self.ar = self.pc
        elif ars == SYM[("ARSRC", "DI")]:
            self.ar = self.di & A17
        elif ars == SYM[("ARSRC", "PCNEXT")]:
            self.ar = self.pc                 # already incremented this cycle
        elif ars == SYM[("ARSRC", "PAGE")]:
            self.ar = (self.pgl << 12) | (self.ir & 0o7777)
        elif ars == SYM[("ARSRC", "STACK")]:
            self.ar = 0x1000 | (r & 0xFFF)          # the decremented SP, for a push
        elif ars == SYM[("ARSRC", "STACKR")]:
            self.ar = 0x1000 | (self.sp & 0xFFF)    # SP as it stands, for a pop

        if pc_pending:
            self.pc = self.ar & A17
        if newir is not None:
            # the page of the instruction just read, latched before the
            # increment, because the concatenation wants that one
            self.pgl = ((self.pc - 1) >> 12) & 0x1F
            self.ir = newir
            self.msk = newir & 0xF
            self.instrs += 1

        self.cycles += 1

        # ---- sequencer
        seq = f("SEQ")
        if irq_now:
            self.upc = LBL["IRQ"]
            return
        if seq == SYM[("SEQ", "NEXT")]:
            self.upc += 1
        elif seq == SYM[("SEQ", "JUMP")]:
            self.upc = f("NA")
        elif seq == SYM[("SEQ", "MAP")]:
            nxt = self.map1[(self.ir >> 12) & 0x3F]
            self.upc = self.mask_entry() if nxt == LBL["G3"] else nxt
        elif seq == SYM[("SEQ", "MAP2")]:
            self.upc = self.map2[(self.ir >> 14) & 0xF]
        elif seq == SYM[("SEQ", "SKIPC")]:
            if self.cond(f("CC")):
                self.pc = (self.pc + 1) & A17
                self.ar = self.pc
            self.upc = LBL["FETCH"]
        elif seq == SYM[("SEQ", "SKIPF")]:
            if skipping:
                # PCINC has already stepped past the word being discarded, and
                # ARSRC has already pointed AR at the one after it
                self.upc = LBL["FETCH"]
            else:
                self.upc = self.map1[(self.ir >> 12) & 0x3F]
        elif seq == SYM[("SEQ", "BRANCH")]:
            self.upc = f("NA") if self.cond(f("CC")) else self.upc + 1
        elif seq == SYM[("SEQ", "MAP2")]:
            self.upc = self.map2[(self.ir >> 14) & 0xF]
        elif seq == SYM[("SEQ", "MAPMASK")]:
            if self.msk == 0:
                self.upc = LBL["FETCH_I"]
            elif not (self.ir >> 11) & 1:        # push walks upward
                for bit, lab in ((0, "PSH_SP"), (1, "PSH_LPC"),
                                 (2, "PSH_IX"), (3, "PSH_AC")):
                    if (self.msk >> bit) & 1:
                        self.msk &= ~(1 << bit)
                        self.upc = LBL[lab]
                        break
            else:                                 # pop walks downward
                for bit, lab in ((3, "POP_AC"), (2, "POP_IX"),
                                 (1, "POP_LPC"), (0, "POP_SP")):
                    if (self.msk >> bit) & 1:
                        self.msk &= ~(1 << bit)
                        self.upc = LBL[lab]
                        break
        else:
            self.upc = LBL["FETCH_I"]

    def mask_entry(self):
        """The priority encoder answers the dispatch in the fetch's own cycle:
        lowest bit set for a push, highest for a pop, and the bit is cleared as
        it is taken.  That is the progressive reduction, and it is why a stack
        instruction costs its population count and nothing else."""
        if self.msk == 0:
            return LBL["FETCH_I"]
        order = ((0, "PSH_SP"), (1, "PSH_LPC"), (2, "PSH_IX"), (3, "PSH_AC")) \
            if not (self.ir >> 11) & 1 else \
            ((3, "POP_AC"), (2, "POP_IX"), (1, "POP_LPC"), (0, "POP_SP"))
        for bit, lab in order:
            if (self.msk >> bit) & 1:
                self.msk &= ~(1 << bit)
                return LBL[lab]
        return LBL["FETCH_I"]

    def cond(self, cc):
        n = ["NEVER", "Z", "NZ", "G2", "IRQ", "MSK0"][cc]
        if n == "Z":
            return self.do == 0
        if n == "NZ":
            return (self.ac if not ((self.ir >> 11) & 1) else self.ix) != self.di
        if n == "G2":
            w = self.ir
            c = 0
            if w & 1:
                c |= 1 if self.ac == 0 else 0
            if (w >> 1) & 1:
                c |= 1 if self.l else 0
            if (w >> 2) & 1:
                c |= 1 if self.i else 0
            if (w >> 11) & 1:
                c ^= 1
            return bool(c)
        return False
