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

    // AMBA AXI interface (AW channel)
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

// Configuration interface signals
wire    [31:0]      cfg_start_ptr;
wire                cfg_start, cfg_done;

// Configuration register module
SGDMAC_CFG      u_cfg
(
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
    .start_o        (cfg_start),
    .done_i         (cfg_done)
);

// Descriptor processing signals
wire                desc_done;

// Channel arbitration - optimized for 2 channels
localparam      N_CH = 2;
wire    [31:0]  araddr_vec[N_CH];
wire    [3:0]   arlen_vec[N_CH];
wire    [2:0]   arsize_vec[N_CH];
wire    [1:0]   arburst_vec[N_CH];
wire            arvalid_vec[N_CH];
wire            arready_vec[N_CH];
wire            rready_vec[N_CH];

// Direct assignment for read response ready multiplexing
assign rready_o = rready_vec[rid_i];

// Command FIFO parameters - optimized width
localparam      CMD_WIDTH = 48;
wire                    cmd_fifo_wr;
wire   [CMD_WIDTH-1:0]  cmd_fifo_data;
wire                    cmd_rw;

// Optimized command FIFO splitting
wire            rd_cmd_wr   = (~cmd_rw) & cmd_fifo_wr;
wire            wr_cmd_wr   = cmd_rw & cmd_fifo_wr;
wire            rd_cmd_empty, wr_cmd_empty;
wire            rd_cmd_rd, wr_cmd_rd;
wire [CMD_WIDTH-1:0] rd_cmd_data, wr_cmd_data;

// Data buffer parameters - optimized depth
localparam      DATA_DEPTH = 128;
wire            data_afull, data_empty;
wire            data_wr, data_rd;
wire [31:0]     data_wdata, data_rdata;
wire [$clog2(DATA_DEPTH):0] data_cnt;

// Read channel arbiter
SGDMAC_ARBITER #(
    .DATA_SIZE  ($bits({arid_o, araddr_o, arlen_o, arsize_o, arburst_o}))
)
u_arbiter
(
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dst_valid_o            (arvalid_o),
    .dst_ready_i            (arready_i),
    .dst_data_o             ({arid_o, araddr_o, arlen_o, arsize_o, arburst_o}),
    .data_reader_valid_i    (arvalid_vec[1]),
    .data_reader_ready_o    (arready_vec[1]),
    .data_reader_data_i     ({4'd1, araddr_vec[1], arlen_vec[1], arsize_vec[1], arburst_vec[1]}),
    .descriptor_valid_i     (arvalid_vec[0]),
    .descriptor_ready_o     (arready_vec[0]),
    .descriptor_data_i      ({4'd0, araddr_vec[0], arlen_vec[0], arsize_vec[0], arburst_vec[0]})
);

// Descriptor fetcher
SGDMAC_DESCRIPTOR_FETCHER u_desc_fetch
(
    .clk            (clk),
    .rst_n          (rst_n),
    .start_pointer_i(cfg_start_ptr),
    .start_i        (cfg_start),
    .done_o         (desc_done),
    .arid_o         (),
    .araddr_o       (araddr_vec[0]),
    .arlen_o        (arlen_vec[0]),   
    .arsize_o       (arsize_vec[0]),   
    .arburst_o      (arburst_vec[0]),   
    .arvalid_o      (arvalid_vec[0]),   
    .arready_i      (arready_vec[0]), 
    .rid_i          (),
    .rdata_i        (rdata_i),
    .rresp_i        (rresp_i),
    .rlast_i        (rlast_i),
    .rvalid_i       (rvalid_i),
    .rready_o       (rready_vec[0]),
    .afull_i        (),
    .wren_o         (cmd_fifo_wr),
    .wdata_o        (cmd_fifo_data),
    .rw_o           (cmd_rw)
);

// Command FIFOs - optimized depth
SGDMAC_FIFO #(.FIFO_DEPTH(16), .DATA_WIDTH(CMD_WIDTH)) u_rd_cmd_fifo
(
    .clk        (clk),
    .rst_n      (rst_n),
    .full_o     (),
    .afull_o    (),
    .wren_i     (rd_cmd_wr),
    .wdata_i    (cmd_fifo_data),
    .empty_o    (rd_cmd_empty),
    .aempty_o   (),
    .rden_i     (rd_cmd_rd),
    .rdata_o    (rd_cmd_data),
    .cnt_o      ()
);

SGDMAC_FIFO #(.FIFO_DEPTH(16), .DATA_WIDTH(CMD_WIDTH)) u_wr_cmd_fifo
(
    .clk        (clk),
    .rst_n      (rst_n),
    .full_o     (),
    .afull_o    (),
    .wren_i     (wr_cmd_wr),
    .wdata_i    (cmd_fifo_data),
    .empty_o    (wr_cmd_empty),
    .aempty_o   (),
    .rden_i     (wr_cmd_rd),
    .rdata_o    (wr_cmd_data),
    .cnt_o      ()
);

// Data FIFO
SGDMAC_FIFO #(.FIFO_DEPTH(DATA_DEPTH), .DATA_WIDTH(32)) u_data_fifo
(
    .clk        (clk),
    .rst_n      (rst_n),
    .full_o     (),
    .afull_o    (data_afull),
    .wren_i     (data_wr),
    .wdata_i    (data_wdata),
    .empty_o    (data_empty),
    .aempty_o   (),
    .rden_i     (data_rd),
    .rdata_o    (data_rdata),
    .cnt_o      (data_cnt)
);

// Engine control signals - optimized
wire    rd_done, wr_done;
wire    rd_start = rd_done & (~rd_cmd_empty);
wire    wr_start = wr_done & (~wr_cmd_empty);

// Optimized completion detection
assign  cfg_done = desc_done & rd_done & wr_done & rd_cmd_empty & wr_cmd_empty & data_empty;
assign  rd_cmd_rd = rd_start;
assign  wr_cmd_rd = wr_start;

// Read engine
SGDMAC_READ #(.FIFO_DEPTH(DATA_DEPTH)) u_reader
(
    .clk            (clk),
    .rst_n          (rst_n),
    .arid_o         (),
    .araddr_o       (araddr_vec[1]),
    .arlen_o        (arlen_vec[1]),   
    .arsize_o       (arsize_vec[1]),   
    .arburst_o      (arburst_vec[1]),   
    .arvalid_o      (arvalid_vec[1]),   
    .arready_i      (arready_vec[1]), 
    .rid_i          (),
    .rdata_i        (rdata_i),
    .rresp_i        (rresp_i),
    .rlast_i        (rlast_i),
    .rvalid_i       (rvalid_i),
    .rready_o       (rready_vec[1]),
    .start_i        (rd_start),
    .desc_done_i    (desc_done),
    .cmd_i          (rd_cmd_data),
    .done_o         (rd_done),
    .fifo_afull_i   (data_afull),
    .fifo_cnt_i     (data_cnt), 
    .fifo_wren_o    (data_wr),
    .fifo_wdata_o   (data_wdata)
);

// Write engine
SGDMAC_WRITE #(.FIFO_DEPTH(DATA_DEPTH)) u_writer
(
    .clk            (clk),
    .rst_n          (rst_n),
    .awid_o         (),
    .awaddr_o       (awaddr_o),
    .awlen_o        (awlen_o),
    .awsize_o       (awsize_o),
    .awburst_o      (awburst_o),
    .awvalid_o      (awvalid_o),
    .awready_i      (awready_i),
    .wid_o          (wid_o),
    .wdata_o        (wdata_o),
    .wstrb_o        (wstrb_o),
    .wlast_o        (wlast_o),
    .wvalid_o       (wvalid_o),
    .wready_i       (wready_i),
    .bid_i          (),
    .bresp_i        (bresp_i),
    .bvalid_i       (bvalid_i),
    .bready_o       (bready_o),
    .start_i        (wr_start),
    .cmd_i          (wr_cmd_data),
    .done_o         (wr_done),
    .fifo_empty_i   (data_empty),
    .fifo_rdata_i   (data_rdata),
    .fifo_rden_o    (data_rd)
);

endmodule
