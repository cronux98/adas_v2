#!/usr/bin/env python3
"""
dut_wrapper.py — cocotb DUT Interface for ADAS v2 SoC
========================================================
Provides a clean Python interface to the adas_soc_tb_wrapper Verilog module.

Usage:
    from dut_wrapper import ADASSoC
    dut = ADASSoC(cocotb_dut_handle)
    await dut.reset()
    await dut.write_register(0x1000, 0x00000001)
    val = await dut.read_register(0x1000)

Architecture:
    - ClockGen: 100 MHz system clock + 32.768 kHz WDT clock
    - Reset sequencer: assert reset_n low for 5+ cycles, then release
    - AXI4-Lite BFM: write/read register transactions with handshake
    - Convenience helpers: wait_cycles, pulse_speed, inject_lockstep_mismatch
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles
# BinaryValue not available in cocotb 2.0; use .value.integer directly
from typing import Optional


class ADASSoC:
    """cocotb interface to the ADAS v2 SoC test wrapper."""

    # Register map base addresses
    AI_ACCEL_BASE   = 0x00001000
    SPI_BASE        = 0x00002000
    SERVO_BASE      = 0x00003000
    SPEED_BASE      = 0x00004000
    BUZZER_BASE     = 0x00005000
    UART_BASE       = 0x00006000
    GPIO_BASE       = 0x00007000
    SAFETY_BASE     = 0x0000F000
    WDT_BASE        = 0x0000F100

    # AI register offsets
    AI_CTRL         = 0x00
    AI_STATUS       = 0x04
    AI_WEIGHT_0     = 0x08
    AI_WEIGHT_1     = 0x0C
    AI_WEIGHT_2     = 0x10
    AI_WEIGHT_3     = 0x14
    AI_INPUT        = 0x18
    AI_BIAS_0_1     = 0x1C
    AI_BIAS_2_3     = 0x20
    AI_OUTPUT_0     = 0x24
    AI_OUTPUT_1     = 0x28
    AI_OUTPUT_2     = 0x2C
    AI_OUTPUT_3     = 0x30
    AI_ACTIVATION   = 0x34
    AI_SCALE        = 0x38
    AI_INTR_MASK    = 0x3C

    # Speed sensor reg
    SPEED_REG       = 0x10

    # Safety regs
    SAFETY_CTRL             = 0x00
    SAFETY_STATUS           = 0x04
    SAFETY_FAULT_MASK       = 0x08
    SAFETY_FAULT_STATUS     = 0x0C
    SAFETY_FAULT_COUNT      = 0x10
    SAFETY_LOCKSTEP_CTRL    = 0x14
    SAFETY_LOCKSTEP_MASK    = 0x18
    SAFETY_LOCKSTEP_MISMATCH= 0x1C
    SAFETY_LOCKSTEP_LAST_PC = 0x20
    SAFETY_LOCKSTEP_LAST_OUT= 0x24
    SAFETY_LOCKSTEP_LAST_EXP= 0x28
    SAFETY_SCRATCH          = 0x2C
    SAFETY_INTR_MASK        = 0x30
    SAFETY_INTR_STATUS      = 0x34
    SAFETY_RESET_CTRL       = 0x38
    SAFETY_ID               = 0x3C

    def __init__(self, dut):
        self.dut = dut
        self._clock_started = False
        self._reset_done = False

    # =========================================================================
    # Clock & Reset
    # =========================================================================

    async def start_clocks(self):
        """Start system clock (100 MHz) and WDT clock (32.768 kHz)."""
        if self._clock_started:
            return
        # 100 MHz system clock: 10 ns period = 5 ns half-period
        cocotb.start_soon(Clock(self.dut.sys_clk_i, 10, units='ns').start())
        # 32.768 kHz WDT clock: ~30.52 us period
        cocotb.start_soon(Clock(self.dut.wdt_clk_i, 30520, units='ns').start())
        self._clock_started = True
        # Wait for clocks to stabilize
        await Timer(50, units='ns')

    async def reset(self):
        """Assert reset, hold for 5+ sys_clk cycles, then release."""
        await self.start_clocks()

        self.dut.sys_rst_n_i.value = 0
        self.dut.wdt_rst_n_i.value = 0

        # Hold reset low for 5 cycles = 50 ns
        await ClockCycles(self.dut.sys_clk_i, 5)

        self.dut.sys_rst_n_i.value = 1
        self.dut.wdt_rst_n_i.value = 1

        # Wait for reset de-assertion to propagate
        await ClockCycles(self.dut.sys_clk_i, 5)

        # Initialize AXI master signals to idle
        await self._axi_idle()

        # Initialize lockstep checker inputs to match master
        self.dut.ls_test_checker_outputs.value = 0
        self.dut.ls_test_checker_pc.value = 0
        self.dut.ls_test_checker_valid.value = 0

        self._reset_done = True

    # =========================================================================
    # AXI4-Lite Bus Functional Model
    # =========================================================================

    async def _axi_idle(self):
        """Set all AXI master signals to idle state."""
        self.dut.tb_axi_awaddr.value  = 0
        self.dut.tb_axi_awprot.value  = 0
        self.dut.tb_axi_awvalid.value = 0
        self.dut.tb_axi_wdata.value   = 0
        self.dut.tb_axi_wstrb.value   = 0
        self.dut.tb_axi_wvalid.value  = 0
        self.dut.tb_axi_bready.value  = 1
        self.dut.tb_axi_araddr.value  = 0
        self.dut.tb_axi_arprot.value  = 0
        self.dut.tb_axi_arvalid.value = 0
        self.dut.tb_axi_rready.value  = 1

    async def write_register(self, addr: int, data: int, timeout_cycles: int = 100):
        """
        AXI4-Lite write transaction.
        
        Steps:
        1. Assert AWVALID + AWADDR
        2. Wait for AWREADY
        3. Assert WVALID + WDATA + WSTRB
        4. Wait for WREADY
        5. Wait for BVALID (write response)
        6. Assert BREADY and capture BRESP
        """
        addr = addr & 0xFFFFFFFF
        data = data & 0xFFFFFFFF

        # Write address phase
        self.dut.tb_axi_awaddr.value = addr
        self.dut.tb_axi_awvalid.value = 1

        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.sys_clk_i)
            if self.dut.tb_axi_awready.value == 1:
                break
        else:
            self.dut.tb_axi_awvalid.value = 0
            raise TimeoutError(f"AXI write addr handshake timeout at addr=0x{addr:08X}")

        self.dut.tb_axi_awvalid.value = 0

        # Write data phase
        self.dut.tb_axi_wdata.value = data
        self.dut.tb_axi_wstrb.value = 0xF  # all byte lanes
        self.dut.tb_axi_wvalid.value = 1

        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.sys_clk_i)
            if self.dut.tb_axi_wready.value == 1:
                break
        else:
            self.dut.tb_axi_wvalid.value = 0
            raise TimeoutError(f"AXI write data handshake timeout at addr=0x{addr:08X}")

        self.dut.tb_axi_wvalid.value = 0

        # Write response phase
        self.dut.tb_axi_bready.value = 1
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.sys_clk_i)
            if self.dut.tb_axi_bvalid.value == 1:
                break
        else:
            raise TimeoutError(f"AXI write response timeout at addr=0x{addr:08X}")

        bresp = self.dut.tb_axi_bresp.value.integer
        self.dut.tb_axi_bready.value = 0

        if bresp != 0:
            raise RuntimeError(f"AXI write error: BRESP=0b{bresp:02b} at addr=0x{addr:08X}")

        # Extra cycle for safety
        await RisingEdge(self.dut.sys_clk_i)

    async def read_register(self, addr: int, timeout_cycles: int = 100) -> int:
        """
        AXI4-Lite read transaction.
        
        Steps:
        1. Assert ARVALID + ARADDR
        2. Wait for ARREADY
        3. Wait for RVALID
        4. Capture RDATA, assert RREADY
        """
        addr = addr & 0xFFFFFFFF

        # Read address phase
        self.dut.tb_axi_araddr.value = addr
        self.dut.tb_axi_arvalid.value = 1

        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.sys_clk_i)
            if self.dut.tb_axi_arready.value == 1:
                break
        else:
            self.dut.tb_axi_arvalid.value = 0
            raise TimeoutError(f"AXI read addr handshake timeout at addr=0x{addr:08X}")

        self.dut.tb_axi_arvalid.value = 0

        # Read data phase
        self.dut.tb_axi_rready.value = 1
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.sys_clk_i)
            if self.dut.tb_axi_rvalid.value == 1:
                break
        else:
            raise TimeoutError(f"AXI read data timeout at addr=0x{addr:08X}")

        rdata = self.dut.tb_axi_rdata.value.integer
        rresp = self.dut.tb_axi_rresp.value.integer
        self.dut.tb_axi_rready.value = 0

        if rresp != 0:
            raise RuntimeError(f"AXI read error: RRESP=0b{rresp:02b} at addr=0x{addr:08X}")

        await RisingEdge(self.dut.sys_clk_i)
        return rdata

    # =========================================================================
    # Convenience Helpers
    # =========================================================================

    async def wait_cycles(self, n: int):
        """Wait n system clock cycles."""
        await ClockCycles(self.dut.sys_clk_i, n)

    async def pulse_speed(self, num_pulses: int = 1):
        """Generate speed sensor pulses."""
        for _ in range(num_pulses):
            self.dut.speed_pulse_i.value = 1
            await RisingEdge(self.dut.sys_clk_i)
            self.dut.speed_pulse_i.value = 0
            await ClockCycles(self.dut.sys_clk_i, 10)  # realistic pulse spacing

    async def inject_lockstep_mismatch(self, bad_output: int = 0xDEADBEEF,
                                        pc: int = 0x100):
        """Inject a lockstep mismatch by making checker differ from master."""
        self.dut.ls_test_valid.value = 1
        self.dut.ls_test_outputs.value = 0x00000000   # master ("correct")
        self.dut.ls_test_pc.value = pc
        self.dut.ls_test_checker_valid.value = 1
        self.dut.ls_test_checker_outputs.value = bad_output  # checker ("wrong")
        self.dut.ls_test_checker_pc.value = pc
        await RisingEdge(self.dut.sys_clk_i)
        self.dut.ls_test_valid.value = 0
        self.dut.ls_test_checker_valid.value = 0

    # =========================================================================
    # High-Level Peripheral Operations
    # =========================================================================

    async def write_speed_sensor(self, speed_value: int):
        """Write speed sensor value to peripheral register."""
        addr = self.SPEED_BASE + self.SPEED_REG
        await self.write_register(addr, speed_value & 0xFFFFFFFF)

    async def read_speed_sensor(self) -> int:
        """Read speed sensor value."""
        addr = self.SPEED_BASE + self.SPEED_REG
        return await self.read_register(addr)

    async def write_ai_weights(self, weights: list):
        """Write 4xINT8 weight registers to AI accelerator."""
        base = self.AI_ACCEL_BASE
        offsets = [self.AI_WEIGHT_0, self.AI_WEIGHT_1, self.AI_WEIGHT_2, self.AI_WEIGHT_3]
        for i, w in enumerate(weights[:4]):
            await self.write_register(base + offsets[i], w & 0xFFFFFFFF)

    async def write_ai_input(self, input_reg: int):
        """Write input activations to AI accelerator."""
        await self.write_register(self.AI_ACCEL_BASE + self.AI_INPUT, input_reg & 0xFFFFFFFF)

    async def write_ai_biases(self, bias_0_1: int, bias_2_3: int):
        """Write INT16 biases to AI accelerator."""
        await self.write_register(self.AI_ACCEL_BASE + self.AI_BIAS_0_1, bias_0_1 & 0xFFFFFFFF)
        await self.write_register(self.AI_ACCEL_BASE + self.AI_BIAS_2_3, bias_2_3 & 0xFFFFFFFF)

    async def configure_ai_activation(self, activation_fn: int, scale: int = 0x1000):
        """Configure AI activation function and scale."""
        await self.write_register(self.AI_ACCEL_BASE + self.AI_ACTIVATION, activation_fn & 0xFFFFFFFF)
        await self.write_register(self.AI_ACCEL_BASE + self.AI_SCALE, scale & 0xFFFF)

    async def trigger_ai_compute(self):
        """Trigger AI computation by writing GO bit to AI_CTRL."""
        await self.write_register(self.AI_ACCEL_BASE + self.AI_CTRL, 0x00000001)  # GO=1

    async def wait_ai_done(self, timeout_cycles: int = 1000) -> bool:
        """Wait for AI computation to complete (poll DONE bit)."""
        for _ in range(timeout_cycles):
            status = await self.read_register(self.AI_ACCEL_BASE + self.AI_CTRL)
            if (status & 0x4):  # DONE bit
                return True
            await self.wait_cycles(2)
        return False

    async def read_ai_outputs(self) -> list:
        """Read all 4 AI output registers."""
        base = self.AI_ACCEL_BASE
        offsets = [self.AI_OUTPUT_0, self.AI_OUTPUT_1, self.AI_OUTPUT_2, self.AI_OUTPUT_3]
        return [await self.read_register(base + off) for off in offsets]

    async def get_obs_signals(self) -> dict:
        """Read observation signals."""
        signals = {}
        for name in ['ai_irq_done', 'ai_irq_error', 'all_irq_lines',
                      'fault_agg_out', 'ls_mismatch_obs', 'ls_count_obs',
                      'wdt_fault_obs', 'wdt_prewarn_obs',
                      'core_halt_obs', 'force_shutdown_obs']:
            try:
                sig = getattr(self.dut, name)
                signals[name] = sig.value.integer if sig.value.is_resolvable else 0
            except Exception:
                signals[name] = 0

        # Also read GPIO-level safety outputs
        for name in ['shutdown_n_o', 'alert_n_o']:
            try:
                sig = getattr(self.dut, name)
                val = sig.value
                if hasattr(val, 'integer'):
                    signals[name] = val.integer
                elif hasattr(val, 'binstr'):
                    signals[name] = val.binstr
                else:
                    signals[name] = int(val)
            except Exception:
                signals[name] = -1
        return signals
