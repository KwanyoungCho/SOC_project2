module SGDMAC_READ #(
    parameter               FIFO_DEPTH = 64
)
(
    input   wire            clk,
    input   wire            rst_n,

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

    // Command Interface from Descriptor Unit
    input   wire                start_i,
    input   wire                desc_done_i,
    input   wire    [47:0]      cmd_i,  // {source_address(32), byte_count(16)}
    output  wire                done_o, // indicates idle state

    // Data Buffer Write Interface
    input   wire                fifo_afull_i,
    input   wire    [$clog2(FIFO_DEPTH):0] fifo_cnt_i,
    output  wire                fifo_wren_o,
    output  wire    [31:0]      fifo_wdata_o // 4-byte data words
);

// State machine encoding
localparam          STATE_IDLE      =   2'd0,
                    STATE_ADDR_REQ  =   2'd1,
                    STATE_DATA_RX   =   2'd2;

// Internal state and control registers
reg [2:0]           engine_state, next_engine_state;
reg [31:0]          memory_address, next_memory_address;
reg [15:0]          remaining_bytes, next_remaining_bytes;

// Control signal generation
reg                 addr_request_valid, data_response_ready, engine_idle, buffer_write_enable;

// Sequential state update logic
always_ff @(posedge clk)begin
    if(!rst_n)begin
        engine_state    <=  STATE_IDLE;
        memory_address  <=  32'd0;
        remaining_bytes <=  16'd0;
    end
    else begin
        engine_state        <=  next_engine_state;
        memory_address      <=  next_memory_address;
        remaining_bytes     <=  next_remaining_bytes; 
    end
end 

// Combinational logic for state machine and control
always_comb begin
    next_engine_state           =   engine_state;
    next_memory_address         =   memory_address;
    next_remaining_bytes        =   remaining_bytes;
    
    addr_request_valid          =   1'b0;
    data_response_ready         =   1'b0;
    engine_idle                 =   1'b0;
    buffer_write_enable         =   1'b0;
    
    case (engine_state)
        STATE_IDLE: begin
            engine_idle             =   1'b1;
            if(start_i) begin
                next_memory_address     =   cmd_i[47:16];
                next_remaining_bytes    =   cmd_i[15:0];
                next_engine_state       =   STATE_ADDR_REQ;
            end 
        end 
        STATE_ADDR_REQ: begin
            addr_request_valid      =   (fifo_cnt_i >= arlen_o + 1) || desc_done_i; 
                                        // Allow reads when buffer has space or descriptor processing complete
            if(addr_request_valid & arready_i) begin
                next_engine_state       =   STATE_DATA_RX;
                next_memory_address     =   memory_address + 'd64;
                next_remaining_bytes    =   (remaining_bytes < 'd64) ? 'd0 : remaining_bytes - 'd64;
            end 
        end
        STATE_DATA_RX: begin
            data_response_ready     =   !fifo_afull_i; 
            if(data_response_ready && rvalid_i)begin
                buffer_write_enable     =   1'b1;
                if(rlast_i)begin
                    next_engine_state   =   (remaining_bytes == 0) ? STATE_IDLE : STATE_ADDR_REQ;
                end
            end
        end
        default:begin 
            // Default case for unused states
        end 
    endcase
end

// Output interface assignments
assign  done_o          =   engine_idle;

// AXI Read Address Channel assignments
assign  arvalid_o       =   addr_request_valid;
assign  araddr_o        =   memory_address;
assign  arlen_o         =   (remaining_bytes >= 'd64) ? 4'hF : remaining_bytes[5:2] - 4'h1;
assign  arsize_o        =   3'b010; // 4-byte transfers
assign  arburst_o       =   2'b01;  // Incremental addressing

// AXI Read Data Channel assignments
assign  rready_o        =   data_response_ready;

// Data buffer interface assignments
assign  fifo_wren_o     =   buffer_write_enable;
assign  fifo_wdata_o    =   rdata_i;

endmodule