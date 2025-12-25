`timescale 1ns/1ps

module tb_cache_system;
    reg clk;
    reg read_en;
    reg write_en;
    reg [15:0] addr;
    reg [31:0] write_data;
    wire [31:0] read_data;
    wire hit;

    CacheController DUT (
        .clk(clk),
        .read_en(read_en),
        .write_en(write_en),
        .addr(addr),
        .write_data(write_data),
        .read_data(read_data),
        .hit(hit)
    );

    always #5 clk = ~clk;

    task write_mem(input [15:0] a, input [31:0] d);
    begin
        @(negedge clk);
        addr = a;
        write_data = d;
        write_en = 1;
        read_en = 0;
        @(negedge clk);
        write_en = 0;
        wait(DUT.state == 2'b11);
        @(negedge clk);
    end
    endtask

    task read_mem(input [15:0] a);
    begin
        @(negedge clk);
        addr = a;
        read_en = 1;
        write_en = 0;
        @(negedge clk);
        read_en = 0;
        wait(DUT.state == 2'b11);
        @(negedge clk);
    end
    endtask

    initial begin
        clk = 0;
        read_en = 0;
        write_en = 0;
        addr = 0;
        write_data = 0;

        write_mem(16'h0010, 32'hAAAA_BBBB); //Write MISS
        read_mem(16'h0010);  //Read HIT
	write_mem(16'h0010, 32'hCCCC_DDDD);//Write HIT
        read_mem(16'h0110);  //Read MISS
	//LRU check
        write_mem(16'h0210, 32'h1111_2222);
        write_mem(16'h0310, 32'h3333_4444);
        write_mem(16'h0410, 32'h5555_6666);
        read_mem(16'h0010);

        #100 $finish;
    end
endmodule
