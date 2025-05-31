module SGDMAC_WRITE #(
    parameter               FIFO_DEPTH = 64
)
(
    input   wire            clk,
    input   wire            rst_n,

    // AXI [AW channel] 
    output  wire    [3:0]   awid_o,
    output  wire    [31:0]  awaddr_o,
    output  wire    [3:0]   awlen_o,
    output  wire    [2:0]   awsize_o,
    output  wire    [1:0]   awburst_o,
    output  wire            awvalid_o,
    input   wire            awready_i,

    // AXI [W channel]
    output  wire    [3:0]       wid_o,
    output  wire    [31:0]      wdata_o,
    output  wire    [3:0]       wstrb_o,
    output  wire                wlast_o,
    output  wire                wvalid_o,
    input   wire                wready_i,

    // AXI [B channel]
    input   wire    [3:0]       bid_i,
    input   wire    [1:0]       bresp_i,
    input   wire                bvalid_i,
    output  wire                bready_o,

    // DEMUX interface
    input   wire                start_i,
    input   wire    [47:0]      cmd_i, //{address(32), len(16)}
    output  wire                done_o, // idle

    // DATA FIFO
    input   wire                fifo_empty_i,
    input   wire    [31:0]     fifo_rdata_i, //4bytes
    output  wire                fifo_rden_o
);

localparam                      S_IDLE  = 2'd0,
                                S_WREQ  = 2'd1,
                                S_WDATA = 2'd2,
                                S_WAIT  = 2'd3;

reg [2:0]                       state, state_n;
reg [15:0]                      cnt, cnt_n; // total data len
reg [3:0]                       wcnt, wcnt_n;
reg [31:0]                      dst_addr, dst_addr_n;
reg [31:0]                      wdata, wdata_n;

reg                             awvalid, wvalid, wlast, done, bready;
reg                             fifo_rden;

always_ff @(posedge clk)begin
    if(!rst_n) begin
        state           <=  S_IDLE;
        dst_addr        <=  32'd0;
        cnt             <=  16'd0;
        wcnt            <=  4'd0;
    end
    else begin
        state           <=  state_n;
        dst_addr        <=  dst_addr_n;
        cnt             <=  cnt_n;
        wcnt            <=  wcnt_n;
    end 
end

always_comb begin
    state_n             =   state;
    dst_addr_n          =   dst_addr;
    cnt_n               =   cnt;
    wcnt_n              =   wcnt;

    awvalid             =   1'd0;
    wvalid              =   1'd0;
    wlast               =   1'd0;
    bready             =   1'd0;
    done                =   1'd0;
    
    fifo_rden           =   1'd0;

    case (state)
        S_IDLE: begin
            done        =   1'd1;
            if(start_i) begin
                awvalid = 1'd1;
                state_n         =   S_WREQ;
                dst_addr_n  =   cmd_i[47:16];
                cnt_n       =   cmd_i[15:0]; 
            end
        end 
        S_WREQ: begin
            awvalid         =   1'd1;
            if(awready_i)begin
                state_n     =   S_WDATA;
                dst_addr_n  =   dst_addr + 'd64;
                wcnt_n      =   awlen_o;
                if(cnt >= 'd64) cnt_n   =   cnt - 'd64;
                else            cnt_n   =   'd0;
            end 
        end
        S_WDATA: begin
            wvalid          =   !fifo_empty_i;
            wlast           =   (wcnt == 4'd0);
            if(wready_i && wvalid) begin
                wcnt_n      =   wcnt - 1;
                fifo_rden   =   1'b1;
                if(wlast) begin
                    bready =   1'b1;
                    state_n =   (bvalid_i)?S_IDLE:S_WAIT;
                end
            end
        end
        S_WAIT: begin
            bready         =   1'b1;
            if(bvalid_i) 
                state_n     =   (cnt == 'd0)?S_IDLE:S_WREQ;
        end
        default: begin end 
    endcase
end
// TODO: try modify b channel behavior
assign  awaddr_o        =   dst_addr;
assign  awlen_o         =   (cnt >= 'd64)? 4'hF:cnt[5:2]-4'h1;
assign  awsize_o        =   3'b010; //32bit per transfer
assign  awburst_o       =   2'b01; //inc
assign  awvalid_o       =   awvalid;

assign  wdata_o         =   fifo_rdata_i;
assign  wstrb_o         =   4'b1111;
assign  wlast_o         =   wlast;
assign  wvalid_o        =   wvalid;

assign  bready_o        =   bready;

assign  done_o          =   done;

assign  fifo_rden_o     =   fifo_rden;

endmodule
