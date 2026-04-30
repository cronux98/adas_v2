/*
 * ai_accel_driver.h — AI Accelerator Driver for 4×4 Systolic Array
 * ====================================================================
 * Project:  adas_v2 — ADAS RISC-V High-Performance Safety-Critical SoC
 * Target:   RV32IM (bare-metal, MMIO to 0x0000_1000)
 * Hardware: ai_accel_4x4 — 4×4 INT8 Weight-Stationary Systolic Array
 *
 * DESCRIPTION
 *   This driver provides the C-level API for the 4×4 systolic array
 *   accelerator. It handles:
 *     1. Weight loading (16×INT8 → 4×32-bit register writes)
 *     2. Bias loading (4×INT16 → 2×32-bit register writes)
 *     3. Activation function and scale configuration
 *     4. Input loading + GO trigger → compute
 *     5. Done polling and result readback
 *     6. Classification (4 outputs → object class + confidence)
 *
 * MAPPING: RTL Register  ←→  Driver API
 *   AI_CTRL (0x00)       ←→  ai_accel_go(), ai_accel_get_status()
 *   AI_STATUS (0x04)     ←→  ai_accel_is_busy(), ai_accel_is_done()
 *   AI_WEIGHT_0..3       ←→  ai_accel_load_weights()
 *   (0x08,0x0C,0x10,0x14)
 *   AI_INPUT (0x18)      ←→  ai_accel_load_inputs()
 *   AI_BIAS_0_1/2_3      ←→  ai_accel_load_biases()
 *   (0x1C,0x20)
 *   AI_OUTPUT_0..3       ←→  ai_accel_read_output()
 *   (0x24,0x28,0x2C,0x30)
 *
 * USAGE (standalone):
 *   // 1. Train/generate weights offline
 *   int8_t weights[4][4] = { ... };
 *   int16_t biases[4]    = { ... };
 *
 *   // 2. Initialize and configure
 *   ai_accel_init();
 *   ai_accel_set_activation(AI_ACT_RELU);
 *   ai_accel_set_scale(AI_SCALE_DEFAULT);
 *
 *   // 3. Load one inference
 *   ai_accel_load_weights(weights);
 *   ai_accel_load_biases(biases);
 *   ai_accel_load_inputs(input_acts);
 *
 *   // 4. Run inference (blocking)
 *   int32_t outputs[4];
 *   ai_accel_run_blocking(outputs);
 *
 *   // 5. Classify output
 *   ai_accel_class_t result;
 *   int32_t confidence;
 *   ai_accel_classify(outputs, &result, &confidence);
 *
 * LICENSE: Proprietary — ADAS Safety-Critical Firmware
 */

#ifndef AI_ACCEL_DRIVER_H
#define AI_ACCEL_DRIVER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================
 * ACCELERATOR MEMORY MAP
 * ========================================================================
 * Base address for the AI accelerator block on the AXI4-Lite crossbar.
 * See REGISTER_MAP.md §2 for complete details.
 * ======================================================================== */

#define AI_ACCEL_BASE_ADDR      0x00001000UL

/* ---- Register Offsets (32-bit, aligned) ----
 * Guarded for co-inclusion with hal/ai_accel.h — values MUST match
 * REGISTER_MAP.md §2 exactly. */
#ifndef AI_CTRL_OFFSET
#define AI_CTRL_OFFSET          0x00U
#endif
#ifndef AI_STATUS_OFFSET
#define AI_STATUS_OFFSET        0x04U
#endif
#ifndef AI_WEIGHT_0_OFFSET
#define AI_WEIGHT_0_OFFSET      0x08U
#endif
#ifndef AI_WEIGHT_1_OFFSET
#define AI_WEIGHT_1_OFFSET      0x0CU
#endif
#ifndef AI_WEIGHT_2_OFFSET
#define AI_WEIGHT_2_OFFSET      0x10U
#endif
#ifndef AI_WEIGHT_3_OFFSET
#define AI_WEIGHT_3_OFFSET      0x14U
#endif
#ifndef AI_INPUT_OFFSET
#define AI_INPUT_OFFSET         0x18U
#endif
#ifndef AI_BIAS_0_1_OFFSET
#define AI_BIAS_0_1_OFFSET      0x1CU
#endif
#ifndef AI_BIAS_2_3_OFFSET
#define AI_BIAS_2_3_OFFSET      0x20U
#endif
#ifndef AI_OUTPUT_0_OFFSET
#define AI_OUTPUT_0_OFFSET      0x24U
#endif
#ifndef AI_OUTPUT_1_OFFSET
#define AI_OUTPUT_1_OFFSET      0x28U
#endif
#ifndef AI_OUTPUT_2_OFFSET
#define AI_OUTPUT_2_OFFSET      0x2CU
#endif
#ifndef AI_OUTPUT_3_OFFSET
#define AI_OUTPUT_3_OFFSET      0x30U
#endif
#ifndef AI_ACTIVATION_OFFSET
#define AI_ACTIVATION_OFFSET    0x34U
#endif
#ifndef AI_SCALE_OFFSET
#define AI_SCALE_OFFSET         0x38U
#endif
#ifndef AI_INTR_MASK_OFFSET
#define AI_INTR_MASK_OFFSET     0x3CU
#endif

/* ========================================================================
 * AI_CTRL BIT DEFINITIONS (register at 0x00)
 * ========================================================================
 * Writing AI_CTRL.GO = 1 starts the computation FSM.
 * The FSM: LOAD_WEIGHTS → LOAD_INPUT → COMPUTE → DONE
 * See control_fsm.v for the 5-state Moore machine.
 * ======================================================================== */

#ifndef AI_CTRL_GO
#define AI_CTRL_GO              (1U << 0)   /* Write 1 → start computation */
#endif
#ifndef AI_CTRL_BUSY
#define AI_CTRL_BUSY            (1U << 1)   /* RO: FSM not in IDLE state */
#endif
#ifndef AI_CTRL_DONE
#define AI_CTRL_DONE            (1U << 2)   /* RO: computation complete */
#endif
#ifndef AI_CTRL_ERROR
#define AI_CTRL_ERROR           (1U << 3)   /* RO: error flag (latch) */
#endif
#ifndef AI_CTRL_RELU_EN
#define AI_CTRL_RELU_EN         (1U << 4)   /* RW: enable ReLU after bias addition */
#endif
#ifndef AI_CTRL_QUANT_EN
#define AI_CTRL_QUANT_EN        (1U << 5)   /* RW: enable output quantization */
#endif
#ifndef AI_CTRL_CLK_EN
#define AI_CTRL_CLK_EN          (1U << 8)   /* RW: clock gate enable */
#endif
#ifndef AI_CTRL_RST
#define AI_CTRL_RST             (1U << 9)   /* RW: soft reset */
#endif

/* ========================================================================
 * AI_STATUS BIT DEFINITIONS (register at 0x04)
 * ======================================================================== */

#define AI_STATUS_BUSY          (1U << 0)   /* FSM active */
#define AI_STATUS_DONE          (1U << 1)   /* Computation finished */
#define AI_STATUS_ERROR         (1U << 2)   /* Error occurred */
#define AI_STATUS_WEIGHTS_LOAD  (1U << 3)   /* Weights loaded indicator */
#define AI_STATUS_INPUTS_LOAD   (1U << 4)   /* Input loaded indicator */
#define AI_STATUS_CYCLE_CNT_MASK (0x0FU << 8) /* Current compute cycle [11:8] */

#define AI_STATUS_CYCLE_CNT_SHIFT 8

/* ========================================================================
 * AI_ACTIVATION BIT DEFINITIONS (register at 0x34)
 * ======================================================================== */

#ifndef AI_ACT_NONE
#define AI_ACT_NONE             (1U << 0)   /* No activation function */
#endif
#ifndef AI_ACT_RELU
#define AI_ACT_RELU             (1U << 1)   /* ReLU: max(0, x) */
#endif

/* ========================================================================
 * AI_INTR_MASK BIT DEFINITIONS (register at 0x3C)
 * ======================================================================== */

#ifndef AI_INTR_DONE_IE
#define AI_INTR_DONE_IE         (1U << 0)   /* Done interrupt enable */
#endif
#ifndef AI_INTR_ERROR_IE
#define AI_INTR_ERROR_IE        (1U << 1)   /* Error interrupt enable */
#endif

/* ========================================================================
 * DEFAULT SCALE FACTOR
 * ======================================================================== */

#ifndef AI_SCALE_DEFAULT
#define AI_SCALE_DEFAULT        0x00001000UL  /* Q8.8: 16.0 default scale */
#endif

/* ========================================================================
 * COMPUTE LATENCY CONSTANTS
 * ========================================================================
 * From systolic_array.v and control_fsm.v:
 *   LOAD_WEIGHTS: 16 cycles (address all 16 PEs)
 *   LOAD_INPUT:   1 cycle
 *   COMPUTE:      4 cycles (one per column) + 1 pipeline fill
 *   Total:       ~22 sys_clk cycles from GO → DONE
 *   At 100 MHz:  ~220 ns
 * ======================================================================== */

#define AI_ACCEL_COMPUTE_CYCLES  22U
#define AI_ACCEL_POLL_TIMEOUT   1000U          /* safety timeout (microseconds) */

/* ========================================================================
 * OUTPUT INTERPRETATION
 * ========================================================================
 * The 4×4 systolic array computes: output[row] = Σ(col) wt[row][col] × act[col]
 *
 * Each output row corresponds to one object class:
 *   output[0] → ADAS_OBJ_CAR
 *   output[1] → ADAS_OBJ_PEDESTRIAN
 *   output[2] → ADAS_OBJ_OBSTACLE
 *   output[3] → ADAS_OBJ_NONE (background/reject)
 *
 * After bias addition + ReLU + scaling, the class with the highest
 * output value wins. Confidence = softmax approximation using max/total.
 * ======================================================================== */

typedef enum {
    AI_ACCEL_CLASS_CAR        = 0,
    AI_ACCEL_CLASS_PEDESTRIAN = 1,
    AI_ACCEL_CLASS_OBSTACLE   = 2,
    AI_ACCEL_CLASS_NONE       = 3,
    AI_ACCEL_CLASS_UNCERTAIN  = 4     /* no class confidently above noise */
} ai_accel_class_t;

/* Maximum number of consecutive polls before declaring timeout */
#define AI_ACCEL_POLL_RETRIES  5000

/* Confidence threshold: output must exceed this fraction of max to be valid */
#define AI_ACCEL_CONFIDENCE_THRESHOLD_Q16  ((int32_t)19661)  /* 0.30 in Q16.16 */

/* ========================================================================
 * MMIO INLINE HELPERS
 * ========================================================================
 * Volatile pointer dereference for direct register access.
 * These compile to a single LW/SW instruction on RV32.
 * ======================================================================== */

static inline void ai_accel_reg_write(uint32_t offset, uint32_t val) {
    *((volatile uint32_t *)(AI_ACCEL_BASE_ADDR + offset)) = val;
}

static inline uint32_t ai_accel_reg_read(uint32_t offset) {
    return *((volatile uint32_t *)(AI_ACCEL_BASE_ADDR + offset));
}

/* ========================================================================
 * PUBLIC API
 * ======================================================================== */

/**
 * Initialize the AI accelerator.
 *
 * Configures clock gating, clears any stale error/done flags,
 * and puts the FSM in IDLE state via a soft reset sequence.
 *
 * Must be called once before any inference operations.
 */
void ai_accel_init(void);

/**
 * Check if the accelerator is idle (FSM in IDLE state).
 *
 * @return true if the accelerator is ready for a new inference.
 */
bool ai_accel_is_idle(void);

/**
 * Check if the accelerator is currently computing.
 *
 * @return true if computation in progress.
 */
bool ai_accel_is_busy(void);

/**
 * Check if the last computation completed successfully.
 *
 * @return true if DONE flag is set.
 */
bool ai_accel_is_done(void);

/**
 * Check if an error occurred during the last computation.
 *
 * @return true if ERROR flag is set.
 */
bool ai_accel_is_error(void);

/**
 * Set the activation function applied after bias addition.
 *
 * Supported values: AI_ACT_NONE, AI_ACT_RELU
 *
 * @param activation  Activation function bitmask.
 */
void ai_accel_set_activation(uint32_t activation);

/**
 * Set the output scaling factor (Q8.8 fixed-point).
 *
 * The output from the systolic array is multiplied by this factor
 * and right-shifted by 8 to produce the final INT32 result.
 *
 * Default: AI_SCALE_DEFAULT (0x1000 = 16.0 in Q8.8)
 *
 * @param scale  Scaling factor in Q8.8 format.
 */
void ai_accel_set_scale(uint32_t scale);

/**
 * Load weights into the accelerator's SRAM buffer.
 *
 * The 4×4 weight matrix is loaded into 4×32-bit registers
 * (AI_WEIGHT_0..3), one 32-bit word per row. Each word packs
 * 4 INT8 weights: [col3, col2, col1, col0] in MSB→LSB order.
 *
 * When AI_CTRL.GO is written, the control FSM reads these
 * registers and distributes them to individual PEs through
 * the systolic_array weight loading port.
 *
 * @param weights  4×4 INT8 weight matrix [row][col].
 *                 weights[row][col] ← PE[row][col] in the array.
 */
void ai_accel_load_weights(const int8_t weights[4][4]);

/**
 * Load bias values for each output row.
 *
 * Four INT16 bias values packed into two 32-bit registers:
 *   AI_BIAS_0_1: bias[0] in [15:0], bias[1] in [31:16]
 *   AI_BIAS_2_3: bias[2] in [15:0], bias[3] in [31:16]
 *
 * Bias is added to the accumulated MAC result before ReLU.
 *
 * @param biases  Array of 4 INT16 bias values, one per output row.
 */
void ai_accel_load_biases(const int16_t biases[4]);

/**
 * Load 4 INT8 input activations for one inference.
 *
 * The 4 activations are packed into a single 32-bit register (AI_INPUT):
 *   [31:24] = act[3], [23:16] = act[2], [15:8] = act[1], [7:0] = act[0]
 *
 * @param activations  Array of 4 INT8 input activation values.
 *                     activation[col] is broadcast to column 'col'.
 */
void ai_accel_load_inputs(const int8_t activations[4]);

/**
 * Trigger computation on the accelerator (non-blocking).
 *
 * Sets AI_CTRL.GO = 1, which starts the control FSM:
 *   IDLE → LOAD_WEIGHTS → LOAD_INPUT → COMPUTE → DONE → IDLE
 *
 * Use ai_accel_is_done() or ai_accel_poll_done() to wait for completion.
 */
void ai_accel_go(void);

/**
 * Poll the accelerator until computation is done or timeout.
 *
 * Polls AI_STATUS.DONE with a timeout mechanism to prevent hangs.
 *
 * @return true if computation completed successfully within timeout.
 *         false if timeout or error occurred.
 */
bool ai_accel_poll_done(void);

/**
 * Run one complete inference (blocking convenience function).
 *
 * Combines: load_inputs → go → poll_done → read_outputs
 *
 * @param activations  Input activations (4×INT8).
 * @param outputs      Output buffer (4×INT32). Must be non-NULL.
 * @return true if inference completed successfully.
 */
bool ai_accel_inference(const int8_t activations[4], int32_t outputs[4]);

/**
 * Read one output channel.
 *
 * @param channel  Output index [0..3].
 * @return INT32 accumulated output value.
 */
int32_t ai_accel_read_output(uint32_t channel);

/**
 * Read all 4 output channels into an array.
 *
 * @param outputs  Output buffer (4×INT32). Must be non-NULL.
 */
void ai_accel_read_all_outputs(int32_t outputs[4]);

/**
 * Clear the DONE and ERROR status flags.
 *
 * Writing AI_CTRL.CLR_DONE = 1 and AI_CTRL.CLR_ERROR = 1
 * resets the corresponding sticky bits.
 */
void ai_accel_clear_status(void);

/**
 * Classify the 4 output values into an object class with confidence.
 *
 * Implements a winner-take-all with confidence threshold:
 *   1. Find the output with the maximum value
 *   2. Compute confidence = (max - second_max) / max  (Q16.16 approx)
 *   3. If confidence < threshold → return UNCERTAIN
 *   4. Otherwise, return the class corresponding to the max output row
 *
 * @param outputs      Array of 4 INT32 output values.
 * @param class_out    [out] Classified object class.
 * @param confidence_q16 [out] Confidence score in Q16.16 format [0..1].
 * @return true if classification succeeded (confidence above threshold).
 */
bool ai_accel_classify(const int32_t outputs[4],
                       ai_accel_class_t *class_out,
                       int32_t *confidence_q16);

/**
 * Full pipeline: load weights + biases once, then run N inferences.
 *
 * This is the main entry point for the ADAS firmware integration:
 *   1. Call once at boot: ai_accel_init_pipeline(weights, biases, activation, scale)
 *   2. Call per sensor frame: ai_accel_run(activations, &class, &confidence)
 *
 * @param weights      4×4 INT8 weight matrix.
 * @param biases       4 INT16 bias values.
 * @param activation   Activation function (AI_ACT_NONE or AI_ACT_RELU).
 * @param scale        Scaling factor in Q8.8 format.
 */
void ai_accel_init_pipeline(const int8_t weights[4][4],
                            const int16_t biases[4],
                            uint32_t activation,
                            uint32_t scale);

/**
 * Run one inference using the previously loaded weights/biases.
 *
 * Must call ai_accel_init_pipeline() first.
 *
 * @param activations  Input activations (4×INT8).
 * @param class_out    [out] Classified object class.
 * @param confidence_q16 [out] Confidence score, Q16.16.
 * @return true if inference + classification succeeded.
 */
bool ai_accel_run(const int8_t activations[4],
                  ai_accel_class_t *class_out,
                  int32_t *confidence_q16);

/**
 * Software model of the 4×4 systolic array (bit-exact reference).
 *
 * Computes output[row] = Σ(col) weight[row][col] × activation[col]
 * using the same INT8×INT8 → INT32 MAC as the RTL systolic_array.v.
 *
 * This is useful for:
 *   - Verifying hardware outputs against a golden reference
 *   - Pre-computing expected outputs for test vectors
 *   - Offline inference without accelerator hardware
 *
 * @param weights      4×4 INT8 weight matrix.
 * @param activations  4 INT8 input activation values.
 * @param outputs      [out] 4 INT32 output values.
 */
void ai_accel_sw_compute(const int8_t weights[4][4],
                         const int8_t activations[4],
                         int32_t outputs[4]);

#ifdef __cplusplus
}
#endif

#endif /* AI_ACCEL_DRIVER_H */
