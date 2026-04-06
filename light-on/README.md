# light-on

A small Gowin FPGA demo that drives 6 LEDs with a 1-second counter and PWM brightness control, with a debounced key input used to change brightness.

## Overview

The top-level design counts seconds from `0` to `59`, uses the 6-bit second value as the LED pattern, and gates that pattern with a PWM signal to control apparent brightness. A debounced push-button input is sampled by a small key controller that changes the PWM brightness state.

Current design flow and sources target a Gowin device:

- Device: `GW2AR-18C`
- Part number: `GW2AR-LV18QN88C8/I7`
- Project file: [light-on.gprj](light-on.gprj)
- Constraint file: [src/light-on.cst](src/light-on.cst)

## Module Structure

- [src/led.v](src/led.v): Top-level module. Instantiates the key controller, second counter, and PWM generator, then drives the 6 LED outputs.
- [src/key_ctrl.v](src/key_ctrl.v): Tracks debounced button presses and advances a 2-bit key state.
- [src/debouncer.v](src/debouncer.v): Filters the mechanical key input and outputs a stable key level.
- [src/sec_cnt.v](src/sec_cnt.v): Generates a 1-second tick from the input clock and counts seconds from `0` to `59`.
- [src/pwm_gen.v](src/pwm_gen.v): 8-bit PWM generator used for LED brightness control.

## Top-Level Interface

The top-level module in [src/led.v](src/led.v) uses these ports:

- `clk`: system clock input
- `rst_n`: active-low reset input
- `key_i`: push-button input for brightness control
- `led[5:0]`: active-low LED outputs

## Behavior

- The counter increments once per second.
- `bin_sec[5:0]` is used directly as the LED on/off pattern.
- The LED pattern is ANDed with the PWM output, so brightness is controlled by duty cycle rather than by changing the pattern itself.
- `key_ctrl` increments a 2-bit state on each debounced key press.
- The current code maps `key_state` to PWM duty in [src/led.v](src/led.v); this is a simple demonstration mapping, not a calibrated brightness table.
- LED outputs are active low: `assign led = ~led_r;`

## Top-Level Parameters

The top-level module in [src/led.v](src/led.v) exposes these parameters:

- `CLOCK_FREQUENCY = 27_000_000`
- `A_MINUTE_SEC = 6'd60`
- `BRIGHTNESS = 8'h01`

The debouncer in [src/debouncer.v](src/debouncer.v) also exposes:

- `CLOCK_FREQUENCY = 27_000_000`
- `STABLE_TIMES = 20`

You can change these values to adapt the design to a different board clock, debounce interval, or default brightness.

## Pin Constraints

The current constraint file [src/light-on.cst](src/light-on.cst) defines:

- `clk` on pin `4`
- `key_i` on pin `88`
- `led[0]` to `led[5]` on pins `20` to `15`
- Electrical settings for `rst_n`, but no explicit `IO_LOC` assignment for `rst_n`

If your board uses different pins, update [src/light-on.cst](src/light-on.cst) before implementation.

## Build And Program

This project is intended for Gowin EDA.

1. Open [light-on.gprj](light-on.gprj) in Gowin EDA.
2. Confirm the Verilog source list includes [src/led.v](src/led.v), [src/key_ctrl.v](src/key_ctrl.v), [src/debouncer.v](src/debouncer.v), [src/pwm_gen.v](src/pwm_gen.v), and [src/sec_cnt.v](src/sec_cnt.v).
3. Run synthesis and place-and-route.
4. Program the generated bitstream from the [impl/pnr](impl/pnr) output.

Generated implementation artifacts are already present under [impl](impl), but they can be regenerated from source.

## Repository Layout

```text
.
├─ light-on.gprj
├─ src/
│  ├─ debouncer.v
│  ├─ key_ctrl.v
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