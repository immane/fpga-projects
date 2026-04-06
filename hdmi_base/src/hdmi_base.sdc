# Base input clock: 27 MHz on top-level port clk.
create_clock -name clk_27m -period 37.037 [get_ports {clk}]

# PLL output clock: 27 MHz * 55 / 4 = 371.25 MHz.
create_generated_clock -name clk_hdmi_5x \
	-source [get_ports {clk}] \
	-multiply_by 55 \
	-divide_by 4 \
	[get_pins {pll_hdmi/clkout}]

# CLKDIV output clock: 371.25 MHz / 5 = 74.25 MHz.
create_generated_clock -name clk_hdmi \
	-source [get_pins {pll_hdmi/clkout}] \
	-divide_by 5 \
	[get_pins {clkdiv_hdmi/clkout}]

# rst_n is an asynchronous reset and should not be timing-closed as data.
set_false_path -from [get_ports {rst_n}]
