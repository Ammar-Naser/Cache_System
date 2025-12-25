`timescale 1ns/1ps

module RAM #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input clk,
    input read_en,
    input write_en,
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] write_data,
    output reg [DATA_WIDTH-1:0] read_data
);
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always @(posedge clk) begin
        if (write_en)
            mem[addr] <= write_data;
        if (read_en)
            read_data <= mem[addr];
    end
endmodule

module Cache #(
    parameter NUM_SETS   = 64,
    parameter NUM_WAYS   = 4,
    parameter TAG_WIDTH  = 10,
    parameter DATA_WIDTH = 32
)(
    input clk,
    input [TAG_WIDTH-1:0] tag_in,
    input [$clog2(NUM_SETS)-1:0] index,
    input write_en,
    input [$clog2(NUM_WAYS)-1:0] write_way,
    input [DATA_WIDTH-1:0] write_data,
    input update_lru,
    input [$clog2(NUM_WAYS)-1:0] update_way,
    output reg hit,
    output reg [$clog2(NUM_WAYS)-1:0] hit_way,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg [$clog2(NUM_WAYS)-1:0] lru_way
);
    reg valid [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [TAG_WIDTH-1:0] tag [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [DATA_WIDTH-1:0] data [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [1:0] lru [0:NUM_SETS-1][0:NUM_WAYS-1]; 

    integer i;

    always @(*) begin
        hit = 0;
        hit_way = 0;
        read_data = 0;
        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            if (valid[index][i] && tag[index][i] == tag_in) begin
                hit = 1;
                hit_way = i;
                read_data = data[index][i];
            end
        end
    end

    always @(*) begin
        lru_way = 0;
        for (i = 1; i < NUM_WAYS; i = i + 1)
            if (lru[index][i] > lru[index][lru_way])
                lru_way = i;
    end

    always @(posedge clk) begin
        if (write_en) begin
            valid[index][write_way] <= 1'b1;
            tag[index][write_way]   <= tag_in;
            data[index][write_way]  <= write_data;
        end

        if (write_en || update_lru) begin
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                if (i == (write_en ? write_way : update_way))
                    lru[index][i] <= 0;
                else if (lru[index][i] < 2'b11)
                    lru[index][i] <= lru[index][i] + 1;
            end
        end
    end
endmodule

module CacheController (
    input clk,
    input read_en,
    input write_en,
    input [15:0] addr,
    input [31:0] write_data,
    output reg [31:0] read_data,
    output reg hit
);
    reg [15:0] addr_reg;
    reg [31:0] wdata_reg;
    reg is_read, is_write;

    wire [9:0] tag   = addr_reg[15:6];
    wire [5:0] index = addr_reg[5:0];

    reg cache_we;
    reg [1:0] cache_way;
    wire cache_hit;
    wire [1:0] hit_way_out;
    wire [1:0] lru_way_out;
    wire [31:0] cache_read_data;
    reg lru_upd;
    reg [1:0] lru_upd_way;

    reg ram_rd, ram_wr;
    wire [31:0] ram_rd_data;

    wire [31:0] cache_in_data = (is_read && !cache_hit) ? ram_rd_data : wdata_reg;

    Cache cache_inst (
        .clk(clk),
        .tag_in(tag),
        .index(index),
        .write_en(cache_we),
        .write_way(cache_way),
        .write_data(cache_in_data),
        .update_lru(lru_upd),
        .update_way(lru_upd_way),
        .hit(cache_hit),
        .hit_way(hit_way_out),
        .read_data(cache_read_data),
        .lru_way(lru_way_out)
    );

    RAM ram_inst (
        .clk(clk),
        .read_en(ram_rd),
        .write_en(ram_wr),
        .addr(addr_reg),
        .write_data(wdata_reg),
        .read_data(ram_rd_data)
    );

//FSM
    parameter IDLE = 2'b00, CHECK = 2'b01, MISS = 2'b10, RESP = 2'b11;
    reg [1:0] state = IDLE;

    always @(posedge clk) begin
        cache_we <= 0;
        lru_upd  <= 0;
        ram_rd   <= 0;
        ram_wr   <= 0;
        hit      <= 0;

        case (state)
            IDLE: begin
                if (read_en || write_en) begin
                    addr_reg  <= addr;
                    wdata_reg <= write_data;
                    is_read   <= read_en;
                    is_write  <= write_en;
                    state     <= CHECK;
                end
            end
            CHECK: begin
                if (cache_hit) begin
                    hit <= 1;
                    read_data <= cache_read_data;
                    lru_upd <= 1;
                    lru_upd_way <= hit_way_out;
                    if (is_write) begin
                        cache_we <= 1;
                        cache_way <= hit_way_out;
                        ram_wr <= 1;
                    end
                    state <= RESP;
                end else begin
                    if (is_read) ram_rd <= 1;
                    if (is_write) ram_wr <= 1;
                    cache_way <= lru_way_out;  //LRU
                    state <= MISS;
                end
            end
            MISS: begin
                cache_we <= 1;
                if (is_read) read_data <= ram_rd_data;
                state <= RESP;
            end
            RESP: begin
                state <= IDLE;
            end
        endcase
    end
endmodule
