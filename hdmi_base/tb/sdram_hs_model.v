// Behavioral model of the Gowin SDRAM Controller HS IP user interface
// for protocol verification of sdram_user_ctrl (IPUG756 semantics).
//   cmd = {RAS#,CAS#,WE#}: ACTIVE=011, WRITE=100, READ=101,
//                          PRECHARGE=010, REFRESH=001, NOP=111
//   data_len is 0-based -> burst length = data_len + 1
//   WRITE : word0 sampled with cmd_en, words 1..len on following cycles,
//           cmd_ack after len+1 + WR cycles
//   READ  : data driven on o_data for len+1 cycles, cmd_ack aligned with
//           the LAST read word
//   ACTIVE/PRECHARGE/REFRESH : cmd_ack after RCD/RP cycles
`timescale 1ns/1ps
module sdram_hs_model #(
    parameter CL = 2,
    parameter WR = 2,
    parameter RP = 2,
    parameter RCD = 2
) (
    input             clk,
    input             rst_n,
    input             cmd_en,
    input      [2:0]  cmd,
    input      [20:0] addr,
    input      [31:0] data,
    input      [7:0]  data_len,
    output reg [31:0] o_data,
    output reg        cmd_ack,
    output reg        init_done,
    output reg        protocol_error
);
    localparam CMD_ACTIVE    = 3'b011;
    localparam CMD_WRITE     = 3'b100;
    localparam CMD_READ      = 3'b101;
    localparam CMD_PRECHARGE = 3'b010;
    localparam CMD_REFRESH   = 3'b001;
    localparam CMD_NOP       = 3'b111;

    reg [31:0] mem [0:2097151];

    reg [2:0]  op;
    reg [20:0] op_addr;
    reg [7:0]  op_len;
    reg        busy;
    reg [8:0]  cnt;
    reg [8:0]  col_i;

    wire [20:0] base = op_addr;
    reg [3:0] bank_open;
    reg [10:0] open_row [0:3];
    reg [7:0] init_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_done <= 1'b0;
            cmd_ack   <= 1'b0;
            o_data    <= 32'd0;
            busy      <= 1'b0;
            cnt       <= 9'd0;
            col_i     <= 9'd0;
            op        <= CMD_NOP;
            op_addr   <= 21'd0;
            op_len    <= 8'd0;
            bank_open <= 4'b0000;
            init_cnt  <= 8'd0;
            protocol_error <= 1'b0;
        end else begin
            cmd_ack <= 1'b0;

            if (!init_done) begin
                if (init_cnt == 8'd20)
                    init_done <= 1'b1;
                else
                    init_cnt <= init_cnt + 1'b1;
            end

            if (cmd_en && !busy) begin
                op      <= cmd;
                op_addr <= addr;
                op_len  <= data_len;
                busy    <= 1'b1;
                cnt     <= 9'd1;
                col_i   <= 9'd0;
                if (cmd == CMD_WRITE) begin
                    if (!bank_open[addr[20:19]] || open_row[addr[20:19]] != addr[18:8])
                        protocol_error <= 1'b1;
                    // word 0 sampled together with the write command.
                    // NOTE: use the addr port directly (op_addr is not yet
                    // updated by the non-blocking assignment in this edge).
                    mem[addr] <= data;
                end else if (cmd == CMD_READ) begin
                    if (!bank_open[addr[20:19]] || open_row[addr[20:19]] != addr[18:8])
                        protocol_error <= 1'b1;
                end else if (cmd == CMD_ACTIVE) begin
                    if (bank_open[addr[20:19]])
                        protocol_error <= 1'b1;
                    bank_open[addr[20:19]] <= 1'b1;
                    open_row[addr[20:19]] <= addr[18:8];
                end else if (cmd == CMD_PRECHARGE) begin
                    bank_open[addr[20:19]] <= 1'b0;
                end else if (cmd == CMD_REFRESH) begin
                    if (bank_open != 4'b0000)
                        protocol_error <= 1'b1;
                end
            end else if (busy) begin
                case (op)
                    CMD_WRITE: begin
                        // stream words 1..len; then wait WR, then ack
                        if (cnt <= op_len)
                            mem[base + cnt] <= data;
                        if (cnt == op_len + WR + 9'd1) begin
                            busy    <= 1'b0;
                            cmd_ack <= 1'b1;
                        end
                        cnt <= cnt + 9'd1;
                    end
                    CMD_READ: begin
                        // deterministic: data driven on cycles cnt=RCD..RCD+len,
                        // cmd_ack set on the LAST data-word cycle (RCD+len).
                        if (cnt >= RCD && cnt < RCD + op_len + 9'd1) begin
                            o_data <= mem[base + col_i];
                            col_i  <= col_i + 9'd1;
                        end
                        if (cnt == RCD + op_len) begin
                            busy    <= 1'b0;
                            cmd_ack <= 1'b1;
                        end
                        cnt <= cnt + 9'd1;
                    end
                    CMD_ACTIVE: begin
                        if (cnt >= RCD) begin
                            busy    <= 1'b0;
                            cmd_ack <= 1'b1;
                        end
                        cnt <= cnt + 9'd1;
                    end
                    CMD_PRECHARGE, CMD_REFRESH: begin
                        if (cnt >= RP) begin
                            busy    <= 1'b0;
                            cmd_ack <= 1'b1;
                        end
                        cnt <= cnt + 9'd1;
                    end
                    default: begin
                        busy    <= 1'b0;
                        cmd_ack <= 1'b1;
                    end
                endcase
            end
        end
    end
endmodule
