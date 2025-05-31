module SGDMAC_DESCRIPTOR_FETCHER
(
    input   wire            clk,
    input   wire            rst_n,

    input   wire    [31:0]  pointer_i,
    input   wire            start_i,
    output  wire            done_o,

    output  wire    [31:0]      araddr_o,
    output  wire    [3:0]       arlen_o,
    output  wire    [2:0]       arsize_o,
    output  wire    [1:0]       arburst_o,
    output  wire                arvalid_o,
    input   wire                arready_i,

    input   wire    [31:0]      rdata_i,
    input   wire    [1:0]       rresp_i,
    input   wire                rlast_i,
    input   wire                rvalid_i,
    output  wire                rready_o,

    output  wire                wren_o,
    output  wire    [47:0]      wdata_o,
    output  wire                rw_o
);

localparam                  IDLE        = 2'b00,
                            READ_REQ    = 2'b01,
                            READ_DATA   = 2'b10;

reg [1:0]                   state;
reg [1:0]                   word_cnt;
reg [31:0]                  desc_ptr;
reg [31:0]                  init_ptr;
reg [31:0]                  desc_words[4];

wire                        addr_handshake = arvalid_o & arready_i;
wire                        data_handshake = rvalid_i & rready_o;
wire                        last_word      = data_handshake & rlast_i;
wire                        loop_detected  = (rdata_i == init_ptr);

always_ff @(posedge clk) begin
    if(!rst_n) begin
        state       <= IDLE;
        word_cnt    <= 2'd0;
        desc_ptr    <= 32'd0;
        init_ptr    <= 32'd0;
    end else begin
        case(state)
            IDLE: begin
                if(start_i) begin
                    state    <= READ_REQ;
                    desc_ptr <= pointer_i;
                    init_ptr <= pointer_i;
                end
            end
            
            READ_REQ: begin
                if(addr_handshake) begin
                    state    <= READ_DATA;
                    word_cnt <= 2'd3;
                end
            end
            
            READ_DATA: begin
                if(data_handshake) begin
                    desc_words[word_cnt] <= rdata_i;
                    word_cnt <= word_cnt - 1;
                    
                    if(last_word) begin
                        desc_ptr <= rdata_i;
                        state <= loop_detected ? IDLE : READ_REQ;
                    end
                end
            end
        endcase
    end
end

assign done_o    = (state == IDLE);
assign arvalid_o = (state == READ_REQ);
assign rready_o  = (state == READ_DATA);
assign wren_o    = last_word;

assign araddr_o  = desc_ptr;
assign arlen_o   = 4'd3;
assign arsize_o  = 3'b010;
assign arburst_o = 2'b01;

assign wdata_o = {desc_words[3], desc_words[2][15:0]};
assign rw_o    = desc_words[1][0];

endmodule