# Round Robin Arbiter

A 4-request Round Robin Arbiter designed and verified using Verilog.

## Overview

This project implements a Round Robin Arbitration mechanism that provides fair access to a shared resource among multiple requesters.

The arbiter uses a rotating priority scheme so that continuously requesting clients are served without starvation.

## Files

- `rr_arbiter.v` — Round Robin Arbiter design
- `tb_rr_arbiter.v` — Verilog testbench
- `rr_arbiter.vcd` — Simulation waveform data

## Verification

The design was tested using 10 test cases:

1. Reset
2. No requests
3. Single request
4. Multiple simultaneous requests
5. Continuous requests
6. Changing request patterns
7. Request withdrawal
8. Wrap-around
9. Persistent requests
10. Fairness

### Result

**PASS — 498 cycles checked, 0 errors**

## Tools Used

- Verilog
- Icarus Verilog
- GTKWave

## Simulation

Compile:

```bash
iverilog -g2001 -o sim rr_arbiter.v tb_rr_arbiter.v
vvp sim
gtkwave rr_arbiter.vcd
