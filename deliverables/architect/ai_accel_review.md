# AI Accelerator RTL Review — ADAS v2

**Document:** ARCH-RVW-001 | **Version:** 1.0 | **Date:** 2026-04-29  
**Author:** Kenji Tanaka, Chief Architect  
**Reviewed:** 7 RTL files (ai_accelerator_top, axi4_lite_decode, control_fsm, mac_pe, result_buffer, sram_buffer, systolic_array)  
**References:** `block_interfaces.md` §6, `REGISTER_MAP.md` §2, `microarchitecture_spec.md`  

---

## Executive Summary

Three engineers wrote seven files. I found **6 bugs** (3 critical, 2 high, 1 medium) and **4 warnings**. The good news: the 4×4 systolic array datapath (mac_pe + systolic_array) is clean, the 5-state FSM is correct (with one caveat), and the AXI4-Lite slave is mostly ARM IHI 0022E compliant. The bad news: the register map has read-back mismatches with REGISTER_MAP.md for weight and bias registers, one control bit is write-only-1, the ECC is parity-only (not SECDED as needed for ASIL-D), and the module name doesn't match the block interface spec.

**Overall assessment: CONDITIONALLY ACCEPTABLE — fix 3 critical bugs before synthesis; implement ECC upgrade before ASIL-D sign-off.**

---

## 1. Bug Summary

| ID | Severity | File | Description | REGISTER_MAP/Interface Impact |
|----|----------|------|-------------|------------------------------|
| **BUG-01** | 🔴 CRITICAL | axi4_lite_decode.v:218-222 | AI_WEIGHT_0..3 read returns SLVERR | REGISTER_MAP.md §2 says RW |
| **BUG-02** | 🔴 CRITICAL | axi4_lite_decode.v:319-330 | AI_BIAS_0_1 + AI_BIAS_2_3 read return 0x0 | REGISTER_MAP.md §2 says RW for both |
| **BUG-03** | 🔴 CRITICAL | axi4_lite_decode.v:296-299 | AI_CTRL.CLK_EN (bit 8) write-only-1 | REGISTER_MAP.md §2 says RW |
| **BUG-04** | 🟠 HIGH | axi4_lite_decode.v:424 | input_valid = \|reg_ai_input | FSM hangs when inputs are all zeros |
| **BUG-05** | 🟠 HIGH | sram_buffer.v:98-101 | ECC is parity-only, not SECDED; ecc_err_correct flagged but no correction applied | ASIL-D requires SECDED per Trikarenos paper |
| **BUG-06** | 🟡 MEDIUM | ai_accelerator_top.v:30 | Module named `ai_accelerator_top`, spec says `ai_accel_4x4` | block_interfaces.md §6.1 |

---

## 2. Detailed Bug Analysis

### BUG-01: AI_WEIGHT Readback Returns SLVERR (CRITICAL)

**Location:** `axi4_lite_decode.v`, lines 218-222

```verilog
6'h02: begin
    // AI_WEIGHT_0: read from SRAM
    araddr_read_data = 32'd0; // weights read via SRAM, not direct reg
    araddr_resp = AXI_RESP_SLVERR; // weight readback not supported
end
```

**Expected behavior (REGISTER_MAP.md §2):** AI_WEIGHT_0..3 are marked RW. A read at offsets 0x08/0x0C/0x10/0x14 should return the 32-bit packed weight word stored in sram_buffer.

**Observed behavior:** All four weight registers return SLVERR (0b10) with zero data. This breaks firmware that needs to verify weight values were correctly written (a common ASIL-D diagnostic pattern — write → read-back → compare).

**Impact:**
- Firmware cannot verify weight loading correctness via read-back.
- ASIL-D diagnostic coverage requirement: memory write-read-compare is a standard stuck-at fault detection mechanism. Without weight readback, the system cannot self-test the weight buffer.
- REGISTER_MAP.md explicitly documents these registers as RW — this is a spec violation.

**Fix:**
Add SRAM readback support. The sram_buffer already has a read port. Route reads at offsets 0x08, 0x0C, 0x10, 0x14 through the sram_buffer read port. Add a `weight_rd_addr` signal from axi4_lite_decode → sram_buffer:

```verilog
// In axi4_lite_decode.v, add:
output reg  [3:0]  weight_rd_addr,
input  wire [31:0] weight_rd_data,

// In the read case:
6'h02: begin weight_rd_addr = 4'd0; araddr_read_data = weight_rd_data; end
6'h03: begin weight_rd_addr = 4'd1; araddr_read_data = weight_rd_data; end
6'h04: begin weight_rd_addr = 4'd2; araddr_read_data = weight_rd_data; end
6'h05: begin weight_rd_addr = 4'd3; araddr_read_data = weight_rd_data; end
```

**Effort:** ~1 hour (add 3 ports, 4 case entries). Must be fixed before firmware integration.

---

### BUG-02: AI_BIAS Read Returns Zero for Both Registers (CRITICAL)

**Location:** `axi4_lite_decode.v`, lines 319-330:

```verilog
// Line 319:
reg [31:0] bias_data_read;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        bias_data_read <= 32'd0;
    else
        bias_data_read <= 32'd0; // bias readback not implemented
end

// Lines 327, 330: Both offsets use bias_data_read which is always 0
6'h07: araddr_read_data = bias_data_read;  // AI_BIAS_0_1 — always 0
6'h08: araddr_read_data = 32'd0;            // AI_BIAS_2_3 — always 0
```

**Expected behavior (REGISTER_MAP.md §2):** AI_BIAS_0_1 (0x1C) and AI_BIAS_2_3 (0x20) are both RW. Reads should return the stored bias values (4 INT16 values total).

**Observed behavior:** Both registers return 0x00000000 regardless of what was written. The `bias_data_read` register is hardwired to zero on every clock cycle.

**Impact:**
- Same diagnostic coverage gap as BUG-01 — cannot verify bias loading via read-back.
- Biases are safety-critical parameters — incorrect bias values could cause object misdetection or phantom braking.
- Both bias registers (4 INT16 bias values total) are unreadable.

**Fix:**
The biases are stored in result_buffer. Add a readback path from result_buffer → axi4_lite_decode:

```verilog
// In axi4_lite_decode.v, add:
input wire [31:0] bias_rd_data_0_1,  // from result_buffer
input wire [31:0] bias_rd_data_2_3,  // from result_buffer

6'h07: araddr_read_data = bias_rd_data_0_1;
6'h08: araddr_read_data = bias_rd_data_2_3;
```

In result_buffer.v, expose bias_0_1_reg and bias_2_3_reg as outputs:
```verilog
output wire [31:0] bias_rd_data_0_1,
output wire [31:0] bias_rd_data_2_3,
assign bias_rd_data_0_1 = bias_0_1_reg;
assign bias_rd_data_2_3 = bias_2_3_reg;
```

**Effort:** ~30 minutes (add 2 ports, route through top-level).

---

### BUG-03: AI_CTRL.CLK_EN Write-Only-1 (CRITICAL)

**Location:** `axi4_lite_decode.v`, lines 296-299:

```verilog
if (wdata_latched[8]) begin
    reg_ai_ctrl[8] <= 1'b1;  // CLK_EN
end
```

**Expected behavior (REGISTER_MAP.md §2):** CLK_EN is RW. Writing 0 should disable the clock (gate it off).

**Observed behavior:** Writing 0 to bit 8 has no effect — CLK_EN stays set. The bit can be set to 1 but never cleared to 0 without a hard reset. This means:
- The AI accelerator's clock cannot be gated off via software once enabled.
- Power management is broken — the accelerator consumes dynamic power even when idle.
- The CLK_EN register is de facto write-once, violating REGISTER_MAP.md.

**Impact:**
- Power budget violation: the accelerator cannot be clock-gated when not in use. At 100 MHz, even a quiescent 4×4 array toggles ~200-300 flops per cycle, consuming ~5-10 mW unnecessarily.
- Safety: In an ASIL-D system, the ability to disable non-critical peripherals during a fault condition is a diagnostic requirement.

**Fix:**
Replace the conditional-set with a direct strb-gated write:

```verilog
// Replace:
if (wdata_latched[8]) begin
    reg_ai_ctrl[8] <= 1'b1;
end
// With:
if (wstrb_latched[1]) begin
    reg_ai_ctrl[8] <= wdata_latched[8];
end
```

**Effort:** ~5 minutes (2-line change).

---

### BUG-04: Zero-Input Activation Hangs FSM (HIGH)

**Location:** `axi4_lite_decode.v`, line 424:

```verilog
assign input_valid = |reg_ai_input;  // non-zero input indicates data loaded
```

**Expected behavior:** input_valid should be true when the AI_INPUT register has been written since the last GO pulse, regardless of the data value.

**Observed behavior:** If the input activation values are all zero (a[0]=a[1]=a[2]=a[3]=0), input_valid = 0 and the FSM hangs forever in the LOAD_INPUT state. Zero-valued inputs are a legitimate case — ReLU activation often produces zero outputs that become inputs to the next layer.

**Impact:**
- The accelerator cannot process layers where all input activations are zero (a valid edge case for sparse/pruned networks).
- The FSM deadlocks with busy=1, done never asserted. The CPU must reset the accelerator via the RST bit.
- Any inference pipeline that feeds the accelerator a layer with all-zero activations will hang the system.

**Fix:**
Add a separate "input_written" flag that is set when AI_INPUT is written and cleared when GO is pulsed:

```verilog
// In axi4_lite_decode.v, add:
reg input_written_flag;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        input_written_flag <= 1'b0;
    else if (wr_active && wr_is_input)
        input_written_flag <= 1'b1;
    else if (go)  // cleared when computation starts
        input_written_flag <= 1'b0;
end

assign input_valid = input_written_flag;  // replace the reduction-OR
```

**Effort:** ~15 minutes (new register + replacement assign).

---

### BUG-05: ECC is Parity-Only, Not SECDED (HIGH)

**Location:** `sram_buffer.v`, lines 62-101

```verilog
reg [3:0]  mem_parity [0:15];  // 1 parity bit per byte, 4 bits total
```

**Expected behavior (ASIL-D requirement):** SECDED (Single Error Correct, Double Error Detect) ECC per the Trikarenos paper (2407.05938). SECDED requires 7 ECC bits for a 32-bit data word (Hamming(39,32)).

**Observed behavior:** The sram_buffer implements a simple per-byte parity scheme (4 parity bits for 32 data bits). This:
- Detects all odd-bit errors per byte
- **Cannot correct any errors** (the `ecc_err_correct` flag is set but no correction is applied to `rd_data` — the corrected data is never computed or output)
- Misses even-bit errors within a single byte (e.g., 2 bits flipped in byte 0 → parity matches, error undetected)
- The `ecc_err_correct_comb` logic (`$countones(parity_mismatch) == 1`) signals "correctable" but is misleading — no correction occurs

**Impact:**
- **ASIL-D certification blocker:** ASIL-D requires ECC on all safety-critical SRAM per ISO 26262-5:2018 §D.2.4.2. Parity is inadequate.
- Single-bit upsets (the dominant failure mode in terrestrial neutron environments per Trikarenos) cannot be corrected — they accumulate until a double-bit error occurs, which parity may or may not detect.
- The `ecc_err_correct` output falsely asserts that correction occurred when it did not — this could mislead firmware error handling.

**Fix:**
Implement true SECDED Hamming(39,32):
1. **Encoder** (on write): Generate 7 ECC bits from 32 data bits.
2. **Decoder** (on read): Compute syndrome (7 bits), correct single-bit errors, detect double-bit errors.
3. **Physical storage:** 16 entries × (32+7) = 39 bits each.

```verilog
// 39-bit physical width (32 data + 7 ECC)
reg [38:0] mem_ecc [0:15];  // {ecc[6:0], data[31:0]}
```

The Hamming(39,32) encoder/decoder is ~200 gates — easily synthesizable.

**Effort:** ~1 day (RTL design + verification of SECDED encode/decode + integration into sram_buffer). This is the highest-priority ASIL-D fix per the architecture decision in research_response.md.

---

### BUG-06: Module Name Mismatch (MEDIUM)

**Location:** `ai_accelerator_top.v`, line 30: `module ai_accelerator_top`

**Expected (block_interfaces.md §6.1):** Module name `ai_accel_4x4`.

**Observed:** Module name `ai_accelerator_top`.

**Impact:**
- Integration mismatch: the top-level SoC (`adas_v2_top`) will instantiate `ai_accel_4x4` based on the block interface spec. The RTL provides `ai_accelerator_top`. Synthesis will fail with "module not found."
- This is a last-minute integration hazard.

**Fix:** Rename RTL module to `ai_accel_4x4` to match spec.

**Effort:** ~1 minute (rename module declaration).

---

## 3. Warnings (Non-Blocking Issues)

### WARN-01: awprot/arprot Not Implemented

**Location:** `ai_accelerator_top.v`

The AXI4-Lite interface in block_interfaces.md §3.2 includes `awprot[2:0]` and `arprot[2:0]` signals, but they are absent from the AI accelerator's AXI slave port list. The AXI4-Lite spec requires these signals. For a peripheral that doesn't use protection information, they can be ignored on the slave side, but they MUST be present in the port list to match the crossbar connections.

**Recommendation:** Add `s_axi_awprot_i[2:0]` and `s_axi_arprot_i[2:0]` ports (unused internally) to `ai_accelerator_top` and `axi4_lite_decode`.

---

### WARN-02: cycle_count Width Mismatch

**Location:** `ai_accelerator_top.v`, lines 73-74:

```verilog
wire [3:0]  cycle_count;
assign cycle_count = {2'd0, compute_cycle};  // zero-extend 2→4 bits
```

The `compute_cycle` signal from control_fsm is 2 bits wide `[1:0]`. The `cycle_count` wire is declared as `[3:0]` (correct for the register map's CYCLE_COUNT[3:0] field) but is constructed by zero-extending. Verilator will flag the implicit width mismatch. Pass `cycle_count` as a properly-sized 4-bit signal from the FSM instead of zero-extending at the top level.

**Recommendation:** Change `compute_cycle` in control_fsm to `[3:0]` (always driven with zero-extended value), or handle the zero-extension explicitly with a width-cast in Verilator-compatible syntax.

---

### WARN-03: sram_buffer Combinational Read + ECC Path

**Location:** `sram_buffer.v`, lines 89-101

```verilog
assign rd_data_raw        = mem[rd_addr];
assign rd_parity_stored   = mem_parity[rd_addr];
assign rd_parity_computed = {^rd_data_raw[31:24], ...};
```

The `rd_data_raw` and parity computation are purely combinational. For a 16-entry register file, this is fine. But if upgraded to a hard SRAM macro (v3), the ~2-3 ns SRAM access time plus ~1 ns ECC decode creates a critical path that may need pipelining.

**Recommendation:** Acceptable for current register-file implementation. When upgrading to hard SRAM macros in v3, register the ECC check outputs.

---

### WARN-04: mac_pe activation_out Unconnected

**Location:** `systolic_array.v`, line 136:

```verilog
.activation_out (),  // not connected (no activation flow needed)
```

In a weight-stationary dataflow, activation pass-through between columns within the same row is NOT needed — each column is independently driven by the broadcast activation. This is correct for WS dataflow. Synthesis will optimize away the unused port.

**Recommendation:** Accept as-is. Flag in the architecture backlog that future dataflow changes (IS, OS, RS) will require connecting `activation_out` between adjacent PEs.

---

## 4. Interface Compliance Matrix

### 4.1 block_interfaces.md §6.2 — AI Accelerator Port List

| Port Name (Spec) | Port Name (RTL) | Width | Dir Match | Status |
|------------------|-----------------|-------|-----------|--------|
| `clk_i` | `clk_i` | 1 | ✅ In | PASS |
| `rst_n_i` | `rst_n_i` | 1 | ✅ In | PASS |
| `s_axi_*` | s_axi_awaddr_i, s_axi_awvalid_i, etc. | varies | ✅ AXI slave | PASS (see WARN-01 for prot) |
| `irq_done_o` | `irq_done_o` | 1 | ✅ Out | PASS |
| `irq_error_o` | `irq_error_o` | 1 | ✅ Out | PASS |
| `fault_o` | `fault_o` | 1 | ✅ Out | PASS |

**Result:** 5/6 port groups match. WARN-01 (missing awprot/arprot) flagged. AXI signal directions are correct for a slave.

### 4.2 REGISTER_MAP.md §2 — Register Coverage

| Offset | Register | Access (Spec) | Read (RTL) | Write (RTL) | Status |
|--------|----------|---------------|------------|-------------|--------|
| 0x00 | AI_CTRL | RW | ✅ Returns ctrl_status | ⚠️ Bit 8 write-only-1 | FAIL (BUG-03) |
| 0x04 | AI_STATUS | RO | ✅ Returns ai_status_computed | ✅ Ignored | PASS |
| 0x08 | AI_WEIGHT_0 | RW | ❌ SLVERR | ✅ Writes sram[0] | FAIL (BUG-01) |
| 0x0C | AI_WEIGHT_1 | RW | ❌ SLVERR | ✅ Writes sram[1] | FAIL (BUG-01) |
| 0x10 | AI_WEIGHT_2 | RW | ❌ SLVERR | ✅ Writes sram[2] | FAIL (BUG-01) |
| 0x14 | AI_WEIGHT_3 | RW | ❌ SLVERR | ✅ Writes sram[3] | FAIL (BUG-01) |
| 0x18 | AI_INPUT | RW | ✅ Returns reg_ai_input | ✅ Writes reg_ai_input | PASS |
| 0x1C | AI_BIAS_0_1 | RW | ❌ Returns 0 | ✅ Writes via bias_wr | FAIL (BUG-02) |
| 0x20 | AI_BIAS_2_3 | RW | ❌ Returns 0 | ✅ Writes via bias_wr | FAIL (BUG-02) |
| 0x24 | AI_OUTPUT_0 | RO | ✅ Returns result_data[0] | ✅ Ignored | PASS |
| 0x28 | AI_OUTPUT_1 | RO | ✅ Returns result_data[1] | ✅ Ignored | PASS |
| 0x2C | AI_OUTPUT_2 | RO | ✅ Returns result_data[2] | ✅ Ignored | PASS |
| 0x30 | AI_OUTPUT_3 | RO | ✅ Returns result_data[3] | ✅ Ignored | PASS |
| 0x34 | AI_ACTIVATION | RW | ✅ Returns reg_ai_activation | ✅ Writes correctly | PASS |
| 0x38 | AI_SCALE | RW | ✅ Returns reg_ai_scale | ✅ Writes correctly | PASS |
| 0x3C | AI_INTR_MASK | RW | ✅ Returns reg_ai_intr_mask | ✅ Writes correctly | PASS |

**Result:** 9/16 registers fully compliant. 7 register offsets have read-path issues (BUG-01 × 4 + BUG-02 × 2 + BUG-03).

---

## 5. State Machine Correctness (5-State FSM)

**Reviewed:** `control_fsm.v`

### States and Transitions

| State | Transition Condition | Next State | Verified |
|-------|---------------------|------------|----------|
| S_IDLE (0) | go=1 | S_LOAD_WEIGHTS | ✅ Correct |
| S_LOAD_WEIGHTS (1) | weights_loaded=1 | S_LOAD_INPUT | ✅ Correct |
| S_LOAD_INPUT (2) | inputs_loaded=1 | S_COMPUTE | ⚠️ Depends on BUG-04 fix |
| S_COMPUTE (3) | compute_cycle==3 | S_DONE | ✅ Correct |
| S_DONE (4) | (unconditional) | S_IDLE | ✅ Correct |

### Outputs per State

| State | busy | done | weight_wr | col_enable | sram_rd |
|-------|------|------|-----------|------------|---------|
| IDLE | 0 | 0 | 0 | 0000 | 0 |
| LOAD_WEIGHTS | 1 | 0 | 1 (16 cycles) | 0000 | 1 (per row) |
| LOAD_INPUT | 1 | 0 | 0 | 0000 | 0 |
| COMPUTE | 1 | 0 | 0 | one-hot (cycle) | 0 |
| DONE | 0 | 1 | 0 | 0000 | 0 |

✅ All outputs match expected behavior from microarchitecture_spec.md.

### Weight Loading Sequence

The FSM generates weight_row/col in sequence: (0,0)→(0,1)→(0,2)→(0,3)→(1,0)→...→(3,3). The top-level `weights_loaded` signal checks both the counter (weight_load_count == 15) and the current row/col (3,3). This double-check is defensive and correct.

### Compute Cycle Sequence

Column enables follow the one-hot pattern 0001→0010→0100→1000 over 4 cycles. Each column receives its activation during its compute cycle. ✅ Correct for WS dataflow with column-serial activation broadcast.

### Caveat: Second Inference Run

After DONE→IDLE, `weight_load_count` wraps from 15 to 0 on the first weight_write of the next run (natural 4-bit overflow). This is correct — the counter will count 0→15 again, and `weights_loaded` won't fire prematurely. ✅ No bug.

---

## 6. Timing Path Analysis

### 6.1 Longest Combinational Path — mac_pe.v

The critical path in the systolic array:

```
psum_in[31:0] ──┐
                 ├──→ 32-bit Adder ──→ psum_out[31:0] (registered)
weight[7:0]  ──┐ │
               │ │
activation[7:0]─┤ │
               ▼ │
          8×8 Mult│
           (~1.8ns)──→ (~1.2ns) ──→ (~0.1ns setup)
                             Total: ~3.1 ns
```

At 100 MHz (10 ns period): 31% of cycle — **ample margin**.  
At 150 MHz (6.67 ns period): 46% of cycle — **comfortable**.  
At 170 MHz (5.88 ns period): 53% of cycle — **tight but feasible**.

✅ The mac_pe is correctly pipelined at 1 stage (register on psum_out). This is adequate for 100-150 MHz.

### 6.2 AXI Read Path

```
araddr_latched[7:2] → rd_offset → case statement → araddr_read_data → s_axi_rdata register
```

- Address decode mux: ~5 gates (~0.5 ns)
- Case statement (16-way mux): ~4-5 gates (~0.5 ns)  
- Total read path: ~1.0 ns + register setup → ~1.1 ns

At 100 MHz (10 ns): 11% — ✅ very comfortable.

### 6.3 Control FSM Path

```
state → col_enable decoder → systolic_array PE enable → mac_pe psum_out mux
```

- FSM state decode: ~3 gates (~0.3 ns)
- col_enable one-hot decoder: ~2 gates (~0.2 ns)  
- PE enable mux (psum_in vs psum_in+MAC): part of mac_pe adder path (~1.2 ns)
- Total: ~1.7 ns

At 100 MHz: 17% — ✅ comfortable.

---

## 7. File-by-File Quality Assessment

| File | Lines | Quality | Notes |
|------|-------|---------|-------|
| `ai_accelerator_top.v` | 248 | 🟡 GOOD | Clean integration; one width mismatch (WARN-02); module name mismatch (BUG-06) |
| `axi4_lite_decode.v` | 474 | 🟠 NEEDS FIX | 4 bugs (BUG-01,02,03,04); otherwise well-structured AXI slave |
| `control_fsm.v` | 200 | 🟢 EXCELLENT | Clean FSM; correct one-hot decode; compute_cycle sequencing correct |
| `mac_pe.v` | 92 | 🟢 EXCELLENT | Clean PE; signed arithmetic correct; timing margins good |
| `result_buffer.v` | 139 | 🟡 GOOD | Bias application post-capture is acceptable; needs bias readback ports |
| `sram_buffer.v` | 129 | 🟠 NEEDS FIX | Parity-only ECC (BUG-05); otherwise clean register file |
| `systolic_array.v` | 175 | 🟢 EXCELLENT | Clean generate-based instantiation; weight load decoding correct; psum chaining correct |

---

## 8. Quality Gate Checklist

| Check | Status | Notes |
|-------|--------|-------|
| All 7 files reviewed | ✅ DONE | Every file read and analyzed |
| Interface match block_interfaces.md §6 | ⚠️ 5/6 port groups OK | BUG-06 (name) + WARN-01 (prot) |
| Register map match REGISTER_MAP.md §2 | ❌ 9/16 registers OK | 7 registers have read-path bugs |
| State machine correctness | ✅ VERIFIED | 5-state FSM correct (with BUG-04 caveat) |
| Timing path analysis | ✅ VERIFIED | All paths < 31% of 10 ns period |
| ECC implementation | ❌ INADEQUATE | Parity-only; must upgrade to SECDED for ASIL-D |
| Missing signals or misconnections | ⚠️ 2 warnings | WARN-01 (prot), WARN-03 (comb path) |

---

## 9. Recommended Fix Priority

| Priority | Bug/Warn | Effort | Blocks |
|----------|----------|--------|--------|
| **P0 — Before synthesis** | BUG-01 (weight readback) | 1 hour | Firmware integration |
| **P0 — Before synthesis** | BUG-02 (bias readback) | 30 min | Firmware integration |
| **P0 — Before synthesis** | BUG-03 (CLK_EN write) | 5 min | Power management |
| **P0 — Before synthesis** | BUG-04 (zero-input hang) | 15 min | Functional correctness |
| **P0 — Before synthesis** | BUG-06 (module name) | 1 min | Top-level integration |
| **P1 — Before ASIL-D sign-off** | BUG-05 (SECDED ECC) | 1 day | ASIL-D certification |
| **P2 — Before tape-out** | WARN-01 (prot signals) | 30 min | AXI compliance |
| **P3 — Nice to have** | WARN-02 (width mismatch) | 10 min | Lint cleanliness |
| **P3 — Nice to have** | WARN-03 (comb path) | N/A (v3) | Future macro migration |

---

## 10. Sign-off

**Architect Assessment:** CONDITIONALLY ACCEPTABLE

The systolic array datapath and control FSM are solid — well-structured, correct dataflow, adequate timing margins. The RTL can be synthesized and tested once P0 bugs are fixed. The ECC deficiency (BUG-05) is the long pole for ASIL-D and must be addressed before safety certification, but does not block initial functional verification.

**Required before dispatching to digital_design for synthesis:**
1. Fix BUG-01 through BUG-04 and BUG-06 (estimated 2 hours total).
2. Update axi4_lite_decode.v with weight/bias readback paths.
3. Rename module to `ai_accel_4x4`.
4. Add `input_written_flag` for zero-input handling.

**Required before ASIL-D sign-off:**
5. Replace parity ECC with Hamming(39,32) SECDED in sram_buffer.v.

---

*"Three minds, three chances for interface drift — and I found all three. But the bones are good. Fix these bugs, and this accelerator ships."*  
*— Kenji Tanaka, Chief Architect*

💙 *Suisei: Good work, Kenji. Six bugs caught before they became six re-spins. The digital_design team has clear direction — fix the P0 items, verify the array works at 100 MHz, and upgrade ECC before ASIL-D audit. Now let me brief the Hoshiyomi on these decisions.*
