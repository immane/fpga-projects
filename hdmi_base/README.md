# hdmi_base

HDMI base design for Tang Nano 20K (GW2AR-18C), using a 27 MHz input clock and a 1080p test-pattern pipeline.

## Overview

This project includes a complete basic video path:

- clock generation (27 MHz -> HDMI 5x -> pixel clock)
- 1080p timing generation (`hsync`, `vsync`, `de`, `x`, `y`)
- RGB pattern generation (9 horizontal color bars)
- TMDS encoding (3 channels)
- 10:1 serialization and differential output buffers

The top-level is [src/main.v](src/main.v).

## Clock Tree

- input clock: 27.000 MHz
- PLL output clock: HDMI 5x clock (`clk_hdmi_5x`)
- CLKDIV output clock: pixel clock (`clk_hdmi`), divide-by-5 from `clk_hdmi_5x`

The PLL wrapper is [src/gowin_rpll/rpll_hdmi.v](src/gowin_rpll/rpll_hdmi.v), and the divide-by-5 clock divider is [src/gowin_clkdiv/clkdiv_hdmi.v](src/gowin_clkdiv/clkdiv_hdmi.v).

### PLL PROFILE Mapping

`PLL_PROFILE` is defined in [src/main.v](src/main.v):

- `0`: 1080p30, pixel 74.25 MHz, 5x 371.25 MHz
- `1`: 1080p40, pixel 99.00 MHz, 5x 495.00 MHz
- `2`: 1080p50, pixel 123.75 MHz, 5x target 618.75 MHz
- `3`: 1080p60, pixel 148.50 MHz, 5x 742.50 MHz

Note: the TMDS serializer uses the 5x clock domain.

## Top-Level Ports

Defined in [src/main.v](src/main.v):

- inputs:
  - `clk` (27 MHz)
  - `rst_n` (active-low reset)
- debug output:
  - `led`
- HDMI differential outputs:
  - `tmds_clk_p`, `tmds_clk_n`
  - `tmds_data0_p`, `tmds_data0_n` (blue)
  - `tmds_data1_p`, `tmds_data1_n` (green)
  - `tmds_data2_p`, `tmds_data2_n` (red)

## RTL Blocks

- [src/vid_timing_gen.v](src/vid_timing_gen.v): 1920x1080 timing generator.
- [src/pattern_gen.v](src/pattern_gen.v): 9 horizontal bars (red, orange, yellow, green, cyan, blue, purple, black, white).
- [src/tmds_encoder.v](src/tmds_encoder.v): TMDS channel encoder.
- [src/serlizer_10to1.v](src/serlizer_10to1.v): OSER10 wrapper for 10:1 serialization.

## Constraints

- physical constraints: [src/hdmi_base.cst](src/hdmi_base.cst)
- timing constraints: [src/hdmi_base.sdc](src/hdmi_base.sdc)

Current CST mapping follows Tang Nano 20K HDMI pin groups (TMDS clock + 3 data pairs).

## Build (Gowin EDA)

1. Open [hdmi_base.gprj](hdmi_base.gprj).
2. Confirm all RTL/IP/constraint files are included.
3. Run Synthesis.
4. Run Place & Route.
5. Program bitstream to board.

Build outputs are under [impl](impl).

## Simulation

Testbenches are in [tb](tb), including:

- [tb/main_smoke_tb.v](tb/main_smoke_tb.v)
- [tb/main_hdmi_tb.v](tb/main_hdmi_tb.v)
- [tb/vid_timing_gen_tb.v](tb/vid_timing_gen_tb.v)
- [tb/pattern_gen_tb.v](tb/pattern_gen_tb.v)
- [tb/tmds_encoder_tb.v](tb/tmds_encoder_tb.v)
- [tb/tmds_encoder_golden_tb.v](tb/tmds_encoder_golden_tb.v)

For Icarus simulation, vendor primitives are stubbed in [tb/gowin_stub.v](tb/gowin_stub.v).

## Current Notes

- The HDMI domain reset is gated with PLL lock in [src/main.v](src/main.v).
- TMDS control alignment latency is configurable in [src/main.v](src/main.v) (`TMDS_ALIGN_LATENCY`).
- Timing constraints in [src/hdmi_base.sdc](src/hdmi_base.sdc) constrain the HDMI 5x clock at the worst-case profile, so one SDC can cover 30/40/50/60 modes.
- If edge artifacts appear (for example 1-pixel seam), first verify control/data alignment and refresh timing relationships.
