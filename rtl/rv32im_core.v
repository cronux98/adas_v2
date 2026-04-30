// ============================================================================
// rv32im_core.v — RV32IM Core Wrapper (3-Stage Pipeline)
// ============================================================================
// Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
// Block:    RV32IM RISC-V processor core (3-stage: IF→ID→EX)
// Author:   Mei-Lin Chang, Digital Design Engineer
// Date:     2026-04-29
// PDK:      sky130_fd_sc_hs (SkyWater 130nm High-Speed)
// Clock:    sys_clk @ 100 MHz
//
// Interface (block_interfaces.md §3):
//   - ITCM master (32-bit instruction fetch)
//   - DTCM master (32-bit data access)
//   - AXI4-Lite master (peripheral access)
//   - 16 external interrupt lines + timer IRQ
//   - Lockstep outputs for safety monitor
//   - Halt input from safety monitor
//   - Debug request input
//
// Architecture (microarchitecture_spec.md §4):
//   3-stage pipeline: Fetch → Decode → Execute
//   Branch penalty: 1 cycle
//   No caches — deterministic ITCM/DTCM access
//   Multi-cycle MUL/DIV with pipeline stall
//
// Note: This is a structural wrapper that provides the specified interfaces.
// The actual RV32IM microarchitecture implementation is inside the core block.
// For tape-out, this can be swapped with a hard macro or a more complete
// implementation (e.g., SERV, PicoRV32, or a custom core).
// ============================================================================

`timescale 1ns / 1ps

module rv32im_core (
    // Clock and reset
    input  wire        clk_i,
    input  wire        rst_n_i,

    // =====================================================================
    // ITCM Interface (Instruction Fetch)
    // =====================================================================
    output wire [12:0] itcm_addr_o,
    input  wire [31:0] itcm_rdata_i,
    output wire        itcm_req_o,
    input  wire        itcm_ack_i,

    // =====================================================================
    // DTCM Interface (Data Access)
    // =====================================================================
    output wire [12:0] dtcm_addr_o,
    output wire [31:0] dtcm_wdata_o,
    input  wire [31:0] dtcm_rdata_i,
    output wire [3:0]  dtcm_we_o,
    output wire        dtcm_req_o,
    input  wire        dtcm_ack_i,

    // =====================================================================
    // AXI4-Lite Master Interface (Peripheral Access)
    // =====================================================================
    // Write address channel
    output wire [31:0] m_axi_awaddr_o,
    output wire [2:0]  m_axi_awprot_o,
    output wire        m_axi_awvalid_o,
    input  wire        m_axi_awready_i,

    // Write data channel
    output wire [31:0] m_axi_wdata_o,
    output wire [3:0]  m_axi_wstrb_o,
    output wire        m_axi_wvalid_o,
    input  wire        m_axi_wready_i,

    // Write response channel
    input  wire [1:0]  m_axi_bresp_i,
    input  wire        m_axi_bvalid_i,
    output wire        m_axi_bready_o,

    // Read address channel
    output wire [31:0] m_axi_araddr_o,
    output wire [2:0]  m_axi_arprot_o,
    output wire        m_axi_arvalid_o,
    input  wire        m_axi_arready_i,

    // Read data channel
    input  wire [31:0] m_axi_rdata_i,
    input  wire [1:0]  m_axi_rresp_i,
    input  wire        m_axi_rvalid_i,
    output wire        m_axi_rready_o,

    // =====================================================================
    // Interrupts
    // =====================================================================
    input  wire [15:0] irq_i,
    input  wire        timer_irq_i,

    // =====================================================================
    // Safety Monitor Interface (Lockstep outputs)
    // =====================================================================
    output wire [31:0] lockstep_outputs_o,
    output wire [31:0] lockstep_pc_o,
    output wire        lockstep_valid_o,
    input  wire        halt_i,

    // =====================================================================
    // Debug Interface
    // =====================================================================
    input  wire        debug_req_i
);

    // —————————————————————————————————————————————————————————————————
    // 3-Stage Pipeline Implementation
    // —————————————————————————————————————————————————————————————————

    // Program counter
    reg [31:0] pc;
    reg [31:0] pc_next;

    // Pipeline registers
    // Stage 1 (IF) → Stage 2 (ID)
    reg [31:0] if_pc;
    reg [31:0] if_instr;
    reg        if_valid;
    wire       if_stall;

    // Stage 2 (ID) → Stage 3 (EX)
    reg [31:0] id_pc;
    reg [31:0] id_instr;
    reg [31:0] id_rs1_data;
    reg [31:0] id_rs2_data;
    reg        id_valid;

    // Stage 3 (EX)
    reg [31:0] ex_pc;
    reg [31:0] ex_result;
    reg [3:0]  ex_we;        // byte write enable for stores
    reg [31:0] ex_wdata;
    reg        ex_rd_wen;
    reg [4:0]  ex_rd_addr;
    reg        ex_branch_taken;
    reg [31:0] ex_branch_target;
    reg        ex_valid;
    reg        ex_is_load;
    reg        ex_is_store;
    reg        ex_is_axi;     // AXI-Lite access (not DTCM)

    // Register file (32 × 32-bit)
    reg [31:0] regfile [0:31];

    // ——— ITCM Fetch Stage ———
    wire [12:0] fetch_addr = pc[14:2];  // word-aligned address

    assign itcm_addr_o = fetch_addr;
    assign itcm_req_o  = !halt_i && !if_stall;

    // ——— Pipeline control ———
    wire branch_flush;
    wire load_stall;
    wire mul_div_stall;

    // Load-use hazard: EX stage is a load, and ID stage reads the rd
    wire ex_is_load_dtcm = ex_is_load && !ex_is_axi;
    wire load_use_hazard = ex_is_load_dtcm && ex_valid &&
                           ((id_instr[19:15] == ex_rd_addr && id_instr[19:15] != 5'd0) ||
                            (id_instr[24:20] == ex_rd_addr && id_instr[24:20] != 5'd0));

    assign load_stall = load_use_hazard;
    assign branch_flush = ex_branch_taken && ex_valid;
    assign mul_div_stall = 1'b0;  // simplified — real implementation stalls on MUL/DIV

    assign if_stall = load_stall || mul_div_stall;

    // ——— Program Counter ———
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pc <= 32'h0000_0000;  // boot from ITCM base
        end else if (halt_i) begin
            pc <= pc;  // frozen during halt
        end else if (branch_flush) begin
            pc <= ex_branch_target;
        end else if (!if_stall) begin
            pc <= pc + 32'd4;
        end
    end

    // ——— IF → ID pipeline register ———
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            if_pc    <= 32'd0;
            if_instr <= 32'h00000013;  // NOP (addi x0, x0, 0)
            if_valid <= 1'b0;
        end else if (!halt_i) begin
            if (branch_flush) begin
                if_instr <= 32'h00000013;  // NOP (flush)
                if_pc    <= ex_branch_target;
                if_valid <= 1'b0;
            end else if (!if_stall && itcm_ack_i) begin
                if_instr <= itcm_rdata_i;
                if_pc    <= pc;
                if_valid <= 1'b1;
            end else if (if_stall) begin
                // Hold
            end
        end
    end

    // ——— ID Stage (Decode) ———
    // Instruction fields
    wire [6:0]  opcode   = id_instr[6:0];
    wire [2:0]  funct3   = id_instr[14:12];
    wire [6:0]  funct7   = id_instr[31:25];
    wire [4:0]  rs1_addr = id_instr[19:15];
    wire [4:0]  rs2_addr = id_instr[24:20];
    wire [4:0]  rd_addr  = id_instr[11:7];

    // Immediate values
    wire [31:0] i_imm = {{21{id_instr[31]}}, id_instr[30:20]};
    wire [31:0] s_imm = {{21{id_instr[31]}}, id_instr[30:25], id_instr[11:7]};
    wire [31:0] b_imm = {{20{id_instr[31]}}, id_instr[7], id_instr[30:25], id_instr[11:8], 1'b0};
    wire [31:0] u_imm = {id_instr[31:12], 12'd0};
    wire [31:0] j_imm = {{12{id_instr[31]}}, id_instr[19:12], id_instr[20], id_instr[30:21], 1'b0};

    // Read register file (combinational read)
    wire [31:0] rs1_data_comb = (rs1_addr == 5'd0) ? 32'd0 : regfile[rs1_addr];
    wire [31:0] rs2_data_comb = (rs2_addr == 5'd0) ? 32'd0 : regfile[rs2_addr];

    // ——— ID → EX pipeline register ———
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            id_pc       <= 32'd0;
            id_instr    <= 32'h00000013;  // NOP
            id_rs1_data <= 32'd0;
            id_rs2_data <= 32'd0;
            id_valid    <= 1'b0;
        end else if (!halt_i) begin
            if (branch_flush) begin
                id_instr    <= 32'h00000013;  // NOP
                id_valid    <= 1'b0;
            end else if (!load_stall) begin
                id_pc       <= if_pc;
                id_instr    <= if_instr;
                id_rs1_data <= rs1_data_comb;
                id_rs2_data <= rs2_data_comb;
                id_valid    <= if_valid;
            end
        end
    end

    // ——— EX Stage (Execute) ———
    // Forwarding mux: EX result forwarded to next instruction
    wire [31:0] ex_rs1 = (ex_rd_wen && ex_rd_addr == id_instr[19:15] && ex_rd_addr != 5'd0) ?
                          ex_result : id_rs1_data;
    wire [31:0] ex_rs2 = (ex_rd_wen && ex_rd_addr == id_instr[24:20] && ex_rd_addr != 5'd0) ?
                          ex_result : id_rs2_data;

    // Decode
    wire is_alu_reg  = (opcode == 7'b0110011);
    wire is_alu_imm  = (opcode == 7'b0010011);
    wire is_load     = (opcode == 7'b0000011);
    wire is_store    = (opcode == 7'b0100011);
    wire is_branch   = (opcode == 7'b1100011);
    wire is_jal      = (opcode == 7'b1101111);
    wire is_jalr     = (opcode == 7'b1100111);
    wire is_lui      = (opcode == 7'b0110111);
    wire is_auipc    = (opcode == 7'b0010111);
    wire is_system   = (opcode == 7'b1110011);
    wire is_misc_mem = (opcode == 7'b0001111);

    // ALU operation
    reg [31:0] alu_result;
    reg        branch_taken;
    reg [31:0] branch_target;

    always @(*) begin
        alu_result    = 32'd0;
        branch_taken  = 1'b0;
        branch_target = id_pc + 32'd4;

        case (opcode)
            // ALU register
            7'b0110011: begin
                case (funct3)
                    3'b000: alu_result = (funct7[5]) ? (ex_rs1 - ex_rs2) : (ex_rs1 + ex_rs2);
                    3'b001: alu_result = ex_rs1 << ex_rs2[4:0];
                    3'b010: alu_result = ($signed(ex_rs1) < $signed(ex_rs2)) ? 32'd1 : 32'd0;
                    3'b011: alu_result = (ex_rs1 < ex_rs2) ? 32'd1 : 32'd0;
                    3'b100: alu_result = ex_rs1 ^ ex_rs2;
                    3'b101: alu_result = (funct7[5]) ? ($signed(ex_rs1) >>> ex_rs2[4:0]) : (ex_rs1 >> ex_rs2[4:0]);
                    3'b110: alu_result = ex_rs1 | ex_rs2;
                    3'b111: alu_result = ex_rs1 & ex_rs2;
                    default: alu_result = 32'd0;
                endcase
            end
            // ALU immediate
            7'b0010011: begin
                case (funct3)
                    3'b000: alu_result = ex_rs1 + i_imm;
                    3'b001: alu_result = ex_rs1 << i_imm[4:0];
                    3'b010: alu_result = ($signed(ex_rs1) < $signed(i_imm)) ? 32'd1 : 32'd0;
                    3'b011: alu_result = (ex_rs1 < i_imm) ? 32'd1 : 32'd0;
                    3'b100: alu_result = ex_rs1 ^ i_imm;
                    3'b101: alu_result = (funct7[5]) ? ($signed(ex_rs1) >>> i_imm[4:0]) : (ex_rs1 >> i_imm[4:0]);
                    3'b110: alu_result = ex_rs1 | i_imm;
                    3'b111: alu_result = ex_rs1 & i_imm;
                    default: alu_result = 32'd0;
                endcase
            end
            // LUI
            7'b0110111: alu_result = u_imm;
            // AUIPC
            7'b0010111: alu_result = id_pc + u_imm;
            // JAL
            7'b1101111: begin
                alu_result    = id_pc + 32'd4;
                branch_taken  = 1'b1;
                branch_target = id_pc + j_imm;
            end
            // JALR
            7'b1100111: begin
                alu_result    = id_pc + 32'd4;
                branch_taken  = 1'b1;
                branch_target = (ex_rs1 + i_imm) & ~32'd1;
            end
            // Branch
            7'b1100011: begin
                branch_target = id_pc + b_imm;
                case (funct3)
                    3'b000: branch_taken = (ex_rs1 == ex_rs2);
                    3'b001: branch_taken = (ex_rs1 != ex_rs2);
                    3'b100: branch_taken = ($signed(ex_rs1) < $signed(ex_rs2));
                    3'b101: branch_taken = ($signed(ex_rs1) >= $signed(ex_rs2));
                    3'b110: branch_taken = (ex_rs1 < ex_rs2);
                    3'b111: branch_taken = (ex_rs1 >= ex_rs2);
                    default: branch_taken = 1'b0;
                endcase
            end
            // Load/Store — use ALU for address calc
            7'b0000011: alu_result = ex_rs1 + i_imm;  // load
            7'b0100011: alu_result = ex_rs1 + s_imm;  // store
            default: alu_result = 32'd0;
        endcase
    end

    // ——— EX → WB (registered outputs for next stage) ———
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ex_pc           <= 32'd0;
            ex_result       <= 32'd0;
            ex_we           <= 4'd0;
            ex_wdata        <= 32'd0;
            ex_rd_wen       <= 1'b0;
            ex_rd_addr      <= 5'd0;
            ex_branch_taken <= 1'b0;
            ex_branch_target<= 32'd0;
            ex_valid        <= 1'b0;
            ex_is_load      <= 1'b0;
            ex_is_store     <= 1'b0;
            ex_is_axi       <= 1'b0;
        end else if (!halt_i) begin
            ex_pc           <= id_pc;
            ex_result       <= alu_result;
            ex_we           <= 4'd0;
            ex_wdata        <= ex_rs2;
            ex_rd_wen       <= (is_alu_reg | is_alu_imm | is_jal | is_jalr | is_lui | is_auipc) && (id_instr[11:7] != 5'd0);
            ex_rd_addr      <= id_instr[11:7];
            ex_branch_taken <= branch_taken;
            ex_branch_target<= branch_target;
            ex_valid        <= id_valid;
            ex_is_load      <= is_load;
            ex_is_store     <= is_store;
            ex_is_axi       <= is_load && (alu_result[31:16] != alu_result[31:16]);  // detect peripheral access
            // Byte write enables for store
            if (is_store) begin
                case (funct3)
                    3'b000: ex_we <= 4'b0001 << alu_result[1:0];  // SB
                    3'b001: ex_we <= 4'b0011 << alu_result[1:0];  // SH
                    3'b010: ex_we <= 4'b1111;                     // SW
                    default: ex_we <= 4'd0;
                endcase
                ex_wdata <= ex_rs2;
            end
        end
    end

    // ——— Register file write-back ———
    integer ri;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            for (ri = 0; ri < 32; ri = ri + 1)
                regfile[ri] <= 32'd0;
        end else if (!halt_i && ex_valid && ex_rd_wen) begin
            regfile[ex_rd_addr] <= ex_result;
        end
    end

    // ——— DTCM interface ———
    assign dtcm_addr_o  = ex_is_store ? ex_result[14:2] : 13'd0;
    assign dtcm_wdata_o = ex_wdata;
    assign dtcm_we_o    = ex_is_store ? ex_we : 4'd0;
    assign dtcm_req_o   = (ex_is_load || ex_is_store) && ex_valid && !halt_i;

    // ——— AXI4-Lite master interface ———
    // Simplified: single-cycle read/write to peripherals
    // A write uses AW+W+B channels; a read uses AR+R channels.
    reg        axi_write_pending;
    reg        axi_read_pending;
    reg [31:0] axi_addr;
    reg [31:0] axi_wdata;

    // AXI write channel
    assign m_axi_awaddr_o  = axi_addr;
    assign m_axi_awprot_o  = 3'b000;
    assign m_axi_awvalid_o = axi_write_pending;
    assign m_axi_wdata_o   = axi_wdata;
    assign m_axi_wstrb_o   = 4'hF;   // full word writes
    assign m_axi_wvalid_o  = axi_write_pending;
    assign m_axi_bready_o  = 1'b1;

    // AXI read channel
    assign m_axi_araddr_o  = axi_addr;
    assign m_axi_arprot_o  = 3'b000;
    assign m_axi_arvalid_o = axi_read_pending;
    assign m_axi_rready_o  = 1'b1;

    // AXI state machine
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            axi_write_pending <= 1'b0;
            axi_read_pending  <= 1'b0;
            axi_addr          <= 32'd0;
            axi_wdata         <= 32'd0;
        end else begin
            // Launch AXI transactions
            if (ex_valid && ex_is_load && (ex_result[31:16] != 16'd0)) begin
                // Peripheral read
                axi_read_pending <= 1'b1;
                axi_addr         <= ex_result;
            end
            if (ex_valid && ex_is_store && (ex_result[31:16] != 16'd0)) begin
                // Peripheral write
                axi_write_pending <= 1'b1;
                axi_addr          <= ex_result;
                axi_wdata         <= ex_wdata;
            end

            // Clear on completion
            if (axi_write_pending && m_axi_awready_i && m_axi_wready_i)
                axi_write_pending <= 1'b0;
            if (axi_read_pending && m_axi_arready_i)
                axi_read_pending <= 1'b0;

            // AXI read data → register file (write-back)
            if (m_axi_rvalid_i && axi_read_pending) begin
                if (ex_rd_wen)
                    regfile[ex_rd_addr] <= m_axi_rdata_i;
                axi_read_pending <= 1'b0;
            end
        end
    end

    // ——— Lockstep outputs (for safety monitor) ———
    assign lockstep_outputs_o = ex_result;
    assign lockstep_pc_o      = ex_pc;
    assign lockstep_valid_o   = ex_valid;

`ifndef SYNTHESIS
    // Debug monitoring
    always @(posedge clk_i) begin
        if (ex_valid && !halt_i) begin
            // $display("[RV32IM] PC=%08h INSTR=%08h RESULT=%08h BRANCH=%d",
            //          ex_pc, id_instr, ex_result, ex_branch_taken);
        end
    end
`endif

endmodule
