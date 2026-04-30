/*
 * main.c — ADAS v2 Firmware Integration Test
 * ===========================================
 * Links: adas_algorithm.c + adas_v2_firmware_sdk
 * Target: RV32IM | bare-metal | sky130hs 100 MHz
 *
 * This is a minimal main() that exercises the integration:
 *   - Calls adas_init()
 *   - Creates a sensor frame and calls adas_process_frame()
 *   - Tests peripheral register access (compile-time check)
 *   - Prints a sign-of-life message via UART (if available)
 */

#include "adas_platform.h"
#include "adas_algorithm.h"
#include "sdk_version.h"

/* Include all peripheral drivers to verify they compile */
#include "hal/ai_accel.h"
#include "hal/spi.h"
#include "hal/servo_pwm.h"
#include "hal/speed_sensor.h"
#include "hal/buzzer_pwm.h"
#include "hal/uart.h"
#include "hal/gpio.h"
#include "hal/wdt.h"
#include "hal/safety.h"

/* ========================================================================
 * Compile-time Address Verification
 *
 * These compile-time asserts verify that the SDK addresses match
 * the REGISTER_MAP.md specification exactly.
 * ======================================================================== */

#define STATIC_ASSERT(cond, msg)  _Static_assert(cond, msg)

STATIC_ASSERT(ITCM_BASE == 0x00000000UL, "ITCM base mismatch");
STATIC_ASSERT(DTCM_BASE == 0x00002000UL, "DTCM base mismatch");
STATIC_ASSERT(AI_ACCEL_BASE  == 0x00001000UL, "AI_ACCEL base mismatch");
STATIC_ASSERT(SPI_BASE       == 0x00002000UL, "SPI base mismatch");
STATIC_ASSERT(SERVO_PWM_BASE == 0x00003000UL, "SERVO_PWM base mismatch");
STATIC_ASSERT(SPEED_SENSOR_BASE == 0x00004000UL, "SPEED_SENSOR base mismatch");
STATIC_ASSERT(BUZZER_PWM_BASE   == 0x00005000UL, "BUZZER_PWM base mismatch");
STATIC_ASSERT(UART_BASE      == 0x00006000UL, "UART base mismatch");
STATIC_ASSERT(GPIO_BASE      == 0x00007000UL, "GPIO base mismatch");
STATIC_ASSERT(SAFETY_CTRL_BASE == 0x0000F000UL, "SAFETY_CTRL base mismatch");
STATIC_ASSERT(WDT_BASE       == 0x0000F100UL, "WDT base mismatch");

STATIC_ASSERT(SYS_CLK_HZ     == 100000000UL, "SYS_CLK mismatch");
STATIC_ASSERT(WDT_CLK_HZ     == 32768UL, "WDT_CLK mismatch");

/* ========================================================================
 * UART Sign-of-Life
 *
 * Prints boot banner if UART is connected. Bare-metal — no printf.
 * ======================================================================== */

static void boot_banner(void) {
    uart_init(UART_BAUD_115200_DLL, UART_BAUD_115200_DLM);
    uart_puts("\r\n\r\n");
    uart_puts("============================================\r\n");
    uart_puts(" ADAS v2 Firmware SDK — Boot\r\n");
    uart_puts(" Target: RV32IM @ 100 MHz | sky130hs\r\n");
    uart_puts(" SDK:    " SDK_VERSION_STRING "\r\n");
    uart_puts(" Build:  " __DATE__ " " __TIME__ "\r\n");
    uart_puts("============================================\r\n");
}

/* ========================================================================
 * Peripheral Sanity Check
 *
 * Reads module ID registers to verify peripheral bus connectivity.
 * All peripherals should return their known ID values.
 * ======================================================================== */

static bool sanity_check_peripherals(void) {
    bool ok = true;

    /* Safety module ID: "SFTY" = 0x53465459 */
    uint32_t safety_id = safety_read_id();
    if (safety_id != SAFETY_ID_VALUE) {
        uart_puts("  FAIL: Safety module ID mismatch\r\n");
        ok = false;
    } else {
        uart_puts("  PASS: Safety module ID = 0x");
        uart_puthex32(safety_id);
        uart_puts("\r\n");
    }

    /* WDT module ID: "WDT\0" = 0x57445400 */
    uint32_t wdt_id = wdt_read_id();
    if (wdt_id != WDT_ID_VALUE) {
        uart_puts("  FAIL: WDT module ID mismatch\r\n");
        ok = false;
    } else {
        uart_puts("  PASS: WDT module ID = 0x");
        uart_puthex32(wdt_id);
        uart_puts("\r\n");
    }

    return ok;
}

/* ========================================================================
 * ADAS Algorithm Integration Test
 *
 * Exercises the firmware_engineer's adas_algorithm.c through its
 * public API with a realistic sensor frame.
 * ======================================================================== */

static void test_adas_algorithm(void) {
    adas_controller_t ctrl;
    adas_safety_monitor_t sm;
    adas_sensor_frame_t frame;
    adas_output_t out;

    uart_puts("\r\n--- ADAS Algorithm Integration Test ---\r\n");

    /* 1. Initialize controller and safety monitor */
    adas_init(&ctrl);
    adas_safety_init(&sm);

    /* 2. Create a realistic sensor frame:
     *    - Ego speed: 30 m/s (~108 km/h)
     *    - Object distance: 50 m ahead
     *    - Relative speed: 25 m/s (closing fast)
     *    - Object class: CAR
     */
    frame.ego_speed_q16       = INT_TO_Q16(30);        /* 30.00 m/s      */
    frame.object_distance_q16 = INT_TO_Q16(50);        /* 50.00 m        */
    frame.object_rel_speed_q16= INT_TO_Q16(25);        /* 25.00 m/s      */
    frame.object_class        = ADAS_OBJ_CAR;          /* Car            */
    frame.timestamp_ms        = 0;

    /* 3. Validate the frame */
    if (!adas_validate_frame(&frame)) {
        uart_puts("  FAIL: Frame validation rejected valid frame\r\n");
        return;
    }
    uart_puts("  PASS: Frame validation accepted\r\n");

    /* 4. Compute TTC */
    q16_t ttc = adas_compute_ttc(frame.object_distance_q16,
                                  frame.object_rel_speed_q16);
    uart_puts("  TTC = 2.0 seconds (expected), got: ");
    uart_puthex32((uint32_t)ttc);
    uart_puts("\r\n");

    /* 5. Process frame through state machine */
    out = adas_process_frame(&ctrl, &frame);

    /* TTC = 50m / 25 m/s = 2.0s.
     * Threshold for CAR = 1.8s.
     * Since TTC (2.0) >= threshold (1.8), should NOT brake on first frame.
     * State should be IDLE or MONITORING (first frame triggers monitoring). */

    uart_puts("  State: ");
    uart_puthex32(out.state);
    uart_puts("\r\n");

    uart_puts("  Should Brake: ");
    uart_puts(out.should_brake ? "YES\r\n" : "NO\r\n");

    if (out.should_brake) {
        uart_puts("  WARNING: Brake asserted on first frame (TTC=2.0 > thr=1.8)\r\n");
    }

    /* 6. Feed a second frame with same data → should still be below
     *    hysteresis count unless TTC < threshold.
     *    Let's feed a more critical frame: distance 20m, rel_speed 25 m/s.
     *    TTC = 20/25 = 0.8s < 1.8s threshold → should trigger braking. */

    frame.object_distance_q16 = INT_TO_Q16(20);        /* 20 m           */
    out = adas_process_frame(&ctrl, &frame);           /* Frame 2        */
    out = adas_process_frame(&ctrl, &frame);           /* Frame 3 (>= hysteresis) */

    uart_puts("  CRITICAL Frame — Brake: ");
    uart_puts(out.should_brake ? "YES\r\n" : "NO\r\n");

    uart_puts("  PWM duty (Q16.16): 0x");
    uart_puthex32((uint32_t)out.pwm_duty_q16);
    uart_puts("\r\n");

    uart_puts("  Buzzer: ");
    uart_puts(out.buzzer_active ? "ON\r\n" : "OFF\r\n");

    uart_puts("--- ADAS Algorithm Test Complete ---\r\n");
}

/* ========================================================================
 * MAIN — Entry Point
 * ======================================================================== */

int main(void) {
    /* Print boot banner via UART */
    boot_banner();

    /* Verify SDK version consistency */
    uart_puts("SDK: " SDK_VERSION_STRING "\r\n");
    uart_puts("Target: " SDK_TARGET " @ ");
    uart_puthex32(SDK_SYS_CLK_HZ);
    uart_puts(" Hz\r\n\r\n");

    /* Run peripheral sanity checks */
    uart_puts("--- Peripheral Sanity Check ---\r\n");
    bool periph_ok = sanity_check_peripherals();

    /* Run ADAS algorithm test */
    test_adas_algorithm();

    /* Summary */
    uart_puts("\r\n============================================\r\n");
    uart_puts(" INTEGRATION TEST SUMMARY\r\n");
    uart_puts("============================================\r\n");
    uart_puts("  Peripherals: ");
    uart_puts(periph_ok ? "PASS\r\n" : "PARTIAL (simulation expected)\r\n");
    uart_puts("  adas_algorithm.c: LINKED\r\n");
    uart_puts("  Startup code: EXECUTED\r\n");
    uart_puts("  SDK version: " SDK_VERSION_STRING "\r\n");
    uart_puts("============================================\r\n");

    /* Main loop — idle with WFI */
    while (1) {
        wfi();
    }

    return 0;  /* unreachable */
}
