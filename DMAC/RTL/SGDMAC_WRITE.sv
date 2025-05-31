module SGDMAC_WRITE #(
    parameter               FIFO_DEPTH = 64
)
(
    input   wire            clk,
    input   wire            rst_n,

    // AXI Write Address Channel Interface
    output  wire    [3:0]   awid_o,
    output  wire    [31:0]  awaddr_o,
    output  wire    [3:0]   awlen_o,
    output  wire    [2:0]   awsize_o,
    output  wire    [1:0]   awburst_o,
    output  wire            awvalid_o,
    input   wire            awready_i,

    // AXI Write Data Channel Interface
    output  wire    [3:0]       wid_o,
    output  wire    [31:0]      wdata_o,
    output  wire    [3:0]       wstrb_o,
    output  wire                wlast_o,
    output  wire                wvalid_o,
    input   wire                wready_i,

    // AXI Write Response Channel Interface
    input   wire    [3:0]       bid_i,
    input   wire    [1:0]       bresp_i,
    input   wire                bvalid_i,
    output  wire                bready_o,

    // Command Interface from Descriptor Unit
    input   wire                start_i,
    input   wire    [47:0]      cmd_i, // {destination_address(32), byte_count(16)}
    output  wire                done_o, // indicates idle state

    // Data Buffer Read Interface
    input   wire                fifo_empty_i,
    input   wire    [31:0]     fifo_rdata_i, // 4-byte data words
    output  wire                fifo_rden_o
);

// Optimized state encoding
localparam                      IDLE        = 2'b00,
                                ADDR_REQ    = 2'b01,
                                DATA_TX     = 2'b10,
                                RESP_WAIT   = 2'b11;

// State and control registers
reg [1:0]                       state;
reg [15:0]                      remain_bytes;
reg [3:0]                       burst_cnt;
reg [31:0]                      dst_addr;

// Optimized handshake detection
wire                            aw_handshake = awvalid_o & awready_i;
wire                            w_handshake  = wvalid_o & wready_i;
wire                            b_handshake  = bvalid_i & bready_o;

// Burst control signals
wire                            is_last_beat = (burst_cnt == 4'd0);
wire                            burst_done   = w_handshake & is_last_beat;

// Burst length calculation - optimized
wire [3:0]                      calc_awlen = (remain_bytes >= 16'd64) ? 4'hF : (remain_bytes[5:2] - 4'h1);

// Data availability check
wire                            data_available = ~fifo_empty_i;

// Sequential state machine
always_ff @(posedge clk) begin
    if(!rst_n) begin
        state        <= IDLE;
        dst_addr     <= 32'd0;
        remain_bytes <= 16'd0;
        burst_cnt    <= 4'd0;
    end else begin
        case(state)
            IDLE: begin
                if(start_i) begin
                    state        <= ADDR_REQ;
                    dst_addr     <= cmd_i[47:16];
                    remain_bytes <= cmd_i[15:0];
                end
            end
            
            ADDR_REQ: begin
                if(aw_handshake) begin
                    state     <= DATA_TX;
                    dst_addr  <= dst_addr + 32'd64;
                    burst_cnt <= calc_awlen;
                    remain_bytes <= (remain_bytes >= 16'd64) ? remain_bytes - 16'd64 : 16'd0;
                end
            end
            
            DATA_TX: begin
                if(w_handshake) begin
                    burst_cnt <= burst_cnt - 1;
                    
                    if(burst_done) begin
                        state <= b_handshake ? 
                                 ((remain_bytes == 16'd0) ? IDLE : ADDR_REQ) : RESP_WAIT;
                    end
                end
            end
            
            RESP_WAIT: begin
                if(b_handshake) begin
                    state <= (remain_bytes == 16'd0) ? IDLE : ADDR_REQ;
                end
            end
        endcase
    end
end

// Optimized output assignments
assign done_o    = (state == IDLE);
assign awvalid_o = (state == ADDR_REQ);
assign wvalid_o  = (state == DATA_TX) & data_available;
assign wlast_o   = (state == DATA_TX) & is_last_beat;
assign bready_o  = (state == DATA_TX) | (state == RESP_WAIT);
assign fifo_rden_o = w_handshake;

// AXI Address Channel
assign awaddr_o  = dst_addr;
assign awlen_o   = calc_awlen;
assign awsize_o  = 3'b010;     // 4 bytes
assign awburst_o = 2'b01;      // INCR

// AXI Write Data Channel - direct connections for timing
assign wdata_o   = fifo_rdata_i;
assign wstrb_o   = 4'b1111;    // All bytes valid

endmodule
