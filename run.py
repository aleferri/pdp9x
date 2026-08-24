#!/usr/bin/env python3
import struct
import sys
import time

from sim import CPU, MEMSZ, Halt, STACK_PAGE, SP_MASK, A, W


def load(path):
    d = open(path, 'rb').read()
    mem = [0] * MEMSZ
    assert len(d) % 4 == 0, "binary is not a whole number of 32-bit units"
    for i in range(0, len(d), 4):
        mem[i // 4] = struct.unpack('>I', d[i:i + 4])[0] & W
    return mem, len(d) // 4


# ---------------------------------------------------------------- unit tests
def asm_word(op, ind=0, idx=0, r=0, addr=0):
    return (op << 14) | (ind << 13) | (idx << 12) | (r << 11) | addr


def g3(d, ifield, mask):
    return 0x3C000 | (2 << 12) | (d << 11) | (ifield << 9) | mask


FAIL = []


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  FAIL %s  %s" % (name, detail))
        FAIL.append(name)


def t_stack_involution():
    """PSH m ; POP m must be the identity for every mask, SP included."""
    for mask in range(16):
        c = CPU()
        c.ac, c.ix, c.l, c.pc, c.sp = 0o123456, 0o765432, 1, 0o1000, 0o7000
        before = (c.ac, c.ix, c.l, c.pc, c.sp)
        c.m[0o1000] = g3(0, 0, mask)
        c.m[0o1001] = g3(1, 0, mask)
        c.step()
        c.step()
        after = (c.ac, c.ix, c.l, c.pc, c.sp)
        exp = (before[0], before[1], before[2], 0o1002, before[4])
        if mask & 2:                      # LPC popped -> pc comes from stack
            exp = (before[0], before[1], before[2], 0o1001, before[4])
        check("PSH/POP mask=%X involution" % mask, after == exp,
              "%s vs %s" % (oct_t(after), oct_t(exp)))


def oct_t(t):
    return tuple(oct(x) for x in t)


def t_sp_transfer():
    c = CPU()
    c.sp = 0o7000
    c.ac = 0o1234
    c.pc = 0
    c.m[0] = g3(0, 0, 0b1000)     # PSH AC
    c.m[1] = g3(1, 0, 0b0001)     # POP SP
    c.step()
    c.step()
    check("PSH AC; POP SP sets SP<-AC", c.sp == 0o1234, oct(c.sp))

    c = CPU()
    c.sp = 0o1234
    c.pc = 0
    c.m[0] = g3(0, 0, 0b0001)     # PSH SP
    c.m[1] = g3(1, 0, 0b1000)     # POP AC
    c.step()
    c.step()
    check("PSH SP; POP AC reads SP into AC", c.ac == 0o1234 and c.sp == 0o1234,
          "ac=%s sp=%s" % (oct(c.ac), oct(c.sp)))


def t_cal_ret():
    c = CPU()
    c.sp = 0o7000
    c.pc = 0o100
    c.l = 1
    c.m[0o100] = (8 << 14) | 0o200        # CAL 200
    c.m[0o200] = 0x3C000 | (1 << 10)      # CLL
    c.m[0o201] = g3(1, 0, 0b0010)         # RET
    c.step()
    check("CAL jumps", c.pc == 0o200, oct(c.pc))
    check("CAL pushes L,PC", c.m[c.saddr()] == (1 << 17) | 0o101, oct(c.m[c.saddr()]))
    c.step()
    c.step()
    check("RET restores PC", c.pc == 0o101, oct(c.pc))
    check("RET restores L", c.l == 1, c.l)


def t_irq_transparency():
    """An IRQ between TAD and SKL must not perturb the main program."""
    for fire in (False, True):
        c = CPU()
        c.sp = 0o7000
        c.pc = 0o100
        c.i = 1
        c.m[2] = 0o400                       # the timer is device 2
        c.m[0o100] = asm_word(0, addr=0o50)  # TAD 50
        c.m[0o101] = 0x3D000 | 2             # SKL
        c.m[0o102] = 0                       # (skipped or not)
        c.m[0o50] = 1
        c.ac = W                             # AC = -1, TAD 1 -> carry
        # handler clobbers AC, IX, L then returns
        c.m[0o400] = g3(0, 0, 0b1100)        # PSH AC,IX
        c.m[0o401] = 0x3C000 | (1 << 10) | (1 << 8)   # CLL CML -> L=1... force 0
        c.m[0o402] = 0x3C000 | (1 << 10)     # CLL  -> L = 0
        c.m[0o403] = g3(1, 0, 0b1100)        # POP AC,IX
        c.m[0o404] = g3(1, 2, 0b0010)        # RTI
        c.step()                             # TAD -> AC=0, L=1
        if fire:
            c.req[2] = True
            c.check_irq()
            for _ in range(5):
                c.step()
            c.req[2] = False
        check("IRQ transparency (fire=%s): L" % fire, c.l == 1, c.l)
        check("IRQ transparency (fire=%s): AC" % fire, c.ac == 0, oct(c.ac))
        check("IRQ transparency (fire=%s): I" % fire, c.i == 1, c.i)
        c.step()                             # SKL
        check("IRQ transparency (fire=%s): PC" % fire, c.pc == 0o103, oct(c.pc))


def t_interrupt_mask():
    """Device n drives vector entry n, and the mask gates each device on its
    own without touching the others."""
    c = CPU()
    c.i = 1
    c.req[3] = True
    c.req[5] = True
    c.m[3] = 0o400
    c.m[5] = 0o500
    check("device 3 and device 5 request independently",
          c.req[3] and c.req[5])
    check("lower device number wins", c.check_irq() and c.pc == 0o400)
    c.pc = 0o1000
    c.i = 1
    c.imask &= ~(1 << 3)
    check("masking one leaves the other through",
          c.check_irq() and c.pc == 0o500)
    c.pc = 0o1000
    c.i = 1
    c.imask &= ~(1 << 5)
    check("masking both silences the pair", not c.check_irq())
    c.imask = 0xFF
    check("a masked request is hidden, not lost", c.check_irq())

    c = CPU()
    c.i = 1
    c.req[2] = True
    c.m[2] = 0o400
    check("device n takes vector entry n", c.check_irq() and c.pc == 0o400)
    c = CPU()
    c.i = 1
    c.req[2] = True
    c.imask &= ~(1 << 2)
    check("a masked request is not taken", not c.check_irq())


def t_skip_polarity():
    c = CPU()
    c.pc = 0
    c.ac = 0
    c.l = 1
    c.i = 0
    c.m[0] = 0x3D000 | 0b011      # SKZ + SKL, OR
    c.step()
    check("G2 OR of two true conditions skips", c.pc == 2, c.pc)
    c.pc = 0
    c.m[0] = 0x3D000 | (1 << 11) | 0b011   # N + Z + L  => NOR
    c.step()
    check("G2 with N over 2 conditions is NOR (documented gotcha)",
          c.pc == 1, c.pc)


def run_tests():
    print("CPU unit tests")
    t_stack_involution()
    t_sp_transfer()
    t_cal_ret()
    t_irq_transparency()
    t_interrupt_mask()
    t_skip_polarity()
    print()


# ---------------------------------------------------------------- sieve
def run_sieve(path, iters=None, timer=0):
    mem, n = load(path)
    c = CPU(mem)
    c.reset()
    if iters is not None:
        import subprocess, re
        out = subprocess.run(['casmeleon', '-lang=pdp9x.casm', '-byteSize=32',
                              'asm/sieve.s'], capture_output=True, text=True).stdout
        sym = {m.group(1): int(m.group(2)) // 4
               for m in re.finditer(r'(\w+)@(\d+)', out)}
        c.m[sym['NITER']] = (-iters) & W
    if timer:
        c.timer_period = timer
    t0 = time.time()
    st = c.run()
    dt = time.time() - t0
    return c, st, dt


if __name__ == '__main__':
    run_tests()
    print("Sieve")
    c, st, dt = run_sieve('bin/sieve.bin', timer=997)
    print("  status      :", st)
    print("  output      :", c.out)
    print("  ticks       :", c.m[9])
    print("  stack low   : 0x%X" % (STACK_PAGE | c.sp))
    print("  instructions: %d" % c.instrs)
    print("  mem cycles  : %d" % c.cycles)
    print("  wall        : %.2fs" % dt)
    if FAIL:
        print("\n%d unit test failures" % len(FAIL))
        sys.exit(1)
