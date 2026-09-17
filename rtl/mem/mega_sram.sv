// =============================================================================
// Mega SRAM (Scratchpad Memory Subsystem)
// 2MB Total Capacity, partitioned for Weights, Activations, and Outputs.
// Supports 512-bit wide memory accesses for 64x64 systolic array.
// =============================================================================
`default_nettype none

module mega_sram #(
    parameter int DATA_W = 512,
    parameter int WGT_DEPTH = 16384, // 1MB for weights
    parameter int ACT_DEPTH = 8192,  // 512KB for activations
    parameter int OUT_DEPTH = 8192,  // 512KB for outputs
    parameter int ADDR_W = 16        // Global address width
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- Weight Memory Interface ----
    input  wire                 wgt_rd_en,
    input  wire [ADDR_W-1:0]    wgt_rd_addr,
    output logic [DATA_W-1:0]   wgt_rd_data,
    output logic                wgt_rd_valid,

    input  wire                 wgt_wr_en,
    input  wire [ADDR_W-1:0]    wgt_wr_addr,
    input  wire [DATA_W-1:0]    wgt_wr_data,

    // ---- Activation Memory Interface ----
    input  wire                 act_rd_en,
    input  wire [ADDR_W-1:0]    act_rd_addr,
    output logic [DATA_W-1:0]   act_rd_data,
    output logic                act_rd_valid,

    input  wire                 act_wr_en,
    input  wire [ADDR_W-1:0]    act_wr_addr,
    input  wire [DATA_W-1:0]    act_wr_data,

    // ---- Output Memory Interface ----
    input  wire                 out_rd_en,
    input  wire [ADDR_W-1:0]    out_rd_addr,
    output logic [DATA_W-1:0]   out_rd_data,
    output logic                out_rd_valid,

    input  wire                 out_wr_en,
    input  wire [ADDR_W-1:0]    out_wr_addr,
    input  wire [DATA_W-1:0]    out_wr_data
);

    // =========================================================================
    // Weight SRAM (1MB) - 16384 x 512-bit
    // =========================================================================
    banked_sram #(
        .NUM_BANKS(2),
        .BANK_DEPTH(WGT_DEPTH/2),
        .DATA_W(DATA_W),
        .PINGPONG(1)
    ) u_wgt_sram (
        .clk             (clk),
        .rst_n           (rst_n),
        .rd_en           (wgt_rd_en),
        .rd_bank_sel     (wgt_rd_addr[$clog2(WGT_DEPTH/2)]), // simplistic bank mapping
        .rd_addr         (wgt_rd_addr[$clog2(WGT_DEPTH/2)-1:0]),
        .rd_pingpong_sel (1'b0),
        .rd_data         (wgt_rd_data),
        .rd_valid        (wgt_rd_valid),

        .wr_en           (wgt_wr_en),
        .wr_bank_sel     (wgt_wr_addr[$clog2(WGT_DEPTH/2)]),
        .wr_addr         (wgt_wr_addr[$clog2(WGT_DEPTH/2)-1:0]),
        .wr_pingpong_sel (1'b0),
        .wr_data         (wgt_wr_data)
    );

    // =========================================================================
    // Activation SRAM (512KB) - 8192 x 512-bit
    // =========================================================================
    banked_sram #(
        .NUM_BANKS(2),
        .BANK_DEPTH(ACT_DEPTH/2),
        .DATA_W(DATA_W),
        .PINGPONG(1)
    ) u_act_sram (
        .clk             (clk),
        .rst_n           (rst_n),
        .rd_en           (act_rd_en),
        .rd_bank_sel     (act_rd_addr[$clog2(ACT_DEPTH/2)]),
        .rd_addr         (act_rd_addr[$clog2(ACT_DEPTH/2)-1:0]),
        .rd_pingpong_sel (1'b0),
        .rd_data         (act_rd_data),
        .rd_valid        (act_rd_valid),

        .wr_en           (act_wr_en),
        .wr_bank_sel     (act_wr_addr[$clog2(ACT_DEPTH/2)]),
        .wr_addr         (act_wr_addr[$clog2(ACT_DEPTH/2)-1:0]),
        .wr_pingpong_sel (1'b0),
        .wr_data         (act_wr_data)
    );

    // =========================================================================
    // Output SRAM (512KB) - 8192 x 512-bit
    // =========================================================================
    banked_sram #(
        .NUM_BANKS(2),
        .BANK_DEPTH(OUT_DEPTH/2),
        .DATA_W(DATA_W),
        .PINGPONG(1)
    ) u_out_sram (
        .clk             (clk),
        .rst_n           (rst_n),
        .rd_en           (out_rd_en),
        .rd_bank_sel     (out_rd_addr[$clog2(OUT_DEPTH/2)]),
        .rd_addr         (out_rd_addr[$clog2(OUT_DEPTH/2)-1:0]),
        .rd_pingpong_sel (1'b0),
        .rd_data         (out_rd_data),
        .rd_valid        (out_rd_valid),

        .wr_en           (out_wr_en),
        .wr_bank_sel     (out_wr_addr[$clog2(OUT_DEPTH/2)]),
        .wr_addr         (out_wr_addr[$clog2(OUT_DEPTH/2)-1:0]),
        .wr_pingpong_sel (1'b0),
        .wr_data         (out_wr_data)
    );

endmodule

`default_nettype wire
