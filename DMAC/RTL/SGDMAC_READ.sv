module SGDMAC_READ #(
    parameter               FIFO_DEPTH = 64
)
(
    input   wire            clk,
    input   wire            rst_n,

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

    // DEMUX interface
    input   wire                start_i,
    input   wire                desc_done_i,
    input   wire    [47:0]      cmd_i,  //{address(32), len(16)}
    output  wire                done_o, // idle

    // FIFO Write interface
    input   wire                fifo_afull_i,
    input   wire    [$clog2(FIFO_DEPTH):0] fifo_cnt_i,
    output  wire                fifo_wren_o,
    output  wire    [31:0]      fifo_wdata_o //4byte
);
localparam          S_IDLE  =   2'd0,
                    S_RREQ  =   2'd1,
                    S_RDATA =   2'd2;

reg [2:0]           state, state_n;
reg [31:0]          src_addr, src_addr_n;
reg [15:0]          cnt, cnt_n;

reg                 arvalid, rready, done, fifo_wren;

always_ff @(posedge clk)begin
    if(!rst_n)begin
        state       <=  S_IDLE;
        src_addr    <=  32'd0;
        cnt         <=  16'd0;
    end
    else begin
        state       <=  state_n;
        src_addr    <=  src_addr_n;
        cnt         <=  cnt_n; 
    end
end 

always_comb begin
    state_n         =   state;
    src_addr_n      =   src_addr;
    cnt_n           =   cnt;
    arvalid         =   1'b0;
    rready          =   1'b0;
    done            =   1'b0;
    fifo_wren       =   1'b0;
    
    case (state)
        S_IDLE: begin
            done         =   1'b1;
            if(start_i) begin
                src_addr_n      =   cmd_i[47:16];
                cnt_n           =   cmd_i[15:0];
                state_n         =   S_RREQ;
            end 
        end 
        S_RREQ: begin
            arvalid             =   (fifo_cnt_i >= arlen_o + 1) || desc_done_i; 
                                    // no need to read additional descriptor if desc_done = 1
            if(arvalid & arready_i) begin
                state_n         =   S_RDATA;
                src_addr_n      =   src_addr + 'd64;
                cnt_n           =   (cnt < 'd64)? 'd0 : cnt - 'd64;
            end 
        end
        S_RDATA: begin
            rready               =   !fifo_afull_i; 
            if(rready && rvalid_i)begin
                fifo_wren        =   1'b1;
                if(rlast_i)begin
                    state_n     =   (cnt == 0)? S_IDLE : S_RREQ;
                end
            end
        end
        default:begin end 
    endcase
end

assign  done_o          =   done;

assign  arvalid_o       =   arvalid;
assign  araddr_o        =   src_addr;
assign  arlen_o         =   (cnt >= 'd64)?4'hF:cnt[5:2]-4'h1;
assign  arsize_o        =   3'b010; //4byte
assign  arburst_o       =   2'b01;  //inc

assign  rready_o        =   rready;

assign  fifo_wren_o     =   fifo_wren;
assign  fifo_wdata_o    =   rdata_i;
endmodule