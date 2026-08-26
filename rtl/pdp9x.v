// 18-bit accumulator machine, microcoded.  Verilog 2005, for iverilog.
//
// The field positions and the symbolic values come from ufields.vh, which
// ucode.py generates, so the RTL cannot drift away from the microassembler.
// One microinstruction per clock: everything is read from the current state
// and latched at the edge, which is what makes this comparable with the
// Python engine cycle for cycle.

`include "ufields.vh"

module pdp9x (
    input  wire        clk,
    input  wire        rst,
    output wire        halted,
    // the IOT strobe is brought out so the testbench can be the device model
    output wire        io_stb,
    output wire [13:0] io_field,
    output wire [17:0] io_ac,
    input  wire [17:0] io_in,
    input  wire        io_skip,
    // eight device requests, one per vector entry
    input  wire  [7:0] req
);

    // ---------------- state ----------------
    reg [17:0] ac, ix, t, di, dobuf;
    reg [11:0] sp;
    reg [16:0] pc, ar;
    reg [17:0] ir;
    reg        l, ien, hlt;
    reg  [3:0] msk;
    reg  [4:0] pgl;
    reg  [6:0] upc;
    reg  [7:0] imask;

    assign halted = hlt;

    // ---------------- control store and maps ----------------
    reg [`UW_WIDTH-1:0] cs   [0:127];
    reg  [7:0]          map1 [0:63];
    reg  [7:0]          map2 [0:15];
    initial begin
        $readmemh("ucode.hex", cs);
        $readmemh("map1.hex",  map1);
        $readmemh("map2.hex",  map2);
    end

    wire [`UW_WIDTH-1:0] uw = cs[upc];

    // ---------------- memory ----------------
    reg [17:0] mem [0:131071];
    wire [17:0] bd = mem[ar];

    // ---------------- interrupt: one point, no cycle of its own ----------------
    wire fetching = (upc == `L_FETCH)   || (upc == `L_FETCH_A) ||
                    (upc == `L_FETCH_G) || (upc == `L_FETCH_S) ||
                    (upc == `L_FETCH_I);
    reg  [2:0] irq_dev;
    reg  [2:0] irq_devl;
    reg        irq_now;
    integer d;
    always @* begin
        irq_now = 0;
        irq_dev = 0;
        if (fetching && ien)
            for (d = 1; d < 8; d = d + 1)
                if (!irq_now && req[d] && imask[d]) begin
                    irq_now = 1;
                    irq_dev = d[2:0];
                end
    end

    // ---------------- the register IR names ----------------
    wire irx = ir[11];

    // ---------------- bus A ----------------
    reg [17:0] busa;
    always @* case (`F_ASRC)
        `ASRC_AC:     busa = ac;
        `ASRC_IX:     busa = ix;
        `ASRC_SP:     busa = {6'b0, sp};
        `ASRC_T:      busa = t;
        `ASRC_PC:     busa = {l, pc};
        `ASRC_FROMIR: busa = irx ? ix : ac;
        default:      busa = 18'b0;
    endcase

    // ---------------- bus B ----------------
    reg [17:0] busb;
    always @* case (`F_BSRC)
        `BSRC_DI:    busb = di;
        `BSRC_IRF11: busb = {7'b0, ir[10:0]};
        `BSRC_IRF12: busb = {6'b0, ir[11:0]};
        `BSRC_DEV:   busb = {15'b0, irq_devl};        // the vector entry
        default:     busb = 18'b0;
    endcase

    // ---------------- ALU ----------------
    // FROMIR means take the function from the opcode, and taking it from the
    // opcode includes taking which flag drives L: carry for TAD, overflow for
    // TAS.  That distinction does not fit in the four bit function field.
    reg  [3:0] aluop;
    reg        from_tas;
    always @* begin
        from_tas = 0;
        if (`F_ALU == `ALU_FROMIR) begin
            case (ir[17:14])
                4'd0:    aluop = `ALU_ADD;
                4'd1:  begin aluop = `ALU_ADD; from_tas = 1; end
                4'd2:    aluop = `ALU_AND;
                4'd3:    aluop = `ALU_XOR;
                4'd5:    aluop = `ALU_PASSB;
                4'd7:    aluop = `ALU_OR;
                4'd10:   aluop = `ALU_ADD1;
                4'd11:   aluop = `ALU_DECB;
                default: aluop = `ALU_PASSB;
            endcase
        end else aluop = `F_ALU;
    end

    wire [18:0] sum  = {1'b0, busa} + {1'b0, busb};
    wire [18:0] sum1 = sum + 19'd1;
    wire [18:0] dec  = {1'b0, busa} + 19'h3FFFF;
    wire        ovf  = (busa[17] == busb[17]) && (sum[17] != busa[17]);

    reg [17:0] r;
    reg        lout;
    // group 1 is dedicated logic, applied to AC, L and IX at once
    reg [17:0] g1ac;
    reg        g1l;
    reg        g1t;
    always @* begin
        g1ac = busa;
        g1l  = l;
        if (ir[11]) g1ac = 18'b0;                       // CLA
        if (ir[10]) g1l  = 1'b0;                        // CLL
        if (ir[9])  g1ac = ~g1ac;                       // CMA
        if (ir[8])  g1l  = ~g1l;                        // CML
        if (ir[3])  g1ac = g1ac + 18'd1;                // IAC
        // Both rotates need the bit that leaves kept aside: assigning the link
        // first makes the shift bring in the bit it just took, and taking it
        // from bus A ignores whatever CLA, CMA or IAC did above.
        if (ir[7])  begin g1t = g1ac[17]; g1ac = {g1ac[16:0], g1l}; g1l = g1t; end
        if (ir[6])  begin g1t = g1ac[0];  g1ac = {g1l, g1ac[17:1]}; g1l = g1t; end
        if (ir[5])  g1ac = {g1ac[16:0], 1'b0};          // SHA
        if (ir[4])  g1ac = {g1ac[17], g1ac[17:1]};      // SRA
    end

    always @* begin
        lout = l;
        case (aluop)
            `ALU_ADD:    begin r = sum[17:0];  lout = from_tas ? ovf : sum[18]; end
            `ALU_ADD1:   begin r = sum1[17:0]; lout = sum1[18]; end
            `ALU_DEC:    begin r = dec[17:0];  lout = dec[18]; end
            `ALU_AND:    r = busa & busb;
            `ALU_OR:     r = busa | busb;
            `ALU_XOR:    r = busa ^ busb;
            `ALU_PASSA:  r = busa;
            `ALU_PASSB:  r = busb;
            `ALU_DECB:   r = busb - 18'd1;   // DSZ: the datum arrives on bus B
            `ALU_CMA:    r = ~busa;
            `ALU_SHL:    r = {busa[16:0], 1'b0};
            `ALU_SHR:    r = {busa[17], busa[17:1]};
            `ALU_ROL:    begin r = {busa[16:0], l}; lout = busa[17]; end
            `ALU_ROR:    begin r = {l, busa[17:1]}; lout = busa[0]; end
            `ALU_G1:     begin r = g1ac; lout = g1l; end
            default:     r = busa;
        endcase
    end

    // ---------------- DO, straight off the register file ----------------
    reg [17:0] donext;
    always @* case (`F_DOSRC)
        `DOSRC_FROMIR: donext = irx ? ix : ac;
        `DOSRC_LPC:    donext = {l, pc};
        `DOSRC_ALU:    donext = r;
        `DOSRC_AC:     donext = ac;
        `DOSRC_IX:     donext = ix;
        `DOSRC_SP:     donext = {6'b0, sp};
        default:       donext = dobuf;
    endcase

    // ---------------- conditions ----------------
    // The skip group's conditions, as the 18-bit family had them: zero, link
    // and the sign, OR'd, with bit 11 inverting.  Skip-on-interrupts-enabled
    // used to sit on bit 2; it was ours, DEC had no such thing, and it now
    // lives in the IO group with the processor's other state.
    wire g2 = ir[11] ^ ((ir[0] & (ac == 18'b0)) | (ir[1] & l) | (ir[2] & ac[17]));
    reg  cond;
    always @* case (`F_CC)
        `CC_Z:   cond = (dobuf == 18'b0);
        `CC_NZ:  cond = ((irx ? ix : ac) != di);
        `CC_G2:  cond = g2;
        default: cond = 1'b0;
    endcase

    wire skipping = (upc == `L_FETCH_S) && cond;
    // SKIPC steps PC when the condition holds and goes straight to the fetch,
    // so a comparison needs no state of its own after it
    wire skipc = (`F_SEQ == `SEQ_SKIPC) && cond;
    // An IOT that tests a flag steps PC as it goes.  The port for the device's
    // answer was declared and never read, so no device skip worked here at all
    // -- the sieve uses two IOTs and neither of them skips, which is why it
    // never showed.
    wire iot_skip = (`F_MEM == `MEM_IO) && (io_skip || io_skip_i);
    wire load_ir  = fetching && !irq_now && !skipping;

    // ---------------- PC and AR ----------------
    wire        pcinc  = (`F_ARSRC == `ARSRC_PCNEXT) && !irq_now;
    wire [16:0] pcnext = pcinc ? (pc + 17'd1) : pc;

    reg [16:0] arnext;
    always @* case (`F_ARSRC)
        `ARSRC_ALU:    arnext = r[16:0];
        `ARSRC_PC:     arnext = pcnext;
        `ARSRC_PCNEXT: arnext = pcnext;
        `ARSRC_DI:     arnext = di[16:0];
        `ARSRC_PAGE:   arnext = {pgl, ir[11:0]};
        `ARSRC_STACK:  arnext = {5'b00001, r[11:0]};   // decremented SP, push
        `ARSRC_STACKR: arnext = {5'b00001, sp};        // SP as it stands, pop
        default:       arnext = ar;
    endcase

    // ---------------- IOT, and the wait it can start ----------------
    // Device 0 is the processor itself, and sub-function 3 with iop4 stops the
    // fetch until a device asks for attention.  Waiting is not halting: the
    // clock runs, the microsequencer simply does not advance, so the cost is
    // cycles and no instructions.
    wire is_wait = (`F_MEM == `MEM_IO) && (ir[13:11] == 3'd0)
                   && (ir[10:8] == 3'd3) && ir[2];
    // device 0, sub 4 and 5 with IOP1: skip on interrupts on, and off
    wire cpu_io  = (`F_MEM == `MEM_IO) && (ir[13:11] == 3'd0) && ir[0];
    wire io_skip_i = cpu_io && (((ir[10:8] == 3'd4) && ien)
                             || ((ir[10:8] == 3'd5) && !ien));
    reg  waiting;
    wire wake = |req[7:1];

    assign io_stb   = (`F_MEM == `MEM_IO);
    assign io_field = ir[13:0];
    assign io_ac    = ac;

    // ---------------- the mask encoder ----------------
    // It answers the dispatch in the fetch's own cycle, so a stack instruction
    // costs its population count.  The mask it works on is the one just read
    // when the dispatch comes from a fetch.
    // Both the mask and the direction come from the word just read, not from
    // the instruction still in IR: at a fetch, IR is a whole instruction behind.
    wire [3:0]  mcur  = load_ir ? bd[3:0] : msk;
    wire        pushc = load_ir ? ~bd[11] : ~ir[11];
    reg  [6:0] mask_entry;
    reg  [3:0] mask_left;
    always @* begin
        if (mcur == 4'b0) begin mask_entry = `L_FETCH_I; mask_left = 4'b0; end
        else if (pushc) begin                         // push takes the lowest
            if (mcur[0])      begin mask_entry = `L_PSH_SP;  mask_left = mcur & 4'b1110; end
            else if (mcur[1]) begin mask_entry = `L_PSH_LPC; mask_left = mcur & 4'b1101; end
            else if (mcur[2]) begin mask_entry = `L_PSH_IX;  mask_left = mcur & 4'b1011; end
            else              begin mask_entry = `L_PSH_AC;  mask_left = mcur & 4'b0111; end
        end else begin                                // pop takes the highest
            if (mcur[3])      begin mask_entry = `L_POP_AC;  mask_left = mcur & 4'b0111; end
            else if (mcur[2]) begin mask_entry = `L_POP_IX;  mask_left = mcur & 4'b1011; end
            else if (mcur[1]) begin mask_entry = `L_POP_LPC; mask_left = mcur & 4'b1101; end
            else              begin mask_entry = `L_POP_SP;  mask_left = mcur & 4'b1110; end
        end
    end

    // ---------------- the sequencer ----------------
    reg [6:0] upcnext;
    reg [3:0] msknext;
    always @* begin
        // The mask a fetch has just read is the one the dispatch works on, and
        // the bit it takes must stay taken: loading the field afterwards would
        // put the bit back and the push would repeat for ever.
        msknext = load_ir ? bd[3:0] : msk;
        case (`F_SEQ)
            `SEQ_NEXT:  upcnext = upc + 7'd1;
            `SEQ_JUMP:  upcnext = `F_NA;
            `SEQ_MAP: begin
                upcnext = map1[load_ir ? bd[17:12] : ir[17:12]][6:0];
                if (upcnext == `L_G3) begin
                    upcnext = mask_entry;
                    msknext = mask_left;
                end
            end
            `SEQ_MAP2:  upcnext = map2[ir[17:14]][6:0];
            `SEQ_BRANCH: upcnext = cond ? `F_NA : upc + 7'd1;
            `SEQ_SKIPC: upcnext = `L_FETCH;
            `SEQ_SKIPF: upcnext = skipping ? `L_FETCH
                                           : map1[bd[17:12]][6:0];
            default: begin                       // MAPMASK
                upcnext = mask_entry;
                msknext = mask_left;
            end
        endcase
    end

    // ---------------- the edge ----------------
    reg [16:0] pcw;
    always @(posedge clk) begin
        if (rst) begin
            upc <= `L_FETCH; ien <= 0; sp <= 12'b0; hlt <= 0; waiting <= 0;
            imask <= 8'hFF; msk <= 4'b0; pgl <= 5'b0;
            ac <= 18'b0; ix <= 18'b0; t <= 18'b0; di <= 18'b0;
            dobuf <= 18'b0; l <= 1'b0; ir <= 18'b0;
            pc <= mem[0][16:0]; ar <= mem[0][16:0];
        end else if (waiting) begin
            if (wake) waiting <= 1'b0;
        end else if (!hlt) begin
            // memory
            if (`F_MEM == `MEM_RD) di <= bd;
            if (`F_MEM == `MEM_WR) mem[ar] <= dobuf;

            dobuf <= donext;

            // writes from bus R; PC takes the AR mux value, not bus R, because
            // a jump wants the address it has just formed and AR is on no bus
            pcw = (skipc || iot_skip) ? (pc + 17'd1) : pcnext;
            case (`F_RDST)
                `RDST_AC:  ac <= r;
                `RDST_IX:  ix <= r;
                `RDST_SP:  sp <= r[11:0];
                `RDST_T:   t  <= r;
                `RDST_PC:  pcw = arnext;
                `RDST_FROMIR: if (irx) ix <= r; else ac <= r;
                default: ;
            endcase

            if (`F_ALU == `ALU_G1) begin
                ac <= g1ac;
                l  <= g1l;
                if (ir[2]) ix <= ix + 18'd1;     // IXC, beside the AC path
                if (ir[0]) hlt <= 1'b1;          // HLT
            end else begin
                if (`F_LCTL == `LCTL_FROMALU) l <= lout;
                if (`F_LCTL == `LCTL_FROMDI)  l <= di[17];
            end

            if (`F_SPUP) sp <= sp + 12'd1;

            case (`F_ICTL)
                `ICTL_ICLR: ien <= 1'b0;
                `ICTL_ISET: ien <= 1'b1;
                `ICTL_IFROMIR: if (ir[10:9] == 2'd1) ien <= 1'b0;
                               else if (ir[10:9] == 2'd2) ien <= 1'b1;
                default: ;
            endcase

            pc <= pcw;
            ar <= (skipc || iot_skip) ? (pc + 17'd1) : arnext;
            msk <= msknext;

            if (load_ir) begin
                ir  <= bd;
                pgl <= pc[16:12];                // before the increment
            end

            if (is_wait) waiting <= 1'b1;
            if (irq_now) begin
                upc <= `L_IRQ;
                irq_devl <= irq_dev;
            end else
                upc <= upcnext;
        end
    end
endmodule
