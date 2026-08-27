#!/usr/bin/env python3
"""Compile a FOCAL source file into the interpreter's stored line format.

    python3 mkprog.py focal/sum.fc asm/program.s

A stored line is a key word, a length, a body of words, and a newline.  The
length counts the whole line, so the next one starts at start+length and
walking the lines needs no scanning.  A body word is either a character or a
tagged item, told apart by bit 16, which a character never carries:

    0 0xxxxxxx          a character, kept byte for byte
    1 0000 dnnnlllll    a command: letter, letters written, trailing point
    1 0010 .......g    a line number follows in the next word; g marks one
                        written without a point, which names a group

Only three things are replaced, so only three need encoding.  The text between
them is verbatim, which is why spacing costs nothing.  A line number needs 17
bits on its own -- 99*1000+999 is 99999 -- so there is no room beside it for a
tag, hence the marker and a word of its own.  Where a line number may appear
is fixed by the command that introduced it, so it needs no tag of its own.

A command word only ever begins a segment.  Elsewhere a letter is a variable
or plain text, and taking one for a command turns TYPE "SUM " into TYPE "SET ".

An abbreviated command carries the point -- G. and GO. are commands, a bare G
is not.  The point is stored rather than derived from the count of letters,
because it is also allowed after the whole name: GOTO and GOTO. are both
commands and are different text, so the compression has to tell them apart.

The reverse of this is WRITE, in focal.s.  Line numbers come back canonically,
gg.sss, or as gg when the step is zero and the number named a group.
"""
import re
import sys

ITEM = 0x10000                  # set on every tagged word, never on a character
CMD = ITEM | 0x0000
LNUM = ITEM | 0x2000
GROUP = 1                       # written without a point, so it names a group
NL = 10

COMMANDS = {'A': 'ASK', 'C': 'COMMENT', 'D': 'DO', 'E': 'ERASE', 'F': 'FOR',
            'G': 'GOTO', 'I': 'IF', 'Q': 'QUIT', 'R': 'RETURN', 'S': 'SET',
            'T': 'TYPE', 'W': 'WRITE'}
JUMPS = {'G': 1, 'D': 1, 'I': 3}   # how many line numbers may follow

NUM = re.compile(r'(\d{1,2})(?:\.(\d{1,3}))?')


def key(m):
    """A matched line number as one word: group*1000 + step, padded right."""
    group, step = m.group(1), m.group(2)
    return int(group) * 1000 + (int(step.ljust(3, '0')) if step else 0)


def marker(m):
    """The word that introduces a line number.  A number written without a
    point names a group, and saying so here saves DO a division by 1000."""
    return LNUM | (0 if m.group(2) else GROUP)


def close(s, i):
    """Index just past the paren matching the one at i."""
    depth = 0
    while i < len(s):
        if s[i] == '(':
            depth += 1
        elif s[i] == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise SystemExit("unbalanced parentheses: %r" % s)


def segments(s):
    """Split on the semicolons outside quoted strings, keeping them."""
    out, cur, quoted = [], '', False
    for ch in s:
        if ch == '"':
            quoted = not quoted
        if ch == ';' and not quoted:
            out += [cur, ';']
            cur = ''
        else:
            cur += ch
    return out + [cur]


def compile_line(src, where):
    words = []

    def text(s):
        words.extend(ord(c) for c in s)

    def numbers(seg, i, n):
        for _ in range(n):
            m = NUM.search(seg, i)
            if not m:
                break
            text(seg[i:m.start()])
            words.extend((marker(m), key(m)))
            i = m.end()
        text(seg[i:])

    m = NUM.match(src, len(re.match(r'\s*', src).group(0)))
    if not m:
        raise SystemExit("%s: line has no number: %r" % (where, src))
    if not 1 <= key(m) // 1000 <= 99:
        raise SystemExit("%s: line number outside 01..99: %r" % (where, src))
    words.append(key(m))   # indentation before the number is not kept
    words.append(0)        # the length, filled in once the line is built

    for seg in segments(src[m.end():]):
        if seg == ';':
            text(';')
            continue
        head = re.match(r'(\s*)([A-Z]+)(\.?)', seg)
        if not head:
            text(seg)
            continue
        spaces, word, dot = head.groups()
        letter = word[0]
        if letter not in COMMANDS:
            raise SystemExit("%s: unknown command %r in %r" % (where, word, src))
        full = COMMANDS[letter]
        if not full.startswith(word):
            raise SystemExit("%s: %r is not a spelling of %s in %r"
                             % (where, word, full, src))
        if word != full and not dot:
            raise SystemExit("%s: %r abbreviates %s and so needs its point, "
                             "in %r" % (where, word, full, src))
        text(spaces)
        words.append(CMD | (ord(letter) & 31) | (len(word) << 5)
                     | (0x100 if dot else 0))
        i = head.end()
        if letter == 'I':                       # the condition stays verbatim
            k = seg.find('(', i)
            if k >= 0:
                end = close(seg, k)
                text(seg[i:end])
                i = end
            numbers(seg, i, 3)
        elif letter in JUMPS:
            numbers(seg, i, JUMPS[letter])
        else:
            text(seg[i:])
    words.append(NL)
    words[1] = len(words)
    return words


def main():
    src, dst = sys.argv[1], sys.argv[2]
    out = ["; generated by mkprog.py from %s -- do not edit" % src, "TEXT:"]
    total = lines = 0
    for n, line in enumerate(open(src).read().replace('\r\n', '\n')
                             .rstrip('\n').split('\n'), 1):
        if not line.strip():
            continue
        words = compile_line(line, "%s:%d" % (src, n))
        total += len(words)
        lines += 1
        out.append("        .dd     %s" % ", ".join(str(w) for w in words))
        out.append("                                ; %s" % line)
    out.append("        .dd     0")
    open(dst, 'w').write("\n".join(out) + "\n")
    print("%s: %d lines, %d words" % (dst, lines, total))


main()
