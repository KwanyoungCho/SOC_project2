// Copyright (c) 2021 Sungkyunkwan University
//
// Authors:
// - Jungrae Kim <dale40@skku.edu>

module SGDMAC_CFG
(
    input   wire                clk,
    input   wire                rst_n,  // _n means active low

    // AMBA APB interface
    input   wire                psel_i,
    input   wire                penable_i,
    input   wire    [11:0]      paddr_i,
    input   wire                pwrite_i,
    input   wire    [31:0]      pwdata_i,
    output  reg                 pready_o,
    output  reg     [31:0]      prdata_o,
    output  reg                 pslverr_o,

    // configuration registers
    output  reg     [31:0]      start_pointer_o,
    output  wire                start_o,
    input   wire                done_i
);

    // Internal configuration storage registers
    reg [31:0]                      descriptor_start_address;
    reg [31:0]                      control_register;

    // Register address map definitions - optimized for decode speed
    localparam DESCRIPTOR_PTR_ADDR    =       12'h100;
    localparam CONTROL_REG_ADDR       =       12'h104;
    localparam STATUS_REG_ADDR        =       12'h108;
    localparam VERSION_REG_ADDR       =       12'h000;
    localparam HARDWARE_VERSION       =       32'h01012024;

    // Optimized APB transaction detection
    wire    write_enable = psel_i & penable_i & pwrite_i;
    wire    read_enable  = psel_i & (~penable_i);

    // Optimized register write logic - reduced critical path
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            descriptor_start_address <= 32'd0;
            control_register         <= 32'd0;
        end
        else if(write_enable) begin
            // Parallel address decode for better timing
            if (paddr_i == DESCRIPTOR_PTR_ADDR)
                descriptor_start_address <= pwdata_i;
            else if (paddr_i == CONTROL_REG_ADDR)
                control_register <= {31'd0, pwdata_i[0]};
        end
    end

    // Optimized start signal - combinational for immediate response
    assign start_o = write_enable & (paddr_i == CONTROL_REG_ADDR) & pwdata_i[0];
    
    // Direct assignment to reduce delay
    always_comb begin
        start_pointer_o = descriptor_start_address;
    end

    // Optimized read logic - single cycle response
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            prdata_o <= 32'd0;
        end
        else if (read_enable) begin
            // Optimized case statement with priority encoding
            casez(paddr_i)
                12'h000: prdata_o <= HARDWARE_VERSION;
                12'h100: prdata_o <= descriptor_start_address;
                12'h104: prdata_o <= control_register;
                12'h108: prdata_o <= {31'd0, done_i};
                default: prdata_o <= 32'd0;
            endcase
        end
    end

    // Constant assignments for optimal timing
    always_comb begin
        pready_o  = 1'b1;    // Always ready for better performance
        pslverr_o = 1'b0;    // No slave errors
    end

endmodule
