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
    input   wire                rst_n,  // _n means active low

    // output
    output  reg                 dst_valid_o,
    input   wire                dst_ready_i,
    output  reg     [DATA_SIZE-1:0] dst_data_o,

    // input
    input   wire                data_reader_valid_i,
    output  reg                 data_reader_ready_o,
    input   wire    [DATA_SIZE-1:0]     data_reader_data_i,

    input   wire                descriptor_valid_i,
    output  reg                 descriptor_ready_o,
    input   wire    [DATA_SIZE-1:0]     descriptor_data_i
);

    // Optimized channel selection - single bit register
    reg     channel_select;  // 0: descriptor, 1: data_reader
    
    // Optimized transaction completion detection
    wire    handshake_complete = dst_valid_o & dst_ready_i;
    
    // Priority logic for channel switching
    wire    switch_to_data_reader = ~channel_select & data_reader_valid_i;
    wire    switch_to_descriptor  = channel_select & descriptor_valid_i;
    
    // Optimized channel arbitration logic
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            channel_select <= 1'b0;  // Start with descriptor channel
        end
        else if(handshake_complete | ~dst_valid_o) begin
            // Round-robin with priority to data_reader when both are valid
            if(data_reader_valid_i & descriptor_valid_i) begin
                channel_select <= ~channel_select;  // Toggle for fairness
            end
            else if(switch_to_data_reader) begin
                channel_select <= 1'b1;
            end
            else if(switch_to_descriptor) begin
                channel_select <= 1'b0;
            end
        end
    end

    // Optimized output multiplexing - reduced logic depth
    always_comb begin
        if(channel_select) begin
            // Data reader selected
            dst_valid_o         = data_reader_valid_i;
            dst_data_o          = data_reader_data_i;
            data_reader_ready_o = dst_ready_i;
            descriptor_ready_o  = 1'b0;
        end else begin
            // Descriptor selected
            dst_valid_o         = descriptor_valid_i;
            dst_data_o          = descriptor_data_i;
            data_reader_ready_o = 1'b0;
            descriptor_ready_o  = dst_ready_i;
        end
    end

endmodule
