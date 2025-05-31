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
wire    [31:0]      configuration_start_ptr;
wire                configuration_trigger, operation_completed;

// Configuration register module instantiation
SGDMAC_CFG      configuration_unit
(
    .clk            (clk),
    .rst_n          (rst_n),

    // APB interface connection
    .psel_i         (psel_i),
    .penable_i      (penable_i),
    .paddr_i        (paddr_i),
    .pwrite_i       (pwrite_i),
    .pwdata_i       (pwdata_i),
    .pready_o       (pready_o),
    .prdata_o       (prdata_o),
    .pslverr_o      (pslverr_o),

    // control signals
    .start_pointer_o(configuration_start_ptr),
    .start_o        (configuration_trigger),
    .done_i         (operation_completed)
);

// Descriptor processing completion flag
wire                descriptor_fetch_complete;

// Channel arbitration parameters
localparam      CHANNEL_COUNT    =   2;
wire    [3:0]               read_id_array[CHANNEL_COUNT];
assign  {read_id_array[1], read_id_array[0]}  =   {4'd1, 4'd0};

wire    [31:0]              read_addr_array[CHANNEL_COUNT];
wire    [3:0]               read_len_array[CHANNEL_COUNT];
wire    [2:0]               read_size_array[CHANNEL_COUNT];
wire    [1:0]               read_burst_array[CHANNEL_COUNT];
wire                        read_valid_array[CHANNEL_COUNT];
wire                        read_ready_array[CHANNEL_COUNT];
wire                        read_resp_ready_array[CHANNEL_COUNT];

assign rready_o =   read_resp_ready_array[rid_i];

// Command FIFO parameters and signals
localparam      COMMAND_WIDTH    =   48;
wire                        command_fifo_write_enable;
wire   [COMMAND_WIDTH-1:0]  command_fifo_write_data;
wire                        command_operation_type;

// Read command FIFO signals
wire                        rd_cmd_fifo_wr_en,
                            rd_cmd_fifo_is_empty,
                            rd_cmd_fifo_rd_en;
wire    [COMMAND_WIDTH - 1:0] rd_cmd_fifo_rd_data;

// Write command FIFO signals
wire                        wr_cmd_fifo_wr_en,
                            wr_cmd_fifo_is_empty,
                            wr_cmd_fifo_rd_en;
wire    [COMMAND_WIDTH - 1:0] wr_cmd_fifo_rd_data;

// Command FIFO demultiplexer logic
assign  rd_cmd_fifo_wr_en  =   (~command_operation_type) & command_fifo_write_enable;
assign  wr_cmd_fifo_wr_en  =   command_operation_type & command_fifo_write_enable;

// Data buffer parameters and signals
localparam      BUFFER_DEPTH =   128;
wire                        buffer_almost_full,
                            buffer_write_enable,
                            buffer_is_empty,
                            buffer_read_enable;
wire    [31:0]              buffer_write_data, buffer_read_data;
wire    [$clog2(BUFFER_DEPTH):0]   buffer_usage_count;

// Read channel arbiter instantiation
SGDMAC_ARBITER #(
    .N_MASTER      (CHANNEL_COUNT),
    .DATA_SIZE     ($bits(arid_o) + $bits(araddr_o) + $bits(arlen_o) + $bits(arsize_o) + $bits(arburst_o))
)
read_channel_arbiter
(
    .clk            (clk),
    .rst_n          (rst_n),

    // Output to AXI read address channel
    .dst_valid_o    (arvalid_o),
    .dst_ready_i    (arready_i),
    .dst_data_o     ({arid_o, araddr_o, arlen_o, arsize_o, arburst_o}),

    // Data reader channel input
    .data_reader_valid_i(read_valid_array[1]),
    .data_reader_ready_o(read_ready_array[1]),
    .data_reader_data_i ({read_id_array[1], read_addr_array[1], read_len_array[1], read_size_array[1], read_burst_array[1]}),

    // Descriptor fetcher channel input
    .descriptor_valid_i(read_valid_array[0]),
    .descriptor_ready_o(read_ready_array[0]),
    .descriptor_data_i ({read_id_array[0], read_addr_array[0], read_len_array[0], read_size_array[0], read_burst_array[0]})
);

// Descriptor management unit
SGDMAC_DESCRIPTOR_FETCHER descriptor_management_unit
(
    .clk            (clk),
    .rst_n          (rst_n),

    // Configuration inputs
    .start_pointer_i(configuration_start_ptr),
    .start_i        (configuration_trigger),
    .done_o         (descriptor_fetch_complete),

    // AXI read address channel (unused ID)
    .arid_o         (),
    .araddr_o       (read_addr_array[0]),
    .arlen_o        (read_len_array[0]),   
    .arsize_o       (read_size_array[0]),   
    .arburst_o      (read_burst_array[0]),   
    .arvalid_o      (read_valid_array[0]),   
    .arready_i      (read_ready_array[0]), 
    
    // AXI read data channel (unused ID)
    .rid_i          (),
    .rdata_i        (rdata_i),
    .rresp_i        (rresp_i),
    .rlast_i        (rlast_i),
    .rvalid_i       (rvalid_i),
    .rready_o       (read_resp_ready_array[0]),

    // Command FIFO interface (unused almost full)
    .afull_i        (),
    .wren_o         (command_fifo_write_enable),
    .wdata_o        (command_fifo_write_data),
    .rw_o           (command_operation_type)
);

// Read command buffer
SGDMAC_FIFO #(
    .FIFO_DEPTH (16),
    .DATA_WIDTH (COMMAND_WIDTH),
    .AFULL_THRESHOLD (16),
    .AEMPTY_THRESHOLD (0)
)
read_command_buffer
(
    .clk            (clk),
    .rst_n          (rst_n),

    .full_o         (),
    .afull_o        (),
    .wren_i         (rd_cmd_fifo_wr_en),
    .wdata_i        (command_fifo_write_data),

    .empty_o        (rd_cmd_fifo_is_empty),
    .aempty_o       (),
    .rden_i         (rd_cmd_fifo_rd_en),
    .rdata_o        (rd_cmd_fifo_rd_data),
    .cnt_o          ()
);

// Write command buffer
SGDMAC_FIFO #(
    .FIFO_DEPTH (16),
    .DATA_WIDTH (COMMAND_WIDTH),
    .AFULL_THRESHOLD (16),
    .AEMPTY_THRESHOLD (0)
)
write_command_buffer
(
    .clk            (clk),
    .rst_n          (rst_n),

    .full_o         (),
    .afull_o        (),
    .wren_i         (wr_cmd_fifo_wr_en),
    .wdata_i        (command_fifo_write_data),

    .empty_o        (wr_cmd_fifo_is_empty),
    .aempty_o       (),
    .rden_i         (wr_cmd_fifo_rd_en),
    .rdata_o        (wr_cmd_fifo_rd_data),
    .cnt_o          ()
);

// Main data storage buffer
SGDMAC_FIFO #(
    .FIFO_DEPTH (BUFFER_DEPTH),
    .DATA_WIDTH (32),
    .AFULL_THRESHOLD (BUFFER_DEPTH),
    .AEMPTY_THRESHOLD (0)
)
primary_data_buffer
(
    .clk            (clk),
    .rst_n          (rst_n),

    .full_o         (),
    .afull_o        (buffer_almost_full),
    .wren_i         (buffer_write_enable),
    .wdata_i        (buffer_write_data),

    .empty_o        (buffer_is_empty),
    .aempty_o       (),
    .rden_i         (buffer_read_enable),
    .rdata_o        (buffer_read_data),
    .cnt_o          (buffer_usage_count)
);

// Command demultiplexer and control signals
wire            operation_mode;
wire[47:0]      read_engine_command, write_engine_command;
wire            read_engine_idle, write_engine_idle;
wire            read_engine_trigger, write_engine_trigger;

assign read_engine_command   =   rd_cmd_fifo_rd_data;
assign write_engine_command  =   wr_cmd_fifo_rd_data;
assign read_engine_trigger   =   read_engine_idle & (!rd_cmd_fifo_is_empty);
assign write_engine_trigger  =   write_engine_idle & (!wr_cmd_fifo_is_empty);
assign wr_cmd_fifo_rd_en = write_engine_trigger;
assign rd_cmd_fifo_rd_en = read_engine_trigger;

// Overall operation completion logic
assign operation_completed = descriptor_fetch_complete & read_engine_idle & write_engine_idle & 
                           rd_cmd_fifo_is_empty & wr_cmd_fifo_is_empty & buffer_is_empty;

// Data read engine instantiation
SGDMAC_READ #(
    .FIFO_DEPTH     (BUFFER_DEPTH)
)   
data_read_engine
(
    .clk            (clk),
    .rst_n          (rst_n),
    
    // AXI read address channel (unused ID)
    .arid_o         (),
    .araddr_o       (read_addr_array[1]),
    .arlen_o        (read_len_array[1]),   
    .arsize_o       (read_size_array[1]),   
    .arburst_o      (read_burst_array[1]),   
    .arvalid_o      (read_valid_array[1]),   
    .arready_i      (read_ready_array[1]), 
    
    // AXI read data channel (unused ID)
    .rid_i          (),
    .rdata_i        (rdata_i),
    .rresp_i        (rresp_i),
    .rlast_i        (rlast_i),
    .rvalid_i       (rvalid_i),
    .rready_o       (read_resp_ready_array[1]),

    // Control interface
    .start_i        (read_engine_trigger),
    .desc_done_i    (descriptor_fetch_complete),
    .cmd_i          (read_engine_command),
    .done_o         (read_engine_idle),

    // Buffer interface
    .fifo_afull_i   (buffer_almost_full),
    .fifo_cnt_i     (buffer_usage_count), 
    .fifo_wren_o    (buffer_write_enable),
    .fifo_wdata_o   (buffer_write_data)
);

// Data write engine instantiation
SGDMAC_WRITE #(
    .FIFO_DEPTH     (BUFFER_DEPTH)
)   
data_write_engine
(
    .clk            (clk),
    .rst_n          (rst_n),

    // AXI write address channel (unused ID)
    .awid_o         (),
    .awaddr_o       (awaddr_o),
    .awlen_o        (awlen_o),
    .awsize_o       (awsize_o),
    .awburst_o      (awburst_o),
    .awvalid_o      (awvalid_o),
    .awready_i      (awready_i),

    // AXI write data channel
    .wid_o          (wid_o),
    .wdata_o        (wdata_o),
    .wstrb_o        (wstrb_o),
    .wlast_o        (wlast_o),
    .wvalid_o       (wvalid_o),
    .wready_i       (wready_i),

    // AXI write response channel (unused ID)
    .bid_i          (),
    .bresp_i        (bresp_i),
    .bvalid_i       (bvalid_i),
    .bready_o       (bready_o),

    // Control interface
    .start_i        (write_engine_trigger),
    .cmd_i          (write_engine_command),
    .done_o         (write_engine_idle),

    // Buffer interface
    .fifo_empty_i   (buffer_is_empty),
    .fifo_rdata_i   (buffer_read_data),
    .fifo_rden_o    (buffer_read_enable)
);

endmodule
