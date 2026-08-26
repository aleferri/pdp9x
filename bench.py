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

    # The FOR loop decides whether to continue by comparing two signs, which
    # used to mean extracting both.  Two signs agree exactly when their XOR is
    # not negative, so one skip settles it -- and this is where a sign error
    # hides, so the edges are here: a step that crosses zero, a loop that lands
    # exactly on its limit, and two that must not run at all.
    m = Machine(load('bin/focal_fort.bin'))
    m.reset()
    st = m.run(limit=40_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    print("FOR edges: %s" % " ".join(r.split(' ')[1] for r in rows[:8]))
    assert st == "halt", "fort did not finish"
    for r in rows:
        if 'ATTESO' not in r:
            continue
        got, want = r.split(' ')[1], r.split('ATTESO ')[1]
        assert got == want, "FOR edges: %s" % r

    # The skip group with the conditions the 18-bit family had: the sign on the
    # bit that skip-on-interrupts-enabled used to hold, and that one moved into
    # the IO group under device 0.  Nine cases: both polarities of the sign,
    # the two combinations, and the relocated interrupt-state skips.
    c = CPU(load('bin/skiptest.bin'))
    c.reset()
    c.timer_period = 10 ** 9
    st = c.run(limit=100_000)
    print("skip group: %s" % ("all nine cases pass" if c.out == [1] else "FAILED %s" % c.out))
    assert st == "halt" and c.out == [1], "skip group failed: %s" % c.out

    # WAIT: device 0, sub-function 3.  Waiting is not halting -- the clock runs
    # and the fetch does not, so the cost is cycles without instructions.  The
    # blitter has no interrupt line, so this cannot replace the scroll poll; it
    # is for the waits that a device can end, which means the timer and the
    # keyboard.
    c = CPU(load('bin/waittest.bin'))
    c.reset()
    c.timer_period = 500
    st = c.run(limit=100_000)
    print("WAIT: %d instructions, %d cycles" % (c.instrs, c.cycles))
    assert st == "halt", "wait did not finish"
    assert c.instrs == 4, "wait executed %d instructions, expected 4" % c.instrs
    assert c.cycles > 400, "wait did not actually stall: %d cycles" % c.cycles

    # and with nothing able to wake it, the wait holds: the program's HTON arms
    # the harness timer, so the period has to be pushed past the run to see it
    c = CPU(load('bin/waittest.bin'))
    c.reset()
    c.timer_period = 10 ** 9
    st = c.run(limit=5_000)
    assert st == "limit" and c.instrs == 2, \
        "wait should hold with nothing to wake it, got %d instructions" % c.instrs

    # MUL36 and DIV36: the thirty-six bit pair that fixed point needs.  The
    # last vector's true quotient does not fit a word, so it checks the
    # documented truncation rather than an exact answer.
    c = CPU(load('bin/m36test.bin'))
    c.reset()
    c.timer_period = 10 ** 9
    c.run(limit=20_000_000)
    o = c.out
    vec = ((1000, 1000, 1000), (2897, 15885, 131072), (2897, 252, 1024),
           (100000, 3, 7), (131071, 131071, 131071), (262143, 262143, 65536),
           (5, 7, 3), (15885, 15885, 131072))
    bad = 0
    for i, (a, b, d) in enumerate(vec):
        hi, lo, q, r = o[4 * i:4 * i + 4]
        if (hi << 18) | lo != a * b:
            bad += 1
        if q != (a * b // d) & 0o777777 or r != a * b % d:
            bad += 1
    print("36-bit mul/div: %d checks failing of %d" % (bad, 2 * len(vec)))
    assert bad == 0, "36-bit primitives failed"
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

    # Two programs that are historical rather than synthetic.  Hamurabi began
    # as The Sumer Game, in FOCAL on a PDP-8 in 1968; Jim Storer's Lunar
    # Landing Game was FOCAL on a PDP-8 in 1969.  Both were converted to BASIC
    # by David Ahl afterwards, which is how most people met them.
    # Two size classes for string bodies, eight words and 256, with free lists.
    # The loop matters more than the single assignments: without recycling, a
    # bump allocator would grow the heap on every reassignment.
    # The functions return a word and used to leave ACH alone, so FABS of a
    # negative came back negative -- the high half still held the operand's
    # sign.  They are called rather than jumped to now, so one widening covers
    # all of them.
    m = Machine(load('bin/focal_fnt.bin'))
    m.reset()
    st = m.run(limit=40_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    print("functions in wide expressions: %s" % " | ".join(rows[2:6]))
    assert st == "halt", "fnt did not finish"
    for r in rows:
        if 'ATTESO' not in r:
            continue
        got, want = r.split(' ')[1], r.split('ATTESO ')[1]
        assert got == want, "functions in wide expressions: %s" % r

    # The evaluator now carries thirty-six bits, so every ordinary expression
    # goes through the widened path.  These are the shapes that broke while it
    # was being converted: a bare variable, and a variable inside a product.
    m = Machine(load('bin/focal_exprt.bin'))
    m.reset()
    st = m.run(limit=30_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    want = ["a 7", "b 10", "c 4", "d 21", "e 7", "f 7", "g 21", "h 16"]
    print("expressions: %s" % " ".join(rows[:8]))
    assert st == "halt" and rows[:8] == want, "expressions: %s" % rows[:8]

    # Type 1, the thirty-six bit integer.  Storage and printing are done; the
    # expression that feeds it is still eighteen bits wide, so a literal beyond
    # a word truncates before WIDEN ever sees it.  That is the ACH channel's
    # job, not this one's.
    m = Machine(load('bin/focal_long.bin'))
    m.reset()
    st = m.run(limit=30_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    print("36-bit type: %s" % " | ".join(rows[:5]))
    assert st == "halt", "long did not finish"
    for r in rows:
        if 'ATTESO' not in r:
            continue
        got, want = r.split(' ')[1], r.split('ATTESO ')[1]
        assert got == want, "long: %s" % r

    m = Machine(load('bin/focal_grow.bin'))
    m.reset()
    st = m.run(limit=40_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    print("string classes: %s" % " | ".join(rows[:4]))
    assert st == "halt", "grow did not finish"
    for r in rows[:4]:
        if 'ATTESO' in r:
            got, want = r.split('LEN ')[1].split(' ATTESO ')
            assert got.strip() == want.strip(), "grow: %s" % r

    # The descriptor carries a capacity, so a subscript past the end is an
    # error where it used to run into whatever followed the array.
    m = Machine(load('bin/focal_bounds.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    print("array bounds: %s" % " | ".join(rows[:2]))
    assert st == "halt" and rows[1] == "?B", "bounds check did not fire"
    assert not any('NON DOVREBBE' in r for r in rows), "execution continued past ?B"

    m = Machine(load('bin/focal_twoch.bin'))
    m.reset()
    st = m.run(limit=30_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    print("two-character names: %s" % " | ".join(rows[:5]))
    assert st == "halt" and rows[0] == "A 1 A1 2 A2 3 AB 4 B 5", "two-char names failed"
    assert rows[3].endswith("19 ATTESO 19"), "FOR with a two-character index failed"

    m = Machine(load('bin/focal_hamurabi.bin'))
    m.reset()
    m.kbd_input = [(c, 0) for c in '0\n1900\n900\n' * 12]
    st = m.run(limit=40_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    # Five endings: deposed mid-term, or one of the four appraisals the 1973
    # version added.  No fixed line of play survives every roll -- a single
    # yield of one bushel an acre is fatal -- so the test asserts that the
    # game grades you, not that it lets you win.
    endings = ('DEPOSTO', 'FINK', 'NERONE', 'MEGLIO', 'FANTASTICA')
    verdict = [r for r in rows if any(e in r for e in endings)]
    print("hamurabi: %d instructions, verdict %r" % (m.instrs, verdict[0] if verdict else None))
    assert st == "halt" and verdict, "hamurabi did not reach a verdict"

    # Storer's physics now, not a kinematic stand-in: the mass falls as the
    # fuel burns, so the same flow rate decelerates harder as the tank empties,
    # and the series for -ln(1-Q) keeps its second term because the evaluator
    # carries thirty-six bits.  These numbers match an independent model of the
    # same integer arithmetic digit for digit.
    m = Machine(load('bin/focal_lunar.bin'))
    m.reset()
    m.kbd_input = [(c, 0) for c in '0\n' * 6 + '170\n' * 8 + '36\n' * 10]
    st = m.run(limit=40_000_000)
    rows = [r.rstrip() for r in m.console() if r.strip()]
    print("lunar: %s / %s" % (rows[-2] if len(rows) > 1 else '?', rows[-1]))
    assert st == "halt", "lunar did not finish"
    assert any('CONTATTO AL TEMPO 200' in r for r in rows), "lunar: wrong contact time"
    assert any('IMPATTO A 741' in r for r in rows), "lunar: wrong impact speed"

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
