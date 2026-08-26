"""18-bit accumulator machine, PDP-9-ish. Simulator core."""

W = 0o777777          # 18-bit word mask
A = 0x1FFFF           # 17-bit address mask
MEMSZ = 1 << 17

OP_TAD, OP_TAS, OP_AND, OP_XOR = 0, 1, 2, 3
OP_DAC, OP_LAC, OP_SAD, OP_IOR = 4, 5, 6, 7
OP_CAL, OP_JMP, OP_ISZ, OP_DSZ = 8, 9, 10, 11
OP_IO, OP_OPR = 14, 15

G1, G2, G3 = 0, 1, 2

STACK_PAGE = 1 << 12  # stack lives in page 1: 0x1000..0x1FFF
SP_MASK = 0xFFF       # SP is 12 bits; the 6 high address bits are 000001


class Halt(Exception):
    pass


class CPU:
    def __init__(self, mem=None, trace=False):
        self.m = mem if mem is not None else [0] * MEMSZ
        self.ac = 0
        self.ix = 0
        self.l = 0
        self.pc = 0
        self.sp = 0
        self.i = 0                 # interrupt enable
        self.req = [False] * 8     # one request per device
        # The interrupt mask is CPU state, not device state: one bit per
        # device, saying whether that peripheral is let through.  Device 0 is
        # the processor itself, which is why vector entry 0 is reset rather
        # than an interrupt, and why bit 0 of the mask is spare.
        self.imask = 0xFF
        self.cycles = 0
        self.instrs = 0
        self.trace = trace
        self.out = []
        self.waiting = False
        self.timer_on = False
        self.timer_period = 0
        self.timer_ctr = 0

    # ---- reset -----------------------------------------------------
    def reset(self):
        self.i = 0
        self.sp = 0
        self.pc = self.m[0] & A

    # ---- memory ------------------------------------------------------
    # Timing: an opcode fetch is 1 cycle.  A data access is 2: one cycle to
    # form the address register, one to hold the read or write.  A jump
    # spends 1 extra cycle computing its target.
    FETCH_CYCLES = 1
    DATA_CYCLES = 2
    BRANCH_CYCLES = 1     # folding EXEC into the next fetch is impossible
                          # whenever PC moves other than by the plain increment

    def fetch(self, a):
        self.cycles += self.FETCH_CYCLES
        return self.m[a & A] & W

    def rd(self, a):
        self.cycles += self.DATA_CYCLES
        return self.m[a & A] & W

    def wr(self, a, v):
        self.cycles += self.DATA_CYCLES
        self.m[a & A] = v & W

    # ---- effective address ----------------------------------------
    def ea(self, ind, idx, addr):
        a = addr
        if ind:
            a = self.rd(a) & A
        if idx:
            a = (a + self.ix) & A
        return a

    # ---- stack primitives -----------------------------------------
    def saddr(self):
        return STACK_PAGE | self.sp

    def push(self, v):
        self.sp = (self.sp - 1) & SP_MASK
        self.wr(self.saddr(), v)

    def pop(self):
        v = self.rd(self.saddr())
        self.sp = (self.sp + 1) & SP_MASK
        return v

    def push_lpc(self, pc):
        self.push(((self.l & 1) << 17) | (pc & A))

    # ---- interrupt entry -------------------------------------------
    def pending(self):
        """Any device flag at all.  The mask decides which requests may
        interrupt; it does not decide what ends a WAIT, because a program that
        waits for a device it has masked off still means to be woken by it --
        that is the whole reason to mask a device and wait for it rather than
        take its vector."""
        return any(self.req[1:8])

    def check_irq(self):
        if not self.i:
            return False
        for n in range(1, 8):        # device n drives vector entry n
            if self.req[n] and (self.imask >> n) & 1:
                self.push_lpc(self.pc)
                self.i = 0
                self.pc = self.rd(n) & A
                self.cycles += self.BRANCH_CYCLES
                return True
        return False

    # ---- one instruction -------------------------------------------
    def step(self):
        self.instrs += 1
        ipc = self.pc
        w = self.fetch(self.pc)
        self.pc = (self.pc + 1) & A
        op = (w >> 14) & 0xF

        if op <= OP_IOR:
            ind = (w >> 13) & 1
            idx = (w >> 12) & 1
            r = (w >> 11) & 1
            addr = w & 0o3777
            self.mem_ref(op, r, self.ea(ind, idx, addr))
        elif op <= OP_DSZ:
            ind = (w >> 13) & 1
            idx = (w >> 12) & 1
            addr = w & 0o7777
            if op <= OP_JMP and not ind and not idx:
                ea = (ipc & 0x1F000) | addr   # PC-page, page of THIS instruction
            else:
                ea = self.ea(ind, idx, addr)
            if op <= OP_JMP:              # CAL and JMP always reload PC
                self.cycles += self.BRANCH_CYCLES
            self.jump_class(op, ea)
        elif op == OP_IO:
            self.io(w & 0o37777)
        else:
            self.opr(w)

    def skip(self):
        self.pc = (self.pc + 1) & A
        self.cycles += self.BRANCH_CYCLES

    # ---- opcodes 0..7 ----------------------------------------------
    def mem_ref(self, op, r, ea):
        reg = self.ix if r else self.ac
        if op == OP_DAC:
            self.wr(ea, reg)
            return
        if op == OP_LAC:
            v = self.rd(ea)
            if r:
                self.ix = v
            else:
                self.ac = v
            return
        if op == OP_SAD:
            # The comparison decides a skip, so its result cannot be folded
            # into the next fetch the way an ALU result bound for a register
            # can: the fetch address is not known until the compare is done.
            # Four cycles either way, and skip() already charges one.
            if self.rd(ea) != reg:
                self.skip()
            else:
                self.cycles += self.BRANCH_CYCLES
            return
        v = self.rd(ea)
        if op == OP_TAD:
            s = reg + v
            self.l = 1 if s > W else 0
            res = s & W
        elif op == OP_TAS:
            s = reg + v
            res = s & W
            sa = (reg >> 17) & 1
            sb = (v >> 17) & 1
            sr = (res >> 17) & 1
            self.l = 1 if (sa == sb and sr != sa) else 0
        elif op == OP_AND:
            res = reg & v
        elif op == OP_XOR:
            res = reg ^ v
        elif op == OP_IOR:
            res = reg | v
        if r:
            self.ix = res
        else:
            self.ac = res

    # ---- opcodes 8..11 ---------------------------------------------
    def jump_class(self, op, ea):
        if op == OP_CAL:
            self.push_lpc(self.pc)
            self.pc = ea
        elif op == OP_JMP:
            self.pc = ea
        elif op == OP_ISZ:
            v = (self.rd(ea) + 1) & W
            self.wr(ea, v)
            if v == 0:
                self.skip()
        elif op == OP_DSZ:
            v = (self.rd(ea) - 1) & W
            self.wr(ea, v)
            if v == 0:
                self.skip()

    # ---- IO ---------------------------------------------------------
    #Device 0 is the processor itself: its only register is the interrupt mask
    def io_cpu(self, f):
        dev = (f >> 11) & 7
        if dev != 0:
            return False
        sub = (f >> 8) & 7
        iop1, iop2, iop4, cla = f & 1, (f >> 1) & 1, (f >> 2) & 1, (f >> 3) & 1
        if cla:
            self.ac = 0
        if iop2 and sub == 0:
            self.ac |= self.imask
        # IOP1 tests a flag and skips, IOP4 moves data or acts: the interrupt
        # state skips belong to the first, not nested under the second.
        if iop1:
            if sub == 4 and self.i:
                self.skip()
            elif sub == 5 and not self.i:
                self.skip()
        if iop4:
            if sub == 0:
                self.imask = self.ac & 0xFF
            elif sub == 1:
                self.imask |= self.ac & 0xFF
            elif sub == 2:
                self.imask &= ~self.ac & 0xFF
            elif sub == 3:
                # Stop fetching until a request arrives.  A polling loop burns
                # an instruction every couple of cycles for no work; this burns
                # cycles without instructions, which is what waiting is.
                self.waiting = True
        return True

    # Device 5 is the bare-CPU test harness: a coarse timer and a print port,
    # used by the programs that run without the device model in machine.py.
    def io(self, f):
        if self.io_cpu(f):
            return
        if (f >> 11) & 7 != 5:
            return
        sub = (f >> 8) & 7
        if sub == 0:
            self.timer_on = True
        elif sub == 1:
            self.timer_on = False
        elif sub == 2:
            self.out.append(self.ac)
        elif sub == 3:
            self.req[2] = False

    # ---- OPR --------------------------------------------------------
    def opr(self, w):
        g = (w >> 12) & 3
        if g == G1:
            self.opr_g1(w)
        elif g == G2:
            self.opr_g2(w)
        elif g == G3:
            self.opr_g3(w)

    def opr_g1(self, w):
        if (w >> 11) & 1:            # CLA
            self.ac = 0
        if (w >> 10) & 1:            # CLL
            self.l = 0
        if (w >> 9) & 1:             # CMA
            self.ac ^= W
        if (w >> 8) & 1:             # CML
            self.l ^= 1
        if (w >> 3) & 1:             # IAC  AC + 1; L untouched
            self.ac = (self.ac + 1) & W
        if (w >> 2) & 1:             # IXC  IX + 1; L untouched
            self.ix = (self.ix + 1) & W
        if (w >> 7) & 1:             # RLA  rotate {L,AC} left
            n = ((self.ac << 1) | self.l) & W
            self.l = (self.ac >> 17) & 1
            self.ac = n
        if (w >> 6) & 1:             # RRA  rotate {L,AC} right
            n = ((self.l << 17) | (self.ac >> 1)) & W
            self.l = self.ac & 1
            self.ac = n
        if (w >> 5) & 1:             # SHA  shift left; L untouched
            self.ac = (self.ac << 1) & W
        if (w >> 4) & 1:             # SRA  shift right arithmetic; L untouched
            self.ac = ((self.ac >> 1) | (self.ac & 0o400000)) & W
        if w & 1:                    # HLT
            raise Halt()

    def opr_g2(self, w):
        n = (w >> 11) & 1
        c = 0
        if w & 1:
            c |= 1 if self.ac == 0 else 0
        if (w >> 1) & 1:
            c |= 1 if self.l else 0
        if (w >> 2) & 1:
            c |= (self.ac >> 17) & 1        # the sign, which DEC had and we
                                            # had left out
        if n:
            c ^= 1
        if c:
            self.skip()

    def opr_g3(self, w):
        d = (w >> 11) & 1
        ifield = (w >> 9) & 3
        mask = w & 0xF
        if d == 0:                   # PUSH, bit0 -> bit3
            sp0 = self.sp
            for b, get in ((0, lambda: sp0),
                           (1, lambda: ((self.l & 1) << 17) | (self.pc & A)),
                           (2, lambda: self.ix),
                           (3, lambda: self.ac)):
                if (mask >> b) & 1:
                    self.push(get())
        else:                        # POP, bit3 -> bit0
            for b in (3, 2, 1, 0):
                if not ((mask >> b) & 1):
                    continue
                # Three cycles, not two: the address, the read, and the
                # transfer.  A word read from memory reaches DI at the clock
                # edge, so it can only leave for a register the cycle after,
                # and the stack address cycle has nothing to overlap with.
                self.cycles += self.BRANCH_CYCLES
                if b == 3:
                    self.ac = self.pop()
                elif b == 2:
                    self.ix = self.pop()
                elif b == 1:
                    v = self.pop()
                    self.l = (v >> 17) & 1
                    self.pc = v & A
                    self.cycles += self.BRANCH_CYCLES
                else:
                    self.sp = self.rd(self.saddr()) & SP_MASK  # dest wins, no ++
        if ifield == 1:
            self.i = 0
        elif ifield == 2:
            self.i = 1

    # ---- run ---------------------------------------------------------
    def run(self, limit=200_000_000):
        n = 0
        try:
            while n < limit:
                if self.timer_on:
                    self.timer_ctr += 1
                    if self.timer_ctr >= self.timer_period:
                        self.timer_ctr = 0
                        self.req[2] = True
                if self.waiting:
                    # WAIT costs cycles and no instructions.  An interrupt ends
                    # it; so does a request the mask lets through, because a
                    # program that waits with interrupts off means to resume.
                    self.cycles += 1
                    if self.check_irq() or self.pending():
                        self.waiting = False
                    n += 1
                    continue
                self.check_irq()
                self.step()
                n += 1
        except Halt:
            return "halt"
        return "limit"
