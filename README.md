# pdp9x — 18-bit accumulator machine

Simulator, assembler definition and sample programs for an 18-bit machine in
the PDP-4/7/9/15 line, with a hardware stack, one index register and a
four-entry interrupt vector.

`SPEC.md` is the architecture document. Everything asserted in it is exercised
by the code here.

## Running

The `bin/` directory ships pre-assembled, so nothing needs building to run:

```
python3 bench.py            # CPU invariants, then every sample program
python3 bench.py checks     # just the 32 CPU unit tests
python3 bench.py sieve      # just the sieve variants
python3 bench.py sieve 10   # sieve, ten iterations
python3 bench.py console    # console driver, spacing test, link return
```

Python 3.8 or later, no dependencies.

## Rebuilding

Assembly is done with [casmeleon](https://github.com/aleferri/casmeleon), a
retargetable assembler in Go by aleferri:

One patch is needed, `patches/casmeleon-org-places-by-address.patch`: the memory
map below cannot be assembled without it. Two older changes this machine carried
were merged upstream in `6af03b3`, so their patches are gone; the three
directives they and this one concern are described below.

```
git clone --depth 1 https://github.com/aleferri/casmeleon
cd casmeleon
GOPROXY=direct GOSUMDB=off GOFLAGS=-mod=mod go get github.com/aleferri/casmvm@v0.2.9
git apply /path/to/pdp9x/patches/casmeleon-org-places-by-address.patch
GOPROXY=direct GOSUMDB=off go build -o casmeleon ./cmd/casmeleon
```

The `go get` matters. `casmeleon` pins `casmvm v0.2.8`, in which `Enter.Apply`
discards the error returned by an inline in order to check the return count
first. An inline aborted by `.error` never reaches its `.return`, so the count
necessarily disagrees and that generic complaint replaces the real message:
every range check in `pdp9x.casm` used to surface as `len of formal returns and
effective returns diffs, expected 1 returns, received 0 instead`. Upstream
fixed it in `63c8d7d`, released as `v0.2.9`. With it, a range check says what it
means:

```
memory reference address outside the 11 bit zero page, value 16384
CAL/JMP direct is PC-page relative: target is in another 4K page, value 16384
```

The `.dd` directive deposits at the width the target actually uses. `.db` and
`.dw` are fixed at 8 and 16 bits regardless of `-byteSize`, so an 18-bit
machine previously had to route every data word through a pseudo opcode. `.dd`
takes numbers, negatives, labels and quoted strings, so `WORD` and `NWORD` are
gone.

Backslash escapes in quoted literals matter because a FOCAL program is
embedded into the assembly as a string and its own `TYPE "..."` statements are
full of quotes. The scanner used to have none: a `"` opened a literal and the
next `"` closed it, so a string could never contain one. It now honours `\\`,
`\"`, `\n`, `\r`, `\t` and `\0`, with an unknown escape yielding the character
itself so a stray backslash is never silently dropped.

`.org` is the one that still needs patching. It places what follows at an
address; `.advance` pads up to one. The difference only matters if a file wants
to lay out regions in an order other than the order it reads in, which is
exactly what putting the interpreter above the arena wants. As shipped `.org`
did nothing: the driver skips items whose bytes cannot have changed and
recomputes the address after them from the byte count, which is right for
`.advance` and wrong for a directive that emits nothing, so a skipped `.org`
silently did not move the address. `patches/README.md` has the rest.

Then, from this directory:

```
CASM=/path/to/casmeleon ./build.sh
```

`build.sh` regenerates `pdp9x.casm` from `gen_casm.py` and assembles every
`asm/*.s` into `bin/`. The instruction set definition is generated rather than
hand-written because the memory-reference opcodes are 64 near-identical
patterns (8 opcodes by 2 register selectors by 4 addressing modes).

Three casmeleon constraints shaped the definition, and are worth knowing before
editing it:

- Opcode arguments are **single tokens**. No expressions and no negative
  literals, which is why negative constants are `.dd` data rather than operands.
- `.db` and `.dw` stay 8 and 16 bits wide even at `-byteSize=32`; `.dd` follows
  the byte size.
- `.org` places what follows at an address and may run backwards; `.advance`
  pads up to one and may not. Both need the patch in `patches/` to work at all.
- Every `.set` member needs a trailing `;`, **including the last one**.
  Omitting it reports only `Unexpected Error`, with no line number.
- `.include` resolves relative to the **including file**, not the working
  directory.

A memory reference operand above 2047 is rejected, which is easy to trigger by
declaring a constant next to the code that uses it instead of in the zero page.

A forward label reads as 0 on the first pass, which would make the PC-page
range check in `JPC` fire spuriously; since `.error` is fatal and blocks
re-evaluation, the check is guarded with `a != 0`.

## Files

| | |
|---|---|
| `SPEC.md` | architecture specification |
| `MICROCODE.md` | the control store, and `ucode.py` which assembles it |
| `sim.py` | CPU core: decode, execute, cycle accounting |
| `machine.py` | blitter and timer on IOT, framebuffer at `0x800` |
| `model.py` | Python model of the console algorithm, used to debug it |
| `run.py` | CPU invariant tests |
| `bench.py` | runs everything and reports |
| `gen_casm.py` | generates `pdp9x.casm` |
| `mkprog.py` | compiles a FOCAL `.fc` source into the stored line format |
| `pdp9x.casm` | casmeleon instruction set definition |
| `build.sh` | regenerate and assemble |
| `patches/` | the one casmeleon patch the build needs, and why |

## Sample programs

### Sieve

The Byte magazine sieve, 8190 flags, one word per flag, answer 1899. Four
versions showing where the instruction set costs and pays:

| | |
|---|---|
| `sieve.s` | baseline: loop variable in memory, bound checked with `TAD` against a negative constant |
| `sieve2.s` | loop variable lives in `IX`, incremented with `TADX`, bound checked with `SXD` |
| `sieve3.s` | index biased so the limit sits on the sign boundary, `TASX` reports the crossing as overflow |
| `sieve4.s` | `IAC`/`IXC` replace the explicit `TAD ONE` |

Measured: 912398 cycles down to 514769, **−43.6%**, with the answer unchanged
throughout.

The step from `sieve2` to `sieve3` is the interesting one. There is no skip on
sign, and `SXD` only compares for inequality, so the marking loop — which
advances by a variable stride and overshoots the limit — cannot terminate on
equality. Biasing the index by `2^17 − (limit+1)` moves the limit onto the sign
boundary, and the bias is absorbed by the base pointer because the effective
address is masked to 17 bits. The ordering test then costs nothing.

### Console

`driver.s` and `driver2.s` drive a 16×32 character blitter and a 16-bit timer,
both on IOT. The blitter is deaf for 7680 cycles during a scroll, and needs 8
cycles between consecutive framebuffer writes.

Output is queued during a scroll with the newlines kept inline; on scroll-done
the queue is replayed through the normal `putc`/`newline` path rather than
copied, so a queued newline issues the next scroll by itself. The timer times
the scroll, so its interrupt *is* the completion signal.

Busy-waiting instead would serialise computation and scrolling. Buffering
overlaps them: cost per line goes from `t_compute + 7680` to
`max(t_compute, 7680)`, worth up to 2× when the two are comparable.

### spacing.s

Writes to the framebuffer four times in a row, 5 cycles apart against a floor
of 8. Loses 587 writes with no error of any kind. Unrolling a fill loop is
exactly this mistake, which is why the simulator counts the violations rather
than letting them pass.

### FOCAL

`asm/focal.s` is a subset of DEC's FOCAL: `SET`, `TYPE`, `ASK`, `IF`, `GOTO`,
`DO`, `RETURN`, `FOR`, `WRITE`, `ERASE`, `QUIT` and comment lines, several to a
line separated by semicolons, over an expression evaluator with `+ - * / ^`,
parentheses, unary minus, subscripted variables `A(i)` and the functions
`FABS`, `FSGN`, `FITR`, `FSQT`, `FLEN`. `IF` takes one, two or three targets
and falls through when the arm it wants is not there. `ASK` prompts with the
variable name and a colon. Control C stops a running program with `?C`. Line
numbers are fixed point `gg.sss` and `DO gg` runs a whole group; see *Line
numbers*.

### Two programs that are not benchmarks

**Hamurabi** began life as *The Sumer Game*, in FOCAL on a PDP-8 in 1968, and
**Lunar** is Jim Storer's Lunar Landing Game, FOCAL on a PDP-8 in the autumn of
1969 — written by a high school student weeks after Apollo 12 launched, sent to
the DEC users' newsletter, and from there into a whole genre. David Ahl
converted both to BASIC afterwards, which is how most people met them. They are
here because they are the two historical programs that were *native* to the
language this machine runs.

Both needed `FRAN`, which on an integer machine cannot return a fraction the way
FOCAL's does: `FRAN(n)` gives a value in `0..n-1` instead. A linear
congruential generator, with the low bits shifted away because those are the
weak ones.

Hamurabi ran unchanged in spirit — bushels, acres and population are integers.
Lunar did not, and for a reason worth stating precisely: in millimetres per
second the velocity of a 370 second lunar fall is 599000, and an 18-bit word
stops at 131071. The velocity wrapped and the lander drifted.

It now runs **Storer's own physics** rather than a kinematic stand-in, because
the evaluator carries 36 bits. The mass falls as the fuel burns, so the same
flow rate decelerates harder as the tank empties, and the series for
`-ln(1-Q)` keeps its second term instead of vanishing under the resolution of
the fixed point. Free fall gains 52.8 ft/s every ten seconds; a searched
profile — six steps of fall, eight at 170 lb/s, then 36 — touches down at 200
seconds doing 74.1 ft/s. Those numbers match an independent model of the same
integer arithmetic digit for digit.

One rule the program has to respect, and it is a limit of the evaluator rather
than of the physics: `9504*10*E` works and `9504*E*10` does not. A product of
two words is exact in the pair, but multiplying a value that is *already* wider
than a word truncates it, because an exact 36 by 36 product would need 72 bits.
Division has no such limit — it takes the whole pair.

### Command level

`bin/focal_int.bin` is the same interpreter with no program assembled in, so it
converses. A line beginning with a number is filed away, anything else runs at
once, and a bare number deletes that line:

```
*01.010 TYPE "ONE", !
*01.030 TYPE "THREE", !
*01.020 TYPE "TWO", !          filed in numeric order, not typing order
*01.040 QUIT
*01.020 TYPE "TWO BIS", !      replaces line 01.020
*01.030                        deletes line 01.030
*WRITE
01.010 TYPE "ONE", !
01.020 TYPE "TWO BIS", !
01.040 QUIT
*GOTO 1.5                      the step is padded: 1.5 is 01.500
*GOTO 01.010
ONE
TWO BIS
```

The same `BODY` runs both modes; only the text pointer differs, aiming at the
stored program or at the line just typed. `RESET` looks at the first word of
the program area: assembled in, it runs and stops; empty, it prompts. So every
batch program above still works unchanged.

The program area ends where the framebuffer begins, and a store that would not
fit is refused with `?S`. It used to walk straight past into the screen.

An error abandons the stack and returns to the prompt — the stack lives in a
fixed page precisely so that this costs two instructions — but in a batch image
there is nobody to return to, so it stops instead.

What is left is **floating point**, which is the substrate of the real language
and was replaced on purpose. `LIBRARY` and `MODIFY` sit behind mass storage.

`FOR v=start,step,limit; body` re-runs the rest of its own line, so the loop
just rewinds the text pointer and calls the body again; the loop variable lives
in the ordinary variable table, as FOCAL specifies, so the body can read it.
`FSQT` is Newton from above in `arithlib.s`: the guess only ever falls, so the
first value that fails to fall is the answer.

```
01.010 COMMENT TRIANGULAR NUMBERS AND A THREE WAY TEST
01.020 SET A=7
01.030 SET B=A*(A+1)/2
01.040 TYPE "SUM TO ", A, " IS ", B, !
01.050 IF (B-28) 01.080, 01.060, 01.080
01.060 TYPE "TWENTY EIGHT, AS EXPECTED", !
```

`DO gg.sss` runs that line as a subroutine and then carries on after the `DO` —
on the same line, so `DO 02.010; TYPE T` prints what the subroutine left, which
is what FOCAL does. It used to swallow the rest of its line.
The main loop calls a `STEP` subroutine that executes exactly one line, so a
line can be run from inside another line and the nesting rides entirely on the
hardware stack — a few words per level, no interpreter state to save. `DO`
inside `DO` therefore works without a single line of extra code, which is the
one place where this machine's stack earns its keep over the PDP-8 it descends
from.

`DO gg`, a group with no step, runs every line of the group in turn. The walk
needs a cursor and the group's upper end, and both ride on the stack rather
than in the zero page, because a nested `DO` would otherwise overwrite the
outer walk. `RETURN` abandons the rest of the group and not just the rest of
the line, which is what lets a subroutine spread over several lines leave from
the middle of the first.

A `DO` typed at the prompt now comes back to the prompt. `FIND` moves both the
text pointer and the run/converse flag into the stored program, and the old
`DO` restored neither, so `DO 01.010` at the prompt ran on from there as if it
had been a `GOTO`. Both are saved with the return position.

`ASK` reads decimal numbers from the keyboard, which has four registers: the
raw code, the modifiers held with it, a status flag and an acknowledge. A
keystroke latches code and modifiers and raises `irq1` on release, and scanning
stops until the CPU acknowledges. **Reconstructing the character is the CPU's
job**: control masks to the low five bits, shift folds letters to upper case.
The symbol half of the shift map is left alone because it depends on the
physical layout.

The handler reconstructs into an eight-entry queue, and the queue-full case is
where the handshake earns its place: the handler simply does not acknowledge,
so the device keeps the keystroke and stops scanning. It then masks **that one
device** in the processor's interrupt mask and returns with interrupts still on,
because a keyboard queue that is momentarily full is no reason to stop
listening to the rest of the machine. `GETK` unmasks once it has taken a
character and the held keystroke is delivered again. Nothing is dropped, no
keystroke is duplicated, and the buffer never has to grow.

The evaluator is plain recursive descent, which the machine supports directly
because `CAL` and `RET` use the hardware stack and intermediate values ride on
it via `PSH AC`.

`IX` is the text pointer for the whole interpreter, not a variable in the zero
page. Reading the current character is then a single `LAC (TXTP), X` and
advancing is a single `IXC`, both inline. As subroutines they cost a `CAL`, a
`LIX`, an indirect load and a `RET` each, and the scanner calls them about
1600 times in a 24 line program: moving the pointer into the register cut the
whole run from 69788 cycles to 51510, **26 percent**. A routine that needs `IX`
for its own indexing saves it first, which is `FVAR`, `PNUM`, `PUTC`, the store
side of `SET`, and `MUL` in the library. FOCAL's three-way `IF` needs the sign of a value, and the
`RLA` then `GLK` idiom hands it over as a 0 or 1 word without a branch.

Two things dominated the interpreter before they were fixed, and neither was
the evaluator. Reading the current character was a subroutine call: moving the
text pointer into `IX` made it one inline instruction and cut a quarter of the
run. Then `num*10` in the number parser was calling the general multiplier,
which turned out to be **half** of a loop-heavy program; `10x = 8x + 2x` is
three `SHA` and an add.

Command dispatch goes through a 32-entry table of jumps indexed by the low five
bits of the command letter, which needs no range check because `A`..`Z` map onto
1..26 and anything else lands on an entry that skips the line. The table holds
jumps rather than addresses because the machine indirects once, not twice.

Measured against the chain of comparisons it replaced: a failed comparison
costs two instructions (`LAC`, then `SAD` skipping the `JMP`), so the chain
costs `2(k-1)` for the command in position *k* while the table is flat and four
instructions worse than position one. **They cross at position three.** With
seven commands and uniform use it is still close to a wash; the table pulls
ahead where the chain is long or the hit is late — on a loop of comment lines,
which fall past every comparison, it wins 2.3% of cycles.

The interesting part is that it took two wrong guesses to find this out. The
dispatch chain looked like the obvious waste in an instruction-coverage census
because it left the indexed indirect jump unused, but coverage says nothing
about cost. The actual waste was `CAL MUL` for a constant, which the census
could never flag because multiplying is perfectly normal code — it was only in
the wrong place. A call profile found it in one measurement.

### Two types

FOCAL has exactly one type, floating point: variables hold it, expressions
evaluate to it, and line numbers *are* it. Replacing that single type with
18-bit integers is therefore not a missing feature, it is a different language.
Line numbers are the one place the original type survives in shape, as fixed
point rather than float — see *Line numbers* below.

Variable names are a letter, optionally followed by a letter or a digit, with
only the first two characters significant — FOCAL's own rule.

The lookup is **two levels deep and allocated on demand**, because the flat
cross product was 36556 words for tables that almost every program leaves
empty. The second character picks one of thirty-seven classes — none, a letter,
a digit — and each class owns a block of twenty-six entries, one per first
letter. The class pointers live in the zero page and start empty; a block is
carved off the heap the first time a name in that class is used. The four kinds
are allocated separately, so a program with no strings never pays for the twenty
words per letter that strings would want.

| program | heap used | of the flat 36556 |
|---|---|---|
| Hamurabi, Lunar | 52 | 0.1% |
| subscripts | 468 | 1.3% |
| declared types | 598 | 1.6% |
| two-character names | 1248 | 3.4% |

The scheme also **removed the multiply**: a flat index needed `40n` computed
with five shifts, while two indexed reads need none. `ERASE` got shorter too —
it drops every block by emptying the class pointers and rewinding the heap
instead of walking every variable, and the reset clears nothing at all, because
the pointers start empty and a block is cleared when it is carved.

Reading a name is one subroutine, `VNAME`, rather than the nine copies it used
to be. That mattered more than the duplication suggested: two places
disambiguate a bare string variable from an expression beginning with one, and
both did it by peeking one character ahead and stepping back with `TADX MONE`. A
name that can be two characters long breaks that, so they now remember where the
name started and return to it.

A second type is added by **declaration** rather than by a suffix. BASIC put the
type in the spelling of the name — `A$` for a string, `A%` for an integer — but
in FOCAL `%` is already the `TYPE` format control, as are `!` and `#`, the other
two BASIC suffixes. Declaring instead puts the type in a table beside the
variables, so `A` stays `A` and a further type costs a table entry rather than a
new sigil.

```
10 SET A AS STRING
20 SET N AS INT
30 SET C AS STRING = N       declare and assign in one breath
40 SET A="HELLO"
50 SET N=1234
60 TYPE A, " ", N, " ", FLEN(A), !
70 SET D AS STRING
80 SET D="-56XYZ"
90 TYPE "SUM ", D+N, !       1178: the text read as the number it spells
```

Undeclared means integer, so every program written before declarations existed
still runs. `SET X AS FLOAT` is refused with `?F` rather than silently accepted:
there is no floating point to declare, and a declaration that quietly does
nothing is worse than one that fails.

Conversions run in both directions instead of raising a type error, which suits
a language that never had one, and they reuse the decimal machinery already
there for `TYPE` and `ASK`. Twenty-six strings of nineteen characters,
truncated silently on overflow.

One ambiguity survives the move from suffix to declaration, though it shrinks.
`A` alone, where `A` is a string, prints as text; `A+B` is arithmetic on the
numbers the two strings spell. The parser looks one character past the name — a
separator means the value, anything else means an expression — and a bare name
on the right of `SET` is resolved by **the source's** declared type, not the
destination's.

Arithmetic is 18-bit integer rather than FOCAL's floating point: the machine
has no floating unit, and the interesting part here is the interpreter.

Program text is generated from a `.fc` source:

```
python3 mkprog.py focal/diag.fc asm/program.s
FOCAL=focal/diag.fc ./build.sh
```

Decimal conversion writes its digits **backwards** into the tail of the
buffer. Division yields them least significant first, so filling from the end
leaves them in order and the reversal pass disappears entirely, along with its
four temporaries; `IX` carries the write index throughout, stepped back by
`TADX MONE`, which does not disturb `AC`.

`asm/arithlib.s` holds multiply, divide and decimal conversion at fixed
addresses (variables at `0x300`, code at `0x2000`) so both `arith.s` and
`focal.s` can include it and lay out their own zero page below and code above.

### Line numbers

A line number is fixed point, `gg.sss`: two digits of group and three of step,
held in one word as `group*1000 + step`. That is the numeric order too, so the
line index and the insertion search compare words and nothing has to be
unpacked. The step is padded on the right, so `1.5`, `01.500` and `1.500` are
one line, exactly as they were when the number was a float.

Written without a point it is a group, which is what `DO` takes. That leaves no
room for a line with a step of zero, and none is wanted: `01.000` would be
indistinguishable from group 1. The four shapes FOCAL itself refused are
refused here, all as `?L` — group zero, a group above 99, a fourth digit of
step, and a second point — as are a jump to a line that does not exist and a
`DO` of a group that does not.

The historical language used **two** decimals, `01.10`, with groups 1 to 31.
Three is a deliberate widening: `99.999` is 99999, which still fits an 18-bit
word with room to spare.

One parser serves the lot. There used to be four hand-copied decimal scanners —
one per buffer the interpreter reads: program text through `TXTP`, program text
through `TXTB`, the typed line in `LBUF`, and the index build — plus duplicate
`SKSP` and `EOL` for the second of those. Putting the fixed point rule in four
places was not an option, so the callers now aim `TXTP` at the buffer they want
and share `RDLN`; `LIRDN`, `LISKSP`, `LIEOL` and their three scratch words are
gone.

`RDLN` uses one accumulator and no multiply: the step's digits go into the
packed number as they arrive, and the padding that turns `1.5` into `01.500` is
the same times-ten run again. Calling the general multiplier for a constant is
the mistake this interpreter already made once, in the number parser, and it
cost half a loop-heavy program. Nobody ever asks for the step's *value*, only
whether it is zero, so its digits are summed rather than accumulated — the sum
is zero exactly when every digit was — and whether there is a number here at
all is a property of the first character, tested once before the loop rather
than re-flagged on every digit.

Callers that only need the pointer moved use `SKLN`, which walks digits and a
point and computes nothing — `STEP`, which parses the number of every line it
runs and whose value nobody reads, and the line editor. `IF` steps over the
targets it is not going to take instead of evaluating and discarding them. The
index stores the position of the **body**, past the number, so a jump does not
re-parse a number the index build already parsed.

### Memory map

| | | words | |
|---|---|---|---|
| `0x00000`–`0x00007` | interrupt vectors | 8 | entry *n* is device *n*, entry 0 is reset |
| `0x00008`–`0x007FF` | zero page variables | 760 + 1280 | an operand addresses 11 bits, so everything named directly lives here |
| `0x00800`–`0x009FF` | framebuffer | 512 | 16×32, write only |
| `0x01000`–`0x01FFF` | stack | 4096 | page 1; `SP` is 12 bits and cannot leave it |
| `0x02000`–`0x1EFFF` | arena | 118784 | program text up from the bottom, heap down from the top |
| `0x1F000`–`0x1FFFF` | interpreter | 4096 | arithmetic runtime, code, command tables |

Two things decide this shape. The **zero page** is fixed by the instruction
word: a memory reference carries 11 bits, so every variable has to sit below
`0x800` whatever else moves. And the **interpreter is one 4K page** because a
direct `CAL` or `JMP` is PC-page relative over 12 bits, so code that jumps to
its own labels has to share a page with them.

The interpreter is at the top and **nothing writes to it** — `bench.py` fails
the run if any address at or above `0x1F000` is written while the samples, the
command level and the string allocator work, so it could be ROM. That held by
accident until a name table built at reset broke it, which is why the check is
there rather than assumed. The interrupt vectors are still RAM at address zero
and are part of the image: on real hardware they would have to arrive from ROM
at reset, which is not solved here.

The **arena has one boundary, not two ceilings**. Text grows up, the heap grows
down, and both `STORE` and `HCARVE` test the same comparison, so neither side
can be overrun without the other noticing. Before this the text had a fixed
ceiling and the heap had none at all: a program that filled the text area wrote
over the framebuffer, and a program that exhausted the heap kept carving.

The arithmetic runtime shares that page, because a direct `CAL` cannot leave
one: `arithlib.s` places its variables at `0x300` and its code at `0x1F000`
with an `.org` each, and every program that includes it puts its own code in
the same page. The five small test programs moved up with it.

Each file says where its own regions go and no longer cares what order they
appear in — which needs the `.org` fix in `patches/`. `focal.s` has two `.org`
and puts the program text last, at `0x2000`, where it reads best.

### The stored form

Lines are not stored as typed. A stored line is a key word, its length in
words, a body, and a newline, so the next line starts at `start+length`; a body
word is either a character or a tagged item, told apart by bit 16, which a
character never carries:

    0 0xxxxxxx          a character, kept byte for byte
    1 0000 dnnnlllll    a command: letter, letters written, trailing point
    1 0010 .......g     a line number follows in the next word; g marks one
                        written without a point, which names a group

Only three things are replaced, so only three need encoding, and the text
between them is verbatim -- which is why spacing costs nothing and needs no
counting.  A line number needs 17 bits on its own, 99*1000+999 being 99999, so
there is no room beside it for a tag: hence the marker and a word of its own.
Where a line number may appear is fixed by the command that introduced it, so
it carries no tag.

An abbreviated command carries the point — `G.` and `GO.` are commands, a bare
`G` is not, and an abbreviation missing its point stays the characters it was.
The point is **stored** rather than derived from the count of letters, because
it is also allowed after the whole name: `TYPE` and `TYPE.` are both commands
and are different text, so the compression has to tell them apart. `focal/
abbrev.fc` holds all four spellings and the round trip covers them.

That FOCAL's commands are told apart by their first letter is what makes this
cheap: `AND C31` on a command word yields the letter exactly as it did on a
character, so **the dispatch table did not change at all**.  `SKIPW`, which
existed to step over the rest of `GOTO`, became one `IXC` and then went away.
`STEP` reads its key and steps past it.  `LIBUILD` parses nothing.  `TNUM`,
`RDLNUM`, `LBLENF`, `LBODYQ` and `SKLN` are gone: asking the compiled line
whether it has a body is simpler than re-scanning the characters that made it.

`mkprog.py` is the compiler.  A line typed at the prompt is compiled too --
even an immediate one, because `BODY` dispatches on a command word -- by the
same rules, which is what `COMP` and `CCMD` do.  A command word is emitted only
when the letters typed are a spelling of a real command, so `G`, `GO` and
`GOTO` are commands while `XYZ` is left as the characters it was and still
dispatches to `CUNK` through its letter.

There are two tables, and only one of them is written out. A command's letter
is its own first character, so the table `WRITE` indexes by letter is built at
reset from a flat list of names rather than spelled out a second time. The
other direction cannot be derived: `CTAB` holds jumps, and an address carries
no letters, so adding a command means a name in the list and a `JMP` in the
table. `bench.py` checks they agree — every letter that dispatches has a name,
or `WRITE` would spell it as question marks. The reverse is allowed and
`COMMENT` uses it: a comment is meant to be skipped, so the default entry is
its handler.

`WRITE` is the decompression, and the compression is lossless but for one
thing: a line number comes back canonical, `gg.sss`, or `gg` when the step is
zero and it named a group.  So `1.5` lists as `01.500` -- which is what FOCAL
did anyway, and closes a gap this interpreter used to have.  `bench.py` lists
every sample back out and diffs it against the `.fc`: 379 lines, none
differing.  That test is what stops the compiler and the lister drifting apart.

Reading a line number went from six characters to two words, and the cost of
the whole change lands well under where it started:

Each column below was measured when that change landed, so the last one is the
reduced form on its own and not the figure today — the length word and the walk
that replaced the line index came after it. Current numbers at the end of this
section.

| | before line numbers | fixed point | reduced |
|---|---|---|---|
| `focal.bin`, sum.fc | 49167 cycles | 55373 | 44173 |
| loop.fc | 196042 cycles | 217626 | 159251 |
| hamurabi | 650039 instrs | 661080 | 615511 |

The stored program is 71% of the characters it came from, not the half I first
guessed: most of a line is expression and string text that stays verbatim. The
gain is time, not space, and the time does not depend on that ratio.

Where it stands now, against the same starting point, with everything since
included — the length word, the walk that replaced the index, and `CNLOOK`:

| | before | now | |
|---|---|---|---|
| `focal.bin`, sum.fc | 49167 cycles | **39479** | −19.7% |
| loop.fc | 196042 cycles | **157139** | −19.8% |
| hamurabi | 650039 instrs | **603783** | −7.1% |
| do.fc | — | 23269 instrs | sample rewritten, not comparable |

The sieve numbers elsewhere in this file are untouched by any of it: 912398
cycles down to 514770 still, since none of this is on that path.

The rope index of `<key, position>` pairs is gone, and getting there took two
attempts worth recording. A key as one word makes looking a line up a walk over
the lines, so the chunks, the build and the invalidation on every edit ought to
be unnecessary — but measured that way, hamurabi cost **46% more**. The walk had
to scan each body with `EOL`, so it cost the words of the program rather than
the count of its lines, and paid that on every jump.

The missing piece was the length word, which had been sketched with the format
and then dropped on the wrong measurement: `EOL` was 0.7% of `loop.fc`, but `EOL`
is called from the middle of a line and cannot use a length, while a walk starts
at line heads and can. With `start+length` the step is an add, and the index has
nothing left to buy:

| | index, no length | index and length | walk by length |
|---|---|---|---|
| sum.fc | 45148 cycles | 42069 | 40425 |
| loop.fc | 160226 cycles | 160602 | 158085 |
| do.fc | 20958 instrs | 19902 | 15748 |
| hamurabi | 615819 instrs | 606280 | 604080 |

Nothing got slower. Short jump-heavy programs gain most, because they no longer
pay for a build they barely use; hamurabi comes out level with a fraction of the
machinery. What is left of all of it is `LINEXT`, a compare and an add per line.

### return_link.s

Shows that a subroutine can return `L` after all, by editing the packed
`{L, PC}` word on the stack before returning, and that the same handle gives a
skip return.

## Caveats

The cycle model is an interpretation, not silicon. If the control logic
diverges, the three places to check first are the execution order of combined
group 0 microinstructions, the cost of an indirection, and whether indexing is
really free.

`machine.py` models the specific devices attached in LogicCircuit — the
8-cycle spacing, the write-only framebuffer, the 7680-cycle scroll. Those are
device properties, not architecture, which is why they are not in `SPEC.md`.
