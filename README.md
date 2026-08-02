# FPGA

Collection of Verilog projects targeting Gowin FPGA devices, primarily the Tang Nano 20K (GW2AR-18C).

## Projects

| Project | Description |
|---------|-------------|
| [hdmi_base](hdmi_base/README.md) | HDMI base design (1080p60 TMDS output pipeline) with video timing, clock-domain-crossing FIFO, and TMDS encoder/serializer. |
| [light-on](light-on/README.md) | Small LED demo: 6 LEDs driven by a 1-second counter with PWM brightness control and debounced key input. |

## Repository Layout

```text
.
├─ hdmi_base/   # HDMI output design (Tang Nano 20K)
│  ├─ src/      # RTL sources + Gowin IP wrappers (PLL, CLKDIV)
│  ├─ tb/       # Icarus Verilog testbenches + Gowin primitive stubs
│  └─ impl/     # Gowin EDA synthesis / PnR outputs
├─ light-on/    # LED demo design
│  ├─ src/      # RTL sources + pin constraints
│  ├─ tb/       # Testbenches
│  └─ impl/     # Gowin EDA synthesis / PnR outputs
└─ README.md
```

## Toolchain

- **Synthesis / Place & Route / Programming:** [Gowin EDA](https://www.gowinsemi.com/) — open the `.gprj` file of the project, run synthesis, then place-and-route, and generate the bitstream.
- **Simulation:** Icarus Verilog (`iverilog` / `vvp`) with GTKWave for waveform viewing.

Example Icarus compile + run via Docker (Linux style):

```bash
cd /path/to/hdmi_base
docker run --rm -v "$PWD":/work -w /work hdlc/iverilog:latest \
  iverilog -g2012 -o tb/main_check.out \
  tb/gowin_stub.v \
  src/gowin_rpll/pll_hdmi.v src/gowin_clkdiv/clkdiv_hdmi.v src/gowin_rpll/rpll_sys.v \
  src/vid_timing_gen.v src/pattern_gen.v src/tmds_encoder.v src/serlizer_10to1.v \
  src/async_fifo.v src/dither_rgb888_to_565.v src/main.v tb/main_smoke_tb.v
docker run --rm -v "$PWD":/work -w /work hdlc/iverilog:latest vvp tb/main_check.out
```

> Note: vendor-specific primitives (e.g. Gowin PLL/CLKDIV) are replaced by behavioral stubs in `tb/gowin_stub.v` when simulating with Icarus Verilog.

## Board Targets

Both designs target the **Tang Nano 20K** (GW2AR-18C, part `GW2AR-LV18QN88C8/I7`) and use a 27 MHz system clock.

## Notes

- Gowin project files: `hdmi_base/hdmi_base.gprj`, `light-on/light-on.gprj`.
- Pin constraints live in each project's `src/*.cst`; timing constraints in `hdmi_base/src/hdmi_base.sdc`.
- Each sub-project has its own detailed README — see the links above for design status, module structure, and build/simulation instructions.
