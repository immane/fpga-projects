# hdmi_base

HDMI base design for Tang Nano 20K (GW2AR-18C), built around a 27 MHz input clock and a TMDS output pipeline.

This repository is used as a bring-up project for:

1. video timing and TMDS verification
2. clock-domain-crossing experiments
3. future external framebuffer input (pSRAM or DDR3)

## Current Design Status

Top-level is [src/main.v](src/main.v).

Current default configuration in [src/main.v](src/main.v):

1. active timing: 1080p parameters enabled (720p block commented out)
2. PLL profile: `PLL_PROFILE = 2'd3`
3. TMDS control alignment: `TMDS_ALIGN_LATENCY = 2`
4. data path includes async FIFO CDC and RGB888 -> RGB565 -> RGB888 conversion path for experiments
5. TMDS encoder includes internal pipelining (`de_q/data_q/ctrl_q` and `de_qq/q_m_q/dc_ones_cnt_q`) for timing closure experiments

## Architecture

End-to-end path (logical):

1. `clk` (27 MHz) -> HDMI PLL and CLKDIV clocks
2. video timing generation in HDMI pixel domain (`clk_hdmi`)
3. pattern source generation in system domain (`clk_sys`)
4. asynchronous FIFO CDC (`clk_sys` write, `clk_hdmi` read)
5. TMDS encode (R/G/B)
6. 10:1 serialize
7. differential output buffers to HDMI pins

### Clock Tree

1. input clock: 27.000 MHz (`clk`)
2. HDMI PLL output: `clk_hdmi_5x`
3. pixel clock: `clk_hdmi` from `Gowin_CLKDIV` divide-by-5
4. system clocks from `rPLL_SYS`: `clk_sys`, `clk_sys_90`, `clk_cpu`

Related files:

1. [src/gowin_rpll/rpll_hdmi.v](src/gowin_rpll/rpll_hdmi.v)
2. [src/gowin_clkdiv/clkdiv_hdmi.v](src/gowin_clkdiv/clkdiv_hdmi.v)
3. [src/gowin_rpll/rpll_sys.v](src/gowin_rpll/rpll_sys.v)

### PLL_PROFILE Mapping

Defined by `get_hdmi_freq` in [src/main.v](src/main.v):

1. `0`: pixel 74.25 MHz, 5x 371.25 MHz
2. `1`: pixel 99.00 MHz, 5x 495.00 MHz
3. `2`: pixel 123.75 MHz, 5x 618.75 MHz
4. `3`: pixel 148.50 MHz, 5x 742.50 MHz

## RTL Modules

Core modules:

1. [src/main.v](src/main.v): top-level integration
2. [src/vid_timing_gen.v](src/vid_timing_gen.v): timing (`hsync`, `vsync`, `de`, `x`, `y`)
3. [src/pattern_gen.v](src/pattern_gen.v): RGB pattern source
4. [src/async_fifo.v](src/async_fifo.v): asynchronous FIFO CDC path (current experimental bridge)
5. [src/dither_rgb888_to_565.v](src/dither_rgb888_to_565.v): RGB888 -> RGB565 conversion
6. [src/tmds_encoder.v](src/tmds_encoder.v): TMDS channel encoder
7. [src/serlizer_10to1.v](src/serlizer_10to1.v): OSER10 wrapper

Legacy/support modules (may be reused depending on branch/experiment):

1. [src/vid_line_buf.v](src/vid_line_buf.v)
2. [src/sdp_bram.v](src/sdp_bram.v)

## Top-Level I/O

Declared in [src/main.v](src/main.v):

Inputs:

1. `clk` (27 MHz)
2. `rst_n` (active-low)

Debug:

1. `led`

HDMI differential outputs:

1. `tmds_clk_p`, `tmds_clk_n`
2. `tmds_data0_p`, `tmds_data0_n` (Blue)
3. `tmds_data1_p`, `tmds_data1_n` (Green)
4. `tmds_data2_p`, `tmds_data2_n` (Red)

## Constraints

1. pin constraints: [src/hdmi_base.cst](src/hdmi_base.cst)
2. timing constraints: [src/hdmi_base.sdc](src/hdmi_base.sdc)

If you change `PLL_PROFILE`, re-check [src/hdmi_base.sdc](src/hdmi_base.sdc) clock periods to match the active profile.

## Build Flow (Gowin EDA)

1. Open [hdmi_base.gprj](hdmi_base.gprj).
2. Confirm file list includes all `src` files used by your current branch.
3. Confirm top module is `main`.
4. Run Synthesis.
5. Run Place and Route.
6. Generate bitstream and program board.

Outputs are under [impl](impl).

## Simulation

Testbenches are in [tb](tb):

1. [tb/main_smoke_tb.v](tb/main_smoke_tb.v)
2. [tb/main_hdmi_tb.v](tb/main_hdmi_tb.v)
3. [tb/vid_timing_gen_tb.v](tb/vid_timing_gen_tb.v)
4. [tb/pattern_gen_tb.v](tb/pattern_gen_tb.v)
5. [tb/tmds_encoder_tb.v](tb/tmds_encoder_tb.v)
6. [tb/tmds_encoder_golden_tb.v](tb/tmds_encoder_golden_tb.v)

Vendor primitive stubs for simulation:

1. [tb/gowin_stub.v](tb/gowin_stub.v)

Example Icarus compile command (Windows path style):

```powershell
Set-Location d:\Development\FPGA\hdmi_base
C:\iverilog\bin\iverilog.exe -g2012 -o tb\main_check.out `
  tb\gowin_stub.v `
  src\gowin_rpll\rpll_hdmi.v src\gowin_clkdiv\clkdiv_hdmi.v src\gowin_rpll\rpll_sys.v `
  src\vid_timing_gen.v src\pattern_gen.v src\tmds_encoder.v src\serlizer_10to1.v `
  src\async_fifo.v src\dither_rgb888_to_565.v src\main.v tb\main_smoke_tb.v
```

## CDC and Image Artifacts Notes

When testing cross-domain video data, typical symptoms are:

1. stable vertical solid lines
2. moving dashed/noisy vertical lines

Usually caused by one of these:

1. data/control not aligned after CDC
2. reading FIFO while empty or writing while full
3. write/read throughput mismatch over time
4. reset release order mismatch across domains

Recommended checks:

1. verify FIFO `full` and `empty` handling in [src/main.v](src/main.v)
2. verify TMDS `de` alignment depth (`TMDS_ALIGN_LATENCY`)
3. scope `de`, FIFO read enable, and output pixel validity in simulation

## Timing Closure Notes (April 2026)

Observed top failing paths during 1080p60 timing closure were primarily inside TMDS encode logic:

1. `hdmi_line_buf_fifo/fifo_ram/.../DO -> tmds_encoder_*/disparity_*`
2. then after front-end pipelining, `tmds_encoder_*/data_q_* -> disparity_*`
3. later-stage residuals around `dc_ones_cnt_q/disparity -> disparity`

Key takeaway:

1. Async FIFO solves CDC safety, but does not by itself fix long single-cycle same-domain paths in `clk_hdmi`.

Current code-side mitigations already present in [src/tmds_encoder.v](src/tmds_encoder.v):

1. stage-0 input register cut (`de_q`, `data_q`, `ctrl_q`)
2. stage-1 register cut (`de_qq`, `ctrl_qq`, `q_m_q`, `dc_ones_cnt_q`)
3. simplified running-disparity delta update to reduce combinational depth

Remaining practical closure knobs (without architectural rewrite):

1. add one more local register cut around disparity decision/update in [src/tmds_encoder.v](src/tmds_encoder.v)
2. keep timing constraints in [src/hdmi_base.sdc](src/hdmi_base.sdc) strictly aligned with active `PLL_PROFILE`
3. reduce non-essential logic fanout on TMDS critical nets

Known non-blocking simulation warnings in current [src/main.v](src/main.v):

1. RGB565 width mismatch around dither/fifo wiring (`24 -> 16` truncation/padding warnings)

## Planned Integration Direction

The intended long-term direction is external framebuffer input.

For pSRAM/DDR3 integration, keep [src/main.v](src/main.v) structure as:

1. memory controller in `clk_sys` domain produces pixel stream
2. CDC bridge transfers data into `clk_hdmi` domain
3. TMDS path remains isolated in `clk_hdmi` domain

This keeps timing closure and functional debugging manageable while migrating from pattern source to real memory-backed video.
