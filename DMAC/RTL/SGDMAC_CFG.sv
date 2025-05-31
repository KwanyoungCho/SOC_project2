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

    //config regs
    reg [31:0]                      start_pointer;
    reg [31:0]                      ctrl;

    localparam DMA_START    =       12'h100;
    localparam DMA_CONTROL  =       12'h104;
    localparam DMA_STATUS   =       12'h108;
    localparam DMA_VERSION  =       12'h000;
    localparam VERSION      =       32'h01012024;

    //APB WRITE
    //wren: PSEL, PENABLE, PWRITE
    wire    wren;
    assign wren             =       psel_i & penable_i & pwrite_i;

    always_ff @(posedge clk) begin
        if(!rst_n) begin
            start_pointer <= 32'd0;
            ctrl          <= 32'd0;
        end
        else if(wren) begin
            case ( paddr_i )
                DMA_START: start_pointer    <= pwdata_i; 
                DMA_CONTROL: ctrl           <= {31'd0, pwdata_i[0]}; 
                default: begin end
            endcase
        end
    end

    //START: write 1 to DMA_CMD
    assign start_o          =           (paddr_i == DMA_CONTROL) & wren & pwdata_i[0];
    assign start_pointer_o  =           start_pointer;

    reg[31:0]       rdata;
    //APB READ
    // PSEL, PENABLE, !PWRITE
    // setup: PSEL & !PENABLE
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            rdata <= 32'd0;
        end
        else if (psel_i & !penable_i)begin
            case(paddr_i)
            DMA_VERSION :   rdata   <=  VERSION;
            DMA_START   :   rdata   <=  start_pointer;
            DMA_CONTROL :   rdata   <=  ctrl;
            DMA_STATUS  :   rdata   <=  {31'd0, done_i};
            default     :   rdata   <=  32'd0;
            endcase
        end
    end

    assign  pready_o        =   1'b1;
    assign  prdata_o        =   rdata;
    assign  pslverr_o       =   1'b0;


endmodule
