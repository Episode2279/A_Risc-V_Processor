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

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void uart_put_unsigned(uint32_t value, uint32_t base, int width, char pad) {
    char buf[32];
    int pos = 0;

    if (value == 0) {
        buf[pos++] = '0';
    } else {
        while (value != 0) {
            uint32_t digit = value % base;
            buf[pos++] = (digit < 10u) ? (char)('0' + digit) : (char)('a' + digit - 10u);
            value /= base;
        }
    }

    while (pos < width) {
        uart_putc(pad);
        width--;
    }

    while (pos > 0) {
        uart_putc(buf[--pos]);
    }
}

static void uart_put_signed(int32_t value, int width, char pad) {
    uint32_t magnitude;

    if (value < 0) {
        uart_putc('-');
        magnitude = (uint32_t)(-(value + 1)) + 1u;
    } else {
        magnitude = (uint32_t)value;
    }

    uart_put_unsigned(magnitude, 10u, width, pad);
}

/* Small UART-backed printf for bare-metal simulation output.
 * Supports the CoreMark formats used by this port: %d, %u, %x, %s, %c,
 * optional zero padding/width such as %04x, and the ignored 'l' length flag.
 */

int ee_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);

    for (const char *p = fmt; *p; ++p) {
        int width = 0;
        char pad = ' ';
        int long_arg = 0;

        if (*p != '%') {
            if (*p == '\n') uart_putc('\r');
            uart_putc(*p);
            continue;
        }

        p++;
        if (*p == '%') {
            uart_putc('%');
            continue;
        }

        if (*p == '0') {
            pad = '0';
            p++;
        }

        while ((*p >= '0') && (*p <= '9')) {
            width = (width * 10) + (*p - '0');
            p++;
        }

        if (*p == 'l') {
            long_arg = 1;
            p++;
        }

        switch (*p) {
            case 'd':
            case 'i':
                uart_put_signed(long_arg ? (int32_t)va_arg(ap, long) : va_arg(ap, int), width, pad);
                break;
            case 'u':
                uart_put_unsigned(long_arg ? (uint32_t)va_arg(ap, unsigned long) : va_arg(ap, unsigned int),
                                  10u, width, pad);
                break;
            case 'x':
            case 'X':
                uart_put_unsigned(long_arg ? (uint32_t)va_arg(ap, unsigned long) : va_arg(ap, unsigned int),
                                  16u, width, pad);
                break;
            case 'c':
                uart_putc((char)va_arg(ap, int));
                break;
            case 's': {
                const char *s = va_arg(ap, const char *);
                uart_puts(s ? s : "(null)");
                break;
            }
            default:
                uart_putc('%');
                if (*p) uart_putc(*p);
                break;
        }
    }

    va_end(ap);
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
 * Since the hardware currently has no cycle/timer CSR, the benchmark reports a
 * fixed placeholder duration. Use the testbench cycle count for real timing.
 */
static CORE_TICKS t0 = 0, t1 = 0;

void start_time(void) { t0 = 0; t1 = 0; }
void stop_time(void)  { t1 = 10; }
CORE_TICKS get_time(void) { return (CORE_TICKS)(t1 - t0); }

secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)ticks;
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
    uart_puts("[coremark] UART online, benchmark starting\n");
    uart_puts("[coremark] Timing is a 10-second placeholder; use TB cycles for real timing\n");
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
    uart_puts("[coremark] Benchmark finished, signaling tohost=1\n");
    /* End simulation */
    mmio_write32(TOHOST_ADDR, 1u);
    for (;;) {}
}
