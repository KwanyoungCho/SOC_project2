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



endmodule
