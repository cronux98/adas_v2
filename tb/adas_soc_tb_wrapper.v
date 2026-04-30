// ============================================================================
// adas_soc_tb_wrapper.v — Testbench Wrapper for cocotb + Icarus Verilog
// ============================================================================
// Purpose:  Exposes the AXI4-Lite crossbar master port externally so cocotb
//           can drive peripheral register accesses directly, bypassing the
//           RV32IM CPU core (which has no firmware loaded for simulation).
//
// This wrapper instantiates:
//   - AXI4-Lite Interconnect (1M→9S crossbar)
//   - All 9 peripheral blocks (AI, SPI, Servo, Speed, Buzzer, UART, GPIO,
//     Fault Aggregator, WDT)
//   - Safety subsystem (lockstep, fault aggregator, redundant shutdown)
//   - Clock-domain-crossing synchronizers
//
// The CPU-side AXI master interface is brought to top-level ports so cocotb
// can perform read/write register transactions.
//
// ============================================================================

`timescale 1ns / 1ps

module adas_soc_tb_wrapper (
    // =====================================================================
    // Clocks
    // =====================================================================
    input  wire        sys_clk_i,
    input  wire        wdt_clk_i,

    // =====================================================================
    // Resets (async assert, sync de-assert)
    // =====================================================================
    input  wire        sys_rst_n_i,
    input  wire        wdt_rst_n_i,

    // =====================================================================
    // Testbench AXI4-Lite Master Interface (drives the crossbar)
    // =====================================================================
    // Write Address Channel
    input  wire [31:0] tb_axi_awaddr,
    input  wire [2:0]  tb_axi_awprot,
    input  wire        tb_axi_awvalid,
    output wire        tb_axi_awready,
    // Write Data Channel
    input  wire [31:0] tb_axi_wdata,
    input  wire [3:0]  tb_axi_wstrb,
    input  wire        tb_axi_wvalid,
    output wire        tb_axi_wready,
    // Write Response Channel
    output wire [1:0]  tb_axi_bresp,
    output wire        tb_axi_bvalid,
    input  wire        tb_axi_bready,
    // Read Address Channel
    input  wire [31:0] tb_axi_araddr,
    input  wire [2:0]  tb_axi_arprot,
    input  wire        tb_axi_arvalid,
    output wire        tb_axi_arready,
    // Read Data Channel
    output wire [31:0] tb_axi_rdata,
    output wire [1:0]  tb_axi_rresp,
    output wire        tb_axi_rvalid,
    input  wire        tb_axi_rready,

    // =====================================================================
    // SPI External Interface
    // =====================================================================
    output wire        spi_sck_o,
    output wire        spi_mosi_o,
    input  wire        spi_miso_i,
    output wire [3:0]  spi_cs_n_o,

    // =====================================================================
    // Servo PWM Output
    // =====================================================================
    output wire        servo_pwm_o,

    // =====================================================================
    // Speed Sensor Pulse Input
    // =====================================================================
    input  wire        speed_pulse_i,

    // =====================================================================
    // Buzzer PWM Output
    // =====================================================================
    output wire        buzzer_pwm_o,

    // =====================================================================
    // UART External Interface
    // =====================================================================
    output wire        uart_tx_o,
    input  wire        uart_rx_i,

    // =====================================================================
    // GPIO Bidirectional Bus
    // =====================================================================
    inout  wire [31:0] gpio_io,

    // =====================================================================
    // Safety Outputs (wdt_clk domain)
    // =====================================================================
    output wire        alert_n_o,
    output wire [1:0]  shutdown_n_o,

    // =====================================================================
    // DFT Test Mode
    // =====================================================================
    input  wire        test_mode_i,

    // =====================================================================
    // Lockstep Test Inject Inputs (for safety path verification)
    // =====================================================================
    input  wire [31:0] ls_test_outputs,
    input  wire [31:0] ls_test_pc,
    input  wire        ls_test_valid,
    input  wire [31:0] ls_test_checker_outputs,
    input  wire [31:0] ls_test_checker_pc,
    input  wire        ls_test_checker_valid,

    // =====================================================================
    // Status Observation Outputs
    // =====================================================================
    output wire        ai_irq_done,
    output wire        ai_irq_error,
    output wire [15:0] all_irq_lines,
    output wire        fault_agg_out,
    output wire        ls_mismatch_obs,
    output wire [31:0] ls_count_obs,
    output wire        wdt_fault_obs,
    output wire        wdt_prewarn_obs,
    output wire        core_halt_obs,
    output wire        force_shutdown_obs
);

    // =========================================================================
    // Internal wires
    // =========================================================================
    wire sys_rst_n  = sys_rst_n_i;
    wire wdt_rst_n  = wdt_rst_n_i;

    // =========================================================================
    // AXI Crossbar Slave 0..8 signals
    // =========================================================================
    wire [31:0] s0_awaddr, s0_wdata, s0_araddr;
    wire [2:0]  s0_awprot, s0_arprot;
    wire        s0_awvalid, s0_wvalid, s0_bready, s0_arvalid, s0_rready;
    wire [3:0]  s0_wstrb;
    wire        s0_awready, s0_wready;
    wire [1:0]  s0_bresp;
    wire        s0_bvalid;
    wire        s0_arready;
    wire [31:0] s0_rdata;
    wire [1:0]  s0_rresp;
    wire        s0_rvalid;

    wire [31:0] s1_awaddr, s1_wdata, s1_araddr;
    wire [2:0]  s1_awprot, s1_arprot;
    wire        s1_awvalid, s1_wvalid, s1_bready, s1_arvalid, s1_rready;
    wire [3:0]  s1_wstrb;
    wire        s1_awready, s1_wready;
    wire [1:0]  s1_bresp;
    wire        s1_bvalid;
    wire        s1_arready;
    wire [31:0] s1_rdata;
    wire [1:0]  s1_rresp;
    wire        s1_rvalid;

    wire [31:0] s2_awaddr, s2_wdata, s2_araddr;
    wire [2:0]  s2_awprot, s2_arprot;
    wire        s2_awvalid, s2_wvalid, s2_bready, s2_arvalid, s2_rready;
    wire [3:0]  s2_wstrb;
    wire        s2_awready, s2_wready;
    wire [1:0]  s2_bresp;
    wire        s2_bvalid;
    wire        s2_arready;
    wire [31:0] s2_rdata;
    wire [1:0]  s2_rresp;
    wire        s2_rvalid;

    wire [31:0] s3_awaddr, s3_wdata, s3_araddr;
    wire [2:0]  s3_awprot, s3_arprot;
    wire        s3_awvalid, s3_wvalid, s3_bready, s3_arvalid, s3_rready;
    wire [3:0]  s3_wstrb;
    wire        s3_awready, s3_wready;
    wire [1:0]  s3_bresp;
    wire        s3_bvalid;
    wire        s3_arready;
    wire [31:0] s3_rdata;
    wire [1:0]  s3_rresp;
    wire        s3_rvalid;

    wire [31:0] s4_awaddr, s4_wdata, s4_araddr;
    wire [2:0]  s4_awprot, s4_arprot;
    wire        s4_awvalid, s4_wvalid, s4_bready, s4_arvalid, s4_rready;
    wire [3:0]  s4_wstrb;
    wire        s4_awready, s4_wready;
    wire [1:0]  s4_bresp;
    wire        s4_bvalid;
    wire        s4_arready;
    wire [31:0] s4_rdata;
    wire [1:0]  s4_rresp;
    wire        s4_rvalid;

    wire [31:0] s5_awaddr, s5_wdata, s5_araddr;
    wire [2:0]  s5_awprot, s5_arprot;
    wire        s5_awvalid, s5_wvalid, s5_bready, s5_arvalid, s5_rready;
    wire [3:0]  s5_wstrb;
    wire        s5_awready, s5_wready;
    wire [1:0]  s5_bresp;
    wire        s5_bvalid;
    wire        s5_arready;
    wire [31:0] s5_rdata;
    wire [1:0]  s5_rresp;
    wire        s5_rvalid;

    wire [31:0] s6_awaddr, s6_wdata, s6_araddr;
    wire [2:0]  s6_awprot, s6_arprot;
    wire        s6_awvalid, s6_wvalid, s6_bready, s6_arvalid, s6_rready;
    wire [3:0]  s6_wstrb;
    wire        s6_awready, s6_wready;
    wire [1:0]  s6_bresp;
    wire        s6_bvalid;
    wire        s6_arready;
    wire [31:0] s6_rdata;
    wire [1:0]  s6_rresp;
    wire        s6_rvalid;

    wire [31:0] s7_awaddr, s7_wdata, s7_araddr;
    wire [2:0]  s7_awprot, s7_arprot;
    wire        s7_awvalid, s7_wvalid, s7_bready, s7_arvalid, s7_rready;
    wire [3:0]  s7_wstrb;
    wire        s7_awready, s7_wready;
    wire [1:0]  s7_bresp;
    wire        s7_bvalid;
    wire        s7_arready;
    wire [31:0] s7_rdata;
    wire [1:0]  s7_rresp;
    wire        s7_rvalid;

    wire [31:0] s8_awaddr, s8_wdata, s8_araddr;
    wire [2:0]  s8_awprot, s8_arprot;
    wire        s8_awvalid, s8_wvalid, s8_bready, s8_arvalid, s8_rready;
    wire [3:0]  s8_wstrb;
    wire        s8_awready, s8_wready;
    wire [1:0]  s8_bresp;
    wire        s8_bvalid;
    wire        s8_arready;
    wire [31:0] s8_rdata;
    wire [1:0]  s8_rresp;
    wire        s8_rvalid;

    // =========================================================================
    // TCM placeholder wires (not used in testbench mode, tie off)
    // =========================================================================
    wire [31:0] itcm_rdata = 32'h00000013; // NOP instruction (addi x0,x0,0)
    wire        itcm_ack   = 1'b1;
    wire        itcm_parity_err = 1'b0;
    wire [31:0] dtcm_rdata = 32'd0;
    wire        dtcm_ack   = 1'b1;
    wire        dtcm_parity_err = 1'b0;

    // =========================================================================
    // AXI4-Lite Crossbar
    // =========================================================================
    axi4_lite_interconnect u_axi_xbar (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),

        // Master (driven by testbench)
        .m_axi_awaddr_i   (tb_axi_awaddr),
        .m_axi_awprot_i   (tb_axi_awprot),
        .m_axi_awvalid_i  (tb_axi_awvalid),
        .m_axi_awready_o  (tb_axi_awready),
        .m_axi_wdata_i    (tb_axi_wdata),
        .m_axi_wstrb_i    (tb_axi_wstrb),
        .m_axi_wvalid_i   (tb_axi_wvalid),
        .m_axi_wready_o   (tb_axi_wready),
        .m_axi_bresp_o    (tb_axi_bresp),
        .m_axi_bvalid_o   (tb_axi_bvalid),
        .m_axi_bready_i   (tb_axi_bready),
        .m_axi_araddr_i   (tb_axi_araddr),
        .m_axi_arprot_i   (tb_axi_arprot),
        .m_axi_arvalid_i  (tb_axi_arvalid),
        .m_axi_arready_o  (tb_axi_arready),
        .m_axi_rdata_o    (tb_axi_rdata),
        .m_axi_rresp_o    (tb_axi_rresp),
        .m_axi_rvalid_o   (tb_axi_rvalid),
        .m_axi_rready_i   (tb_axi_rready),

        // Slave 0 — AI Accelerator
        .s0_axi_awaddr_o  (s0_awaddr),  .s0_axi_awprot_o(s0_awprot), .s0_axi_awvalid_o(s0_awvalid),  .s0_axi_awready_i(s0_awready),
        .s0_axi_wdata_o   (s0_wdata),   .s0_axi_wstrb_o(s0_wstrb),   .s0_axi_wvalid_o(s0_wvalid),    .s0_axi_wready_i(s0_wready),
        .s0_axi_bresp_i   (s0_bresp),   .s0_axi_bvalid_i(s0_bvalid), .s0_axi_bready_o(s0_bready),
        .s0_axi_araddr_o  (s0_araddr),  .s0_axi_arprot_o(s0_arprot), .s0_axi_arvalid_o(s0_arvalid),  .s0_axi_arready_i(s0_arready),
        .s0_axi_rdata_i   (s0_rdata),   .s0_axi_rresp_i(s0_rresp),   .s0_axi_rvalid_i(s0_rvalid),    .s0_axi_rready_o(s0_rready),
        // Slave 1 — SPI
        .s1_axi_awaddr_o  (s1_awaddr),  .s1_axi_awprot_o(s1_awprot), .s1_axi_awvalid_o(s1_awvalid),  .s1_axi_awready_i(s1_awready),
        .s1_axi_wdata_o   (s1_wdata),   .s1_axi_wstrb_o(s1_wstrb),   .s1_axi_wvalid_o(s1_wvalid),    .s1_axi_wready_i(s1_wready),
        .s1_axi_bresp_i   (s1_bresp),   .s1_axi_bvalid_i(s1_bvalid), .s1_axi_bready_o(s1_bready),
        .s1_axi_araddr_o  (s1_araddr),  .s1_axi_arprot_o(s1_arprot), .s1_axi_arvalid_o(s1_arvalid),  .s1_axi_arready_i(s1_arready),
        .s1_axi_rdata_i   (s1_rdata),   .s1_axi_rresp_i(s1_rresp),   .s1_axi_rvalid_i(s1_rvalid),    .s1_axi_rready_o(s1_rready),
        // Slave 2 — Servo
        .s2_axi_awaddr_o  (s2_awaddr),  .s2_axi_awprot_o(s2_awprot), .s2_axi_awvalid_o(s2_awvalid),  .s2_axi_awready_i(s2_awready),
        .s2_axi_wdata_o   (s2_wdata),   .s2_axi_wstrb_o(s2_wstrb),   .s2_axi_wvalid_o(s2_wvalid),    .s2_axi_wready_i(s2_wready),
        .s2_axi_bresp_i   (s2_bresp),   .s2_axi_bvalid_i(s2_bvalid), .s2_axi_bready_o(s2_bready),
        .s2_axi_araddr_o  (s2_araddr),  .s2_axi_arprot_o(s2_arprot), .s2_axi_arvalid_o(s2_arvalid),  .s2_axi_arready_i(s2_arready),
        .s2_axi_rdata_i   (s2_rdata),   .s2_axi_rresp_i(s2_rresp),   .s2_axi_rvalid_i(s2_rvalid),    .s2_axi_rready_o(s2_rready),
        // Slave 3 — Speed
        .s3_axi_awaddr_o  (s3_awaddr),  .s3_axi_awprot_o(s3_awprot), .s3_axi_awvalid_o(s3_awvalid),  .s3_axi_awready_i(s3_awready),
        .s3_axi_wdata_o   (s3_wdata),   .s3_axi_wstrb_o(s3_wstrb),   .s3_axi_wvalid_o(s3_wvalid),    .s3_axi_wready_i(s3_wready),
        .s3_axi_bresp_i   (s3_bresp),   .s3_axi_bvalid_i(s3_bvalid), .s3_axi_bready_o(s3_bready),
        .s3_axi_araddr_o  (s3_araddr),  .s3_axi_arprot_o(s3_arprot), .s3_axi_arvalid_o(s3_arvalid),  .s3_axi_arready_i(s3_arready),
        .s3_axi_rdata_i   (s3_rdata),   .s3_axi_rresp_i(s3_rresp),   .s3_axi_rvalid_i(s3_rvalid),    .s3_axi_rready_o(s3_rready),
        // Slave 4 — Buzzer
        .s4_axi_awaddr_o  (s4_awaddr),  .s4_axi_awprot_o(s4_awprot), .s4_axi_awvalid_o(s4_awvalid),  .s4_axi_awready_i(s4_awready),
        .s4_axi_wdata_o   (s4_wdata),   .s4_axi_wstrb_o(s4_wstrb),   .s4_axi_wvalid_o(s4_wvalid),    .s4_axi_wready_i(s4_wready),
        .s4_axi_bresp_i   (s4_bresp),   .s4_axi_bvalid_i(s4_bvalid), .s4_axi_bready_o(s4_bready),
        .s4_axi_araddr_o  (s4_araddr),  .s4_axi_arprot_o(s4_arprot), .s4_axi_arvalid_o(s4_arvalid),  .s4_axi_arready_i(s4_arready),
        .s4_axi_rdata_i   (s4_rdata),   .s4_axi_rresp_i(s4_rresp),   .s4_axi_rvalid_i(s4_rvalid),    .s4_axi_rready_o(s4_rready),
        // Slave 5 — UART
        .s5_axi_awaddr_o  (s5_awaddr),  .s5_axi_awprot_o(s5_awprot), .s5_axi_awvalid_o(s5_awvalid),  .s5_axi_awready_i(s5_awready),
        .s5_axi_wdata_o   (s5_wdata),   .s5_axi_wstrb_o(s5_wstrb),   .s5_axi_wvalid_o(s5_wvalid),    .s5_axi_wready_i(s5_wready),
        .s5_axi_bresp_i   (s5_bresp),   .s5_axi_bvalid_i(s5_bvalid), .s5_axi_bready_o(s5_bready),
        .s5_axi_araddr_o  (s5_araddr),  .s5_axi_arprot_o(s5_arprot), .s5_axi_arvalid_o(s5_arvalid),  .s5_axi_arready_i(s5_arready),
        .s5_axi_rdata_i   (s5_rdata),   .s5_axi_rresp_i(s5_rresp),   .s5_axi_rvalid_i(s5_rvalid),    .s5_axi_rready_o(s5_rready),
        // Slave 6 — GPIO
        .s6_axi_awaddr_o  (s6_awaddr),  .s6_axi_awprot_o(s6_awprot), .s6_axi_awvalid_o(s6_awvalid),  .s6_axi_awready_i(s6_awready),
        .s6_axi_wdata_o   (s6_wdata),   .s6_axi_wstrb_o(s6_wstrb),   .s6_axi_wvalid_o(s6_wvalid),    .s6_axi_wready_i(s6_wready),
        .s6_axi_bresp_i   (s6_bresp),   .s6_axi_bvalid_i(s6_bvalid), .s6_axi_bready_o(s6_bready),
        .s6_axi_araddr_o  (s6_araddr),  .s6_axi_arprot_o(s6_arprot), .s6_axi_arvalid_o(s6_arvalid),  .s6_axi_arready_i(s6_arready),
        .s6_axi_rdata_i   (s6_rdata),   .s6_axi_rresp_i(s6_rresp),   .s6_axi_rvalid_i(s6_rvalid),    .s6_axi_rready_o(s6_rready),
        // Slave 7 — Fault Aggregator
        .s7_axi_awaddr_o  (s7_awaddr),  .s7_axi_awprot_o(s7_awprot), .s7_axi_awvalid_o(s7_awvalid),  .s7_axi_awready_i(s7_awready),
        .s7_axi_wdata_o   (s7_wdata),   .s7_axi_wstrb_o(s7_wstrb),   .s7_axi_wvalid_o(s7_wvalid),    .s7_axi_wready_i(s7_wready),
        .s7_axi_bresp_i   (s7_bresp),   .s7_axi_bvalid_i(s7_bvalid), .s7_axi_bready_o(s7_bready),
        .s7_axi_araddr_o  (s7_araddr),  .s7_axi_arprot_o(s7_arprot), .s7_axi_arvalid_o(s7_arvalid),  .s7_axi_arready_i(s7_arready),
        .s7_axi_rdata_i   (s7_rdata),   .s7_axi_rresp_i(s7_rresp),   .s7_axi_rvalid_i(s7_rvalid),    .s7_axi_rready_o(s7_rready),
        // Slave 8 — WDT
        .s8_axi_awaddr_o  (s8_awaddr),  .s8_axi_awprot_o(s8_awprot), .s8_axi_awvalid_o(s8_awvalid),  .s8_axi_awready_i(s8_awready),
        .s8_axi_wdata_o   (s8_wdata),   .s8_axi_wstrb_o(s8_wstrb),   .s8_axi_wvalid_o(s8_wvalid),    .s8_axi_wready_i(s8_wready),
        .s8_axi_bresp_i   (s8_bresp),   .s8_axi_bvalid_i(s8_bvalid), .s8_axi_bready_o(s8_bready),
        .s8_axi_araddr_o  (s8_araddr),  .s8_axi_arprot_o(s8_arprot), .s8_axi_arvalid_o(s8_arvalid),  .s8_axi_arready_i(s8_arready),
        .s8_axi_rdata_i   (s8_rdata),   .s8_axi_rresp_i(s8_rresp),   .s8_axi_rvalid_i(s8_rvalid),    .s8_axi_rready_o(s8_rready)
    );

    // =========================================================================
    // Peripheral Blocks
    // =========================================================================

    // ---- AI Accelerator ----
    wire ai_irq_done_w, ai_irq_error_w, ai_fault;
    ai_accel_4x4 u_ai_accel (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        .s_axi_awaddr_i   (s0_awaddr),  .s_axi_awvalid_i(s0_awvalid),  .s_axi_awready_o(s0_awready),
        .s_axi_wdata_i    (s0_wdata),   .s_axi_wstrb_i(s0_wstrb),     .s_axi_wvalid_i(s0_wvalid),    .s_axi_wready_o(s0_wready),
        .s_axi_bresp_o    (s0_bresp),   .s_axi_bvalid_o(s0_bvalid),   .s_axi_bready_i(s0_bready),
        .s_axi_araddr_i   (s0_araddr),  .s_axi_arvalid_i(s0_arvalid), .s_axi_arready_o(s0_arready),
        .s_axi_rdata_o    (s0_rdata),   .s_axi_rresp_o(s0_rresp),     .s_axi_rvalid_o(s0_rvalid),    .s_axi_rready_i(s0_rready),
        .irq_done_o       (ai_irq_done_w),
        .irq_error_o      (ai_irq_error_w),
        .fault_o          (ai_fault)
    );

    // ---- SPI Controller ----
    wire spi_irq_rx, spi_irq_tx, spi_irq_err, spi_fault;
    spi_controller u_spi (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        .s_axi_awaddr_i   (s1_awaddr),  .s_axi_awvalid_i(s1_awvalid),  .s_axi_awready_o(s1_awready),
        .s_axi_wdata_i    (s1_wdata),   .s_axi_wstrb_i(s1_wstrb),     .s_axi_wvalid_i(s1_wvalid),    .s_axi_wready_o(s1_wready),
        .s_axi_bresp_o    (s1_bresp),   .s_axi_bvalid_o(s1_bvalid),   .s_axi_bready_i(s1_bready),
        .s_axi_araddr_i   (s1_araddr),  .s_axi_arvalid_i(s1_arvalid), .s_axi_arready_o(s1_arready),
        .s_axi_rdata_o    (s1_rdata),   .s_axi_rresp_o(s1_rresp),     .s_axi_rvalid_o(s1_rvalid),    .s_axi_rready_i(s1_rready),
        .sck_o            (spi_sck_o),
        .mosi_o           (spi_mosi_o),
        .miso_i           (spi_miso_i),
        .cs_n_o           (spi_cs_n_o),
        .irq_rx_o         (spi_irq_rx),
        .irq_tx_o         (spi_irq_tx),
        .irq_err_o        (spi_irq_err),
        .fault_o          (spi_fault)
    );

    // ---- Servo PWM ----
    wire servo_irq_fault, servo_fault;
    servo_pwm u_servo (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        .s_axi_awaddr_i   (s2_awaddr),  .s_axi_awvalid_i(s2_awvalid),  .s_axi_awready_o(s2_awready),
        .s_axi_wdata_i    (s2_wdata),   .s_axi_wstrb_i(s2_wstrb),     .s_axi_wvalid_i(s2_wvalid),    .s_axi_wready_o(s2_wready),
        .s_axi_bresp_o    (s2_bresp),   .s_axi_bvalid_o(s2_bvalid),   .s_axi_bready_i(s2_bready),
        .s_axi_araddr_i   (s2_araddr),  .s_axi_arvalid_i(s2_arvalid), .s_axi_arready_o(s2_arready),
        .s_axi_rdata_o    (s2_rdata),   .s_axi_rresp_o(s2_rresp),     .s_axi_rvalid_o(s2_rvalid),    .s_axi_rready_i(s2_rready),
        .pwm_o            (servo_pwm_o),
        .irq_fault_o      (servo_irq_fault),
        .fault_o          (servo_fault)
    );

    // ---- Speed Sensor ----
    wire speed_irq_pulse, speed_irq_ovf, speed_fault;
    speed_sensor u_speed (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        .s_axi_awaddr_i   (s3_awaddr),  .s_axi_awvalid_i(s3_awvalid),  .s_axi_awready_o(s3_awready),
        .s_axi_wdata_i    (s3_wdata),   .s_axi_wstrb_i(s3_wstrb),     .s_axi_wvalid_i(s3_wvalid),    .s_axi_wready_o(s3_wready),
        .s_axi_bresp_o    (s3_bresp),   .s_axi_bvalid_o(s3_bvalid),   .s_axi_bready_i(s3_bready),
        .s_axi_araddr_i   (s3_araddr),  .s_axi_arvalid_i(s3_arvalid), .s_axi_arready_o(s3_arready),
        .s_axi_rdata_o    (s3_rdata),   .s_axi_rresp_o(s3_rresp),     .s_axi_rvalid_o(s3_rvalid),    .s_axi_rready_i(s3_rready),
        .pulse_i          (speed_pulse_i),
        .irq_pulse_o      (speed_irq_pulse),
        .irq_ovf_o        (speed_irq_ovf),
        .fault_o          (speed_fault)
    );

    // ---- Buzzer PWM ----
    wire buzzer_irq_done_w;
    buzzer_pwm u_buzzer (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        .s_axi_awaddr_i   (s4_awaddr),  .s_axi_awvalid_i(s4_awvalid),  .s_axi_awready_o(s4_awready),
        .s_axi_wdata_i    (s4_wdata),   .s_axi_wstrb_i(s4_wstrb),     .s_axi_wvalid_i(s4_wvalid),    .s_axi_wready_o(s4_wready),
        .s_axi_bresp_o    (s4_bresp),   .s_axi_bvalid_o(s4_bvalid),   .s_axi_bready_i(s4_bready),
        .s_axi_araddr_i   (s4_araddr),  .s_axi_arvalid_i(s4_arvalid), .s_axi_arready_o(s4_arready),
        .s_axi_rdata_o    (s4_rdata),   .s_axi_rresp_o(s4_rresp),     .s_axi_rvalid_o(s4_rvalid),    .s_axi_rready_i(s4_rready),
        .pwm_o            (buzzer_pwm_o),
        .irq_done_o       (buzzer_irq_done_w)
    );

    // ---- UART ----
    wire uart_irq_rx, uart_irq_tx;
    uart u_uart (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        .s_axi_awaddr_i   (s5_awaddr),  .s_axi_awvalid_i(s5_awvalid),  .s_axi_awready_o(s5_awready),
        .s_axi_wdata_i    (s5_wdata),   .s_axi_wstrb_i(s5_wstrb),     .s_axi_wvalid_i(s5_wvalid),    .s_axi_wready_o(s5_wready),
        .s_axi_bresp_o    (s5_bresp),   .s_axi_bvalid_o(s5_bvalid),   .s_axi_bready_i(s5_bready),
        .s_axi_araddr_i   (s5_araddr),  .s_axi_arvalid_i(s5_arvalid), .s_axi_arready_o(s5_arready),
        .s_axi_rdata_o    (s5_rdata),   .s_axi_rresp_o(s5_rresp),     .s_axi_rvalid_o(s5_rvalid),    .s_axi_rready_i(s5_rready),
        .tx_o             (uart_tx_o),
        .rx_i             (uart_rx_i),
        .irq_rx_o         (uart_irq_rx),
        .irq_tx_o         (uart_irq_tx)
    );

    // ---- GPIO ----
    wire [7:0] gpio_irq_lines;
    wire       gpio_alert;
    wire       force_shutdown_cdc;
    gpio u_gpio (
        .clk_i              (sys_clk_i),
        .rst_n_i            (sys_rst_n),
        .s_axi_awaddr_i     (s6_awaddr),  .s_axi_awvalid_i(s6_awvalid),  .s_axi_awready_o(s6_awready),
        .s_axi_wdata_i      (s6_wdata),   .s_axi_wstrb_i(s6_wstrb),     .s_axi_wvalid_i(s6_wvalid),    .s_axi_wready_o(s6_wready),
        .s_axi_bresp_o      (s6_bresp),   .s_axi_bvalid_o(s6_bvalid),   .s_axi_bready_i(s6_bready),
        .s_axi_araddr_i     (s6_araddr),  .s_axi_arvalid_i(s6_arvalid), .s_axi_arready_o(s6_arready),
        .s_axi_rdata_o      (s6_rdata),   .s_axi_rresp_o(s6_rresp),     .s_axi_rvalid_o(s6_rvalid),    .s_axi_rready_i(s6_rready),
        .gpio_io            (gpio_io),
        .irq_o              (gpio_irq_lines),
        .force_shutdown_i   (force_shutdown_cdc),
        .alert_o            (gpio_alert)
    );

    // =========================================================================
    // Safety Subsystem
    // =========================================================================

    // ---- Lockstep Comparator (v2: dual-core, master+checker inputs) ----
    wire ls_mismatch;
    wire [31:0] ls_mismatch_pc, ls_last_out, ls_last_exp, ls_count;
    wire [31:0] ls_master_out, ls_checker_out;
    wire [3:0]  ls_threshold;
    wire ls_en, ls_delay_en;
    wire [1:0] ls_delay;
    wire [31:0] ls_mask;

    assign ls_threshold = 4'd0;  // Any mismatch triggers immediately

    lockstep_comparator u_lockstep (
        .clk_i              (sys_clk_i),
        .rst_n_i            (sys_rst_n),
        .master_outputs_i   (ls_test_outputs),
        .master_pc_i        (ls_test_pc),
        .master_valid_i     (ls_test_valid),
        .checker_outputs_i  (ls_test_checker_outputs),
        .checker_pc_i       (ls_test_checker_pc),
        .checker_valid_i    (ls_test_checker_valid),
        .enable_i           (ls_en),
        .mask_i             (ls_mask),
        .threshold_i        (ls_threshold),
        .mismatch_o         (ls_mismatch),
        .mismatch_pc_o      (ls_mismatch_pc),
        .mismatch_count_o   (ls_count),
        .master_output_o    (ls_master_out),
        .checker_output_o   (ls_checker_out)
    );

    // Bridge: new lockstep outputs → fault_aggregator legacy names
    assign ls_last_out = ls_master_out;
    assign ls_last_exp = ls_checker_out;

    // ---- CDC: WDT Fault → sys_clk (CDC-02: 2FF) ----
    wire wdt_fault_wdtclk;
    (* ASYNC_REG = "TRUE" *) reg wdt_fault_sync0, wdt_fault_sync1;
    wire wdt_fault_sysclk;

    always @(posedge sys_clk_i or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wdt_fault_sync0 <= 1'b0;
            wdt_fault_sync1 <= 1'b0;
        end else begin
            wdt_fault_sync0 <= wdt_fault_wdtclk;
            wdt_fault_sync1 <= wdt_fault_sync0;
        end
    end
    assign wdt_fault_sysclk = wdt_fault_sync1;

    // ---- CDC: WDT Prewarn → sys_clk (CDC-04: Pulse Sync) ----
    wire wdt_prewarn_wdtclk;
    reg wdt_prewarn_toggle;

    always @(posedge wdt_clk_i or negedge wdt_rst_n) begin
        if (!wdt_rst_n)
            wdt_prewarn_toggle <= 1'b0;
        else if (wdt_prewarn_wdtclk)
            wdt_prewarn_toggle <= ~wdt_prewarn_toggle;
    end

    (* ASYNC_REG = "TRUE" *) reg prewarn_sync0, prewarn_sync1, prewarn_sync2;
    wire wdt_prewarn_sysclk;

    always @(posedge sys_clk_i or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            prewarn_sync0 <= 1'b0;
            prewarn_sync1 <= 1'b0;
            prewarn_sync2 <= 1'b0;
        end else begin
            prewarn_sync0 <= wdt_prewarn_toggle;
            prewarn_sync1 <= prewarn_sync0;
            prewarn_sync2 <= prewarn_sync1;
        end
    end
    assign wdt_prewarn_sysclk = prewarn_sync1 ^ prewarn_sync2;

    // ---- Fault Aggregator (Safety Control Registers) ----
    wire fault_agg_out_w;
    wire fault_core_halt;
    wire fault_irq_lockstep, fault_irq_agg;

    fault_aggregator u_fault_agg (
        .clk_i                (sys_clk_i),
        .rst_n_i              (sys_rst_n),
        .s_axi_awaddr_i       (s7_awaddr),  .s_axi_awvalid_i(s7_awvalid),  .s_axi_awready_o(s7_awready),
        .s_axi_wdata_i        (s7_wdata),   .s_axi_wstrb_i(s7_wstrb),     .s_axi_wvalid_i(s7_wvalid),    .s_axi_wready_o(s7_wready),
        .s_axi_bresp_o        (s7_bresp),   .s_axi_bvalid_o(s7_bvalid),   .s_axi_bready_i(s7_bready),
        .s_axi_araddr_i       (s7_araddr),  .s_axi_arvalid_i(s7_arvalid), .s_axi_arready_o(s7_arready),
        .s_axi_rdata_o        (s7_rdata),   .s_axi_rresp_o(s7_rresp),     .s_axi_rvalid_o(s7_rvalid),    .s_axi_rready_i(s7_rready),
        .lockstep_mismatch_i  (ls_mismatch),
        .wdt_fault_i          (wdt_fault_sysclk),
        .servo_fault_i        (servo_fault),
        .ai_fault_i           (ai_fault),
        .spi_fault_i          (spi_fault),
        .speed_fault_i        (speed_fault),
        .itcm_parity_err_i    (1'b0),
        .dtcm_parity_err_i    (1'b0),
        .lockstep_mismatch_pc_i(ls_mismatch_pc),
        .lockstep_last_out_i  (ls_last_out),
        .lockstep_last_exp_i  (ls_last_exp),
        .lockstep_count_i     (ls_count),
        .aggregated_fault_o   (fault_agg_out_w),
        .core_halt_o          (fault_core_halt),
        .irq_lockstep_o       (fault_irq_lockstep),
        .irq_fault_agg_o      (fault_irq_agg),
        .lockstep_en_o        (ls_en),
        .lockstep_delay_en_o  (ls_delay_en),
        .lockstep_delay_o     (ls_delay),
        .lockstep_mask_o      (ls_mask)
    );

    // ---- CDC: Aggregated Fault → wdt_clk (CDC-03: 3FF) ----
    (* ASYNC_REG = "TRUE" *) reg agg_fault_sync0, agg_fault_sync1, agg_fault_sync2;
    wire agg_fault_wdtclk;

    always @(posedge wdt_clk_i or negedge wdt_rst_n) begin
        if (!wdt_rst_n) begin
            agg_fault_sync0 <= 1'b0;
            agg_fault_sync1 <= 1'b0;
            agg_fault_sync2 <= 1'b0;
        end else begin
            agg_fault_sync0 <= fault_agg_out_w;
            agg_fault_sync1 <= agg_fault_sync0;
            agg_fault_sync2 <= agg_fault_sync1;
        end
    end
    assign agg_fault_wdtclk = agg_fault_sync2;

    // ---- CDC-01: AXI → WDT (2FF per signal) ----
    `define CDC_2FF(sig) \
        (* ASYNC_REG = "TRUE" *) reg sig``_sync0, sig``_sync1; \
        always @(posedge wdt_clk_i or negedge wdt_rst_n) begin \
            if (!wdt_rst_n) begin sig``_sync0 <= 1'b0; sig``_sync1 <= 1'b0; end \
            else begin sig``_sync0 <= sig; sig``_sync1 <= sig``_sync0; end \
        end \
        wire sig``_wdtclk = sig``_sync1;

    `CDC_2FF(s8_awvalid)
    `CDC_2FF(s8_wvalid)
    `CDC_2FF(s8_bready)
    `CDC_2FF(s8_arvalid)
    `CDC_2FF(s8_rready)

    (* ASYNC_REG = "TRUE" *) reg [31:0] s8_awaddr_sync0, s8_awaddr_sync1;
    (* ASYNC_REG = "TRUE" *) reg [31:0] s8_wdata_sync0,  s8_wdata_sync1;
    (* ASYNC_REG = "TRUE" *) reg [3:0]  s8_wstrb_sync0,  s8_wstrb_sync1;

    always @(posedge wdt_clk_i or negedge wdt_rst_n) begin
        if (!wdt_rst_n) begin
            s8_awaddr_sync0 <= 32'd0; s8_awaddr_sync1 <= 32'd0;
            s8_wdata_sync0  <= 32'd0; s8_wdata_sync1  <= 32'd0;
            s8_wstrb_sync0  <= 4'd0;  s8_wstrb_sync1  <= 4'd0;
        end else begin
            s8_awaddr_sync0 <= s8_awaddr; s8_awaddr_sync1 <= s8_awaddr_sync0;
            s8_wdata_sync0  <= s8_wdata;  s8_wdata_sync1  <= s8_wdata_sync0;
            s8_wstrb_sync0  <= s8_wstrb;  s8_wstrb_sync1  <= s8_wstrb_sync0;
        end
    end

    // ---- Window WDT (wdt_clk domain) ----
    wdt u_wdt (
        .clk_i            (wdt_clk_i),
        .rst_n_i          (wdt_rst_n),
        .s_axi_awaddr_i   (s8_awaddr_sync1),
        .s_axi_awvalid_i  (s8_awvalid_wdtclk),
        .s_axi_awready_o  (s8_awready),
        .s_axi_wdata_i    (s8_wdata_sync1),
        .s_axi_wstrb_i    (s8_wstrb_sync1),
        .s_axi_wvalid_i   (s8_wvalid_wdtclk),
        .s_axi_wready_o   (s8_wready),
        .s_axi_bresp_o    (s8_bresp),
        .s_axi_bvalid_o   (s8_bvalid),
        .s_axi_bready_i   (s8_bready_wdtclk),
        .s_axi_araddr_i   (s8_awaddr_sync1),
        .s_axi_arvalid_i  (s8_arvalid_wdtclk),
        .s_axi_arready_o  (s8_arready),
        .s_axi_rdata_o    (s8_rdata),
        .s_axi_rresp_o    (s8_rresp),
        .s_axi_rvalid_o   (s8_rvalid),
        .s_axi_rready_i   (s8_rready_wdtclk),
        .fault_o          (wdt_fault_wdtclk),
        .prewarn_o        (wdt_prewarn_wdtclk)
    );

    // ---- Redundant Shutdown Controller (wdt_clk domain) ----
    wire rsc_force_shutdown;
    redundant_shutdown u_rsc (
        .clk_i                (wdt_clk_i),
        .rst_n_i              (wdt_rst_n),
        .aggregated_fault_i   (agg_fault_wdtclk),
        .force_shutdown_sw_i  (1'b0),
        .shutdown_n_o         (shutdown_n_o),
        .alert_n_o            (alert_n_o),
        .force_shutdown_o     (rsc_force_shutdown)
    );

    // ---- CDC: RSC force_shutdown → sys_clk (CDC-05: 2FF) ----
    (* ASYNC_REG = "TRUE" *) reg rsc_shdn_sync0, rsc_shdn_sync1;
    always @(posedge sys_clk_i or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rsc_shdn_sync0 <= 1'b0;
            rsc_shdn_sync1 <= 1'b0;
        end else begin
            rsc_shdn_sync0 <= rsc_force_shutdown;
            rsc_shdn_sync1 <= rsc_shdn_sync0;
        end
    end
    assign force_shutdown_cdc = rsc_shdn_sync1;

    // =========================================================================
    // Interrupt Assembly
    // =========================================================================
    wire [15:0] core_irq;
    assign core_irq[0]  = spi_irq_rx;
    assign core_irq[1]  = spi_irq_tx;
    assign core_irq[2]  = spi_irq_err;
    assign core_irq[3]  = servo_irq_fault;
    assign core_irq[4]  = speed_irq_pulse;
    assign core_irq[5]  = speed_irq_ovf;
    assign core_irq[6]  = buzzer_irq_done_w;
    assign core_irq[7]  = uart_irq_rx;
    assign core_irq[8]  = uart_irq_tx;
    assign core_irq[9]  = |gpio_irq_lines;
    assign core_irq[10] = ai_irq_done_w;
    assign core_irq[11] = ai_irq_error_w;
    assign core_irq[12] = wdt_prewarn_sysclk;
    assign core_irq[13] = fault_irq_lockstep;
    assign core_irq[14] = fault_irq_agg;
    assign core_irq[15] = 1'b0;

    // =========================================================================
    // Observation output assignments
    // =========================================================================
    assign ai_irq_done       = ai_irq_done_w;
    assign ai_irq_error      = ai_irq_error_w;
    assign all_irq_lines     = core_irq;
    assign fault_agg_out     = fault_agg_out_w;
    assign ls_mismatch_obs   = ls_mismatch;
    assign ls_count_obs      = ls_count;
    assign wdt_fault_obs     = wdt_fault_wdtclk;
    assign wdt_prewarn_obs   = wdt_prewarn_wdtclk;
    assign core_halt_obs     = fault_core_halt;
    assign force_shutdown_obs = rsc_force_shutdown;

    `undef CDC_2FF

endmodule
