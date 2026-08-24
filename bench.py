#!/usr/bin/env python3
"""Run every sample program and report what it did.

    python3 bench.py            everything
    python3 bench.py sieve      just the sieve variants
    python3 bench.py console    just the console drivers
    python3 bench.py checks     just the CPU unit tests
"""
import struct
import sys

from sim import CPU, MEMSZ, W
from machine import Machine


def load(path):
    d = open(path, 'rb').read()
    mem = [0] * MEMSZ
    for i in range(0, len(d), 4):
        mem[i // 4] = struct.unpack('>I', d[i:i + 4])[0] & W
    return mem


def rule(title):
    print("\n" + title)
    print("-" * len(title))


# ---------------------------------------------------------------- sieve
def symbols(src):
    """Ask the assembler where the labels ended up, rather than hardcoding
    addresses that move whenever the zero page is rearranged."""
    import subprocess, re
    out = subprocess.run(['casmeleon', '-lang=pdp9x.casm', '-byteSize=32', src],
                         capture_output=True, text=True).stdout
    return {m.group(1): int(m.group(2)) // 4 for m in re.finditer(r'(\w+)@(\d+)', out)}



def sieve(iters=1):
    rule("Byte sieve, 8190 flags, %d iteration(s)" % iters)
    print("%-9s %-12s %9s %10s %6s  %s"
          % ("program", "result", "instrs", "cycles", "CPI", "what changed"))
    notes = {
        'sieve': "baseline",
        'sieve2': "loop var in IX, TADX + SXD",
        'sieve3': "biased index, TASX carries the bound",
        'sieve4': "IAC / IXC instead of TAD ONE",
    }
    base = None
    for name in ('sieve', 'sieve2', 'sieve3', 'sieve4'):
        c = CPU(load('bin/%s.bin' % name))
        c.reset()
        c.m[symbols('asm/%s.s' % name)['NITER']] = (-iters) & W
        c.timer_period = 10 ** 9
        st = c.run()
        if base is None:
            base = c.cycles
        delta = "" if c.cycles == base else "  (%+.1f%%)" % (100 * (c.cycles - base) / base)
        ok = "%s primes" % c.out[0] if c.out == [1899] else "WRONG: %s" % c.out
        print("%-9s %-12s %9d %10d %6.2f  %s%s"
              % (name, ok, c.instrs, c.cycles, c.cycles / c.instrs, notes[name], delta))
        assert st == "halt" and c.out == [1899], "sieve %s failed" % name


# ---------------------------------------------------------------- console
def console():
    rule("Console drivers, 24 lines through a 16x32 blitter")
    for name, note in (('driver', "buffered, replay on scroll-done"),
                       ('driver2', "buffered + IXC")):
        m = Machine(load('bin/%s.bin' % name))
        m.reset()
        st = m.run(limit=30_000_000)
        print("%-9s instrs %6d  cycles %7d  scrolls %2d  "
              "lost(scroll) %d  lost(spacing) %d  fb reads %d   %s"
              % (name, m.instrs, m.cycles, m.scrolls, m.dropped,
                 m.too_fast, len(m.fb_reads), note))
        assert st == "halt", "%s did not halt" % name
    print()
    m = Machine(load('bin/driver2.bin'))
    m.reset()
    m.run(limit=30_000_000)
    print("+" + "-" * 32 + "+")
    for r in m.console():
        print("|" + r + "|")
    print("+" + "-" * 32 + "+")

    rule("Blitter spacing rule, deliberately violated")
    m = Machine(load('bin/spacing.bin'))
    m.reset()
    m.run(limit=20_000_000)
    print("four back-to-back writes to the framebuffer:")
    print("  writes lost because the cell counter was still drawing: %d" % m.too_fast)
    print("  first offenders (pc, cycles short): %s" % m.violations[:3])
    assert m.too_fast > 0, "the spacing checker did not fire"

    rule("Arithmetic runtime: multiply, divide, decimal")
    sym = symbols('asm/arith.s')
    c = CPU(load('bin/arith.bin'))
    c.reset()
    c.run(limit=5_000_000)
    fails = c.m[sym['FAILS']] if 'FAILS' in sym else -1
    print("mul/div vectors failing: %d of 9  (signed, both signs, overflow, /0)" % fails)
    print("multiply exits as soon as the multiplier runs dry, so cost tracks")
    print("the significant bits of the smaller operand, not a fixed 18.")
    assert fails == 0, "arithmetic self test failed"

    rule("FOCAL subset: SET, TYPE, IF, GOTO, QUIT")
    m = Machine(load('bin/focal.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    print("%d instructions, %d cycles" % (m.instrs, m.cycles))
    print("+" + "-" * 32 + "+")
    for r in m.console()[:6]:
        print("|" + r + "|")
    print("+" + "-" * 32 + "+")
    assert st == "halt", "focal did not halt"
    assert m.console()[0].startswith("SUM TO 7 IS 28"), "focal produced the wrong result"

    m = Machine(load('bin/focal_do.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    print("DO, nested one level: %d instructions -> %s"
          % (m.instrs, m.console()[0].rstrip()))
    assert st == "halt" and m.console()[0].startswith("TOTAL 2"), "DO failed"

    m = Machine(load('bin/focal_ask.bin'))
    m.reset()
    m.kbd_input = [(c, 0) for c in "12\n30\n-4\n"]
    st = m.run(limit=20_000_000)
    print("ASK, keyboard through IOT: %s / %s"
          % (m.console()[2].rstrip(), m.console()[5].rstrip()))
    assert st == "halt" and m.console()[5].startswith("SUM 26"), "ASK failed"

    m = Machine(load('bin/focal_for.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    print("FOR: %s / %s / %s" % (m.console()[0].rstrip(), m.console()[1].rstrip(),
                                 m.console()[2].rstrip()))
    assert st == "halt" and m.console()[0].startswith("SUM 1..5 = 15"), "FOR failed"
    assert m.console()[1].startswith("10 7 4 1"), "FOR with a negative step failed"
    assert m.console()[2].startswith("EVEN SUM 20"), "FOR around DO failed"

    m = Machine(load('bin/focal_func.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    exp = {'A': 7, 'B': -1, 'C': 0, 'D': 1, 'E': 12, 'F': 12, 'G': 3, 'H': 9}
    bad = [r.rstrip() for r in m.console()[:9]
           if r.strip() and r[0] in exp and r.rstrip()[2:] != str(exp[r[0]])]
    print("functions: %d of 8 correct  (FSQT(FABS(0-81)) = %s)"
          % (8 - len(bad), m.console()[7].rstrip()[2:]))
    assert st == "halt" and not bad, "functions failed"

    for label, keys, echo in (("plain", [('4', 0), ('2', 0), ('\n', 0)], "42"),
                              ("shift", [('a', 1), ('\n', 0)], "A"),
                              ("ctrl", [('a', 2), ('\n', 0)], chr(1))):
        m = Machine(load('bin/focal_keys.bin'))
        m.reset()
        m.kbd_input = keys
        st = m.run(limit=20_000_000)
        got = m.console()[0].rstrip()[2:2 + len(echo)]   # past the "N:" prompt
        print("keyboard %-6s raw+modifiers reconstruct to %r" % (label, got))
        assert st == "halt" and got == echo, "keyboard %s failed" % label

    m = Machine(load('bin/focal_types.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    got = [m.console()[k].rstrip() for k in range(3)]
    print("declared types: %s" % " | ".join(got))
    assert st == "halt", "types did not halt"
    assert got[0] == "HELLO HELLO 1234 LEN 5", "string declaration failed"
    assert got[1] == "C IS 1234", "declaration with assignment failed"
    assert got[2] == "SUM 1178", "string read as a number failed"

    m = Machine(load('bin/focal_tyerr.bin'))
    m.reset()
    st = m.run(limit=2_000_000)
    print("unimplemented type rejected: %r" % m.console()[0].rstrip())
    assert st == "halt" and m.console()[0].rstrip() == "?F", "float should be refused"

    m = Machine(load('bin/focal_more.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    got = [m.console()[k].rstrip() for k in range(5)]
    print("power and short IF: %s" % " | ".join(got))
    assert st == "halt" and got == ["A 1024", "B 1", "C 18",
                                    "D ZERO ARM", "E FELL THROUGH"], "power/IF failed"

    m = Machine(load('bin/focal_arr.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    got = [m.console()[k].rstrip() for k in range(3)]
    print("subscripts: %s" % " | ".join(got))
    assert st == "halt" and got == ["A(3) 9 A(9) 81", "SUM 285",
                                    "A(3) NOW 99"], "arrays failed"

    m = Machine(load('bin/focal_brk.bin'))
    m.reset()
    m.kbd_input = [('c', 2)]
    st = m.run(limit=5_000_000)
    print("control C stops a running program: %r" % m.console()[0].rstrip())
    assert st == "halt" and m.console()[0].rstrip() == "?C", "break failed"

    m = Machine(load('bin/focal_int.bin'))
    m.reset()
    m.kbd_input = [(c, 0) for c in
                   '10 TYPE "ONE", !\n30 TYPE "THREE", !\n20 TYPE "TWO", !\n'
                   '40 QUIT\n20 TYPE "TWO BIS", !\n30\nWRITE\nGOTO 10\nQUIT\n']
    st = m.run(limit=30_000_000)
    rows = [r.rstrip() for r in m.console()]
    print("command level: listing %s -> ran %s"
          % (rows[7:10], rows[11:13]))
    assert st == "halt", "command level did not halt"
    assert rows[7:10] == ['10 TYPE "ONE", !', '20 TYPE "TWO BIS", !', '40 QUIT'], \
        "line editing failed"
    assert rows[11:13] == ["ONE", "TWO BIS"], "running the typed program failed"

    m = Machine(load('bin/focal_loop.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    print("loop program: %d instructions, %d cycles" % (m.instrs, m.cycles))
    assert st == "halt" and m.console()[0].startswith("COUNTED TO 40"), "loop failed"

    rule("Returning the link, and the skip return")
    c = CPU(load('bin/return_link.bin'))
    c.reset()
    c.run(limit=100000)
    res = c.m[symbols('asm/return_link.s')['RES']]
    print("cases passed: %d of 3  (set L, clear L, skip return)" % res)
    assert res == 3, "return-link demo failed"


# ---------------------------------------------------------------- checks
def checks():
    import run as unit
    unit.run_tests()
    if unit.FAIL:
        raise SystemExit("%d unit test failures" % len(unit.FAIL))
    print("all CPU invariants hold")


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    iters = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    if what in ('all', 'checks'):
        checks()
    if what in ('all', 'sieve'):
        sieve(iters)
    if what in ('all', 'console'):
        console()
    print()
