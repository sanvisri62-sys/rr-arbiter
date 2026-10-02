//-----------------------------------------------------------------------------
// rr_arbiter : 4-requester round-robin arbiter (synthesizable Verilog-2001)
//
//  - grant is COMBINATIONAL from (req, ptr): reacts to the current request
//    pattern in the same cycle (spec items 5 and 8).
//  - ptr (priority pointer) is the only state. It updates on the clock edge,
//    only when a grant was issued (spec item 6).
//  - rst_n is active-low ASYNCHRONOUS reset: ptr -> 0, grant -> 0.
//-----------------------------------------------------------------------------
module rr_arbiter (
  input        clk,
  input        rst_n,
  input  [3:0] req,
  output [3:0] grant,
  output       grant_valid
);

  reg [1:0] ptr;        // who is searched FIRST (0..3)
  reg [3:0] grant_c;    // combinational grant (before reset gating)
  reg [1:0] next_ptr;   // pointer value to load at next clock edge

  //---------------------------------------------------------------------------
  // 1) Priority search: start at ptr, go around the circle, take first req
  //---------------------------------------------------------------------------
  always @(*) begin
    grant_c = 4'b0000;                       // default => no latch
    case (ptr)
      2'd0: begin                            // order 0 -> 1 -> 2 -> 3
        if      (req[0]) grant_c = 4'b0001;
        else if (req[1]) grant_c = 4'b0010;
        else if (req[2]) grant_c = 4'b0100;
        else if (req[3]) grant_c = 4'b1000;
      end
      2'd1: begin                            // order 1 -> 2 -> 3 -> 0
        if      (req[1]) grant_c = 4'b0010;
        else if (req[2]) grant_c = 4'b0100;
        else if (req[3]) grant_c = 4'b1000;
        else if (req[0]) grant_c = 4'b0001;
      end
      2'd2: begin                            // order 2 -> 3 -> 0 -> 1
        if      (req[2]) grant_c = 4'b0100;
        else if (req[3]) grant_c = 4'b1000;
        else if (req[0]) grant_c = 4'b0001;
        else if (req[1]) grant_c = 4'b0010;
      end
      default: begin                         // ptr = 3: order 3 -> 0 -> 1 -> 2
        if      (req[3]) grant_c = 4'b1000;
        else if (req[0]) grant_c = 4'b0001;
        else if (req[1]) grant_c = 4'b0010;
        else if (req[2]) grant_c = 4'b0100;
      end
    endcase
  end

  //---------------------------------------------------------------------------
  // 2) Next pointer: one after the winner; unchanged if nobody won
  //---------------------------------------------------------------------------
  always @(*) begin
    case (grant_c)
      4'b0001: next_ptr = 2'd1;              // granted 0 -> priority 1
      4'b0010: next_ptr = 2'd2;              // granted 1 -> priority 2
      4'b0100: next_ptr = 2'd3;              // granted 2 -> priority 3
      4'b1000: next_ptr = 2'd0;              // granted 3 -> priority 0 (wrap)
      default: next_ptr = ptr;               // no grant -> hold
    endcase
  end

  //---------------------------------------------------------------------------
  // 3) Pointer register: async active-low reset, starts at requester 0
  //---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) ptr <= 2'd0;
    else        ptr <= next_ptr;
  end

  //---------------------------------------------------------------------------
  // 4) Outputs. Gating with rst_n guarantees grant = 0 while in reset,
  //    even if req is HIGH during reset.
  //---------------------------------------------------------------------------
  assign grant       = rst_n ? grant_c : 4'b0000;
  assign grant_valid = |grant;

endmodule
