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

// State machine encoding
localparam                      STATE_IDLE      = 2'd0,
                                STATE_ADDR_REQ  = 2'd1,
                                STATE_DATA_TX   = 2'd2,
                                STATE_RESP_WAIT = 2'd3;

// Internal state and control registers
reg [2:0]                       engine_state, next_engine_state;
reg [15:0]                      remaining_bytes, next_remaining_bytes; 
reg [3:0]                       write_burst_counter, next_write_burst_counter;
reg [31:0]                      destination_address, next_destination_address;
reg [31:0]                      write_data_reg, next_write_data_reg;

// Control signal generation
reg                             addr_request_valid, data_write_valid, write_last_beat, engine_idle, resp_ready;
reg                             buffer_read_enable;

// Sequential state update logic
always_ff @(posedge clk)begin
    if(!rst_n) begin
        engine_state            <=  STATE_IDLE;
        destination_address     <=  32'd0;
        remaining_bytes         <=  16'd0;
        write_burst_counter     <=  4'd0;
    end
    else begin
        engine_state            <=  next_engine_state;
        destination_address     <=  next_destination_address;
        remaining_bytes         <=  next_remaining_bytes;
        write_burst_counter     <=  next_write_burst_counter;
    end 
end

// Combinational logic for state machine and control
always_comb begin
    next_engine_state           =   engine_state;
    next_destination_address    =   destination_address;
    next_remaining_bytes        =   remaining_bytes;
    next_write_burst_counter    =   write_burst_counter;

    addr_request_valid          =   1'd0;
    data_write_valid            =   1'd0;
    write_last_beat             =   1'd0;
    resp_ready                  =   1'd0;
    engine_idle                 =   1'd0;
    
    buffer_read_enable          =   1'd0;

    case (engine_state)
        STATE_IDLE: begin
            engine_idle         =   1'd1;
            if(start_i) begin
                addr_request_valid      = 1'd1;
                next_engine_state       = STATE_ADDR_REQ;
                next_destination_address = cmd_i[47:16];
                next_remaining_bytes    = cmd_i[15:0]; 
            end
        end 
        STATE_ADDR_REQ: begin
            addr_request_valid      =   1'd1;
            if(awready_i)begin
                next_engine_state       =   STATE_DATA_TX;
                next_destination_address =  destination_address + 'd64;
                next_write_burst_counter =  awlen_o;
                if(remaining_bytes >= 'd64) 
                    next_remaining_bytes =  remaining_bytes - 'd64;
                else            
                    next_remaining_bytes =  'd0;
            end 
        end
        STATE_DATA_TX: begin
            data_write_valid        =   !fifo_empty_i;
            write_last_beat         =   (write_burst_counter == 4'd0);
            if(wready_i && data_write_valid) begin
                next_write_burst_counter = write_burst_counter - 1;
                buffer_read_enable      = 1'b1;
                if(write_last_beat) begin
                    resp_ready          = 1'b1;
                    next_engine_state   = (bvalid_i) ? STATE_IDLE : STATE_RESP_WAIT;
                end
            end
        end
        STATE_RESP_WAIT: begin
            resp_ready              =   1'b1;
            if(bvalid_i) 
                next_engine_state   =   (remaining_bytes == 'd0) ? STATE_IDLE : STATE_ADDR_REQ;
        end
        default: begin 
            // Default case for unused states
        end 
    endcase
end

// AXI Write Address Channel assignments
assign  awaddr_o        =   destination_address;
assign  awlen_o         =   (remaining_bytes >= 'd64) ? 4'hF : remaining_bytes[5:2] - 4'h1;
assign  awsize_o        =   3'b010; // 32-bit transfers
assign  awburst_o       =   2'b01;  // Incremental addressing
assign  awvalid_o       =   addr_request_valid;

// AXI Write Data Channel assignments
assign  wdata_o         =   fifo_rdata_i;
assign  wstrb_o         =   4'b1111;
assign  wlast_o         =   write_last_beat;
assign  wvalid_o        =   data_write_valid;

// AXI Write Response Channel assignments
assign  bready_o        =   resp_ready;

// Control interface assignments
assign  done_o          =   engine_idle;

// Data buffer interface assignments
assign  fifo_rden_o     =   buffer_read_enable;

endmodule
