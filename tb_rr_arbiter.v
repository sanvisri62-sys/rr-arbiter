//-----------------------------------------------------------------------------
// Self-checking testbench for rr_arbiter  (plain Verilog-2001)
//
// A reference model (model_ptr) runs inside the TB. Every clock edge the
// checker compares the DUT against it and flags:
//   E1  grant to a requester whose req is LOW
//   E2  more than one grant bit set
//   E3  wrong requester granted (round-robin order violated)
//   E4  grant_valid inconsistent with grant
//   E5  priority pointer changed without a grant / updated wrongly
//   E6  starvation (persistent requester waits more than 3 cycles)
//   E7  grant/grant_valid not 0 after / during reset
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_rr_arbiter;

  reg        clk;
  reg        rst_n;
  reg  [3:0] req;
  wire [3:0] grant;
  wire       grant_valid;

  integer errors;
  integer cycles;

  rr_arbiter dut (.clk(clk), .rst_n(rst_n), .req(req),
                  .grant(grant), .grant_valid(grant_valid));

  //---------------------------------------------------------------- clock
  initial clk = 1'b0;
  always #5 clk = ~clk;                      // 100 MHz

  //------------------------------------------------------- reference model
  reg [1:0] model_ptr;
  reg [3:0] exp_grant;
  integer   k, idx;
  integer   wait_cnt [0:3];
  reg [3:0] last_grant_seen;

  // expected winner for a given pointer and request vector
  function [3:0] ref_grant;
    input [1:0] p;
    input [3:0] r;
    integer j;
    reg     found;
    reg [1:0] n;
    begin
      ref_grant = 4'b0000;
      found     = 1'b0;
      for (j = 0; j < 4; j = j + 1) begin
        n = p + j;                           // wraps naturally (2-bit)
        if (!found && r[n]) begin
          ref_grant = 4'b0001 << n;
          found     = 1'b1;
        end
      end
    end
  endfunction

  function [1:0] next_after;                 // pointer after a grant
    input [3:0] g;
    input [1:0] p;
    begin
      case (g)
        4'b0001: next_after = 2'd1;
        4'b0010: next_after = 2'd2;
        4'b0100: next_after = 2'd3;
        4'b1000: next_after = 2'd0;
        default: next_after = p;
      endcase
    end
  endfunction

  task flag;
    input [8*40-1:0] msg;
    begin
      errors = errors + 1;
      $display("[%0t] ERROR: %0s | req=%b grant=%b valid=%b dut_ptr=%0d model_ptr=%0d",
               $time, msg, req, grant, grant_valid, dut.ptr, model_ptr);
    end
  endtask

  //---------------------------------------------------------------- checker
  // Samples values just BEFORE the DUT's non-blocking updates take effect.
  initial begin
    model_ptr = 2'd0;
    for (k = 0; k < 4; k = k + 1) wait_cnt[k] = 0;
  end

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (!rst_n) begin
      // E7: in reset, outputs must be zero
      if (grant !== 4'b0000 || grant_valid !== 1'b0) flag("E7 outputs not 0 in reset");
      model_ptr = 2'd0;
      for (k = 0; k < 4; k = k + 1) wait_cnt[k] = 0;
    end else begin
      exp_grant = ref_grant(model_ptr, req);

      // E5: DUT pointer must equal model pointer (catches change w/o grant)
      if (dut.ptr !== model_ptr) flag("E5 priority pointer wrong");

      // E1: only active requesters may be granted
      if ((grant & ~req) !== 4'b0000) flag("E1 inactive requester granted");

      // E2: at most one bit set
      if ((grant & (grant - 4'b0001)) !== 4'b0000) flag("E2 multiple grants");

      // E4: valid flag
      if (grant_valid !== (|grant)) flag("E4 grant_valid mismatch");

      // E3: exact round-robin order
      if (grant !== exp_grant) flag("E3 round-robin order violated");

      // E6: starvation monitor
      for (k = 0; k < 4; k = k + 1) begin
        if (req[k] && !grant[k]) wait_cnt[k] = wait_cnt[k] + 1;
        else                     wait_cnt[k] = 0;
        if (wait_cnt[k] > 3) flag("E6 starvation detected");
      end

      // advance the model
      model_ptr = next_after(exp_grant, model_ptr);
    end
  end

  //------------------------------------------------------------ stimulus
  // apply(): drive req on the falling edge, so it is stable at next rising edge
  task apply;
    input [3:0] r;
    begin
      @(negedge clk);
      req = r;
    end
  endtask

  task repeat_apply;
    input [3:0]  r;
    input integer n;
    integer m;
    begin
      for (m = 0; m < n; m = m + 1) apply(r);
    end
  endtask

  // synchronous-release reset
  task do_reset;
    begin
      @(negedge clk);
      req   = 4'b0000;
      rst_n = 1'b0;
      repeat (2) @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  integer i;

  initial begin
    errors = 0;
    cycles = 0;
    rst_n  = 1'b0;                           // power-up reset
    req    = 4'b0000;
    $dumpfile("rr_arbiter.vcd");
    $dumpvars(0, tb_rr_arbiter);

    // ---------- TEST 1: reset behaviour -----------------------------------
    $display("TEST 1: reset");
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    apply(4'b0000);
    // reset in the MIDDLE of operation with req HIGH (asynchronous check)
    repeat_apply(4'b1111, 3);                // ptr is now non-zero
    #2 rst_n = 1'b0;                         // assert away from clock edge
    #1 if (grant !== 4'b0000 || grant_valid !== 1'b0) flag("E7 async reset not immediate");
    @(negedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat_apply(4'b1111, 2);                // first grant after reset must be 0

    // ---------- TEST 2: no requests ---------------------------------------
    $display("TEST 2: no requests");
    do_reset;
    repeat_apply(4'b0000, 5);

    // ---------- TEST 3: single request, every requester --------------------
    $display("TEST 3: single request");
    do_reset;
    for (i = 0; i < 4; i = i + 1) repeat_apply(4'b0001 << i, 2);

    // ---------- TEST 4: multiple simultaneous requests --------------------
    $display("TEST 4: multiple simultaneous requests");
    do_reset;
    apply(4'b0101); apply(4'b1010); apply(4'b0110); apply(4'b1100);
    apply(4'b0011); apply(4'b1001); apply(4'b0111); apply(4'b1110);

    // ---------- TEST 5: all four continuously asserted --------------------
    $display("TEST 5: req = 1111 continuously");
    do_reset;
    repeat_apply(4'b1111, 12);               // expect 0,1,2,3,0,1,2,3,...

    // ---------- TEST 6: changing request patterns -------------------------
    $display("TEST 6: changing patterns (directed + random)");
    do_reset;
    apply(4'b0001); apply(4'b1000); apply(4'b0110); apply(4'b1111);
    apply(4'b0000); apply(4'b1010); apply(4'b0101); apply(4'b1111);
    for (i = 0; i < 300; i = i + 1) apply($random);

    // ---------- TEST 7: request withdrawal ---------------------------------
    $display("TEST 7: request withdrawal");
    do_reset;
    apply(4'b1111);                          // 0 granted
    apply(4'b1110);                          // 0 withdraws -> 1 granted
    apply(4'b1100);                          // 1 withdraws -> 2 granted
    apply(4'b1000);                          // 2 withdraws -> 3 granted
    apply(4'b0000);                          // all withdraw
    apply(4'b0100);

    // ---------- TEST 8: priority wrap-around 3 -> 0 -----------------------
    $display("TEST 8: wrap-around");
    do_reset;
    apply(4'b0100);                          // grant 2 -> ptr = 3
    apply(4'b0011);                          // ptr=3, req=0011 -> grant 0
    apply(4'b1000);                          // grant 3 -> ptr = 0
    apply(4'b1001);                          // ptr=0 -> grant 0, not 3
    apply(4'b0000);

    // ---------- TEST 9: persistent requests --------------------------------
    $display("TEST 9: persistent requests");
    do_reset;
    repeat_apply(4'b1010, 8);                // 1,3,1,3...
    repeat_apply(4'b0111, 9);                // 0,1,2,0,1,2...

    // ---------- TEST 10: fairness / starvation -----------------------------
    $display("TEST 10: fairness");
    do_reset;
    repeat_apply(4'b1111, 40);
    for (i = 0; i < 4; i = i + 1) begin      // one requester joins late
      repeat_apply(4'b1111 & ~(4'b0001 << i), 8);
      repeat_apply(4'b1111, 4);
    end

    // ---------- finish ------------------------------------------------------
    apply(4'b0000);
    repeat (2) @(negedge clk);
    $display("--------------------------------------------");
    if (errors == 0) $display("RESULT: PASS  (%0d cycles checked, 0 errors)", cycles);
    else             $display("RESULT: FAIL  (%0d errors)", errors);
    $display("--------------------------------------------");
    $finish;
  end

  // safety net
  initial begin
    #200000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
