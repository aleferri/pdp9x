#!/usr/bin/env python3
"""Run every sample program and report what it did.

    python3 bench.py            everything
    python3 bench.py sieve      just the sieve variants
    python3 bench.py console    just the console drivers
    python3 bench.py checks     just the CPU unit tests
"""
import re
import struct
import subprocess
import sys

from sim import CPU, MEMSZ, W
from machine import Machine


def load(path):
    d = open(path, 'rb').read()
    mem = [0] * MEMSZ
    for i in range(0, len(d), 4):
        mem[i // 4] = struct.unpack('>I', d[i:i + 4])[0] & W
    return mem


GROUP_FORM = re.compile(r'.*\b(DO|GOTO)\s+\d{1,2}\s*$')


def relist(mem, text):
    """The stored program spelled back out, the way WRITE does it.  Reading it
    out of memory rather than off the 32-column console keeps the comparison
    about the format and not about line wrapping."""
    names = {}
    for nm in ('ASK COMMENT DO ERASE FOR GOTO IF QUIT RETURN SET TYPE '
               'WRITE').split():
        names[ord(nm[0]) & 31] = nm

    def key(v):
        g, step = divmod(v, 1000)
        return "%02d" % g if step == 0 else "%02d.%03d" % (g, step)

    out, i = [], 0
    while mem[text + i]:
        line, i = key(mem[text + i]), i + 2      # the key, then its length
        while mem[text + i] != 10:
            w = mem[text + i]
            if not w & 0x10000:
                line += chr(w)
            elif w & 0x1E000 == 0x12000:
                i += 1
                line += key(mem[text + i])
            else:
                line += names[w & 31][:(w >> 5) & 7] + ('.' if w & 0x100 else '')
            i += 1
        out.append(line)
        i += 1
    return out


def rule(title):
    print("\n" + title)
    print("-" * len(title))


# ---------------------------------------------------------------- sieve
def symbols(src):
    """Ask the assembler where the labels ended up, rather than hardcoding
    addresses that move whenever the zero page is rearranged.

    asm/program.s is generated and not tracked, so a fresh checkout has none:
    make one first, or focal.s cannot be assembled.  And say so when the
    assembler fails, instead of returning an empty table and letting the caller
    die on a KeyError several steps later."""
    import subprocess, re, os
    if not os.path.exists('asm/program.s'):
        subprocess.run(['python3', 'mkprog.py', 'focal/sum.fc', 'asm/program.s'],
                       check=True, capture_output=True)
    done = subprocess.run(['casmeleon', '-lang=pdp9x.casm', '-byteSize=32', src],
                          capture_output=True, text=True)
    table = {m.group(1): int(m.group(2)) // 4
             for m in re.finditer(r'(\w+)@(\d+)', done.stdout)}
    if not table:
        raise SystemExit("could not assemble %s:\n%s%s"
                         % (src, done.stdout[-400:], done.stderr[-400:]))
    return table



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
    got = [m.console()[k].rstrip() for k in range(6)]
    print("DO: %d instructions -> %s" % (m.instrs, " | ".join(got)))
    assert st == "halt", "DO did not halt"
    # RIGA distinguishes a DO of one line from a DO of its group: group 02 has
    # two lines, so a single-line DO must give 1 and the group 101.  Without
    # that the two cannot be told apart, and they were not.
    assert got[0] == "RIGA 1", "DO of a single line ran more than the line"
    assert got[1] == "GRUPPO 101", "DO of a whole group failed"
    assert got[2] == "ANNIDATO 1", "DO inside DO failed"
    # 13 is 04.010, 04.020 and 04.030 in that order and nothing else: leaking
    # into group 05 would say 999.
    assert got[3] == "ORDINE 13", "the group ran out of order or ran on"
    # RETURN from the middle of group 06 skips 06.030, which would add 100.
    assert got[4] == "RETURN 7", "RETURN did not unwind the group"
    # A DO is not the end of a line: what follows the semicolon still runs.
    assert got[5] == "SEMI 1", "the rest of the line after a DO did not run"

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
                   '01.010 TYPE "ONE", !\n01.030 TYPE "THREE", !\n'
                   '01.020 TYPE "TWO", !\n01.040 QUIT\n01.020 TYPE "TWO BIS", !\n'
                   '01.030\nWRITE\nGOTO 01.010\nQUIT\n']
    st = m.run(limit=30_000_000)
    rows = [r.rstrip() for r in m.console()]
    print("command level: listing %s -> ran %s"
          % (rows[7:10], rows[11:13]))
    assert st == "halt", "command level did not halt"
    assert rows[7:10] == ['01.010 TYPE "ONE", !', '01.020 TYPE "TWO BIS", !',
                          '01.040 QUIT'], "line editing failed"
    assert rows[11:13] == ["ONE", "TWO BIS"], "running the typed program failed"

    # A DO typed at the prompt has to come back to the prompt.  FIND moves the
    # text pointer and the mode into the stored program, so without saving both
    # the DO ran on as if it had been a GOTO.
    m = Machine(load('bin/focal_int.bin'))
    m.reset()
    m.kbd_input = [(c, 0) for c in
                   '02.010 TYPE "A", !\n02.020 TYPE "B", !\n03.010 TYPE "C", !\n'
                   'DO 2\nTYPE "BACK", !\nQUIT\n']
    st = m.run(limit=30_000_000)
    rows = [r.rstrip() for r in m.console()]
    print("DO at the prompt: %s" % rows[4:8])
    assert st == "halt", "typed DO did not halt"
    assert rows[4:7] == ["A", "B", '*TYPE "BACK", !'], \
        "a group DO typed at the prompt did not return to the prompt"
    assert rows[7] == "BACK", "the typed line did not carry on after the DO"

    # The line number rules, at the prompt where an error can be seen.  The
    # four malformed shapes are the ones FOCAL itself rejected.
    checks = [
        ("1.5 is 01.500", '01.500 TYPE "HIT", !\n01.510 QUIT\nGOTO 1.5\nQUIT\n',
         "HIT"),
        ("group zero", '00.100 TYPE "X", !\nQUIT\n', "?L"),
        ("group above 99", '100.100 TYPE "X", !\nQUIT\n', "?L"),
        ("four digits of step", '01.1000 TYPE "X", !\nQUIT\n', "?L"),
        ("two points", '01.10.0 TYPE "X", !\nQUIT\n', "?L"),
        ("absent group", '01.010 TYPE "A", !\n01.020 QUIT\nDO 9\nQUIT\n', "?L"),
        ("absent line", '01.010 TYPE "A", !\n01.020 QUIT\nGOTO 07.010\nQUIT\n',
         "?L"),
    ]
    bad = []
    for name, keys, want in checks:
        m = Machine(load('bin/focal_int.bin'))
        m.reset()
        m.kbd_input = [(c, 0) for c in keys]
        m.run(limit=30_000_000)
        if want not in [r.rstrip() for r in m.console()]:
            bad.append(name)
    print("line numbers: %d of %d rules hold" % (len(checks) - len(bad), len(checks)))
    assert not bad, "line number rules failed: %s" % ", ".join(bad)

    # A bare number still deletes its line now that the number carries a point.
    m = Machine(load('bin/focal_int.bin'))
    m.reset()
    m.kbd_input = [(c, 0) for c in
                   '01.010 TYPE "A", !\n01.020 TYPE "B", !\n01.010\nWRITE\nQUIT\n']
    m.run(limit=30_000_000)
    rows = [r.rstrip() for r in m.console()]
    assert '01.020 TYPE "B", !' in rows and '01.010 TYPE "A", !' not in rows[5:], \
        "deleting a line by its bare fixed point number failed"

    # Text grows up from the bottom of the arena and the heap down from the top,
    # so there is one boundary between them and both sides have to test it.  The
    # arena is 118784 words, far too many to fill by typing, so the heap pointer
    # is moved down to just above the text first: what is under test is the
    # check, not the patience of the simulator.
    sym = symbols('asm/focal.s')

    m = Machine(load('bin/focal_int.bin'))
    m.m[sym['HEAP']] = sym['TEXT'] + 30          # room for one short line, not two
    m.reset()
    m.kbd_input = [(c, 0) for c in
                   '01.010 TYPE "A", !\n01.020 TYPE "BBBBBBBBBBBBBB", !\nQUIT\n']
    st = m.run(limit=20_000_000)
    end = sym['TEXT'] + m.m[sym['TEND']]
    print("arena, text side: ends at %#x, heap at %#x, refused with %s"
          % (end, m.m[sym['HEAP']],
             [r.rstrip() for r in m.console() if r.rstrip().startswith('?')][:1]))
    assert st == "halt", "the text side did not halt"
    assert any(r.rstrip() == "?S" for r in m.console()), \
        "storing past the heap was not refused"
    assert end <= m.m[sym['HEAP']], "the program text ran into the heap"

    # And the other way: a program that allocates, with the heap already down
    # against the text, must be refused rather than carving over it.
    m = Machine(load('bin/focal_grow.bin'))
    m.m[sym['HEAP']] = sym['TEXT'] + m.m[sym['TEND']] + 40
    m.reset()
    st = m.run(limit=20_000_000)
    print("arena, heap side: refused with %s"
          % [r.rstrip() for r in m.console() if r.rstrip().startswith('?')][:1])
    assert st == "halt", "the heap side did not halt"
    assert any(r.rstrip() == "?S" for r in m.console()), \
        "carving into the text was not refused"
    assert m.m[sym['HEAP']] >= sym['TEXT'] + m.m[sym['TEND']], \
        "the heap carved into the program text"

    # Nothing in the last 4K page -- the arithmetic runtime, the interpreter's
    # code, its dispatch table and its command names -- may be written, or none
    # of it could ever sit in ROM.  This held by accident until a name table
    # built at reset broke it.
    class ROMProbe(Machine):
        hits = []

        def wr(self, a, v):
            if (a & 0x1FFFF) >= 0x1F000:
                ROMProbe.hits.append((a & 0x1FFFF, self.pc))
            return Machine.wr(self, a, v)

    ROMProbe.hits = []
    for img, keys in (('bin/focal_hamurabi.bin', '10\n2000\n800\n' * 40),
                      ('bin/focal_int.bin',
                       '01.010 TYPE "A", !\n01.020 QUIT\nWRITE\nGOTO 01.010\n'
                       'ERASE\n01.010\nQUIT\n'),
                      ('bin/focal_do.bin', None),
                      ('bin/focal_grow.bin', None)):
        m = ROMProbe(load(img))
        m.reset()
        if keys:
            m.kbd_input = [(c, 0) for c in keys]
        m.run(limit=40_000_000)
    print("read-only above 0x1F000: %d writes" % len(ROMProbe.hits))
    assert not ROMProbe.hits, \
        "the interpreter writes into its own code or tables: %s" % ROMProbe.hits[:3]

    # casmeleon accepts a label defined twice without a word, and takes one of
    # them.  That silently aliased two scratch cells into one, and kept a
    # byte-identical second copy of ISQRT that an edit to the first would never
    # have reached.
    seen, dup = set(), []
    for src in ('asm/focal.s', 'asm/arithlib.s'):
        for line in open(src):
            m = re.match(r'([A-Za-z_][A-Za-z0-9_]*):', line)
            if m:
                if m.group(1) in seen:
                    dup.append(m.group(1))
                seen.add(m.group(1))
    print("labels: %d, none defined twice" % len(seen) if not dup else "")
    assert not dup, "labels defined twice: %s" % sorted(set(dup))

    # Five samples that nothing used to run, so they rotted unnoticed: if3
    # spent years printing the wrong arm because it used F as a variable, and F
    # is the prefix that starts a function.
    for name, want in (("comment", ["LOOPED"]),
                       ("diag", ["A 12", "B 3", "C 8", "D 24"]),
                       ("if3", ["A NEG", "VAL -1000", "D NEG"]),
                       ("seven", ["DONE"]),
                       ("erase", ["PRIMA 7 3", "DOPO 0 0"])):
        m = Machine(load('bin/focal_%s.bin' % name))
        m.reset()
        st = m.run(limit=20_000_000)
        got = [r.rstrip() for r in m.console() if r.strip()][:len(want)]
        print("%-8s %s" % (name, " | ".join(got)))
        assert st == "halt", "%s did not halt" % name
        assert got == want, "%s gave %s" % (name, got)

    # A command may be spelled whole, whole with a point, or abbreviated with
    # one, and WRITE has to give back the one that was typed.  The point is
    # stored rather than derived from the letter count precisely because TYPE
    # and TYPE. are both commands and are different text.
    m = Machine(load('bin/focal_abbrev.bin'))
    m.reset()
    st = m.run(limit=20_000_000)
    got = [m.console()[k].rstrip() for k in range(4)]
    print("command spellings: %s" % " | ".join(got))
    assert st == "halt", "abbreviations did not halt"
    assert got == ["PIENO", "PIENO COL PUNTO", "ABBREVIATO",
                   "ABBREVIATO PIU LUNGO"], "abbreviated commands failed"

    # WRITE spells a command out from a name, and BODY dispatches on a letter.
    # The letter each name belongs to is its own first character, so CNLOOK can
    # search the name list and no table indexed by letter is needed -- but the
    # other direction cannot be derived, because CTAB holds jumps and an address
    # carries no letters.  So check the two agree: every letter CTAB handles has
    # a name, and every name a handler.
    sym = symbols('asm/focal.s')
    mem = load('bin/focal_int.bin')
    default = mem[sym['CTAB']]          # index 0 is the unknown-command entry
    handled = {i for i in range(32) if mem[sym['CTAB'] + i] != default}
    named = set()
    i = 0
    while mem[sym['CNAMES'] + i]:
        named.add(mem[mem[sym['CNAMES'] + i]] & 31)
        i += 1
    # The requirement runs one way: a letter CTAB handles must have a name, or
    # WRITE spells it as question marks.  The reverse is allowed, and COMMENT
    # uses it -- a comment is meant to be skipped, so the default entry is its
    # handler.
    print("commands: %d letters dispatch, %d have names, %d skipped by default"
          % (len(handled), len(named), len(named - handled)))
    assert handled <= named, \
        "these letters dispatch with no name for WRITE: %s" % sorted(handled - named)

    # The stored form is a compression of the source, so listing it back is the
    # decompression, and the two are only in step if every line survives the
    # round trip.  mkprog.py compiles and WRITE spells back out; this diffs the
    # result against the .fc that produced it, which is what stops the compiler
    # and the lister drifting apart.  Only a line number's own spelling is
    # lost, and it comes back canonical -- 1.5 as 01.500, a bare group as gg.
    import glob
    bad, lines = [], 0
    for fc in sorted(glob.glob('focal/*.fc')):
        src = [l for l in open(fc).read().rstrip('\n').split('\n') if l.strip()]
        if not src:
            continue
        subprocess.run(['python3', 'mkprog.py', fc, 'asm/program.s'],
                       check=True, capture_output=True)
        subprocess.run(['casmeleon', '-lang=pdp9x.casm', '-byteSize=32',
                        '-endian=big', '-export=bin', 'asm/focal.s'],
                       check=True, capture_output=True)
        mem = load('asm/focal.bin')
        got = relist(mem, symbols('asm/focal.s')['TEXT'])
        lines += len(src)
        if len(src) != len(got):
            bad.append("%s: %d lines in, %d out" % (fc, len(src), len(got)))
            continue
        for a, b in zip(src, got):
            if a != b and not GROUP_FORM.match(a):
                bad.append("%s\n    in  %r\n    out %r" % (fc, a, b))
    print("stored form: %d lines round trip, %d differ" % (lines, len(bad)))
    for b in bad[:5]:
        print("  " + b)
    assert not bad, "the stored form and the listing have drifted apart"

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
