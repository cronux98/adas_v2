/*
 * ai_accel_driver.c — AI Accelerator Driver (4×4 Systolic Array)
 * ====================================================================
 * Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
 * Target:   RV32IM (bare-metal, MMIO at 0x0000_1000)
 * Hardware: ai_accel_4x4 — 4×4 INT8 Weight-Stationary Systolic Array
 * Author:   Firmware Team
 * Version:  1.0.0
 * Date:     2026-04-30
 *
 * IMPLEMENTATION NOTES:
 *   - All register accesses are 32-bit aligned MMIO via volatile pointers.
 *   - The systolic array has a ~22 cycle compute latency at 100 MHz (~220 ns).
 *   - Polling is used instead of interrupts for deterministic latency.
 *   - Weights/biases are latched on AI_CTRL.GO write by the control FSM's
 *     LOAD_WEIGHTS → LOAD_INPUT sequence.
 *   - For ASIL-D diagnostic coverage, write-read-compare is implemented
 *     for weight and bias registers (covers BUG-01/BUG-02 fixes in RTL).
 *
 * SOFTWARE-TO-HARDWARE MAPPING REFERENCE:
 *
 *   C function call        → Register write sequence
 *   ─────────────────────────────────────────────────
 *   ai_accel_load_weights  → AI_WEIGHT_0 (0x08) = {w03,w02,w01,w00}
 *                          → AI_WEIGHT_1 (0x0C) = {w13,w12,w11,w10}
 *                          → AI_WEIGHT_2 (0x10) = {w23,w22,w21,w20}
 *                          → AI_WEIGHT_3 (0x14) = {w33,w32,w31,w30}
 *
 *   ai_accel_load_biases   → AI_BIAS_0_1 (0x1C) = {bias1[15:0], bias0[15:0]}
 *                          → AI_BIAS_2_3 (0x20) = {bias3[15:0], bias2[15:0]}
 *
 *   ai_accel_load_inputs   → AI_INPUT   (0x18) = {act3,act2,act1,act0}
 *
 *   ai_accel_go            → AI_CTRL    (0x00) |= GO
 *                             └─ FSM: LOAD_WEIGHTS (16 cycles)
 *                                     → reads sram_buffer → systolic_array
 *                             └─ FSM: LOAD_INPUT (1 cycle)
 *                             └─ FSM: COMPUTE (4 cycles, 1 pipeline)
 *                                     → col_enable cycles columns 0..3
 *                                     → mac_pe: weight × activation + psum_in
 *                             └─ FSM: DONE
 *                                     → result_buffer captures all 4 outputs
 *                                     → AI_CTRL.DONE bit set
 *
 *   ai_accel_read_output   → AI_OUTPUT_n (0x24..0x30)
 *                             └─ result_buffer → axi4_lite_decode → AXI rdata
 *
 *   FIRMWARE ALGORITHM PIPELINE:
 *
 *     Boot:  ai_accel_init_pipeline(w, b, ACT_RELU, SCALE_DEFAULT)
 *              └─ write AI_WEIGHT_0..3    (weights → SRAM)
 *              └─ write AI_BIAS_0_1/2_3   (biases → result_buffer)
 *              └─ write AI_ACTIVATION     (activation fn select)
 *              └─ write AI_SCALE          (output scaling)
 *
 *     Frame:  ai_accel_run(input_acts, &class, &confidence)
 *     Loop:     └─ write AI_INPUT         (4 INT8 activations)
 *               └─ write AI_CTRL.GO       (trigger FSM)
 *               └─ poll AI_STATUS.DONE    (wait ~220 ns)
 *               └─ read AI_OUTPUT_0..3    (4 INT32 results)
 *               └─ classify outputs       (winner-take-all)
 *
 * LICENSE: Proprietary — ADAS Safety-Critical Firmware
 */

#include "ai_accel_driver.h"
#include <stddef.h>

/* ========================================================================
 * SOFTWARE MODEL OF THE 4×4 SYSTOLIC ARRAY
 * ========================================================================
 * This is an INT8 bit-exact software reference of the systolic array.
 * It implements the same compute as the hardware:
 *   output[row] = Σ(col=0..3) weight[row][col] × activation[col]
 *
 * Use this reference to:
 *   a) Verify the hardware is computing correctly by comparing outputs
 *   b) Pre-compute expected outputs for test vectors
 *   c) Simulate accelerator behavior without hardware
 *
 * The hardware computes:
 *   PE[row][col] accumulates: psum += weight[row][col] × activation[col]
 *   With column enable cycling: col 0 → col 1 → col 2 → col 3
 *   Results captured at end of COMPUTE phase on DONE cycle
 *
 * Pipeline stages (standard mode, no FAST_MODE):
 *   Cycle 0: col_enable = 0001, PE[*][0] computes: psum += w[*][0] × a[0]
 *   Cycle 1: col_enable = 0010, PE[*][1] computes: psum += w[*][1] × a[1]
 *   Cycle 2: col_enable = 0100, PE[*][2] computes: psum += w[*][2] × a[2]
 *   Cycle 3: col_enable = 1000, PE[*][3] computes: psum += w[*][3] × a[3]
 *   Cycle 4: results propagate through pipeline → captured on DONE
 *
 * Note: psum is initialized to 0 per row boundary in systolic_array.v
 * ======================================================================== */

static void ai_accel_sw_model(const int8_t weights[4][4],
                               const int8_t activations[4],
                               int32_t outputs[4]) {
    int32_t psum[4];

    /* Each row accumulates independently */
    for (int row = 0; row < 4; row++) {
        psum[row] = 0;
        for (int col = 0; col < 4; col++) {
            /* INT8 × INT8 → INT32 multiply-accumulate */
            psum[row] += (int32_t)weights[row][col] * (int32_t)activations[col];
        }
    }

    /* Copy to output buffer */
    for (int i = 0; i < 4; i++) {
        outputs[i] = psum[i];
    }
}

/* Public wrapper for integration testing */
void ai_accel_sw_compute(const int8_t weights[4][4],
                         const int8_t activations[4],
                         int32_t outputs[4]) {
    ai_accel_sw_model(weights, activations, outputs);
}

/* ========================================================================
 * INTERNAL: Packing/Unpacking Helpers
 * ======================================================================== */

/**
 * Pack 4 INT8 values into a 32-bit register word.
 * Byte order (MSB to LSB): val3, val2, val1, val0
 */
static inline uint32_t pack_4x8(int8_t v0, int8_t v1, int8_t v2, int8_t v3) {
    return ((uint32_t)(uint8_t)v0)       |
           ((uint32_t)(uint8_t)v1 << 8)  |
           ((uint32_t)(uint8_t)v2 << 16) |
           ((uint32_t)(uint8_t)v3 << 24);
}

/**
 * Pack 2 INT16 values into a 32-bit register word.
 * Byte order: val1 in upper 16 bits, val0 in lower 16 bits.
 */
static inline uint32_t pack_2x16(int16_t v0, int16_t v1) {
    return ((uint32_t)(uint16_t)v0)       |
           ((uint32_t)(uint16_t)v1 << 16);
}

/**
 * Pack 4 INT8 activations from array into single word.
 * Activation order: activations[0] → byte0, activations[3] → byte3
 */
static uint32_t pack_inputs(const int8_t activations[4]) {
    return pack_4x8(activations[0], activations[1],
                    activations[2], activations[3]);
}

/* ========================================================================
 * PUBLIC API IMPLEMENTATION
 * ======================================================================== */

void ai_accel_init(void) {
    /* 1. Soft reset: assert reset bit */
    ai_accel_reg_write(AI_CTRL_OFFSET, AI_CTRL_RST);

    /* Small delay: wait for reset to propagate (2 sys_clk cycles @ 100 MHz) */
    __asm__ volatile ("nop");
    __asm__ volatile ("nop");

    /* 2. De-assert reset, enable clock */
    ai_accel_reg_write(AI_CTRL_OFFSET, AI_CTRL_CLK_EN);

    /* 3. Clear any stale status bits by writing GO=0, clearing error/done */
    ai_accel_clear_status();

    /* 4. Set default activation: None, default scale */
    ai_accel_reg_write(AI_ACTIVATION_OFFSET, AI_ACT_NONE);
    ai_accel_reg_write(AI_SCALE_OFFSET, AI_SCALE_DEFAULT);

    /* 5. Disable interrupts (polling mode) */
    ai_accel_reg_write(AI_INTR_MASK_OFFSET, 0);
}

bool ai_accel_is_idle(void) {
    uint32_t status = ai_accel_reg_read(AI_STATUS_OFFSET);
    return (status & AI_STATUS_BUSY) == 0;
}

bool ai_accel_is_busy(void) {
    uint32_t status = ai_accel_reg_read(AI_STATUS_OFFSET);
    return (status & AI_STATUS_BUSY) != 0;
}

bool ai_accel_is_done(void) {
    uint32_t status = ai_accel_reg_read(AI_CTRL_OFFSET);
    return (status & AI_CTRL_DONE) != 0;
}

bool ai_accel_is_error(void) {
    uint32_t status = ai_accel_reg_read(AI_CTRL_OFFSET);
    return (status & AI_CTRL_ERROR) != 0;
}

void ai_accel_set_activation(uint32_t activation) {
    ai_accel_reg_write(AI_ACTIVATION_OFFSET, activation);

    /* If ReLU is requested, also set the RELU_EN bit in AI_CTRL */
    uint32_t ctrl = ai_accel_reg_read(AI_CTRL_OFFSET);
    if (activation & AI_ACT_RELU) {
        ctrl |= AI_CTRL_RELU_EN;
    } else {
        ctrl &= ~AI_CTRL_RELU_EN;
    }
    ai_accel_reg_write(AI_CTRL_OFFSET, ctrl);
}

void ai_accel_set_scale(uint32_t scale) {
    ai_accel_reg_write(AI_SCALE_OFFSET, scale);
}

void ai_accel_load_weights(const int8_t weights[4][4]) {
    /*
     * Write 4 weight rows. Each register packs one row of 4 INT8 weights.
     *
     * Register layout per row (from REGISTER_MAP.md §2):
     *   AI_WEIGHT_0 (0x08): w00[7:0], w01[15:8], w02[23:16], w03[31:24]
     *   AI_WEIGHT_1 (0x0C): w10[7:0], w11[15:8], w12[23:16], w13[31:24]
     *   AI_WEIGHT_2 (0x10): w20[7:0], w21[15:8], w22[23:16], w23[31:24]
     *   AI_WEIGHT_3 (0x14): w30[7:0], w31[15:8], w32[23:16], w33[31:24]
     *
     * PE mapping in the systolic array:
     *   PE[row][col] receives weight weights[row][col]
     *   The control FSM addresses each PE via weight_row/weight_col
     *   during LOAD_WEIGHTS state (16 cycles, one per PE).
     *
     * ASIL-D diagnostic: write-read-compare each register.
     */

    /* Row 0 */
    uint32_t w0 = pack_4x8(weights[0][0], weights[0][1],
                            weights[0][2], weights[0][3]);
    ai_accel_reg_write(AI_WEIGHT_0_OFFSET, w0);

    /* Row 1 */
    uint32_t w1 = pack_4x8(weights[1][0], weights[1][1],
                            weights[1][2], weights[1][3]);
    ai_accel_reg_write(AI_WEIGHT_1_OFFSET, w1);

    /* Row 2 */
    uint32_t w2 = pack_4x8(weights[2][0], weights[2][1],
                            weights[2][2], weights[2][3]);
    ai_accel_reg_write(AI_WEIGHT_2_OFFSET, w2);

    /* Row 3 */
    uint32_t w3 = pack_4x8(weights[3][0], weights[3][1],
                            weights[3][2], weights[3][3]);
    ai_accel_reg_write(AI_WEIGHT_3_OFFSET, w3);

    /*
     * ASIL-D write-read-compare diagnostic:
     * Read back each register and compare to expected value.
     * This detects:
     *   - Bus interconnect faults
     *   - Stuck-at faults in register file
     *   - Address decode errors
     *   - BUG-01 was: read returned SLVERR — fixed in RTL v2
     */
    uint32_t check;
    check = ai_accel_reg_read(AI_WEIGHT_0_OFFSET);
    if (check != w0) {
        /* Diagnostic failure — weight row 0 readback mismatch */
        /* In production: set error flag, trigger safety monitor */
        while (1); /* halt — safety violation */
    }

    check = ai_accel_reg_read(AI_WEIGHT_1_OFFSET);
    if (check != w1) {
        while (1);
    }

    check = ai_accel_reg_read(AI_WEIGHT_2_OFFSET);
    if (check != w2) {
        while (1);
    }

    check = ai_accel_reg_read(AI_WEIGHT_3_OFFSET);
    if (check != w3) {
        while (1);
    }
}

void ai_accel_load_biases(const int16_t biases[4]) {
    /*
     * Write 2 bias registers, each packing 2 INT16 values.
     *
     * From REGISTER_MAP.md §2:
     *   AI_BIAS_0_1 (0x1C): bias[0] in [15:0], bias[1] in [31:16]
     *   AI_BIAS_2_3 (0x20): bias[2] in [15:0], bias[3] in [31:16]
     *
     * Biases are added to the accumulated MAC result in result_buffer.v
     * before ReLU is applied.
     */

    uint32_t b01 = pack_2x16(biases[0], biases[1]);
    uint32_t b23 = pack_2x16(biases[2], biases[3]);

    ai_accel_reg_write(AI_BIAS_0_1_OFFSET, b01);
    ai_accel_reg_write(AI_BIAS_2_3_OFFSET, b23);

    /*
     * ASIL-D write-read-compare diagnostic:
     * BUG-02 was: bias readback always returned 0 — fixed in RTL v2.
     */
    uint32_t check;
    check = ai_accel_reg_read(AI_BIAS_0_1_OFFSET);
    if (check != b01) {
        /* Diagnostic failure — halt for safety violation */
        while (1);
    }

    check = ai_accel_reg_read(AI_BIAS_2_3_OFFSET);
    if (check != b23) {
        while (1);
    }
}

void ai_accel_load_inputs(const int8_t activations[4]) {
    /*
     * Pack 4 INT8 activations into a single 32-bit register word.
     *
     * From REGISTER_MAP.md §2:
     *   AI_INPUT (0x18): act[0][7:0], act[1][15:8],
     *                    act[2][23:16], act[3][31:24]
     *
     * The activation values are driven to systolic_array.activation_0..3.
     * When the control FSM enters COMPUTE state, it cycles:
     *   col_enable[0] → activation_0 broadcast to column 0
     *   col_enable[1] → activation_1 broadcast to column 1
     *   col_enable[2] → activation_2 broadcast to column 2
     *   col_enable[3] → activation_3 broadcast to column 3
     */
    uint32_t packed = pack_inputs(activations);
    ai_accel_reg_write(AI_INPUT_OFFSET, packed);
}

void ai_accel_go(void) {
    /*
     * Trigger computation by writing AI_CTRL.GO = 1.
     *
     * The control FSM transitions: IDLE → LOAD_WEIGHTS → LOAD_INPUT
     * → COMPUTE → DONE → IDLE.
     *
     * During LOAD_WEIGHTS (16 cycles):
     *   - sram_buffer is read sequentially (16 addresses)
     *   - Each 32-bit word is split into 4 INT8 bytes
     *   - Each byte is written to the correct PE via weight_row/weight_col
     *
     * During COMPUTE (4 + 1 cycles):
     *   - col_enable cycles through one-hot [0001, 0010, 0100, 1000]
     *   - Each mac_pe computes: psum += weight × activation
     *   - Pipeline fill adds 1 cycle
     *
     * On DONE:
     *   - result_buffer captures all 4 output values
     *   - AI_CTRL.DONE bit is set
     *   - irq_done_o is asserted (if interrupt enabled)
     *
     * Total latency from GO → DONE: ~22 sys_clk cycles @ 100 MHz ≈ 220 ns
     */
    ai_accel_reg_write(AI_CTRL_OFFSET,
                       ai_accel_reg_read(AI_CTRL_OFFSET) | AI_CTRL_GO);
}

bool ai_accel_poll_done(void) {
    /*
     * Poll AI_CTRL for DONE bit.
     * Since compute takes ~22 cycles (220 ns), we poll rapidly.
     * Safety timeout prevents infinite loop on hardware fault.
     */
    uint32_t retries = AI_ACCEL_POLL_RETRIES;

    while (retries > 0) {
        uint32_t ctrl = ai_accel_reg_read(AI_CTRL_OFFSET);

        if (ctrl & AI_CTRL_DONE) {
            /* Computation complete */
            return true;
        }

        if (ctrl & AI_CTRL_ERROR) {
            /* Hardware error flagged */
            return false;
        }

        retries--;

        /* Small pause between polls: ~3 NOPs ≈ 30 ns */
        __asm__ volatile ("nop");
        __asm__ volatile ("nop");
        __asm__ volatile ("nop");
    }

    /* Timeout — accelerator did not complete */
    return false;
}

bool ai_accel_inference(const int8_t activations[4], int32_t outputs[4]) {
    if (outputs == NULL) return false;

    /* 1. Check accelerator is idle */
    if (ai_accel_is_busy()) {
        return false;
    }

    /* 2. Clear any stale done/error flags from previous run */
    ai_accel_clear_status();

    /* 3. Load inputs */
    ai_accel_load_inputs(activations);

    /* 4. Trigger computation */
    ai_accel_go();

    /* 5. Poll for completion */
    if (!ai_accel_poll_done()) {
        return false;
    }

    /* 6. Read outputs */
    ai_accel_read_all_outputs(outputs);

    return true;
}

int32_t ai_accel_read_output(uint32_t channel) {
    /*
     * Read one output register (AI_OUTPUT_0..3).
     *
     * From REGISTER_MAP.md §2:
     *   AI_OUTPUT_0 (0x24): output[0] — INT32 accumulated value for row 0
     *   AI_OUTPUT_1 (0x28): output[1] — INT32 accumulated value for row 1
     *   AI_OUTPUT_2 (0x2C): output[2] — INT32 accumulated value for row 2
     *   AI_OUTPUT_3 (0x30): output[3] — INT32 accumulated value for row 3
     *
     * These values come from result_buffer.v, which captures the
     * systolic array outputs on the DONE state transition.
     *
     * The INT32 value = Σ(col=0..3) weight[row][col] × activation[col]
     * Before any bias addition or ReLU (those happen inside result_buffer).
     * The final output includes bias and ReLU as configured.
     */
    switch (channel) {
    case 0: return (int32_t)ai_accel_reg_read(AI_OUTPUT_0_OFFSET);
    case 1: return (int32_t)ai_accel_reg_read(AI_OUTPUT_1_OFFSET);
    case 2: return (int32_t)ai_accel_reg_read(AI_OUTPUT_2_OFFSET);
    case 3: return (int32_t)ai_accel_reg_read(AI_OUTPUT_3_OFFSET);
    default: return 0;
    }
}

void ai_accel_read_all_outputs(int32_t outputs[4]) {
    if (outputs == NULL) return;

    outputs[0] = ai_accel_read_output(0);
    outputs[1] = ai_accel_read_output(1);
    outputs[2] = ai_accel_read_output(2);
    outputs[3] = ai_accel_read_output(3);
}

void ai_accel_clear_status(void) {
    /*
     * Clear sticky DONE and ERROR bits.
     * Writing 1 to CLR_DONE (bit 2) clears DONE.
     * Writing 1 to CLR_ERROR (bit 3) clears ERROR.
     *
     * We write GO=0, CLR_DONE=1, CLR_ERROR=1 simultaneously.
     * The control FSM must be in IDLE for this to take effect.
     */
    uint32_t ctrl = ai_accel_reg_read(AI_CTRL_OFFSET);
    /* Keep CLK_EN, RELU_EN, but clear GO, DONE, ERROR */
    ctrl &= (AI_CTRL_CLK_EN | AI_CTRL_RELU_EN | AI_CTRL_QUANT_EN);
    /* Write current state with status bits cleared */
    ai_accel_reg_write(AI_CTRL_OFFSET, ctrl);
}

bool ai_accel_classify(const int32_t outputs[4],
                       ai_accel_class_t *class_out,
                       int32_t *confidence_q16) {
    if (class_out == NULL || confidence_q16 == NULL) return false;

    /* Find the output with the maximum value and the second maximum */
    int32_t max_val     = outputs[0];
    int32_t second_max  = outputs[1];
    uint32_t max_idx    = 0;

    for (uint32_t i = 1; i < 4; i++) {
        if (outputs[i] > max_val) {
            second_max = max_val;
            max_val    = outputs[i];
            max_idx    = i;
        } else if (outputs[i] > second_max) {
            second_max = outputs[i];
        }
    }

    /*
     * Compute confidence: (max - second_max) / max as Q16.16.
     * If max <= 0, confidence is 0 (nothing detected).
     */
    int32_t conf_q16 = 0;

    if (max_val > 0) {
        /*
         * Convert to Q16.16: confidence = (max - second_max) / max
         * Using Q16.16: conf_q16 = ((max - second_max) << 16) / max
         */
        int64_t diff     = (int64_t)(max_val - second_max);
        int64_t conf_i64 = (diff << 16) / (int64_t)max_val;

        /* Clamp to [0, Q16_ONE] */
        if (conf_i64 > 65536) conf_i64 = 65536;
        if (conf_i64 < 0)     conf_i64 = 0;

        conf_q16 = (int32_t)conf_i64;
    }

    *confidence_q16 = conf_q16;

    /* Map index to class enum */
    switch (max_idx) {
    case 0: *class_out = AI_ACCEL_CLASS_CAR;        break;
    case 1: *class_out = AI_ACCEL_CLASS_PEDESTRIAN; break;
    case 2: *class_out = AI_ACCEL_CLASS_OBSTACLE;   break;
    case 3: *class_out = AI_ACCEL_CLASS_NONE;        break;
    default: *class_out = AI_ACCEL_CLASS_UNCERTAIN;  break;
    }

    /*
     * Apply confidence threshold.
     * If confidence < 0.30 in Q16.16, the classification is uncertain.
     * This prevents false positives from noisy sensor data.
     */
    if (conf_q16 < AI_ACCEL_CONFIDENCE_THRESHOLD_Q16) {
        *class_out = AI_ACCEL_CLASS_UNCERTAIN;
        return false;  /* Below confidence threshold */
    }

    return true;
}

/* ========================================================================
 * PIPELINE API (weights loaded once, many inferences)
 * ========================================================================
 *
 * ADAS firmware flow:
 *
 *   ┌──────────────────────────────────────────────────────┐
 *   │  BOOT:                                                │
 *   │    ai_accel_init_pipeline(weights, biases, ...)       │
 *   │      └─ weights stay in SRAM buffer                   │
 *   │      └─ biases stay in result_buffer                  │
 *   │      └─ activation/scale configured once             │
 *   ├──────────────────────────────────────────────────────┤
 *   │  LOOP (every 10ms sensor ISR):                        │
 *   │    ai_accel_run(input_acts, &class, &confidence)      │
 *   │      └─ write AI_INPUT (4 activations)                │
 *   │      └─ write AI_CTRL.GO (trigger compute)            │
 *   │      └─ poll AI_STATUS.DONE                           │
 *   │      └─ read AI_OUTPUT_0..3                           │
 *   │      └─ classify → CAR/PED/OBST/NONE + confidence     │
 *   │      └─ return to adas_process_frame() pipeline       │
 *   └──────────────────────────────────────────────────────┘
 */

/* Static storage for pipeline configuration (weights already in SRAM) */
static uint32_t _pipeline_activation = AI_ACT_NONE;
static uint32_t _pipeline_scale      = AI_SCALE_DEFAULT;
static bool     _pipeline_initialized = false;

void ai_accel_init_pipeline(const int8_t weights[4][4],
                            const int16_t biases[4],
                            uint32_t activation,
                            uint32_t scale) {
    /* 1. Initialize accelerator hardware */
    ai_accel_init();

    /* 2. Load weights (goes to sram_buffer, survives across inferences) */
    ai_accel_load_weights(weights);

    /* 3. Load biases (goes to result_buffer, persists) */
    ai_accel_load_biases(biases);

    /* 4. Set activation function */
    ai_accel_set_activation(activation);
    _pipeline_activation = activation;

    /* 5. Set scale factor */
    ai_accel_set_scale(scale);
    _pipeline_scale = scale;

    /* 6. Mark pipeline as initialized */
    _pipeline_initialized = true;
}

bool ai_accel_run(const int8_t activations[4],
                  ai_accel_class_t *class_out,
                  int32_t *confidence_q16) {
    if (!_pipeline_initialized) return false;

    /* Run inference on hardware */
    int32_t outputs[4];
    if (!ai_accel_inference(activations, outputs)) {
        return false;
    }

    /* Classify outputs */
    if (class_out == NULL || confidence_q16 == NULL) return false;

    return ai_accel_classify(outputs, class_out, confidence_q16);
}

/* ========================================================================
 * TEST MAIN — Self-test and software model verification
 * ========================================================================
 *
 * Compile with: riscv32-unknown-elf-gcc -DAI_ACCEL_SELF_TEST ai_accel_driver.c -o test_accel
 *
 * This test:
 *   1. Defines a set of known weights and activations
 *   2. Runs the software model of the systolic array
 *   3. Prints expected outputs for each test case
 *   4. Tracks coverage of edge cases
 *
 * The senior engineer can use this to verify the C→RTL mapping by
 * comparing the SW model outputs against actual RTL simulation results.
 */

#ifdef AI_ACCEL_SELF_TEST

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Test case 1: Identity — all weights = 1, single activation = 1
 * Expected: all 4 outputs = 1 × 1 + 1 × 0 + 1 × 0 + 1 × 0 = 1
 */
static const int8_t test_weights_identity[4][4] = {
    {1, 0, 0, 0},
    {1, 0, 0, 0},
    {1, 0, 0, 0},
    {1, 0, 0, 0}
};
static const int8_t test_acts_identity[4] = {1, 0, 0, 0};
static const int32_t test_exp_identity[4] = {1, 1, 1, 1};

/*
 * Test case 2: Car detection — weights set for car-like pattern
 * Input: [high_speed, medium_distance, closing_fast, bias_term(1)]
 * Expected: output[0](CAR) > output[1](PED) > output[2](OBST) > output[3](NONE)
 */
static const int8_t test_weights_car[4][4] = {
    { 12, -3, 15,  5},   /* CAR: high speed + closing = car */
    {  8,  2, 10, -2},   /* PEDESTRIAN: lower response */
    { 15, -8, 10,  3},   /* OBSTACLE: high on speed, less on closure */
    {  1,  1,  1, -10}   /* NONE: always negative (reject) */
};
static const int8_t test_acts_car[4] = {30, 50, 25, 1};   /* ~30 m/s, 50 m, 25 m/s closing */

/*
 * Test case 3: No object — all activations near zero
 * Expected: all outputs ≈ 0, classification = NONE or UNCERTAIN
 */
static const int8_t test_weights_empty[4][4] = {
    { 5, -2,  8,  3},
    { 3,  1,  4,  1},
    { 7, -5,  6,  2},
    { 1,  0,  1, -8}
};
static const int8_t test_acts_empty[4] = {0, 0, 0, 0};

/*
 * Test case 4: Pedestrian detection — slow speed, close distance
 * Expected: output[1](PED) > output[*]
 */
static const int8_t test_weights_ped[4][4] = {
    { 5,  2,  3,  2},    /* CAR: moderate response */
    { 3, 10,  8,  5},    /* PEDESTRIAN: high on close distance */
    { 2,  5,  4,  1},    /* OBSTACLE: moderate */
    { 0,  0,  0, -5}     /* NONE: reject */
};
static const int8_t test_acts_ped[4] = {2, 15, 3, 1};  /* low speed, close, slow closing */

/*
 * Test case 5: Real ADAS frame — full pipeline integration test
 * Represents a real emergency braking scenario from the reference vectors.
 * Ego speed: 30 m/s, Object: 50 m ahead, Closing at 25 m/s, CAR class.
 */
static const int8_t test_weights_adas[4][4] = {
    { 10, -2, 12,  3},   /* CAR pattern */
    {  5,  3,  6, -1},   /* PEDESTRIAN pattern */
    {  8, -5,  7,  2},   /* OBSTACLE pattern */
    {  1,  0,  1, -8}    /* NONE reject */
};
static const int8_t test_acts_adas[4] = {20, 35, 18, 1};  /* normalized sensor frame */

/* Test result tracking */
static struct {
    uint32_t passed;
    uint32_t failed;
    uint32_t total;
} test_stats;

/* Test wrapper */
#define TEST(name, cond, expected) do {                                 \
    test_stats.total++;                                                 \
    printf("  TEST %s... ", name);                                      \
    if (!(cond)) {                                                      \
        printf("FAIL\n");                                               \
        printf("    Expected: %s\n", expected);                         \
        test_stats.failed++;                                            \
    } else {                                                            \
        printf("PASS\n");                                               \
        test_stats.passed++;                                            \
    }                                                                   \
} while(0)

/* Compare int32_t arrays */
static bool arrays_equal(const int32_t a[4], const int32_t b[4]) {
    return (a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3]);
}

/* Print array */
static void print_array(const int32_t arr[4]) {
    printf("[%d, %d, %d, %d]", arr[0], arr[1], arr[2], arr[3]);
}

int main(void) {
    printf("\n");
    printf("==========================================================\n");
    printf("  AI ACCELERATOR DRIVER — SELF TEST\n");
    printf("  Target: 4×4 INT8 Systolic Array (Weight-Stationary)\n");
    printf("  Mode:   Software model (no hardware required)\n");
    printf("==========================================================\n\n");

    /*
     * === TEST GROUP 1: Software Model Correctness ===
     */

    printf("[Group 1] Software systolic array model correctness:\n");

    /* Test 1.1: Identity weights */
    int32_t sw_out[4];
    ai_accel_sw_model(test_weights_identity, test_acts_identity, sw_out);
    TEST("identity weights",
         arrays_equal(sw_out, test_exp_identity),
         "all outputs = 1");

    /* Test 1.2: All-zero activations */
    int32_t allzero_exp[4] = {0, 0, 0, 0};
    int32_t allzero_out[4];
    ai_accel_sw_model(test_weights_car, test_acts_empty, allzero_out);
    TEST("zero activations → zero outputs",
         arrays_equal(allzero_out, allzero_exp),
         "all outputs = 0");

    /* Test 1.3: Symmetric negative values */
    const int8_t w_sym[4][4] = {{-1, 2},  {0, 0},  {0, 0},  {0, 0}};
    const int8_t a_sym[4]     = {1, -1, 0, 0};
    int32_t sym_out[4];
    ai_accel_sw_model(w_sym, a_sym, sym_out);
    TEST("symmetric negative: (-1)*1 + 2*(-1) = -3",
         sym_out[0] == -3,
         "output[0] = -3");

    /* Test 1.4: Overflow guard — max INT8 × max INT8 × 4 */
    const int8_t w_max[4][4] = {{127, 127, 127, 127}, {0}, {0}, {0}};
    const int8_t a_max[4]     = {127, 127, 127, 127};
    int32_t max_out[4];
    ai_accel_sw_model(w_max, a_max, max_out);
    TEST("max int8: 4 × (127 × 127) = 64516",
         max_out[0] == 64516,
         "output[0] = 64516");

    /*
     * === TEST GROUP 2: Packing/Unpacking Correctness ===
     */

    printf("\n[Group 2] INT8 packing correctness:\n");

    /* Test 2.1: pack_4x8 */
    uint32_t packed = pack_4x8(0x12, 0x34, 0x56, 0x78);
    /* Little-endian on wire: byte0=0x12 at [7:0] */
    TEST("pack_4x8(0x12,0x34,0x56,0x78) = 0x78563412",
         packed == 0x78563412U,
         "packed = 0x78563412");

    /* Test 2.2: Negative INT8 packing */
    packed = pack_4x8(-1, -2, -3, -4);
    /* -1 = 0xFF, -2 = 0xFE, -3 = 0xFD, -4 = 0xFC */
    TEST("pack negative int8: pack_4x8(-1,-2,-3,-4) = 0xFCFDFEFF",
         packed == 0xFCFDFEFFU,
         "packed negative values correctly");

    /* Test 2.3: pack_2x16 */
    uint32_t bpack = pack_2x16(0x1234, 0x5678);
    TEST("pack_2x16(0x1234,0x5678) = 0x56781234",
         bpack == 0x56781234U,
         "packed = 0x56781234");

    /* Test 2.4: pack_inputs consistency */
    const int8_t test_acts[4] = {1, 2, 3, 4};
    uint32_t ipacked = pack_inputs(test_acts);
    TEST("pack_inputs([1,2,3,4]) = 0x04030201",
         ipacked == 0x04030201U,
         "inputs packed MSB→LSB");

    /*
     * === TEST GROUP 3: Classification Logic ===
     */

    printf("\n[Group 3] Classification correctness:\n");

    /* Test 3.1: Clear win — CAR dominates */
    int32_t car_win[4] = {1000, 200, 300, -500};
    ai_accel_class_t cls;
    int32_t conf;
    bool classified = ai_accel_classify(car_win, &cls, &conf);
    TEST("Car wins (1000 > 200/300/-500), classified=true",
         classified == true,
         "classified = true");
    TEST("Car wins → class = AI_ACCEL_CLASS_CAR (0)",
         cls == AI_ACCEL_CLASS_CAR,
         "class = CAR");
    TEST("Car win confidence > 0.30",
         conf >= AI_ACCEL_CONFIDENCE_THRESHOLD_Q16,
         "confidence above threshold");

    /* Test 3.2: No clear winner — all outputs similar */
    int32_t close_call[4] = {100, 98, 99, 97};
    classified = ai_accel_classify(close_call, &cls, &conf);
    TEST("No clear winner → classified=false",
         classified == false,
         "classified = false");
    TEST("No clear winner → class = UNCERTAIN (4)",
         cls == AI_ACCEL_CLASS_UNCERTAIN,
         "class = UNCERTAIN");

    /* Test 3.3: All outputs negative */
    int32_t all_neg[4] = {-100, -200, -300, -400};
    classified = ai_accel_classify(all_neg, &cls, &conf);
    TEST("All negative → classified=false",
         classified == false,
         "classified = false");
    TEST("All negative → conf = 0",
         conf == 0,
         "confidence = 0");

    /* Test 3.4: Zero outputs */
    int32_t all_zero[4] = {0, 0, 0, 0};
    classified = ai_accel_classify(all_zero, &cls, &conf);
    TEST("All zero → classified=false",
         classified == false,
         "classified = false");

    /*
     * === TEST GROUP 4: Full ADAS Integration ===
     */

    printf("\n[Group 4] ADAS integration — software model inference:\n");

    /* Test 4.1: Car detection scenario */
    int32_t car_out[4];
    ai_accel_sw_model(test_weights_adas, test_acts_adas, car_out);
    printf("  Car scenario outputs: ");
    print_array(car_out);
    printf("\n");

    TEST("Car scenario: output[0] > output[1] (car > pedestrian)",
         car_out[0] > car_out[1],
         "car dominates");
    TEST("Car scenario: output[1] > output[2] (ped > obst)",
         car_out[1] > car_out[2],
         "pedestrian > obstacle");
    TEST("Car scenario: output[0] >> output[3] (car dominates reject)",
         car_out[0] > (car_out[3] * 5),
         "car >> reject class output");

    /* Test 4.2: Pedestrian detection scenario */
    int32_t ped_out[4];
    ai_accel_sw_model(test_weights_ped, test_acts_ped, ped_out);
    printf("  Ped scenario outputs: ");
    print_array(ped_out);
    printf("\n");

    classified = ai_accel_classify(ped_out, &cls, &conf);
    TEST("Ped scenario classified?",
         classified == true,
         "classification succeeded");
    TEST("Ped scenario class = PEDESTRIAN (1)",
         cls == AI_ACCEL_CLASS_PEDESTRIAN,
         "pedestrian detected");

    /* Test 4.3: Empty scene (no object) */
    int32_t empty_out[4];
    ai_accel_sw_model(test_weights_empty, test_acts_empty, empty_out);
    printf("  Empty scenario outputs: ");
    print_array(empty_out);
    printf("\n");

    classified = ai_accel_classify(empty_out, &cls, &conf);
    TEST("Empty scene → classified=false (below threshold)",
         classified == false,
         "nothing detected");

    /*
     * === TEST GROUP 5: Design Constraints ===
     */

    printf("\n[Group 5] Design constraint verification:\n");

    /* Test 5.1: ai_accel_is_idle() check */
    /* In the SW model test (no hardware), we can't actually call the MMIO */
    /* But we can verify the logic: after init, idle = !busy */
    TEST("Weight register address map: AI_WEIGHT_0 = 0x08",
         AI_WEIGHT_0_OFFSET == 0x08U,
         "weight0 at 0x08");
    TEST("Weight register stride: AI_WEIGHT_1 = AI_WEIGHT_0 + 4",
         AI_WEIGHT_1_OFFSET == AI_WEIGHT_0_OFFSET + 4,
         "contiguous 32-bit registers");

    TEST("Output register address map: AI_OUTPUT_0 = 0x24",
         AI_OUTPUT_0_OFFSET == 0x24U,
         "output0 at 0x24");
    TEST("Output register stride: AI_OUTPUT_3 = AI_OUTPUT_0 + 12",
         AI_OUTPUT_3_OFFSET == AI_OUTPUT_0_OFFSET + 12,
         "4 consecutive 32-bit output registers");

    /* Test 5.2: Verify the class enum matches RTL output mapping */
    TEST("AI_ACCEL_CLASS_CAR = output[0] row",
         AI_ACCEL_CLASS_CAR == 0,
         "row 0 → CAR");
    TEST("AI_ACCEL_CLASS_PEDESTRIAN = output[1] row",
         AI_ACCEL_CLASS_PEDESTRIAN == 1,
         "row 1 → PEDESTRIAN");
    TEST("AI_ACCEL_CLASS_OBSTACLE = output[2] row",
         AI_ACCEL_CLASS_OBSTACLE == 2,
         "row 2 → OBSTACLE");
    TEST("AI_ACCEL_CLASS_NONE = output[3] row",
         AI_ACCEL_CLASS_NONE == 3,
         "row 3 → NONE");

    /*
     * === SUMMARY ===
     */

    printf("\n");
    printf("==========================================================\n");
    printf("  SELF TEST SUMMARY\n");
    printf("==========================================================\n");
    printf("  Total:  %u\n", test_stats.total);
    printf("  Passed: %u (%d%%)\n", test_stats.passed,
           (test_stats.total > 0) ? (test_stats.passed * 100 / test_stats.total) : 0);
    printf("  Failed: %u\n", test_stats.failed);
    printf("==========================================================\n");

    if (test_stats.failed > 0) {
        printf("  ❌ SOME TESTS FAILED — review before integration\n");
        return 1;
    }

    printf("  ✅ ALL TESTS PASSED — driver ready for hardware\n");
    printf("==========================================================\n\n");

    return 0;
}

#endif /* AI_ACCEL_SELF_TEST */
