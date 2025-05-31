module SGDMAC_READ #(
    parameter               FIFO_DEPTH = 64
)
(
    input   wire            clk,
    input   wire            rst_n,

    output  wire    [31:0]      araddr_o,
    output  wire    [3:0]       arlen_o,
    output  wire    [2:0]       arsize_o,
    output  wire    [1:0]       arburst_o,
    output  wire                arvalid_o,
    input   wire                arready_i,

    input   wire    [31:0]      rdata_i,
    input   wire                rlast_i,
    input   wire                rvalid_i,
    output  wire                rready_o,

    input   wire                start_i,
    input   wire                dt_done_i,
    input   wire    [47:0]      cmd_i,
    output  wire                done_o,

    input   wire                fifo_afull_i,
    input   wire    [$clog2(FIFO_DEPTH):0] fifo_cnt_i,
    output  wire                fifo_wren_o,
    output  wire    [31:0]      fifo_wdata_o
);

localparam          IDLE        = 2'b00,
                    ADDR_REQ    = 2'b01,
                    DATA_RX     = 2'b10;

reg [1:0]           state;
reg [31:0]          src_addr;
reg [15:0]          remain_bytes;

wire                addr_handshake = arvalid_o & arready_i;
wire                data_handshake = rvalid_i & rready_o;
wire                burst_complete = data_handshake & rlast_i;
wire                sufficient_space = (fifo_cnt_i >= arlen_o + 1) | dt_done_i;
wire [3:0]          calc_arlen = (remain_bytes >= 16'd64) ? 4'hF : (remain_bytes[5:2] - 4'h1);

always_ff @(posedge clk) begin
    if(!rst_n) begin
        state        <= IDLE;
        src_addr     <= 32'd0;
        remain_bytes <= 16'd0;
    end else begin
        case(state)
            IDLE: begin
                if(start_i) begin
                    state        <= ADDR_REQ;
                    src_addr     <= cmd_i[47:16];
                    remain_bytes <= cmd_i[15:0];
                end
            end
            
            ADDR_REQ: begin
                if(sufficient_space & addr_handshake) begin
                    state        <= DATA_RX;
                    src_addr     <= src_addr + 32'd64;
                    remain_bytes <= (remain_bytes >= 16'd64) ? remain_bytes - 16'd64 : 16'd0;
                end
            end
            
            DATA_RX: begin
                if(burst_complete) begin
                    state <= (remain_bytes == 16'd0) ? IDLE : ADDR_REQ;
                end
            end
        endcase
    end
end

assign done_o         = (state == IDLE);
assign arvalid_o      = (state == ADDR_REQ) & sufficient_space;
assign rready_o       = (state == DATA_RX) & (~fifo_afull_i);
assign fifo_wren_o    = data_handshake;

assign araddr_o       = src_addr;
assign arlen_o        = calc_arlen;
assign arsize_o       = 3'b010;
assign arburst_o      = 2'b01;

assign fifo_wdata_o   = rdata_i;

endmodule