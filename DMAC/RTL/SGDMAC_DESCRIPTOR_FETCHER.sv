module SGDMAC_DESCRIPTOR_FETCHER
(
    input   wire            clk,
    input   wire            rst_n,

    // Control interface signals
    input   wire    [31:0]  start_pointer_i,
    input   wire            start_i,
    output  wire            done_o,

    // AXI Read Address Channel Interface
    output  wire    [3:0]       arid_o,
    output  wire    [31:0]      araddr_o,
    output  wire    [3:0]       arlen_o,
    output  wire    [2:0]       arsize_o,
    output  wire    [1:0]       arburst_o,
    output  wire                arvalid_o,
    input   wire                arready_i,

    // AXI Read Data Channel Interface
    input   wire    [3:0]       rid_i,
    input   wire    [31:0]      rdata_i,
    input   wire    [1:0]       rresp_i,
    input   wire                rlast_i,
    input   wire                rvalid_i,
    output  wire                rready_o,

    // Command FIFO Output Interface
    input   wire                afull_i,
    output  wire                wren_o,
    output  wire    [47:0]      wdata_o, // {memory_address(32), transfer_length(16)}
    output  wire                rw_o
);

// Optimized state encoding - reduced states
localparam                  IDLE        = 2'b00,
                            READ_REQ    = 2'b01,
                            READ_DATA   = 2'b10;

// State machine and control registers
reg [1:0]                   state;
reg [1:0]                   word_cnt;      // 2-bit counter (0-3)
reg [31:0]                  desc_ptr;
reg [31:0]                  init_ptr;     // Loop detection
reg [31:0]                  desc_words[4]; // Descriptor storage

// Optimized control signals
wire                        addr_handshake = arvalid_o & arready_i;
wire                        data_handshake = rvalid_i & rready_o;
wire                        last_word      = data_handshake & rlast_i;
wire                        loop_detected  = (rdata_i == init_ptr);

// Sequential logic - optimized for minimal logic depth
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
                    desc_ptr <= start_pointer_i;
                    init_ptr <= start_pointer_i;
                end
            end
            
            READ_REQ: begin
                if(addr_handshake) begin
                    state    <= READ_DATA;
                    word_cnt <= 2'd3;  // Start from word 3, count down
                end
            end
            
            READ_DATA: begin
                if(data_handshake) begin
                    desc_words[word_cnt] <= rdata_i;
                    word_cnt <= word_cnt - 1;
                    
                    if(last_word) begin
                        desc_ptr <= rdata_i;  // Next descriptor pointer
                        state <= loop_detected ? IDLE : READ_REQ;
                    end
                end
            end
        endcase
    end
end

// Optimized output assignments - reduced critical path
assign done_o    = (state == IDLE);
assign arvalid_o = (state == READ_REQ);
assign rready_o  = (state == READ_DATA);
assign wren_o    = last_word;

// AXI Address Channel - constants for better timing
assign araddr_o  = desc_ptr;
assign arlen_o   = 4'd3;       // Always 4 beats
assign arsize_o  = 3'b010;     // 4 bytes
assign arburst_o = 2'b01;      // INCR

// Command output - optimized multiplexing
assign wdata_o = {desc_words[3], desc_words[2][15:0]}; // {addr, len}
assign rw_o    = desc_words[1][0];

endmodule