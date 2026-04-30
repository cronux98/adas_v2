/*
 * CoreMark port for RV32I multi-cycle CPU simulation
 */

#ifndef CORE_PORTME_H
#define CORE_PORTME_H

/************************/
/* Data types and settings */
/************************/

/* Configuration : HAS_FLOAT
 * Define to 1 if the platform supports floating point.
 */
#ifndef HAS_FLOAT
#define HAS_FLOAT 0
#endif

/* Configuration : HAS_TIME_H
 * Define to 1 if platform has the time.h header file.
 */
#ifndef HAS_TIME_H
#define HAS_TIME_H 0
#endif

/* Configuration : USE_CLOCK
 * Define to 1 if platform has the time.h header file.
 */
#ifndef USE_CLOCK
#define USE_CLOCK 0
#endif

/* Configuration : HAS_STDIO
 * Define to 1 if the platform has stdio.h.
 */
#ifndef HAS_STDIO
#define HAS_STDIO 0
#endif

/* Configuration : HAS_PRINTF
 * Define to 1 if the platform has stdio.h and implements the printf function.
 */
#ifndef HAS_PRINTF
#define HAS_PRINTF 0
#endif

/* Definitions : COMPILER_VERSION, COMPILER_FLAGS, MEM_LOCATION
 * Initialize these strings per platform
 */
#ifndef COMPILER_VERSION
#ifdef __GNUC__
#define COMPILER_VERSION "GCC"__VERSION__
#else
#define COMPILER_VERSION "riscv64-unknown-elf-gcc"
#endif
#endif

#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS FLAGS_STR
#endif

#ifndef FLAGS_STR
#define FLAGS_STR "-march=rv32i -mabi=ilp32 -O2"
#endif

#ifndef MEM_LOCATION
#define MEM_LOCATION "STATIC"
#define HAVE_UART_SEND_CHAR 1
#endif

/* Data Types */
typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef double         ee_f32;
typedef unsigned char  ee_u8;
typedef unsigned int   ee_u32;
typedef ee_u32         ee_ptr_int;
typedef unsigned int   ee_size_t;
#define NULL ((void *)0)

/* align_mem :
 * This macro is used to align an offset to point to a 32b value.
 */
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

/* Configuration : CORE_TICKS
 * Define type of return from the timing functions.
 */
#define CORETIMETYPE ee_u32
typedef ee_u32 CORE_TICKS;

/* Timer macros */
#define GETMYTIME(_t)              (*_t = barebones_clock())
#define MYTIMEDIFF(fin, ini)       ((fin) - (ini))
#define TIMER_RES_DIVIDER          1
#define SAMPLE_TIME_IMPLEMENTATION 1
#define CLOCKS_PER_SEC             1000000
#define EE_TICKS_PER_SEC           (CLOCKS_PER_SEC / TIMER_RES_DIVIDER)

/* Configuration : SEED_METHOD
 * Defines method to get seed values that cannot be computed at compile time.
 * Valid values : SEED_ARG, SEED_FUNC, SEED_VOLATILE
 */
#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif

/* Configuration : MEM_METHOD
 * Defines method to get a block of memory.
 * Valid values : MEM_MALLOC, MEM_STATIC, MEM_STACK
 */
#ifndef MEM_METHOD
#define MEM_METHOD MEM_STATIC
#endif

/* Configuration : MULTITHREAD
 * Define for parallel execution
 */
#ifndef MULTITHREAD
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK    0
#define USE_SOCKET  0
#endif

/* Configuration : MAIN_HAS_NOARGC
 * Needed if platform does not support getting arguments to main.
 */
#ifndef MAIN_HAS_NOARGC
#define MAIN_HAS_NOARGC 1
#endif

/* Configuration : MAIN_HAS_NORETURN
 * Needed if platform does not support returning a value from main.
 */
#ifndef MAIN_HAS_NORETURN
#define MAIN_HAS_NORETURN 0
#endif

/* Iteration count: set to 1000 as default iteration count */
#ifndef ITERATIONS
#define ITERATIONS 1000
#endif

/* Performance run */
#ifndef PERFORMANCE_RUN
#define PERFORMANCE_RUN 1
#endif

/* Total data size */
#ifndef TOTAL_DATA_SIZE
#define TOTAL_DATA_SIZE 2000
#endif

/* Variable : default_num_contexts
 * Not used for this simple port, must contain the value 1.
 */
extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

/* target specific init/fini */
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

/* Provided by ee_printf.c */
int ee_printf(const char *fmt, ...);

/* Function implemented in core_portme.c */
CORETIMETYPE barebones_clock(void);
void uart_send_char(char c);

#endif /* CORE_PORTME_H */