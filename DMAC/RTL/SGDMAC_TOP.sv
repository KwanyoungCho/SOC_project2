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

wire    [31:0]      cfg_start_pointer;
wire                cfg_start, cfg_done;
SGDMAC_CFG      u_cfg
(
    .clk            (clk),
    .rst_n          (rst_n),  // _n means active low

    // AMBA APB interface
    .psel_i         (psel_i),
    .penable_i      (penable_i),
    .paddr_i        (paddr_i),
    .pwrite_i       (pwrite_i),
    .pwdata_i       (pwdata_i),
    .pready_o       (pready_o),
    .prdata_o       (prdata_o),
    .pslverr_o      (pslverr_o),

    // configuration registers
    .start_pointer_o(cfg_start_pointer),
    .start_o        (cfg_start),
    .done_i         (cfg_done)
);

/* DONE */
wire                desc_done;
/* ARBITER */
localparam      N_CH    =   2;
wire    [3:0]               arid_vec[N_CH];
assign  {arid_vec[1], arid_vec[0]}  =   {4'd1, 4'd0};
wire    [31:0]              araddr_vec[N_CH];
wire    [3:0]               arlen_vec[N_CH];
wire    [2:0]               arsize_vec[N_CH];
wire    [1:0]               arburst_vec[N_CH];
wire                        arvalid_vec[N_CH];
wire                        arready_vec[N_CH];
wire                        rready_vec[N_CH];

assign rready_o =   rready_vec[rid_i];

/* CMD FIFO */
localparam      CMD_DATA_LEN    =   48;
wire                        cmd_fifo_wren;
wire   [CMD_DATA_LEN-1:0]   cmd_fifo_wdata;
wire                        cmd_rw;

wire                        read_cmd_fifo_wren,
                            read_cmd_fifo_empty,
                            read_cmd_fifo_rden;
wire    [CMD_DATA_LEN - 1:0] read_cmd_fifo_rdata;

wire                        write_cmd_fifo_wren,
                            write_cmd_fifo_empty,
                            write_cmd_fifo_rden;
wire    [CMD_DATA_LEN - 1:0] write_cmd_fifo_rdata;

assign  read_cmd_fifo_wren  =   (~cmd_rw)&cmd_fifo_wren;
assign  write_cmd_fifo_wren =   cmd_rw&cmd_fifo_wren;
/* DATA FIFO */
localparam      DATA_FIFO_DEPTH =   128;
wire                        data_fifo_afull,
                            data_fifo_wren,
                            data_fifo_empty,
                            data_fifo_rden;
wire    [31:0]              data_fifo_wdata, data_fifo_rdata;
wire    [$clog2(DATA_FIFO_DEPTH):0]   data_fifo_cnt;

// ARBITER [AR channel]
SGDMAC_ARBITER #(
    .N_MASTER      (N_CH),
    .DATA_SIZE     ($bits(arid_o) + $bits(araddr_o) + $bits(arlen_o) + $bits(arsize_o) + $bits(arburst_o))
)
u_ar_arbiter
(
    .clk            (clk),
    .rst_n          (rst_n),

    .dst_valid_o    (arvalid_o),
    .dst_ready_i    (arready_i),
    .dst_data_o     ({arid_o, araddr_o, arlen_o, arsize_o, arburst_o}),

    .data_reader_valid_i(arvalid_vec[1]),
    .data_reader_ready_o(arready_vec[1]),
    .data_reader_data_i ({arid_vec[1], araddr_vec[1], arlen_vec[1], arsize_vec[1], arburst_vec[1]}),

    .descriptor_valid_i(arvalid_vec[0]),
    .descriptor_ready_o(arready_vec[0]),
    .descriptor_data_i ({arid_vec[0], araddr_vec[0], arlen_vec[0], arsize_vec[0], arburst_vec[0]})
);

// Descriptor Fetcher
SGDMAC_DESCRIPTOR_FETCHER u_descriptor_fetcher
(
    .clk            (clk),
    .rst_n          (rst_n),

    .start_pointer_i(cfg_start_pointer),
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
    .wren_o         (cmd_fifo_wren),
    .wdata_o        (cmd_fifo_wdata),
    .rw_o           (cmd_rw)
);

SGDMAC_FIFO #(
    .FIFO_DEPTH (16),
    .DATA_WIDTH (CMD_DATA_LEN),
    .AFULL_THRESHOLD (16),
    .AEMPTY_THRESHOLD (0)
)
u_cmd_read_fifo
(
    .clk            (clk),
    .rst_n          (rst_n),

    .full_o         (),
    .afull_o        (),
    .wren_i         (read_cmd_fifo_wren),
    .wdata_i        (cmd_fifo_wdata),

    .empty_o        (read_cmd_fifo_empty),
    .aempty_o       (),
    .rden_i         (read_cmd_fifo_rden),
    .rdata_o        (read_cmd_fifo_rdata),
    .cnt_o          ()
);

SGDMAC_FIFO #(
    .FIFO_DEPTH (16),
    .DATA_WIDTH (CMD_DATA_LEN),
    .AFULL_THRESHOLD (16),
    .AEMPTY_THRESHOLD (0)
)
u_cmd_write_fifo
(
    .clk            (clk),
    .rst_n          (rst_n),

    .full_o         (),
    .afull_o        (),
    .wren_i         (write_cmd_fifo_wren),
    .wdata_i        (cmd_fifo_wdata),

    .empty_o        (write_cmd_fifo_empty),
    .aempty_o       (),
    .rden_i         (write_cmd_fifo_rden),
    .rdata_o        (write_cmd_fifo_rdata),
    .cnt_o          ()
);


// MAX: 15 * 128byte -> 15 * 32 entries
SGDMAC_FIFO #(
    .FIFO_DEPTH (DATA_FIFO_DEPTH),
    .DATA_WIDTH (32),
    .AFULL_THRESHOLD (DATA_FIFO_DEPTH),
    .AEMPTY_THRESHOLD (0)
)
u_data_fifo
(
    .clk            (clk),
    .rst_n          (rst_n),

    .full_o         (),
    .afull_o        (data_fifo_afull),
    .wren_i         (data_fifo_wren),
    .wdata_i        (data_fifo_wdata),

    .empty_o        (data_fifo_empty),
    .aempty_o       (),
    .rden_i         (data_fifo_rden),
    .rdata_o        (data_fifo_rdata),
    .cnt_o          (data_fifo_cnt)
);

//DEMUX
wire            rw;
wire[47:0]      reader_cmd, writer_cmd;
wire            reader_done, writer_done;
wire            reader_start, writer_start;

assign reader_cmd   =   read_cmd_fifo_rdata;
assign writer_cmd   =   write_cmd_fifo_rdata;
assign reader_start =   reader_done & !read_cmd_fifo_empty;
assign writer_start =   writer_done & !write_cmd_fifo_empty;
assign write_cmd_fifo_rden= writer_start;
assign read_cmd_fifo_rden= reader_start;

assign cfg_done    =    desc_done & reader_done & writer_done & read_cmd_fifo_empty & write_cmd_fifo_empty & data_fifo_empty;

SGDMAC_READ #(
    .FIFO_DEPTH     (DATA_FIFO_DEPTH)
)   
u_reader
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

    .start_i        (reader_start),
    .desc_done_i    (desc_done),
    .cmd_i          (reader_cmd),
    .done_o         (reader_done),

    .fifo_afull_i   (data_fifo_afull),
    .fifo_cnt_i     (data_fifo_cnt), 
    .fifo_wren_o    (data_fifo_wren),
    .fifo_wdata_o   (data_fifo_wdata)
);

SGDMAC_WRITE #(
    .FIFO_DEPTH     (DATA_FIFO_DEPTH)
)   
u_writer
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

    .start_i        (writer_start),
    .cmd_i          (writer_cmd),
    .done_o         (writer_done),

    .fifo_empty_i   (data_fifo_empty),
    .fifo_rdata_i   (data_fifo_rdata),
    .fifo_rden_o    (data_fifo_rden)
);


endmodule
