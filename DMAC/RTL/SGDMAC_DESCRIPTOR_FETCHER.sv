module SGDMAC_DESCRIPTOR_FETCHER
(
    input   wire            clk,
    input   wire            rst_n,

    //config
    input   wire    [31:0]  start_pointer_i,
    input   wire            start_i,
    output  wire            done_o,

    // AXI [AR channel]
    output  wire    [3:0]       arid_o,
    output  wire    [31:0]      araddr_o,
    output  wire    [3:0]       arlen_o,
    output  wire    [2:0]       arsize_o,
    output  wire    [1:0]       arburst_o,
    output  wire                arvalid_o,
    input   wire                arready_i,

    // AXI [R channel]
    input   wire    [3:0]       rid_i,
    input   wire    [31:0]      rdata_i,
    input   wire    [1:0]       rresp_i,
    input   wire                rlast_i,
    input   wire                rvalid_i,
    output  wire                rready_o,

    // FIFO Write interface
    input   wire                afull_i,
    output  wire                wren_o,
    output  wire    [47:0]      wdata_o, // {address(32), length(16)}
    output  wire                rw_o
);

localparam                  S_IDLE      =   2'd0,
                            S_RREQ      =   2'd1,
                            S_RDATA     =   2'd2,
                            S_FIFO      =   2'd3;
localparam                  DESCRIPTOR_LEN  =   128;

reg [1:0]                   cnt, cnt_n; // 3 ~ 0
reg [1:0]                   state, state_n;
reg [31:0]                  start_pointer, start_pointer_n;
reg [31:0]                  init_ptr; // to detect end descriptor
reg [31:0]                  rdata[4]; // store when fifo is full
reg                         arvalid, rready, done;
reg                         fifo_wren, delayed;

always_ff @(posedge clk)begin
    if(!rst_n)begin
        state           <=  S_IDLE;
        cnt             <=  'd0;
        start_pointer   <=  'd0;
    end
    else begin
        state           <=  state_n;
        cnt             <=  cnt_n;
        start_pointer   <=  start_pointer_n;
    end 
end

always_comb begin
    state_n             =   state;

    start_pointer_n     =   start_pointer;

    arvalid                 = 1'b0;
    rready                  = 1'b0;
    done                    = 1'b0;
    
    fifo_wren               = 1'b0;
    cnt_n                   = cnt;
    
    case (state)
        S_IDLE:begin
            done            = 1'b1;
            if(start_i) begin
                start_pointer_n = start_pointer_i;
                init_ptr        = start_pointer_i;
                state_n         = S_RREQ;
            end
        end 
        S_RREQ: begin
            arvalid         = 1'b1;
            if(arready_i) begin
                state_n     =   S_RDATA;
                cnt_n           = 'd3;
            end
        end
        S_RDATA: begin
            rready          = 1'b1;
            if(rvalid_i) begin
                rdata[cnt]          = rdata_i;
                cnt_n               = cnt - 1;
               // $display("rdata[cnt]: %x, cnt: %d\n", rdata[cnt], cnt_n);
                if(rlast_i)begin// not last
                    fifo_wren       = 1'b1;
                    start_pointer_n = rdata_i;
                    state_n         = (rdata_i == init_ptr)? S_IDLE : S_RREQ;
                end
            end 
        end
        default: begin end
    endcase
end 

assign done_o               =   done;

assign arvalid_o            =   arvalid;
assign araddr_o             =   start_pointer;
assign arlen_o              =   4'd3;   // 4 times
assign arsize_o             =   3'b010; // 4bytes per transfer
assign arburst_o            =   2'b01; //incremental

assign rready_o             =   rready;

assign wren_o               =   fifo_wren;
assign wdata_o              =   {rdata[3], rdata[2][15:0]};
assign rw_o                 =   rdata[1][0];
endmodule