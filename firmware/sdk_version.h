/*
 * sdk_version.h — ADAS v2 Firmware SDK Version Tracking
 * ======================================================
 * SDK:  adas_v2_firmware_sdk
 * Arch: RV32IM (rv32im_zicsr_zifencei)
 * PDK:  sky130_fd_sc_hs
 */

#ifndef SDK_VERSION_H
#define SDK_VERSION_H

#define SDK_VERSION_MAJOR       0
#define SDK_VERSION_MINOR       1
#define SDK_VERSION_PATCH       0
#define SDK_VERSION_STRING      "adas_v2_firmware_sdk v0.1.0-dev"
#define SDK_TARGET              "RV32IM"
#define SDK_ARCH_STRING         "rv32im_zicsr_zifencei"
#define SDK_PDK                 "sky130_fd_sc_hs"
#define SDK_SYS_CLK_HZ          100000000UL
#define SDK_WDT_CLK_HZ          32768UL
#define SDK_BUILD_DATE          __DATE__
#define SDK_BUILD_TIME          __TIME__

#endif /* SDK_VERSION_H */
