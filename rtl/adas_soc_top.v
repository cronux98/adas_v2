// ============================================================================
// adas_soc_top.v — ADAS v2 SoC Top-Level Integration
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    Full SoC Top-Level (All Blocks + AXI Bus + Safety Monitor)
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    2 domains — sys_clk (100 MHz) + wdt_clk (32.768 kHz)
//
// Architecture:
//   RV32IM Core → AXI4-Lite Xbar (1M→9S)
//     ├── S0: AI Accelerator   @ 0x0000_1000
//     ├── S1: SPI Controller   @ 0x0000_2000
//     ├── S2: Servo PWM        @ 0x0000_3000
//     ├── S3: Speed Sensor     @ 0x0000_4000
//     ├── S4: Buzzer PWM       @ 0x0000_5000
//     ├── S5: UART             @ 0x0000_6000
//     ├── S6: GPIO             @ 0x0000_7000
//     ├── S7: Fault Aggregator @ 0x0000_F000
//     └── S8: Window WDT       @ 0x0000_F100 (CDC'd)
//
//   Safety Subsystem:
//     Lockstep Comp → Fault Agg → CDC → Redundant Shutdown Ctrl (wdt_clk)
//     WDT Fault → CDC → Fault Agg
//     RSC → shutdown_n_o[1:0], alert_n_o
//
// CDC Crossings (cdc_plan.md):
//   CDC-01: AXI → WDT   (handshake, in wdt_cdc_sys2wdt)
//   CDC-02: WDT → Fault Agg (2FF, in wdt_cdc_wdt2sys)
//   CDC-03: Fault Agg → RSC (3FF redundant, in rsc_cdc)
//   CDC-04: WDT Prewarn → IRQ (pulse sync, in wdt_prewarn_cdc)
//   CDC-05: RSC → GPIO (2FF, in rsc_shdn_cdc)
//   CDC-06: Speed pulse (2FF, internal to speed_sensor)
//   CDC-07: UART RX (3x oversampling, internal to uart)
// ============================================================================

`timescale 1ns / 1ps

module adas_soc_top (
    // Clocks
    input  wire        sys_clk_i,
    input  wire        wdt_clk_i,

    // Resets (async assert, sync de-assert)
    input  wire        sys_rst_n_i,
    input  wire        wdt_rst_n_i,

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
    input  wire        test_mode_i
);

    // =========================================================================
    // Internal Reset Distribution
    // =========================================================================
    wire sys_rst_n  = sys_rst_n_i;
    wire wdt_rst_n  = wdt_rst_n_i;

    // =========================================================================
    // ITCM / DTCM (8KB each)
    // =========================================================================
    wire [12:0] itcm_addr;
    wire [31:0] itcm_rdata;
    wire        itcm_req;
    wire        itcm_ack;
    wire        itcm_ecc_correct;
    wire        itcm_ecc_fatal;

    wire [12:0] dtcm_addr;
    wire [31:0] dtcm_wdata;
    wire [31:0] dtcm_rdata;
    wire [3:0]  dtcm_we;
    wire        dtcm_req;
    wire        dtcm_ack;
    wire        dtcm_ecc_correct;
    wire        dtcm_ecc_fatal;

    // TCM scrubber interface wires
    wire        tcm_scr_req;
    wire [10:0] tcm_scr_addr;
    wire [38:0] tcm_scr_raw;
    wire [38:0] tcm_scr_raw_dtcm;  // DTCM raw readback (scrubber reads ITCM)
    wire        tcm_scr_we;
    wire [31:0] tcm_scr_wdata;
    wire [6:0]  tcm_scr_ecc;

    tcm_8kb u_itcm (
        .clk_i        (sys_clk_i),
        .rst_n_i      (sys_rst_n),
        .addr_i       (itcm_addr),
        .wdata_i      (32'd0),
        .we_i         (4'd0),          // ITCM is read-only at boot
        .req_i        (itcm_req),
        .rdata_o      (itcm_rdata),
        .ack_o        (itcm_ack),
        .ecc_err_correct_o (itcm_ecc_correct),
        .ecc_err_fatal_o   (itcm_ecc_fatal),
        .scr_req_i    (tcm_scr_req),
        .scr_addr_i   (tcm_scr_addr),
        .scr_raw_o    (tcm_scr_raw),
        .scr_we_i     (tcm_scr_we),
        .scr_wdata_i  (tcm_scr_wdata),
        .scr_ecc_i    (tcm_scr_ecc)
    );

    tcm_8kb u_dtcm (
        .clk_i        (sys_clk_i),
        .rst_n_i      (sys_rst_n),
        .addr_i       (dtcm_addr),
        .wdata_i      (dtcm_wdata),
        .we_i         (dtcm_we),
        .req_i        (dtcm_req),
        .rdata_o      (dtcm_rdata),
        .ack_o        (dtcm_ack),
        .ecc_err_correct_o (dtcm_ecc_correct),
        .ecc_err_fatal_o   (dtcm_ecc_fatal),
        .scr_req_i    (tcm_scr_req),
        .scr_addr_i   (tcm_scr_addr),
        .scr_raw_o    (tcm_scr_raw_dtcm),
        .scr_we_i     (tcm_scr_we),
        .scr_wdata_i  (tcm_scr_wdata),
        .scr_ecc_i    (tcm_scr_ecc)
    );

    // =========================================================================
    // Dual-Core Lockstep Wrapper (replaces single RV32IM)
    // =========================================================================
    // Per ARCH-AD-001: dual-core time-staggered lockstep for ASIL-D.
    // Core A (master) drives all busses. Core B (checker) trails by 2 cycles.
    // Both cores' lockstep outputs go to the comparator for cycle-by-cycle XOR check.
    wire [31:0] core_axi_awaddr, core_axi_wdata, core_axi_araddr;
    wire [2:0]  core_axi_awprot, core_axi_arprot;
    wire        core_axi_awvalid, core_axi_wvalid, core_axi_bready;
    wire [3:0]  core_axi_wstrb;
    wire        core_axi_awready, core_axi_wready;
    wire [1:0]  core_axi_bresp;
    wire        core_axi_bvalid;
    wire        core_axi_arvalid, core_axi_rready;
    wire        core_axi_arready;
    wire [31:0] core_axi_rdata;
    wire [1:0]  core_axi_rresp;
    wire        core_axi_rvalid;

    // Lockstep outputs: master (Core A, delayed) + checker (Core B, direct)
    wire [31:0] lockstep_outputs_m, lockstep_outputs_c;
    wire [31:0] lockstep_pc_m,      lockstep_pc_c;
    wire        lockstep_valid_m,   lockstep_valid_c;
    wire        core_halt;

    wire [15:0] core_irq;

    dual_lockstep_top u_lockstep_core (
        .clk_i                  (sys_clk_i),
        .rst_n_i                (sys_rst_n),
        .itcm_addr_o            (itcm_addr),
        .itcm_rdata_i           (itcm_rdata),
        .itcm_req_o             (itcm_req),
        .itcm_ack_i             (itcm_ack),
        .dtcm_addr_o            (dtcm_addr),
        .dtcm_wdata_o           (dtcm_wdata),
        .dtcm_rdata_i           (dtcm_rdata),
        .dtcm_we_o              (dtcm_we),
        .dtcm_req_o             (dtcm_req),
        .dtcm_ack_i             (dtcm_ack),
        .m_axi_awaddr_o         (core_axi_awaddr),
        .m_axi_awprot_o         (core_axi_awprot),
        .m_axi_awvalid_o        (core_axi_awvalid),
        .m_axi_awready_i        (core_axi_awready),
        .m_axi_wdata_o          (core_axi_wdata),
        .m_axi_wstrb_o          (core_axi_wstrb),
        .m_axi_wvalid_o         (core_axi_wvalid),
        .m_axi_wready_i         (core_axi_wready),
        .m_axi_bresp_i          (core_axi_bresp),
        .m_axi_bvalid_i         (core_axi_bvalid),
        .m_axi_bready_o         (core_axi_bready),
        .m_axi_araddr_o         (core_axi_araddr),
        .m_axi_arprot_o         (core_axi_arprot),
        .m_axi_arvalid_o        (core_axi_arvalid),
        .m_axi_arready_i        (core_axi_arready),
        .m_axi_rdata_i          (core_axi_rdata),
        .m_axi_rresp_i          (core_axi_rresp),
        .m_axi_rvalid_i         (core_axi_rvalid),
        .m_axi_rready_o         (core_axi_rready),
        .irq_i                  (core_irq),
        .timer_irq_i            (1'b0),
        .lockstep_outputs_m_o   (lockstep_outputs_m),
        .lockstep_pc_m_o        (lockstep_pc_m),
        .lockstep_valid_m_o     (lockstep_valid_m),
        .lockstep_outputs_c_o   (lockstep_outputs_c),
        .lockstep_pc_c_o        (lockstep_pc_c),
        .lockstep_valid_c_o     (lockstep_valid_c),
        .halt_i                 (core_halt),
        .debug_req_i            (1'b0)
    );

    // =========================================================================
    // AXI4-Lite Crossbar
    // =========================================================================
    // Slave 0 — AI Accelerator
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

    // Slave 1 — SPI
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

    // Slave 2 — Servo
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

    // Slave 3 — Speed
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

    // Slave 4 — Buzzer
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

    // Slave 5 — UART
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

    // Slave 6 — GPIO
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

    // Slave 7 — Fault Aggregator (Safety Control)
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

    // Slave 8 — Window WDT
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

    axi4_lite_interconnect u_axi_xbar (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        // Master
        .m_axi_awaddr_i   (core_axi_awaddr),
        .m_axi_awprot_i   (core_axi_awprot),
        .m_axi_awvalid_i  (core_axi_awvalid),
        .m_axi_awready_o  (core_axi_awready),
        .m_axi_wdata_i    (core_axi_wdata),
        .m_axi_wstrb_i    (core_axi_wstrb),
        .m_axi_wvalid_i   (core_axi_wvalid),
        .m_axi_wready_o   (core_axi_wready),
        .m_axi_bresp_o    (core_axi_bresp),
        .m_axi_bvalid_o   (core_axi_bvalid),
        .m_axi_bready_i   (core_axi_bready),
        .m_axi_araddr_i   (core_axi_araddr),
        .m_axi_arprot_i   (core_axi_arprot),
        .m_axi_arvalid_i  (core_axi_arvalid),
        .m_axi_arready_o  (core_axi_arready),
        .m_axi_rdata_o    (core_axi_rdata),
        .m_axi_rresp_o    (core_axi_rresp),
        .m_axi_rvalid_o   (core_axi_rvalid),
        .m_axi_rready_i   (core_axi_rready),
        // Slave 0
        .s0_axi_awaddr_o  (s0_awaddr),  .s0_axi_awprot_o(s0_awprot), .s0_axi_awvalid_o(s0_awvalid),  .s0_axi_awready_i(s0_awready),
        .s0_axi_wdata_o   (s0_wdata),   .s0_axi_wstrb_o(s0_wstrb),   .s0_axi_wvalid_o(s0_wvalid),    .s0_axi_wready_i(s0_wready),
        .s0_axi_bresp_i   (s0_bresp),   .s0_axi_bvalid_i(s0_bvalid), .s0_axi_bready_o(s0_bready),
        .s0_axi_araddr_o  (s0_araddr),  .s0_axi_arprot_o(s0_arprot), .s0_axi_arvalid_o(s0_arvalid),  .s0_axi_arready_i(s0_arready),
        .s0_axi_rdata_i   (s0_rdata),   .s0_axi_rresp_i(s0_rresp),   .s0_axi_rvalid_i(s0_rvalid),    .s0_axi_rready_o(s0_rready),
        // Slave 1
        .s1_axi_awaddr_o  (s1_awaddr),  .s1_axi_awprot_o(s1_awprot), .s1_axi_awvalid_o(s1_awvalid),  .s1_axi_awready_i(s1_awready),
        .s1_axi_wdata_o   (s1_wdata),   .s1_axi_wstrb_o(s1_wstrb),   .s1_axi_wvalid_o(s1_wvalid),    .s1_axi_wready_i(s1_wready),
        .s1_axi_bresp_i   (s1_bresp),   .s1_axi_bvalid_i(s1_bvalid), .s1_axi_bready_o(s1_bready),
        .s1_axi_araddr_o  (s1_araddr),  .s1_axi_arprot_o(s1_arprot), .s1_axi_arvalid_o(s1_arvalid),  .s1_axi_arready_i(s1_arready),
        .s1_axi_rdata_i   (s1_rdata),   .s1_axi_rresp_i(s1_rresp),   .s1_axi_rvalid_i(s1_rvalid),    .s1_axi_rready_o(s1_rready),
        // Slave 2
        .s2_axi_awaddr_o  (s2_awaddr),  .s2_axi_awprot_o(s2_awprot), .s2_axi_awvalid_o(s2_awvalid),  .s2_axi_awready_i(s2_awready),
        .s2_axi_wdata_o   (s2_wdata),   .s2_axi_wstrb_o(s2_wstrb),   .s2_axi_wvalid_o(s2_wvalid),    .s2_axi_wready_i(s2_wready),
        .s2_axi_bresp_i   (s2_bresp),   .s2_axi_bvalid_i(s2_bvalid), .s2_axi_bready_o(s2_bready),
        .s2_axi_araddr_o  (s2_araddr),  .s2_axi_arprot_o(s2_arprot), .s2_axi_arvalid_o(s2_arvalid),  .s2_axi_arready_i(s2_arready),
        .s2_axi_rdata_i   (s2_rdata),   .s2_axi_rresp_i(s2_rresp),   .s2_axi_rvalid_i(s2_rvalid),    .s2_axi_rready_o(s2_rready),
        // Slave 3
        .s3_axi_awaddr_o  (s3_awaddr),  .s3_axi_awprot_o(s3_awprot), .s3_axi_awvalid_o(s3_awvalid),  .s3_axi_awready_i(s3_awready),
        .s3_axi_wdata_o   (s3_wdata),   .s3_axi_wstrb_o(s3_wstrb),   .s3_axi_wvalid_o(s3_wvalid),    .s3_axi_wready_i(s3_wready),
        .s3_axi_bresp_i   (s3_bresp),   .s3_axi_bvalid_i(s3_bvalid), .s3_axi_bready_o(s3_bready),
        .s3_axi_araddr_o  (s3_araddr),  .s3_axi_arprot_o(s3_arprot), .s3_axi_arvalid_o(s3_arvalid),  .s3_axi_arready_i(s3_arready),
        .s3_axi_rdata_i   (s3_rdata),   .s3_axi_rresp_i(s3_rresp),   .s3_axi_rvalid_i(s3_rvalid),    .s3_axi_rready_o(s3_rready),
        // Slave 4
        .s4_axi_awaddr_o  (s4_awaddr),  .s4_axi_awprot_o(s4_awprot), .s4_axi_awvalid_o(s4_awvalid),  .s4_axi_awready_i(s4_awready),
        .s4_axi_wdata_o   (s4_wdata),   .s4_axi_wstrb_o(s4_wstrb),   .s4_axi_wvalid_o(s4_wvalid),    .s4_axi_wready_i(s4_wready),
        .s4_axi_bresp_i   (s4_bresp),   .s4_axi_bvalid_i(s4_bvalid), .s4_axi_bready_o(s4_bready),
        .s4_axi_araddr_o  (s4_araddr),  .s4_axi_arprot_o(s4_arprot), .s4_axi_arvalid_o(s4_arvalid),  .s4_axi_arready_i(s4_arready),
        .s4_axi_rdata_i   (s4_rdata),   .s4_axi_rresp_i(s4_rresp),   .s4_axi_rvalid_i(s4_rvalid),    .s4_axi_rready_o(s4_rready),
        // Slave 5
        .s5_axi_awaddr_o  (s5_awaddr),  .s5_axi_awprot_o(s5_awprot), .s5_axi_awvalid_o(s5_awvalid),  .s5_axi_awready_i(s5_awready),
        .s5_axi_wdata_o   (s5_wdata),   .s5_axi_wstrb_o(s5_wstrb),   .s5_axi_wvalid_o(s5_wvalid),    .s5_axi_wready_i(s5_wready),
        .s5_axi_bresp_i   (s5_bresp),   .s5_axi_bvalid_i(s5_bvalid), .s5_axi_bready_o(s5_bready),
        .s5_axi_araddr_o  (s5_araddr),  .s5_axi_arprot_o(s5_arprot), .s5_axi_arvalid_o(s5_arvalid),  .s5_axi_arready_i(s5_arready),
        .s5_axi_rdata_i   (s5_rdata),   .s5_axi_rresp_i(s5_rresp),   .s5_axi_rvalid_i(s5_rvalid),    .s5_axi_rready_o(s5_rready),
        // Slave 6
        .s6_axi_awaddr_o  (s6_awaddr),  .s6_axi_awprot_o(s6_awprot), .s6_axi_awvalid_o(s6_awvalid),  .s6_axi_awready_i(s6_awready),
        .s6_axi_wdata_o   (s6_wdata),   .s6_axi_wstrb_o(s6_wstrb),   .s6_axi_wvalid_o(s6_wvalid),    .s6_axi_wready_i(s6_wready),
        .s6_axi_bresp_i   (s6_bresp),   .s6_axi_bvalid_i(s6_bvalid), .s6_axi_bready_o(s6_bready),
        .s6_axi_araddr_o  (s6_araddr),  .s6_axi_arprot_o(s6_arprot), .s6_axi_arvalid_o(s6_arvalid),  .s6_axi_arready_i(s6_arready),
        .s6_axi_rdata_i   (s6_rdata),   .s6_axi_rresp_i(s6_rresp),   .s6_axi_rvalid_i(s6_rvalid),    .s6_axi_rready_o(s6_rready),
        // Slave 7
        .s7_axi_awaddr_o  (s7_awaddr),  .s7_axi_awprot_o(s7_awprot), .s7_axi_awvalid_o(s7_awvalid),  .s7_axi_awready_i(s7_awready),
        .s7_axi_wdata_o   (s7_wdata),   .s7_axi_wstrb_o(s7_wstrb),   .s7_axi_wvalid_o(s7_wvalid),    .s7_axi_wready_i(s7_wready),
        .s7_axi_bresp_i   (s7_bresp),   .s7_axi_bvalid_i(s7_bvalid), .s7_axi_bready_o(s7_bready),
        .s7_axi_araddr_o  (s7_araddr),  .s7_axi_arprot_o(s7_arprot), .s7_axi_arvalid_o(s7_arvalid),  .s7_axi_arready_i(s7_arready),
        .s7_axi_rdata_i   (s7_rdata),   .s7_axi_rresp_i(s7_rresp),   .s7_axi_rvalid_i(s7_rvalid),    .s7_axi_rready_o(s7_rready),
        // Slave 8
        .s8_axi_awaddr_o  (s8_awaddr),  .s8_axi_awprot_o(s8_awprot), .s8_axi_awvalid_o(s8_awvalid),  .s8_axi_awready_i(s8_awready),
        .s8_axi_wdata_o   (s8_wdata),   .s8_axi_wstrb_o(s8_wstrb),   .s8_axi_wvalid_o(s8_wvalid),    .s8_axi_wready_i(s8_wready),
        .s8_axi_bresp_i   (s8_bresp),   .s8_axi_bvalid_i(s8_bvalid), .s8_axi_bready_o(s8_bready),
        .s8_axi_araddr_o  (s8_araddr),  .s8_axi_arprot_o(s8_arprot), .s8_axi_arvalid_o(s8_arvalid),  .s8_axi_arready_i(s8_arready),
        .s8_axi_rdata_i   (s8_rdata),   .s8_axi_rresp_i(s8_rresp),   .s8_axi_rvalid_i(s8_rvalid),    .s8_axi_rready_o(s8_rready)
    );

    // =========================================================================
    // Peripheral Blocks
    // =========================================================================

    // ---- AI Accelerator (existing) ----
    wire ai_irq_done, ai_irq_error, ai_fault;

    ai_accel_4x4 u_ai_accel (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        .s_axi_awaddr_i   (s0_awaddr),  .s_axi_awvalid_i(s0_awvalid),  .s_axi_awready_o(s0_awready),
        .s_axi_wdata_i    (s0_wdata),   .s_axi_wstrb_i(s0_wstrb),     .s_axi_wvalid_i(s0_wvalid),    .s_axi_wready_o(s0_wready),
        .s_axi_bresp_o    (s0_bresp),   .s_axi_bvalid_o(s0_bvalid),   .s_axi_bready_i(s0_bready),
        .s_axi_araddr_i   (s0_araddr),  .s_axi_arvalid_i(s0_arvalid), .s_axi_arready_o(s0_arready),
        .s_axi_rdata_o    (s0_rdata),   .s_axi_rresp_o(s0_rresp),     .s_axi_rvalid_o(s0_rvalid),    .s_axi_rready_i(s0_rready),
        .irq_done_o       (ai_irq_done),
        .irq_error_o      (ai_irq_error),
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
    wire buzzer_irq_done;

    buzzer_pwm u_buzzer (
        .clk_i            (sys_clk_i),
        .rst_n_i          (sys_rst_n),
        .s_axi_awaddr_i   (s4_awaddr),  .s_axi_awvalid_i(s4_awvalid),  .s_axi_awready_o(s4_awready),
        .s_axi_wdata_i    (s4_wdata),   .s_axi_wstrb_i(s4_wstrb),     .s_axi_wvalid_i(s4_wvalid),    .s_axi_wready_o(s4_wready),
        .s_axi_bresp_o    (s4_bresp),   .s_axi_bvalid_o(s4_bvalid),   .s_axi_bready_i(s4_bready),
        .s_axi_araddr_i   (s4_araddr),  .s_axi_arvalid_i(s4_arvalid), .s_axi_arready_o(s4_arready),
        .s_axi_rdata_o    (s4_rdata),   .s_axi_rresp_o(s4_rresp),     .s_axi_rvalid_o(s4_rvalid),    .s_axi_rready_i(s4_rready),
        .pwm_o            (buzzer_pwm_o),
        .irq_done_o       (buzzer_irq_done)
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
    wire       force_shutdown_cdc;  // from RSC, CDC'd to GPIO

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

    // ---- Dual-Core Lockstep Comparator ----
    // Per ARCH-AD-001: simple dual-input XOR comparison (no delay pipeline).
    // Master outputs are already delay-compensated by dual_lockstep_top.
    wire ls_mismatch;
    wire [31:0] ls_mismatch_pc, ls_master_out, ls_checker_out, ls_count;

    wire        ls_en;
    wire [31:0] ls_mask;
    wire        ls_self_test;  // P0-5: lockstep comparator self-test pulse
    // THRESHOLD: fire on first mismatch (0). Should be connected to
    // SAFETY_LOCKSTEP_CTRL[7:4] via fault_aggregator in a future revision.
    wire [3:0]  ls_threshold = 4'd0;

    lockstep_comparator u_lockstep (
        .clk_i              (sys_clk_i),
        .rst_n_i            (sys_rst_n),
        .master_outputs_i   (lockstep_outputs_m),
        .master_pc_i        (lockstep_pc_m),
        .master_valid_i     (lockstep_valid_m),
        .checker_outputs_i  (lockstep_outputs_c),
        .checker_pc_i       (lockstep_pc_c),
        .checker_valid_i    (lockstep_valid_c),
        .enable_i           (ls_en),
        .mask_i             (ls_mask),
        .threshold_i        (ls_threshold),
        .self_test_i        (ls_self_test),  // P0-5: comparator self-test
        .mismatch_o         (ls_mismatch),
        .mismatch_pc_o      (ls_mismatch_pc),
        .mismatch_count_o   (ls_count),
        .master_output_o    (ls_master_out),
        .checker_output_o   (ls_checker_out)
    );

    // ---- CDC: WDT Fault → sys_clk (CDC-02: 2FF) ----
    wire wdt_fault_wdtclk;    // from WDT (wdt_clk domain)
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
    reg wdt_prewarn_toggle;  // toggle FF in wdt_clk domain

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
    assign wdt_prewarn_sysclk = prewarn_sync1 ^ prewarn_sync2;  // edge detect

    // ---- Fault Aggregator (Safety Control Registers) ----
    wire fault_agg_out;
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
        .itcm_parity_err_i    (itcm_ecc_fatal),
        .dtcm_parity_err_i    (dtcm_ecc_fatal),
        .lockstep_mismatch_pc_i(ls_mismatch_pc),
        .lockstep_last_out_i  (ls_master_out),
        .lockstep_last_exp_i  (ls_checker_out),
        .lockstep_count_i     (ls_count),
        .aggregated_fault_o   (fault_agg_out),
        .core_halt_o          (fault_core_halt),
        .irq_lockstep_o       (fault_irq_lockstep),
        .irq_fault_agg_o      (fault_irq_agg),
        .lockstep_en_o        (ls_en),
        /* verilator lint_off PINCONNECTEMPTY */
        .lockstep_delay_en_o  (),                     // unused in dual-core
        .lockstep_delay_o     (),                     // unused in dual-core
        /* verilator lint_on PINCONNECTEMPTY */
        .lockstep_mask_o      (ls_mask),
        .lockstep_self_test_o (ls_self_test)  // P0-5
    );

    assign core_halt = fault_core_halt;

    // ---- CDC: Aggregated Fault → wdt_clk (CDC-03: Dual-Redundant 3FF) ----
    // O-05 FIX: Dual-redundant CDC per cdc_plan.md §5.5.
    // Two independent 3FF synchronizer chains; outputs are compared.
    // Mismatch indicates a synchronizer failure (safety-critical).
    //
    // Primary path: 3FF
    (* ASYNC_REG = "TRUE" *) reg agg_fault_sync0, agg_fault_sync1, agg_fault_sync2;
    // Redundant path: 3FF (independent physical wiring intent)
    (* ASYNC_REG = "TRUE" *) reg agg_fault_red_sync0, agg_fault_red_sync1, agg_fault_red_sync2;

    wire agg_fault_wdtclk_pri;
    wire agg_fault_wdtclk_red;
    wire agg_fault_wdtclk;
    wire cdc03_mismatch;   // asserted when redundant paths disagree

    always @(posedge wdt_clk_i or negedge wdt_rst_n) begin
        if (!wdt_rst_n) begin
            agg_fault_sync0     <= 1'b0; agg_fault_sync1     <= 1'b0; agg_fault_sync2     <= 1'b0;
            agg_fault_red_sync0 <= 1'b0; agg_fault_red_sync1 <= 1'b0; agg_fault_red_sync2 <= 1'b0;
        end else begin
            // Primary path
            agg_fault_sync0 <= fault_agg_out;
            agg_fault_sync1 <= agg_fault_sync0;
            agg_fault_sync2 <= agg_fault_sync1;
            // Redundant path (physically separate — same source, independent sync chain)
            agg_fault_red_sync0 <= fault_agg_out;
            agg_fault_red_sync1 <= agg_fault_red_sync0;
            agg_fault_red_sync2 <= agg_fault_red_sync1;
        end
    end

    assign agg_fault_wdtclk_pri = agg_fault_sync2;
    assign agg_fault_wdtclk_red = agg_fault_red_sync2;
    // Conservative: fault is asserted if either path says so (fail-safe)
    assign agg_fault_wdtclk     = agg_fault_wdtclk_pri || agg_fault_wdtclk_red;
    // Diagnostics: mismatch indicates synchronizer failure
    assign cdc03_mismatch        = agg_fault_wdtclk_pri ^ agg_fault_wdtclk_red;

    // =========================================================================
    // CDC-01: AXI → WDT Handshake Synchronizer (O-04 FIX)
    // =========================================================================
    // Replaces simple 2FF with proper req/ack handshake per cdc_plan.md §4.1.
    //
    // Protocol:
    //   1. sys_clk: Detect AXI transaction (awvalid or arvalid)
    //   2. sys_clk: Assert req, hold addr/data/strobe stable
    //   3. wdt_clk: 2FF samples req → detect rising edge
    //   4. wdt_clk: Latch all AXI signals on req edge
    //   5. wdt_clk: Drive to WDT, wait for transaction to complete
    //   6. wdt_clk: Assert ack
    //   7. sys_clk: 2FF samples ack → drive ready to AXI master
    //   8. sys_clk: De-assert req
    //   9. wdt_clk: See req de-assertion → de-assert ack
    //  10. sys_clk: See ack de-assertion → cycle complete

    // ---- sys_clk domain: CDC-01 Handshake FSM ----
    reg [1:0]  wdt_hs_state;          // 0=IDLE, 1=TXN_PEND, 2=WAIT_ACK_LO
    reg        wdt_hs_req;            // request to wdt_clk
    reg        wdt_hs_is_write;       // 1=write, 0=read
    reg [31:0] wdt_hs_awaddr_held;    // held stable during handshake
    reg [31:0] wdt_hs_wdata_held;
    reg [3:0]  wdt_hs_wstrb_held;
    reg [31:0] wdt_hs_araddr_held;    // O-03 FIX: dedicated read address

    always @(posedge sys_clk_i or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wdt_hs_state      <= 2'd0;
            wdt_hs_req        <= 1'b0;
            wdt_hs_is_write   <= 1'b0;
            wdt_hs_awaddr_held<= 32'd0;
            wdt_hs_wdata_held <= 32'd0;
            wdt_hs_wstrb_held <= 4'd0;
            wdt_hs_araddr_held<= 32'd0;
        end else begin
            case (wdt_hs_state)
                2'd0: begin  // IDLE — wait for AXI transaction
                    if (s8_awvalid) begin
                        // Write transaction detected
                        wdt_hs_is_write    <= 1'b1;
                        wdt_hs_awaddr_held <= s8_awaddr;
                        wdt_hs_wdata_held  <= s8_wdata;
                        wdt_hs_wstrb_held  <= s8_wstrb;
                        wdt_hs_req         <= 1'b1;
                        wdt_hs_state       <= 2'd1;
                    end else if (s8_arvalid) begin
                        // Read transaction detected
                        wdt_hs_is_write    <= 1'b0;
                        wdt_hs_araddr_held <= s8_araddr;
                        wdt_hs_req         <= 1'b1;
                        wdt_hs_state       <= 2'd1;
                    end
                end

                2'd1: begin  // TXN_PEND — wait for ack from wdt_clk
                    if (wdt_ack_sync1) begin
                        // Ack received → drive ready, de-assert req
                        wdt_hs_req   <= 1'b0;
                        wdt_hs_state <= 2'd2;
                    end
                end

                2'd2: begin  // WAIT_ACK_LO — wait for ack to go low
                    if (!wdt_ack_sync1) begin
                        wdt_hs_state <= 2'd0;  // back to IDLE
                    end
                end

                default: wdt_hs_state <= 2'd0;
            endcase
        end
    end

    // AXI ready signals driven from handshake state
    assign s8_awready = (wdt_hs_state == 2'd1) && wdt_hs_is_write  && wdt_ack_sync1;
    assign s8_wready  = (wdt_hs_state == 2'd1) && wdt_hs_is_write  && wdt_ack_sync1;
    assign s8_arready = (wdt_hs_state == 2'd1) && !wdt_hs_is_write && wdt_ack_sync1;

    // ---- wdt_clk domain: req synchronizer (2FF) ----
    (* ASYNC_REG = "TRUE" *) reg wdt_req_sync0, wdt_req_sync1;
    reg wdt_req_sync1_d;  // delayed for edge detection
    wire wdt_req_rising;

    always @(posedge wdt_clk_i or negedge wdt_rst_n) begin
        if (!wdt_rst_n) begin
            wdt_req_sync0   <= 1'b0;
            wdt_req_sync1   <= 1'b0;
            wdt_req_sync1_d <= 1'b0;
        end else begin
            wdt_req_sync0   <= wdt_hs_req;
            wdt_req_sync1   <= wdt_req_sync0;
            wdt_req_sync1_d <= wdt_req_sync1;
        end
    end
    assign wdt_req_rising = wdt_req_sync1 && !wdt_req_sync1_d;

    // ---- wdt_clk domain: ack synchronizer (2FF back to sys_clk) ----
    (* ASYNC_REG = "TRUE" *) reg wdt_ack_sync0, wdt_ack_sync1;
    reg wdt_ack_wdtclk;   // ack in wdt_clk domain

    always @(posedge sys_clk_i or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wdt_ack_sync0 <= 1'b0;
            wdt_ack_sync1 <= 1'b0;
        end else begin
            wdt_ack_sync0 <= wdt_ack_wdtclk;
            wdt_ack_sync1 <= wdt_ack_sync0;
        end
    end

    // ---- wdt_clk domain: latched AXI signals + WDT transaction control ----
    reg        wdt_latched_valid;   // transaction pending in wdt_clk domain
    reg        wdt_latched_is_write;
    reg [31:0] wdt_latched_awaddr;
    reg [31:0] wdt_latched_wdata;
    reg [3:0]  wdt_latched_wstrb;
    reg [31:0] wdt_latched_araddr;  // O-03 FIX: dedicated read address latch

    // WDT transaction completion tracking
    reg wdt_wr_done;   // write transaction completed
    reg wdt_rd_done;   // read transaction completed
    reg [31:0] wdt_rd_data_latched;
    reg [1:0]  wdt_rd_resp_latched;

    always @(posedge wdt_clk_i or negedge wdt_rst_n) begin
        if (!wdt_rst_n) begin
            wdt_latched_valid    <= 1'b0;
            wdt_latched_is_write <= 1'b0;
            wdt_latched_awaddr   <= 32'd0;
            wdt_latched_wdata    <= 32'd0;
            wdt_latched_wstrb    <= 4'd0;
            wdt_latched_araddr   <= 32'd0;
            wdt_ack_wdtclk       <= 1'b0;
            wdt_wr_done          <= 1'b0;
            wdt_rd_done          <= 1'b0;
            wdt_rd_data_latched  <= 32'd0;
            wdt_rd_resp_latched  <= 2'd0;
        end else begin
            // Latch AXI signals on req rising edge (data is stable per handshake)
            if (wdt_req_rising && wdt_req_sync1) begin
                // Data was sourced from sys_clk domain registers which are stable
                // These arrive via the held registers in sys_clk, synchronized via req
                wdt_latched_awaddr   <= wdt_hs_awaddr_held;
                wdt_latched_wdata    <= wdt_hs_wdata_held;
                wdt_latched_wstrb    <= wdt_hs_wstrb_held;
                wdt_latched_araddr   <= wdt_hs_araddr_held;
                wdt_latched_is_write <= wdt_hs_is_write;
                wdt_latched_valid    <= 1'b1;
            end

            // Write completion: WDT accepts write
            if (wdt_latched_valid && wdt_latched_is_write &&
                s8_awready_wdt && s8_wready_wdt) begin
                wdt_wr_done <= 1'b1;
            end

            // Read completion: WDT returns read data
            if (wdt_latched_valid && !wdt_latched_is_write &&
                s8_rvalid_wdt && wdt_rd_rready_wdt) begin
                wdt_rd_data_latched <= s8_rdata_wdt;
                wdt_rd_resp_latched <= s8_rresp_wdt;
                wdt_rd_done <= 1'b1;
            end

            // Assert ack when transaction completes in wdt_clk domain
            if (wdt_wr_done || wdt_rd_done) begin
                wdt_ack_wdtclk <= 1'b1;
            end

            // De-assert ack when req goes low
            if (!wdt_req_sync1) begin
                wdt_ack_wdtclk       <= 1'b0;
                wdt_latched_valid    <= 1'b0;
                wdt_wr_done          <= 1'b0;
                wdt_rd_done          <= 1'b0;
            end
        end
    end

    // WDT AXI signals driven from latched values or inactive
    wire [31:0] s8_awaddr_wdt;
    wire        s8_awvalid_wdt;
    wire [31:0] s8_wdata_wdt;
    wire [3:0]  s8_wstrb_wdt;
    wire        s8_wvalid_wdt;
    wire        s8_bready_wdt;
    wire [31:0] s8_araddr_wdt;
    wire        s8_arvalid_wdt;
    wire        s8_rready_wdt;
    assign s8_awaddr_wdt  = wdt_latched_valid && wdt_latched_is_write ? wdt_latched_awaddr : 32'd0;
    assign s8_awvalid_wdt = wdt_latched_valid && wdt_latched_is_write;
    assign s8_wdata_wdt   = wdt_latched_wdata;
    assign s8_wstrb_wdt   = wdt_latched_wstrb;
    assign s8_wvalid_wdt  = wdt_latched_valid && wdt_latched_is_write;
    assign s8_bready_wdt  = 1'b1;  // always accept write response

    // O-03 FIX: Dedicated read address bus (was: reused awaddr_sync1)
    assign s8_araddr_wdt  = wdt_latched_valid && !wdt_latched_is_write ? wdt_latched_araddr : 32'd0;
    assign s8_arvalid_wdt = wdt_latched_valid && !wdt_latched_is_write;
    assign s8_rready_wdt  = 1'b1;  // always accept read data

    // AXI response signals back to sys_clk domain (pass-through from WDT)
    // Note: These are in wdt_clk domain and go through the handshake ack path.
    // The sys_clk domain uses wdt_ack_sync1 timing, not these directly.
    wire [31:0] s8_rdata_wdt;
    wire [1:0]  s8_rresp_wdt;
    wire        s8_rvalid_wdt;
    wire [1:0]  s8_bresp_wdt;
    wire        s8_bvalid_wdt;
    wire        s8_awready_wdt;
    wire        s8_wready_wdt;
    wire        s8_arready_wdt;
    wire        wdt_rd_rready_wdt;

    // =========================================================================
    // Window WDT Instantiation (wdt_clk domain)
    // =========================================================================
    // AXI inputs are driven from the handshake-latched signals above.

    wdt u_wdt (
        .clk_i            (wdt_clk_i),
        .rst_n_i          (wdt_rst_n),
        .s_axi_awaddr_i   (s8_awaddr_wdt),
        .s_axi_awvalid_i  (s8_awvalid_wdt),
        .s_axi_awready_o  (s8_awready_wdt),
        .s_axi_wdata_i    (s8_wdata_wdt),
        .s_axi_wstrb_i    (s8_wstrb_wdt),
        .s_axi_wvalid_i   (s8_wvalid_wdt),
        .s_axi_wready_o   (s8_wready_wdt),
        .s_axi_bresp_o    (s8_bresp_wdt),
        .s_axi_bvalid_o   (s8_bvalid_wdt),
        .s_axi_bready_i   (s8_bready_wdt),
        .s_axi_araddr_i   (s8_araddr_wdt),    // O-03 FIX: dedicated read address
        .s_axi_arvalid_i  (s8_arvalid_wdt),
        .s_axi_arready_o  (s8_arready_wdt),
        .s_axi_rdata_o    (s8_rdata_wdt),
        .s_axi_rresp_o    (s8_rresp_wdt),
        .s_axi_rvalid_o   (s8_rvalid_wdt),
        .s_axi_rready_i   (wdt_rd_rready_wdt),
        .fault_o          (wdt_fault_wdtclk),
        .prewarn_o        (wdt_prewarn_wdtclk)
    );

    // WDT read response routing: always accept
    assign wdt_rd_rready_wdt = 1'b1;

    // =========================================================================
    // CDC-01 Response Path: WDT → sys_clk (BVALID, RVALID, RDATA, RRESP)
    // =========================================================================
    // WDT response signals are in wdt_clk domain. We use the handshake ack
    // mechanism to guarantee data stability: response data is captured in
    // wdt_clk when ack is asserted and held stable until next transaction.
    // 2FF synchronizers bring response valid to sys_clk; data is held stable
    // for many wdt_clk cycles so 2FF convergence is guaranteed.

    // Write response: BVALID + BRESP → sys_clk via 2FF
    wire        wdt_bvalid_wdtclk;
    wire [1:0]  wdt_bresp_wdtclk;
    (* ASYNC_REG = "TRUE" *) reg wdt_bvalid_sync0, wdt_bvalid_sync1;
    (* ASYNC_REG = "TRUE" *) reg [1:0] wdt_bresp_sync0, wdt_bresp_sync1;

    always @(posedge sys_clk_i or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wdt_bvalid_sync0 <= 1'b0; wdt_bvalid_sync1 <= 1'b0;
            wdt_bresp_sync0  <= 2'd0; wdt_bresp_sync1  <= 2'd0;
        end else begin
            wdt_bvalid_sync0 <= wdt_bvalid_wdtclk;
            wdt_bvalid_sync1 <= wdt_bvalid_sync0;
            wdt_bresp_sync0  <= wdt_bresp_wdtclk;
            wdt_bresp_sync1  <= wdt_bresp_sync0;
        end
    end

    // Read response: RVALID + RDATA + RRESP → sys_clk via 2FF
    wire        wdt_rvalid_wdtclk;
    wire [31:0] wdt_rdata_wdtclk;
    wire [1:0]  wdt_rresp_wdtclk;
    (* ASYNC_REG = "TRUE" *) reg        wdt_rvalid_sync0, wdt_rvalid_sync1;
    (* ASYNC_REG = "TRUE" *) reg [31:0] wdt_rdata_sync0,  wdt_rdata_sync1;
    (* ASYNC_REG = "TRUE" *) reg [1:0]  wdt_rresp_sync0,  wdt_rresp_sync1;

    always @(posedge sys_clk_i or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wdt_rvalid_sync0 <= 1'b0;  wdt_rvalid_sync1 <= 1'b0;
            wdt_rdata_sync0  <= 32'd0; wdt_rdata_sync1  <= 32'd0;
            wdt_rresp_sync0  <= 2'd0;  wdt_rresp_sync1  <= 2'd0;
        end else begin
            wdt_rvalid_sync0 <= wdt_rvalid_wdtclk;
            wdt_rvalid_sync1 <= wdt_rvalid_sync0;
            wdt_rdata_sync0  <= wdt_rdata_wdtclk;
            wdt_rdata_sync1  <= wdt_rdata_sync0;
            wdt_rresp_sync0  <= wdt_rresp_wdtclk;
            wdt_rresp_sync1  <= wdt_rresp_sync0;
        end
    end

    // Response capture in wdt_clk: latch WDT outputs at transaction completion
    reg wdt_bvalid_captured;
    reg [1:0] wdt_bresp_captured;
    reg wdt_rvalid_captured;
    reg [31:0] wdt_rdata_captured;
    reg [1:0] wdt_rresp_captured;

    always @(posedge wdt_clk_i or negedge wdt_rst_n) begin
        if (!wdt_rst_n) begin
            wdt_bvalid_captured <= 1'b0;
            wdt_bresp_captured  <= 2'd0;
            wdt_rvalid_captured <= 1'b0;
            wdt_rdata_captured  <= 32'd0;
            wdt_rresp_captured  <= 2'd0;
        end else begin
            // Capture write response from WDT
            if (s8_bvalid_wdt && s8_bready_wdt) begin
                wdt_bvalid_captured <= 1'b1;
                wdt_bresp_captured  <= s8_bresp_wdt;
            end else if (wdt_ack_wdtclk && !wdt_req_sync1) begin
                // Clear captured response when transaction cycle completes
                wdt_bvalid_captured <= 1'b0;
                wdt_rvalid_captured <= 1'b0;
            end
            // Capture read response from WDT
            if (s8_rvalid_wdt && wdt_rd_rready_wdt) begin
                wdt_rvalid_captured <= 1'b1;
                wdt_rdata_captured  <= s8_rdata_wdt;
                wdt_rresp_captured  <= s8_rresp_wdt;
            end
        end
    end

    // Response signals driven to AXI xbar (sys_clk domain, CDC'd)
    assign s8_bvalid = wdt_bvalid_sync1;
    assign s8_bresp  = wdt_bresp_sync1;
    assign s8_rvalid = wdt_rvalid_sync1;
    assign s8_rdata  = wdt_rdata_sync1;
    assign s8_rresp  = wdt_rresp_sync1;

    // Response valid signals from WDT driven through capture registers
    assign wdt_bvalid_wdtclk = wdt_bvalid_captured;
    assign wdt_bresp_wdtclk  = wdt_bresp_captured;
    assign wdt_rvalid_wdtclk = wdt_rvalid_captured;
    assign wdt_rdata_wdtclk  = wdt_rdata_captured;
    assign wdt_rresp_wdtclk  = wdt_rresp_captured;

    // =========================================================================
    // TCM Scrubber Control
    // =========================================================================
    // Scrubber control (hardwired; should be connected to FAULT_AGG SCRUB_CTRL register)
    wire        scr_enable   = 1'b1;       // TODO: map to SCRUB_CTRL[0]
    wire [15:0] scr_interval = 16'd1000;  // TODO: map to SCRUB_CTRL[31:16]

    wire        scr_busy;
    wire        scr_sweep_done;
    wire [15:0] scr_correct_count;
    wire [10:0] scr_addr_current;

    // =========================================================================
    // Memory Scrubber Instance
    // =========================================================================
    sram_scrubber u_scrubber (
        .clk                (sys_clk_i),
        .rst_n              (sys_rst_n),
        .scr_enable         (scr_enable),
        .scr_interval       (scr_interval),
        .scr_busy           (scr_busy),
        .scr_sweep_done     (scr_sweep_done),
        .scr_correct_count  (scr_correct_count),
        .scr_addr_current   (scr_addr_current),
        .tcm_scr_req        (tcm_scr_req),
        .tcm_scr_addr       (tcm_scr_addr),
        .tcm_scr_raw        (tcm_scr_raw),
        .tcm_scr_we         (tcm_scr_we),
        .tcm_scr_wdata      (tcm_scr_wdata),
        .tcm_scr_ecc        (tcm_scr_ecc)
    );

    // ---- Redundant Shutdown Controller (wdt_clk domain) ----
    wire rsc_force_shutdown;  // in wdt_clk domain

    redundant_shutdown u_rsc (
        .clk_i                (wdt_clk_i),
        .rst_n_i              (wdt_rst_n),
        .aggregated_fault_i   (agg_fault_wdtclk),
        .force_shutdown_sw_i  (1'b0),  // software shutdown not yet connected
        .shutdown_n_o         (shutdown_n_o),
        .alert_n_o            (alert_n_o),
        .force_shutdown_o     (rsc_force_shutdown)
    );

    // ---- CDC: RSC force_shutdown → sys_clk for GPIO (CDC-05: 2FF) ----
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
    // Interrupt Assembly (16 IRQ lines → RV32IM Core)
    // =========================================================================
    assign core_irq[0]  = spi_irq_rx;          // SPI RX available
    assign core_irq[1]  = spi_irq_tx;          // SPI TX empty
    assign core_irq[2]  = spi_irq_err;         // SPI error
    assign core_irq[3]  = servo_irq_fault;     // Servo fault
    assign core_irq[4]  = speed_irq_pulse;     // Speed pulse detected
    assign core_irq[5]  = speed_irq_ovf;       // Speed overflow
    assign core_irq[6]  = buzzer_irq_done;     // Buzzer cycle done
    assign core_irq[7]  = uart_irq_rx;         // UART RX available
    assign core_irq[8]  = uart_irq_tx;         // UART TX empty
    assign core_irq[9]  = |gpio_irq_lines;     // GPIO interrupt (combined)
    assign core_irq[10] = ai_irq_done;         // AI compute done
    assign core_irq[11] = ai_irq_error;        // AI error
    assign core_irq[12] = wdt_prewarn_sysclk;  // WDT pre-warning (CDC'd)
    assign core_irq[13] = fault_irq_lockstep;  // Lockstep mismatch
    assign core_irq[14] = fault_irq_agg;       // Fault aggregator alert
    assign core_irq[15] = 1'b0;                // Timer IRQ (from mtime)

endmodule
