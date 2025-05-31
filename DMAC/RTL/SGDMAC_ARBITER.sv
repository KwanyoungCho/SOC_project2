// Copyright (c) 2021 Sungkyunkwan University
//
// Authors:
// - Jungrae Kim <dale40@skku.edu>

module SGDMAC_ARBITER
#(
    DATA_SIZE                   = 32
)
(
    input   wire                clk,
    input   wire                rst_n,

    // output
    output  reg                 dst_valid_o,
    input   wire                dst_ready_i,
    output  reg     [DATA_SIZE-1:0] dst_data_o,

    // input
    input   wire                rm_vlid_i,
    output  reg                 rm_ready_o,
    input   wire    [DATA_SIZE-1:0]     rm_data_i,

    input   wire                dt_valid_i,
    output  reg                 dt_ready_o,
    input   wire    [DATA_SIZE-1:0]     dt_data_i
);

    reg     ch_select;
    
    wire    handshake_complete = dst_valid_o & dst_ready_i;    
    wire    switch_to_rm = ~ch_select & rm_vlid_i;
    wire    switch_to_dt  = ch_select & dt_valid_i;
    
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            ch_select <= 1'b0;
        end
        else if(handshake_complete | ~dst_valid_o) begin
            if(rm_vlid_i & dt_valid_i) begin
                ch_select <= ~ch_select;
            end
            else if(switch_to_rm) begin
                ch_select <= 1'b1;
            end
            else if(switch_to_dt) begin
                ch_select <= 1'b0;
            end
        end
    end

    always_comb begin
        if(ch_select) begin
            dst_valid_o         = rm_vlid_i;
            dst_data_o          = rm_data_i;
            rm_ready_o = dst_ready_i;
            dt_ready_o  = 1'b0;
        end else begin
            dst_valid_o         = dt_valid_i;
            dst_data_o          = dt_data_i;
            rm_ready_o = 1'b0;
            dt_ready_o  = dst_ready_i;
        end
    end

endmodule
