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

    reg                     channel, channel_n; //1:data reader, 0: descriptor
    wire                    rcvd;
    assign rcvd                 =   dst_valid_o & dst_ready_i;

    always_ff @(posedge clk) begin
        if(!rst_n) begin
            channel <= 1'd0;
        end
        else begin
            channel <= channel_n;
        end
    end

    always_comb begin 
        channel_n   =   channel;
        if(rcvd || ~dst_valid_o)begin
            case(channel)
            0: channel_n    =   (data_reader_valid_i)?1:0;
            1: channel_n    =   (descriptor_valid_i)?0:1;
            endcase
        end
    end

    assign  data_reader_ready_o =   (channel == 1)?dst_ready_i:0;
    assign  descriptor_ready_o  =   (channel == 0)?dst_ready_i:0;
    assign  dst_data_o          =   (channel)?data_reader_data_i:descriptor_data_i;
    assign  dst_valid_o         =   (channel)?data_reader_valid_i:descriptor_valid_i;


endmodule
