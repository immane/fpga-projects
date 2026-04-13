# Base input clock: 27 MHz on top-level port clk.
create_clock -name clk_27m -period 37.037 [get_ports {clk}]

# PLL 5x clock at CLKDIV primitive input.
# Constrain to worst-case (148.5MHz pixel * 5 = 742.5MHz, period ~= 1.3468ns)
# so the same SDC is safe for 30/40/50/60 profiles.
create_clock -name clk_hdmi_5x -period 1.347 [get_pins {clkdiv_hdmi/clkdiv_inst/HCLKIN}]

# Pixel clock at CLKDIV primitive output.
create_generated_clock -name clk_hdmi -source [get_pins {clkdiv_hdmi/clkdiv_inst/HCLKIN}] -divide_by 5 [get_pins {clkdiv_hdmi/clkdiv_inst/CLKOUT}]

# rst_n is an asynchronous reset and should not be timing-closed as data.
set_false_path -from [get_ports {rst_key_n}]