#include "core_portme.h"

/* CoreMark expects this global */
ee_u32 default_num_contexts = MULTITHREAD;

/* Add these seed definitions */
static ee_s32 seed1_volatile = 0x3415;
static ee_s32 seed2_volatile = 0x3415;
static ee_s32 seed3_volatile = 0x66;
static ee_s32 seed4_volatile = ITERATIONS;  /* this is the key */
static ee_s32 seed5_volatile = 0;

/* ---------------- MMIO helpers ---------------- */
static inline void mmio_write32(uintptr_t addr, uint32_t value) {
    *(volatile uint32_t *)addr = value;
}

static inline uint32_t mmio_read32(uintptr_t addr) {
    return *(volatile uint32_t *)addr;
}

static inline void uart_putc(char c) {
    mmio_write32(UART_TX_ADDR, (uint32_t)(uint8_t)c);
}

/* Very small ee_printf:
 * - prints the format string literally
 * - ignores varargs
 * Good enough for bring-up. We can add %d/%x later if you want.
 */

// int ee_printf(const char *fmt, ...) {
//     mmio_write32(TOHOST_ADDR, 0x22u);
//     for (;;) {}
// }

int ee_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    va_end(ap);

    for (const char *p = fmt; *p; ++p) {
        if (*p == '\n') uart_putc('\r');
        uart_putc(*p);
    }
    return 0;
}

/* Add this function */
ee_s32 get_seed_32(int i) {
    // if (i == 4) {
    //     mmio_write32(TOHOST_ADDR, 0x44u);
    //     for (;;) {}
    // }
    // return 0;
    switch (i) {
       case 1: return seed1_volatile;
       case 2: return seed2_volatile;
       case 3: return seed3_volatile;
       case 4: return seed4_volatile;  /* returns 1 if ITERATIONS=1 */
       case 5: return seed5_volatile;
       default: return 0;
    }
}

/* Optional: some CoreMark drops also expect this */
ee_s16 get_seed(int i) {
    return (ee_s16)get_seed_32(i);
}

/* ---------------- Timing (dummy) ----------------
 * Since you measure cycles in the testbench, we return 0 ticks.
 * CoreMark will still run+validate; the reported time is meaningless.
 */
static CORE_TICKS t0 = 0, t1 = 0;

void start_time(void) { t0 = 0; }
void stop_time(void)  { t1 = 0; }
CORE_TICKS get_time(void) { return (CORE_TICKS)(t1 - t0); }

secs_ret time_in_secs(CORE_TICKS ticks) {
    (void)ticks;
    return (secs_ret)0;
}

/* ---------------- Memory allocation ----------------
 * CoreMark uses portable_malloc/free for its working memory.
 * Implement a simple bump allocator from a static pool.
 */
#ifndef PORTABLE_HEAP_SIZE
#define PORTABLE_HEAP_SIZE (16 * 1024)  /* 16KB is enough for most default builds */
#endif

static uint8_t  portable_heap[PORTABLE_HEAP_SIZE];
static ee_size_t heap_off = 0;

void *align_mem(void *p) {
    uintptr_t x = (uintptr_t)p;
    x = (x + 7u) & ~((uintptr_t)7u); /* align to 8 bytes */
    return (void *)x;
}

void *portable_malloc(ee_size_t size) {
    /* align requested size */
    size = (size + 7u) & ~((ee_size_t)7u);

    /* align the start pointer too */
    ee_size_t off = (heap_off + 7u) & ~((ee_size_t)7u);
    if (off + size > (ee_size_t)PORTABLE_HEAP_SIZE) return NULL;

    void *p = &portable_heap[off];
    heap_off = off + size;
    return p;
}

void portable_free(void *p) {
    (void)p;
    /* bump allocator: no free */
}

/* ---------------- Init / fini ---------------- */
void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc; (void)argv;
    heap_off = 0;
    (void)mmio_read32(FROMHOST_ADDR);
    if (p) p->portable_id = 1;
}

// void portable_init(core_portable *p, int *argc, char *argv[]) {
//     (void)argc; (void)argv;
//     mmio_write32(TOHOST_ADDR, 0x11u);
//     for (;;) {}
// }

// void portable_init(core_portable *p, int *argc, char *argv[]) {
//     mmio_write32(TOHOST_ADDR, 0x11u);
//     heap_off = 0;
//     if (p) p->portable_id = 1;
// }

void portable_fini(core_portable *p) {
    (void)p;
    /* End simulation*/
    mmio_write32(TOHOST_ADDR, 1u);
    for (;;) {}
}
