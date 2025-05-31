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

    // Channel selection state registers
    reg                     active_channel, next_active_channel; 
    // Channel encoding: 1=data_reader, 0=descriptor_fetcher
    
    // Transaction completion detection
    wire                    transaction_complete;
    assign transaction_complete = dst_valid_o && dst_ready_i;

    // Sequential logic for channel state update
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            active_channel <= 1'd0;
        end
        else begin
            active_channel <= next_active_channel;
        end
    end

    // Combinational logic for next channel selection
    always_comb begin 
        next_active_channel = active_channel;
        
        // Switch channel when transaction completes or output is idle
        if(transaction_complete || (~dst_valid_o)) begin
            case(active_channel)
            1'b0: next_active_channel = (data_reader_valid_i) ? 1'b1 : 1'b0;
            1'b1: next_active_channel = (descriptor_valid_i) ? 1'b0 : 1'b1;
            endcase
        end
    end

    // Output interface assignments with channel multiplexing
    assign  data_reader_ready_o = (active_channel == 1'b1) ? dst_ready_i : 1'b0;
    assign  descriptor_ready_o  = (active_channel == 1'b0) ? dst_ready_i : 1'b0;
    assign  dst_data_o          = (active_channel) ? data_reader_data_i : descriptor_data_i;
    assign  dst_valid_o         = (active_channel) ? data_reader_valid_i : descriptor_valid_i;

endmodule
