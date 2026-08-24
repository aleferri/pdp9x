"""Model of the buffered console driver, transcribed literally from the
pseudocode, so that the logic can be exercised before it is written in
assembly.  LITERAL=True reproduces the pseudocode exactly; LITERAL=False
applies the candidate fixes."""

COLS, ROWS = 32, 16
SCRSZ = COLS * ROWS
CAP0 = COLS
SCROLL_CYCLES = 7680


class Console:
    def __init__(self, literal=True):
        self.literal = literal
        self.screen = [' '] * SCRSZ
        self.buf = [' '] * 256
        self.bufp = 0            # 'buffer' pointer
        self.cap = CAP0
        self.line = 0
        self.index = 0
        self.busy = False
        self.need_scroll = False
        self.t = 0               # cycle clock
        self.done_at = None      # when the timer IRQ will fire
        self.waits = 0
        self.wait_cycles = 0

    # ---- hardware ----------------------------------------------------
    def hw_scroll(self):
        for r in range(ROWS - 1):
            self.screen[r * COLS:(r + 1) * COLS] = \
                self.screen[(r + 1) * COLS:(r + 2) * COLS]
        self.done_at = self.t + SCROLL_CYCLES

    def init_timer(self):
        pass                     # done_at already set by hw_scroll

    def advance(self, n):
        """Let n cycles pass, delivering the scroll-done interrupt."""
        target = self.t + n
        while self.done_at is not None and self.done_at <= target:
            self.t = self.done_at
            self.done_at = None
            self.on_scroll_done()
        self.t = target

    def wait_until_rdy(self):
        self.waits += 1
        if self.done_at is not None:
            self.wait_cycles += self.done_at - self.t
            self.advance(self.done_at - self.t)

    # ---- driver ------------------------------------------------------
    def putc(self, c):
        if self.busy:
            if self.cap:
                self.buf[self.bufp] = c
                self.bufp += 1
                self.cap -= 1
                return
            else:
                self.wait_until_rdy()
        self.screen[self.index] = c
        self.index += 1

    def newline(self):
        if self.busy:
            if not self.need_scroll:
                self.need_scroll = True
                return
            else:
                self.wait_until_rdy()
        if self.line < ROWS - 1:
            self.line += 1
            self.index = COLS * self.line
        else:
            self.hw_scroll()
            self.init_timer()
            self.busy = True

    def on_scroll_done(self):
        if self.literal:
            self.line -= 1
        self.index = COLS * self.line
        k = self.index
        end = self.index + COLS
        filled = CAP0 - self.cap
        reset_buffer = self.bufp - filled
        if self.literal:
            bound = filled                       # as written
        else:
            bound = self.index + filled          # candidate fix
        while k < bound:
            self.screen[k] = self.buf[reset_buffer + k - self.index]
            k += 1
        self.index = k
        self.bufp = reset_buffer
        if not self.literal:
            self.cap = CAP0                      # candidate fix
        while k < end:
            self.screen[k] = ' '
            k += 1
        if self.need_scroll:
            if not self.literal:
                self.need_scroll = False         # candidate fix
            self.hw_scroll()
            self.init_timer()
        else:
            self.busy = False

    def rows(self):
        return [''.join(self.screen[r * COLS:(r + 1) * COLS])
                for r in range(ROWS)]


def reference(stream):
    """Unbuffered, always-correct console, for comparison."""
    scr = [' '] * SCRSZ
    line = idx = 0
    for c in stream:
        if c == '\n':
            if line < ROWS - 1:
                line += 1
                idx = COLS * line
            else:
                for r in range(ROWS - 1):
                    scr[r * COLS:(r + 1) * COLS] = scr[(r + 1) * COLS:(r + 2) * COLS]
                scr[(ROWS - 1) * COLS:] = [' '] * COLS
                idx = COLS * line
        else:
            scr[idx] = c
            idx += 1
    return [''.join(scr[r * COLS:(r + 1) * COLS]) for r in range(ROWS)]
