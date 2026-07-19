`timescale 1ns/1ps

module sdram_user_ctrl_tb;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg init_done = 1'b0;
reg cmd_ack = 1'b0;
reg pix_valid = 1'b0;
reg [15:0] pix_data = 16'd0;
reg out_ready = 1'b1;
reg [31:0] read_data = 32'd0;

wire pix_ready;
wire out_valid;
wire [15:0] out_data;
wire [2:0] user_cmd;
wire user_cmd_en;
wire [20:0] user_addr;
wire [31:0] user_data;
wire [7:0] user_len;

reg [31:0] memory [0:7];
integer input_count = 0;
integer output_count = 0;
integer write_count = 0;
integer activate_count = 0;
integer read_count = 0;
integer timeout_count = 0;
reg write_active = 1'b0;

always #5 clk = ~clk;

sdram_user_ctrl uut (
    .clk(clk),
    .rst_n(rst_n),
    .init_done(init_done),
    .cmd_ack(cmd_ack),
    .pix_valid(pix_valid),
    .pix_data(pix_data),
    .pix_ready(pix_ready),
    .out_valid(out_valid),
    .out_data(out_data),
    .out_ready(out_ready),
    .user_cmd(user_cmd),
    .user_cmd_en(user_cmd_en),
    .user_addr(user_addr),
    .user_data(user_data),
    .user_len(user_len),
    .read_data(read_data)
);

always @(posedge clk) begin
    cmd_ack <= 1'b0;

    if (user_cmd_en && user_cmd == 3'b011) begin
        activate_count <= activate_count + 1;
        cmd_ack <= 1'b1;
    end

    if (user_cmd_en && user_cmd == 3'b100) begin
        memory[0] <= user_data;
        write_count <= 1;
        write_active <= 1'b1;
    end else if (write_active) begin
        memory[write_count] <= user_data;
        if (write_count == 7) begin
            write_active <= 1'b0;
            write_count <= 8;
        end else begin
            write_count <= write_count + 1;
        end
    end

    if (user_cmd_en && user_cmd == 3'b101)
        read_count <= read_count + 1;

    if (pix_valid && pix_ready) begin
        input_count <= input_count + 1;
        pix_data <= pix_data + 1'b1;
        if (input_count == 15)
            pix_valid <= 1'b0;
    end

    if (out_valid && out_ready) begin
        if (out_data !== output_count[15:0]) begin
            $display("FAIL: output %0d was %h", output_count, out_data);
            $finish;
        end
        output_count <= output_count + 1;
    end

    timeout_count <= timeout_count + 1;
    if (output_count == 16) begin
        if (activate_count != 2 || read_count != 1 || write_count != 8 || user_len != 7) begin
            $display("FAIL: activate=%0d read=%0d write=%0d len=%0d",
                     activate_count, read_count, write_count, user_len);
            $finish;
        end
        $display("PASS: SDRAM command sequence and 16-pixel round trip verified.");
        $finish;
    end

    if (timeout_count == 500) begin
        $display("FAIL: timeout, output_count=%0d state=%0d", output_count, uut.state);
        $finish;
    end
end

// Model the controller's burst read data at the sampling edge.
always @(negedge clk) begin
    if (uut.state == 4'd10)
        read_data <= memory[uut.read_count];
end

initial begin
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    init_done <= 1'b1;
    pix_valid <= 1'b1;
end

endmodule
