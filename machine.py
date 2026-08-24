"""Blitter + timer as memory mapped devices, wrapped around the CPU core."""
from sim import CPU, W, A

# ---- address map -------------------------------------------------------
# 0x000-0x003  interrupt vectors
# 0x004-0x1FF  zero page variables
# 0x200-0x3FF  screen, 512 words, 16 rows x 32 cols, 7-bit ASCII
# 0x400        scroll command register (write only)
# 0x401-0x7FB  more zero page variables
# 0x7FC-0x7FF  timer: IRQ(ro) ACK(wo) ARM(so) THI(wo)
# 0x1000-0x1FFF stack page
SCREEN = 0x4000          # framebuffer, outside the zero page, write only
COLS, ROWS = 32, 16
SCRSZ = COLS * ROWS

# Everything that is not the framebuffer is reached with IOT:
#   17..14  13..11  10..8   7..4   3    2     1     0
#    1110   dev(3)  sub(3)  ----  CLA  IOP4  IOP2  IOP1
# IOP1 tests a flag and skips, IOP2 moves device->AC, IOP4 moves AC->device.
# Device 0 is the processor, so that vector entry 0 is reset.  Every other
# device number is its own vector entry.
DEV_CPU, DEV_BLIT, DEV_TIMER, DEV_KBD, DEV_LED = 0, 1, 2, 3, 4


SCROLL_CYCLES = 7680
CHAR_CYCLES = 8      # the cell counter walks 8 font scanlines and is deaf meanwhile


class Machine(CPU):
    def __init__(self, mem=None):
        CPU.__init__(self, mem)
        self.scroll_until = -1        # cycle count at which the blitter frees up
        self.dropped = 0              # screen writes swallowed during a scroll
        self.t_count = 0
        self.t_armed = False
        self.t_irq = False
        self.scrolls = 0
        self.next_ok = 0          # earliest cycle the cell counter listens again
        self.too_fast = 0         # writes lost because the counter was still busy
        self.violations = []
        self.fb_reads = []        # CPU reads of the write-only framebuffer
        # Keyboard: four registers.  A keystroke latches the raw code and the
        # modifier set, and the interrupt is raised on release, by which point
        # both latches are stable.  Scanning stops until the CPU acknowledges,
        # so nothing can overwrite a keystroke that has not been collected.
        self.kbd_raw = 0
        self.kbd_mods = 0
        self.kbd_flag = False
        self.kbd_scanning = True
        self.kbd_input = []      # list of (character, modifier mask)
        self.kbd_pos = 0
        self.leds = 0

    # ---- device clock, advanced by the memory system ------------------
    def feed_keyboard(self):
        if self.kbd_scanning and not self.kbd_flag and self.kbd_pos < len(self.kbd_input):
            ch, mods = self.kbd_input[self.kbd_pos]
            self.kbd_pos += 1
            self.kbd_raw = ord(ch) & 0x7F
            self.kbd_mods = mods & 7
            self.kbd_scanning = False     # the latches freeze on release
            self.kbd_flag = True

    def tick(self, n=1):
        self.feed_keyboard()
        if self.t_armed:
            for _ in range(n):
                self.t_count = (self.t_count + 1) & 0xFFFF
                if self.t_count == 0:
                    self.t_armed = False
                    self.t_irq = True
                    break
        self.refresh_irq()

    def refresh_irq(self):
        self.req[DEV_TIMER] = self.t_irq
        self.req[DEV_KBD] = self.kbd_flag

    def fetch(self, a):
        self.cycles += self.FETCH_CYCLES
        self.tick(self.FETCH_CYCLES)
        return self.m[a & A] & W

    def busy(self):
        return self.cycles < self.scroll_until

    # ---- memory / MMIO ------------------------------------------------
    def rd(self, a):
        a &= A
        self.cycles += self.DATA_CYCLES
        self.tick(self.DATA_CYCLES)
        if SCREEN <= a < SCREEN + SCRSZ:
            # the framebuffer is write only: the cell needs the character as an
            # index into the scanline ROM, there is nothing to read back.
            self.fb_reads.append((self.pc, a))
            return 0
        return self.m[a] & W

    def wr(self, a, v):
        a &= A
        self.cycles += self.DATA_CYCLES
        self.tick(self.DATA_CYCLES)
        v &= W
        if SCREEN <= a < SCREEN + SCRSZ:
            if self.busy():
                self.dropped += 1             # swallowed: a scroll is running
                return
            if self.cycles < self.next_ok:
                self.too_fast += 1            # swallowed: cell counter still drawing
                if len(self.violations) < 5:
                    self.violations.append((self.pc, self.next_ok - self.cycles))
                return
            self.next_ok = self.cycles + CHAR_CYCLES
        self.m[a] = v

    # ---- IOT ----------------------------------------------------------
    def io(self, f):
        dev = (f >> 11) & 7
        sub = (f >> 8) & 7
        iop1, iop2, iop4, cla = f & 1, (f >> 1) & 1, (f >> 2) & 1, (f >> 3) & 1
        if cla:
            self.ac = 0
        if self.io_cpu(f):
            return
        if dev == DEV_BLIT:
            if iop1:
                ready = not self.busy()
                if (sub == 1) == ready:       # sub0 = skip if busy, sub1 = if ready
                    self.skip()
            if iop4 and not self.busy():
                self.do_scroll()
        elif dev == DEV_TIMER:
            if iop1 and self.t_irq:
                self.skip()
            if iop4:
                if sub == 0:
                    self.t_armed = True
                elif sub == 1:
                    self.t_irq = False
                    self.refresh_irq()
                elif sub == 2:
                    self.t_count = (self.ac & 0xFF) << 8
        elif dev == DEV_KBD:
            if iop1 and sub == 2 and self.kbd_flag:
                self.skip()
            if iop2:
                if sub == 0:
                    self.ac |= self.kbd_raw & 0x7F
                elif sub == 1:
                    self.ac |= self.kbd_mods & 7
            if iop4 and sub == 3:
                self.kbd_flag = False
                self.kbd_scanning = True
                self.refresh_irq()
        elif dev == DEV_LED:
            if iop4:
                self.leds = self.ac

    # ---- blitter ------------------------------------------------------
    def do_scroll(self):
        for r in range(ROWS - 1):
            src = SCREEN + (r + 1) * COLS
            dst = SCREEN + r * COLS
            self.m[dst:dst + COLS] = self.m[src:src + COLS]
        self.scroll_until = self.cycles + SCROLL_CYCLES
        self.next_ok = self.scroll_until
        self.scrolls += 1

    # ---- host side helper --------------------------------------------
    def console(self):
        rows = []
        for r in range(ROWS):
            base = SCREEN + r * COLS
            rows.append(''.join(chr(self.m[base + c] & 0x7F) for c in range(COLS)))
        return rows
