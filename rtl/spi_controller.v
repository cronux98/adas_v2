// ============================================================================
// spi_controller.v — SPI Master Controller (8-bit frames, configurable clock div)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    SPI Master for LIDAR sensor interface
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Register Map (base 0x0000_2000):
//   0x00 SPI_CTRL         RW   Control register
//   0x04 SPI_STATUS       RO   Status + FIFO levels
//   0x08 SPI_CLKDIV       RW   Clock divider
//   0x0C SPI_TXDATA       WO   TX FIFO write data
//   0x10 SPI_RXDATA       RO   RX FIFO read data
//   0x14 SPI_CS           RW   Chip select mask
//   0x18 SPI_INTR_MASK    RW   Interrupt mask
//   0x1C SPI_INTR_STATUS  RO   Interrupt status (W1C)
// ============================================================================

`timescale 1ns / 1ps

module spi_controller (
    input  wire        clk_i,
    input  wire        rst_n_i,

    // AXI4-Lite Slave
    input  wire [31:0] s_axi_awaddr_i,
    input  wire        s_axi_awvalid_i,
    output wire        s_axi_awready_o,
    input  wire [31:0] s_axi_wdata_i,
    input  wire [3:0]  s_axi_wstrb_i,
    input  wire        s_axi_wvalid_i,
    output wire        s_axi_wready_o,
    output wire [1:0]  s_axi_bresp_o,
    output wire        s_axi_bvalid_o,
    input  wire        s_axi_bready_i,
    input  wire [31:0] s_axi_araddr_i,
    input  wire        s_axi_arvalid_i,
    output wire        s_axi_arready_o,
    output wire [31:0] s_axi_rdata_o,
    output wire [1:0]  s_axi_rresp_o,
    output wire        s_axi_rvalid_o,
    input  wire        s_axi_rready_i,

    // SPI external interface
    output wire        sck_o,
    output wire        mosi_o,
    input  wire        miso_i,
    output wire [3:0]  cs_n_o,

    // Interrupts / fault
    output wire        irq_rx_o,
    output wire        irq_tx_o,
    output wire        irq_err_o,
    output wire        fault_o
);

    localparam AXI_OKAY   = 2'b00;
    localparam AXI_SLVERR = 2'b10;
    localparam FIFO_DEPTH = 8;

    // ——— Registers ———
    reg [31:0] reg_ctrl;          // 0x00
    reg [31:0] reg_clkdiv;        // 0x08
    reg [31:0] reg_cs;            // 0x14
    reg [31:0] reg_intr_mask;     // 0x18
    reg [31:0] reg_intr_status;   // 0x1C  (W1C)
    reg [7:0]  tx_fifo    [0:FIFO_DEPTH-1];
    reg [7:0]  rx_fifo    [0:FIFO_DEPTH-1];
    reg [2:0]  tx_wr_ptr, tx_rd_ptr;
    reg [2:0]  rx_wr_ptr, rx_rd_ptr;
    reg [3:0]  tx_count,  rx_count;

    // ——— AXI4-Lite state ———
    reg awready, wready;
    reg [31:0] awaddr_latch, wdata_latch;
    reg [3:0]  wstrb_latch;
    reg        aw_latched, w_latched;
    reg [1:0]  bresp;
    reg        bvalid;
    reg        arready;
    reg [31:0] araddr_latch;
    reg        ar_latched;
    reg [31:0] rdata;
    reg [1:0]  rresp;
    reg        rvalid;

    // Write handshake: accept aw+w any order, then respond
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            awready <= 1'b0; wready <= 1'b0;
            awaddr_latch <= 32'd0; wdata_latch <= 32'd0; wstrb_latch <= 4'd0;
            aw_latched <= 1'b0; w_latched <= 1'b0;
            bvalid <= 1'b0; bresp <= AXI_OKAY;
        end else begin
            // Latch address
            if (s_axi_awvalid_i && awready) begin
                awaddr_latch <= s_axi_awaddr_i;
                aw_latched <= 1'b1;
                awready <= 1'b0;
            end
            // Latch data
            if (s_axi_wvalid_i && wready) begin
                wdata_latch <= s_axi_wdata_i;
                wstrb_latch <= s_axi_wstrb_i;
                w_latched <= 1'b1;
                wready <= 1'b0;
            end
            // When both present, commit write
            if (aw_latched && w_latched && !bvalid) begin
                bvalid <= 1'b1;
                bresp <= wr_valid ? AXI_OKAY : AXI_SLVERR;
                aw_latched <= 1'b0;
                w_latched <= 1'b0;
            end
            // Response handshake
            if (bvalid && s_axi_bready_i) begin
                bvalid <= 1'b0;
            end
            // Re-arm ready
            if (!aw_latched && !(aw_latched && w_latched && !bvalid))
                awready <= !s_axi_awvalid_i || !awready;
            else awready <= 1'b0;
            if (!w_latched && !(aw_latched && w_latched && !bvalid))
                wready <= !s_axi_wvalid_i || !wready;
            else wready <= 1'b0;
        end
    end

    // Address decode — 32-bit word offset
    wire [5:0] wr_off = awaddr_latch[7:2];
    wire wr_is_ctrl   = (wr_off == 6'h00);
    wire wr_is_clkdiv = (wr_off == 6'h02);
    wire wr_is_txdata = (wr_off == 6'h03);
    wire wr_is_cs     = (wr_off == 6'h05);
    wire wr_is_im     = (wr_off == 6'h06);
    wire wr_is_ist    = (wr_off == 6'h07);
    wire wr_valid = wr_is_ctrl | wr_is_clkdiv | wr_is_txdata | wr_is_cs | wr_is_im | wr_is_ist;

    wire wr_commit = bvalid && s_axi_bready_i;

    // ——— Read channel ———
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            arready <= 1'b0;
            araddr_latch <= 32'd0;
            ar_latched <= 1'b0;
            rvalid <= 1'b0;
            rdata <= 32'd0;
            rresp <= AXI_OKAY;
        end else begin
            // Accept read address
            if (s_axi_arvalid_i && arready) begin
                araddr_latch <= s_axi_araddr_i;
                ar_latched <= 1'b1;
                arready <= 1'b0;
            end
            // Respond next cycle
            if (ar_latched && !rvalid) begin
                rvalid <= 1'b1;
                rdata <= rd_data;
                rresp <= rd_valid ? AXI_OKAY : AXI_SLVERR;
                ar_latched <= 1'b0;
            end
            if (rvalid && s_axi_rready_i) begin
                rvalid <= 1'b0;
            end
            arready <= !ar_latched;
        end
    end

    // Read data mux
    wire [5:0] rd_off = araddr_latch[7:2];
    wire [31:0] rd_data;
    wire rd_valid;
    // Status: TX_FIFO_COUNT[11:8], RX_FIFO_COUNT[15:12]
    wire [31:0] status_word = {16'd0, rx_count, 4'd0, tx_count, 4'd0,
                                tx_busy, 2'd0, rx_full, rx_empty,
                                tx_full, tx_empty};
    assign {rd_data, rd_valid} =
        (rd_off == 6'h00) ? {reg_ctrl,        1'b1} :
        (rd_off == 6'h01) ? {status_word,     1'b1} :
        (rd_off == 6'h02) ? {reg_clkdiv,      1'b1} :
        (rd_off == 6'h04) ? {rx_fifo_data,    1'b1} :
        (rd_off == 6'h05) ? {reg_cs,          1'b1} :
        (rd_off == 6'h06) ? {reg_intr_mask,   1'b1} :
        (rd_off == 6'h07) ? {reg_intr_status, 1'b1} :
                             {32'd0,           1'b0};

    wire [7:0] rx_fifo_data = rx_fifo[rx_rd_ptr];

    // ——— Write register logic (triggered on wr_commit) ———
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            reg_ctrl       <= 32'd0;
            reg_clkdiv     <= 32'd4;    // default: sys_clk/8 = 12.5 MHz
            reg_cs         <= 32'hF;    // all CS inactive-high (cs_n = 1)
            reg_intr_mask  <= 32'd0;
            reg_intr_status<= 32'd0;
        end else begin
            // W1C on interrupt status
            if (tx_empty_pulse)
                reg_intr_status[1] <= 1'b0;
            if (rx_avail_pulse && (rx_count > 0))
                reg_intr_status[0] <= 1'b0;

            // SPI DONE → pulse tx_complete → status
            if (spi_done_s) begin
                reg_intr_status[4] <= 1'b0;
            end

            if (wr_commit) begin
                if (wr_is_ctrl) begin
                    if (wstrb_latch[0]) begin
                        reg_ctrl[0]  <= wdata_latch[0];   // ENABLE
                        reg_ctrl[1]  <= wdata_latch[1];   // CPOL
                        reg_ctrl[2]  <= wdata_latch[2];   // CPHA
                        reg_ctrl[3]  <= wdata_latch[3];   // MSTEN
                        reg_ctrl[4]  <= wdata_latch[4];   // LSBFE
                        reg_ctrl[5]  <= wdata_latch[5];   // AUTOCS
                    end
                    if (wstrb_latch[1]) begin
                        if (wdata_latch[8]) begin tx_wr_ptr <= 3'd0; tx_rd_ptr <= 3'd0; tx_count <= 4'd0; end
                        if (wdata_latch[9]) begin rx_wr_ptr <= 3'd0; rx_rd_ptr <= 3'd0; rx_count <= 4'd0; end
                        reg_ctrl[10] <= wdata_latch[10];  // CLK_EN
                    end
                end
                if (wr_is_clkdiv)
                    reg_clkdiv <= wdata_latch;
                if (wr_is_txdata && wstrb_latch[0] && tx_count < FIFO_DEPTH) begin
                    tx_fifo[tx_wr_ptr] <= wdata_latch[7:0];
                    tx_wr_ptr <= tx_wr_ptr + 3'd1;
                    tx_count  <= tx_count + 4'd1;
                end
                if (wr_is_cs)
                    reg_cs <= wdata_latch;
                if (wr_is_im)
                    reg_intr_mask <= wdata_latch;
                if (wr_is_ist)
                    reg_intr_status <= reg_intr_status & ~wdata_latch;  // W1C
            end
        end
    end

    // ——— FIFO status ———
    wire tx_empty = (tx_count == 4'd0);
    wire tx_full  = (tx_count == FIFO_DEPTH);
    wire rx_empty = (rx_count == 4'd0);
    wire rx_full  = (rx_count == FIFO_DEPTH);

    // ——— SPI clock generation ———
    reg [15:0] clkdiv_cnt;
    wire       sck_en;
    wire [15:0] divider = |reg_clkdiv[15:0] ? reg_clkdiv[15:0] : 16'd4;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            clkdiv_cnt <= 16'd0;
        else if (reg_ctrl[0] && !tx_empty)
            clkdiv_cnt <= (clkdiv_cnt >= divider - 1) ? 16'd0 : clkdiv_cnt + 16'd1;
        else
            clkdiv_cnt <= 16'd0;
    end
    assign sck_en = (clkdiv_cnt == 16'd0) && reg_ctrl[0];

    // ——— SPI state machine ———
    reg [3:0] bit_cnt;
    reg       sck_reg, mosi_reg;
    reg       tx_busy;
    reg       spi_done_s;

    localparam SPI_IDLE = 2'd0, SPI_SHIFT = 2'd1, SPI_DONE = 2'd2;
    reg [1:0] spi_state, spi_next;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            spi_state <= SPI_IDLE;
        else
            spi_state <= spi_next;
    end

    always @(*) begin
        spi_next = spi_state;
        case (spi_state)
            SPI_IDLE: if (!tx_empty && reg_ctrl[0]) spi_next = SPI_SHIFT;
            SPI_SHIFT: if (bit_cnt == 4'd8 && sck_en) spi_next = SPI_DONE;
            SPI_DONE: spi_next = SPI_IDLE;
            default:  spi_next = SPI_IDLE;
        endcase
    end

    reg [7:0] shift_reg;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sck_reg   <= 1'b0;
            mosi_reg  <= 1'b0;
            bit_cnt   <= 4'd0;
            tx_busy   <= 1'b0;
            spi_done_s <= 1'b0;
            shift_reg <= 8'd0;
        end else begin
            spi_done_s <= 1'b0;
            case (spi_state)
                SPI_IDLE: begin
                    sck_reg <= reg_ctrl[1];  // idle level = CPOL
                    bit_cnt <= 4'd0;
                    tx_busy <= 1'b0;
                    if (!tx_empty && reg_ctrl[0]) begin
                        shift_reg <= tx_fifo[tx_rd_ptr];
                        tx_rd_ptr <= tx_rd_ptr + 3'd1;
                        tx_count  <= tx_count - 4'd1;
                        tx_busy   <= 1'b1;
                    end
                end
                SPI_SHIFT: begin
                    if (sck_en) begin
                        if (bit_cnt < 4'd8) begin
                            // CPHA=0: drive on first edge (sck_en 1→toggle)
                            // CPHA=1: drive on second edge
                            if (reg_ctrl[2] == 1'b0) begin
                                // CPHA=0: sample at leading edge, shift at trailing
                                if (sck_reg == reg_ctrl[1]) begin
                                    mosi_reg <= reg_ctrl[4] ? shift_reg[0] : shift_reg[7];
                                end else begin
                                    if (reg_ctrl[4]) shift_reg <= {1'b0, shift_reg[7:1]};
                                    else              shift_reg <= {shift_reg[6:0], 1'b0};
                                end
                            end else begin
                                // CPHA=1: shift at leading edge, sample at trailing
                                if (sck_reg == reg_ctrl[1]) begin
                                    if (reg_ctrl[4]) shift_reg <= {1'b0, shift_reg[7:1]};
                                    else              shift_reg <= {shift_reg[6:0], 1'b0};
                                end else begin
                                    mosi_reg <= reg_ctrl[4] ? shift_reg[0] : shift_reg[7];
                                end
                            end
                            sck_reg <= ~sck_reg;
                        end
                        bit_cnt <= bit_cnt + 4'd1;
                    end
                end
                SPI_DONE: begin
                    spi_done_s <= 1'b1;
                    // Capture MISO byte into RX FIFO
                    if (rx_count < FIFO_DEPTH) begin
                        rx_fifo[rx_wr_ptr] <= shift_reg;
                        rx_wr_ptr <= rx_wr_ptr + 3'd1;
                        rx_count  <= rx_count + 4'd1;
                    end
                    sck_reg <= reg_ctrl[1];
                    bit_cnt <= 4'd0;
                end
            endcase
        end
    end

    assign sck_o  = sck_reg;
    assign mosi_o = mosi_reg;
    assign cs_n_o = reg_ctrl[0] ? ~reg_cs[3:0] : 4'hF;  // active-low CS

    // ——— Interrupt generation ———
    reg tx_empty_d1, rx_avail_d1, rx_empty_d1;
    wire tx_empty_pulse = tx_empty && !tx_empty_d1;
    wire rx_avail_pulse = !rx_empty && rx_empty_d1;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tx_empty_d1 <= 1'b1;
            rx_avail_d1 <= 1'b0;
            rx_empty_d1 <= 1'b1;
        end else begin
            tx_empty_d1 <= tx_empty;
            rx_avail_d1 <= !rx_empty;
            rx_empty_d1 <= rx_empty;
        end
    end

    assign irq_rx_o  = reg_intr_mask[0] && !rx_empty;
    assign irq_tx_o  = reg_intr_mask[1] && tx_empty;
    assign irq_err_o = reg_intr_mask[2] && 1'b0;  // no detailed error tracking yet
    assign fault_o   = 1'b0;

    // Output assignments
    assign s_axi_awready_o = awready;
    assign s_axi_wready_o  = wready;
    assign s_axi_bresp_o   = bresp;
    assign s_axi_bvalid_o  = bvalid;
    assign s_axi_arready_o = arready;
    assign s_axi_rdata_o   = rdata;
    assign s_axi_rresp_o   = rresp;
    assign s_axi_rvalid_o  = rvalid;

endmodule
