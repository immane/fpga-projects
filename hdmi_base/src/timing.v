module timing #(
    parameter [1:0] PLL_PROFILE = 2'd3 // 0:30Hz, 1:40Hz, 2:50Hz, 3:60Hz
) (
    input wire clk,
    input wire rst_n,
    input wire hdmi_rst_n,
    
    output wire clk_sys,
    output wire clk_sys_90,
    output wire clk_cpu,
    output wire clk_hdmi,
    output wire clk_hdmi_5x,
    output wire lock,
    output wire lock_sys
);
    // Timing parameters
    function integer get_hdmi_freq;
        input [1:0] p;
        begin
            case (p)
                2'd0: get_hdmi_freq = 74_250_000;   // 1080p30 / 720p60 pixel clock
                2'd1: get_hdmi_freq = 99_000_000;   // 1080p40 pixel clock
                2'd2: get_hdmi_freq = 123_750_000;  // 1080p50 pixel clock
                2'd3: get_hdmi_freq = 148_500_000;  // 1080p60 / 2k30 pixel clock
                default: get_hdmi_freq = 74_250_000;
            endcase
        end
    endfunction

    localparam CLOCK_FREQUENCY = 27_000_000; // 27 MHz input
    localparam HDMI_FREQ = get_hdmi_freq(PLL_PROFILE);
    localparam HDMI_FREQ_5X = HDMI_FREQ * 5;

    rPLL_SYS rpll_sys(
        .clkin(clk),
        .clkout(clk_sys),
        .clkoutp(clk_sys_90),
        .clkoutd(clk_cpu),
        .lock(lock_sys)
    );

    // Generate HDMI clock (e.g. 148.5MHz for 1080p60) from the input 27MHz using rPLL_HDMI
    rPLL_HDMI #(
        .PROFILE(PLL_PROFILE)
    ) pll_hdmi(
        .clkin(clk),
        .clkout(clk_hdmi_5x),
        .lock(lock)
    );
    Gowin_CLKDIV clkdiv_hdmi(
        .clkout(clk_hdmi), //output clkout
        .hclkin(clk_hdmi_5x), //input hclkin
        .resetn(hdmi_rst_n) //input resetn
    );  
endmodule