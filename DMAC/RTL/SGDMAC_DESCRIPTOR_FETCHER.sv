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

// State machine encoding
localparam                  STATE_IDLE          =   2'd0,
                            STATE_READ_REQUEST  =   2'd1,
                            STATE_READ_DATA     =   2'd2,
                            STATE_FIFO_WRITE    =   2'd3;

// Descriptor parameters
localparam                  DESCRIPTOR_SIZE_BYTES  =   128;

// State machine and control registers
reg [1:0]                   current_state, next_state;
reg [1:0]                   data_word_counter, next_data_word_counter; 
reg [31:0]                  current_descriptor_ptr, next_descriptor_ptr;
reg [31:0]                  initial_descriptor_ptr; // Reference for loop detection
reg [31:0]                  descriptor_data[4]; // 4-word descriptor storage

// Control signal generation
reg                         address_valid, data_ready, operation_complete;
reg                         fifo_write_enable, processing_delayed;

// Sequential logic block
always_ff @(posedge clk)begin
    if(!rst_n)begin
        current_state           <=  STATE_IDLE;
        data_word_counter       <=  'd0;
        current_descriptor_ptr  <=  'd0;
    end
    else begin
        current_state           <=  next_state;
        data_word_counter       <=  next_data_word_counter;
        current_descriptor_ptr  <=  next_descriptor_ptr;
    end 
end

// Combinational logic for state machine and control
always_comb begin
    next_state                  =   current_state;
    next_descriptor_ptr         =   current_descriptor_ptr;

    address_valid               = 1'b0;
    data_ready                  = 1'b0;
    operation_complete          = 1'b0;
    
    fifo_write_enable           = 1'b0;
    next_data_word_counter      = data_word_counter;
    
    case (current_state)
        STATE_IDLE:begin
            operation_complete      = 1'b1;
            if(start_i) begin
                next_descriptor_ptr = start_pointer_i;
                initial_descriptor_ptr = start_pointer_i;
                next_state          = STATE_READ_REQUEST;
            end
        end 
        STATE_READ_REQUEST: begin
            address_valid           = 1'b1;
            if(arready_i) begin
                next_state          = STATE_READ_DATA;
                next_data_word_counter = 'd3;
            end
        end
        STATE_READ_DATA: begin
            data_ready              = 1'b1;
            if(rvalid_i) begin
                descriptor_data[data_word_counter] = rdata_i;
                next_data_word_counter = data_word_counter - 1;
                if(rlast_i)begin
                    fifo_write_enable   = 1'b1;
                    next_descriptor_ptr = rdata_i;
                    next_state = (rdata_i == initial_descriptor_ptr) ? STATE_IDLE : STATE_READ_REQUEST;
                end
            end 
        end
        default: begin 
            // Default case handling
        end
    endcase
end 

// Output signal assignments
assign done_o               =   operation_complete;

// AXI Read Address Channel outputs
assign arvalid_o            =   address_valid;
assign araddr_o             =   current_descriptor_ptr;
assign arlen_o              =   4'd3;   // 4 AXI transactions for descriptor
assign arsize_o             =   3'b010; // 4 bytes per AXI transaction
assign arburst_o            =   2'b01;  // Incremental burst mode

// AXI Read Data Channel outputs
assign rready_o             =   data_ready;

// Command FIFO interface outputs
assign wren_o               =   fifo_write_enable;
assign wdata_o              =   {descriptor_data[3], descriptor_data[2][15:0]};
assign rw_o                 =   descriptor_data[1][0];

endmodule