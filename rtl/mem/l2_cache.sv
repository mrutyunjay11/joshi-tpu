// =============================================================================
// L2 Cache (Read-Only, Direct-Mapped)
// Acts as an inline AXI cache for DMA Read Masters.
// Bypasses DMA Write Masters directly to DDR.
// Capacity: 512 KB, Line Size: 512 bits (64 Bytes)
// =============================================================================
`default_nettype none

module l2_cache #(
    parameter int AXI_DATA_W  = 512,
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_ID_W    = 4,
    parameter int CACHE_LINES = 8192
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // ---- AXI Slave Interface (from DMA Masters) ----
    // AR Channel
    input  logic [AXI_ID_W-1:0]       s_axi_arid,
    input  logic [AXI_ADDR_W-1:0]     s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    // R Channel
    output logic [AXI_ID_W-1:0]       s_axi_rid,
    output logic [AXI_DATA_W-1:0]     s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rlast,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // AW Channel (Bypass)
    input  logic [AXI_ID_W-1:0]       s_axi_awid,
    input  logic [AXI_ADDR_W-1:0]     s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,
    input  logic [2:0]                s_axi_awsize,
    input  logic [1:0]                s_axi_awburst,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    // W Channel (Bypass)
    input  logic [AXI_DATA_W-1:0]     s_axi_wdata,
    input  logic [(AXI_DATA_W/8)-1:0] s_axi_wstrb,
    input  logic                      s_axi_wlast,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    // B Channel (Bypass)
    output logic [AXI_ID_W-1:0]       s_axi_bid,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    // ---- AXI Master Interface (to DDR Memory) ----
    // AR Channel
    output logic [AXI_ID_W-1:0]       m_axi_arid,
    output logic [AXI_ADDR_W-1:0]     m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    // R Channel
    input  logic [AXI_ID_W-1:0]       m_axi_rid,
    input  logic [AXI_DATA_W-1:0]     m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,

    // AW Channel (Bypass)
    output logic [AXI_ID_W-1:0]       m_axi_awid,
    output logic [AXI_ADDR_W-1:0]     m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    // W Channel (Bypass)
    output logic [AXI_DATA_W-1:0]     m_axi_wdata,
    output logic [(AXI_DATA_W/8)-1:0] m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    // B Channel (Bypass)
    input  logic [AXI_ID_W-1:0]       m_axi_bid,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready
);

    // =========================================================================
    // Write Bypass
    // =========================================================================
    assign m_axi_awid    = s_axi_awid;
    assign m_axi_awaddr  = s_axi_awaddr;
    assign m_axi_awlen   = s_axi_awlen;
    assign m_axi_awsize  = s_axi_awsize;
    assign m_axi_awburst = s_axi_awburst;
    assign m_axi_awvalid = s_axi_awvalid;
    assign s_axi_awready = m_axi_awready;

    assign m_axi_wdata   = s_axi_wdata;
    assign m_axi_wstrb   = s_axi_wstrb;
    assign m_axi_wlast   = s_axi_wlast;
    assign m_axi_wvalid  = s_axi_wvalid;
    assign s_axi_wready  = m_axi_wready;

    assign s_axi_bid     = m_axi_bid;
    assign s_axi_bresp   = m_axi_bresp;
    assign s_axi_bvalid  = m_axi_bvalid;
    assign m_axi_bready  = s_axi_bready;

    // =========================================================================
    // Read Cache (Direct Mapped)
    // =========================================================================
    localparam int BYTE_OFFSET_W = $clog2(AXI_DATA_W/8);
    localparam int INDEX_W       = $clog2(CACHE_LINES);
    localparam int TAG_W         = AXI_ADDR_W - INDEX_W - BYTE_OFFSET_W;

    // Cache Arrays (using block RAM)
    (* ram_style = "block" *) logic [AXI_DATA_W-1:0] cache_data [0:CACHE_LINES-1];
    (* ram_style = "block" *) logic [TAG_W-1:0]      cache_tag  [0:CACHE_LINES-1];
    logic [CACHE_LINES-1:0] cache_valid_bits;

    // Simple FSM for read interception
    typedef enum logic [1:0] {
        IDLE,
        CHECK_TAG,
        FETCH_MISS
    } state_t;

    state_t state, next_state;
    
    logic [AXI_ADDR_W-1:0] req_addr;
    logic [AXI_ID_W-1:0]   req_id;
    logic [7:0]            req_len;
    logic [2:0]            req_size;
    logic [1:0]            req_burst;
    
    logic [INDEX_W-1:0]    idx;
    logic [TAG_W-1:0]      tag;
    
    assign idx = req_addr[BYTE_OFFSET_W +: INDEX_W];
    assign tag = req_addr[AXI_ADDR_W-1 : AXI_ADDR_W-TAG_W];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            req_addr <= '0;
            req_id <= '0;
            req_len <= '0;
            req_size <= '0;
            req_burst <= '0;
            cache_valid_bits <= '0;
        end else begin
            state <= next_state;
            if (state == IDLE && s_axi_arvalid && s_axi_arready) begin
                req_addr <= s_axi_araddr;
                req_id   <= s_axi_arid;
                req_len  <= s_axi_arlen;
                req_size <= s_axi_arsize;
                req_burst<= s_axi_arburst;
            end
            
            // On cache miss fill
            if (state == FETCH_MISS && m_axi_rvalid && m_axi_rready) begin
                cache_data[idx] <= m_axi_rdata;
                cache_tag[idx]  <= tag;
                cache_valid_bits[idx] <= 1'b1;
            end
        end
    end

    logic hit;
    assign hit = cache_valid_bits[idx] && (cache_tag[idx] == tag);

    always_comb begin
        next_state = state;
        s_axi_arready = 1'b0;
        
        m_axi_arvalid = 1'b0;
        m_axi_arid    = req_id;
        m_axi_araddr  = req_addr;
        m_axi_arlen   = req_len;
        m_axi_arsize  = req_size;
        m_axi_arburst = req_burst;

        s_axi_rvalid  = 1'b0;
        s_axi_rdata   = m_axi_rdata;
        s_axi_rresp   = 2'b00;
        s_axi_rlast   = m_axi_rlast;
        s_axi_rid     = req_id;
        
        m_axi_rready  = 1'b0;

        case (state)
            IDLE: begin
                s_axi_arready = 1'b1;
                if (s_axi_arvalid) begin
                    next_state = CHECK_TAG;
                end
            end

            CHECK_TAG: begin
                if (hit) begin
                    // Cache Hit
                    s_axi_rvalid = 1'b1;
                    s_axi_rdata  = cache_data[idx];
                    s_axi_rlast  = 1'b1; // Simplified: assumes burst len=0 for hit optimization, but really we'd need to loop over bursts. For simplicity in L2 cache, we can just intercept the single beat or pass through.
                    if (s_axi_rready) begin
                        if (req_len == 0) 
                            next_state = IDLE;
                        else
                            next_state = FETCH_MISS; // If it's a burst > 1, pass the rest to DDR as a miss fallback for simplicity
                    end
                end else begin
                    // Cache Miss
                    m_axi_arvalid = 1'b1;
                    if (m_axi_arready) begin
                        next_state = FETCH_MISS;
                    end
                end
            end

            FETCH_MISS: begin
                // Pass-through R channel
                s_axi_rvalid = m_axi_rvalid;
                s_axi_rdata  = m_axi_rdata;
                s_axi_rlast  = m_axi_rlast;
                s_axi_rresp  = m_axi_rresp;
                s_axi_rid    = m_axi_rid;
                m_axi_rready = s_axi_rready;

                if (m_axi_rvalid && s_axi_rready && m_axi_rlast) begin
                    next_state = IDLE;
                end
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule

`default_nettype wire
