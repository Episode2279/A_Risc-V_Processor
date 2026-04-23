#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stdint.h>
#include <stddef.h>   /* NULL, size_t */
#include <stdarg.h>

/* --------------------------------------------------------------------
 * CoreMark required basic types
 * -------------------------------------------------------------------- */
typedef uint8_t   ee_u8;
typedef int16_t   ee_s16;
typedef uint16_t  ee_u16;
typedef int32_t   ee_s32;
typedef uint32_t  ee_u32;
typedef int64_t   ee_s64;
typedef uint64_t  ee_u64;

/* CoreMark expects these in many drops */
typedef size_t    ee_size_t;
typedef uintptr_t ee_ptr_int;

typedef ee_u32    CORE_TICKS;

/* --------------------------------------------------------------------
 * Configuration (CoreMark “software multithread”)
 * Keep this 1 even if you have 4 hardware threads running identical code.
 * -------------------------------------------------------------------- */
#ifndef MULTITHREAD
#define MULTITHREAD 1
#endif

/* Use the standard CoreMark volatile-seed path so bare-metal simulation does
 * not depend on command-line arguments that do not exist in this environment.
 */
#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif

#ifndef MEM_METHOD
#define MEM_METHOD MEM_STATIC
#endif

#ifndef HAS_FLOAT
#define HAS_FLOAT 0
#endif

#ifndef HAS_STDIO
#define HAS_STDIO 0
#endif

#ifndef HAS_PRINTF
#define HAS_PRINTF 0
#endif

#ifndef MAIN_HAS_NORETURN
#define MAIN_HAS_NORETURN 0
#endif

/* CoreMark prints these strings */
#ifndef COMPILER_VERSION
#define COMPILER_VERSION __VERSION__
#endif

#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS "rv32i_zicsr baremetal (UART printf, cycle CSR timing)"
#endif

#ifndef MEM_LOCATION
#define MEM_LOCATION "private DMEM per thread (hw remap)"
#endif

/* Reduce iterations for simulation bring-up */
#ifndef ITERATIONS
#define ITERATIONS 1
#endif

/* Core clock used to convert the architectural mcycle/cycle counter into the
 * integer seconds API expected by this no-float CoreMark configuration.
 */
#ifndef CORE_CLOCK_HZ
#define CORE_CLOCK_HZ 100000000u
#endif

/* --------------------------------------------------------------------
 * MMIO addresses provided by coremark/link.ld
 * -------------------------------------------------------------------- */
extern ee_u8 uart_tx[];
extern ee_u8 fromhost[];
extern ee_u8 tohost[];

#define UART_TX_ADDR   ((uintptr_t)uart_tx)
#define FROMHOST_ADDR  ((uintptr_t)fromhost)
#define TOHOST_ADDR    ((uintptr_t)tohost)

/* --------------------------------------------------------------------
 * core_portable structure (must exist)
 * -------------------------------------------------------------------- */
typedef struct core_portable {
    ee_u8 portable_id;
} core_portable;

/* CoreMark uses secs_ret for time conversion */
typedef ee_u32 secs_ret;

/* --------------------------------------------------------------------
 * Required porting APIs
 * -------------------------------------------------------------------- */
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

void start_time(void);
void stop_time(void);
CORE_TICKS get_time(void);
secs_ret time_in_secs(CORE_TICKS ticks);

void *portable_malloc(ee_size_t size);
void  portable_free(void *p);
void *align_mem(void *p);

/* Output hook CoreMark calls */
int ee_printf(const char *fmt, ...);


ee_s32 get_seed_32(int i);
ee_s16 get_seed(int i);
/* Some CoreMark drops expect this symbol */
extern ee_u32 default_num_contexts;

#endif /* CORE_PORTME_H */
