# light-on

A small Gowin FPGA demo that drives 6 LEDs with a 1-second counter and PWM brightness control.

## Overview

The top-level module counts seconds from `0` to `59`, maps the current second value to a 6-bit LED pattern, and applies PWM dimming so the LEDs are not driven at full duty cycle.

Current design flow and sources target a Gowin device:

- Device: `GW2AR-18C`
- Part number: `GW2AR-LV18QN88C8/I7`
- Project file: [light-on.gprj](light-on.gprj)
- Constraint file: [src/light-on.cst](src/light-on.cst)

## Module Structure

- [src/led.v](src/led.v): Top-level module. Instantiates the second counter and PWM generator, then drives the 6 LED outputs.
- [src/sec_cnt.v](src/sec_cnt.v): Generates a 1-second tick from the input clock and counts seconds from `0` to `59`.
- [src/pwm_gen.v](src/pwm_gen.v): 8-bit PWM generator used for LED brightness control.

## Behavior

- Input clock is expected on `clk`.
- The counter increments once per second.
- `bin_sec[5:0]` is used directly as the LED on/off pattern.
- PWM duty is set by the `BRIGHTNESS` parameter in [src/led.v](src/led.v).
- LED outputs are active low: `assign led = ~led_r;`

## Top-Level Parameters

The top-level module in [src/led.v](src/led.v) exposes these parameters:

- `CLOCK_FREQUENCY = 27_000_000`
- `A_MINUTE_SEC = 6'd60`
- `BRIGHTNESS = 8'h01`

You can change these values to adapt the design to a different board clock or LED brightness.

## Pin Constraints

The current constraint file [src/light-on.cst](src/light-on.cst) defines:

- `clk` on pin `4`
- `led[0]` to `led[5]` on pins `20` to `15`

If your board uses different pins, update [src/light-on.cst](src/light-on.cst) before implementation.

## Build And Program

This project is intended for Gowin EDA.

1. Open [light-on.gprj](light-on.gprj) in Gowin EDA.
2. Check that all source files are present in the project file list.
3. Run synthesis and place-and-route.
4. Program the generated bitstream from the `impl/pnr/` output.

Generated implementation artifacts are already present under [impl](impl), but they can be regenerated from source.

## Repository Layout

```text
.
├─ light-on.gprj
├─ src/
│  ├─ led.v
│  ├─ pwm_gen.v
│  ├─ sec_cnt.v
│  ├─ light-on.cst
│  └─ light-on.rao
└─ impl/
```

## Notes

- [src/light-on.rao](src/light-on.rao) is a Gowin analyzer/debug configuration file.
- The repository currently includes generated implementation outputs in [impl](impl).
- If you plan to publish a cleaner source-only repository, you may want to exclude regenerated build artifacts later.