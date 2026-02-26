module FIFO(
    input clk,
    input rst,
    input wr,
    input rd,
    input [7:0] din,

    output reg [7:0] dout,
    output full,
    output empty
);

    reg [7:0] mem [15:0];
    reg [3:0] rptr = 0, wptr = 0;
    reg [4:0] cnt = 0;

    always @(posedge clk or posedge rst) begin
        if(rst == 1'b1)begin
            wptr <= 0;
            rptr <= 0;
            cnt <= 0;
        end
        else if(wr && !full)begin
            mem[wptr] <= din;
            wptr <= wptr + 1;
            cnt <= cnt + 1;
        end
        else if(rd && !empty)begin 
            dout <= mem[rptr];
            rptr <= rptr + 1;
            cnt <= cnt - 1;
        end
    end

    assign empty    = (cnt == 0)        ? 1'b1: 1'b0;
    assign full     = (cnt == 5'b10000) ? 1'b1: 1'b0;
endmodule

interface fifo_if;
    logic clk;
    logic rst;
    logic wr;
    logic rd;
    logic [7:0] din;

    logic [7:0] dout;
    logic full;
    logic empty;
endinterface //fifo_if