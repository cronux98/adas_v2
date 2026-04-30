// ============================================================================
// axi4_lite_interconnect.v — AXI4-Lite Crossbar (1 Master → 9 Slaves)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    AXI4-Lite bus fabric with flat address decode
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Address Decode Map (block_interfaces.md §5.4):
//   Slave 0: 0x0000_1000 - AI Accelerator
//   Slave 1: 0x0000_2000 - SPI Controller
//   Slave 2: 0x0000_3000 - Servo PWM
//   Slave 3: 0x0000_4000 - Speed Sensor
//   Slave 4: 0x0000_5000 - Buzzer PWM
//   Slave 5: 0x0000_6000 - UART
//   Slave 6: 0x0000_7000 - GPIO
//   Slave 7: 0x0000_F000 - Safety Control
//   Slave 8: 0x0000_F100 - Window WDT
//   Default: SLVERR on unmapped addresses
// ============================================================================

`timescale 1ns / 1ps

module axi4_lite_interconnect (
    input  wire        clk_i,
    input  wire        rst_n_i,

    // =====================================================================
    // Master Port (connected to RV32IM Core)
    // =====================================================================
    // Write address channel
    input  wire [31:0] m_axi_awaddr_i,
    input  wire [2:0]  m_axi_awprot_i,
    input  wire        m_axi_awvalid_i,
    output wire        m_axi_awready_o,

    // Write data channel
    input  wire [31:0] m_axi_wdata_i,
    input  wire [3:0]  m_axi_wstrb_i,
    input  wire        m_axi_wvalid_i,
    output wire        m_axi_wready_o,

    // Write response channel
    output wire [1:0]  m_axi_bresp_o,
    output wire        m_axi_bvalid_o,
    input  wire        m_axi_bready_i,

    // Read address channel
    input  wire [31:0] m_axi_araddr_i,
    input  wire [2:0]  m_axi_arprot_i,
    input  wire        m_axi_arvalid_i,
    output wire        m_axi_arready_o,

    // Read data channel
    output wire [31:0] m_axi_rdata_o,
    output wire [1:0]  m_axi_rresp_o,
    output wire        m_axi_rvalid_o,
    input  wire        m_axi_rready_i,

    // =====================================================================
    // Slave Port 0 — AI Accelerator @ 0x0000_1000
    // =====================================================================
    output wire [31:0] s0_axi_awaddr_o,
    output wire [2:0]  s0_axi_awprot_o,
    output wire        s0_axi_awvalid_o,
    input  wire        s0_axi_awready_i,
    output wire [31:0] s0_axi_wdata_o,
    output wire [3:0]  s0_axi_wstrb_o,
    output wire        s0_axi_wvalid_o,
    input  wire        s0_axi_wready_i,
    input  wire [1:0]  s0_axi_bresp_i,
    input  wire        s0_axi_bvalid_i,
    output wire        s0_axi_bready_o,
    output wire [31:0] s0_axi_araddr_o,
    output wire [2:0]  s0_axi_arprot_o,
    output wire        s0_axi_arvalid_o,
    input  wire        s0_axi_arready_i,
    input  wire [31:0] s0_axi_rdata_i,
    input  wire [1:0]  s0_axi_rresp_i,
    input  wire        s0_axi_rvalid_i,
    output wire        s0_axi_rready_o,

    // =====================================================================
    // Slave Port 1 — SPI Controller @ 0x0000_2000
    // =====================================================================
    output wire [31:0] s1_axi_awaddr_o,
    output wire [2:0]  s1_axi_awprot_o,
    output wire        s1_axi_awvalid_o,
    input  wire        s1_axi_awready_i,
    output wire [31:0] s1_axi_wdata_o,
    output wire [3:0]  s1_axi_wstrb_o,
    output wire        s1_axi_wvalid_o,
    input  wire        s1_axi_wready_i,
    input  wire [1:0]  s1_axi_bresp_i,
    input  wire        s1_axi_bvalid_i,
    output wire        s1_axi_bready_o,
    output wire [31:0] s1_axi_araddr_o,
    output wire [2:0]  s1_axi_arprot_o,
    output wire        s1_axi_arvalid_o,
    input  wire        s1_axi_arready_i,
    input  wire [31:0] s1_axi_rdata_i,
    input  wire [1:0]  s1_axi_rresp_i,
    input  wire        s1_axi_rvalid_i,
    output wire        s1_axi_rready_o,

    // =====================================================================
    // Slave Port 2 — Servo PWM @ 0x0000_3000
    // =====================================================================
    output wire [31:0] s2_axi_awaddr_o,
    output wire [2:0]  s2_axi_awprot_o,
    output wire        s2_axi_awvalid_o,
    input  wire        s2_axi_awready_i,
    output wire [31:0] s2_axi_wdata_o,
    output wire [3:0]  s2_axi_wstrb_o,
    output wire        s2_axi_wvalid_o,
    input  wire        s2_axi_wready_i,
    input  wire [1:0]  s2_axi_bresp_i,
    input  wire        s2_axi_bvalid_i,
    output wire        s2_axi_bready_o,
    output wire [31:0] s2_axi_araddr_o,
    output wire [2:0]  s2_axi_arprot_o,
    output wire        s2_axi_arvalid_o,
    input  wire        s2_axi_arready_i,
    input  wire [31:0] s2_axi_rdata_i,
    input  wire [1:0]  s2_axi_rresp_i,
    input  wire        s2_axi_rvalid_i,
    output wire        s2_axi_rready_o,

    // =====================================================================
    // Slave Port 3 — Speed Sensor @ 0x0000_4000
    // =====================================================================
    output wire [31:0] s3_axi_awaddr_o,
    output wire [2:0]  s3_axi_awprot_o,
    output wire        s3_axi_awvalid_o,
    input  wire        s3_axi_awready_i,
    output wire [31:0] s3_axi_wdata_o,
    output wire [3:0]  s3_axi_wstrb_o,
    output wire        s3_axi_wvalid_o,
    input  wire        s3_axi_wready_i,
    input  wire [1:0]  s3_axi_bresp_i,
    input  wire        s3_axi_bvalid_i,
    output wire        s3_axi_bready_o,
    output wire [31:0] s3_axi_araddr_o,
    output wire [2:0]  s3_axi_arprot_o,
    output wire        s3_axi_arvalid_o,
    input  wire        s3_axi_arready_i,
    input  wire [31:0] s3_axi_rdata_i,
    input  wire [1:0]  s3_axi_rresp_i,
    input  wire        s3_axi_rvalid_i,
    output wire        s3_axi_rready_o,

    // =====================================================================
    // Slave Port 4 — Buzzer PWM @ 0x0000_5000
    // =====================================================================
    output wire [31:0] s4_axi_awaddr_o,
    output wire [2:0]  s4_axi_awprot_o,
    output wire        s4_axi_awvalid_o,
    input  wire        s4_axi_awready_i,
    output wire [31:0] s4_axi_wdata_o,
    output wire [3:0]  s4_axi_wstrb_o,
    output wire        s4_axi_wvalid_o,
    input  wire        s4_axi_wready_i,
    input  wire [1:0]  s4_axi_bresp_i,
    input  wire        s4_axi_bvalid_i,
    output wire        s4_axi_bready_o,
    output wire [31:0] s4_axi_araddr_o,
    output wire [2:0]  s4_axi_arprot_o,
    output wire        s4_axi_arvalid_o,
    input  wire        s4_axi_arready_i,
    input  wire [31:0] s4_axi_rdata_i,
    input  wire [1:0]  s4_axi_rresp_i,
    input  wire        s4_axi_rvalid_i,
    output wire        s4_axi_rready_o,

    // =====================================================================
    // Slave Port 5 — UART @ 0x0000_6000
    // =====================================================================
    output wire [31:0] s5_axi_awaddr_o,
    output wire [2:0]  s5_axi_awprot_o,
    output wire        s5_axi_awvalid_o,
    input  wire        s5_axi_awready_i,
    output wire [31:0] s5_axi_wdata_o,
    output wire [3:0]  s5_axi_wstrb_o,
    output wire        s5_axi_wvalid_o,
    input  wire        s5_axi_wready_i,
    input  wire [1:0]  s5_axi_bresp_i,
    input  wire        s5_axi_bvalid_i,
    output wire        s5_axi_bready_o,
    output wire [31:0] s5_axi_araddr_o,
    output wire [2:0]  s5_axi_arprot_o,
    output wire        s5_axi_arvalid_o,
    input  wire        s5_axi_arready_i,
    input  wire [31:0] s5_axi_rdata_i,
    input  wire [1:0]  s5_axi_rresp_i,
    input  wire        s5_axi_rvalid_i,
    output wire        s5_axi_rready_o,

    // =====================================================================
    // Slave Port 6 — GPIO @ 0x0000_7000
    // =====================================================================
    output wire [31:0] s6_axi_awaddr_o,
    output wire [2:0]  s6_axi_awprot_o,
    output wire        s6_axi_awvalid_o,
    input  wire        s6_axi_awready_i,
    output wire [31:0] s6_axi_wdata_o,
    output wire [3:0]  s6_axi_wstrb_o,
    output wire        s6_axi_wvalid_o,
    input  wire        s6_axi_wready_i,
    input  wire [1:0]  s6_axi_bresp_i,
    input  wire        s6_axi_bvalid_i,
    output wire        s6_axi_bready_o,
    output wire [31:0] s6_axi_araddr_o,
    output wire [2:0]  s6_axi_arprot_o,
    output wire        s6_axi_arvalid_o,
    input  wire        s6_axi_arready_i,
    input  wire [31:0] s6_axi_rdata_i,
    input  wire [1:0]  s6_axi_rresp_i,
    input  wire        s6_axi_rvalid_i,
    output wire        s6_axi_rready_o,

    // =====================================================================
    // Slave Port 7 — Safety Control @ 0x0000_F000
    // =====================================================================
    output wire [31:0] s7_axi_awaddr_o,
    output wire [2:0]  s7_axi_awprot_o,
    output wire        s7_axi_awvalid_o,
    input  wire        s7_axi_awready_i,
    output wire [31:0] s7_axi_wdata_o,
    output wire [3:0]  s7_axi_wstrb_o,
    output wire        s7_axi_wvalid_o,
    input  wire        s7_axi_wready_i,
    input  wire [1:0]  s7_axi_bresp_i,
    input  wire        s7_axi_bvalid_i,
    output wire        s7_axi_bready_o,
    output wire [31:0] s7_axi_araddr_o,
    output wire [2:0]  s7_axi_arprot_o,
    output wire        s7_axi_arvalid_o,
    input  wire        s7_axi_arready_i,
    input  wire [31:0] s7_axi_rdata_i,
    input  wire [1:0]  s7_axi_rresp_i,
    input  wire        s7_axi_rvalid_i,
    output wire        s7_axi_rready_o,

    // =====================================================================
    // Slave Port 8 — Window WDT @ 0x0000_F100
    // =====================================================================
    output wire [31:0] s8_axi_awaddr_o,
    output wire [2:0]  s8_axi_awprot_o,
    output wire        s8_axi_awvalid_o,
    input  wire        s8_axi_awready_i,
    output wire [31:0] s8_axi_wdata_o,
    output wire [3:0]  s8_axi_wstrb_o,
    output wire        s8_axi_wvalid_o,
    input  wire        s8_axi_wready_i,
    input  wire [1:0]  s8_axi_bresp_i,
    input  wire        s8_axi_bvalid_i,
    output wire        s8_axi_bready_o,
    output wire [31:0] s8_axi_araddr_o,
    output wire [2:0]  s8_axi_arprot_o,
    output wire        s8_axi_arvalid_o,
    input  wire        s8_axi_arready_i,
    input  wire [31:0] s8_axi_rdata_i,
    input  wire [1:0]  s8_axi_rresp_i,
    input  wire        s8_axi_rvalid_i,
    output wire        s8_axi_rready_o
);

    localparam AXI_OKAY   = 2'b00;
    localparam AXI_SLVERR = 2'b10;
    localparam AXI_DECERR = 2'b11;

    // ——— Address Decode ———
    // Match on address [31:12] for 4KB-aligned slaves
    // Match on address [31:8] for 256B-aligned WDT
    wire [19:0] addr_4k_page = m_axi_awaddr_i[31:12];

    wire sel_ai     = (addr_4k_page == 20'h00001);  // 0x0000_1000
    wire sel_spi    = (addr_4k_page == 20'h00002);  // 0x0000_2000
    wire sel_servo  = (addr_4k_page == 20'h00003);  // 0x0000_3000
    wire sel_speed  = (addr_4k_page == 20'h00004);  // 0x0000_4000
    wire sel_buzzer = (addr_4k_page == 20'h00005);  // 0x0000_5000
    wire sel_uart   = (addr_4k_page == 20'h00006);  // 0x0000_6000
    wire sel_gpio   = (addr_4k_page == 20'h00007);  // 0x0000_7000
    wire sel_safety = (addr_4k_page == 20'h0000F);  // 0x0000_F000
    wire sel_wdt    = (addr_4k_page == 20'h0000F) && (m_axi_awaddr_i[11:8] == 4'h1); // 0x0000_F100

    wire any_match  = sel_ai | sel_spi | sel_servo | sel_speed | sel_buzzer |
                      sel_uart | sel_gpio | sel_safety | sel_wdt;

    // Read address decode (same logic for read channel)
    wire [19:0] ar_4k_page = m_axi_araddr_i[31:12];
    wire ar_sel_ai     = (ar_4k_page == 20'h00001);
    wire ar_sel_spi    = (ar_4k_page == 20'h00002);
    wire ar_sel_servo  = (ar_4k_page == 20'h00003);
    wire ar_sel_speed  = (ar_4k_page == 20'h00004);
    wire ar_sel_buzzer = (ar_4k_page == 20'h00005);
    wire ar_sel_uart   = (ar_4k_page == 20'h00006);
    wire ar_sel_gpio   = (ar_4k_page == 20'h00007);
    wire ar_sel_safety = (ar_4k_page == 20'h0000F);
    wire ar_sel_wdt    = (ar_4k_page == 20'h0000F) && (m_axi_araddr_i[11:8] == 4'h1);
    wire ar_any_match  = ar_sel_ai | ar_sel_spi | ar_sel_servo | ar_sel_speed |
                         ar_sel_buzzer | ar_sel_uart | ar_sel_gpio |
                         ar_sel_safety | ar_sel_wdt;

    // ——— Write Channel Routing ———
    // Broadcast all write signals to all slaves; only the selected slave responds
    // This is a full-crossbar implementation — simple and correct for 9 slaves.

    // Slave 0 — AI Accelerator
    assign s0_axi_awaddr_o  = m_axi_awaddr_i;
    assign s0_axi_awprot_o  = m_axi_awprot_i;
    assign s0_axi_awvalid_o = m_axi_awvalid_i && sel_ai;
    assign s0_axi_wdata_o   = m_axi_wdata_i;
    assign s0_axi_wstrb_o   = m_axi_wstrb_i;
    assign s0_axi_wvalid_o  = m_axi_wvalid_i && sel_ai;
    assign s0_axi_bready_o  = m_axi_bready_i && sel_ai;
    assign s0_axi_araddr_o  = m_axi_araddr_i;
    assign s0_axi_arprot_o  = m_axi_arprot_i;
    assign s0_axi_arvalid_o = m_axi_arvalid_i && ar_sel_ai;
    assign s0_axi_rready_o  = m_axi_rready_i && ar_sel_ai;

    // Slave 1 — SPI
    assign s1_axi_awaddr_o  = m_axi_awaddr_i;
    assign s1_axi_awprot_o  = m_axi_awprot_i;
    assign s1_axi_awvalid_o = m_axi_awvalid_i && sel_spi;
    assign s1_axi_wdata_o   = m_axi_wdata_i;
    assign s1_axi_wstrb_o   = m_axi_wstrb_i;
    assign s1_axi_wvalid_o  = m_axi_wvalid_i && sel_spi;
    assign s1_axi_bready_o  = m_axi_bready_i && sel_spi;
    assign s1_axi_araddr_o  = m_axi_araddr_i;
    assign s1_axi_arprot_o  = m_axi_arprot_i;
    assign s1_axi_arvalid_o = m_axi_arvalid_i && ar_sel_spi;
    assign s1_axi_rready_o  = m_axi_rready_i && ar_sel_spi;

    // Slave 2 — Servo
    assign s2_axi_awaddr_o  = m_axi_awaddr_i;
    assign s2_axi_awprot_o  = m_axi_awprot_i;
    assign s2_axi_awvalid_o = m_axi_awvalid_i && sel_servo;
    assign s2_axi_wdata_o   = m_axi_wdata_i;
    assign s2_axi_wstrb_o   = m_axi_wstrb_i;
    assign s2_axi_wvalid_o  = m_axi_wvalid_i && sel_servo;
    assign s2_axi_bready_o  = m_axi_bready_i && sel_servo;
    assign s2_axi_araddr_o  = m_axi_araddr_i;
    assign s2_axi_arprot_o  = m_axi_arprot_i;
    assign s2_axi_arvalid_o = m_axi_arvalid_i && ar_sel_servo;
    assign s2_axi_rready_o  = m_axi_rready_i && ar_sel_servo;

    // Slave 3 — Speed
    assign s3_axi_awaddr_o  = m_axi_awaddr_i;
    assign s3_axi_awprot_o  = m_axi_awprot_i;
    assign s3_axi_awvalid_o = m_axi_awvalid_i && sel_speed;
    assign s3_axi_wdata_o   = m_axi_wdata_i;
    assign s3_axi_wstrb_o   = m_axi_wstrb_i;
    assign s3_axi_wvalid_o  = m_axi_wvalid_i && sel_speed;
    assign s3_axi_bready_o  = m_axi_bready_i && sel_speed;
    assign s3_axi_araddr_o  = m_axi_araddr_i;
    assign s3_axi_arprot_o  = m_axi_arprot_i;
    assign s3_axi_arvalid_o = m_axi_arvalid_i && ar_sel_speed;
    assign s3_axi_rready_o  = m_axi_rready_i && ar_sel_speed;

    // Slave 4 — Buzzer
    assign s4_axi_awaddr_o  = m_axi_awaddr_i;
    assign s4_axi_awprot_o  = m_axi_awprot_i;
    assign s4_axi_awvalid_o = m_axi_awvalid_i && sel_buzzer;
    assign s4_axi_wdata_o   = m_axi_wdata_i;
    assign s4_axi_wstrb_o   = m_axi_wstrb_i;
    assign s4_axi_wvalid_o  = m_axi_wvalid_i && sel_buzzer;
    assign s4_axi_bready_o  = m_axi_bready_i && sel_buzzer;
    assign s4_axi_araddr_o  = m_axi_araddr_i;
    assign s4_axi_arprot_o  = m_axi_arprot_i;
    assign s4_axi_arvalid_o = m_axi_arvalid_i && ar_sel_buzzer;
    assign s4_axi_rready_o  = m_axi_rready_i && ar_sel_buzzer;

    // Slave 5 — UART
    assign s5_axi_awaddr_o  = m_axi_awaddr_i;
    assign s5_axi_awprot_o  = m_axi_awprot_i;
    assign s5_axi_awvalid_o = m_axi_awvalid_i && sel_uart;
    assign s5_axi_wdata_o   = m_axi_wdata_i;
    assign s5_axi_wstrb_o   = m_axi_wstrb_i;
    assign s5_axi_wvalid_o  = m_axi_wvalid_i && sel_uart;
    assign s5_axi_bready_o  = m_axi_bready_i && sel_uart;
    assign s5_axi_araddr_o  = m_axi_araddr_i;
    assign s5_axi_arprot_o  = m_axi_arprot_i;
    assign s5_axi_arvalid_o = m_axi_arvalid_i && ar_sel_uart;
    assign s5_axi_rready_o  = m_axi_rready_i && ar_sel_uart;

    // Slave 6 — GPIO
    assign s6_axi_awaddr_o  = m_axi_awaddr_i;
    assign s6_axi_awprot_o  = m_axi_awprot_i;
    assign s6_axi_awvalid_o = m_axi_awvalid_i && sel_gpio;
    assign s6_axi_wdata_o   = m_axi_wdata_i;
    assign s6_axi_wstrb_o   = m_axi_wstrb_i;
    assign s6_axi_wvalid_o  = m_axi_wvalid_i && sel_gpio;
    assign s6_axi_bready_o  = m_axi_bready_i && sel_gpio;
    assign s6_axi_araddr_o  = m_axi_araddr_i;
    assign s6_axi_arprot_o  = m_axi_arprot_i;
    assign s6_axi_arvalid_o = m_axi_arvalid_i && ar_sel_gpio;
    assign s6_axi_rready_o  = m_axi_rready_i && ar_sel_gpio;

    // Slave 7 — Safety Control
    assign s7_axi_awaddr_o  = m_axi_awaddr_i;
    assign s7_axi_awprot_o  = m_axi_awprot_i;
    assign s7_axi_awvalid_o = m_axi_awvalid_i && sel_safety;
    assign s7_axi_wdata_o   = m_axi_wdata_i;
    assign s7_axi_wstrb_o   = m_axi_wstrb_i;
    assign s7_axi_wvalid_o  = m_axi_wvalid_i && sel_safety;
    assign s7_axi_bready_o  = m_axi_bready_i && sel_safety;
    assign s7_axi_araddr_o  = m_axi_araddr_i;
    assign s7_axi_arprot_o  = m_axi_arprot_i;
    assign s7_axi_arvalid_o = m_axi_arvalid_i && ar_sel_safety;
    assign s7_axi_rready_o  = m_axi_rready_i && ar_sel_safety;

    // Slave 8 — Window WDT
    assign s8_axi_awaddr_o  = m_axi_awaddr_i;
    assign s8_axi_awprot_o  = m_axi_awprot_i;
    assign s8_axi_awvalid_o = m_axi_awvalid_i && sel_wdt;
    assign s8_axi_wdata_o   = m_axi_wdata_i;
    assign s8_axi_wstrb_o   = m_axi_wstrb_i;
    assign s8_axi_wvalid_o  = m_axi_wvalid_i && sel_wdt;
    assign s8_axi_bready_o  = m_axi_bready_i && sel_wdt;
    assign s8_axi_araddr_o  = m_axi_araddr_i;
    assign s8_axi_arprot_o  = m_axi_arprot_i;
    assign s8_axi_arvalid_o = m_axi_arvalid_i && ar_sel_wdt;
    assign s8_axi_rready_o  = m_axi_rready_i && ar_sel_wdt;

    // ——— Master-side response mux ———
    // Write channel response mux
    // For unmapped addresses, return SLVERR
    // Wait: the AWREADY needs to come from the selected slave or default
    // We use a registered approach: decode on awvalid, route through.
    reg [3:0]  aw_sel_id;  // 0-8 = valid slave, 15 = unmapped
    reg        aw_sel_valid;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            aw_sel_id <= 4'd15;
            aw_sel_valid <= 1'b0;
        end else begin
            if (m_axi_awvalid_i) begin
                aw_sel_valid <= 1'b1;
                if      (sel_ai)     aw_sel_id <= 4'd0;
                else if (sel_spi)    aw_sel_id <= 4'd1;
                else if (sel_servo)  aw_sel_id <= 4'd2;
                else if (sel_speed)  aw_sel_id <= 4'd3;
                else if (sel_buzzer) aw_sel_id <= 4'd4;
                else if (sel_uart)   aw_sel_id <= 4'd5;
                else if (sel_gpio)   aw_sel_id <= 4'd6;
                else if (sel_safety && !sel_wdt) aw_sel_id <= 4'd7;
                else if (sel_wdt)    aw_sel_id <= 4'd8;
                else                 aw_sel_id <= 4'd15;
            end else if (m_axi_bready_i && m_axi_bvalid_o) begin
                aw_sel_valid <= 1'b0;
            end
        end
    end

    // AWREADY: from selected slave, or ready immediately for unmapped (we eat it)
    assign m_axi_awready_o = aw_sel_valid ? 1'b0 :
                              any_match ?
                                ((aw_sel_id == 4'd0) ? s0_axi_awready_i :
                                 (aw_sel_id == 4'd1) ? s1_axi_awready_i :
                                 (aw_sel_id == 4'd2) ? s2_axi_awready_i :
                                 (aw_sel_id == 4'd3) ? s3_axi_awready_i :
                                 (aw_sel_id == 4'd4) ? s4_axi_awready_i :
                                 (aw_sel_id == 4'd5) ? s5_axi_awready_i :
                                 (aw_sel_id == 4'd6) ? s6_axi_awready_i :
                                 (aw_sel_id == 4'd7) ? s7_axi_awready_i :
                                 (aw_sel_id == 4'd8) ? s8_axi_awready_i :
                                 1'b0) : 1'b1;  // unmapped: accept immediately

    // WREADY: from selected slave
    assign m_axi_wready_o = any_match ?
                              ((aw_sel_id == 4'd0) ? s0_axi_wready_i :
                               (aw_sel_id == 4'd1) ? s1_axi_wready_i :
                               (aw_sel_id == 4'd2) ? s2_axi_wready_i :
                               (aw_sel_id == 4'd3) ? s3_axi_wready_i :
                               (aw_sel_id == 4'd4) ? s4_axi_wready_i :
                               (aw_sel_id == 4'd5) ? s5_axi_wready_i :
                               (aw_sel_id == 4'd6) ? s6_axi_wready_i :
                               (aw_sel_id == 4'd7) ? s7_axi_wready_i :
                               (aw_sel_id == 4'd8) ? s8_axi_wready_i :
                               1'b0) : 1'b1;

    // BRESP/BVALID: mux from selected slave or return SLVERR for unmapped
    assign m_axi_bresp_o  = any_match ?
                              ((aw_sel_id == 4'd0) ? s0_axi_bresp_i :
                               (aw_sel_id == 4'd1) ? s1_axi_bresp_i :
                               (aw_sel_id == 4'd2) ? s2_axi_bresp_i :
                               (aw_sel_id == 4'd3) ? s3_axi_bresp_i :
                               (aw_sel_id == 4'd4) ? s4_axi_bresp_i :
                               (aw_sel_id == 4'd5) ? s5_axi_bresp_i :
                               (aw_sel_id == 4'd6) ? s6_axi_bresp_i :
                               (aw_sel_id == 4'd7) ? s7_axi_bresp_i :
                               (aw_sel_id == 4'd8) ? s8_axi_bresp_i :
                               AXI_SLVERR) : AXI_SLVERR;

    assign m_axi_bvalid_o = any_match ?
                              ((aw_sel_id == 4'd0) ? s0_axi_bvalid_i :
                               (aw_sel_id == 4'd1) ? s1_axi_bvalid_i :
                               (aw_sel_id == 4'd2) ? s2_axi_bvalid_i :
                               (aw_sel_id == 4'd3) ? s3_axi_bvalid_i :
                               (aw_sel_id == 4'd4) ? s4_axi_bvalid_i :
                               (aw_sel_id == 4'd5) ? s5_axi_bvalid_i :
                               (aw_sel_id == 4'd6) ? s6_axi_bvalid_i :
                               (aw_sel_id == 4'd7) ? s7_axi_bvalid_i :
                               (aw_sel_id == 4'd8) ? s8_axi_bvalid_i :
                               1'b0) : (aw_sel_valid && aw_sel_id == 4'd15);  // auto-respond SLVERR

    // ——— Read channel routing + response mux ———
    reg [3:0]  ar_sel_id;
    reg        ar_sel_valid;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ar_sel_id <= 4'd15;
            ar_sel_valid <= 1'b0;
        end else begin
            if (m_axi_arvalid_i && m_axi_arready_o) begin
                ar_sel_valid <= 1'b1;
                if      (ar_sel_ai)     ar_sel_id <= 4'd0;
                else if (ar_sel_spi)    ar_sel_id <= 4'd1;
                else if (ar_sel_servo)  ar_sel_id <= 4'd2;
                else if (ar_sel_speed)  ar_sel_id <= 4'd3;
                else if (ar_sel_buzzer) ar_sel_id <= 4'd4;
                else if (ar_sel_uart)   ar_sel_id <= 4'd5;
                else if (ar_sel_gpio)   ar_sel_id <= 4'd6;
                else if (ar_sel_safety && !ar_sel_wdt) ar_sel_id <= 4'd7;
                else if (ar_sel_wdt)    ar_sel_id <= 4'd8;
                else                    ar_sel_id <= 4'd15;
            end else if (m_axi_rready_i && m_axi_rvalid_o) begin
                ar_sel_valid <= 1'b0;
            end
        end
    end

    assign m_axi_arready_o = !ar_sel_valid;

    assign m_axi_rdata_o = ar_any_match ?
                              ((ar_sel_id == 4'd0) ? s0_axi_rdata_i :
                               (ar_sel_id == 4'd1) ? s1_axi_rdata_i :
                               (ar_sel_id == 4'd2) ? s2_axi_rdata_i :
                               (ar_sel_id == 4'd3) ? s3_axi_rdata_i :
                               (ar_sel_id == 4'd4) ? s4_axi_rdata_i :
                               (ar_sel_id == 4'd5) ? s5_axi_rdata_i :
                               (ar_sel_id == 4'd6) ? s6_axi_rdata_i :
                               (ar_sel_id == 4'd7) ? s7_axi_rdata_i :
                               (ar_sel_id == 4'd8) ? s8_axi_rdata_i :
                               32'd0) : 32'd0;

    assign m_axi_rresp_o = ar_any_match ?
                              ((ar_sel_id == 4'd0) ? s0_axi_rresp_i :
                               (ar_sel_id == 4'd1) ? s1_axi_rresp_i :
                               (ar_sel_id == 4'd2) ? s2_axi_rresp_i :
                               (ar_sel_id == 4'd3) ? s3_axi_rresp_i :
                               (ar_sel_id == 4'd4) ? s4_axi_rresp_i :
                               (ar_sel_id == 4'd5) ? s5_axi_rresp_i :
                               (ar_sel_id == 4'd6) ? s6_axi_rresp_i :
                               (ar_sel_id == 4'd7) ? s7_axi_rresp_i :
                               (ar_sel_id == 4'd8) ? s8_axi_rresp_i :
                               AXI_SLVERR) : AXI_SLVERR;

    assign m_axi_rvalid_o = ar_any_match ?
                              ((ar_sel_id == 4'd0) ? s0_axi_rvalid_i :
                               (ar_sel_id == 4'd1) ? s1_axi_rvalid_i :
                               (ar_sel_id == 4'd2) ? s2_axi_rvalid_i :
                               (ar_sel_id == 4'd3) ? s3_axi_rvalid_i :
                               (ar_sel_id == 4'd4) ? s4_axi_rvalid_i :
                               (ar_sel_id == 4'd5) ? s5_axi_rvalid_i :
                               (ar_sel_id == 4'd6) ? s6_axi_rvalid_i :
                               (ar_sel_id == 4'd7) ? s7_axi_rvalid_i :
                               (ar_sel_id == 4'd8) ? s8_axi_rvalid_i :
                               1'b0) : (ar_sel_valid && ar_sel_id == 4'd15);

endmodule
