# hdmi_base

A small Gowin FPGA base project for bringing up an HDMI-style clock tree from a 27 MHz board clock.

## Overview

This project currently focuses on clock generation and basic bring-up logic rather than full HDMI video output.

The top-level design:

- takes a 27 MHz input clock
- uses a Gowin rPLL to generate a 371.25 MHz high-speed clock
- divides that clock by 5 to generate a 74.25 MHz pixel-rate clock
- uses the derived clock to drive a simple counter
- toggles a user LED as a visible sign that the generated clock domain is running

At this stage, the project does not yet expose TMDS data lanes, HDMI timing generation, or video pattern output.

## Clock Tree

The current clock plan is:

- Input clock: `27.000 MHz`
- PLL output: `371.250 MHz`
- CLKDIV output: `74.250 MHz`

This matches a common HDMI pixel clock family, where `74.25 MHz` is a standard video timing reference and the `5x` clock is typically used for high-speed serialization.

## Top-Level Interface

The top-level module is [src/main.v](src/main.v) and currently exposes:

- `clk`: 27 MHz board clock input
- `rst_n`: active-low reset input
- `led`: status LED output

## Project Structure

- [src/main.v](src/main.v): Top-level design. Instantiates the PLL and clock divider, then toggles an LED in the generated clock domain.
- [src/gowin_rpll/pll_hdmi.v](src/gowin_rpll/pll_hdmi.v): Gowin-generated PLL IP wrapper.
- [src/gowin_clkdiv/clkdiv_hdmi.v](src/gowin_clkdiv/clkdiv_hdmi.v): Gowin-generated clock divider IP wrapper.
- [src/hdmi_base.cst](src/hdmi_base.cst): Pin and IO constraint file.
- [src/hdmi_base.sdc](src/hdmi_base.sdc): Timing constraint file for the input clock, generated clocks, and reset exception.

## Constraints

The current physical constraints define:

- `clk` on pin `4`
- `led` on pin `15`
- IO settings for `rst_n`

The current timing constraints define:

- a `27 MHz` primary clock on `clk`
- a generated `371.25 MHz` PLL clock
- a generated `74.25 MHz` divided clock
- a false path from the asynchronous reset input `rst_n`

## Build Flow

This project is intended for Gowin EDA.

1. Open [hdmi_base.gprj](hdmi_base.gprj) in Gowin EDA.
2. Confirm the source list includes the top-level RTL, PLL IP, clock divider IP, CST, and SDC files.
3. Run synthesis.
4. Run place-and-route.
5. Program the generated bitstream to the target board.

Generated implementation outputs are stored under [impl](impl).

## Current Behavior

After reset is released, the logic counts in the `74.25 MHz` clock domain and toggles the LED periodically. This gives a simple hardware-level sanity check that:

- the input clock is present
- the PLL is operating
- the divided HDMI-rate clock is active
- logic in the generated clock domain is running

## Notes

- The top-level logic already instantiates the clocking blocks needed for a future HDMI pipeline.
- The design currently uses the generated clock only for a counter and LED toggle.
- If you extend this project toward real HDMI output, the next steps are usually sync timing generation, pixel generation, and TMDS encoding/serialization.