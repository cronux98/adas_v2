# AI Accelerator Driver — SW→HW Mapping Verification Report
**Project:** adas_v2 | **Date:** 2026-04-30 | **Engineer:** Aiden Marsh
**Artifacts:** ai_accel_driver.h, ai_accel_driver.c, main.c, Makefile

---

## 1. REGISTER MAP VERIFICATION (Quality Gate 1)

All 16 register offsets in `ai_accel_driver.h` match `ai_accelerator_top.v` and `REGISTER_MAP.md §2` exactly:

| Register | Offset | RTL Source | Match |
|----------|--------|-----------|-------|
| AI_CTRL | 0x00 | axi4_lite_decode → ctrl_status | ✅ |
| AI_STATUS | 0x04 | control_fsm → busy/done/cycle_count | ✅ |
| AI_WEIGHT_0..3 | 0x08-0x14 | axi4_lite_decode → sram_buffer (wr) | ✅ |
| AI_INPUT | 0x18 | axi4_lite_decode → input_act_0..3 | ✅ |
| AI_BIAS_0_1/2_3 | 0x1C,0x20 | axi4_lite_decode → result_buffer (bias) | ✅ |
| AI_OUTPUT_0..3 | 0x24-0x30 | result_buffer → axi4_lite_decode (rd) | ✅ |
| AI_ACTIVATION | 0x34 | axi4_lite_decode → activation_fn | ✅ |
| AI_SCALE | 0x38 | axi4_lite_decode → scale_factor | ✅ |
| AI_INTR_MASK | 0x3C | axi4_lite_decode → irq_done_en/irq_error_en | ✅ |

**HAL co-inclusion fix:** Added `#ifndef` guards to all macros in `ai_accel_driver.h` (30 guards) to allow safe co-inclusion with `hal/ai_accel.h` without `-Werror` redefinition failures. Values are identical.

---

## 2. WEIGHT PACKING VERIFICATION (Quality Gate 2)

### Driver packing (ai_accel_driver.c:pack_4x8):
```
AI_WEIGHT_n[7:0]   = weights[row][0]  → PE[row][0] (col 0)
AI_WEIGHT_n[15:8]  = weights[row][1]  → PE[row][1] (col 1)
AI_WEIGHT_n[23:16] = weights[row][2]  → PE[row][2] (col 2)
AI_WEIGHT_n[31:24] = weights[row][3]  → PE[row][3] (col 3)
```

### RTL weight_byte mux (ai_accelerator_top.v:138-141):
```verilog
assign weight_byte = (weight_col_fsm == 2'd0) ? sram_rd_data[7:0]   :
                     (weight_col_fsm == 2'd1) ? sram_rd_data[15:8]  :
                     (weight_col_fsm == 2'd2) ? sram_rd_data[23:16] :
                                                sram_rd_data[31:24];
```

### Systolic array loading (systolic_array.v:89-95):
- During LOAD_WEIGHTS state (16 cycles), the FSM addresses PEs via `weight_row`/`weight_col`
- `PE[row][col]` receives `weight_data = weight_byte` when `weight_row=row AND weight_col=col`
- `wt_load_en[i][j] = weight_wr && (weight_row==i) && (weight_col==j)`

**Result:** The driver's INT8×4 packing (little-endian byte order within 32-bit word) matches the RTL's byte-level mux exactly. Self-test confirmed: `pack_4x8(0x12,0x34,0x56,0x78) = 0x78563412`.

---

## 3. OUTPUT INTERPRETATION (Quality Gate 3)

| RTL Output Row | Systolic Array | Driver Class | Enum Value |
|---------------|----------------|--------------|------------|
| result_0 (psum[0][4]) | Row 0: PE[0][0..3] | CAR | 0 |
| result_1 (psum[1][4]) | Row 1: PE[1][0..3] | PEDESTRIAN | 1 |
| result_2 (psum[2][4]) | Row 2: PE[2][0..3] | OBSTACLE | 2 |
| result_3 (psum[3][4]) | Row 3: PE[3][0..3] | NONE | 3 |

The SW model computes: `output[row] = Σ(col) weight[row][col] × activation[col]`
Classification is winner-take-all with Q16.16 confidence threshold (0.30).

---

## 4. BUILD RESULTS (Quality Gates 4, 6, 7)

| Metric | Value | Status |
|--------|-------|--------|
| Compiler warnings | 0 (with -Wall -Wextra -Werror) | ✅ |
| ITCM usage | 3,568 bytes / 8,192 (43.6%) | ✅ |
| DTCM usage | 2,488 bytes / 8,192 (30.4%) | ✅ |
| C-extension instructions | 0 | ✅ |
| Floating-point instructions | 0 | ✅ |
| Architecture | rv32im_zicsr_zifencei | ✅ |
| Optimization | -O2 | ✅ |

---

## 5. SELF-TEST RESULTS (Quality Gate 5)

Compiled with `-DAI_ACCEL_SELF_TEST` and run under Spike + pk:

```
Group 1: SW model correctness ........ 4/4 PASS
Group 2: INT8 packing correctness .... 4/4 PASS
Group 3: Classification correctness ... 8/8 PASS
Group 4: ADAS integration ............ 6/6 PASS
Group 5: Design constraints .......... 8/8 PASS
-----------------------------------------------
Total: 30/30 PASS (100%)
```

Test vectors include: identity, zero-activation, symmetric-negative, INT8-max overflow, CAR/PED/OBST/NONE scenarios, edge cases (all-negative, low-confidence).

---

## 6. FILES MODIFIED

| File | Change |
|------|--------|
| `firmware/ai_accel_driver.h` | Added `#ifndef` guards (30 macros) for HAL co-inclusion |
| `firmware/ai_accel_driver.c` | Added public `ai_accel_sw_compute()` wrapper |
| `firmware/Makefile` | Added `ai_accel_driver.c` to APP_C_SRCS + build rule; updated test target |
| `firmware/main.c` | Rewritten with full AI accelerator integration test |
| `firmware/linker.ld` | Moved `.rodata` into `.data` section (DTCM VMA, ITCM LMA) to fit code in 8KB ITCM |

---

## 7. KNOWN LIMITATIONS

1. **Spike MMIO:** The pipeline test in `main.c` runs `ai_accel_init_pipeline()` and `ai_accel_run()` which access MMIO at 0x00001000. Under Spike+pk, these reads return 0 (no AXI4-Lite crossbar). The driver correctly handles this — `ai_accel_poll_done()` times out gracefully. On real hardware with the `ai_accelerator_top.v` RTL, MMIO accesses would behave as documented.

2. **.rodata relocation:** String literals are in DTCM rather than ITCM to fit the 8KB budget. For production, consider a 16KB ITCM or split frequently-accessed constants back into ITCM.

3. **Weight SRAM ECC:** The driver's ASIL-D write-read-compare diagnostic (weight/bias readback) depends on BUG-01/BUG-02 RTL fixes being present in the synthesized netlist.

---

*Aiden Marsh, Firmware/Embedded Engineer — adas_v2 AI Accelerator Integration*
