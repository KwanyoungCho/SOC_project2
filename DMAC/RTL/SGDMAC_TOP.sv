// Copyright (c) 2021 Sungkyunkwan University
//
// Authors:
// - Jungrae Kim <dale40@skku.edu>

module SGDMAC_TOP
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

    // AMBA AXI interface (AW channel)
    output  wire    [3:0]       awid_o,
    output  wire    [31:0]      awaddr_o,
    output  wire    [3:0]       awlen_o,
    output  wire    [2:0]       awsize_o,
    output  wire    [1:0]       awburst_o,
    output  wire                awvalid_o,
    input   wire                awready_i,

    // AMBA AXI interface (W channel)
    output  wire    [3:0]       wid_o,
    output  wire    [31:0]      wdata_o,
    output  wire    [3:0]       wstrb_o,
    output  wire                wlast_o,
    output  wire                wvalid_o,
    input   wire                wready_i,

    // AMBA AXI interface (B channel)
    input   wire    [3:0]       bid_i,
    input   wire    [1:0]       bresp_i,
    input   wire                bvalid_i,
    output  wire                bready_o,

    // AMBA AXI interface (AR channel)
    output  wire    [3:0]       arid_o,
    output  wire    [31:0]      araddr_o,
    output  wire    [3:0]       arlen_o,
    output  wire    [2:0]       arsize_o,
    output  wire    [1:0]       arburst_o,
    output  wire                arvalid_o,
    input   wire                arready_i,

    // AMBA AXI interface (R channel)
    input   wire    [3:0]       rid_i,
    input   wire    [31:0]      rdata_i,
    input   wire    [1:0]       rresp_i,
    input   wire                rlast_i,
    input   wire                rvalid_i,
    output  wire                rready_o
);

localparam  N = 2;
localparam  WIDTH = 48;
localparam  DEPTH = 128;

wire    [31:0]  cfg_start_ptr;
wire            cfg_trigger, cfg_done;
wire            dt_done;
wire    [3:0]   arid_bus[N];
wire    [31:0]  araddr_bus[N];
wire    [3:0]   arlen_bus[N];
wire    [2:0]   arsize_bus[N];
wire    [1:0]   arburst_bus[N];
wire            arvalid_bus[N];
wire            arready_bus[N];
wire            rready_bus[N];

wire            cmd_wr_en;
wire [WIDTH-1:0] cmd_wr_data;
wire            cmd_rw;

wire            rd_cmd_wr_en, rd_cmd_empty, rd_cmd_rd_en;
wire [WIDTH-1:0] rd_cmd_data;
wire            wr_cmd_wr_en, wr_cmd_empty, wr_cmd_rd_en;
wire [WIDTH-1:0] wr_cmd_data;

wire        buf_afull, buf_empty;
wire        buf_wr_en, buf_rd_en;
wire [31:0] buf_wr_data, buf_rd_data;
wire [$clog2(DEPTH):0] buf_cnt;

wire        rd_idle, wr_idle;
wire        rd_start = rd_idle & ~rd_cmd_empty;
wire        wr_start = wr_idle & ~wr_cmd_empty;


assign {arid_bus[1], arid_bus[0]} = {4'd1, 4'd0};
assign rready_o = rready_bus[rid_i];
assign rd_cmd_wr_en = (~cmd_rw) & cmd_wr_en;
assign wr_cmd_wr_en = cmd_rw & cmd_wr_en;

assign rd_cmd_rd_en = rd_start;
assign wr_cmd_rd_en = wr_start;

assign cfg_done = dt_done & rd_idle & wr_idle & 
                  rd_cmd_empty & wr_cmd_empty & buf_empty;

SGDMAC_CFG i0 (
    .clk            (clk),
    .rst_n          (rst_n),
    .psel_i         (psel_i),
    .penable_i      (penable_i),
    .paddr_i        (paddr_i),
    .pwrite_i       (pwrite_i),
    .pwdata_i       (pwdata_i),
    .pready_o       (pready_o),
    .prdata_o       (prdata_o),
    .pslverr_o      (pslverr_o),
    .start_pointer_o(cfg_start_ptr),
    .start_o        (cfg_trigger),
    .done_i         (cfg_done)
);

SGDMAC_ARBITER #(
    .N_MASTER   (N),
    .DATA_SIZE  ($bits(arid_o) + $bits(araddr_o) + $bits(arlen_o) + $bits(arsize_o) + $bits(arburst_o))
) i1 (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dst_valid_o            (arvalid_o),
    .dst_ready_i            (arready_i),
    .dst_data_o             ({arid_o, araddr_o, arlen_o, arsize_o, arburst_o}),
    .data_reader_valid_i    (arvalid_bus[1]),
    .data_reader_ready_o    (arready_bus[1]),
    .data_reader_data_i     ({arid_bus[1], araddr_bus[1], arlen_bus[1], arsize_bus[1], arburst_bus[1]}),
    .descriptor_valid_i     (arvalid_bus[0]),
    .descriptor_ready_o     (arready_bus[0]),
    .descriptor_data_i      ({arid_bus[0], araddr_bus[0], arlen_bus[0], arsize_bus[0], arburst_bus[0]})
);

SGDMAC_DESCRIPTOR_FETCHER i2 (
    .clk            (clk),
    .rst_n          (rst_n),
    .start_pointer_i(cfg_start_ptr),
    .start_i        (cfg_trigger),
    .done_o         (dt_done),
    .arid_o         (),
    .araddr_o       (araddr_bus[0]),
    .arlen_o        (arlen_bus[0]),
    .arsize_o       (arsize_bus[0]),
    .arburst_o      (arburst_bus[0]),
    .arvalid_o      (arvalid_bus[0]),
    .arready_i      (arready_bus[0]),
    .rid_i          (),
    .rdata_i        (rdata_i),
    .rresp_i        (rresp_i),
    .rlast_i        (rlast_i),
    .rvalid_i       (rvalid_i),
    .rready_o       (rready_bus[0]),
    .afull_i        (),
    .wren_o         (cmd_wr_en),
    .wdata_o        (cmd_wr_data),
    .rw_o           (cmd_rw)
);

SGDMAC_FIFO #(
    .FIFO_DEPTH     (16),
    .DATA_WIDTH     (WIDTH),
    .AFULL_THRESHOLD(16),
    .AEMPTY_THRESHOLD(0)
) i3 (
    .clk    (clk),
    .rst_n  (rst_n),
    .full_o (),
    .afull_o(),
    .wren_i (rd_cmd_wr_en),
    .wdata_i(cmd_wr_data),
    .empty_o(rd_cmd_empty),
    .aempty_o(),
    .rden_i (rd_cmd_rd_en),
    .rdata_o(rd_cmd_data),
    .cnt_o  ()
);

SGDMAC_FIFO #(
    .FIFO_DEPTH     (16),
    .DATA_WIDTH     (WIDTH),
    .AFULL_THRESHOLD(16),
    .AEMPTY_THRESHOLD(0)
) i4 (
    .clk    (clk),
    .rst_n  (rst_n),
    .full_o (),
    .afull_o(),
    .wren_i (wr_cmd_wr_en),
    .wdata_i(cmd_wr_data),
    .empty_o(wr_cmd_empty),
    .aempty_o(),
    .rden_i (wr_cmd_rd_en),
    .rdata_o(wr_cmd_data),
    .cnt_o  ()
);

SGDMAC_FIFO #(
    .FIFO_DEPTH     (DEPTH),
    .DATA_WIDTH     (32),
    .AFULL_THRESHOLD(DEPTH),  // Same as original!
    .AEMPTY_THRESHOLD(0)
) i5 (
    .clk    (clk),
    .rst_n  (rst_n),
    .full_o (),
    .afull_o(buf_afull),
    .wren_i (buf_wr_en),
    .wdata_i(buf_wr_data),
    .empty_o(buf_empty),
    .aempty_o(),
    .rden_i (buf_rd_en),
    .rdata_o(buf_rd_data),
    .cnt_o  (buf_cnt)
);

SGDMAC_READ #(.FIFO_DEPTH(DEPTH)) i6 (
    .clk        (clk),
    .rst_n      (rst_n),
    .arid_o     (),
    .araddr_o   (araddr_bus[1]),
    .arlen_o    (arlen_bus[1]),
    .arsize_o   (arsize_bus[1]),
    .arburst_o  (arburst_bus[1]),
    .arvalid_o  (arvalid_bus[1]),
    .arready_i  (arready_bus[1]),
    .rid_i      (),
    .rdata_i    (rdata_i),
    .rresp_i    (rresp_i),
    .rlast_i    (rlast_i),
    .rvalid_i   (rvalid_i),
    .rready_o   (rready_bus[1]),
    .start_i    (rd_start),
    .dt_done_i  (dt_done),
    .cmd_i      (rd_cmd_data),
    .done_o     (rd_idle),
    .fifo_afull_i(buf_afull),
    .fifo_cnt_i (buf_cnt),
    .fifo_wren_o(buf_wr_en),
    .fifo_wdata_o(buf_wr_data)
);

SGDMAC_WRITE #(.FIFO_DEPTH(DEPTH)) i7 (
    .clk        (clk),
    .rst_n      (rst_n),
    .awid_o     (),
    .awaddr_o   (awaddr_o),
    .awlen_o    (awlen_o),
    .awsize_o   (awsize_o),
    .awburst_o  (awburst_o),
    .awvalid_o  (awvalid_o),
    .awready_i  (awready_i),
    .wid_o      (wid_o),
    .wdata_o    (wdata_o),
    .wstrb_o    (wstrb_o),
    .wlast_o    (wlast_o),
    .wvalid_o   (wvalid_o),
    .wready_i   (wready_i),
    .bid_i      (),
    .bresp_i    (bresp_i),
    .bvalid_i   (bvalid_i),
    .bready_o   (bready_o),
    .start_i    (wr_start),
    .cmd_i      (wr_cmd_data),
    .done_o     (wr_idle),
    .fifo_empty_i(buf_empty),
    .fifo_rdata_i(buf_rd_data),
    .fifo_rden_o(buf_rd_en)
);

endmodule
