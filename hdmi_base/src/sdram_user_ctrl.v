module sdram_user_ctrl (
    input             clk,
    input             rst_n,
    input             init_done,
    input             cmd_ack,
    
    // Connected to the IP core
    output reg [2:0]  user_cmd,
    output reg        user_cmd_en,
    output reg [20:0] user_addr,
    output reg [31:0] user_data,   // Write data bus
    output     [7:0]  user_len,    // Burst length
    input             data_valid,  // Important: corresponds to IP's O_sdrc_data_valid
    input      [31:0] read_data    // Corresponds to IP's O_sdrc_data
);

    localparam BURST_SIZE = 8'd8; // Burst length set to 8
    assign user_len = BURST_SIZE;

    localparam IDLE      = 3'd0;
    localparam W_REQ     = 3'd1;
    localparam W_DATA    = 3'd2;
    localparam R_REQ     = 3'd3;
    localparam R_DATA    = 3'd4;
    localparam DONE      = 3'd5;

    reg [2:0] state;
    reg [7:0] cnt; // Counter, tracks how many data words processed

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            user_cmd_en <= 1'b0;
            cnt <= 8'd0;
        end else begin
            case (state)
                IDLE: if (init_done) state <= W_REQ;

                // --- Burst write ---
                W_REQ: begin
                    user_cmd    <= 3'b001;      // Write command
                    user_addr   <= 21'h000000;  // Start address
                    user_cmd_en <= 1'b1;        // Issue request
                    if (cmd_ack) begin          // IP accepted the request
                        user_cmd_en <= 1'b0;    // Withdraw request
                        cnt         <= 8'd1;    // Prepare to send the 1st data word
                        user_data   <= 32'd100; // 1st test data
                        state       <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (cnt < BURST_SIZE) begin
                        cnt       <= cnt + 1'b1;
                        user_data <= user_data + 1'b1; // Provide incrementing data
                    end else begin
                        state <= R_REQ; // After 8 writes, switch to read
                    end
                end

                // --- Burst read ---
                R_REQ: begin
                    user_cmd    <= 3'b010;      // Read command
                    user_addr   <= 21'h000000;  // Read from the address we just wrote
                    user_cmd_en <= 1'b1;
                    if (cmd_ack) begin
                        user_cmd_en <= 1'b0;
                        cnt         <= 8'd0;
                        state       <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (data_valid) begin       // Count only when data_valid is asserted
                        // Here you could store read_data into your FIFO or buffer
                        if (cnt < BURST_SIZE - 1) 
                            cnt <= cnt + 1'b1;
                        else
                            state <= DONE;      // Finished reading 8 data words
                    end
                end

                DONE: state <= DONE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule