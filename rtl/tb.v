// Testbench: loads a program, plays the harness devices, reports.
`timescale 1ns/1ps
module tb;
    reg clk = 0, rst = 1;
    wire halted, io_stb;
    wire [13:0] io_field;
    wire [17:0] io_ac;
    reg  [17:0] io_in = 0;
    reg         io_skip = 0;
    reg   [7:0] req = 0;

    pdp9x cpu (.clk(clk), .rst(rst), .halted(halted), .io_stb(io_stb),
               .io_field(io_field), .io_ac(io_ac), .io_in(io_in),
               .io_skip(io_skip), .req(req));

    integer cycles = 0;
    integer i;
    reg [1023:0] prog;

    always #5 clk = ~clk;

    // device 5 is the test harness: a print port
    always @(posedge clk)
        if (io_stb && !rst && io_field[13:11] == 3'd5 && io_field[10:8] == 3'd2)
            $display("OUT %0d", io_ac);

    initial begin
        if (!$value$plusargs("prog=%s", prog)) prog = "sieve4.hex";
        for (i = 0; i < 131072; i = i + 1) cpu.mem[i] = 18'b0;
        $readmemh(prog, cpu.mem);
        @(negedge clk) rst = 0;
        if ($test$plusargs("trace"))
            for (i = 0; i < 200000; i = i + 1) begin
                @(posedge clk);
                $display("%0d %0d %06o %06o %06o %0d %0o %06o",
                         i, cpu.upc, cpu.ir, cpu.ac, cpu.ix, cpu.l, cpu.pc, cpu.ar);
            end
        while (!halted && cycles < 4000000) begin
            @(posedge clk);
            cycles = cycles + 1;

        end
        $display("cicli %0d  halted %0d  AC %0o IX %0o L %0d SP %0o",
                 cycles, halted, cpu.ac, cpu.ix, cpu.l, cpu.sp);
        $finish;
    end
endmodule
