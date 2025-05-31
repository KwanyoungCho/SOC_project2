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

    // Register address map definitions
    localparam DESCRIPTOR_PTR_ADDR    =       12'h100;
    localparam CONTROL_REG_ADDR       =       12'h104;
    localparam STATUS_REG_ADDR        =       12'h108;
    localparam VERSION_REG_ADDR       =       12'h000;
    localparam HARDWARE_VERSION       =       32'h01012024;

    // APB write transaction detection
    wire    write_transaction_active;
    assign write_transaction_active = psel_i && penable_i && pwrite_i;

    // Configuration register update logic
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            descriptor_start_address <= 32'd0;
            control_register         <= 32'd0;
        end
        else if(write_transaction_active) begin
            case ( paddr_i )
                DESCRIPTOR_PTR_ADDR: descriptor_start_address <= pwdata_i; 
                CONTROL_REG_ADDR:    control_register         <= {31'd0, pwdata_i[0]}; 
                default: begin 
                    // No operation for unrecognized addresses
                end
            endcase
        end
    end

    // Start signal generation logic
    assign start_o          = (paddr_i == CONTROL_REG_ADDR) && write_transaction_active && pwdata_i[0];
    assign start_pointer_o  = descriptor_start_address;

    // Read data preparation register
    reg[31:0]       read_data_buffer;
    
    // APB read transaction handling
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            read_data_buffer <= 32'd0;
        end
        else if (psel_i && (!penable_i)) begin
            case(paddr_i)
            VERSION_REG_ADDR    :   read_data_buffer   <=  HARDWARE_VERSION;
            DESCRIPTOR_PTR_ADDR :   read_data_buffer   <=  descriptor_start_address;
            CONTROL_REG_ADDR    :   read_data_buffer   <=  control_register;
            STATUS_REG_ADDR     :   read_data_buffer   <=  {31'd0, done_i};
            default             :   read_data_buffer   <=  32'd0;
            endcase
        end
    end

    // APB interface output assignments
    assign  pready_o        =   1'b1;
    assign  prdata_o        =   read_data_buffer;
    assign  pslverr_o       =   1'b0;

endmodule
